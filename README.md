# Pocket Server

App personal de iOS en **SwiftUI** (diseño **Liquid Glass** para iOS 26 / iOS 27) para monitorear y controlar un servidor Linux (Fedora Server) y sus contenedores Docker desde el iPhone, compilada y desplegada desde Windows/WSL2 usando **[xtool](https://xtool.sh)** (SwiftPM, sin Xcode ni macOS).

---

## ✨ Funciones

- **Inicio**
  - Estado del servidor: hostname, uptime y refresco **En vivo (cada 4 s)** con pausa automática en segundo plano.
  - Tarjetas de salud: **CPU** (`%` real, load average y temperatura `coretemp`), **RAM + zRAM**, **GPU NVIDIA** (temperatura, uso y VRAM) y resumen de **Docker**.
  - **Accesos rápidos:** enlaces adaptativos (Tailscale HTTPS o LAN HTTP según tu URL base) para **Kavita**, **qBittorrent**, **Jellyfin**, **Suwayomi**, **AdGuard** y **Homepage**, abiertos dentro de la app con `SFSafariViewController`.
- **Almacenamiento**
  - Uso de volúmenes montados (`/` y `/mnt/storage`).
  - Salud del pool **Btrfs** (discos faltantes, espacio asignado/sin asignar, datos reales, libre estimado y perfiles).
  - Inventario de discos físicos (`lsblk`: modelo, `HDD`/`SSD`, interfaz y capacidad) y estado de timers de mantenimiento (`btrfs-scrub`, `btrfs-balance`).
- **Contenedores**
  - Lista completa con controles **Iniciar / Reiniciar / Detener** protegidos por diálogo de confirmación y lista blanca en el servidor.
  - Visor de **logs en vivo** al tocar cualquier contenedor (con selección, copia al portapapeles y refresco).
- **Seguridad y configuración**
  - URL del servidor (Tailscale HTTPS o LAN HTTP) y **Bearer Token** guardados en **iOS Keychain**.

---

## 📁 Estructura del Proyecto

```text
pocket-status-ios/
├── Package.swift                 # Manifiesto SwiftPM (iOS 26.0+)
├── xtool.yml                     # Configuración de bundleID, Info.plist e icono
├── Info.plist                    # Nombre visible y NSAllowsLocalNetworking
├── AppIcon.png                   # Icono de la app (1024x1024 PNG)
├── .env.example                  # Plantilla de URLs privadas (copiar a .env)
├── Sources/PocketStatus/
│   ├── PocketStatusApp.swift     # Punto de entrada SwiftUI
│   ├── ContentView.swift         # Vistas (Inicio, Almacenamiento, Contenedores, Ajustes, Logs)
│   ├── Models.swift              # Modelos Codable y accesos rápidos
│   ├── APIClient.swift           # Cliente HTTP async/await con Bearer Token
│   ├── KeychainStore.swift       # Persistencia en iOS Keychain
│   └── SafariView.swift          # Visor web in-app (SFSafariViewController)
└── .agents/skills/pocket-status-dev/
    └── SKILL.md                  # Runbook de compilación y despliegue para agentes
```

---

## 🛠️ Requisitos y Compilación (Windows + WSL2 + `xtool`)

1. **En WSL2 (Ubuntu):**
   - Swift toolchain (`6.4.2` vía `swiftly`), `libc6-dev`, `gcc`, `zip` y `xtool`.
   - SDK de iOS extraído con `xtool setup` desde un `Xcode.xip` compatible.
2. **Conexión USB estable en Windows (relay TCP `27015`):**
   - Tener instalado `Apple.AppleMobileDeviceSupport` en Windows (en lugar de pasar el USB por `usbipd`, que suele lanzar `Mux error` en WSL2).
   - Reenviar el puerto `27015` hacia la IP puente de WSL (`vEthernet (WSL)`):
     ```powershell
     $wslHostIp = (wsl -d Ubuntu -- ip route list default).Split()[2]
     netsh interface portproxy delete v4tov4 listenport=27015 listenaddress=* 2>$null
     netsh interface portproxy set v4tov4 listenport=27015 connectaddress=127.0.0.1 connectport=27015 listenaddress=$wslHostIp
     ```
3. **Compilar e instalar en el iPhone:**
   ```bash
   source ~/.local/share/swiftly/env.sh
   export USBMUXD_SOCKET_ADDRESS="$(ip route list default | awk '{print $3}'):27015"

   xtool dev build      # Solo compilar
   xtool dev run --usb  # Compilar, firmar e instalar vía USB
   ```

> **Nota sobre firmado gratuito:** con una cuenta estándar de Apple (`Free Provisioning`), el provisioning profile caduca cada **7 días**. Para renovar la app sin perder los datos guardados en Keychain, basta volver a ejecutar `xtool dev run --usb`.

---

## 🔌 Contrato con la Micro-API

La app consume una micro-API REST (en Rust/Axum sobre Tailscale HTTPS o LAN) protegida con `Authorization: Bearer <token>`:

- `GET /status` — Telemetría de sistema, memoria, GPU, discos, pool Btrfs, timers y contenedores.
- `POST /docker/{container}/{action}` — Acciones `start`, `stop` y `restart` restringidas a una lista blanca en el backend.
- `GET /docker/{container}/logs?tail=80` — Últimas líneas de log del contenedor.

Al abrir la app por primera vez, entra a **Ajustes** (icono de engrane) para configurar la URL base (ver `.env.example`, por ejemplo `https://<tu-servidor>.ts.net:9095` o `http://<ip-servidor>:9095`) y tu Bearer Token. Para tu referencia local puedes copiar `.env.example` a `.env` (ignorado por Git).

