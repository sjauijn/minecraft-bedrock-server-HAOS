#!/bin/bash
set -e

FLASK_PORT="${FLASK_PORT:-8789}"
DATA_DIR="${DATA_DIR:-/data}"
RUNTIME_DIR="${DATA_DIR}/run"
BEDROCK_PID_FILE="${RUNTIME_DIR}/bedrock_server.pid"
STOP_MARKER="${RUNTIME_DIR}/bedrock_server.stopped"
OPTIONS_FILE="${DATA_DIR}/options.json"
VERSION_FILE="${DATA_DIR}/.installed-bds-version"

get_option() {
    local key="$1"
    if [ -f "${OPTIONS_FILE}" ]; then
        jq -r ".${key} // empty" "${OPTIONS_FILE}" 2>/dev/null || true
    fi
}

INSTALL_UPGRADE_MODE="$(get_option 'install_upgrade_server')"
ALLOW_DOWNGRADE="$(get_option 'allow_downgrade')"

# ─── Guard: allow_downgrade=true requires install_upgrade_server=true ─────────
case "${ALLOW_DOWNGRADE,,}" in
    true|1|yes|on)
        case "${INSTALL_UPGRADE_MODE,,}" in
            true|1|yes|on)
                # OK — downgrade mode handled inside install-server.sh
                ;;
            *)
                echo ""
                echo "╔══════════════════════════════════════════════════════════════════════╗"
                echo "║                                                                      ║"
                echo "║   🚫  CONFIGURATION ERROR — ADD-ON WILL NOT START                   ║"
                echo "║                                                                      ║"
                echo "║   'Allow Downgrade' is set to  true  but                            ║"
                echo "║   'Installing/Upgrading Server' is set to  false.                  ║"
                echo "║                                                                      ║"
                echo "║   Running the server with 'Allow Downgrade' enabled is dangerous.  ║"
                echo "║   Please disable it first:                                          ║"
                echo "║                                                                      ║"
                echo "║     ➜  In the add-on Configuration, set                            ║"
                echo "║        ┌──────────────────────┐                                     ║"
                echo "║        │  Allow Downgrade: false  │                                 ║"
                echo "║        └──────────────────────┘                                     ║"
                echo "║     ➜  Restart the add-on.                                          ║"
                echo "║                                                                      ║"
                echo "╚══════════════════════════════════════════════════════════════════════╝"
                echo ""
                exit 1
                ;;
        esac
        ;;
esac

# ─── Install / Upgrade mode ───────────────────────────────────────────────────
case "${INSTALL_UPGRADE_MODE,,}" in
    true|1|yes|on)
        echo ""
        echo "═══════════════════════════════════════════════════════════════════════"
        echo "  🔧  Minecraft Bedrock Server Software — Installing / Upgrading Mode"
        echo "═══════════════════════════════════════════════════════════════════════"
        echo ""
        echo "  The add-on is running in software installation / upgrade mode."
        echo "  The Minecraft Bedrock Server will NOT be started in this mode."
        echo ""
        exec env ALLOW_DOWNGRADE="${ALLOW_DOWNGRADE}" /opt/install-server.sh
        ;;
esac

# ─── Normal server mode: guard against missing software ──────────────────────
if [ ! -f "${VERSION_FILE}" ]; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║  ❌  Minecraft Bedrock Server software is not installed yet.         ║"
    echo "║                                                                      ║"
    echo "║  In the add-on Configuration, set:                                  ║"
    echo "║     Installing/Upgrading Server: true                               ║"
    echo "║  and restart the add-on to enter installation mode.                 ║"
    echo "║                                                                      ║"
    echo "║  Then upload bedrock-server-*.zip to:                               ║"
    echo "║     📂  addon_configs/<this-addon>/bedrock-server-software/         ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""
    # Keep container alive so HA doesn't restart-loop; user needs to change config
    tail -f /dev/null
fi

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

start_bedrock_server "$@"

while true; do
    cleanup_stale_pid
    sleep 5
done
