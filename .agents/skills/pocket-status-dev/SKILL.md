---
name: pocket-status-dev
description: >-
  Build, sign, and deploy the Pocket Status iOS app from Windows/WSL2 with xtool
  and update its companion Rust API on Fedora. Use when compiling PocketStatus,
  deploying to iPhone over USB from WSL, troubleshooting WSL usbmuxd/muxError, or
  updating pocket-status-api on the Fedora server.
---

# Pocket Status Build & Deploy Runbook

## 1. Prerequisites on Windows + WSL2 (`Ubuntu`)

The reliable deployment path bypasses `usbipd` (which drops AFC transfers with `Mux error (-8)` / `[Connecting] 100%` hangs) and relays through Windows `Apple Mobile Device Service` on TCP `27015`.

1. Ensure the iPhone is unlocked, trusted in Windows, and **not** bound in `usbipd` (`usbipd list` should not show `Attached`).
2. Verify Windows `AppleMobileDeviceService` is listening on `127.0.0.1:27015` and forwarded to the current WSL vEthernet gateway IP:
   ```powershell
   netstat -ano | findstr ":27015"
   netsh interface portproxy show all
   ```
3. If the WSL gateway IP changed after a Windows reboot, refresh `portproxy` in **PowerShell (Admin)** using the IP returned in WSL by `ip route list default | awk '{print $3}'`:
   ```powershell
   $wslHostIp = (wsl -d Ubuntu -- ip route list default).Split()[2]
   netsh interface portproxy delete v4tov4 listenport=27015 listenaddress=* 2>$null
   netsh interface portproxy set v4tov4 listenport=27015 connectaddress=127.0.0.1 connectport=27015 listenaddress=$wslHostIp
   ```
   Confirm the firewall rule `WSL usbmuxd` allows inbound traffic on `vEthernet (WSL (Hyper-V firewall))`.

**Done when:** in WSL, `USBMUXD_SOCKET_ADDRESS="$(ip route list default | awk '{print $3}'):27015" ideviceinfo -s` prints `DeviceName` and `ProductVersion`.

## 2. Build & Deploy iOS App (`xtool`)

### Preferred Flow: `.ipa` + Taildrop (no USB cable)

1. Ensure `POCKET_SERVER_TAILDROP_TARGET` is set in `.env` (see `.env.example`) and the iPhone is visible in `tailscale file cp --targets`.
2. Build `xtool/PocketStatus.ipa` and send it over Tailscale:
   ```powershell
   .\scripts\send-ipa.ps1
   ```
   Or manually from WSL + Windows:
   ```bash
   source ~/.local/share/swiftly/env.sh
   xtool dev build -c release --ipa   # add --sign if you want xtool signing embedded
   ```
   ```powershell
   tailscale file cp .\xtool\PocketStatus.ipa "<taildrop-target>:"
   ```
3. On the iPhone, accept the Taildrop file (Files app) and import/install it in **SideStore** (SideStore signs on-device and handles 7-day renewals without USB).

### Fallback Flow: Direct USB (`xtool dev run --usb`)

Run from WSL inside the project root:

```bash
cd "/mnt/c/Users/Cesar Denogean/Documents/Proyectos/pocket-status-ios"
source ~/.local/share/swiftly/env.sh
export USBMUXD_SOCKET_ADDRESS="$(ip route list default | awk '{print $3}'):27015"

# Compile check only
xtool dev build

# Compile, sign, package, and install onto connected iPhone
xtool dev run --usb
```

- **App Icon:** `xtool.yml` uses `iconPath: AppIcon.png` (must remain an opaque `1024x1024` `.png`; non-png extensions fail validation).
- **7-day free provisioning:** if the app expires after 7 days or provisioning fails with `ENTITY_ERROR` right after certificate renewal, wait ~30s and re-run `xtool dev run --usb` (or refresh in SideStore).
- **LAN HTTP:** `Info.plist` enables `NSAllowsLocalNetworking` so both Tailscale HTTPS and LAN HTTP URLs from `.env` (see `.env.example`) work.

**Done when:** `xtool/PocketStatus.ipa` is delivered via `tailscale file cp` (exit code 0) or `xtool dev run --usb` finishes with `[Installing] 100%` and `[Verifying] 100%`.

## 3. Update Companion Rust API (`servidor-fedora`)

Source lives in `C:\Users\Cesar Denogean\Documents\Proyectos\servidor-fedora\pocket-status-api`. Port `9095` is used because `9090` is reserved by Cockpit on Fedora Server.

1. Sync source using `POCKET_SERVER_SSH_HOST` from `.env` and run tests + release build via `rust:1-slim` Docker on Fedora:
   ```powershell
   # Load POCKET_SERVER_SSH_HOST from .env (e.g. user@192.168.1.100)
   scp -r "C:\Users\Cesar Denogean\Documents\Proyectos\servidor-fedora\pocket-status-api\*" "$env:POCKET_SERVER_SSH_HOST`:~/server/pocket-status-src/"
   ```
   ```bash
   source .env
   ssh "$POCKET_SERVER_SSH_HOST" '
     set -e
     docker run --rm -v ~/server/pocket-status-src:/app -v pocket-status-cargo:/usr/local/cargo/registry -w /app rust:1-slim sh -c "cargo test && cargo build --release"
     systemctl --user stop pocket-status.service
     cp ~/server/pocket-status-src/target/release/pocket-status-api ~/server/pocket-status/pocket-status-api
     systemctl --user start pocket-status.service
   '
   ```
   *(Always stop `pocket-status.service` before `cp` to avoid `Text file busy`.)*

**Done when:** `systemctl --user is-active pocket-status.service` outputs `active` and `GET /status` returns `200` with Bearer auth (`~/server/pocket-status/.env`).

