#!/bin/sh

. /lib/functions.sh

config_load singbox
config_get PROXY_FWMARK main fwmark 1
config_get PROXY_ROUTE_TABLE main route_table 100

timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}

error_exit() {
    echo "$(timestamp) Error: $1" >&2
    exit "${2:-1}"
}

trap 'error_exit "Script Interrupt"' INT TERM

rm -f /etc/nftables.d/99-singbox.nft && echo "$(timestamp) Delete rule"

nft delete table inet sing-box 2>/dev/null && echo "$(timestamp) delete sing-box table"

ip rule del fwmark $PROXY_FWMARK table $PROXY_ROUTE_TABLE 2>/dev/null && echo "$(timestamp) delete rule"
ip route flush table $PROXY_ROUTE_TABLE && echo "$(timestamp) delete rule"

rm -f /tmp/sing-box/cache.db && echo "$(timestamp) clean cache"

echo "$(timestamp) Uninstall for sing-box"
