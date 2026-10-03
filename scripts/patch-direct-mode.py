#!/usr/bin/env python3
"""Make Arthur's Clash Direct mode bypass ad blocking and proxy routing."""
import argparse
import json
import os

DNS_DIRECT = {"clash_mode": "direct", "action": "route",
              "server": "dns_direct", "strategy": "prefer_ipv4"}
ROUTE_DIRECT = {"clash_mode": "direct", "action": "route", "outbound": "direct"}
DNS_ENTRY = [{"inbound": "dns-in", "action": "hijack-dns"},
             {"port": 53, "action": "hijack-dns"}]


def ipv4_guard(rule):
    parts = rule.get("rules", [])
    return (rule.get("type") == "logical" and rule.get("mode") == "and"
            and rule.get("action") == "predefined" and rule.get("rcode") == "NOERROR"
            and len(parts) == 3 and "inbound" in parts[0]
            and parts[1].get("query_type") == ["AAAA", "HTTPS", "SVCB"]
            and parts[2].get("invert") is True
            and "byr.pt" in parts[2].get("domain_suffix", []))


def patch(config):
    dns, route = config["dns"], config["route"]
    servers = {s["tag"]: s for s in dns["servers"]}
    for tag in ("dns_direct", "dns-campus"):
        if servers[tag].get("type") not in ("udp", "tcp", "https"):
            raise ValueError("Existing network DNS servers are required")
        if servers[tag].get("detour", "direct") != "direct":
            raise ValueError("Direct mode must not use a proxy DNS detour")
    if not any(o.get("tag") == "direct" and o.get("type") == "direct"
               for o in config["outbounds"]):
        raise ValueError("Existing direct outbound is required")
    resolver = route.get("default_domain_resolver")
    if resolver != "dns_direct" and not (
            isinstance(resolver, dict) and resolver.get("server") == "dns_direct"):
        raise ValueError("Outbound name resolution must use the direct DNS server")

    # Recognize only the old unconditional fallback or this helper's own rule.
    # Refuse unknown Direct-mode policies instead of silently deleting them.
    old_dns = {"clash_mode": "direct", "server": "dns_direct"}
    for rules, known in ((dns["rules"], [old_dns, DNS_DIRECT]),
                         (route["rules"], [ROUTE_DIRECT])):
        if any(r.get("clash_mode") == "direct" and r not in known for r in rules):
            raise ValueError("Unrecognized Direct-mode policy")
    dns_rules = [r for r in dns["rules"] if r not in (old_dns, DNS_DIRECT)]
    route_rules = [r for r in route["rules"] if r != ROUTE_DIRECT]

    # This helper targets the existing Arthur IPv4-first/campus configuration.
    # Keep these two DNS policies, but bypass every subsequent rule in Direct.
    campus = {"domain_suffix": ["swu.edu.cn", "byr.pt"], "action": "route",
              "server": "dns-campus", "strategy": "prefer_ipv4"}
    if len(dns_rules) < 2 or not ipv4_guard(dns_rules[0]) or dns_rules[1] != campus:
        raise ValueError("Expected leading IPv4 guard and campus DNS exception")
    if route_rules[:2] != DNS_ENTRY:
        raise ValueError("Expected leading DNS interception rules")
    dns["rules"] = dns_rules[:2] + [dict(DNS_DIRECT)] + dns_rules[2:]
    # DNS-in listens on 1053, so its hijack must remain before the catch-all.
    # Other direct traffic can skip sniffing, address overrides and ad rejection.
    route["rules"] = route_rules[:2] + [dict(ROUTE_DIRECT)] + route_rules[2:]
    api = config["experimental"]["clash_api"]
    if not api.get("external_controller"):
        raise ValueError("Existing Clash API controller is required")
    api.setdefault("default_mode", "rule")
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
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        parser.exit(1, "Cannot create candidate; check configuration and output path.\n")
    print("Candidate written. Validate with singbox-install-config before restarting.")


if __name__ == "__main__":
    main()
