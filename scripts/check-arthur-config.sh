#!/bin/sh
# Run after make defconfig; a requested symbol may silently disappear upstream.
set -eu
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { echo 'Usage: check-arthur-config.sh CONFIG PROFILE [OVERLAY]' >&2; exit 2; }
config=$1
profile=$2
overlay=${3:-}
case "$profile" in base|singbox-ipv4|singbox-dualstack) ;; *) exit 2 ;; esac
for symbol in \
    TARGET_qualcommax TARGET_qualcommax_ipq60xx \
    TARGET_DEVICE_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01 \
    BUSYBOX_CONFIG_FEATURE_IPV6 \
    PACKAGE_block-mount PACKAGE_kmod-fs-ext4 PACKAGE_e2fsprogs \
    PACKAGE_luci-proto-ipv6 PACKAGE_luci-proto-ppp PACKAGE_odhcpd-ipv6only; do
    grep -qx "CONFIG_$symbol=y" "$config" || {
        echo "Required build option disappeared: CONFIG_$symbol=y" >&2
        exit 1
    }
done
if [ "$profile" = base ]; then
    if grep -qx 'CONFIG_PACKAGE_sing-box=y' "$config"; then
        echo 'Base profile unexpectedly contains sing-box' >&2
        exit 1
    fi
    exit 0
fi
if grep -qx 'CONFIG_PACKAGE_sing-box=y' "$config"; then
    echo 'Proxy profile must use the pinned SagerNet core, not the feeds package' >&2
    exit 1
fi
for symbol in \
    PACKAGE_ip-full PACKAGE_ss PACKAGE_ca-bundle PACKAGE_curl \
    PACKAGE_kmod-tun PACKAGE_kmod-nft-tproxy PACKAGE_kmod-nft-fib \
    PACKAGE_luci-compat PACKAGE_luci-lua-runtime; do
    grep -qx "CONFIG_$symbol=y" "$config" || {
        echo "Required proxy option disappeared: CONFIG_$symbol=y" >&2
        exit 1
    }
done
grep -Eq '^CONFIG_PACKAGE_nftables-(json|nojson)=y$' "$config" || {
    echo 'Required nftables implementation is missing (nftables-json or nftables-nojson)' >&2
    exit 1
}
[ -n "$overlay" ] && [ -s "$overlay/usr/bin/sing-box" ] || {
    echo 'Pinned official sing-box core is missing from the proxy overlay' >&2
    exit 1
}
grep -qx 'source=SagerNet/sing-box' "$overlay/usr/share/singbox/core-version.txt" &&
grep -qx 'release=v1.13.21' "$overlay/usr/share/singbox/core-version.txt" &&
grep -qx 'asset_sha256=104e2541d4380e5bc97feae860cd2af9a1817eba2d75304c779b04a788047f6a' \
    "$overlay/usr/share/singbox/core-version.txt" || {
    echo 'Official sing-box provenance metadata is missing or unexpected' >&2
    exit 1
}
