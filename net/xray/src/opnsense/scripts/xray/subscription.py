#!/usr/local/bin/python3
"""
os-xray subscription importer.

Fetches subscription URLs and converts entries into xray outbound objects:
  - vless:// / vmess:// / trojan:// / ss:// / socks:// links
  - base64-encoded lists of the above
  - raw JSON: a single outbound object or {"outbounds": [...]}

Subscription nodes are *derived data*: they are written to
ui/sub/<uuid>.json (atomic replace) and merged at apply time.
config.xml itself only stores the subscription sources. On fetch
failure the previous cache is kept untouched.

Usage:
    subscription.py --update-all [uuid]
    subscription.py --parse-file <path>   # parse share links, print {"outbounds": [...]}
"""
import argparse
import base64
import binascii
import datetime
import json
import os
import re
import sys
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from xray_lib import SUB_CACHE_DIR, load_xray_config, save_json  # noqa: E402


def b64decode_padded(s):
    s = s.strip().replace("-", "+").replace("_", "/")
    s += "=" * (-len(s) % 4)
    return base64.b64decode(s)


def safe_tag(*parts):
    tag = "-".join(str(p) for p in parts if p)
    tag = re.sub(r"[^\w\-.]+", "-", tag, flags=re.UNICODE)
    return tag[:64] or "node"


def build_stream(query, default_port=443):
    """Build streamSettings from URL query params (vless/trojan style)."""
    net = query.get("type", "tcp")
    security = query.get("security", "none")
    stream = {"network": net}
    if net == "ws":
        ws = {"path": query.get("path", "/")}
        if query.get("host"):
            ws["headers"] = {"Host": query["host"]}
        stream["wsSettings"] = ws
    elif net == "grpc":
        stream["grpcSettings"] = {"serviceName": query.get("serviceName", "")}
    elif net == "h2":
        stream["httpSettings"] = {
            "path": query.get("path", "/"),
            "host": [query["host"]] if query.get("host") else [],
        }
    elif net == "quic":
        stream["quicSettings"] = {"security": query.get("quicSecurity", "none")}
    elif net == "kcp":
        stream["kcpSettings"] = {"header": {"type": query.get("headerType", "none")}}
    elif net in ("xhttp", "splithttp"):
        stream["xhttpSettings"] = {
            "path": query.get("path", "/"),
            "host": query.get("host", ""),
            "mode": query.get("mode", "auto"),
        }
    elif net == "httpupgrade":
        stream["httpupgradeSettings"] = {
            "path": query.get("path", "/"),
            "host": query.get("host", ""),
        }
    if query.get("headerType") == "http" and net == "tcp":
        stream["tcpSettings"] = {
            "header": {
                "type": "http",
                "request": {
                    "path": [query.get("path", "/")],
                    "headers": {"Host": [query["host"]]} if query.get("host") else {},
                },
            }
        }
    if security == "tls":
        tls = {}
        if query.get("sni"):
            tls["serverName"] = query["sni"]
        if query.get("fp"):
            tls["fingerprint"] = query["fp"]
        if query.get("alpn"):
            tls["alpn"] = [a.strip() for a in query["alpn"].split(",")]
        stream["security"] = "tls"
        stream["tlsSettings"] = tls
    elif security == "reality":
        reality = {}
        if query.get("sni"):
            reality["serverName"] = query["sni"]
        if query.get("fp"):
            reality["fingerprint"] = query["fp"]
        if query.get("pbk"):
            reality["publicKey"] = query["pbk"]
        if query.get("sid"):
            reality["shortId"] = query["sid"]
        if query.get("spx"):
            reality["spiderX"] = query["spx"]
        stream["security"] = "reality"
        stream["realitySettings"] = reality
    return stream


def parse_vless(url, remark):
    p = urllib.parse.urlparse(url)
    query = dict(urllib.parse.parse_qsl(p.query))
    if not p.hostname:
        return None
    port = p.port or 443
    settings = {
        "vnext": [
            {
                "address": p.hostname,
                "port": port,
                "users": [
                    {
                        "id": p.username or "",
                        "encryption": query.get("encryption", "none"),
                        "flow": query.get("flow", ""),
                    }
                ],
            }
        ]
    }
    return {
        "protocol": "vless",
        "settings": settings,
        "streamSettings": build_stream(query),
        "remark": remark,
    }


