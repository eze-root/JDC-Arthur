#!/bin/sh

. /lib/functions.sh

timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

error_exit() {
    echo "$(timestamp) Error: $1" >&2
    exit "${2:-1}"
}

config_load singbox
config_get TPROXY_PORT main tproxy_port 9898
config_get PROXY_FWMARK main fwmark 1
config_get PROXY_ROUTE_TABLE main route_table 100
config_get LAN_IFNAMES main lan_ifnames "br-lan"
config_get PROXY_ROUTER main proxy_router 0

LAN_IF_SET=$(printf '%s' "$LAN_IFNAMES" | awk '{for (i=1;i<=NF;i++) {printf "\"%s\"%s", $i, (i<NF?", ":"")}}')
[ -n "$LAN_IF_SET" ] || LAN_IF_SET="\"br-lan\""

OUTPUT_RULES=""
if [ "$PROXY_ROUTER" = "1" ]; then
    OUTPUT_RULES="$(cat <<EOF
        # Bypass marked traffic
        meta mark $PROXY_FWMARK accept
        # Make sure DNS work
        meta l4proto { tcp, udp } th dport 53 meta mark set $PROXY_FWMARK accept
        # Bypass local traffic
        ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16 } accept
        # Bypass DNAT
        ct status dnat accept comment "Allow forwarded traffic"
        # Mark others to Tproxy
        meta l4proto { tcp, udp } meta mark set $PROXY_FWMARK accept
EOF
)"
fi


echo "$(date) Creating firewall..."
cat > /etc/nftables.d/99-singbox.nft << EOF
#!/usr/sbin/nft -f

add table inet sing-box

# Create new chain
add chain inet sing-box prerouting { type filter hook prerouting priority mangle; policy accept; }
add chain inet sing-box output { type route hook output priority mangle; policy accept; }

# Add rules
table inet sing-box {
    chain prerouting {
        meta nfproto ipv6 accept
        iifname != { $LAN_IF_SET } accept comment "Bypass non-LAN"
        # Make sure DHCP is not filter by UDP 67/68
        udp dport { 67, 68 } accept comment "Allow DHCP traffic"
        # Make sure DNS and TProxy work
        meta l4proto { tcp, udp } th dport 53 tproxy to :$TPROXY_PORT meta mark set $PROXY_FWMARK accept comment "DNS Transparent Proxy"
        fib daddr type local meta l4proto { tcp, udp } th dport $TPROXY_PORT reject
        fib daddr type local accept
        # Bypass local Networks
        ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16 } accept
        # Bypass DNAT
        ct status dnat accept comment "Allow forwarded traffic"
        # Mark others to Tproxy
        meta l4proto { tcp, udp } tproxy to :$TPROXY_PORT meta mark set $PROXY_FWMARK accept
        meta l4proto { tcp, udp } th dport { 80, 443 } tproxy to :$TPROXY_PORT meta mark set $PROXY_FWMARK accept
    }

    chain output {
        meta nfproto ipv6 accept
$OUTPUT_RULES
    }
}
EOF

# Set privilege for nft
chmod 644 /etc/nftables.d/99-singbox.nft

# Apply firewall rules
if ! nft -f /etc/nftables.d/99-singbox.nft; then
    error_exit "Apply firewall failure"
fi

ip rule del table $PROXY_ROUTE_TABLE >/dev/null 2>&1
ip rule add fwmark $PROXY_FWMARK table $PROXY_ROUTE_TABLE

ip route flush table $PROXY_ROUTE_TABLE >/dev/null 2>&1
ip route add local default dev lo table $PROXY_ROUTE_TABLE


echo "$(date) Ready for sing-box"
