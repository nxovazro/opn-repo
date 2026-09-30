#!/usr/local/bin/python3
"""
os-xray shared helpers: paths, atomic JSON IO, and config.xml parsing.

Configuration lives in /conf/config.xml (model OPNsense\\Xray\\Xray,
mounted at //OPNsense/xray). Subscription node caches (derived data)
live under UI_DIR/sub/<uuid>.json. The geosite category cache is still
a plain JSON file under UI_DIR.
"""
import json
import os
import tempfile
import uuid
import xml.etree.ElementTree as ET

UI_DIR = "/usr/local/etc/xray-ui"
SUB_CACHE_DIR = os.path.join(UI_DIR, "sub")
CONFDIR = "/usr/local/etc/xray-core"
# 官方 xray-core 包的资产位置（geosite.dat/geoip.dat），我们不改动
ASSET_DIR = "/usr/local/share/xray-core"
XRAY_BIN = "/usr/local/bin/xray"
CONFIG_XML = "/conf/config.xml"

GEOSITE_CATEGORIES_FILE = os.path.join(UI_DIR, "geosite_categories.json")


def new_uuid():
    return str(uuid.uuid4())


def load_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if data is not None else default
    except (OSError, ValueError):
        return default


def save_json(path, data, mode=0o640):
    """Atomic write (tmp file + rename). mode defaults to 0640."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def load_store(name, default):
    # legacy shim: only geosite_categories is still file based
    if name == "geosite_categories":
        return load_json(GEOSITE_CATEGORIES_FILE, default)
    return default


def save_store(name, data):
    if name == "geosite_categories":
        save_json(GEOSITE_CATEGORIES_FILE, data)


# ---------------------------------------------------------------------------
# config.xml parsing
# ---------------------------------------------------------------------------

def _text(parent, name, default=""):
    el = parent.find(name)
    if el is None or el.text is None:
        return default
    return el.text


def _bool(text):
    return text == "1"


def _int(text, default=0):
    try:
        return int(text)
    except (TypeError, ValueError):
        return default


def _json(text, default):
    if not text:
        return default
    try:
        data = json.loads(text)
    except ValueError:
        return default
    return data if isinstance(data, type(default)) else default


def _parse_inbound(el):
    return {
        "uuid": el.get("uuid", ""),
        "enabled": _bool(_text(el, "enabled", "1")),
        "tag": _text(el, "tag"),
        "protocol": _text(el, "protocol", "dokodemo-door"),
        "listen": _text(el, "listen", "127.0.0.1"),
        "port": _int(_text(el, "port"), 10808),
        "settings": _json(_text(el, "settings"), {}),
        "streamSettings": _json(_text(el, "streamSettings"), {}),
        "sniffing": _json(_text(el, "sniffing"), {}),
    }


def _parse_outbound(el):
    return {
        "uuid": el.get("uuid", ""),
        "enabled": _bool(_text(el, "enabled", "1")),
        "tag": _text(el, "tag"),
        "protocol": _text(el, "protocol", "freedom"),
        "settings": _json(_text(el, "settings"), {}),
        "streamSettings": _json(_text(el, "streamSettings"), {}),
    }


def _parse_subscription(el):
    return {
        "uuid": el.get("uuid", ""),
        "enabled": _bool(_text(el, "enabled", "1")),
        "name": _text(el, "name"),
        "url": _text(el, "url"),
        "last_update": _text(el, "last_update"),
        "count": _int(_text(el, "count"), 0),
    }


def _parse_rule(el):
    return {
        "uuid": el.get("uuid", ""),
        "enabled": _bool(_text(el, "enabled", "1")),
        "priority": _int(_text(el, "priority"), 100),
        "name": _text(el, "name"),
        "type": _text(el, "type", "field"),
        "domain": _json(_text(el, "domain"), []),
        "ip": _json(_text(el, "ip"), []),
        "port": _text(el, "port"),
        "network": _text(el, "network"),
        "protocol": _json(_text(el, "protocol"), []),
        "inboundTag": _json(_text(el, "inboundTag"), []),
        "source": _json(_text(el, "source"), []),
        "user": _json(_text(el, "user"), []),
        "attrs": _json(_text(el, "attrs"), {}),
        "outboundTag": _text(el, "outboundTag"),
    }


def _parse_dns_server(el):
    return {
        "uuid": el.get("uuid", ""),
        "enabled": _bool(_text(el, "enabled", "1")),
        "address": _text(el, "address"),
        "port": _int(_text(el, "port"), 53),
        "domains": _json(_text(el, "domains"), []),
        "expectIPs": _json(_text(el, "expectIPs"), []),
        "skipFallback": _bool(_text(el, "skipFallback", "0")),
    }


def load_xray_config(path=CONFIG_XML):
    """Parse /conf/config.xml, return dict with all os-xray sections."""
    cfg = {
        "general": {
            "enabled": False,
            "log_level": "warning",
            "log_access": "",
            "log_error": "",
            "api_listen": "",
            "geosite_url": "",
            "geoip_url": "",
        },
        "inbounds": [],
        "outbounds": [],
        "subscriptions": [],
        "routing": {"domainStrategy": "IPIfNonMatch", "domainMatcher": "", "rules": []},
        "dns": {
            "enabled": False,
            "listen": "127.0.0.1",
            "port": 53,
            "queryStrategy": "UseIP",
            "disableCache": False,
            "disableFallback": False,
            "clientIp": "",
            "servers": [],
        },
    }
    try:
        root = ET.parse(path).getroot()
    except (OSError, ET.ParseError):
        return cfg
    # root element is <opnsense>; MVC models live under <OPNsense> (capital O, P):
    # <opnsense><OPNsense><xray>. Fall back to direct <xray> for legacy layouts.
    x = root.find("OPNsense/xray")
    if x is None:
        x = root.find("xray")
    if x is None:
        x = root.find("opnsense/OPNsense/xray")
    if x is None:
        return cfg

    g = x.find("general")
    if g is not None:
        cfg["general"] = {
            "enabled": _bool(_text(g, "enabled", "0")),
            "log_level": _text(g, "log_level", "warning"),
            "log_access": _text(g, "log_access"),
            "log_error": _text(g, "log_error"),
            "api_listen": _text(g, "api_listen"),
            "geosite_url": _text(g, "geosite_url"),
            "geoip_url": _text(g, "geoip_url"),
        }

    ib = x.find("inbounds")
    if ib is not None:
        cfg["inbounds"] = [_parse_inbound(e) for e in ib.findall("inbound")]
    ob = x.find("outbounds")
    if ob is not None:
        cfg["outbounds"] = [_parse_outbound(e) for e in ob.findall("outbound")]
    subs = x.find("subscriptions")
    if subs is not None:
        cfg["subscriptions"] = [_parse_subscription(e) for e in subs.findall("subscription")]

    r = x.find("routing")
    if r is not None:
        cfg["routing"] = {
            "domainStrategy": _text(r, "domainStrategy", "IPIfNonMatch"),
            "domainMatcher": _text(r, "domainMatcher"),
            "rules": [_parse_rule(e) for e in r.find("rules").findall("rule")] if r.find("rules") is not None else [],
        }

    d = x.find("dns")
    if d is not None:
        servers = [_parse_dns_server(e) for e in d.find("servers").findall("server")] if d.find("servers") is not None else []
        cfg["dns"] = {
            "enabled": _bool(_text(d, "enabled", "0")),
            "listen": _text(d, "listen", "127.0.0.1"),
            "port": _int(_text(d, "port"), 53),
            "queryStrategy": _text(d, "queryStrategy", "UseIP"),
            "disableCache": _bool(_text(d, "disableCache", "0")),
            "disableFallback": _bool(_text(d, "disableFallback", "0")),
            "clientIp": _text(d, "clientIp"),
            "servers": servers,
        }
    return cfg


def load_sub_cache(sub_uuid):
    """Load derived node cache for one subscription ({} if missing)."""
    return load_json(os.path.join(SUB_CACHE_DIR, sub_uuid + ".json"), {})


def load_sub_caches(sub_uuids):
    """Load derived node caches for the given subscription uuids."""
    out = []
    for u in sub_uuids:
        data = load_sub_cache(u)
        for ob in data.get("outbounds", []):
            if isinstance(ob, dict):
                out.append(ob)
    return out
