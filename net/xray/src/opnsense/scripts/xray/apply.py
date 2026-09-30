#!/usr/local/bin/python3
"""
os-xray apply: compile config.xml (//OPNsense/xray) into xray's
multi-file confdir, validate with `xray -test`, then restart the service.

- Routing rules are written strictly in ascending priority order
  (enabled rules only); Python's sort is stable so equal priorities keep
  config.xml order. UI-only fields (uuid/enabled/priority/name) are
  stripped from the generated config.
- Manual outbounds come first; nodes imported from enabled subscriptions
  (derived caches in ui/sub/<uuid>.json) are appended with safe tag
  de-duplication.
- When DNS is enabled, 40-dns.json is generated plus an automatic
  "dns-in" dokodemo-door inbound, a "dns" outbound and a first-match
  routing rule wiring dns-in to the dns outbound.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from xray_lib import (  # noqa: E402
    ASSET_DIR,
    CONFDIR,
    XRAY_BIN,
    load_sub_caches,
    load_xray_config,
    save_json,
)

UI_ONLY_RULE_FIELDS = {"uuid", "enabled", "priority", "name"}
UI_ONLY_ENDPOINT_FIELDS = {"uuid", "enabled"}
DNS_IN_TAG = "dns-in"
DNS_OUT_TAG = "dns"


def strip_fields(obj, fields):
    return {k: v for k, v in obj.items() if k not in fields}


def build_base(general):
    base = {}
    log = {"loglevel": general.get("log_level", "warning")}
    if general.get("log_access"):
        log["access"] = general["log_access"]
    if general.get("log_error"):
        log["error"] = general["log_error"]
    base["log"] = log
    if general.get("api_listen"):
        host, _, port = general["api_listen"].rpartition(":")
        base["api"] = {"tag": "api", "services": ["HandlerService", "StatsService"]}
        base.setdefault("stats", {})
        base["inbounds"] = [
            {
                "tag": "api",
                "listen": host or "127.0.0.1",
                "port": int(port or 10085),
                "protocol": "dokodemo-door",
                "settings": {"address": host or "127.0.0.1"},
            }
        ]
        base.setdefault("routing", {"rules": []})
        base["routing"]["rules"].append(
            {"type": "field", "inboundTag": ["api"], "outboundTag": "api"}
        )
    return base


def build_inbounds(inbounds):
    out = []
    for item in inbounds:
        if not item.get("enabled", True):
            continue
        ep = strip_fields(item, UI_ONLY_ENDPOINT_FIELDS)
        if not ep.get("settings"):
            ep.pop("settings", None)
        if not ep.get("streamSettings"):
            ep.pop("streamSettings", None)
        if not ep.get("sniffing"):
            ep.pop("sniffing", None)
        out.append(ep)
    return {"inbounds": out}


def build_outbounds(manual, sub_outbounds, warnings):
    """Manual outbounds first, then subscription nodes with tag de-dup."""
    out = []
    used = set()
    for item in manual:
        if not item.get("enabled", True):
            continue
        ep = strip_fields(item, UI_ONLY_ENDPOINT_FIELDS)
        if not ep.get("settings"):
            ep.pop("settings", None)
        if not ep.get("streamSettings"):
            ep.pop("streamSettings", None)
        tag = ep.get("tag") or ""
        if tag in used:
            warnings.append("duplicate manual outbound tag skipped: %s" % tag)
            continue
        used.add(tag)
        out.append(ep)
    for ob in sub_outbounds:
        if not isinstance(ob, dict) or not ob.get("protocol"):
            continue
        tag = ob.get("tag") or "sub-node"
        base, n = tag, 2
        while tag in used:
            tag = "%s-%d" % (base, n)
            n += 1
        if tag != ob.get("tag"):
            warnings.append(
                "subscription node tag renamed: %s -> %s" % (ob.get("tag"), tag)
            )
        used.add(tag)
        ep = dict(ob)
        ep["tag"] = tag
        ep.pop("uuid", None)
        ep.pop("enabled", None)
        out.append(ep)
    return {"outbounds": out}


def build_routing(routing, extra_first_rules):
    rules = [r for r in routing.get("rules", []) if r.get("enabled", True)]
    # priority ascending; stable sort keeps config.xml order on ties
    rules.sort(key=lambda r: int(r.get("priority", 100)))
    cleaned = [strip_fields(r, UI_ONLY_RULE_FIELDS) for r in rules]
    for r in cleaned:
        # drop empty matchers to keep the generated config clean
        for k in ("domain", "ip", "protocol", "inboundTag", "source", "user"):
            if not r.get(k):
                r.pop(k, None)
        if not r.get("attrs"):
            r.pop("attrs", None)
        if not r.get("port"):
            r.pop("port", None)
        if not r.get("network"):
            r.pop("network", None)
        r["type"] = "field"
    result = {"domainStrategy": routing.get("domainStrategy", "IPIfNonMatch")}
    if routing.get("domainMatcher"):
        result["domainMatcher"] = routing["domainMatcher"]
    result["rules"] = list(extra_first_rules) + cleaned
    return {"routing": result}


def build_dns(dns):
    """Return (dns_section or None, dns_inbound or None)."""
    if not dns.get("enabled"):
        return None, None
    section = {}
    servers = []
    for s in dns.get("servers", []):
        if not s.get("enabled", True):
            continue
        address = s.get("address") or ""
        if not address:
            continue
        extras = {}
        if s.get("domains"):
            extras["domains"] = s["domains"]
        if s.get("expectIPs"):
            extras["expectIPs"] = s["expectIPs"]
        if s.get("skipFallback"):
            extras["skipFallback"] = True
        port = int(s.get("port") or 53)
        if extras or port != 53:
            srv = {"address": address, "port": port}
            srv.update(extras)
            servers.append(srv)
        else:
            servers.append(address)
    section["servers"] = servers
    qs = dns.get("queryStrategy") or "UseIP"
    if qs != "UseIP":
        section["queryStrategy"] = qs
    if dns.get("disableCache"):
        section["disableCache"] = True
    if dns.get("disableFallback"):
        section["disableFallback"] = True
    if dns.get("clientIp"):
        section["clientIp"] = dns["clientIp"]

    listen = dns.get("listen") or "127.0.0.1"
    port = int(dns.get("port") or 53)
    if not servers:
        # enabled but no usable servers: write the section, skip wiring
        return section, None
    dns_inbound = {
        "tag": DNS_IN_TAG,
        "protocol": "dokodemo-door",
        "listen": listen,
        "port": port,
        "settings": {"address": listen, "port": port, "network": "tcp,udp"},
    }
    return section, dns_inbound


def main():
    cfg = load_xray_config()
    warnings = []

    os.makedirs(CONFDIR, exist_ok=True)

    dns_section, dns_inbound = build_dns(cfg["dns"])

    inbounds_doc = build_inbounds(cfg["inbounds"])

    # merge manual outbounds with enabled subscriptions' derived caches
    enabled_subs = [s["uuid"] for s in cfg["subscriptions"] if s.get("enabled") and s.get("uuid")]
    sub_outbounds = load_sub_caches(enabled_subs)
    outbounds_doc = build_outbounds(cfg["outbounds"], sub_outbounds, warnings)

    extra_rules = []
    if dns_inbound is not None:
        manual_in_tags = {i.get("tag") for i in inbounds_doc["inbounds"]}
        manual_out_tags = {o.get("tag") for o in outbounds_doc["outbounds"]}
        if DNS_IN_TAG in manual_in_tags:
            warnings.append('tag "%s" already used; automatic DNS inbound skipped' % DNS_IN_TAG)
        elif DNS_OUT_TAG in manual_out_tags:
            warnings.append('tag "%s" already used; automatic DNS outbound skipped' % DNS_OUT_TAG)
        else:
            inbounds_doc["inbounds"].append(dns_inbound)
            outbounds_doc["outbounds"].append({"tag": DNS_OUT_TAG, "protocol": "dns", "settings": {}})
            extra_rules.append(
                {"type": "field", "inboundTag": [DNS_IN_TAG], "outboundTag": DNS_OUT_TAG}
            )
    files = {
        "00-base.json": build_base(cfg["general"]),
        "10-inbounds.json": inbounds_doc,
        "20-outbounds.json": outbounds_doc,
        "30-routing.json": build_routing(cfg["routing"], extra_rules),
    }
    if dns_section is not None:
        files["40-dns.json"] = {"dns": dns_section}
    else:
        # remove a stale dns file from a previous apply
        stale = os.path.join(CONFDIR, "40-dns.json")
        if os.path.exists(stale):
            os.unlink(stale)

    for name, data in files.items():
        save_json(os.path.join(CONFDIR, name), data)

    # validate before touching the running service
    env = dict(os.environ)
    env["XRAY_LOCATION_ASSET"] = ASSET_DIR
    test = subprocess.run(
        [XRAY_BIN, "run", "-test", "-confdir", CONFDIR],
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )
    result = {"result": "ok", "files": sorted(files.keys())}
    if warnings:
        result["warnings"] = warnings
    if test.returncode != 0:
        result["result"] = "failed"
        result["error"] = (test.stderr or test.stdout or "xray -test failed").strip()[-2000:]
        print(json.dumps(result, ensure_ascii=False))
        return 1

    # restart service through rc script
    restart = subprocess.run(
        ["/usr/local/etc/rc.d/xray", "restart"],
        capture_output=True,
        text=True,
        timeout=120,
    )
    if restart.returncode != 0:
        result["result"] = "failed"
        result["error"] = (restart.stderr or restart.stdout or "restart failed").strip()[-2000:]
        print(json.dumps(result, ensure_ascii=False))
        return 1

    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
