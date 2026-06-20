# Minecraft Bedrock Server Add-on for Home Assistant

Run your own **Minecraft Bedrock Server** directly inside Home Assistant — with support for manual software installation, multiple worlds, MCPack installation, and full configuration through the HA UI.

This add-on is designed for **simplicity**, **performance**, and **zero-maintenance hosting** for families, kids, or LAN-based multiplayer.

**Important:** EULA must be accepted in the add-on UI before the server will start.

---

## Credits & acknowledgements

This add-on builds upon several excellent open-source tools.
Full credit and appreciation go to the original authors and maintainers:

| Tool | Purpose | Author / Project |
|-----|--------|------------------|
| **MC Monitor** | Health checks and server availability monitoring | [itzg](https://github.com/itzg/) |
| **Entrypoint Demoter** | Secure privilege dropping for container entrypoints | [itzg](https://github.com/itzg/) |
| **Set-property** | Safe and declarative configuration file updates | [itzg](https://github.com/itzg/) |
| **Restify** | Lightweight REST API helper for runtime control | [itzg](https://github.com/itzg/) |
| **Easy Add** | Simplified add-on runtime utilities | [itzg](https://github.com/itzg/) |

---

## ✨ Features

| Feature | Description |
|:--------|:--------------|
| Bedrock Dedicated Server | Runs the official Mojang Bedrock Server inside Home Assistant |
| Manual software management | You control which version is installed — no automatic downloads |
| Worlds accessible via SFTP | World saves stored in `addon_configs/<slug>/worlds/`, reachable without Portainer or Docker console |
| Upgrade support | Upload a newer ZIP to upgrade the server software |
| Downgrade support | Optionally install an older version with a 30-second safety countdown |
| World configuration | Seeds, world type, difficulty, gamemode & cheats |
| Player management | Whitelist/allowlist, default permissions, max player limit |
| Performance tuning | View distance, tick distance, multithreading, compression |
| Anti-cheat controls | Server authoritative movement & validation thresholds |
| Easy UI | Configuration through HA UI with friendly labels & dropdowns |
| LAN visibility toggle | Enable/disable server broadcast on local network |
| Works with host network | No port mapping headaches — plug & play |

---

## 🏗 Installation

1. Add this repository to Home Assistant Add-on Store:
   `https://github.com/sjauijn/minecraft-bedrock-server-HAOS`
2. Install the **Minecraft Bedrock Server** add-on
3. Start the add-on — it will create the `bedrock-server-software` directory and wait
4. Download the **Bedrock Dedicated Server for Ubuntu/Debian** ZIP from:
   https://www.minecraft.net/download/server/bedrock
5. Upload the ZIP (e.g. `bedrock-server-1.26.21.1.zip`) to:
   `addon_configs/<slug>/bedrock-server-software/`
6. Restart the add-on — it will install the software automatically
7. Set **Installing/Upgrading Server** to `false` in the Configuration tab
8. Restart the add-on — the server starts
9. Accept the EULA in the add-on UI and restart one final time

> The `bedrock-server-software` directory and your `worlds` are never deleted, even during a downgrade.

---

## 📦 Manual Software Management

### Installing or upgrading

1. In Configuration, set **Installing/Upgrading Server** to `true`
2. Upload `bedrock-server-<version>.zip` to `addon_configs/<slug>/bedrock-server-software/`
3. Restart the add-on
4. After installation completes, set **Installing/Upgrading Server** to `false` and restart

The add-on compares the ZIP version against the installed version and:

- **Fresh install** — installs if nothing is currently installed
- **Upgrade** — installs if the ZIP version is newer than the installed version
- **Already installed** — skips without changes if the same version is present
- **Downgrade** — blocked by default; enable `Allow Downgrade` to proceed

### Downgrading

To install an older version than the one currently installed:

1. Set **Allow Downgrade** to `true` AND **Installing/Upgrading Server** to `true`
2. Upload the older `bedrock-server-<version>.zip` to the software directory
3. Restart the add-on

A warning banner appears in the logs with a **30-second countdown**. Stop the add-on during this window to cancel. After the countdown, the installed server software is removed and replaced with the older version. Your worlds and configuration are fully preserved.

> Setting `Allow Downgrade: true` with `Installing/Upgrading Server: false` is a configuration error — the add-on will refuse to start and display a clear error in the logs. After completing a downgrade, set both options back to `false`.

### Directory layout

```
addon_configs/<slug>/
├── bedrock-server-software/    <- upload bedrock-server-*.zip here
└── worlds/                     <- your world saves (accessible via SFTP)

/data/
├── bds/                        <- installed server binary and libraries
├── .installed-bds-version      <- tracks the installed version
└── server.properties           <- server configuration
```

---

## ⚙️ Configuration

All settings can be modified via the Home Assistant Add-on UI.

### 🔧 Software Management

| Setting | Default | Description |
|:--------|:--------|:------------|
| Installing/Upgrading Server | `true` | When `true`, the add-on runs in install/upgrade mode only — the Bedrock server will not start |
| Allow Downgrade | `false` | When `true` (combined with Installing/Upgrading Server), allows installing an older version with a 30-second safety countdown |

---

### 🧩 General

Core server behavior such as name, ports, online mode, and LAN visibility.

| Setting | Description |
|:--------|:------------|
| Display name | Name shown in the Minecraft server list |
| Port (IPv4/IPv6) | Ports used for Bedrock server |
| Online verification | Require Microsoft/Xbox authentication |
| LAN visibility | Broadcast server on LAN |
| Send telemetry | Allow usage analytics to Microsoft |

---

### 🌍 World

Controls how your world looks, feels, and behaves.

| Setting | Options |
|:--------|:--------|
| World name | Any text |
| World seed | Number or text seed |
| World type | Default / Flat / Legacy |
| Game mode | Survival / Creative / Adventure |
| Difficulty | Peaceful / Easy / Normal / Hard |
| Allow cheats | Yes/No |

---

### 👥 Players

| Setting | Description |
|:--------|:------------|
| Max players | Maximum number of concurrent players |
| Whitelist / Allowlist | Restrict players |
| Default permission | Visitor / Member / Operator |
| Require texture pack | Force clients to install server pack |

---

### 🚀 Performance

Tweak simulation radius, CPU usage & bandwidth.

| Setting | Description |
|:--------|:----------------|
| View distance | Render distance for players |
| Simulation distance | Radius where mobs & redstone tick |
| Idle timeout | Kick inactive players |
| Max threads | 0 = auto |
| Compression threshold | Lower uses more CPU, less bandwidth |

---

### 🛡 Anti-Cheat & Movement

Server authoritative movement ensures fair gameplay and prevents hacked clients.

| Setting | Options |
|:--------|:--------|
| Movement authority | Client / Server / Server+Rewind |
| Block breaking validation | Validate block break actions |
| Score threshold | Cheating sensitivity |
| Distance & duration thresholds | Movement tolerance |
| Correct movement | Fixes illegal movement via teleport |