def parse_vmess(url, remark):
    try:
        data = json.loads(b64decode_padded(url[len("vmess://") :]).decode("utf-8"))
    except (binascii.Error, ValueError, UnicodeDecodeError):
        return None
    query = {
        "type": data.get("net", "tcp"),
        "security": "tls" if str(data.get("tls", "")).lower() == "tls" else "none",
        "sni": data.get("sni", ""),
        "fp": data.get("fp", ""),
        "alpn": data.get("alpn", ""),
        "path": data.get("path", ""),
        "host": data.get("host", ""),
        "serviceName": data.get("path", "").lstrip("/"),
        "headerType": data.get("type", "none"),
    }
    try:
        port = int(data.get("port", 443))
    except (TypeError, ValueError):
        port = 443
    settings = {
        "vnext": [
            {
                "address": data.get("add", ""),
                "port": port,
                "users": [
                    {
                        "id": data.get("id", ""),
                        "alterId": int(data.get("aid", 0) or 0),
                        "security": data.get("scy", "auto"),
                    }
                ],
            }
        ]
    }
    return {
        "protocol": "vmess",
        "settings": settings,
        "streamSettings": build_stream(query),
        "remark": remark or data.get("ps", ""),
    }


def parse_trojan(url, remark):
    p = urllib.parse.urlparse(url)
    query = dict(urllib.parse.parse_qsl(p.query))
    if not p.hostname:
        return None
    if "sni" not in query and query.get("peer"):
        query["sni"] = query["peer"]
    port = p.port or 443
    settings = {
        "servers": [
            {"address": p.hostname, "port": port, "password": p.username or ""}
        ]
    }
    return {
        "protocol": "trojan",
        "settings": settings,
        "streamSettings": build_stream(query),
        "remark": remark,
    }


def parse_ss(url, remark):
    body = url[len("ss://") :]
    # strip fragment already handled by caller; body may be userinfo@host:port
    if "@" not in body:
        try:
            body = b64decode_padded(body).decode("utf-8")
        except (binascii.Error, UnicodeDecodeError):
            return None
    if "@" not in body:
        return None
    userinfo, _, hostport = body.rpartition("@")
    if ":" not in userinfo:
        try:
            userinfo = b64decode_padded(userinfo).decode("utf-8")
        except (binascii.Error, UnicodeDecodeError):
            return None
    method, _, password = userinfo.partition(":")
    host, _, port = hostport.partition(":")
    try:
        port = int(port or 8388)
    except ValueError:
        port = 8388
    settings = {
        "servers": [
            {
                "address": host,
                "port": port,
                "method": method,
                "password": password,
                "uot": False,
            }
        ]
    }
    return {"protocol": "shadowsocks", "settings": settings, "remark": remark}


def parse_socks(url, remark):
    p = urllib.parse.urlparse(url)
    if not p.hostname:
        return None
    users = []
    if p.username:
        users.append(
            {
                "user": urllib.parse.unquote(p.username),
                "pass": urllib.parse.unquote(p.password or ""),
            }
        )
    settings = {
        "servers": [
            {
                "address": p.hostname,
                "port": p.port or 1080,
                "users": users,
            }
        ]
    }
    return {"protocol": "socks", "settings": settings, "remark": remark}


PARSERS = {
    "vless://": parse_vless,
    "vmess://": parse_vmess,
    "trojan://": parse_trojan,
    "ss://": parse_ss,
    "socks://": parse_socks,
}


def split_links(text):
    """Split subscription body into candidate link lines."""
    text = text.strip()
    if not text:
        return []
    # whole-body base64?
    if "\n" not in text and re.fullmatch(r"[A-Za-z0-9+/=_-]+", text):
        try:
            decoded = b64decode_padded(text).decode("utf-8", errors="strict")
            if "://" in decoded:
                text = decoded
        except (binascii.Error, UnicodeDecodeError):
            pass
    lines = []
    for line in text.replace("\r\n", "\n").split("\n"):
        line = line.strip().strip("\"'")
        if line and "://" in line:
            lines.append(line)
    return lines


