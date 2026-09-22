#!/usr/bin/env python3
"""Write a private candidate config; validate/install it on the router separately."""
import argparse
import ipaddress
import json
import os

TAG = "dns-wechat-local"
DOMAINS = ["qpic.cn", "qlogo.cn", "res.wx.qq.com"]


def patch(config, server):
    dns = config.get("dns")
    if not isinstance(dns, dict) or not isinstance(dns.get("servers"), list):
        raise ValueError("An existing sing-box DNS configuration is required")
    if not isinstance(dns.get("rules", []), list):
        raise ValueError("DNS rules must be an array")
    dns["servers"] = [s for s in dns["servers"] if s.get("tag") != TAG]
    dns["servers"].append({
        "type": "udp", "tag": TAG, "server": server, "server_port": 53,
    })
    rule = {
        "domain_suffix": DOMAINS, "action": "route", "server": TAG,
        "strategy": "prefer_ipv6",
    }
    # Replace only our exact rule; preserve unrelated user rules and routing.
    dns["rules"] = [rule] + [r for r in dns.get("rules", []) if r != rule]
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="Private source JSON, outside files/ and Git")
    parser.add_argument("output", help="New private candidate file; must not exist")
    parser.add_argument("--server", default="223.5.5.5", type=ipaddress.ip_address)
    args = parser.parse_args()
    try:
        with open(args.input, encoding="utf-8") as stream:
            config = patch(json.load(stream), str(args.server))
        data = json.dumps(config, ensure_ascii=False, indent=2) + "\n"
        # Never overwrite the original or expose credentials through stdout.
        fd = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(data)
    except (OSError, ValueError, TypeError, AttributeError):
        parser.exit(1, "Cannot create candidate; check input structure and output path.\n")
    print("Candidate written. Run singbox-install-config on the router to validate it.")


if __name__ == "__main__":
    main()
