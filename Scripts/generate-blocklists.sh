#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Brows107/Resources/Blocklists"
mkdir -p "$OUT"
TMP=$(mktemp -d)
curl -fsSL "https://filters.adtidy.org/extension/chromium/filters/11.txt" -o "$TMP/ads.txt"
curl -fsSL "https://raw.githubusercontent.com/AdguardTeam/AdguardFilters/master/SpywareFilter/sections/tracking_servers.txt" -o "$TMP/trackers.txt"
python3 - "$TMP" "$OUT" <<'PY'
import json, os, re, sys
src, out = sys.argv[1], sys.argv[2]

HOST = re.compile(r"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,}$", re.I)
NAV_SAFE = {
    "x.com", "twitter.com", "apple.com", "google.com", "youtube.com", "reddit.com",
    "wikipedia.org", "github.com", "amazon.com", "facebook.com", "instagram.com",
    "microsoft.com", "bing.com", "duckduckgo.com", "figma.com", "cloudflare.com",
    "linkedin.com", "netflix.com", "spotify.com", "yahoo.com", "twitch.tv",
}

def domain_from_rule(line: str):
    line = line.strip()
    if not line or line.startswith("!") or not line.startswith("||"):
        return None
    body = line[2:]
    end = len(body)
    for i, ch in enumerate(body):
        if ch in "^$|/":
            end = i
            break
    d = body[:end].lower().strip(".")
    if not d or not HOST.match(d):
        return None
    if d in NAV_SAFE or d.endswith(".x.com"):
        return None
    return d

def parse_file(path):
    domains = set()
    for line in open(path, encoding="utf-8", errors="ignore"):
        d = domain_from_rule(line)
        if d:
            domains.add(d)
    return sorted(domains)

def pack(domains, chunk=40):
    rules = []
    for i in range(0, len(domains), chunk):
        rules.append({
            "trigger": {"url-filter": ".*", "if-domain": [f"*{(d[4:] if d.startswith('www.') else d)}" for d in domains[i:i + chunk]]},
            "action": {"type": "block"},
        })
    return rules

ads = parse_file(f"{src}/ads.txt")[:4000]
trackers = parse_file(f"{src}/trackers.txt")[:3500]
redirects = sorted({
    "adf.ly", "shorte.st", "adfoc.us", "linkvertise.com", "bcvc.mobi", "ouo.io",
    "publisher.linkvertise.com", "rekonise.com", "boost.ink", "shrinkearn.com",
})

for name, domains in [("ads", ads), ("trackers", trackers), ("redirects", redirects)]:
    with open(os.path.join(out, f"blocklist-{name}.json"), "w", encoding="utf-8") as f:
        json.dump(pack(domains), f, separators=(",", ":"))
    print(f"{name}: {len(domains)} domains -> {len(pack(domains))} rules")
PY
echo "Blocklists written to $OUT"
