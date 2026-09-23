#!/usr/bin/env python3
"""Add campus DNS exceptions without replacing the confirmed public TCP resolvers."""
import argparse
import ipaddress
import json
import os

TAG = "dns-campus"
DOMAINS = ["swu.edu.cn", "byr.pt"]


def patch(config, server):
    dns = config["dns"]
    if not isinstance(dns["servers"], list) or not isinstance(dns["rules"], list):
        raise ValueError("Existing DNS servers and rules are required")
    dns["servers"] = [s for s in dns["servers"] if s.get("tag") != TAG]
    dns["servers"].append({
        "tag": TAG, "type": "udp", "server": server, "server_port": 53,
    })
    rule = {"domain_suffix": DOMAINS, "action": "route", "server": TAG,
            "strategy": "prefer_ipv4"}
    rules = [r for r in dns["rules"] if r != rule]
    # Keep the existing client IPv4 policy ahead of these resolver exceptions.
    # byr.pt remains IPv6-capable because that policy already exempts it.
    insert_at = 0
    for i, existing in enumerate(rules):
        if (existing.get("type") == "logical"
                and existing.get("action") == "predefined"
                and existing.get("rcode") == "NOERROR"
                and any("AAAA" in r.get("query_type", [])
                        for r in existing.get("rules", []))):
            insert_at = i + 1
    rules.insert(insert_at, rule)
    dns["rules"] = rules
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input")
    parser.add_argument("output", help="New private candidate; must not exist")
    parser.add_argument("--server", default="192.0.0.33", type=ipaddress.ip_address)
    args = parser.parse_args()
    try:
        with open(args.input, encoding="utf-8") as stream:
            config = patch(json.load(stream), str(args.server))
        data = json.dumps(config, ensure_ascii=False, indent=2) + "\n"
        fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(data)
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        parser.exit(1, "Cannot create candidate; check input structure and output path.\n")
    print("Candidate written. Validate with singbox-install-config before restarting.")


if __name__ == "__main__":
    main()
