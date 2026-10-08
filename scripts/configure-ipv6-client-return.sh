#!/bin/sh
# Install a narrowly scoped relay workaround on the current Arthur router.
# Learn LAN global IPv6 sources and route replies back to the LAN, even before
# the older odhcpd has installed the corresponding /128 in the main table.
set -eu
[ "$(id -u)" = 0 ] || { echo 'Run as root on the router.' >&2; exit 1; }
[ -f /etc/openwrt_release ] || { echo 'OpenWrt router required.' >&2; exit 1; }
init=/etc/init.d/jdc-ipv6-return
hotplug=/etc/hotplug.d/iface/98-jdc-ipv6-return
for file in "$init" "$hotplug"; do
    if [ -e "$file" ] && ! grep -q 'Managed by JDC-Arthur IPv6 client return' "$file"; then
        echo "Refusing to replace unmanaged file: $file" >&2
        exit 1
    fi
done
umask 077
cat > "$init" <<'SERVICE'
#!/bin/sh /etc/rc.common
# Managed by JDC-Arthur IPv6 client return
START=95
STOP=10

start() {
    local rules
    [ -d /sys/class/net/br-lan ] || return 1
    if [ -f /var/run/jdc-ipv6-return.state ]; then
        nft list table inet jdc_ipv6_return >/dev/null 2>&1 && return 0
        stop || return 1
    fi
    if nft list table inet jdc_ipv6_return >/dev/null 2>&1 ||
       ip -6 rule show | grep -q '^9999:' ||
       [ -n "$(ip -6 route show table 199 2>/dev/null)" ]; then
        echo 'IPv6 return table or policy priority already occupied.' >&2
        return 1
    fi
    rules=$(mktemp /tmp/jdc-ipv6-return.XXXXXX) || return 1
    cat > "$rules" <<'NFT'
table inet jdc_ipv6_return {
    set clients {
        type ipv6_addr
        flags dynamic,timeout
        timeout 1h
        size 2048
    }
    chain learn {
        type filter hook prerouting priority -151; policy accept;
        iifname "br-lan" ip6 saddr 2000::/3 update @clients { ip6 saddr timeout 1h } counter
        iifname != "br-lan" ip6 daddr @clients counter meta mark set meta mark | 0x20000000
    }
    chain reply {
        type route hook output priority -151; policy accept;
        ip6 daddr @clients counter meta mark set meta mark | 0x20000000
    }
}
NFT
    if ! nft -c -f "$rules"; then
        rm -f "$rules"
        return 1
    fi
    if ! ip -6 route add default dev br-lan table 199; then
        rm -f "$rules"
        return 1
    fi
    : > /var/run/jdc-ipv6-return.state
    if ! ip -6 rule add pref 9999 fwmark 0x20000000/0x20000000 lookup 199 ||
       ! nft -f "$rules"; then
        rm -f "$rules"
        stop
        return 1
    fi
    rm -f "$rules"
}

stop() {
    [ -f /var/run/jdc-ipv6-return.state ] || return 0
    if nft list table inet jdc_ipv6_return >/dev/null 2>&1; then
        nft delete table inet jdc_ipv6_return || return 1
    fi
    ip -6 rule del pref 9999 fwmark 0x20000000/0x20000000 lookup 199 2>/dev/null
    ip -6 route del default dev br-lan table 199 2>/dev/null
    rm -f /var/run/jdc-ipv6-return.state
}
SERVICE
cat > "$hotplug" <<'HOTPLUG'
#!/bin/sh
# Managed by JDC-Arthur IPv6 client return
case "$ACTION:$INTERFACE" in
    ifup:lan) /etc/init.d/jdc-ipv6-return restart ;;
    ifdown:lan) /etc/init.d/jdc-ipv6-return stop ;;
esac
HOTPLUG
chmod 755 "$init" "$hotplug"
"$init" start
"$init" enable
echo 'LAN IPv6 reply routing installed. WAN IPv6 and PT traffic remain enabled.'
echo 'Rollback: /etc/init.d/jdc-ipv6-return disable; /etc/init.d/jdc-ipv6-return stop'
