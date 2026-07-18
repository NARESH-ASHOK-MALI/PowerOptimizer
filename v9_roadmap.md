# PowerOptimizer v9.0 Roadmap & Backlog
*Compiled on: 2026-07-05*

This document serves as a backlog for the upcoming **v9.0 update** planned for next month. It documents the medium/low priority functional gaps and cosmetic issues identified during the v8.0 deep-dive analysis.

## 🛠️ Backlog / Planned Fixes

### 1. MongoDB Start Type in Performance Modes
*   **Issue:** MongoDB is set to `demand` start in Battery Saver and PSB modes. It is correctly restored to `auto` in Balanced mode, but **not** in Max Performance or Ultra Performance modes.
*   **Fix Required:** Add `sc config MongoDB start= auto` to the `:performance` and `:ultraperformance` blocks.

### 2. Scheduled Task Logging Quirk
*   **Issue:** In the `:saver` section, three `schtasks /create` commands are run consecutively (for S3, Modern Standby, and Unlock wake triggers). The logging block immediately after (`if %errorlevel% equ 0 call :log "Auto wake re-apply task created"`) only evaluates the exit code of the final command, meaning it could inaccurately report a failure if the first two succeeded but the third failed.
*   **Fix Required:** Update the logging logic to evaluate each task's creation independently, or change the log message to be generic (e.g., `"Auto wake re-apply tasks configured"`).

### 3. Node.js Process Blanket Kill
*   **Issue:** The script currently runs `taskkill /IM node.exe /F` to save battery. This kills *all* Node processes system-wide, which could abruptly terminate local dev servers or unsaved work in Node-based tools.
*   **Fix Required:** Evaluate if Node.js needs to be blanket-killed. If the user develops on battery, this should be removed or made an optional toggle.

### 4. Harmless SATA Command on NVMe
*   **Issue:** The script applies the AHCI Link Power Management GUID (`0b2d69d7-...`) which governs SATA HIPM/DIPM. Since this machine uses an NVMe SSD, it relies on APST (`dbc9e238-...`).
*   **Fix Required:** Remove the obsolete SATA GUID to clean up the script.

### 5. Taskbar Auto-Hide Restarting Explorer
*   **Issue:** The OLED care mode restarts `explorer.exe` entirely to apply the taskbar auto-hide registry changes. This closes all open File Explorer windows.
*   **Fix Required:** This is a known Windows limitation for registry-based taskbar changes, but look for potential workarounds if possible.

### 6. Registry Default Values
*   **Issue:** In Balanced mode, the script uses `reg delete` for `EnableMsHybrid` and `DisablePowerMizer` rather than explicitly writing their default values. While absence usually defaults correctly, explicitly setting the default values is safer.
*   **Fix Required:** Determine the exact OEM default hex values for these keys and use `reg add` to restore them instead of deleting.

### 7. User discovered issues
problems noticed:
1) PhoneLink crashes after mode change(forgets devices after mode change, i needs to reset and repair app to use it again)
2) Auto reapply function malfunctioning(opens 2 cmds and applys battery saver sometimes even if its on battery)


## ✅ Accomplished in v8.0 / v8.1
*   Fixed critical state persistence (`CURRENT_MODE` correctly saved to `%~dp0.powermode.state`).
*   Implemented triple-trigger wake architecture (Legacy S3, Modern Standby S0ix, Workstation Unlock) to guarantee auto-reapply reliability.
*   Fixed stale `%errorlevel%` variables in nested code blocks.
*   Added `Antigravity.exe` to sleep-blocking kill lists.
