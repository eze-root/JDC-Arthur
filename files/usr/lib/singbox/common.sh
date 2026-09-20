#!/bin/sh

. "${IPKG_INSTROOT:-}/lib/functions.sh"

sbox_error() {
    echo "singbox: $*" >&2
    return 1
}

sbox_load() {
    config_load singbox
    config_get ENABLED main enabled 0
    config_get MODE main mode tproxy
    config_get CLIENT_IPV6 main client_ipv6 0
    config_get DATA_MOUNT main data_mount /mnt/mmcblk0p27
    config_get DATA_ROOT main data_root /mnt/mmcblk0p27/sing-box
    config_get DATA_DEVICE main data_device /dev/mmcblk0p27
    config_get PROG main bin_path /mnt/mmcblk0p27/sing-box/bin/sing-box
    config_get PACKAGED_PROG main packaged_bin /usr/bin/sing-box
    config_get CONF main config_path /mnt/mmcblk0p27/sing-box/config/config.json
    config_get DIRECT_CONF main direct_config /usr/share/singbox/direct-ipv4.json
    config_get WORKDIR main sbox_dir /mnt/mmcblk0p27/sing-box/state
    config_get PORT main tproxy_port 9898
    config_get PORT6 main tproxy_port6 9899
    config_get MARK main fwmark 100
    config_get TABLE main route_table 100
    config_get PRIORITY main rule_priority 10000
    config_get LAN_IFNAMES main lan_ifnames br-lan
    config_get RESPAWN_TIMEOUT main respawn_timeout 30
    config_get CONFIG_URL main config_url
    config_get UPDATE_ON_BOOT main update_on_boot 1
    config_get UPDATE_RETRIES main update_retries 6
    config_get UPDATE_RETRY_DELAY main update_retry_delay 30
    config_get DOWNLOAD_TIMEOUT main download_timeout 30
    config_get MAX_CONFIG_BYTES main max_config_bytes 4194304
    config_get PROXY_ROUTER main proxy_router 0
}

sbox_uint() {
    case "$1" in ''|*[!0-9]*|0[0-9]*) return 1 ;; esac
    [ "${#1}" -le 9 ] && [ "$1" -ge "$2" ] && [ "$1" -le "$3" ]
}

