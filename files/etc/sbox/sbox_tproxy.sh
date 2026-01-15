#!/bin/sh
# sing-box monitor

SERVICE_NAME="sing-box"
uci_get() {
    uci -q get "singbox.main.$1"
}

# Use persistent storage in /etc/sbox (JFFS2 partition)
SBOX_DIR="$(uci_get sbox_dir)"
[ -n "$SBOX_DIR" ] || SBOX_DIR="/etc/sbox"

SBOX_PATH="$(uci_get bin_path)"
[ -n "$SBOX_PATH" ] || SBOX_PATH="$SBOX_DIR/sing-box"

SBOX_CONFIG_PATH="$(uci_get config_path)"
[ -n "$SBOX_CONFIG_PATH" ] || SBOX_CONFIG_PATH="$SBOX_DIR/config.json"
SBOX_CONFIG_PATH_NEW="$SBOX_DIR/config-new.json"

# URLs to download binary/config (Leave empty to use local files only)
SBOX_URL="$(uci_get bin_url)"
SBOX_CONFIG_URL="$(uci_get config_url)"

# Network check URL (e.g. baidu.com)
CHECK_URL="$(uci_get check_url)"
[ -n "$CHECK_URL" ] || CHECK_URL="https://www.baidu.com"

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

check_network() {
    # Try to connect with a 5-second timeout
    if curl -I -s --connect-timeout 5 "$CHECK_URL" > /dev/null; then
        return 0
    else
        return 1
    fi
}

mkdir -p $SBOX_DIR

ENABLED="$(uci_get enabled)"
if [ "$ENABLED" != "1" ]; then
    if pgrep -f "${SERVICE_NAME}" > /dev/null; then
        /etc/init.d/${SERVICE_NAME} stop
    fi
    exit 0
fi

# 1. Check Network Connectivity
if ! check_network; then
    echo "$(timestamp) - Network unreachable ($CHECK_URL). Skipping $SERVICE_NAME start."
    # If network is down, we do NOT start the service, per user request.
    exit 0
fi

# 2. Update/Download Binary (If URL is set)
if [ -n "$SBOX_URL" ]; then
    echo "$(timestamp) - Checking for binary update..."
    # Download to tmp first
    if wget --no-check-certificate -T 10 -t 2 -O "/tmp/sing-box-bin" "$SBOX_URL"; then
        mv "/tmp/sing-box-bin" "$SBOX_PATH"
        chmod +x "$SBOX_PATH"
        echo "$(timestamp) - Binary updated."
    else
        echo "$(timestamp) - Failed to download binary. Using local if available."
    fi
fi

# 3. Update/Download Config (If URL is set)
if [ -n "$SBOX_CONFIG_URL" ]; then
     echo "$(timestamp) - Checking for config update..."
    if wget --no-check-certificate -T 10 -t 2 -O "$SBOX_CONFIG_PATH_NEW" "$SBOX_CONFIG_URL"; then
        mv "$SBOX_CONFIG_PATH_NEW" "$SBOX_CONFIG_PATH"
        echo "$(timestamp) - Config updated."
    else
        echo "$(timestamp) - Failed to download config. Using local if available."
    fi
fi

# 4. Check if we have what we need to start
if [ ! -f "$SBOX_PATH" ]; then
    echo "$(timestamp) - Error: $SBOX_PATH not found. Cannot start."
    exit 1
fi
if [ ! -f "$SBOX_CONFIG_PATH" ]; then
    echo "$(timestamp) - Error: $SBOX_CONFIG_PATH not found. Cannot start."
    exit 1
fi

# 5. Start or Reload Service
if ! pgrep -f "${SERVICE_NAME}" > /dev/null; then
    echo "$(timestamp) - Starting $SERVICE_NAME..."
    sh /etc/sbox/sbox_tproxy_start.sh
    /etc/init.d/${SERVICE_NAME} start
else
    # Optional: Reload logic (e.g. at 1AM)
    current_hour=$(date +%H)
    if [ "$current_hour" -ge 1 ] && [ "$current_hour" -lt 2 ]; then
        echo "$(timestamp) - Scheduled reload (1AM-2AM)."
        sh /etc/sbox/sbox_tproxy_stop.sh
        sh /etc/sbox/sbox_tproxy_start.sh
        /etc/init.d/${SERVICE_NAME} reload
    else
        echo "$(timestamp) - Service already running."
    fi
fi
