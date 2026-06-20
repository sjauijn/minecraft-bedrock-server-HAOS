#!/bin/bash
set -e

FLASK_PORT="${FLASK_PORT:-8789}"
DATA_DIR="${DATA_DIR:-/data}"
RUNTIME_DIR="${DATA_DIR}/run"
BEDROCK_PID_FILE="${RUNTIME_DIR}/bedrock_server.pid"
STOP_MARKER="${RUNTIME_DIR}/bedrock_server.stopped"

# ─── Read HA add-on config ────────────────────────────────────────────────────
# Home Assistant writes add-on options to /data/options.json
OPTIONS_FILE="${DATA_DIR}/options.json"

get_option() {
    local key="$1"
    if [ -f "${OPTIONS_FILE}" ]; then
        jq -r ".${key} // empty" "${OPTIONS_FILE}" 2>/dev/null || true
    fi
}

INSTALL_UPGRADE_MODE="$(get_option 'install_upgrade_server')"

# ─── Install / Upgrade mode ───────────────────────────────────────────────────
case "${INSTALL_UPGRADE_MODE,,}" in
    true|1|yes|on)
        echo ""
        echo "═══════════════════════════════════════════════════════════════════"
        echo "  🔧  Minecraft Bedrock Server Software — Installing/Upgrading Mode"
        echo "═══════════════════════════════════════════════════════════════════"
        echo ""
        echo "  The add-on is running in software installation / upgrade mode."
        echo "  The Minecraft Bedrock Server will NOT be started in this mode."
        echo ""
        exec /opt/install-server.sh
        # exec replaces this process; nothing below runs after success
        ;;
esac

# ─── Normal server start ──────────────────────────────────────────────────────

start_bedrock_server() {
    echo "🎮 Starting Bedrock server..."
    mkdir -p "${RUNTIME_DIR}"
    rm -f "${STOP_MARKER}"
    /opt/bedrock-entry.sh "$@" &
    local bedrock_pid=$!
    echo "${bedrock_pid}" > "${BEDROCK_PID_FILE}"
    echo "🧭 Bedrock PID saved to ${BEDROCK_PID_FILE}"
}

cleanup_stale_pid() {
    if [[ -f "${BEDROCK_PID_FILE}" ]]; then
        local pid
        pid="$(cat "${BEDROCK_PID_FILE}" 2>/dev/null || true)"
        if [[ -n "${pid}" && ! -d "/proc/${pid}" ]]; then
            rm -f "${BEDROCK_PID_FILE}"
        fi
    fi
}

cd /opt/flask
echo "🚀 Starting Flask webserver on port ${FLASK_PORT}..."
waitress-serve --listen=0.0.0.0:${FLASK_PORT} app:app &

cd /opt/bds
start_bedrock_server "$@"

while true; do
    cleanup_stale_pid
    sleep 5
done
