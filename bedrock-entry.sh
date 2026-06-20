#!/bin/bash
set -eo pipefail

DATA_DIR="${DATA_DIR:-/data}"

# addon_config:rw mounts the addon config dir.
# Inside the container it is accessible at /homeassistant/addon_configs/<slug>/
# but HA also creates a symlink /config -> that directory.
# We use /config as the canonical path.
readonly CONFIG_DIR="/config"
WORLDS_DIR="${CONFIG_DIR}/worlds"

# =========================
# Bedrock Server entry door Kevin Hekert
# - Resolves requested Minecraft version (latest/preview/pinned) and downloads it at runtime
# - Applies server.properties via set-property (thanks to itzg!)
# - Builds permissions/allowlist (from options + env fallbacks)
# - Starts the resolved binary at /opt/bds/bedrock_server-${VERSION}
# =========================

#(Re)set symlinks (blijft niet altijd bewaard vanuit Dockerfile build)
LINKS=(
  "/opt/bds/worlds:${WORLDS_DIR}"
  "/opt/bds/server.properties:${DATA_DIR}/server.properties"
  "/opt/bds/allowlist.json:${DATA_DIR}/allowlist.json"
  "/opt/bds/permissions.json:${DATA_DIR}/permissions.json"
)

echo "🔗 Checking Bedrock symlinks..."
for entry in "${LINKS[@]}"; do
  target="${entry%%:*}"
  source="${entry##*:}"
  ln -sfn "$source" "$target"
  echo "  - $target → $source"
done
echo "✨ Symlink check and update complete..."

# --- Ensure worlds dir exists in addon_configs ---
# Migration: move worlds from old /data/worlds to new /config/worlds on first start
if [ -d "${DATA_DIR}/worlds" ] && [ ! -L "${DATA_DIR}/worlds" ] && [ ! -d "${WORLDS_DIR}" ]; then
  echo "🔄 Migrating worlds from ${DATA_DIR}/worlds to ${WORLDS_DIR}..."
  mv "${DATA_DIR}/worlds" "${WORLDS_DIR}"
  echo "✅ Migration complete. Worlds are now accessible via SFTP at addon_configs/mc_server_ha/worlds/"
fi

if [ ! -d "${WORLDS_DIR}" ]; then
  echo "📁 Creating ${WORLDS_DIR}..."
  mkdir -p "${WORLDS_DIR}"
  chmod 0777 "${WORLDS_DIR}"
fi

# ---------- helpers ----------
isTrue() { case "${1,,}" in true|on|1|yes) return 0 ;; *) return 1 ;; esac; }
lower_bool() { case "${1,,}" in true|1|on|yes) echo "true" ;; *) echo "false" ;; esac; }

# JSON helpers
OPT_FILE="${DATA_DIR}/config/bedrock_for_ha_config.json"
CONFIG_FILE="$OPT_FILE"
optn() { jq -r "$1 // empty" "$OPT_FILE" 2>/dev/null; }
optf() { jq -r --arg k "$1" '.[$k] // empty' "$OPT_FILE" 2>/dev/null; }
first_nonempty() { for v in "$@"; do [[ -n "$v" ]] && { echo "$v"; return; }; done; echo ""; }

jq_safe_array_file() {
  local f="$1"
  if [[ ! -f "$f" ]] || ! jq -e . "$f" >/dev/null 2>&1; then
    echo "[]" > "$f"
  elif ! jq -e 'type=="array"' "$f" >/dev/null 2>&1; then
    jq -c '[.]' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  fi
}

# ---------- debug ----------
if [[ ${DEBUG^^} = TRUE ]]; then
  set -x
  debug_dir_listing="$(ls -ld "${DATA_DIR}")"
  echo "DEBUG: running as $(id -a) with ${debug_dir_listing}"
  echo "  cwd=$(pwd)"
fi

# ==========================================================================
# ---------- Determine requested Minecraft Game Version (NEW LOGIC) -------
# ==========================================================================
# Priority: explicit env MC_VERSION/VERSION > UI option general.mc_version
# (nested) > flat fallback option > "latest"
RAW_MC_VERSION="$(first_nonempty \
  "${MC_VERSION:-}" \
  "${VERSION:-}" \
  "$(optn '.general.mc_version')" \
  "$(optf 'mc_version')" \
  "latest")"

