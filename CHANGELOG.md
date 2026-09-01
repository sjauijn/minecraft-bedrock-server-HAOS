## 2026.8.2

- Updated `property-definitions.json` to match upstream itzg/docker-minecraft-bedrock-server 2026.8.2 (adds `force-gamemode`, `white-list` (deprecated), `chat-restriction`, `compression-algorithm`, content-log options, script-debugger/watchdog options, `msa-gamertags-only`, `item-transaction-logging-enabled`, and other newly documented `server.properties` keys)
- Bumped bundled tool versions in `build.yaml`/`Dockerfile`: `easy-add` 0.8.14 → 0.8.17, `entrypoint-demoter` 0.5.0 → 0.5.1, `mc-monitor` 0.16.7 → 0.17.1
- Removed unused `configuration` block (~144 keys) from `translations/en.yaml` and `translations/ru.yaml` — it referenced option keys that don't exist in `config.yaml`'s `schema`, so the Supervisor ignored it entirely in both languages. All server settings are managed through the add-on's own web UI instead of the native HAOS options form. Only the still-effective `title`/`config` keys remain
- Normalized `translations/ru.yaml` line endings from CRLF to LF
- Removed unused `__init__.py`, `web/__init__.py`, and `tests/test_app.py` (imported a package that is never built by the Dockerfile) along with stray `.pytest_cache`/`__pycache__` directories
- Added **"Op by player name (offline mode)"** to the web UI's permissions tab. When `online_mode` (Xbox Live authentication) is disabled, Bedrock connects players without a XUID, so the existing XUID-based permission form couldn't assign admin/operator to anyone. This adds a name-based form that calls the server's built-in `op <name>` / `deop <name>` console commands (via the existing `send-command` helper), which match by player name and work without a XUID
- New endpoint `POST /api/op_by_name` (`web/app.py`), accepting `{"name": "...", "action": "op"|"deop"}`; requires the server to be running, since the command is sent over its stdin
- Player name matching is exact and case-sensitive, and is not tied to XUID — a name-changed or impersonated player is treated as a new identity. Intended for trusted local-network servers running with Xbox Live authentication off
- Bumped app version to 2026.8.2

## 2026.6.2

### Breaking change — BDS software is no longer downloaded automatically

The add-on no longer downloads or manages the Minecraft Bedrock Dedicated Server software
on its own. You now upload the server ZIP manually and control which version is installed.

#### New: Manual software installation mode

- Added `Installing/Upgrading Server` configuration option (default `true`)
- When `true`, the add-on runs in install/upgrade mode only — the Bedrock server does not start
- On first run the add-on creates `addon_configs/<slug>/bedrock-server-software/` and waits
- Upload `bedrock-server-<version>.zip` to that directory and restart to install
- After installation, set `Installing/Upgrading Server` to `false` and restart to start the server

#### Install / upgrade logic

- **Fresh install** — installs if no version is currently installed
- **Upgrade** — installs if the ZIP version is newer than the installed version
- **Already installed** — skips without changes and shows a clear log message
- **Downgrade** — blocked by default; requires `Allow Downgrade: true` to proceed

#### New: Downgrade support with safety countdown

- Added `Allow Downgrade` configuration option (default `false`)
- When `true` together with `Installing/Upgrading Server: true`, allows installing an older version
- A warning banner with a **30-second countdown** is printed in the logs before any action
- Stopping the add-on during the countdown cancels the downgrade
- Only the installed server software (`/data/bds/`) is removed during a downgrade
- Worlds (`addon_configs/<slug>/worlds/`) and `bedrock-server-software/` are always preserved
- Setting `Allow Downgrade: true` with `Installing/Upgrading Server: false` is a configuration error — the add-on exits immediately with a clear error message (previously it fell through and started the server anyway — fixed)

#### Persistence fix

- Installed server binary and libraries are now stored in `/data/bds/` (persistent volume)
  instead of `/opt/bds/` (Docker image layer that was wiped on every container restart)
- Installed version is tracked in `/data/.installed-bds-version` (persistent)

#### Runtime fix

- BDS is now launched with its working directory set to `/data/bds/` so it correctly
  resolves `server.properties`, `allowlist.json`, `permissions.json`, and `worlds/` by
  relative path, as Mojang's binary requires

#### README

- Fully rewritten to reflect manual software management workflow
- Added Software Management configuration section
- Added directory layout reference
- Added step-by-step installation guide
- Added upgrade and downgrade procedures
- Betrouwbare update-flow voor de add-on
- Onderhoudsreleases zonder handmatige migratie
