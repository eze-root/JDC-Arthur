#!/bin/sh
# Run on the router after installing a private config with dns-in at 127.0.0.1:1053.
# Without this, DNS sent to the router's IPv6 link-local address bypasses TProxy.
set -e
. /usr/lib/singbox/common.sh
sbox_load
sbox_validate
sbox_require_storage
sbox_service_ready || { echo 'Start sing-box before configuring DNS.' >&2; exit 1; }
netstat -lnu | grep -Eq '127\.0\.0\.1:1053[[:space:]]' || {
    echo 'A sing-box DNS listener at 127.0.0.1:1053 is required.' >&2; exit 1;
}
upstream='127.0.0.1#1053'
existing=$(uci -q get 'dhcp.@dnsmasq[0].server' || true)
if [ "$existing" = "$upstream" ] &&
   [ "$(uci -q get 'dhcp.@dnsmasq[0].noresolv' || true)" = 1 ]; then
    echo 'DNS already forwards to sing-box; previous rollback backup remains valid.'
    exit 0
fi
case "$existing" in
    ''|"$upstream") ;;
    *) echo 'Existing custom DNS upstreams require manual review.' >&2; exit 1 ;;
esac
umask 077
backup_dir="$DATA_ROOT/backups"
mkdir -p "$backup_dir"
backup=$(mktemp "$backup_dir/dhcp-before-singbox-dns.XXXXXX")
cp /etc/config/dhcp "$backup"
chmod 600 "$backup"
uci set 'dhcp.@dnsmasq[0].noresolv=1'
if [ -z "$existing" ]; then
    uci add_list "dhcp.@dnsmasq[0].server=$upstream"
fi
uci commit dhcp
if ! /etc/init.d/dnsmasq restart; then
    cp "$backup" /etc/config/dhcp
    /etc/init.d/dnsmasq restart || true
    echo 'DNS restart failed; previous configuration restored.' >&2
    exit 1
fi
printf 'DNS now forwards to sing-box. Backup: %s\n' "$backup"
echo 'Restore the backup before permanently disabling sing-box.'
