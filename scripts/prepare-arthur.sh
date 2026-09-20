#!/bin/sh
# Run from the config repository before building. Do not copy private runtime data.
set -eu
repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
[ "$#" = 2 ] || { echo 'Usage: prepare-arthur.sh /path/to/openwrt PROFILE' >&2; exit 2; }
target=$1
profile=$2
case "$profile" in base|singbox-ipv4|singbox-dualstack) ;; *) echo 'Invalid firmware profile' >&2; exit 2 ;; esac
[ -f "$target/include/toplevel.mk" ] || { echo 'Not an OpenWrt source directory' >&2; exit 1; }

# An explicit overlay allowlist catches even ignored/untracked local files.
find "$repo/files" -type l -print | while IFS= read -r path; do
    echo "Refusing overlay symlink: $path" >&2
    exit 1
done
find "$repo/files" -type f -print | while IFS= read -r path; do
    relative=${path#"$repo/files/"}
    case "$relative" in
        etc/config/network|etc/config/firewall|etc/config/dropbear|etc/config/fstab|etc/config/singbox|\
        etc/rc.local|etc/crontabs/root|etc/sysupgrade.conf|\
        etc/init.d/frpc|etc/init.d/sing-box|etc/init.d/sing-box-update|\
        etc/uci-defaults/98-arthur-profile|etc/uci-defaults/99-singbox|\
        etc/frp-client/frp-client.sh|\
        etc/sbox/sbox_tproxy.sh|etc/sbox/sbox_tproxy_start.sh|\
        etc/sbox/sbox_tproxy_stop.sh|etc/sbox/sbox_tun.sh|\
        usr/lib/singbox/common.sh|usr/libexec/singbox-run|\
        usr/sbin/singbox-install-config|usr/sbin/singbox-install-core|\
        usr/sbin/singbox-update-config|usr/sbin/arthur-diagnose|\
        usr/share/singbox/direct-ipv4.json|usr/share/singbox/direct-dualstack.json|\
        usr/lib/lua/luci/controller/singbox.lua|usr/lib/lua/luci/model/cbi/singbox.lua) ;;
        *) echo "Unexpected overlay file (possible private data): $relative" >&2; exit 1 ;;
    esac
done
grep -Eq "^[[:space:]]*option enabled '1'$" "$repo/files/etc/config/singbox" || {
    echo 'Proxy firmware must ship with the validated direct profile enabled' >&2; exit 1;
}
if grep -Eq "^[[:space:]]*option config_url '[^']+" "$repo/files/etc/config/singbox"; then
    echo 'Private configuration URLs must not be embedded in firmware' >&2
    exit 1
fi

# A stale destination might contain private data from a previous build.
[ ! -e "$target/files" ] || {
    echo 'Destination files/ already exists; inspect it and use a clean build tree' >&2; exit 1;
}
mkdir -p "$target/files"
cp -R "$repo/files/." "$target/files/"
printf '%s\n' "$profile" > "$target/files/etc/arthur-profile"
if [ "$profile" = base ]; then
    rm -f \
        "$target/files/etc/config/singbox" \
        "$target/files/etc/init.d/sing-box" \
        "$target/files/etc/init.d/sing-box-update" \
        "$target/files/etc/uci-defaults/99-singbox" \
        "$target/files/etc/sbox/sbox_tproxy.sh" \
        "$target/files/etc/sbox/sbox_tproxy_start.sh" \
        "$target/files/etc/sbox/sbox_tproxy_stop.sh" \
        "$target/files/etc/sbox/sbox_tun.sh" \
        "$target/files/usr/lib/singbox/common.sh" \
        "$target/files/usr/libexec/singbox-run" \
        "$target/files/usr/sbin/singbox-install-config" \
        "$target/files/usr/sbin/singbox-install-core" \
        "$target/files/usr/sbin/singbox-update-config" \
        "$target/files/usr/lib/lua/luci/controller/singbox.lua" \
        "$target/files/usr/lib/lua/luci/model/cbi/singbox.lua"
    rm -rf "$target/files/usr/share/singbox"
fi
# Windows checkouts may lack executable bits or contain CRLF.
find "$target/files/etc/init.d" "$target/files/etc/sbox" \
    "$target/files/etc/uci-defaults" "$target/files/usr/libexec" \
    "$target/files/usr/sbin" -type f -exec sed -i 's/\r$//' {} \; -exec chmod 755 {} \;
find "$target/files/usr/lib/singbox" -type f -exec sed -i 's/\r$//' {} \;
echo "Public $profile overlay prepared; no private URL, JSON or runtime binary copied."