# Normalize: trim whitespace, allow user to leave field blank meaning "latest"
RAW_MC_VERSION="$(echo "$RAW_MC_VERSION" | xargs 2>/dev/null || echo "$RAW_MC_VERSION")"
[[ -z "$RAW_MC_VERSION" ]] && RAW_MC_VERSION="latest"

case "${RAW_MC_VERSION,,}" in
  latest)
    VERSION="LATEST"
    ;;
  preview)
    VERSION="PREVIEW"
    PREVIEW="true"
    ;;
  *)
    # Specific pinned version, e.g. "1.26.21" or "1.26.21.1".
    # Bedrock releases are always published as "1.X.Y[.Z]", so if the user
    # typed just "26.21" (omitting the leading "1."), add it back.
    if [[ "$RAW_MC_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] && [[ "$RAW_MC_VERSION" != 1.* ]]; then
      VERSION="1.${RAW_MC_VERSION}"
      echo "ℹ️ Interpreting '${RAW_MC_VERSION}' as Bedrock version ${VERSION}"
    else
      VERSION="${RAW_MC_VERSION}"
    fi
    ;;
esac

export VERSION
export PREVIEW="${PREVIEW:-false}"

# Custom direct download URL takes absolute priority over everything else.
# Lets the user paste the exact bedrock-server-VERSION.zip link they copied
# from https://www.minecraft.net/en-us/download/server/bedrock, which is the
# only fully reliable source when automatic resolution fails.
RAW_MC_DOWNLOAD_URL="$(first_nonempty \
  "${MC_DOWNLOAD_URL:-}" \
  "${DIRECT_DOWNLOAD_URL:-}" \
  "$(optn '.general.mc_download_url')" \
  "$(optf 'mc_download_url')")"
RAW_MC_DOWNLOAD_URL="$(echo "$RAW_MC_DOWNLOAD_URL" | xargs 2>/dev/null || echo "$RAW_MC_DOWNLOAD_URL")"
[[ -n "$RAW_MC_DOWNLOAD_URL" ]] && export DIRECT_DOWNLOAD_URL="$RAW_MC_DOWNLOAD_URL"

BIN_DIR="/opt/bds"
mkdir -p "${BIN_DIR}"

# ---------- Resolve "LATEST"/"PREVIEW" to a concrete version + download URL ----------
# Primary: scrape the official download page with `restify` (already bundled in
# this image), looking for the <a data-platform="serverBedrock...Linux"> element.
# minecraft.net's download page can render its download links via client-side
# JS, in which case scraping the raw HTML/DOM will not find a match. When that
# happens we fail fast with instructions to use the "Custom Download URL"
# option, where the user pastes the exact link copied from their browser
# (Download button → copy link), which is the one fully reliable method.
BDS_DOWNLOAD_PAGE="https://www.minecraft.net/en-us/download/server/bedrock"

resolve_via_restify() {
  local want_preview="$1"
  local platform="serverBedrockLinux"
  [[ "$want_preview" == "true" ]] && platform="serverBedrockPreviewLinux"

  if ! command -v restify >/dev/null 2>&1; then
    return 1
  fi

  local json url
  json="$(restify --user-agent="itzg/minecraft-bedrock-server" \
            --headers 'accept-language:*' \
            --attribute="data-platform=${platform}" \
            "${BDS_DOWNLOAD_PAGE}" 2>/dev/null || true)"
  [[ -z "$json" ]] && return 1

  url="$(echo "$json" | jq -r '.[0].href // empty' 2>/dev/null || true)"
  [[ -z "$url" ]] && return 1

  echo "$url"
  return 0
}

resolve_latest_url() {
  local want_preview="$1"
  resolve_via_restify "$want_preview"
}

extract_version_from_url() {
  # Pulls the dotted version number out of a bedrock-server-X.Y.Z.W.zip URL
  # without relying on `head`, which can be unavailable to a demoted user.
  local in="$1"
  [[ "$in" =~ bedrock-server-([0-9]+(\.[0-9]+){2,3})\.zip ]] && echo "${BASH_REMATCH[1]}"
}

DOWNLOAD_URL=""
RESOLVED_VERSION=""

if [[ -n "${DIRECT_DOWNLOAD_URL:-}" ]]; then
  echo "🌐 Using custom download URL from configuration."
  DOWNLOAD_URL="${DIRECT_DOWNLOAD_URL}"
  RESOLVED_VERSION="$(extract_version_from_url "$DOWNLOAD_URL")"
elif [[ "$VERSION" == "LATEST" || "$VERSION" == "PREVIEW" ]]; then
  echo "🔎 Resolving ${VERSION} Bedrock server version from minecraft.net..."
  DOWNLOAD_URL="$(resolve_latest_url "$( [[ "$VERSION" == "PREVIEW" ]] && echo true || echo false )" || true)"
  if [[ -z "$DOWNLOAD_URL" ]]; then
    echo "ERROR: Could not automatically resolve the ${VERSION} download URL from ${BDS_DOWNLOAD_PAGE}."
    echo "       minecraft.net sometimes renders the download link via client-side JS,"
    echo "       which automatic scraping cannot see."
    echo "       Workaround (confirmed working): open ${BDS_DOWNLOAD_PAGE} in a browser,"
    echo "       right-click the Linux 'Download' button, copy the link address, and paste"
    echo "       it into the add-on's 'Minecraft Download URL' (Custom Download URL) field."
    echo "       Example: https://www.minecraft.net/bedrockdedicatedserver/bin-linux/bedrock-server-1.26.31.1.zip"
    echo "       Alternatively, set 'Minecraft Game Version' to a specific known version (e.g. 1.26.21)."
    exit 2
  fi
  RESOLVED_VERSION="$(extract_version_from_url "$DOWNLOAD_URL")"
else
  # Specific pinned version requested, e.g. "1.26.21" or "1.26.21.1"
  RESOLVED_VERSION="$VERSION"
  ARCH_SUFFIX="bin-linux"
  if [[ "${PREVIEW,,}" == "true" ]]; then
    ARCH_SUFFIX="bin-linux-preview"
  fi
  DOWNLOAD_URL="https://www.minecraft.net/bedrockdedicatedserver/${ARCH_SUFFIX}/bedrock-server-${RESOLVED_VERSION}.zip"
fi

if [[ -z "$RESOLVED_VERSION" ]]; then
  echo "ERROR: Failed to determine resolved Bedrock version string from URL: ${DOWNLOAD_URL}"
  exit 2
fi

echo "🧱 Requested version setting : ${RAW_MC_VERSION}"
echo "🧱 Resolved Bedrock version  : ${RESOLVED_VERSION}"
echo "🌐 Download URL              : ${DOWNLOAD_URL}"

BIN_PATH="${BIN_DIR}/bedrock_server-${RESOLVED_VERSION}"

# ---------- Download/install only if this exact version isn't already cached ----------
if [[ -x "$BIN_PATH" ]]; then
  echo "✅ Bedrock server ${RESOLVED_VERSION} already present in ${BIN_DIR}, skipping download."
else
  echo "📦 Downloading Bedrock server ${RESOLVED_VERSION}..."
  TMP_ZIP="$(mktemp /tmp/bedrock-XXXXXX.zip)"
  if ! curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors --http1.1 \
      -A "itzg/minecraft-bedrock-server" -o "$TMP_ZIP" "$DOWNLOAD_URL"; then
    rm -f "$TMP_ZIP"
    echo "ERROR: Failed to download Bedrock server from ${DOWNLOAD_URL}"
    echo "       Check 'Minecraft Game Version' in the add-on configuration."
    exit 2
  fi

  TMP_EXTRACT="$(mktemp -d /tmp/bedrock-extract-XXXXXX)"
  unzip -q "$TMP_ZIP" -d "$TMP_EXTRACT"
  rm -f "$TMP_ZIP"

  if [[ ! -f "${TMP_EXTRACT}/bedrock_server" ]]; then
    echo "ERROR: Downloaded archive did not contain a bedrock_server executable."
    rm -rf "$TMP_EXTRACT"
    exit 2
  fi

  # Preserve any existing worlds/permissions/allowlist/server.properties already
  # symlinked away from /opt/bds, then sync in everything else (libs, resource_packs
  # skeleton, etc.) for this version, without clobbering the symlinked paths.
  shopt -s dotglob
  for item in "${TMP_EXTRACT}"/*; do
    base="$(basename "$item")"
    case "$base" in
      worlds|server.properties|allowlist.json|permissions.json)
        continue
        ;;
      bedrock_server)
        cp -f "$item" "${BIN_PATH}"
        ;;
      *)
        rm -rf "${BIN_DIR}/${base}"
        cp -rf "$item" "${BIN_DIR}/${base}"
        ;;
    esac
  done
  shopt -u dotglob
  rm -rf "$TMP_EXTRACT"

  chmod +x "$BIN_PATH"
  echo "${RESOLVED_VERSION}" > /etc/bds-version
  echo "✅ Bedrock server ${RESOLVED_VERSION} installed at ${BIN_PATH}"
fi

# Optional cleanup: keep only the currently selected version's binary to save space,
# unless KEEP_OLD_VERSIONS is set to true.
if [[ "${KEEP_OLD_VERSIONS:-false}" != "true" ]]; then
  find "${BIN_DIR}" -maxdepth 1 -name 'bedrock_server-*' ! -name "bedrock_server-${RESOLVED_VERSION}" -exec rm -f {} \;
fi

if [[ ! -x "$BIN_PATH" ]]; then
  echo "ERROR: Binary not found after install: $BIN_PATH"
  exit 2
fi

VERSION="$RESOLVED_VERSION"
export VERSION

# ---------- (Re)apply data-dir symlinks now that /opt/bds has been refreshed ----------
for entry in "${LINKS[@]}"; do
  target="${entry%%:*}"
  source="${entry##*:}"
  ln -sfn "$source" "$target"
done

# ---------- allow list ----------
allowListUsers="${ALLOW_LIST_USERS:-}"
if [ -n "$allowListUsers" ]; then
  echo "Setting allowlist.json from \$ALLOW_LIST_USERS"
  rm -f allowlist.json
  jq -n --arg users "$allowListUsers" \
    '$users | split(",") | map({ "name": . })' > allowlist.json
  export ALLOW_LIST=true
fi

# ---------- options → ENV (nested with flat fallbacks) ----------
# GENERAL
export SERVER_NAME="${SERVER_NAME:-$(first_nonempty "$(optn '.general.server_name')" "$(optf 'server_name')")}"
export SERVER_PORT="${SERVER_PORT:-$(first_nonempty "$(optn '.general.server_port')" "$(optf 'server_port')")}"
export SERVER_PORT_V6="${SERVER_PORT_V6:-$(first_nonempty "$(optn '.general.server_port_v6')" "$(optf 'server_port_v6')")}"
export ONLINE_MODE="$(lower_bool "${ONLINE_MODE:-$(first_nonempty "$(optn '.general.online_mode')" "$(optf 'online_mode')")}")"
export EMIT_SERVER_TELEMETRY="$(lower_bool "${EMIT_SERVER_TELEMETRY:-$(first_nonempty "$(optn '.general.emit_server_telemetry')" "$(optf 'emit_server_telemetry')")}")"
export ENABLE_LAN_VISIBILITY="$(lower_bool "${ENABLE_LAN_VISIBILITY:-$(first_nonempty "$(optn '.general.enable_lan_visibility')" "$(optf 'enable_lan_visibility')")}")"
export EULA="$(lower_bool "${EULA:-$(first_nonempty "$(optn '.general.eula')" "$(optf 'eula')")}")"

# WORLD
export LEVEL_NAME="${LEVEL_NAME:-$(first_nonempty "$(optn '.world.level_name')" "$(optf 'level_name')")}"

# Check world-specific seed from data/worldconfiguration.json
WORLD_CONFIG_FILE="${DATA_DIR}/worldconfiguration.json"
WORLD_SEED=""
if [[ -f "$WORLD_CONFIG_FILE" ]] && [[ -n "$LEVEL_NAME" ]]; then
  if ! WORLD_SEED=$(jq -r --arg world "$LEVEL_NAME" '.[$world].seed // empty' "$WORLD_CONFIG_FILE" 2>&1); then
    echo "⚠️ Warning: Failed to parse $WORLD_CONFIG_FILE: $WORLD_SEED"
    WORLD_SEED=""
  fi
fi

# Use world-specific seed if available, otherwise fall back to config
if [[ -n "$WORLD_SEED" ]]; then
  export LEVEL_SEED="$WORLD_SEED"
  echo "🌍 Using world-specific seed for '$LEVEL_NAME': $LEVEL_SEED"
else
  export LEVEL_SEED="${LEVEL_SEED:-$(first_nonempty "$(optn '.world.level_seed')" "$(optf 'level_seed')")}"
fi
export LEVEL_TYPE="${LEVEL_TYPE:-$(first_nonempty "$(optn '.world.level_type')" "$(optf 'level_type')")}"
export GAMEMODE="${GAMEMODE:-$(first_nonempty "$(optn '.world.gamemode')" "$(optf 'gamemode')")}"
export DIFFICULTY="${DIFFICULTY:-$(first_nonempty "$(optn '.world.difficulty')" "$(optf 'difficulty')")}"
export ALLOW_CHEATS="$(lower_bool "${ALLOW_CHEATS:-$(first_nonempty "$(optn '.world.allow_cheats')" "$(optf 'allow_cheats')")}")"

# PLAYERS
export MAX_PLAYERS="${MAX_PLAYERS:-$(first_nonempty "$(optn '.players.max_players')" "$(optf 'max_players')")}"
export ALLOW_LIST="$(lower_bool "${ALLOW_LIST:-$(first_nonempty "$(optn '.players.allow_list')" "$(optf 'allow_list')")}")"
export DEFAULT_PLAYER_PERMISSION_LEVEL="${DEFAULT_PLAYER_PERMISSION_LEVEL:-$(first_nonempty "$(optn '.players.default_player_permission_level')" "$(optf 'default_player_permission_level')")}"
export TEXTUREPACK_REQUIRED="$(lower_bool "${TEXTUREPACK_REQUIRED:-$(first_nonempty "$(optn '.players.texturepack_required')" "$(optf 'texturepack_required')")}")"

# PERFORMANCE
export VIEW_DISTANCE="${VIEW_DISTANCE:-$(first_nonempty "$(optn '.performance.view_distance')" "$(optf 'view_distance')")}"
export TICK_DISTANCE="${TICK_DISTANCE:-$(first_nonempty "$(optn '.performance.tick_distance')" "$(optf 'tick_distance')")}"
export PLAYER_IDLE_TIMEOUT="${PLAYER_IDLE_TIMEOUT:-$(first_nonempty "$(optn '.performance.player_idle_timeout')" "$(optf 'player_idle_timeout')")}"
export MAX_THREADS="${MAX_THREADS:-$(first_nonempty "$(optn '.performance.max_threads')" "$(optf 'max_threads')")}"
export COMPRESSION_THRESHOLD="${COMPRESSION_THRESHOLD:-$(first_nonempty "$(optn '.performance.compression_threshold')" "$(optf 'compression_threshold')")}"

# ANTI_CHEAT
export SERVER_AUTHORITATIVE_MOVEMENT="${SERVER_AUTHORITATIVE_MOVEMENT:-$(first_nonempty "$(optn '.anti_cheat.server_authoritative_movement')" "$(optf 'server_authoritative_movement')")}"
export SERVER_AUTHORITATIVE_BLOCK_BREAKING="$(lower_bool "${SERVER_AUTHORITATIVE_BLOCK_BREAKING:-$(first_nonempty "$(optn '.anti_cheat.server_authoritative_block_breaking')" "$(optf 'server_authoritative_block_breaking')")}")"
export PLAYER_MOVEMENT_SCORE_THRESHOLD="${PLAYER_MOVEMENT_SCORE_THRESHOLD:-$(first_nonempty "$(optn '.anti_cheat.player_movement_score_threshold')" "$(optf 'player_movement_score_threshold')")}"
export PLAYER_MOVEMENT_DISTANCE_THRESHOLD="${PLAYER_MOVEMENT_DISTANCE_THRESHOLD:-$(first_nonempty "$(optn '.anti_cheat.player_movement_distance_threshold')" "$(optf 'player_movement_distance_threshold')")}"
export PLAYER_MOVEMENT_DURATION_THRESHOLD_IN_MS="${PLAYER_MOVEMENT_DURATION_THRESHOLD_IN_MS:-$(first_nonempty "$(optn '.anti_cheat.player_movement_duration_threshold_in_ms')" "$(optf 'player_movement_duration_threshold_in_ms')")}"
export CORRECT_PLAYER_MOVEMENT="$(lower_bool "${CORRECT_PLAYER_MOVEMENT:-$(first_nonempty "$(optn '.anti_cheat.correct_player_movement')" "$(optf 'correct_player_movement')")}")"

# ---------- Build permissions.json from UI (role_assignments) + env fallbacks ----------
ensure_permissions_file() {
  if [[ ! -f "$PERM_FILE" ]] || ! jq -e . "$PERM_FILE" >/dev/null 2>&1; then
    echo "[]" > "$PERM_FILE"
  fi
}

sync_permissions_and_config() {
  # Als er nog geen config is, kunnen we niets syncen
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "⚠️ Config file $CONFIG_FILE not found, skipping permissions sync"
    return 0
  fi

  ensure_permissions_file

  # 1) role_assignments uit config lezen (altijd array)
  local cfg_ra_json
  cfg_ra_json="$(jq -c '.players.role_assignments // []' "$CONFIG_FILE" 2>/dev/null || echo '[]')"

  # 2) permissions.json normaliseren naar array van {xuid, permission}
  local perm_json
  perm_json="$(jq -c '
    ( . // [] ) |
    map({
      xuid: (.xuid | tostring),
      permission: (.permission | tostring)
    })
  ' "$PERM_FILE" 2>/dev/null || echo '[]')"

  # 3) config ➜ permissions (union op xuid)
  local new_perm_json
  new_perm_json="$(jq -c --argjson cfg "$cfg_ra_json" --argjson perms "$perm_json" '
    ($perms // []) as $perms
    | ($cfg // []) as $cfg
    | reduce $cfg[] as $c ($perms;
        if any(.xuid == $c.xuid) then
          map(if .xuid == $c.xuid then .permission = $c.role else . end)
        else
          . + [{xuid:$c.xuid, permission:$c.role}]
        end
      )
  ' <<< '{}')"

  echo "${new_perm_json:-[]}" > "$PERM_FILE"

  # 4) permissions ➜ config (altijd terugschrijven naar config)
  local final_perm_json
  final_perm_json="$(cat "$PERM_FILE")"
  local tmp_cfg
  tmp_cfg="$(mktemp)"
  jq --argjson perms "$final_perm_json" '
    .players.role_assignments = (
      $perms | map({
        xuid: ( .xuid | tostring ),
        role: ( .permission | tostring )
      })
    )
  ' "$CONFIG_FILE" > "$tmp_cfg" && mv "$tmp_cfg" "$CONFIG_FILE"

  echo "✅ Synced permissions.json ↔ config.players.role_assignments"
}

# ---------- Bidirectionele sync: config <-> permissions.json ----------
PERM_FILE="${DATA_DIR}/permissions.json" # Zie ook symlinks

# Safe lees helpers: geef altijd geldige JSON terug
config_ra_json="$(jq -c '.players.role_assignments // []' "$OPT_FILE" 2>/dev/null || echo '[]')"
perms_json="$(cat "$PERM_FILE" 2>/dev/null || echo '[]')"

merged_json="$(
  jq -c '
    def norm_level(r):
      (r|tostring|ascii_downcase) as $r
      | if $r == "operator" or $r == "op" then 3
        elif $r == "member" or $r == "default" then 2
        else 1
        end;
    def level_to_role(n):
      if n >= 3 then "operator"
      elif n >= 2 then "member"
      else "visitor"
      end;
    # config: [{xuid, role, name?}]
    def cfg_pairs(list):
      [ list[]? | {
          xuid: (.xuid|tostring),
          lvl: norm_level(.role),
          name: (.name // null)
        } ];
    # perms: [{xuid, permission}] – geen name
    def perm_pairs(list):
      [ list[]? | {
          xuid: (.xuid|tostring),
          lvl: norm_level(.permission),
          name: null
        } ];
    . as $in
    | ($in.config_ra // []) as $cfg_list
    | ($in.perms // []) as $perm_list
    | (cfg_pairs($cfg_list) + perm_pairs($perm_list))
    | group_by(.xuid)
    | map({
        xuid: .[0].xuid,
        lvl: ( map(.lvl) | max ),
        # neem naam uit config als die bestaat
        name: (
          [.[].name // empty]
          | map(select(. != "" and . != "null"))
          | first? // null
        )
      })
    as $merged
    | {
        # Voor config: xuid + role + optioneel name
        merged_for_config: (
          $merged | map(
            if .name == null or .name == "" then
              { xuid, role: level_to_role(.lvl) }
            else
              { xuid, role: level_to_role(.lvl), name: .name }
            end
          )
        ),
        # Voor permissions.json: alleen xuid + permission
        merged_for_perms: (
          $merged | map({ xuid, permission: level_to_role(.lvl) })
        )
      }
  ' <<< "{\"config_ra\":$config_ra_json,\"perms\":$perms_json}"
)"

# Haal twee arrays uit het merge-resultaat
cfg_out="$(echo "$merged_json" | jq '.merged_for_config')"
perms_out="$(echo "$merged_json" | jq '.merged_for_perms')"

echo "🔄 Merged $(echo "$cfg_out" | jq 'length') entries voor config & permissions..."

# 1) Schrijf terug naar config: .players.role_assignments = cfg_out
tmp_cfg="$(mktemp)"
jq --argjson ra "$cfg_out" '
  .players.role_assignments = $ra
' "$OPT_FILE" > "$tmp_cfg" && mv "$tmp_cfg" "$OPT_FILE"

# 2) Schrijf terug naar permissions.json
tmp_perm="$(mktemp)"
echo "$perms_out" | jq '.' > "$tmp_perm" && mv "$tmp_perm" "$PERM_FILE"

echo "✅ Bidirectionele sync voltooid."

assignments_json="$(jq -c '.players.role_assignments // []' "$OPT_FILE" 2>/dev/null || echo '[]')"

env_to_items() {
  local csv="$1" role="$2"
  [[ -z "$csv" ]] && return 0
  awk -v RS=',' -v role="$role" '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); if(length($0)) printf("{\"xuid\":\"%s\",\"role\":\"%s\"}\n",$0,role)}' <<< "$csv"
}

tmp="$(mktemp)"
{
  jq -c '.[] | {"xuid": (.xuid|tostring), "role": (.role|tostring)}' <<< "$assignments_json"
  env_to_items "${OPS}" "operator"
  env_to_items "${MEMBERS}" "member"
  env_to_items "${VISITORS}" "visitor"
} | jq -s '
  map(.role |= ( . as $r |
    if ($r=="operator" or $r=="member" or $r=="visitor") then $r else "member" end)) |
  (reduce .[] as $i ({}; .[$i.xuid] = {xuid:$i.xuid, permission:$i.role})) |
  to_entries | map(.value)
' > "$tmp" && mv "$tmp" "$PERM_FILE"

ensure_permissions_file
echo "✅ permissions.json generated"

# ---------- Build allowlist.json vanuit config.players.role_assignments ----------
ALLOWLIST_FILE="${DATA_DIR}/allowlist.json"
if [[ -f "$OPT_FILE" ]]; then
  tmp_allow="$(mktemp)"
  jq -c '
    .players.role_assignments // [] |
    map({
      name: ( .name // "" ),
      xuid: ( .xuid | tostring )
    })
  ' "$OPT_FILE" > "$tmp_allow" && mv "$tmp_allow" "$ALLOWLIST_FILE"
  echo "✅ allowlist.json regenerated from config.players.role_assignments"
else
  echo "⚠️ $OPT_FILE not found, skipping allowlist.json generation"
fi

# ---------- Apply server.properties from ENV via definitions ----------
PROP_FILE="${DATA_DIR}/server.properties"
touch "$PROP_FILE"
if [ -f /etc/bds-property-definitions.json ]; then
  set-property --file "$PROP_FILE" --bulk /etc/bds-property-definitions.json
else
  echo "WARN: /etc/bds-property-definitions.json missing; skipping bulk apply"
fi

# ---------- Log world configuration ----------
echo "🌍 World Configuration:"
echo "  - Name: ${LEVEL_NAME:-<not set>}"
echo "  - Seed: ${LEVEL_SEED:-<not set>}"
echo "-------------------------------------------"

# ---------- Pre-start info ----------
echo "📜 server.properties (excerpt):"
echo "-------------------------------------------"
if [ -f "$PROP_FILE" ]; then
  grep -E '^(server-name|gamemode|difficulty|level-name|default-player-permission-level|view-distance|tick-distance|online-mode|server-port|max-players)' "$PROP_FILE" || echo "⚠️ Geen properties gevonden"
else
  echo "⚠️ $PROP_FILE bestaat nog niet!"
fi
echo "-------------------------------------------"

# ---------- EULA gate: skip Bedrock if not accepted ----------
if [[ ${EULA^^} != TRUE ]]; then
  echo
  echo "⚠️ EULA is not accepted (EULA=${EULA:-unset})."
  echo "   Bedrock server will NOT be started."
  echo "   Accept the Minecraft EULA in the add-on UI and restart."
  echo "   See https://minecraft.net/terms"
  echo
  # Container blijft draaien zodat de Flask UI via Ingress bereikbaar blijft.
  tail -f /dev/null
fi

# ---------- Start ----------
export LD_LIBRARY_PATH="${BIN_DIR}"
echo Library path: ${LD_LIBRARY_PATH:-"(not set)"}
echo "🚀 Starting Bedrock ${VERSION}"

# Filter extremely noisy Bedrock AI warnings (attack_interval disabled -> scan_interval)
# so Home Assistant logs stay readable. Set SUPPRESS_NOISY_BEDROCK_LOGS=false to allow all logs.
: "${SUPPRESS_NOISY_BEDROCK_LOGS:=true}"
LOG_NOISE_PATTERN="${BEDROCK_LOG_NOISE_PATTERN:-attack_interval.*scan_interval}"

has_stdbuf_support() {
  command -v stdbuf >/dev/null 2>&1 || return 1
  local candidates=(
    "/usr/lib/coreutils/libstdbuf.so"
    "/usr/libexec/coreutils/libstdbuf.so"
    "/usr/lib/x86_64-linux-gnu/coreutils/libstdbuf.so"
    "/usr/lib/aarch64-linux-gnu/coreutils/libstdbuf.so"
  )
  for lib in "${candidates[@]}"; do
    [[ -f "$lib" ]] && return 0
  done
  return 1
}

run_bedrock() {
  local cmd=("$@")
  if [[ "${SUPPRESS_NOISY_BEDROCK_LOGS,,}" != "false" ]]; then
    if has_stdbuf_support; then
      exec "${cmd[@]}" \
        > >(stdbuf -oL -eL grep -v -E "${LOG_NOISE_PATTERN}") \
        2> >(stdbuf -oL -eL grep -v -E "${LOG_NOISE_PATTERN}" >&2)
    else
      echo "ℹ️ stdbuf not available; running without LD_PRELOAD tweaks"
      exec "${cmd[@]}" \
        > >(grep -v -E "${LOG_NOISE_PATTERN}") \
        2> >(grep -v -E "${LOG_NOISE_PATTERN}" >&2)
    fi
  else
    exec "${cmd[@]}"
  fi
}

if [ -f /usr/local/bin/box64 ] ; then
  run_bedrock box64 "${BIN_PATH}"
else
  run_bedrock "${BIN_PATH}"
fi
