#!/usr/local/bin/python3
"""
os-xray shared helpers: paths and atomic JSON store IO.
"""
import json
import os
import tempfile
import uuid

UI_DIR = "/usr/local/etc/xray/ui"
CONFDIR = "/usr/local/etc/xray/conf.d"
ASSET_DIR = "/usr/local/etc/xray"
XRAY_BIN = "/usr/local/bin/xray"

FILES = {
    "settings": os.path.join(UI_DIR, "settings.json"),
    "inbounds": os.path.join(UI_DIR, "inbounds.json"),
    "outbounds": os.path.join(UI_DIR, "outbounds.json"),
    "routing": os.path.join(UI_DIR, "routing.json"),
    "subscriptions": os.path.join(UI_DIR, "subscriptions.json"),
    "geosite_categories": os.path.join(UI_DIR, "geosite_categories.json"),
}


def new_uuid():
    return str(uuid.uuid4())


def load_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if data is not None else default
    except (OSError, ValueError):
        return default


def save_json(path, data):
    """Atomic write (tmp file + rename), mode 0640."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
            f.write("\n")
        os.chmod(tmp, 0o640)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def load_store(name, default):
    return load_json(FILES[name], default)


def save_store(name, data):
    save_json(FILES[name], data)
