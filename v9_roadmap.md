# PowerOptimizer v9.0 Roadmap & Backlog
*Compiled on: 2026-07-05*
*Completed on: 2026-07-18*

This document served as a backlog for the **v9.0 update**. All items have been implemented.

## ✅ Completed in v9.0

### 1. MongoDB Start Type in Performance Modes ✅
*   **Issue:** MongoDB was set to `demand` start in Battery Saver and PSB modes but not restored to `auto` in Max Performance or Ultra Performance modes.
*   **Fix Applied:** Added `sc config MongoDB start= auto` to both `:performance` and `:ultraperformance` service blocks.

### 2. Scheduled Task Logging Quirk ✅
*   **Issue:** Three `schtasks /create` commands ran consecutively but only the last `%errorlevel%` was checked.
*   **Fix Applied:** Each task creation now has its own errorlevel check with a counter (`_taskOK` / `_taskFail`). Log message reports "X/3 created, Y/3 failed".

### 3. Node.js Process Blanket Kill ✅
*   **Issue:** `taskkill /IM node.exe /F` killed ALL Node processes, potentially terminating dev servers.
*   **Fix Applied:** Replaced with opt-in `KILL_NODE=0` config toggle (default OFF). Only kills if user explicitly sets `KILL_NODE=1`.

### 4. Harmless SATA Command on NVMe ✅
*   **Issue:** AHCI Link Power Management GUID (`0b2d69d7-...`) was applied but irrelevant for NVMe SSD.
*   **Fix Applied:** Removed the SATA AHCI GUID from all three modes (Saver, Performance, Ultra Performance). Comment documents the removal.

### 5. Taskbar Auto-Hide Restarting Explorer ✅
*   **Issue:** `Stop-Process -Name explorer -Force` closed all File Explorer windows.
*   **Fix Applied:** Replaced with `SendNotifyMessage(HWND_BROADCAST, WM_SETTINGCHANGE, 0, "TraySettings")` via P/Invoke. The taskbar refreshes without restarting explorer.exe.

### 6. Registry Default Values ✅
*   **Issue:** `reg delete` for `EnableMsHybrid` and `DisablePowerMizer` relied on implicit defaults.
*   **Fix Applied:** Replaced with explicit `reg add`:
    - `EnableMsHybrid` = 4 (DWORD) — Optimus auto-select
    - `DisablePowerMizer` = 0 (DWORD) — PowerMizer enabled (normal power management)

### 7. User Discovered Issues ✅

**7a. PhoneLink crashes after mode change ✅**
*   **Issue:** PhoneLink forgot paired devices after mode change, requiring full reset + re-pair.
*   **Root Cause:** PhoneLink relies on persistent Bluetooth LE connections. Battery saver modes were killing all background processes indiscriminately.
*   **Fix Applied:** Added explicit exclusion comment for `PhoneExperienceHost.exe` — it is intentionally NOT killed in any mode.

**7b. Auto reapply function malfunctioning ✅**
*   **Issue:** Opened 2+ cmd windows and sometimes applied battery saver on AC power.
*   **Root Cause:** All three scheduled tasks (S3, Modern Standby, Unlock) fired simultaneously on wake, each launching a separate `cmd /c` instance.
*   **Fix Applied:** Added lockfile mechanism (`%~dp0.reapply.lock`). First instance creates lockfile, runs, then deletes it. Subsequent instances detect the lockfile (if < 120 seconds old) and `exit /b` immediately. The AC power check already existed in `:reapply` — no change needed for that part.

## ✅ Accomplished in v8.0 / v8.1
*   Fixed critical state persistence (`CURRENT_MODE` correctly saved to `%~dp0.powermode.state`).
*   Implemented triple-trigger wake architecture (Legacy S3, Modern Standby S0ix, Workstation Unlock) to guarantee auto-reapply reliability.
*   Fixed stale `%errorlevel%` variables in nested code blocks.
*   Added `Antigravity.exe` to sleep-blocking kill lists.
