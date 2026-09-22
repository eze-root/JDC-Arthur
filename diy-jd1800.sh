#!/bin/sh
# Arthur-specific source adjustments. Keep this intentionally small: packages
# come from the selected LibWrt source and its declared feeds.
set -eu

[ -f include/toplevel.mk ] || {
    echo 'diy-jd1800.sh must run from the LibWrt source root' >&2
    exit 1
}

# Do not enable ttyd passwordless root login or add public default Wi-Fi keys.
# Network/profile defaults are supplied by the reviewed files/ overlay.

# The 2024 odhcpd shipped on the router cannot discover LAN clients when its
# own WAN neighbour solicitation is the trigger (notably with IPv6 TProxy).
# Pin the reviewed upstream source containing f0d855358b86 and d402cdae4316:
# master-interface NS loopback discovery and link-local NDP probes for macOS.
odhcpd=package/network/services/odhcpd/Makefile
for field in PKG_SOURCE_DATE PKG_SOURCE_VERSION PKG_MIRROR_HASH; do
    grep -q "^$field:=" "$odhcpd" || {
        echo "Missing odhcpd source field: $field" >&2
        exit 1
    }
done
sed -i.bak \
    -e 's/^PKG_SOURCE_DATE:=.*/PKG_SOURCE_DATE:=2026-06-29/' \
    -e 's/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=5d7be43f8b9dec0eb47e245cfab81108bb131273/' \
    -e 's/^PKG_MIRROR_HASH:=.*/PKG_MIRROR_HASH:=b9bd30d14f79e34b9f3511a511ef1cd1c4541568448e91fd02ae9173f12a0b64/' \
    "$odhcpd"
rm -f "$odhcpd.bak"
exit 0
