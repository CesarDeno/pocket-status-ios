# Pocket Server

Personal **SwiftUI** iOS app (**Liquid Glass** design for iOS 26 / iOS 27) to monitor and control a Linux home server (Fedora Server) and its Docker containers from an iPhone, built and deployed from Windows/WSL2 using **[xtool](https://xtool.sh)** (SwiftPM, without Xcode or macOS).

---

## ✨ Features

- **Home (`Inicio`)**
  - Server overview: hostname, uptime, and **Live refresh (every 4s)** with automatic pause when backgrounded.
  - Health cards: **CPU** (live `%`, load average, and `coretemp` temperature), **RAM + zRAM**, **NVIDIA GPU** (temperature, utilization, and VRAM), and **Docker** summary.
  - **Quick Shortcuts:** adaptive links (Tailscale HTTPS or LAN HTTP based on your configured base URL) for **Kavita**, **qBittorrent**, **Jellyfin**, **Suwayomi**, **AdGuard**, and **Homepage**, opened in-app via `SFSafariViewController`.
- **Storage (`Almacenamiento`)**
  - Mounted volume usage (`/` and `/mnt/storage`).
  - **Btrfs** pool health (missing devices, allocated vs. unallocated space, actual data usage, estimated free space, and profiles).
  - Physical drive inventory (`lsblk`: model, `HDD`/`SSD`, interface, and capacity) plus systemd maintenance timer status (`btrfs-scrub`, `btrfs-balance`).
- **Containers (`Contenedores`)**
  - Full container list with **Start / Restart / Stop** controls protected by confirmation dialogs and a server-side allowlist.
  - **Live log viewer** when tapping any container (text selection, copy to clipboard, and manual refresh).
- **Security & Configuration**
  - Base URL (Tailscale HTTPS or LAN HTTP) and **Bearer Token** stored securely in **iOS Keychain**.

---

## 📁 Project Structure

```text
pocket-status-ios/
├── Package.swift                 # SwiftPM manifest (iOS 26.0+)
├── xtool.yml                     # bundleID, Info.plist, and app icon config
├── Info.plist                    # Display name and NSAllowsLocalNetworking
├── AppIcon.png                   # App icon (1024x1024 PNG)
├── .env.example                  # Private URL template (copy to .env)
├── Sources/PocketStatus/
│   ├── PocketStatusApp.swift     # SwiftUI app entry point
│   ├── ContentView.swift         # Views (Home, Storage, Containers, Settings, Logs)
│   ├── Models.swift              # Codable models and service shortcuts
│   ├── APIClient.swift           # Async/await HTTP client with Bearer auth
│   ├── KeychainStore.swift       # iOS Keychain persistence
│   └── SafariView.swift          # In-app browser (SFSafariViewController)
└── .agents/skills/pocket-status-dev/
    └── SKILL.md                  # Build and deploy runbook for coding agents
```

---

## 🛠️ Requirements & Build (Windows + WSL2 + `xtool`)

1. **In WSL2 (Ubuntu):**
   - Swift toolchain (`6.4.2` via `swiftly`), `libc6-dev`, `gcc`, `zip`, and `xtool`.
   - iOS Darwin SDK extracted with `xtool setup` from a compatible `Xcode.xip`.
2. **Reliable USB Connection on Windows (TCP `27015` relay):**
   - Install `Apple.AppleMobileDeviceSupport` on Windows (instead of passing USB via `usbipd`, which frequently drops with `Mux error` in WSL2).
   - Forward port `27015` to the WSL bridge gateway IP (`vEthernet (WSL)`):
     ```powershell
     $wslHostIp = (wsl -d Ubuntu -- ip route list default).Split()[2]
     netsh interface portproxy delete v4tov4 listenport=27015 listenaddress=* 2>$null
     netsh interface portproxy set v4tov4 listenport=27015 connectaddress=127.0.0.1 connectport=27015 listenaddress=$wslHostIp
     ```
3. **Build & Install onto iPhone:**
   ```bash
   source ~/.local/share/swiftly/env.sh
   export USBMUXD_SOCKET_ADDRESS="$(ip route list default | awk '{print $3}'):27015"

   xtool dev build      # Compile only
   xtool dev run --usb  # Compile, sign, and install over USB
   ```

> **Free provisioning note:** with a standard free Apple ID (`Free Provisioning`), the provisioning profile expires every **7 days**. Re-running `xtool dev run --usb` refreshes the signature without erasing Keychain data.

---

## 🔌 Micro-API Contract

The app connects to a companion REST micro-API (Rust/Axum over Tailscale HTTPS or LAN) protected with `Authorization: Bearer <token>`:

- `GET /status` — System, memory, GPU, disk, Btrfs pool, maintenance timers, and Docker container telemetry.
- `POST /docker/{container}/{action}` — `start`, `stop`, and `restart` actions restricted to a backend allowlist.
- `GET /docker/{container}/logs?tail=80` — Recent log lines for a container.

On first launch, open **Settings** (gear icon) to enter your base URL (see `.env.example`, e.g. `https://<your-server>.ts.net:9095` or `http://<server-ip>:9095`) and Bearer Token. For local reference, copy `.env.example` to `.env` (gitignored).
