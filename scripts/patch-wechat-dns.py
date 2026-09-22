#!/usr/bin/env python3
"""Write a private candidate config; validate/install it on the router separately."""
import argparse
import ipaddress
import json
import os

TAG = "dns-wechat-local"
DOMAINS = ["qpic.cn", "qlogo.cn", "res.wx.qq.com"]
CDN_HOSTS = ["mmbiz.qpic.cn", "wx.qlogo.cn", "res.wx.qq.com", "mp.weixin.qq.com"]
DIRECT_TAG = "direct-wechat-cdn"


def patch(config, server, ipv4_first=False, ipv6_domains=(), refresh_cdn=False,
          direct_dns_tag=None, transport="udp"):
    dns = config.get("dns")
    if not isinstance(dns, dict) or not isinstance(dns.get("servers"), list):
        raise ValueError("An existing sing-box DNS configuration is required")
    if not isinstance(dns.get("rules", []), list):
        raise ValueError("DNS rules must be an array")
    if direct_dns_tag:
        direct_dns = next((s for s in dns["servers"] if s.get("tag") == direct_dns_tag), None)
        if direct_dns is None or direct_dns.get("type") not in ("udp", "tcp"):
            raise ValueError("The selected direct DNS must be an existing UDP/TCP server")
        direct_dns["type"] = transport
        direct_dns["server"] = server
        direct_dns["server_port"] = 53
    dns["servers"] = [s for s in dns["servers"] if s.get("tag") != TAG]
    dns["servers"].append({
        "type": transport, "tag": TAG, "server": server, "server_port": 53,
    })
    rule = {
        "domain_suffix": DOMAINS, "action": "route", "server": TAG,
        "strategy": "prefer_ipv4",
    }
    # Replace only our exact rule; preserve unrelated user rules and routing.
    previous_rule = dict(rule, strategy="prefer_ipv6")
    dns["rules"] = [rule] + [r for r in dns.get("rules", [])
                             if r not in (rule, previous_rule)]
    if ipv4_first:
        inbounds = [i["tag"] for i in config.get("inbounds", []) if i.get("tag")]
        if not inbounds:
            raise ValueError("Tagged client inbounds are required")
        # Scope filtering to client requests: private proxy servers may need IPv6.
        guard = {
            "type": "logical", "mode": "and", "rules": [
                {"inbound": inbounds},
                {"query_type": ["AAAA", "HTTPS", "SVCB"]},
                {"domain_suffix": sorted(set(["byr.pt", "lan", "local", "ip6.arpa"]
                                              + list(ipv6_domains))), "invert": True},
            ], "action": "predefined", "rcode": "NOERROR",
        }
        dns["strategy"] = "prefer_ipv4"
        for existing in dns["rules"]:
            if existing.get("strategy") == "prefer_ipv6":
                existing["strategy"] = "prefer_ipv4"
        def previous_guard(candidate):
            parts = candidate.get("rules", [])
            return (candidate.get("type") == "logical"
                    and candidate.get("mode") == "and"
                    and candidate.get("action") == "predefined"
                    and candidate.get("rcode") == "NOERROR"
                    and len(parts) == 3 and parts[:2] == guard["rules"][:2]
                    and parts[2].get("invert") is True
                    and set(["byr.pt", "lan", "local", "ip6.arpa"]).issubset(
                        parts[2].get("domain_suffix", [])))
        dns["rules"] = [guard] + [r for r in dns["rules"] if not previous_guard(r)]
    if refresh_cdn:
        rules = config.get("route", {}).get("rules", [])
        sniff = next((i for i, r in enumerate(rules) if r.get("action") == "sniff"), None)
        if sniff is None or not isinstance(config.get("outbounds"), list):
            raise ValueError("CDN refresh requires existing sniff rules and outbounds")
        direct = {"type": "direct", "tag": DIRECT_TAG,
                  "domain_resolver": {"server": TAG, "strategy": "ipv4_only"}}
        existing = next((o for o in config["outbounds"] if o.get("tag") == DIRECT_TAG), None)
        if existing is not None and existing != direct:
            raise ValueError("Dedicated outbound tag is already used")
        if existing is None:
            config["outbounds"].append(direct)
        overrides = [{"domain": host, "action": "route", "outbound": DIRECT_TAG,
                      "override_address": host} for host in CDN_HOSTS]
        # Preserve the exact requested hostname, port and TLS; refresh only its IP.
        rules = [r for r in rules if r not in overrides]
        sniff = next(i for i, r in enumerate(rules) if r.get("action") == "sniff")
        config["route"]["rules"] = rules[:sniff + 1] + overrides + rules[sniff + 1:]
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="Private source JSON, outside files/ and Git")
    parser.add_argument("output", help="New private candidate file; must not exist")
    parser.add_argument("--server", default="223.5.5.5", type=ipaddress.ip_address)
    parser.add_argument("--ipv4-first", action="store_true",
                        help="Suppress client AAAA/HTTPS/SVCB except IPv6 domains")
    parser.add_argument("--ipv6-domain", action="append", default=[],
                        help="Additional IPv6 exception suffix; byr.pt is always kept")
    parser.add_argument("--refresh-cdn-addresses", action="store_true",
                        help="Re-resolve known WeChat image/article hosts over direct IPv4")
    parser.add_argument("--direct-dns-tag",
                        help="Also move this existing UDP/TCP resolver to --server")
    parser.add_argument("--dns-transport", choices=["udp", "tcp"], default="udp",
                        help="Upstream transport; TCP avoids UDP packet-loss timeouts")
    args = parser.parse_args()
    try:
        with open(args.input, encoding="utf-8") as stream:
            config = patch(json.load(stream), str(args.server), args.ipv4_first,
                           args.ipv6_domain, args.refresh_cdn_addresses, args.direct_dns_tag,
                           args.dns_transport)
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