def parse_link(line):
    scheme_end = line.find("://")
    if scheme_end < 0:
        return None
    scheme = line[: scheme_end + 3].lower()
    parser = PARSERS.get(scheme)
    if not parser:
        return None
    remark = ""
    if "#" in line:
        line, _, frag = line.partition("#")
        remark = urllib.parse.unquote(frag)
    try:
        return parser(line, remark)
    except Exception:  # noqa: BLE001 - one bad link must not kill the import
        return None


def parse_body_to_outbounds(body, name_prefix="imported"):
    """Parse a subscription/share-link body into plain outbound dicts
    ({tag, protocol, settings, streamSettings})."""
    outbounds = []
    text = body.strip()
    # raw JSON?
    if text.startswith("{"):
        try:
            obj = json.loads(text)
            items = obj.get("outbounds") if isinstance(obj, dict) else None
            if items is None and isinstance(obj, dict) and obj.get("protocol"):
                items = [obj]
            if items:
                for i, ob in enumerate(items):
                    if not isinstance(ob, dict) or not ob.get("protocol"):
                        continue
                    ob = dict(ob)
                    outbounds.append(
                        {
                            "tag": safe_tag(name_prefix, ob.get("tag", i)),
                            "protocol": ob.get("protocol"),
                            "settings": ob.get("settings", {}),
                            "streamSettings": ob.get("streamSettings", {}),
                        }
                    )
                return outbounds
        except ValueError:
            pass

    for i, line in enumerate(split_links(body)):
        parsed = parse_link(line)
        if not parsed:
            continue
        tag = safe_tag(
            name_prefix, parsed.pop("remark") or "%s-%d" % (parsed["protocol"], i)
        )
        outbounds.append(
            {
                "tag": tag,
                "protocol": parsed["protocol"],
                "settings": parsed["settings"],
                "streamSettings": parsed.get("streamSettings", {}),
            }
        )
    return outbounds


def fetch(url, timeout=30):
    req = urllib.request.Request(url, headers={"User-Agent": "os-xray/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read().decode("utf-8", errors="replace")


def import_subscription(sub):
    """Fetch + parse one subscription, return (outbounds, error)."""
    try:
        body = fetch(sub["url"])
    except Exception as e:  # noqa: BLE001
        return [], "fetch failed: %s" % e
    return parse_body_to_outbounds(body, sub.get("name") or "sub"), None


def update_one(sub):
    outbounds, error = import_subscription(sub)
    now = datetime.datetime.now().isoformat(timespec="seconds")
    if error is None:
        # de-dup tags inside this subscription's own cache
        seen = set()
        for ob in outbounds:
            tag = ob.get("tag") or "node"
            base, n = tag, 2
            while tag in seen:
                tag = "%s-%d" % (base, n)
                n += 1
            seen.add(tag)
            ob["tag"] = tag
        save_json(
            os.path.join(SUB_CACHE_DIR, sub["uuid"] + ".json"),
            {"subscription": sub["uuid"], "updated": now, "outbounds": outbounds},
        )
    return {
        "uuid": sub.get("uuid"),
        "name": sub.get("name"),
        "imported": len(outbounds),
        "updated": now,
        "error": error,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--update-all", action="store_true")
    ap.add_argument("--parse-file", default=None, help="parse share links from file")
    ap.add_argument("uuid", nargs="?", default=None, help="optional subscription uuid")
    args = ap.parse_args()

    if args.parse_file:
        try:
            with open(args.parse_file, "r", encoding="utf-8") as f:
                body = f.read()
        except OSError as e:
            print(json.dumps({"result": "failed", "error": str(e)}))
            return 1
        outbounds = parse_body_to_outbounds(body)
        print(json.dumps({"result": "ok", "outbounds": outbounds}, ensure_ascii=False))
        return 0

    subs = [s for s in load_xray_config()["subscriptions"] if s.get("enabled")]
    targets = subs
    if args.uuid:
        targets = [s for s in subs if s.get("uuid") == args.uuid]
    if not targets:
        print(
            json.dumps(
                {"result": "ok", "updated": [], "note": "no enabled subscriptions"}
            )
        )
        return 0

    results = [update_one(s) for s in targets]
    failed = [r for r in results if r["error"]]
    print(
        json.dumps(
            {"result": "failed" if failed else "ok", "updated": results},
            ensure_ascii=False,
        )
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
