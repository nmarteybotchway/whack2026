#!/usr/bin/env python3
"""Snapshots Tesco's UK store directory into assets/tesco_stores.json.

    python3 tool/fetch_tesco_stores.py [out.json]

tesco.com's store locator sits behind Akamai, which fingerprints TLS clients
and rejects Dart's and Python's HTTP stacks (curl gets through, so this shells
out to it). Because of that, the app ships with this snapshot and picks the
nearest store locally (see TescoStoreDirectory in lib/tesco/tesco_api.dart).
Re-run this occasionally to pick up store openings/closures.
"""
import json
import subprocess
import sys
import time
import urllib.parse

URL = "https://www.tesco.com/store-locator/searchapi"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
    "Accept": "application/json",
    "Accept-Language": "en-GB,en;q=0.9",
    "Referer": "https://www.tesco.com/store-locator/",
}
PAGE = 50


def fetch_page(offset):
    # Centre of Great Britain with a radius wide enough to cover the UK.
    query = urllib.parse.urlencode(
        {"q": "54.0,-2.5", "r": "2000", "l": "en", "per": PAGE, "offset": offset}
    )
    args = ["curl", "-sS", "--fail", "--compressed", "-m", "30"]
    for name, value in HEADERS.items():
        args += ["-H", f"{name}: {value}"]
    body = subprocess.run(
        args + [f"{URL}?{query}"], check=True, capture_output=True
    ).stdout
    return json.loads(body)["response"]


def to_store(entity):
    profile = entity.get("profile", {})
    branch = profile.get("c_bRANCH_NO2")
    coordinate = profile.get("yextDisplayCoordinate") or profile.get(
        "displayCoordinate"
    )
    if not branch or not coordinate or profile.get("closed"):
        return None
    address = profile.get("address", {})
    formats = profile.get("c_sTORE_TYPE") or []
    return {
        "branchNumber": str(branch),
        "name": profile.get("c_bRANCH_NAME") or profile.get("name"),
        "format": formats[0] if formats else None,
        "address": ", ".join(
            part
            for part in (address.get("line1"), address.get("line2"), address.get("city"))
            if part
        ),
        "postcode": address.get("postalCode"),
        "latitude": round(coordinate["lat"], 6),
        "longitude": round(coordinate["long"], 6),
    }


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "assets/tesco_stores.json"
    stores = {}
    offset, total = 0, None
    while total is None or offset < total:
        page = fetch_page(offset)
        total = page["count"]
        for entity in page.get("entities", []):
            store = to_store(entity)
            if store:
                stores.setdefault(store["branchNumber"], store)
        offset += PAGE
        print(f"\r{min(offset, total)} / {total}", end="", file=sys.stderr)
        time.sleep(0.2)
    print(file=sys.stderr)
    result = sorted(stores.values(), key=lambda s: int(s["branchNumber"]))
    with open(out, "w") as f:
        json.dump(result, f, separators=(",", ":"))
    print(f"Wrote {len(result)} stores to {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
