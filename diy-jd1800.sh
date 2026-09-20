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
exit 0
