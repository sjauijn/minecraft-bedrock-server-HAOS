## 1.0.31 - 2026-06-20

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

## 1.0.28 - 2026-06-19
- Updated Bedrock Server from '1.26.30.5' to '1.26.31.1

## 1.0.27 - 2026-06-11
- Fix: create /config/worlds in start.sh before privilege demotion to avoid "Permission denied"
- Fix: bedrock-entry.sh now falls back to /data/worlds if /config/worlds is unavailable

## 1.0.26 - 2026-06-11
- Fix: create /config/worlds in start.sh before privilege demotion to avoid "Permission denied"
- Fix: bedrock-entry.sh now falls back to /data/worlds if /config/worlds is unavailable

## 1.0.25 - 2026-06-11
- Moved `worlds` directory from `/data/worlds/` to `/addon_configs/mc_server_ha/worlds/` for SFTP accessibility
- Added automatic migration of existing worlds on first start
- Added `addon_config:rw` mapping to config.yaml

## 1.0.24 - 2026-06-09
- Updated ENTRYPOINT_DEMOTER from '0.4.10' to '0.5.0'%0A

## 1.0.23 - 2026-05-26
- Updated MC_MONITOR from '0.16.5' to '0.16.6'%0A

## 1.0.22 - 2026-05-26
- Updated Bedrock Server from '1.26.21.1' to '1.26.23.1'


## 1.0.21 - 2026-05-18
- Updated EASY_ADD from '0.8.12' to '0.8.13'%0A- Updated RESTIFY from '1.7.13' to '1.7.14'%0A

## 1.0.20 - 2026-05-18
- Updated MC_MONITOR from '0.16.4' to '0.16.5'%0A

## 1.0.19 - 2026-05-17
- Updated MC_MONITOR from '0.16.3' to '0.16.4'%0A

## 1.0.18 - 2026-05-17
- Updated MC_MONITOR from '0.16.2' to '0.16.3'%0A

## 1.0.17 - 2026-05-14
- Updated Bedrock Server from '1.26.20.5' to '1.26.21.1'


## 1.0.16 - 2026-05-12
- Updated EASY_ADD from '0.8.11' to '0.8.12'%0A- Updated SET_PROPERTY from '0.1.5' to '0.1.6'%0A- Updated ENTRYPOINT_DEMOTER from '0.4.9' to '0.4.10'%0A

## 1.0.15 - 2026-05-05
- Updated Bedrock Server from '1.26.14.1' to '1.26.20.5'


## 1.0.14 - 2026-04-26
- Updated RESTIFY from '1.7.12' to '1.7.13'
- Updated MC_MONITOR from '0.16.1' to '0.16.2'

## 1.0.13 - 2026-04-10
- Updated Bedrock Server from '1.26.13.1' to '1.26.14.1'

## 1.0.12 - 2026-04-06
- Updated Bedrock Server from '1.26.12.2' to '1.26.13.1'

## 1.0.11 - 2026-03-31
- Updated Bedrock Server from '1.26.11.1' to '1.26.12.2'

## 1.0.10 - 2026-03-27
- Updated Bedrock Server from '1.26.10.4' to '1.26.11.1'

## 1.0.9 - 2026-03-24
- Updated Bedrock Server from '1.26.3.1' to '1.26.10.4'

## 1.0.8 - 2026-03-02
- Updated Bedrock Server from '1.26.2.1' to '1.26.3.1'

## 1.0.7 - 2026-02-25
- Updated Bedrock Server from '1.26.1.1' to '1.26.2.1'

## 1.0.6 - 2026-02-19
- Updated Bedrock Server from '1.26.0.2' to '1.26.1.1'

## 1.0.5 - 2026-02-10
- Updated Bedrock Server from '1.21.132.3' to '1.26.0.2'

## 1.0.4 - 2026-02-09
- Updated MC_MONITOR from '0.16.0' to '0.16.1'

## 1.0.3 - 2026-02-08
- Updated RESTIFY from '1.7.11' to '1.7.12'

## 1.0.2 - 2026-01-09
- Updated Bedrock Server from '1.21.132.1' to '1.21.132.3'

## 1.0.1 - 2026-01-08
- Updated Bedrock Server from '1.21.131.1' to '1.21.132.1'

### Functionaliteit (toegevoegd na 1.0.0)
- Addon met Minecraft Bedrock Dedicated Server
- Correcte runtime-afhandeling met juiste working directory en data path
- Health checks en procesbewaking (MC Monitor)
- Detectie en selectie van meerdere werelden (niet simultaan)
- World switching via configuratie
- World-specifieke seeds
- Opslag van seeds per wereld in `/data/worldconfiguration.json`
- Automatisch opslaan van ontbrekende seeds bij bestaande werelden
- Nieuwe werelden en seeds direct beschikbaar in de UI
- Worldnaam en seed zijn immutable na aanmaak
- Logging van worldnaam en seed bij serverstart
- EULA-afhandeling via configuratie (default `false`)
- Server start niet zonder expliciete EULA-acceptatie
- Config-gedreven world detectie en selectie
- Volledige bediening via Home Assistant Ingress
- Actief AppArmor-profiel voor de add-on
- Toegestane helper binaries (o.a. `stdbuf`, `timeout`, `find`, `sleep`, `mkdir`, `rm`, `tail`)
- Toegang tot `/usr/libexec` voor stdbuf/preload-detectie
- Runtime-bestanden uitsluitend in schrijfbare directories
- Add-on uitsluitend toegankelijk via Ingress (deny-all, ingress-only)
- Gecontroleerde log-output zonder LD_PRELOAD-warnings
- Fallback logging indien `stdbuf` niet beschikbaar is
- Watchdog-loop voor stabiele procesbewaking

Package met (allen geleverd door https://github.com/itzg)
- Entrypoint Demoter
- MC Monitor
- Set-property
- Restify
- Easy Add
- GitHub Actions voor automatische Bedrock-versiedetectie en update
- Automatische update van build parameters (`build.yaml`)
- Gesynchroniseerd add-on versiebeheer
- Logo en icon toegevoegd
- Betrouwbare update-flow voor de add-on
- Onderhoudsreleases zonder handmatige migratie
