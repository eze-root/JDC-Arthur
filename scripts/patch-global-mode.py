#!/usr/bin/env python3
"""Add Global proxy mode while retaining Arthur's campus and local access."""
import argparse
import json
import os

DNS_GLOBAL = {"clash_mode": "global", "action": "route",
              "server": "dns_proxy", "strategy": "prefer_ipv4"}
ROUTE_GLOBAL = [
    {"clash_mode": "global", "action": "sniff"},
    {"clash_mode": "global", "ip_is_private": True,
     "action": "route", "outbound": "direct"},
    {"clash_mode": "global", "domain_suffix": ["swu.edu.cn", "byr.pt"],
     "action": "route", "outbound": "direct"},
    {"clash_mode": "global", "action": "route", "outbound": "select"},
]


def patch(config):
    dns, route = config["dns"], config["route"]
    servers = {s["tag"]: s for s in dns["servers"]}
    outbounds = {o["tag"]: o for o in config["outbounds"]}
    if servers["dns_proxy"].get("detour") != "select":
        raise ValueError("Global DNS must use the existing proxy selector")
    if outbounds["select"].get("type") != "selector":
        raise ValueError("Existing select proxy group is required")
    if outbounds["direct"].get("type") != "direct":
        raise ValueError("Existing direct outbound is required")
    for rules, known in ((dns["rules"], [DNS_GLOBAL]),
                         (route["rules"], ROUTE_GLOBAL)):
        if any(r.get("clash_mode") == "global" and r not in known for r in rules):
            raise ValueError("Unrecognized Global-mode policy")
    dns_rules = [r for r in dns["rules"] if r != DNS_GLOBAL]
    route_rules = [r for r in route["rules"] if r not in ROUTE_GLOBAL]
    # Insert beside the already validated Direct-mode catchalls. This preserves
    # the preceding client IPv4 policy, DNS interception and campus DNS rule.
    dns_at = next(i for i, r in enumerate(dns_rules) if r.get("clash_mode") == "direct")
    route_at = next(i for i, r in enumerate(route_rules) if r.get("clash_mode") == "direct")
    if not any(r.get("action") == "hijack-dns" for r in route_rules[:route_at]):
        raise ValueError("DNS interception must precede mode routing")
    if not any(r.get("server") == "dns-campus" for r in dns_rules[:dns_at]):
        raise ValueError("Campus DNS exception must precede Global mode")
    dns["rules"] = dns_rules[:dns_at] + [dict(DNS_GLOBAL)] + dns_rules[dns_at:]
    route["rules"] = route_rules[:route_at] + [dict(r) for r in ROUTE_GLOBAL] + route_rules[route_at:]
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="Private existing JSON")
    parser.add_argument("output", help="New private candidate; must not exist")
    args = parser.parse_args()
    try:
        with open(args.input, encoding="utf-8") as stream:
            config = patch(json.load(stream))
        data = json.dumps(config, ensure_ascii=False, indent=2) + "\n"
        fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(data)
    except (OSError, ValueError, TypeError, KeyError, AttributeError, StopIteration):
        parser.exit(1, "Cannot create candidate; check configuration and output path.\n")
    print("Candidate written. Validate with singbox-install-config before restarting.")


if __name__ == "__main__":
    main()
