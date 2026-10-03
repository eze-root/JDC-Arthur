#!/usr/bin/env python3
"""Keep Youku playback and one Xiaohongshu API ahead of broad ad blocking."""
import argparse
import json
import os

ADS = "geosite-category-ads-all"
YOUKU_SUPPORT_HOSTS = [
    "fourier.taobao.com", "log.mmstat.com", "log-v6.mmstat.com",
    "gm.mmstat.com", "gm-v6.mmstat.com", "yt.mmstat.com", "yt-v6.mmstat.com",
    "pd.ads.cn.miaozhen.com", "yktd.m.cn.miaozhen.com",
]
MATCHES = [
    {"domain_suffix": ["youku.com", "ykimg.com"]},
    {"domain": ["edith-seb.xiaohongshu.com"]},
    # Exact support hosts observed during the successful Youku playback test.
    # Do not allow every domain of these shared analytics providers.
    {"domain": YOUKU_SUPPORT_HOSTS},
]


def ad_index(rules):
    for i, rule in enumerate(rules):
        tags = rule.get("rule_set", [])
        if tags == ADS or isinstance(tags, list) and ADS in tags:
            return i
    raise ValueError("Expected ad rule is missing")


def patch(config):
    dns, route = config["dns"], config["route"]
    if not any(s.get("tag") == "dns_direct" for s in dns["servers"]):
        raise ValueError("Existing direct DNS is required")
    if not any(o.get("tag") == "direct" and o.get("type") == "direct"
               for o in config["outbounds"]):
        raise ValueError("Existing direct outbound is required")
    dns_rules = [dict(match, action="route", server="dns_direct", strategy="prefer_ipv4")
                 for match in MATCHES]
    route_rules = [dict(match, action="route", outbound="direct") for match in MATCHES]
    # Remove only exact managed rules. Keep client AAAA filtering, sniffing,
    # campus exceptions and all unrelated privacy/routing rules in place.
    dns["rules"] = [r for r in dns["rules"] if r not in dns_rules]
    route["rules"] = [r for r in route["rules"] if r not in route_rules]
    dns_at, route_at = ad_index(dns["rules"]), ad_index(route["rules"])
    if not any(r.get("action") == "sniff" for r in route["rules"][:route_at]):
        raise ValueError("Sniff must precede the media exception")
    dns["rules"][dns_at:dns_at] = dns_rules
    route["rules"][route_at:route_at] = route_rules
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="Private existing JSON")
    parser.add_argument("output", help="New private candidate; must not exist")
    args = parser.parse_args()
    try:
        with open(args.input, encoding="utf-8") as stream:
            config = patch(json.load(stream))
        fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(config, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        parser.exit(1, "Cannot create candidate; check configuration and output path.\n")
    print("Candidate written. Validate with singbox-install-config before restarting.")


if __name__ == "__main__":
    main()
