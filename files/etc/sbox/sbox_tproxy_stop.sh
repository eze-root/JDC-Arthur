#!/bin/sh
# Never flush a shared route table or another application's firewall rules.
. /usr/lib/singbox/common.sh
STATE=/var/run/singbox-tproxy.state
if nft list table inet singbox_tproxy >/dev/null 2>&1; then
    nft delete table inet singbox_tproxy || exit 1
fi
if [ -f "$STATE" ]; then
    read -r MARK TABLE PRIORITY < "$STATE"
    sbox_uint "$MARK" 1 65535 && sbox_uint "$TABLE" 1 252 &&
        sbox_uint "$PRIORITY" 1 32765 || exit 1
    ip -4 rule del pref "$PRIORITY" fwmark "$MARK/0xffffffff" lookup "$TABLE" 2>/dev/null
    ip -4 route del local default dev lo table "$TABLE" 2>/dev/null
    ip -6 rule del pref "$PRIORITY" fwmark "$MARK/0xffffffff" lookup "$TABLE" 2>/dev/null
    ip -6 route del local default dev lo table "$TABLE" 2>/dev/null
    rm -f "$STATE"
fi
exit 0
