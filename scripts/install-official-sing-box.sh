#!/bin/sh
# Install the pinned SagerNet OpenWrt/musl core into a prepared firmware overlay.
set -eu

VERSION=1.13.21
ARCH=aarch64_cortex-a53
IPK="sing-box_${VERSION}_openwrt_${ARCH}.ipk"
IPK_SHA256=104e2541d4380e5bc97feae860cd2af9a1817eba2d75304c779b04a788047f6a
URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/${IPK}"

[ "$#" = 1 ] || { echo 'Usage: install-official-sing-box.sh /path/to/openwrt/files' >&2; exit 2; }
overlay=$1
[ -d "$overlay" ] || { echo 'Prepared firmware overlay does not exist' >&2; exit 1; }
[ -f "$overlay/etc/config/singbox" ] || { echo 'Refusing to add sing-box to a base overlay' >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT INT TERM
curl --fail --location --silent --show-error \
    --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 20 --max-time 300 \
    --output "$work/$IPK" "$URL"
printf '%s  %s\n' "$IPK_SHA256" "$work/$IPK" | sha256sum -c -

# SagerNet's OpenWrt IPK is an outer gzip tar containing data.tar.gz.
mkdir -p "$work/ipk" "$work/data" "$overlay/usr/bin" "$overlay/usr/share/singbox"
tar -xzf "$work/$IPK" -C "$work/ipk" data.tar.gz
tar -xzf "$work/ipk/data.tar.gz" -C "$work/data" ./usr/bin/sing-box
install -m 0755 "$work/data/usr/bin/sing-box" "$overlay/usr/bin/sing-box"
cat > "$overlay/usr/share/singbox/core-version.txt" <<EOF
source=SagerNet/sing-box
release=v$VERSION
asset=$IPK
asset_sha256=$IPK_SHA256
architecture=$ARCH
EOF
chmod 0644 "$overlay/usr/share/singbox/core-version.txt"
echo "Installed pinned SagerNet sing-box v$VERSION for OpenWrt $ARCH"
