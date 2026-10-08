#!/bin/sh
# Add a separate trusted IPv4-only SSID; never print or embed the existing PSK.
set -eu
[ "$(id -u)" = 0 ] && [ -f /etc/openwrt_release ] || {
    echo 'Run as root on the Arthur router.' >&2; exit 1;
}
[ -z "$(uci changes)" ] || { echo 'Commit or revert pending UCI changes first.' >&2; exit 1; }
grep -qs ' /mnt/mmcblk0p27 ' /proc/mounts || { echo 'Data partition is not mounted.' >&2; exit 1; }
ssid=${1:-$(uci -q get wireless.default_radio0.ssid)-IPv4}
[ -n "$ssid" ] && [ "${#ssid}" -le 32 ] || { echo 'Invalid SSID.' >&2; exit 1; }
for radio in radio0 radio1; do
    [ "$(uci -q get wireless.default_$radio.mode)" = ap ] || exit 1
    [ -n "$(uci -q get wireless.default_$radio.key)" ] || exit 1
done
lan_zone=$(uci show firewall | sed -n "s/^\(firewall\.[^.]*\)\.name='lan'$/\1/p")
[ -n "$lan_zone" ] || { echo 'Existing LAN firewall zone required.' >&2; exit 1; }
for section in network.jdc_wifi4 network.jdc_wifi4_dev dhcp.jdc_wifi4 \
               wireless.jdc_wifi4_radio0 wireless.jdc_wifi4_radio1; do
    if uci -q get "$section" >/dev/null &&
       [ "$(uci -q get "$section.jdc_managed")" != ipv4-wifi-v1 ]; then
        echo "Section already occupied: $section" >&2; exit 1
    fi
done
if ip -4 route show | grep -q '^192\.168\.14\.0/24 ' &&
   [ "$(uci -q get network.jdc_wifi4.jdc_managed)" != ipv4-wifi-v1 ]; then
    echo '192.168.14.0/24 is already in use.' >&2; exit 1
fi
umask 077
backup=/mnt/mmcblk0p27/sing-box/backup-ipv4-wifi-$(date +%Y%m%d-%H%M%S)
mkdir -p "$backup"
for package in network wireless dhcp firewall singbox; do
    cp "/etc/config/$package" "$backup/$package"
    chmod 600 "$backup/$package"
done
rollback() {
    echo "Setup failed; restoring configuration from $backup" >&2
    for package in network wireless dhcp firewall singbox; do
        uci -q revert "$package" || true
        cp "$backup/$package" "/etc/config/$package"
    done
    ubus call network reload >/dev/null 2>&1 || true
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
    /etc/init.d/odhcpd reload >/dev/null 2>&1 || true
    /etc/init.d/firewall reload >/dev/null 2>&1 || true
    /etc/init.d/sing-box restart >/dev/null 2>&1 || true
    wifi reload >/dev/null 2>&1 || true
}
trap rollback EXIT
trap 'exit 1' HUP INT TERM

uci set network.jdc_wifi4_dev=device
uci set network.jdc_wifi4_dev.jdc_managed=ipv4-wifi-v1
uci set network.jdc_wifi4_dev.name=br-wifi4
uci set network.jdc_wifi4_dev.type=bridge
uci set network.jdc_wifi4_dev.bridge_empty=1
uci set network.jdc_wifi4_dev.ipv6=0
uci set network.jdc_wifi4=interface
uci set network.jdc_wifi4.jdc_managed=ipv4-wifi-v1
uci set network.jdc_wifi4.device=br-wifi4
uci set network.jdc_wifi4.proto=static
uci set network.jdc_wifi4.ipaddr=192.168.14.1
uci set network.jdc_wifi4.netmask=255.255.255.0
uci set network.jdc_wifi4.delegate=0
uci set network.jdc_wifi4.ipv6=0
uci set dhcp.jdc_wifi4=dhcp
uci set dhcp.jdc_wifi4.jdc_managed=ipv4-wifi-v1
uci set dhcp.jdc_wifi4.interface=jdc_wifi4
uci set dhcp.jdc_wifi4.start=100
uci set dhcp.jdc_wifi4.limit=150
uci set dhcp.jdc_wifi4.leasetime=12h
uci set dhcp.jdc_wifi4.ra=disabled
uci set dhcp.jdc_wifi4.dhcpv6=disabled
uci set dhcp.jdc_wifi4.ndp=disabled
for radio in radio0 radio1; do
    section=wireless.jdc_wifi4_$radio
    uci set "$section=wifi-iface"
    uci set "$section.jdc_managed=ipv4-wifi-v1"
    uci set "$section.device=$radio"
    uci set "$section.mode=ap"
    uci set "$section.network=jdc_wifi4"
    uci set "$section.ssid=$ssid"
    uci set "$section.encryption=$(uci -q get wireless.default_$radio.encryption)"
    uci set "$section.key=$(uci -q get wireless.default_$radio.key)"
    uci set "$section.disabled=0"
done
case " $(uci -q get "$lan_zone.network") " in
    *' jdc_wifi4 '*) ;;
    *) uci add_list "$lan_zone.network=jdc_wifi4" ;;
esac
interfaces=$(uci -q get singbox.main.lan_ifnames)
case " $interfaces " in
    *' br-wifi4 '*) ;;
    *) uci set "singbox.main.lan_ifnames=$interfaces br-wifi4" ;;
esac
fw4 check >/dev/null
for package in network wireless dhcp firewall singbox; do uci commit "$package"; done
ubus call network reload >/dev/null
/etc/init.d/dnsmasq restart
/etc/init.d/odhcpd reload
/etc/init.d/firewall reload
/etc/init.d/sing-box restart
wifi reload
attempt=0
until ip -4 addr show dev br-wifi4 2>/dev/null | grep -q '192.168.14.1/24'; do
    attempt=$((attempt + 1)); [ "$attempt" -lt 15 ] || exit 1
    sleep 1
done
[ "$(cat /proc/sys/net/ipv6/conf/br-wifi4/disable_ipv6)" = 1 ]
trap - EXIT HUP INT TERM
echo "Created $ssid on both radios; gateway 192.168.14.1; IPv6 disabled."
echo "Private backup: $backup"
