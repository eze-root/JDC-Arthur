#!/bin/sh
# Called by singbox-run only after the core is listening.
. /usr/lib/singbox/common.sh
sbox_load
sbox_validate || exit 1
[ "$MODE" = tproxy ] || exit 0

umask 077
STATE=/var/run/singbox-tproxy.state
[ ! -e "$STATE" ] || { sbox_error 'TProxy state already exists'; exit 1; }
nft list table inet singbox_tproxy >/dev/null 2>&1 && {
    sbox_error 'TProxy table already exists'; exit 1;
}
for iface in $LAN_IFNAMES; do
    ip link show dev "$iface" >/dev/null 2>&1 || exit 1
done
# Refuse to occupy another application's policy routing resources.
if [ -n "$(ip -4 route show table "$TABLE" 2>/dev/null)" ] ||
   ip -4 rule show | grep -Eq "^$PRIORITY:|lookup $TABLE( |$)"; then
    sbox_error 'Policy table or rule priority is in use'
    exit 1
fi
if [ "$CLIENT_IPV6" = 1 ] && {
    [ -n "$(ip -6 route show table "$TABLE" 2>/dev/null)" ] ||
    ip -6 rule show | grep -Eq "^$PRIORITY:|lookup $TABLE( |$)";
}; then
    sbox_error 'IPv6 policy table or rule priority is in use'
    exit 1
fi

rules=$(mktemp /tmp/singbox-nft.XXXXXX) || exit 1
trap 'rm -f "$rules"' EXIT
interfaces=$(printf '%s\n' "$LAN_IFNAMES" | awk '{for(i=1;i<=NF;i++) printf "%s\"%s\"", (i>1?", ":""), $i}')
ipv6_rules=
if [ "$CLIENT_IPV6" = 1 ]; then
    ipv6_rules="$(cat <<EOF
        udp dport { 546, 547 } return
        ip6 daddr { ::/128, ::1/128, fc00::/7, fe80::/10, ff00::/8 } return
        meta l4proto { tcp, udp } th dport 53 tproxy ip6 to [::1]:$PORT6 meta mark set $MARK accept
        fib daddr type local return
        meta l4proto { tcp, udp } tproxy ip6 to [::1]:$PORT6 meta mark set $MARK accept
EOF
)"
else
    ipv6_rules='        meta nfproto ipv6 return'
fi
cat > "$rules" <<EOF
table inet singbox_tproxy {
    chain prerouting {
        type filter hook prerouting priority mangle; policy accept;
        iifname != { $interfaces } return
        udp dport { 67, 68 } return
        ct status dnat return
        meta nfproto ipv4 ip daddr { 0.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 224.0.0.0/4, 240.0.0.0/4 } return
        meta nfproto ipv4 fib daddr type broadcast return
        meta nfproto ipv4 meta l4proto { tcp, udp } th dport 53 tproxy ip to 127.0.0.1:$PORT meta mark set $MARK accept
        meta nfproto ipv4 fib daddr type local return
        meta nfproto ipv4 ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 100.64.0.0/10 } return
        meta nfproto ipv4 meta l4proto { tcp, udp } tproxy ip to 127.0.0.1:$PORT meta mark set $MARK accept
$ipv6_rules
    }
}
EOF
nft -c -f "$rules" || exit 1
# Save ownership before adding routes. Stop uses this even after a UCI edit.
printf '%s %s %s\n' "$MARK" "$TABLE" "$PRIORITY" > "$STATE" || exit 1
if ! ip -4 route add local default dev lo table "$TABLE" ||
   ! ip -4 rule add pref "$PRIORITY" fwmark "$MARK/0xffffffff" lookup "$TABLE"; then
    /etc/sbox/sbox_tproxy_stop.sh
    exit 1
fi
if [ "$CLIENT_IPV6" = 1 ]; then
    if ! ip -6 route add local default dev lo table "$TABLE" ||
       ! ip -6 rule add pref "$PRIORITY" fwmark "$MARK/0xffffffff" lookup "$TABLE"; then
        /etc/sbox/sbox_tproxy_stop.sh
        exit 1
    fi
fi
if ! nft -f "$rules"; then
    /etc/sbox/sbox_tproxy_stop.sh
    exit 1
fi
