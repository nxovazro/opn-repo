#!/usr/local/bin/python3
"""
os-xray geosite category extractor.

Parses geosite.dat (protobuf GeoSiteList) with a minimal dependency-free
parser and outputs the category (country_code) names. Result is cached to
/usr/local/etc/xray-ui/geosite_categories.json for the web UI dropdown.

Usage:
    geosite_list.py --json [--dat /path/to/geosite.dat]
"""
import argparse
import datetime
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from xray_lib import ASSET_DIR, save_store  # noqa: E402


class ProtoReader:
    """Minimal protobuf reader: enough to walk GeoSiteList entries."""

    def __init__(self, buf):
        self.buf = buf
        self.pos = 0

    def eof(self):
        return self.pos >= len(self.buf)

    def read_varint(self):
        shift = 0
        result = 0
        while True:
            if self.pos >= len(self.buf):
                raise ValueError("truncated varint")
            b = self.buf[self.pos]
            self.pos += 1
            result |= (b & 0x7F) << shift
            if not (b & 0x80):
                return result
            shift += 7
            if shift >= 64:
                raise ValueError("varint too long")

    def read_bytes(self, n):
        if self.pos + n > len(self.buf):
            raise ValueError("truncated bytes")
        b = self.buf[self.pos : self.pos + n]
        self.pos += n
        return b

    def skip_field(self, wire_type):
        if wire_type == 0:  # varint
            self.read_varint()
        elif wire_type == 1:  # 64-bit
            self.read_bytes(8)
        elif wire_type == 2:  # length-delimited
            self.read_bytes(self.read_varint())
        elif wire_type == 5:  # 32-bit
            self.read_bytes(4)
        else:
            raise ValueError("unsupported wire type %d" % wire_type)

    def read_message(self):
        """Yield (field_number, wire_type, raw_bytes_or_None) for each field."""
        fields = []
        while not self.eof():
            tag = self.read_varint()
            field_no, wire_type = tag >> 3, tag & 0x07
            if wire_type == 2:
                n = self.read_varint()
                fields.append((field_no, wire_type, self.read_bytes(n)))
            else:
                self.skip_field(wire_type)
                fields.append((field_no, wire_type, None))
        return fields


def extract_categories(dat_path):
    with open(dat_path, "rb") as f:
        buf = f.read()
    categories = []
    for field_no, wire_type, raw in ProtoReader(buf).read_message():
        if field_no != 1 or wire_type != 2:
            continue
        code = None
        domains = 0
        for fno, wt, fraw in ProtoReader(raw).read_message():
            if fno == 1 and wt == 2:
                code = fraw.decode("utf-8", errors="replace")
            elif fno == 2 and wt == 2:
                domains += 1
        if code:
            categories.append({"name": code, "domains": domains})
    # de-dup, keep first occurrence
    seen = {}
    for c in categories:
        seen.setdefault(c["name"], c)
    return sorted(seen.values(), key=lambda c: c["name"].lower())


def find_dat(explicit):
    candidates = []
    if explicit:
        candidates.append(explicit)
    candidates += [
        os.path.join(ASSET_DIR, "geosite.dat"),
        "/usr/local/share/xray/geosite.dat",
    ]
    for p in candidates:
        if p and os.path.isfile(p):
            return p
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--dat", default=None)
    args = ap.parse_args()

    dat = find_dat(args.dat)
    if not dat:
        result = {"result": "failed", "error": "geosite.dat not found"}
        print(json.dumps(result, ensure_ascii=False))
        return 1

    try:
        categories = extract_categories(dat)
    except Exception as e:  # noqa: BLE001 - report parse errors cleanly
        result = {"result": "failed", "error": "parse error: %s" % e}
        print(json.dumps(result, ensure_ascii=False))
        return 1

    cache = {
        "updated": datetime.datetime.now().isoformat(timespec="seconds"),
        "source": dat,
        "categories": categories,
    }
    save_store("geosite_categories", cache)

    result = {
        "result": "ok",
        "source": dat,
        "count": len(categories),
        "categories": categories,
    }
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
