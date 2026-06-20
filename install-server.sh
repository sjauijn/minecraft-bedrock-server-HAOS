#!/bin/bash
# =============================================================================
#  Minecraft Bedrock Dedicated Server — Manual Install / Upgrade Script
#  Called from start.sh when "Installing/Upgrading Server" = true
# =============================================================================
set -eo pipefail

readonly BIN_DIR="/opt/bds"
readonly CONFIG_DIR="/config"
readonly SOFTWARE_DIR="${CONFIG_DIR}/bedrock-server-software"
readonly VERSION_FILE="${BIN_DIR}/.installed-version"

# ─── helpers ─────────────────────────────────────────────────────────────────

log()      { echo "$*"; }
log_info() { echo "  ℹ️  $*"; }
log_ok()   { echo "  ✅ $*"; }
log_warn() { echo "  ⚠️  $*"; }
log_err()  { echo "  ❌ $*"; }

# Compare two version strings (dot-separated).
# Returns 0 if $1 > $2 , 1 if equal, 2 if $1 < $2
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

# ─── Banner ──────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║   🧱  Minecraft Bedrock Server — Software Install / Upgrade Mode  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# ─── Step 1: ensure software directory exists ─────────────────────────────────

if [ ! -d "${SOFTWARE_DIR}" ]; then
    log "📁 Creating software directory: ${SOFTWARE_DIR}"
    mkdir -p "${SOFTWARE_DIR}"
    chmod 0777 "${SOFTWARE_DIR}"
    log_ok "Directory created."
fi

# ─── Step 2: read currently installed version ─────────────────────────────────

if [ -f "${VERSION_FILE}" ]; then
    INSTALLED_VERSION="$(cat "${VERSION_FILE}" | tr -d '[:space:]')"
else
    INSTALLED_VERSION=""
fi

if [ -z "${INSTALLED_VERSION}" ]; then
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────┐"
    echo "│  📦  No Minecraft Bedrock Server software is currently installed. │"
    echo "│                                                                   │"
    echo "│  Please download the Bedrock Dedicated Server for Ubuntu/Debian  │"
    echo "│  from the official Minecraft website:                            │"
    echo "│                                                                   │"
    echo "│     👉  https://www.minecraft.net/download/server/bedrock        │"
    echo "│                                                                   │"
    echo "│  Then upload the ZIP file (e.g. bedrock-server-1.26.21.1.zip)   │"
    echo "│  to the following directory:                                      │"
    echo "│                                                                   │"
    echo "│     📂  addon_configs/<this-addon>/bedrock-server-software/      │"
    echo "│                                                                   │"
    echo "│  Restart the add-on after uploading to apply the installation.   │"
    echo "└─────────────────────────────────────────────────────────────────┘"
    echo ""
    log_info "Installed Minecraft Bedrock Version: none"
else
    log_info "Installed Minecraft Bedrock Version: ${INSTALLED_VERSION}"
fi

# ─── Step 3: scan for ZIP file ────────────────────────────────────────────────

ZIP_FILE=""
ZIP_VERSION=""

for f in "${SOFTWARE_DIR}"/bedrock-server-*.zip; do
    [ -f "$f" ] || continue
    # Extract version from filename: bedrock-server-1.26.21.1.zip → 1.26.21.1
    fname="$(basename "$f")"
    ver="${fname#bedrock-server-}"
    ver="${ver%.zip}"
    # Validate it looks like a version number
    if [[ "$ver" =~ ^[0-9]+(\.[0-9]+){1,4}$ ]]; then
        ZIP_FILE="$f"
        ZIP_VERSION="$ver"
        break
    fi
done

# ─── Step 4: decide what to do ───────────────────────────────────────────────

if [ -z "${ZIP_FILE}" ]; then
    echo ""
    if [ -n "${INSTALLED_VERSION}" ]; then
        log_warn "No bedrock-server-*.zip found in ${SOFTWARE_DIR}."
        log_info "Place a ZIP file there and restart the add-on to install or upgrade."
    fi
    # Nothing to install/upgrade — proceed to final message
    INSTALL_ACTION="none"

elif [ -z "${INSTALLED_VERSION}" ]; then
    log ""
    log "🔍 Found package:  bedrock-server-${ZIP_VERSION}.zip"
    log "📥 No previous installation detected — performing fresh install…"
    INSTALL_ACTION="install"

