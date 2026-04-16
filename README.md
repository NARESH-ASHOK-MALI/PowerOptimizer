# ⚡ PowerOptimizer v6.1

**A comprehensive Windows power management script built for the Asus Vivobook Pro OLED (M3500QC).**

Dynamically switches between battery-saving and performance profiles by controlling the CPU, GPU, display, storage, services, and USB devices — all from a single batch script with an interactive TUI menu.

---

## 📋 Table of Contents

- [Hardware Profile](#-hardware-profile)
- [Features](#-features)
- [Power Modes](#-power-modes)
- [Quick Start](#-quick-start)
- [Usage](#-usage)
- [Command-Line Shortcuts](#-command-line-shortcuts)
- [What Each Mode Does](#-what-each-mode-does)
- [OLED Care](#-oled-care)
- [Safety Notes](#-safety-notes)
- [Known Limitations](#-known-limitations)
- [Logs & Reports](#-logs--reports)
- [Changelog](#-changelog)

---

## 💻 Hardware Profile

| Component | Specification |
|-----------|--------------|
| **Model** | Asus Vivobook Pro OLED M3500QC |
| **CPU** | AMD Ryzen 5 5600H (6C/12T, 45W TDP) |
| **iGPU** | AMD Radeon Graphics (Vega 7) |
| **dGPU** | NVIDIA GeForce RTX 3050 4GB |
| **RAM** | 16 GB DDR4 |
| **Storage** | 512 GB NVMe SSD |
| **Display** | 15.6" Samsung OLED 60Hz (AMOLED) |
| **BIOS** | M3500QC.316 (Latest) |

> [!NOTE]
> This script is tailored specifically for the M3500QC hardware. It uses Optimus (no MUX switch) — the internal OLED is wired to the AMD iGPU, and the RTX 3050 renders through it.

---

## ✨ Features

- **4 Power Modes** — Ultra Battery Saver, Max Performance, Balanced, and Ultra Performance (NVIDIA-preferred)
- **GPU Switching** — Toggle RTX 3050 on/off, saving 15-25W on battery
- **CPU Tuning** — AMD Precision Boost control, core parking, EPP, and throttle management
- **OLED Optimizations** — Brightness control, dark mode, black wallpaper (0W for black pixels)
- **NVMe Power Management** — APST, link PM, and latency tolerance tuning
- **USB Device Management** — Selective suspend for webcam and peripherals
- **Service Management** — Stops/starts Windows Search, SysMain, NVIDIA, MongoDB, and more
- **Process Killer** — Terminates power-hungry apps (Docker, Steam, Discord, browsers, etc.)
- **Edge Timer Fix** — Disables Edge's 1ms timer resolution that prevents CPU deep sleep
- **Energy Saver Control** — Forces Windows Energy Saver on/off via multiple methods
- **Battery Protection** — Low battery warnings at 20%, auto-hibernate at 8%
- **Network Saver** — Bluetooth/Wi-Fi power control
- **Startup Cleanup** — Disable bloatware auto-start entries
- **OLED Care** — Burn-in protection tools (dark mode, auto-hide taskbar, screen saver)
- **Battery Health Report** — HTML battery report with health analysis
- **Quick Re-apply** — Fix settings that reset after sleep/wake cycles
- **System Status Dashboard** — Live hardware monitoring
- **Logging** — All actions logged with automatic log rotation (500 lines max)
- **Auto-Elevation** — Automatically requests admin privileges via UAC

---

## 🔋 Power Modes

| Mode | CPU | GPU | Brightness | Sleep | Best For |
|------|-----|-----|-----------|-------|----------|
| **Ultra Battery Saver** | 40%, Boost OFF | RTX 3050 OFF | 25% | 5 min | Maximum battery life |
| **Max Performance** | 100%, Boost AGG | RTX 3050 ON | 85% | Never | Plugged-in workloads |
| **Balanced** | 100%, Boost Efficient | Hybrid Optimus | 60% | 15 min | Everyday use |
| **Ultra Performance** | 100% min+max, Boost AGG | RTX 3050 renders ALL | 85% | Never | Gaming, rendering |

---

## 🚀 Quick Start

### Requirements

- **Windows 10/11** (tested on Windows 11)
- **Administrator privileges** (script auto-elevates)
- **PowerShell 5.1+** (built into Windows)

### Run

Double-click `PowerOptimizer.bat` or run from terminal:

```cmd
PowerOptimizer.bat
```

The script will auto-request admin privileges if needed, then present the interactive menu.

---

## 📖 Usage

### Interactive Menu

```
  +==============================================================+
  :     ASUS VIVOBOOK PRO OLED - POWER OPTIMIZER  v6.1           :
  +==============================================================+

   [1]  Ultra Battery Saver     Max battery life
   [2]  Max Performance          Full power (plugged in)
   [3]  Balanced Mode            Everyday use
   [4]  GPU Switch               Toggle RTX 3050 / Radeon iGPU
   [5]  System Status            Live hardware dashboard
   [6]  Battery Health Report    HTML report + energy audit
   [7]  Network Saver            Bluetooth/Wi-Fi power control
   [8]  Startup Cleanup          Disable bloatware auto-start
   [9]  OLED Care                Screen burn-in protection
   [U]  Ultra Performance        NVIDIA rendering mode
   [R]  Quick Re-apply           Re-apply saver after wake
   [0]  Exit
```

The menu shows a live status dashboard including power source, battery level, estimated remaining time, active power plan, and active GPU.

---

## ⌨️ Command-Line Shortcuts

Skip the menu entirely with command-line arguments:

```cmd
PowerOptimizer.bat 1    :: Ultra Battery Saver
PowerOptimizer.bat 2    :: Max Performance
PowerOptimizer.bat 3    :: Balanced
PowerOptimizer.bat 4    :: Ultra Performance
PowerOptimizer.bat G    :: GPU Switch
PowerOptimizer.bat S    :: System Status
PowerOptimizer.bat H    :: Battery Health Report
PowerOptimizer.bat N    :: Network Saver
PowerOptimizer.bat C    :: Startup Cleanup
PowerOptimizer.bat O    :: OLED Care
PowerOptimizer.bat R    :: Quick Re-apply
```

---

## 🔍 What Each Mode Does

### [1] Ultra Battery Saver (15 steps)

Designed for maximum battery life on the go:

1. Kills PowerToys (Awake module blocks sleep)
2. Kills heavy background apps (Docker, Steam, Discord, Spotify, Adobe, Widgets, MongoDB, NVIDIA, Asus bloat)
3. Optionally closes all browsers
4. **Disables RTX 3050** — forces iGPU only, saves ~15-25W
5. Sets Power Saver plan + Best Power Efficiency slider
6. Throttles CPU to 40%, disables Precision Boost, enables aggressive core parking
7. OLED: 25% brightness, dark mode, black wallpaper, 2-min screen timeout
8. NVMe: enables APST + aggressive link PM
9. USB selective suspend ON, PCIe max savings, Wi-Fi max power saving
10. Stops services: Windows Search, Update, SysMain, Diagnostics, Print Spooler, NVIDIA
11. Disables scheduled tasks (Compatibility Appraiser, NVIDIA telemetry, etc.)
12. Fixes Edge 1ms timer resolution (kills Edge, disables background mode)
13. Enables USB selective suspend on webcam and Samsung phone
14. Forces Windows Energy Saver ON (threshold 100%)
15. Sets low battery protection: warn at 20%, auto-hibernate at 8%

### [2] Max Performance (10 steps)

Full power when plugged in:

- Starts PowerToys
- Enables RTX 3050 + NVIDIA services
- Ultimate Performance power plan
- CPU 100%, Boost Aggressive, all 12 threads active
- OLED 85%, always on, no sleep
- NVMe max throughput
- All PM disabled (USB, PCIe, Wi-Fi)
- All services restored
- Energy Saver OFF

### [3] Balanced (6 steps)

Everyday defaults:

- RTX 3050 in hybrid Optimus mode
- Balanced power plan
- CPU 100% max, Boost Efficient, EPP 50
- OLED 60%, moderate timeouts
- Services restored, tasks re-enabled
- GPU preferences reset to Optimus auto

### [U] Ultra Performance (12 steps)

Everything on the RTX 3050:

- Forces ALL rendering to RTX 3050 (iGPU stays as display bridge)
- NVIDIA PowerMizer disabled (max clocks always)
- CPU locked at 100% min+max, Boost Aggressive
- Zero core parking, EPP 0
- All power management disabled

> [!WARNING]
> This mode uses extreme power. Keep the laptop plugged in — battery drains very fast if unplugged.

### [R] Quick Re-apply

Fixes power settings that Windows resets after sleep/wake:

- Detects power source (skips if plugged in)
- Re-kills processes that restarted during sleep
- Re-applies CPU throttle + boost settings
- Resets OLED brightness to 25%
- Verifies RTX 3050 is still disabled

---

## 🖥️ OLED Care

Dedicated tools to protect the Samsung OLED panel from burn-in:

| Option | Description |
|--------|-------------|
| Dark mode + black wallpaper | Black pixels = zero power draw on OLED |
| Auto-hide taskbar | Prevents taskbar burn-in (biggest risk area) |
| 2-minute screen timeout | Prevents static image damage |
| Safe brightness (70%) | High brightness accelerates pixel degradation |
| Blank screen saver | 5-minute timeout, all pixels off |

---

## ⚠️ Safety Notes

### What the script modifies

| Category | Reversible? | Details |
|----------|-------------|---------|
| Power plans | ✅ Yes | `powercfg` settings, restored by Balanced mode |
| Registry keys | ✅ Yes | Edge policies, dark mode, energy saver, GPU prefs |
| Windows services | ✅ Yes | Stopped/started, never uninstalled |
| Scheduled tasks | ✅ Yes | Disabled/enabled, never deleted |
| Running processes | ⚠️ Partial | Killed processes (unsaved work may be lost) |
| GPU state | ✅ Yes | RTX 3050 disabled/enabled via PnP |
| MongoDB service | ✅ Yes | Start type changed between `demand` and `auto` |

### Devices that are safely handled

- **NVIDIA RTX 3050** — Enabled/disabled via `Disable-PnpDevice` (standalone PCIe device, safe)
- **Webcam (VID_13D3/PID_3563)** — Only `SelectiveSuspendEnabled` registry is set. The device is **never** disabled because it shares a USB composite hub with the Bluetooth controller
- **Samsung phone (VID_04E8/PID_6863)** — Only `SelectiveSuspendEnabled` registry is set

> [!CAUTION]
> **Never disable the webcam via `Disable-PnpDevice`** — it is a USB Composite Device that also hosts the physical Bluetooth controller. Disabling it kills Bluetooth hardware.

### Browser kill behavior

The `KILL_BROWSERS` config variable (line 24) controls whether browsers are closed in battery saver mode. Set to `0` to keep browsers open:

```batch
set "KILL_BROWSERS=0"
```

---

## 🚧 Known Limitations

| Limitation | Reason |
|-----------|--------|
| **PCIe ASPM cannot be enabled** | Disabled at BIOS level (M3500QC.316 hardware incompatibility). No newer BIOS available. OS-level `powercfg` sets intent but cannot override BIOS. |
| **No MUX switch** | Optimus-only laptop. The internal OLED is wired to the AMD iGPU. The iGPU cannot be disabled (black screen). Ultra Performance uses the iGPU as a display bridge. |
| **Modern Standby only** | S3 sleep is not supported. The laptop uses Connected Standby (S0 low-power idle). |
| **Service stop delay** | Stopping Windows services takes ~30 seconds consistently. This is a Windows limitation. |
| **Settings reset after wake** | Windows may reset CPU throttle, brightness, and restart killed processes after wake from sleep. Use **Quick Re-apply [R]** to fix. |

---

## 📊 Logs & Reports

| File | Description |
|------|-------------|
| `PowerOptimizer.log` | All actions with timestamps, auto-rotated at 500 lines |
| `battery-report.html` | Windows battery health report (generated via menu option 6) |
| `energy-report.html` | Windows energy efficiency report (60-second scan, option 6) |
| `test13_04.log` | Detailed analysis session log with bug tracking and baselines |

---

## 📝 Changelog

### v6.1 (2026-04-16)
- **CRITICAL FIX**: Removed `Disable-PnpDevice` on webcam (VID_13D3/PID_3563) — was killing the Bluetooth controller via shared USB composite hub
- Webcam now only uses `SelectiveSuspendEnabled` registry setting (safe, non-destructive)
- Removed corresponding `Enable-PnpDevice` for webcam in Balanced mode
- Updated all comments, banners, and log messages

### v6.0 (2026-04-13)
- Added log rotation (500 lines max)
- Fixed critical battery GUID conflict (hibernate action vs energy saver threshold)
- Fixed PowerToys wildcard `taskkill` (silently failing)
- Added GPU preference reset in Balanced mode
- Added power source detection in Quick Re-apply
- Fixed disk space integer overflow (PowerShell replacement)
- Added webcam `Disable-PnpDevice` *(reverted in v6.1 — killed Bluetooth)*
- Added MongoDB `demand` start type in saver mode
- Updated all summary banners

### v5.1 and earlier
- Core saver/performance/balanced modes
- Edge timer fix, USB suspend, NVIDIA task disable
- Samsung phone USB handling, low battery protection
- Ultra Performance mode (NVIDIA-preferred rendering)
- Quick Re-apply mode for post-wake fixes

---

## 📄 License

Personal use. This script is tailored for a specific hardware configuration (Asus Vivobook Pro OLED M3500QC). Adapt settings for other hardware at your own risk.
