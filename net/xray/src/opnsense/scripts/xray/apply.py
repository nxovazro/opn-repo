#!/usr/local/bin/python3
"""
os-xray apply: compile the web UI JSON stores into xray's multi-file
confdir, validate with `xray -test`, then restart the service.

Routing rules are written strictly in ascending priority order
(enabled rules only); UI-only fields (uuid/enabled/priority/name)
are stripped from the generated config.
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
    load_json,
    load_store,
    save_json,
)

UI_ONLY_RULE_FIELDS = {"uuid", "enabled", "priority", "name"}
UI_ONLY_ENDPOINT_FIELDS = {"uuid", "enabled", "from_subscription", "subscription"}


def strip_fields(obj, fields):
    return {k: v for k, v in obj.items() if k not in fields}


def build_base(settings):
    base = {}
    log = {"loglevel": settings.get("log_level", "warning")}
    if settings.get("log_access"):
        log["access"] = settings["log_access"]
    if settings.get("log_error"):
        log["error"] = settings["log_error"]
    base["log"] = log
    if settings.get("api_listen"):
        host, _, port = settings["api_listen"].rpartition(":")
        base["api"] = {"tag": "api", "services": ["HandlerService", "StatsService"]}
        base.setdefault("stats", {})
        base["inbounds"] = base.get("inbounds", [])
        base["inbounds"].append(
            {
                "tag": "api",
                "listen": host or "127.0.0.1",
                "port": int(port or 10085),
                "protocol": "dokodemo-door",
                "settings": {"address": host or "127.0.0.1"},
            }
        )
        base.setdefault("routing", {"rules": []})
        base["routing"]["rules"].append(
            {"type": "field", "inboundTag": ["api"], "outboundTag": "api"}
        )
    return base


def build_inbounds(store):
    out = []
    for item in store.get("inbounds", []):
        if not item.get("enabled", True):
            continue
        ep = strip_fields(item, UI_ONLY_ENDPOINT_FIELDS)
        out.append(ep)
    return {"inbounds": out}


def build_outbounds(store):
    out = []
    for item in store.get("outbounds", []):
        if not item.get("enabled", True):
            continue
        ep = strip_fields(item, UI_ONLY_ENDPOINT_FIELDS)
        out.append(ep)
    return {"outbounds": out}


def build_routing(store):
    rules = [r for r in store.get("rules", []) if r.get("enabled", True)]
    # priority ascending; stable for equal priority (keeps UI order)
    rules.sort(key=lambda r: (int(r.get("priority", 100)), str(r.get("name", ""))))
    cleaned = [strip_fields(r, UI_ONLY_RULE_FIELDS) for r in rules]
    routing = {"domainStrategy": store.get("domainStrategy", "IPIfNonMatch")}
    if store.get("domainMatcher"):
        routing["domainMatcher"] = store["domainMatcher"]
    routing["rules"] = cleaned
    return {"routing": routing}


def main():
    settings = load_store("settings", {})
    xray_bin = settings.get("xray_bin") or XRAY_BIN
    confdir = settings.get("confdir") or CONFDIR
    asset_dir = settings.get("asset_dir") or ASSET_DIR

    os.makedirs(confdir, exist_ok=True)

    files = {
        "00-base.json": build_base(settings),
        "10-inbounds.json": build_inbounds(load_store("inbounds", {})),
        "20-outbounds.json": build_outbounds(load_store("outbounds", {})),
        "30-routing.json": build_routing(load_store("routing", {})),
    }
    for name, data in files.items():
        save_json(os.path.join(confdir, name), data)

    # validate before touching the running service
    env = dict(os.environ)
    env["XRAY_LOCATION_ASSET"] = asset_dir
    test = subprocess.run(
        [xray_bin, "run", "-test", "-confdir", confdir],
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )
    result = {"result": "ok", "files": sorted(files.keys())}
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
