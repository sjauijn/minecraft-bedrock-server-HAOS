#!/bin/bash
set -e

DATA_DIR="${DATA_DIR:-/data}"
CONFIG_FILE="${DATA_DIR}/config/bedrock_for_ha_config.json"
OPTIONS_FILE="${DATA_DIR}/options.json"
STOP_MARKER="${DATA_DIR}/run/bedrock_server.stopped"
VERSION_FILE="${DATA_DIR}/.installed-bds-version"

get_option() {
    local key="$1"
    if [ -f "${OPTIONS_FILE}" ]; then
        jq -r ".${key} // empty" "${OPTIONS_FILE}" 2>/dev/null || true
    fi
}

INSTALL_UPGRADE_MODE="$(get_option 'install_upgrade_server')"
case "${INSTALL_UPGRADE_MODE,,}" in
    true|1|yes|on)
        exit 0
        ;;
esac

if [ ! -f "${VERSION_FILE}" ]; then
    exit 0
fi

eula="false"
if [ -f "$CONFIG_FILE" ]; then
    eula="$(jq -r '.general.eula // false' "$CONFIG_FILE" 2>/dev/null || echo "false")"
fi

case "${eula,,}" in
    true|1|yes|on)
        if [ -f "${STOP_MARKER}" ]; then
            exit 0
        fi
        ;;
    *)
        exit 0
        ;;
esac

timeout 3s /usr/local/bin/mc-monitor status-bedrock \
    --host 127.0.0.1 \
    --port "${SERVER_PORT:-19132}" >/dev/null 2>&1 || exit 1