sbox_validate() {
    case "$ENABLED" in 0|1) ;; *) sbox_error 'Invalid enabled flag'; return 1 ;; esac
    case "$MODE" in tproxy|tun) ;; *) sbox_error 'Mode must be tproxy or tun'; return 1 ;; esac
    case "$CLIENT_IPV6" in 0|1) ;; *) sbox_error 'Invalid client_ipv6 flag'; return 1 ;; esac
    case "$UPDATE_ON_BOOT" in 0|1) ;; *) sbox_error 'Invalid update_on_boot flag'; return 1 ;; esac
    local path iface
    for path in "$DATA_MOUNT" "$DATA_ROOT" "$DATA_DEVICE" "$PROG" "$PACKAGED_PROG" "$CONF" "$DIRECT_CONF" "$WORKDIR"; do
        case "$path" in /*) ;; *) sbox_error 'Paths must be absolute'; return 1 ;; esac
        case "$path" in *'
'*) sbox_error 'Paths must not contain newlines'; return 1 ;; esac
    done
    case "$DATA_ROOT" in "$DATA_MOUNT"/*) ;; *) sbox_error 'Data root must be below data_mount'; return 1 ;; esac
    case "$PROG" in "$DATA_ROOT"/*) ;; *) sbox_error 'Binary path must be below data_root'; return 1 ;; esac
    case "$CONF" in "$DATA_ROOT"/*) ;; *) sbox_error 'Config path must be below data_root'; return 1 ;; esac
    case "$WORKDIR" in "$DATA_ROOT"/*) ;; *) sbox_error 'Working directory must be below data_root'; return 1 ;; esac
    sbox_uint "$RESPAWN_TIMEOUT" 5 3600 || { sbox_error 'Restart delay must be 5..3600 seconds'; return 1; }
    sbox_uint "$UPDATE_RETRIES" 1 60 || { sbox_error 'Update retries must be 1..60'; return 1; }
    sbox_uint "$UPDATE_RETRY_DELAY" 5 3600 || { sbox_error 'Update retry delay must be 5..3600 seconds'; return 1; }
    sbox_uint "$DOWNLOAD_TIMEOUT" 5 600 || { sbox_error 'Download timeout must be 5..600 seconds'; return 1; }
    sbox_uint "$MAX_CONFIG_BYTES" 1024 16777216 || { sbox_error 'Config size limit must be 1024..16777216 bytes'; return 1; }
    case "$CONFIG_URL" in
        '') ;;
        https://*) case "$CONFIG_URL" in *'
'*) sbox_error 'Config URL must not contain newlines'; return 1 ;; esac ;;
        *) sbox_error 'Config URL must use HTTPS'; return 1 ;;
    esac
    [ "$MODE" = tproxy ] || return 0
    [ "$PROXY_ROUTER" = 0 ] || { sbox_error 'Legacy proxy_router is unsupported; use TUN auto_redirect'; return 1; }
    sbox_uint "$PORT" 1024 65535 && sbox_uint "$PORT6" 1024 65535 &&
        [ "$PORT" != "$PORT6" ] && sbox_uint "$MARK" 1 65535 &&
        sbox_uint "$TABLE" 1 252 && sbox_uint "$PRIORITY" 1 32765 || {
        sbox_error 'Invalid or duplicate TProxy ports, mark, table (1..252) or rule priority'; return 1;
    }
    [ -n "$LAN_IFNAMES" ] || { sbox_error 'At least one LAN interface is required'; return 1; }
    case "$LAN_IFNAMES" in *[!a-zA-Z0-9_.:[:space:]-]*) sbox_error 'Invalid LAN interface list'; return 1 ;; esac
    for iface in $LAN_IFNAMES; do
        case "$iface" in *[!a-zA-Z0-9_.:-]*|lo|wan|wan6) sbox_error 'Invalid LAN interface'; return 1 ;; esac
        [ "${#iface}" -le 15 ] || return 1
    done
}

sbox_mount_source() {
    awk -v target="$DATA_MOUNT" '$2 == target { print $1; exit }' /proc/mounts
}

sbox_require_storage() {
    local mountpoint source
    mountpoint=$DATA_MOUNT
    source=$(sbox_mount_source)
    [ "$source" = "$DATA_DEVICE" ] || {
        sbox_error "Data volume $DATA_DEVICE is not mounted at $mountpoint"
        return 1
    }
    awk -v source="$DATA_DEVICE" -v target="$mountpoint" '
        $1 == source && $2 == target && $3 == "ext4" && $4 ~ /(^|,)rw(,|$)/ { found=1 }
        END { exit !found }
    ' /proc/mounts || { sbox_error 'Data volume must be a writable ext4 mount'; return 1; }
}

sbox_install_file() {
    local source=$1 destination=$2 mode=$3 pending
    mkdir -p "$(dirname "$destination")" || return 1
    pending=$(mktemp "$(dirname "$destination")/.install.XXXXXX") || return 1
    if ! cp "$source" "$pending" || ! chmod "$mode" "$pending" || ! mv -f "$pending" "$destination"; then
        rm -f "$pending"
        return 1
    fi
}

sbox_prepare_storage() {
    sbox_require_storage || return 1
    umask 077
    mkdir -p "$DATA_ROOT/bin" "$DATA_ROOT/config" "$WORKDIR" || return 1
    if [ ! -x "$PROG" ]; then
        [ -x "$PACKAGED_PROG" ] || { sbox_error 'Packaged sing-box core is missing'; return 1; }
        sbox_install_file "$PACKAGED_PROG" "$PROG" 755 || return 1
    fi
    "$PROG" version >/dev/null 2>&1 || { sbox_error 'Installed core cannot run'; return 1; }
    if [ -s "$CONF" ]; then
        # A profile change may select the other public direct template. Replace
        # only a known bundled default; never overwrite a private configuration.
        local known
        for known in /usr/share/singbox/direct-ipv4.json /usr/share/singbox/direct-dualstack.json; do
            if [ -s "$known" ] && cmp -s "$CONF" "$known"; then
                cmp -s "$CONF" "$DIRECT_CONF" || sbox_install_file "$DIRECT_CONF" "$CONF" 600 || return 1
                break
            fi
        done
    else
        [ -s "$DIRECT_CONF" ] || { sbox_error 'Default direct configuration is missing'; return 1; }
        sbox_install_file "$DIRECT_CONF" "$CONF" 600 || return 1
    fi
}

sbox_check() {
    sbox_prepare_storage || return 1
    [ -x "$PROG" ] || { sbox_error 'Binary missing or not executable'; return 1; }
    [ -s "$CONF" ] || { sbox_error 'Local configuration missing or empty'; return 1; }
    umask 077
    mkdir -p "$WORKDIR" || return 1
    # Parser errors can include private values: do not send them to syslog.
    "$PROG" check -D "$WORKDIR" -c "$CONF" >/dev/null 2>&1 || {
        sbox_error 'Configuration check failed; run sing-box check locally for details'; return 1;
    }
}

sbox_service_ready() {
    /etc/init.d/sing-box status >/dev/null 2>&1 || return 1
    [ "$MODE" != tproxy ] || {
        [ -s /var/run/singbox-tproxy.state ] &&
            nft list table inet singbox_tproxy >/dev/null 2>&1
    }
}