else
    log ""
    log "🔍 Found package:  bedrock-server-${ZIP_VERSION}.zip"
    log_info "Installed Minecraft Bedrock Version: ${INSTALLED_VERSION}"

    if version_gt "${ZIP_VERSION}" "${INSTALLED_VERSION}"; then
        log "🔼 Upgrade available: ${INSTALLED_VERSION} → ${ZIP_VERSION}"
        INSTALL_ACTION="upgrade"
    elif version_gt "${INSTALLED_VERSION}" "${ZIP_VERSION}"; then
        echo ""
        echo "┌──────────────────────────────────────────────────────────────────┐"
        echo "│  ⬇️  Downgrade Detected                                           │"
        echo "│                                                                    │"
        printf "│  Current :  %-52s│\n" "${INSTALLED_VERSION}"
        printf "│  Package :  %-52s│\n" "${ZIP_VERSION}"
        echo "│                                                                    │"
        echo "│  Downgrading Bedrock Server is not supported and may corrupt      │"
        echo "│  your worlds. Remove the ZIP file and restart to skip.            │"
        echo "└──────────────────────────────────────────────────────────────────┘"
        echo ""
        INSTALL_ACTION="none"
    else
        # Same version
        echo ""
        echo "┌──────────────────────────────────────────────────────────────────┐"
        echo "│  ✅  Upgrade Not Required                                          │"
        echo "│                                                                    │"
        printf "│  Version %-55s│\n" "${INSTALLED_VERSION} is already installed."
        echo "│  No changes have been made to the Bedrock Server software.        │"
        echo "└──────────────────────────────────────────────────────────────────┘"
        echo ""
        INSTALL_ACTION="none"
    fi
fi

# ─── Step 5: perform install / upgrade ───────────────────────────────────────

if [ "${INSTALL_ACTION}" = "install" ] || [ "${INSTALL_ACTION}" = "upgrade" ]; then
    echo ""
    if [ "${INSTALL_ACTION}" = "install" ]; then
        echo "┌──────────────────────────────────────────────────────────────────┐"
        echo "│  📥  Installing Minecraft Bedrock Server ${ZIP_VERSION}          "
        echo "└──────────────────────────────────────────────────────────────────┘"
    else
        echo "┌──────────────────────────────────────────────────────────────────┐"
        echo "│  🔼  Upgrading Minecraft Bedrock Server                           │"
        printf "│      %s  →  %-48s│\n" "${INSTALLED_VERSION}" "${ZIP_VERSION}"
        echo "└──────────────────────────────────────────────────────────────────┘"
    fi
    echo ""

    # Back up old binary if upgrading
    if [ "${INSTALL_ACTION}" = "upgrade" ]; then
        OLD_BIN="${BIN_DIR}/bedrock_server-${INSTALLED_VERSION}"
        if [ -f "${OLD_BIN}" ]; then
            log_info "Removing old binary: bedrock_server-${INSTALLED_VERSION}"
            rm -f "${OLD_BIN}"
        fi
    fi

    # Extract server software to a temp dir first, then move to /opt/bds
    EXTRACT_TMP="$(mktemp -d)"
    log "📦 Extracting ${ZIP_FILE} …"
    unzip -q "${ZIP_FILE}" -d "${EXTRACT_TMP}"

    # Move everything into /opt/bds, preserving symlinks
    log "📂 Installing files to ${BIN_DIR} …"
    # Copy all files except those that are symlinked (worlds, server.properties, etc.)
    SYMLINKED=("worlds" "server.properties" "allowlist.json" "permissions.json")
    shopt -s dotglob nullglob
    for item in "${EXTRACT_TMP}/"*; do
        name="$(basename "$item")"
        skip=0
        for sl in "${SYMLINKED[@]}"; do
            [[ "$name" == "$sl" ]] && skip=1 && break
        done
        [ "$skip" -eq 1 ] && continue
        cp -a "$item" "${BIN_DIR}/"
    done
    shopt -u dotglob nullglob

    # Rename binary with version suffix (matches bedrock-entry.sh expectation)
    if [ -f "${BIN_DIR}/bedrock_server" ]; then
        chmod +x "${BIN_DIR}/bedrock_server"
        mv "${BIN_DIR}/bedrock_server" "${BIN_DIR}/bedrock_server-${ZIP_VERSION}"
        log_ok "Binary installed as: bedrock_server-${ZIP_VERSION}"
    else
        log_err "bedrock_server binary not found in the ZIP archive!"
        rm -rf "${EXTRACT_TMP}"
        exit 1
    fi

    # Save installed version
    echo "${ZIP_VERSION}" > "${VERSION_FILE}"

    # Cleanup
    rm -rf "${EXTRACT_TMP}"

    echo ""
    log_ok "Minecraft Bedrock Server ${ZIP_VERSION} installed successfully."
fi

# ─── Step 6: final instructions ──────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                                                                      ║"
echo "║   🏁  Software Installation / Upgrade process complete.              ║"
echo "║                                                                      ║"
echo "║   To start the Minecraft Bedrock Server:                            ║"
echo "║                                                                      ║"
echo "║     1️⃣   In the add-on Configuration, set                            ║"
echo "║          ┌──────────────────────────────────────┐                   ║"
echo "║          │  Installing/Upgrading Server: false  │                   ║"
echo "║          └──────────────────────────────────────┘                   ║"
echo "║     2️⃣   Restart the add-on.                                         ║"
echo "║                                                                      ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
