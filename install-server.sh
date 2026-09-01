#!/bin/bash

set -eo pipefail

readonly DATA_DIR="${DATA_DIR:-/data}"
readonly CONFIG_DIR="/config"
readonly SOFTWARE_DIR="${CONFIG_DIR}/bedrock-server-software"
readonly BIN_DIR="${DATA_DIR}/bds"
readonly VERSION_FILE="${DATA_DIR}/.installed-bds-version"

log()      { echo "$*"; }
log_info() { echo "  ℹ️  $*"; }
log_ok()   { echo "  ✅ $*"; }
log_warn() { echo "  ⚠️  $*"; }
log_err()  { echo "  ❌ $*"; }

version_gt() {
    [[ "$1" == "$2" ]] && return 1
    local IFS=.
    local i ver1=($1) ver2=($2)
    for (( i=0; i<${#ver1[@]} || i<${#ver2[@]}; i++ )); do
        local a="${ver1[i]:-0}" b="${ver2[i]:-0}"
        (( 10#$a > 10#$b )) && return 0
        (( 10#$a < 10#$b )) && return 2
    done
    return 1
}

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║   🧱  Minecraft Bedrock Server — Software Install / Upgrade Mode     ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

if [ ! -d "${SOFTWARE_DIR}" ]; then
    log "📁 Creating software directory: ${SOFTWARE_DIR}"
    mkdir -p "${SOFTWARE_DIR}"
    chmod 0777 "${SOFTWARE_DIR}"
    log_ok "Directory created: ${SOFTWARE_DIR}"
fi

if [ ! -d "${BIN_DIR}" ]; then
    log "📁 Creating server binary directory: ${BIN_DIR}"
    mkdir -p "${BIN_DIR}"
    chmod 0755 "${BIN_DIR}"
    log_ok "Directory created: ${BIN_DIR}"
fi

if [ -f "${VERSION_FILE}" ]; then
    INSTALLED_VERSION="$(cat "${VERSION_FILE}" | tr -d '[:space:]')"
else
    INSTALLED_VERSION=""
fi

if [ -z "${INSTALLED_VERSION}" ]; then
    log_info "Installed Minecraft Bedrock Version: none"
else
    log_info "Installed Minecraft Bedrock Version: ${INSTALLED_VERSION}"
fi

ZIP_FILE=""
ZIP_VERSION=""

for f in "${SOFTWARE_DIR}"/bedrock-server-*.zip; do
    [ -f "$f" ] || continue
    fname="$(basename "$f")"
    ver="${fname#bedrock-server-}"
    ver="${ver%.zip}"
    if [[ "$ver" =~ ^[0-9]+(\.[0-9]+){1,4}$ ]]; then
        ZIP_FILE="$f"
        ZIP_VERSION="$ver"
        break
    fi
done

if [ -z "${ZIP_FILE}" ]; then
    echo ""
    echo "┌──────────────────────────────────────────────────────────────────────┐"
    echo "│  📦  No Bedrock Server ZIP found in the software directory.           │"
    echo "│                                                                        │"
    echo "│  Please download the Bedrock Dedicated Server for Ubuntu/Debian       │"
    echo "│  from the official Minecraft website:                                 │"
    echo "│                                                                        │"
    echo "│     👉  https://www.minecraft.net/download/server/bedrock             │"
    echo "│                                                                        │"
    echo "│  Upload the ZIP file (e.g. bedrock-server-1.26.21.1.zip) to:         │"
    echo "│                                                                        │"
    echo "│     📂  addon_configs/<this-addon>/bedrock-server-software/           │"
    echo "│                                                                        │"
    echo "│  Then restart the add-on to perform the installation.                 │"
    echo "└──────────────────────────────────────────────────────────────────────┘"
    echo ""
    exit 1
fi

log ""
log "🔍 Found package: bedrock-server-${ZIP_VERSION}.zip"

INSTALL_ACTION="none"

if [ -z "${INSTALLED_VERSION}" ]; then
    log "📥 No previous installation detected — performing fresh install…"
    INSTALL_ACTION="install"
elif version_gt "${ZIP_VERSION}" "${INSTALLED_VERSION}"; then
    log "🔼 Upgrade available: ${INSTALLED_VERSION} → ${ZIP_VERSION}"
    INSTALL_ACTION="upgrade"
elif version_gt "${INSTALLED_VERSION}" "${ZIP_VERSION}"; then
    case "${ALLOW_DOWNGRADE,,}" in
        true|1|yes|on)
            echo ""
            echo "╔══════════════════════════════════════════════════════════════════════╗"
            echo "║                                                                      ║"
            echo "║   ⚠️⚠️⚠️  D O W N G R A D E   W A R N I N G  ⚠️⚠️⚠️                    ║"
            echo "║                                                                      ║"
            echo "║   YOU ARE ABOUT TO DOWNGRADE THE MINECRAFT BEDROCK SERVER!          ║"
            echo "║                                                                      ║"
            printf  "║   Current version  :  %-47s║\n" "${INSTALLED_VERSION}"
            printf  "║   Target version   :  %-47s║\n" "${ZIP_VERSION}"
            echo "║                                                                      ║"
            echo "║   ⛔  THE INSTALLED SERVER SOFTWARE WILL BE REMOVED AND REPLACED.   ║"
            echo "║       Your worlds and configuration will be preserved.               ║"
            echo "║                                                                      ║"
            echo "║   To CANCEL: stop the add-on within the next 30 seconds.            ║"
            echo "║                                                                      ║"
            echo "╚══════════════════════════════════════════════════════════════════════╝"
            echo ""

            for i in 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1; do
                echo "  ⏳  Downgrade starts in ${i} second(s) — stop the add-on now to cancel..."
                sleep 1
            done

            echo ""
            echo "  🗑️  Countdown complete. Beginning downgrade procedure..."
            echo ""

            log "🗑️  Removing installed server binary directory: ${BIN_DIR}"
            rm -rf "${BIN_DIR}"
            mkdir -p "${BIN_DIR}"
            chmod 0755 "${BIN_DIR}"
            log_ok "Binary directory wiped and recreated."

            rm -f "${VERSION_FILE}"
            INSTALLED_VERSION=""

            echo ""
            echo "  ✅  Server software removed. Worlds and config preserved. Proceeding with installation of ${ZIP_VERSION}..."
            echo ""

            INSTALL_ACTION="install"
            ;;
        *)
            echo ""
            echo "┌──────────────────────────────────────────────────────────────────────┐"
            echo "│  ⬇️  Downgrade Detected — operation aborted.                          │"
            echo "│                                                                        │"
            printf  "│     Installed : %-55s│\n" "${INSTALLED_VERSION}"
            printf  "│     Package   : %-55s│\n" "${ZIP_VERSION}"
            echo "│                                                                        │"
            echo "│  Downgrading may corrupt worlds. To allow downgrade, enable:          │"
            echo "│     ➜  Allow Downgrade: true   (in add-on Configuration)             │"
            echo "│  WARNING: enabling downgrade will delete all worlds and data!         │"
            echo "└──────────────────────────────────────────────────────────────────────┘"
            echo ""
            exit 1
            ;;
    esac
else
    echo ""
    echo "┌──────────────────────────────────────────────────────────────────────┐"
    echo "│  ✅  Version ${ZIP_VERSION} is already installed — nothing to do.    "
    echo "│      No changes have been made to the Bedrock Server software.        │"
    echo "└──────────────────────────────────────────────────────────────────────┘"
    echo ""
    INSTALL_ACTION="skip"
fi

if [ "${INSTALL_ACTION}" = "install" ] || [ "${INSTALL_ACTION}" = "upgrade" ]; then
    echo ""
    if [ "${INSTALL_ACTION}" = "install" ]; then
        echo "┌──────────────────────────────────────────────────────────────────────┐"
        printf "│  📥  Installing Minecraft Bedrock Server %-31s│\n" "${ZIP_VERSION}"
        echo "└──────────────────────────────────────────────────────────────────────┘"
    else
        echo "┌──────────────────────────────────────────────────────────────────────┐"
        printf "│  🔼  Upgrading: %-55s│\n" "${INSTALLED_VERSION} → ${ZIP_VERSION}"
        echo "└──────────────────────────────────────────────────────────────────────┘"
    fi
    echo ""

    if [ "${INSTALL_ACTION}" = "upgrade" ]; then
        OLD_BIN="${BIN_DIR}/bedrock_server-${INSTALLED_VERSION}"
        if [ -f "${OLD_BIN}" ]; then
            log_info "Removing old binary: bedrock_server-${INSTALLED_VERSION}"
            rm -f "${OLD_BIN}"
        fi
    fi

    EXTRACT_TMP="$(mktemp -d)"
    log "📦 Extracting ${ZIP_FILE} …"
    unzip -q "${ZIP_FILE}" -d "${EXTRACT_TMP}"

    log "📂 Installing files to ${BIN_DIR} …"
    SKIP_NAMES=("worlds" "server.properties" "allowlist.json" "permissions.json")
    shopt -s dotglob nullglob
    for item in "${EXTRACT_TMP}/"*; do
        name="$(basename "$item")"
        skip=0
        for s in "${SKIP_NAMES[@]}"; do
            [[ "$name" == "$s" ]] && skip=1 && break
        done
        [ "$skip" -eq 1 ] && continue
        cp -a "$item" "${BIN_DIR}/"
    done
    shopt -u dotglob nullglob

    if [ ! -f "${BIN_DIR}/bedrock_server" ]; then
        log_err "bedrock_server binary not found in the ZIP archive!"
        rm -rf "${EXTRACT_TMP}"
        exit 1
    fi

    chmod +x "${BIN_DIR}/bedrock_server"
    mv "${BIN_DIR}/bedrock_server" "${BIN_DIR}/bedrock_server-${ZIP_VERSION}"
    log_ok "Binary installed as: bedrock_server-${ZIP_VERSION}"

    echo "${ZIP_VERSION}" > "${VERSION_FILE}"

    rm -rf "${EXTRACT_TMP}"
    echo ""
    log_ok "Minecraft Bedrock Server ${ZIP_VERSION} installed successfully."
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                                                                      ║"
echo "║   🏁  Software Installation / Upgrade process complete.              ║"
echo "║                                                                      ║"
echo "║   To start the Minecraft Bedrock Server:                             ║"
echo "║                                                                      ║"
echo "║     1️⃣   In the add-on Configuration, set                            ║"
echo "║          ┌──────────────────────────────────────┐                    ║"
echo "║          │  Installing/Upgrading Server: false  │                    ║"
echo "║          └──────────────────────────────────────┘                    ║"
echo "║     2️⃣   Restart the add-on.                                         ║"
echo "║                                                                      ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
