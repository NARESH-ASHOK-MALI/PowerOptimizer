@echo off
setlocal EnableDelayedExpansion
title Asus Vivobook Pro OLED - Power Optimizer v10.0
color 0B

:: =============================================
::  DEVICE PROFILE
::  Asus Vivobook Pro OLED (M3500QC series)
::  CPU:     AMD Ryzen 5 5600H (6C/12T, 45W TDP)
::  iGPU:    AMD Radeon Graphics (Vega 7)
::  dGPU:    NVIDIA GeForce RTX 3050 4GB
::  RAM:     16 GB DDR4
::  Storage: 512 GB NVMe SSD
::  Display: 15.6" OLED 60Hz (AMOLED)
::  BIOS:    M3500QC.316 (2023/05/25) - LATEST
::  OS:      Win 11 26300 (24H2)
::  Battery: 82.9%% health / 309 cycles (as of September 04 2026)
::  NOTE:    PCIe ASPM disabled at BIOS level
::           (hardware incompatibility, no newer BIOS)
:: =============================================

:: =============================================
::  CHANGELOG
::  v10.0 - [FIX-8]  Kill Antigravity language_server_windows_x64.exe
::           (energy report: ~1%% combined CPU across multiple instances)
::        - [FIX-9]  PSB mode now sets video playback to power-saving
::        - [FIX-16] Auto wake re-apply runs SILENT (hidden window, no
::           pause). Uses wscript+VBS to launch hidden cmd. Exits cleanly
::           instead of opening the menu. No more cmd popups on wake.
::           (energy report flagged "Optimize for Video Quality" on battery)
::        - [FIX-10] PSB mode keeps MongoDB at demand start (was restoring
::           to auto, defeating the purpose of a battery-saving mode)
::        - [FIX-11] Disable failed USB device (VID_0000/PID_0002) in
::           Saver/PSB modes (energy report: Device Descriptor Failed)
::        - [FIX-12] Fix duplicate wake log entries — log call moved after
::           lockfile check to prevent double-logging from concurrent tasks
::        - [FIX-13] Battery health updated: 82.9%% / 309 cycles (Sep 04)
::        - [FIX-14] Chrome background processes killed in Saver mode
::           (energy report: 5.27%% CPU from background chrome.exe)
::        - [FIX-15] MongoDB version updated to 8.3 in comments
::  v9.0 - [FIX-1] MongoDB start type now restored in Perf/Ultra Perf modes
::       - [FIX-2] Scheduled task creation now logs each task independently
::       - [FIX-3] Node.js blanket kill replaced with opt-in toggle (KILL_NODE)
::       - [FIX-4] Removed obsolete SATA AHCI Link PM GUID (NVMe-only machine)
::       - [FIX-5] Taskbar auto-hide no longer restarts explorer.exe
::       - [FIX-6] Balanced mode documents GPU registry restore rationale
::       - [FIX-7a] PhoneLink excluded from kill lists (prevents device loss)
::       - [FIX-7b] Auto re-apply lockfile prevents duplicate cmd windows
::  v8.0 - [BUG-20] Fixed critical battery hibernate not triggering
::         at 8%% — now sets thresholds on ALL power plans, raised to 10%%
::       - [BUG-21] Antigravity.exe blocks sleep (energy report)
::         Added to process kill list in Saver/PSB modes
::       - [BUG-22] Removed hardcoded 85.8%% health in Ultra Perf warning
::       - [BUG-23] MongoDB start type now restored in PSB mode
::       - [BUG-24] Fixed low battery action GUID (was Energy Saver threshold)
::       - Added auto wake re-apply scheduled task option
::  v7.1 - Added [P] Power Saving Balanced mode
::         Balanced CPU (no 40% cap) + RTX OFF +
::         Wi-Fi power saving + PowerToys killed
::       - Removed Ferdium references (uninstalled)
:: =============================================

:: =============================================
::  CONFIGURATION
:: =============================================
set "LOGFILE=%~dp0PowerOptimizer.log"
set "KILL_BROWSERS=1"
:: Set KILL_BROWSERS=0 to keep browsers open in battery saver
set "KILL_NODE=0"
:: Set KILL_NODE=1 to kill all Node.js processes in battery saver
:: Default OFF: blanket-killing node.exe can terminate dev servers or tools
set "LOG_MAX_LINES=500"
:: Track current active mode to prevent duplicate activations
set "CURRENT_MODE="
if exist "%~dp0.powermode.state" (
    set /p CURRENT_MODE=<"%~dp0.powermode.state"
)
:: FIX-16: SILENT_MODE flag — set when script is invoked via command-line
:: argument (scheduled task / shortcut). When set, re-apply runs hidden:
:: no pause, no menu, just apply settings and exit.
set "SILENT_MODE=0"
if not "%~1"=="" set "SILENT_MODE=1"

:: =============================================
::  Check for Admin privileges (auto-elevate)
:: =============================================
>nul 2>&1 reg query "HKU\S-1-5-19"
if '%errorlevel%' neq '0' (
    echo.
    echo   Requesting Administrator privileges...
    echo.
    echo Set UAC = CreateObject^("Shell.Application"^) > "%TEMP%\PowerOpt_elevate.vbs"
    echo UAC.ShellExecute "cmd.exe", "/c """"%~f0"""" %*", "%~dp0", "runas", 1 >> "%TEMP%\PowerOpt_elevate.vbs"
    cscript //nologo "%TEMP%\PowerOpt_elevate.vbs"
    del /f /q "%TEMP%\PowerOpt_elevate.vbs" >nul 2>&1
    exit /b
)
cd /d "%~dp0"

:: =============================================
::  Command-line quick switch
::  Usage: PowerOptimizer.bat 1  (battery saver)
::         PowerOptimizer.bat 2  (performance)
::         PowerOptimizer.bat 3  (balanced)
::         PowerOptimizer.bat 4  (ultra performance - NVIDIA only)
::         PowerOptimizer.bat P  (power saving balanced)
:: =============================================
if "%~1"=="1" goto saver
if "%~1"=="2" goto performance
if "%~1"=="3" goto balanced
if /i "%~1"=="4" goto ultraperformance
if /i "%~1"=="U" goto ultraperformance
if /i "%~1"=="G" goto gpuswitch
if /i "%~1"=="S" goto status
if /i "%~1"=="H" goto batteryreport
if /i "%~1"=="N" goto networksaver
if /i "%~1"=="C" goto startupcleanup
if /i "%~1"=="O" goto oledcare
if /i "%~1"=="R" goto reapply
if /i "%~1"=="P" goto psbalanced

:: =============================================
::  MAIN MENU
:: =============================================
:menu
cls
echo.
echo   +==============================================================+
echo   :     ASUS VIVOBOOK PRO OLED - POWER OPTIMIZER  v10.0          :
echo   :     Ryzen 5 5600H ^| RTX 3050 ^| 16GB ^| BIOS 316 (Latest)   :
echo   +==============================================================+
echo.

:: ---- Detect power source ----
set "batStatus="
set "batPercent="
set "batTime="
set "powerSrc=UNKNOWN"

:: Using CIM instead of deprecated WMIC for Win11 24H2+ compatibility
powershell -NoProfile -Command ^
  "$b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue; " ^
  "if ($b) { " ^
  "  [System.IO.File]::WriteAllText('%TEMP%\po_batstatus.txt', [string]$b.BatteryStatus); " ^
  "  [System.IO.File]::WriteAllText('%TEMP%\po_batpct.txt', [string]$b.EstimatedChargeRemaining); " ^
  "  [System.IO.File]::WriteAllText('%TEMP%\po_battime.txt', [string]$b.EstimatedRunTime); " ^
  "}" >nul 2>&1
if exist "%TEMP%\po_batstatus.txt" ( set /p batStatus=<"%TEMP%\po_batstatus.txt" & del "%TEMP%\po_batstatus.txt" >nul 2>&1 )
if exist "%TEMP%\po_batpct.txt" ( set /p batPercent=<"%TEMP%\po_batpct.txt" & del "%TEMP%\po_batpct.txt" >nul 2>&1 )
if exist "%TEMP%\po_battime.txt" ( set /p batTime=<"%TEMP%\po_battime.txt" & del "%TEMP%\po_battime.txt" >nul 2>&1 )

:: ---- Detect current power plan ----
set "currentPlan="
for /f "tokens=4*" %%A in ('powercfg /getactivescheme 2^>nul') do (
    if not defined currentPlan set "currentPlan=%%B"
)

:: ---- Detect active GPU ----
set "activeGPU=Unknown"
powershell -NoProfile -Command ^
  "$nvidia = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*NVIDIA*' -and $_.Status -eq 'OK' }; " ^
  "if ($nvidia) { [System.IO.File]::WriteAllText('%TEMP%\gpustate.txt', 'NVIDIA RTX 3050') } " ^
  "else { [System.IO.File]::WriteAllText('%TEMP%\gpustate.txt', 'AMD Radeon iGPU') }" >nul 2>&1
if exist "%TEMP%\gpustate.txt" (
    set /p activeGPU=<"%TEMP%\gpustate.txt"
    del "%TEMP%\gpustate.txt" >nul 2>&1
)

:: ---- Build status dashboard ----
echo   +------------------------------------------------------------+
if defined batStatus (
    if "%batStatus%"=="2" (
        set "powerSrc=CHARGING"
        echo   :  [AC] CHARGING / PLUGGED IN                              :
    ) else if "%batStatus%"=="1" (
        set "powerSrc=BATTERY"
        echo   :  [BAT] ON BATTERY                                        :
    ) else (
        echo   :  [?] POWER STATUS UNKNOWN                                :
    )
    echo   :  Battery Level:  %batPercent%%%                                    :
    if defined batTime (
        if not "%batTime%"=="71582788" (
            set /a "batHrs=batTime / 60"
            set /a "batMins=batTime %% 60"
            echo   :  Est. Remaining: !batHrs!h !batMins!m                              :
        )
    )
) else (
    echo   :  [PC] Desktop / No Battery Detected                       :
)
echo   :  Active Plan:  %currentPlan%                            :
echo   :  Active GPU:   !activeGPU!                              :
echo   +------------------------------------------------------------+
echo.

:: ---- Smart suggestion ----
if "%powerSrc%"=="BATTERY" (
    echo   TIP: You're on battery. Press P for smooth battery saving,
    echo         or press 1 for maximum battery life.
) else if "%powerSrc%"=="CHARGING" (
    echo   TIP: You're plugged in. Press 2 for full RTX 3050 performance.
)
echo.
echo   ==============================================================
echo.
echo    [1]  Ultra Battery Saver     Max battery life
echo         CPU 40%%, Boost OFF, RTX 3050 OFF, iGPU only
echo         OLED brightness 25%%, dark wallpaper, Energy Saver ON
echo.
echo    [2]  Max Performance          Full power (plugged in)
echo         CPU 100%%, Boost ON, RTX 3050 ON, all cores active
echo         OLED 85%%, NVMe max speed, no sleep
echo.
echo    [3]  Balanced Mode            Everyday use
echo         CPU auto, Boost efficient, hybrid GPU, OLED 60%%
echo.
echo    [4]  GPU Switch               Toggle RTX 3050 / Radeon iGPU
echo.
echo    [5]  System Status            Live hardware dashboard
echo.
echo    [6]  Battery Health Report    HTML report + energy audit
echo.
echo    [7]  Network Saver            Bluetooth/Wi-Fi power control
echo.
echo    [8]  Startup Cleanup          Disable bloatware auto-start
echo.
echo    [9]  OLED Care                Screen burn-in protection
echo.
echo    [U]  Ultra Performance        NVIDIA rendering mode
echo         CPU 100%%, Boost MAX, RTX 3050 renders everything
echo         OLED 85%%, NVMe max speed, no sleep, all power unlocked
echo.
echo    [P]  Power Saving Balanced    Smooth + efficient on battery
echo         CPU 100%% / Boost efficient / EPP 50 (no lag!)
echo         RTX 3050 OFF, Wi-Fi power saving, PowerToys killed
echo         OLED 50%%, screen off 3min, sleep 10min
echo.
echo    [R]  Quick Re-apply          Re-apply saver after wake
echo         Fixes settings that reset after sleep/wake cycles
echo.
echo    [0]  Exit
echo.
echo   ==============================================================
echo.
set /p choice="  Select an option (0-9 / U / P / R): "

if "%choice%"=="1" goto saver
if "%choice%"=="2" goto performance
if "%choice%"=="3" goto balanced
if "%choice%"=="4" goto gpuswitch
if "%choice%"=="5" goto status
if "%choice%"=="6" goto batteryreport
if "%choice%"=="7" goto networksaver
if "%choice%"=="8" goto startupcleanup
if "%choice%"=="9" goto oledcare
if /i "%choice%"=="U" goto ultraperformance
if /i "%choice%"=="P" goto psbalanced
if /i "%choice%"=="R" goto reapply
if "%choice%"=="0" goto exitscript

echo   [!] Invalid choice. Try again.
timeout /t 2 >nul
goto menu

:: =============================================================
::                     LOGGING HELPER
:: =============================================================
:log
echo [%date% %time%] %~1 >> "%LOGFILE%"
goto :eof

:: =============================================================
::                     LOG ROTATION
:: =============================================================
:logrotate
if not exist "%LOGFILE%" goto :eof
for /f %%L in ('find /c /v "" ^< "%LOGFILE%"') do set "lineCount=%%L"
if !lineCount! GTR %LOG_MAX_LINES% (
    echo [%date% %time%] Log rotated (was !lineCount! lines^) >> "%LOGFILE%"
    powershell -NoProfile -Command ^
      "$f = '%LOGFILE%'; $lines = Get-Content $f -Tail %LOG_MAX_LINES%; Set-Content $f -Value $lines" >nul 2>&1
)
goto :eof

:: =============================================================
::              ULTRA BATTERY SAVER MODE
:: =============================================================
:saver
cls
:: Check if already in saver mode
if not "!CURRENT_MODE!"=="SAVER" goto start_saver
echo.
echo   [!] Ultra Battery Saver is already active. Skipping re-activation.
echo       Use [R] to Quick Re-apply if settings have drifted.
echo.
call :log "Saver activation skipped (already active)"
pause
goto menu
:start_saver
set "CURRENT_MODE=SAVER"
echo SAVER>"%~dp0.powermode.state"
call :logrotate
call :log "=== ULTRA BATTERY SAVER MODE ACTIVATED ==="
echo.
echo   +==============================================================+
echo   :       Applying ULTRA Battery Saver for Vivobook Pro OLED     :
echo   +==============================================================+
echo.

echo   [1/16] Killing PowerToys and Awake module (prevents sleep)...
:: PowerToys.Awake was flagged in energy report: prevents system+display sleep
taskkill /IM "PowerToys.Awake.exe" /F /T >nul 2>&1
taskkill /FI "IMAGENAME eq PowerToys.exe" /F /T >nul 2>&1
taskkill /FI "IMAGENAME eq PowerToys.Settings.exe" /F /T >nul 2>&1
taskkill /FI "IMAGENAME eq PowerToys.Peek.UI.exe" /F /T >nul 2>&1
taskkill /FI "IMAGENAME eq PowerToys.FancyZones.exe" /F /T >nul 2>&1
taskkill /FI "IMAGENAME eq PowerToys.PowerLauncher.exe" /F /T >nul 2>&1
call :log "Killed PowerToys + Awake module (was blocking sleep)"

echo   [2/16] Killing heavy background apps...
:: Docker
taskkill /IM "Docker Desktop.exe" /F /T >nul 2>&1
taskkill /IM "com.docker.backend.exe" /F /T >nul 2>&1
taskkill /IM "com.docker.proxy.exe" /F /T >nul 2>&1
:: Cloud Sync
taskkill /IM OneDrive.exe /F /T >nul 2>&1
taskkill /IM Dropbox.exe /F /T >nul 2>&1
taskkill /IM GoogleDriveFS.exe /F /T >nul 2>&1
taskkill /IM iCloudDrive.exe /F /T >nul 2>&1
:: Game Launchers
taskkill /IM steam.exe /F /T >nul 2>&1
taskkill /IM steamwebhelper.exe /F /T >nul 2>&1
taskkill /IM EpicGamesLauncher.exe /F /T >nul 2>&1
taskkill /IM discord.exe /F /T >nul 2>&1
taskkill /IM Update.exe /F /T >nul 2>&1
:: Media
taskkill /IM Spotify.exe /F /T >nul 2>&1
:: Teams / Slack / Communication
taskkill /IM Teams.exe /F /T >nul 2>&1
taskkill /IM ms-teams.exe /F /T >nul 2>&1
taskkill /IM slack.exe /F /T >nul 2>&1
:: Adobe background
taskkill /IM "Adobe Desktop Service.exe" /F /T >nul 2>&1
taskkill /IM AdobeIPCBroker.exe /F /T >nul 2>&1
taskkill /IM CCXProcess.exe /F /T >nul 2>&1
:: Windows Widgets
taskkill /IM Widgets.exe /F /T >nul 2>&1
taskkill /IM WidgetService.exe /F /T >nul 2>&1
:: Node / Dev tools background
:: FIX-3: Blanket node.exe kill is now opt-in via KILL_NODE config.
:: Default OFF because it can terminate local dev servers, Antigravity terminal,
:: or any Node-based tool the user has running.
if not "%KILL_NODE%"=="1" goto skip_node_kill
:: IMPORTANT: Do NOT use /T (tree kill) for node.exe!
:: If this script was launched from VS Code terminal, Antigravity, or any
:: Node-based tool, /T would kill the cmd.exe process tree and terminate
:: this script mid-execution (BUG-17 fix - May 2026).
taskkill /IM "node.exe" /F >nul 2>&1
call :log "Node.exe killed (KILL_NODE=1)"
:skip_node_kill
:: FIX-7a: PhoneLink (PhoneExperienceHost.exe) is intentionally NOT killed.
:: Killing it breaks Bluetooth LE pairing and forces device re-pair on restart.
:: MongoDB 8.3 (timer resolution hog - requests 1ms/10000 100ns units, wastes CPU power)
net stop MongoDB >nul 2>&1
taskkill /IM mongod.exe /F /T >nul 2>&1
taskkill /IM mongos.exe /F /T >nul 2>&1
:: Prevent MongoDB from auto-restarting
sc config MongoDB start= demand >nul 2>&1
:: MoUsoCoreWorker (energy report: execution-required request preventing sleep)
taskkill /IM MoUsoCoreWorker.exe /F /T >nul 2>&1
net stop UsoSvc >nul 2>&1
:: NVIDIA background processes (save battery when GPU off)
taskkill /IM "NVDisplay.Container.exe" /F /T >nul 2>&1
taskkill /IM "NVIDIA Share.exe" /F /T >nul 2>&1
taskkill /IM "NVIDIA Web Helper.exe" /F /T >nul 2>&1
taskkill /IM "nvidia_smi.exe" /F /T >nul 2>&1
taskkill /IM "nvcontainer.exe" /F /T >nul 2>&1
taskkill /IM "NvTelemetryContainer.exe" /F /T >nul 2>&1
:: Asus bloatware
taskkill /IM "ArmouryCrate.exe" /F /T >nul 2>&1
taskkill /IM "ArmouryCrateService.exe" /F /T >nul 2>&1
taskkill /IM "AsusSplendid.exe" /F /T >nul 2>&1
taskkill /IM "AsusOptimization.exe" /F /T >nul 2>&1
taskkill /IM "MyASUS.exe" /F /T >nul 2>&1
:: Antigravity (energy report: execution-required request preventing sleep)
taskkill /IM "Antigravity.exe" /F /T >nul 2>&1
:: FIX-8: Kill Antigravity's language server (energy report: ~1%% combined CPU)
taskkill /IM "language_server_windows_x64.exe" /F >nul 2>&1
:: FIX-14: Kill background Chrome processes (energy report: 5.27%% CPU)
taskkill /IM "chrome.exe" /F >nul 2>&1
call :log "Killed background apps + MongoDB + NVIDIA + Asus bloat + Antigravity + LSP + Chrome"

:: Browsers — BUG-17 FIX: Do NOT use call :log inside if () blocks.
:: cmd.exe's goto :eof inside a call from within a parenthesized block
:: can corrupt the batch file seek pointer and silently kill execution.
if "%KILL_BROWSERS%"=="0" echo          Browsers kept open (KILL_BROWSERS=0)
if "%KILL_BROWSERS%"=="0" goto skipbrowsers
echo   [2b]  Closing browsers to save power...
taskkill /IM msedge.exe /F >nul 2>&1
taskkill /IM chrome.exe /F >nul 2>&1
taskkill /IM brave.exe /F >nul 2>&1
taskkill /IM firefox.exe /F >nul 2>&1
taskkill /IM opera.exe /F >nul 2>&1
call :log "Killed browsers"
:skipbrowsers

echo   [3/16] Disabling NVIDIA RTX 3050 (using iGPU only)...
:: Disable the discrete GPU to save ~15-25W
:: This forces everything onto the Radeon Vega 7 iGPU
powershell -NoProfile -Command ^
  "$gpu = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' -and $_.Class -eq 'Display' }; " ^
  "if ($gpu) { $gpu | Disable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue; Write-Host 'RTX 3050 disabled.' } " ^
  "else { Write-Host 'NVIDIA GPU not found or already disabled.' }"
:: Stop NVIDIA services
net stop NVDisplay.ContainerLocalSystem >nul 2>&1
net stop NvTelemetryContainer >nul 2>&1
call :log "RTX 3050 DISABLED - iGPU only mode"

echo   [4/16] Setting Power Plan to Power Saver...
powercfg -setactive a1841308-3541-4fab-bc81-f71556f20b4a >nul 2>&1
if %errorlevel% neq 0 (
    powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e >nul 2>&1
)
call :log "Power plan set to Power Saver"

echo   [5/16] Setting Windows Power Slider to Best Power Efficiency...
powercfg /SetActiveOverlay SCHEME_CURRENT 961cc777-2547-4f9d-8174-7d86181b8a7a >nul 2>&1

echo   [6/16] Throttling Ryzen 5600H, Boost OFF...
:: AMD Ryzen 5600H: 6 cores / 12 threads, 45W TDP
:: Cap CPU max to 40% on battery (~18W effective)
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 40 >nul 2>&1
:: Set minimum CPU to 5% (deep idle)
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5 >nul 2>&1
:: Disable AMD Precision Boost on battery (saves significant power)
:: PERFBOOSTMODE: 0=Disabled 1=Enabled 2=Aggressive 4=EfficientEnabled
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 0 >nul 2>&1
:: Aggressive core parking - let OS park up to 8 of 12 threads
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 5 >nul 2>&1
:: AMD-specific: set platform power management to battery mode
:: Autonomous mode: let AMD pstate driver manage clocks conservatively
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFAUTONOMOUS 1 >nul 2>&1
:: EPP (Energy Performance Preference): 100 = max power saving
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 100 >nul 2>&1
call :log "Ryzen 5600H throttled 40%%, Boost OFF, EPP=100"

echo   [7/16] OLED Display optimizations...
:: Screen off after 2 minutes on battery (OLED = 0W when pixels off)
powercfg /change monitor-timeout-dc 2
:: Also set reasonable AC timeouts (energy report flagged "never" as error)
powercfg /change monitor-timeout-ac 10
:: Sleep after 5 minutes on battery
powercfg /change standby-timeout-dc 5
powercfg /change standby-timeout-ac 30
:: Hibernate after 15 minutes (saves more than sleep for SSD laptop)
powercfg /change hibernate-timeout-dc 15
powercfg /change hibernate-timeout-ac 60
:: Reduce OLED brightness to 25% (OLED power scales linearly with brightness)
powershell -NoProfile -Command "(Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightnessMethods).WmiSetBrightness(1, 25)" >nul 2>&1
:: Disable adaptive brightness (saves CPU overhead)
powercfg /setdcvalueindex SCHEME_CURRENT 7516b95f-f776-4464-8c53-06167f40cc99 fbd9aa66-9553-4097-ba44-ed6e9d65eab8 0 >nul 2>&1
:: Set dark wallpaper to reduce OLED power draw (black pixels = 0 power)
powershell -NoProfile -Command ^
  "try { " ^
  "  Add-Type @' " ^
  "  using System; using System.Runtime.InteropServices; " ^
  "  public class Wallpaper { " ^
  "    [DllImport(\"user32.dll\", CharSet=CharSet.Auto)] " ^
  "    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni); " ^
  "  } " ^
  "'@ -ErrorAction SilentlyContinue; " ^
  "  [Wallpaper]::SystemParametersInfo(0x0014, 0, '', 0x0001) | Out-Null; " ^
  "  Write-Host 'Wallpaper set to solid black (OLED power saving).'; " ^
  "} catch { Write-Host 'Wallpaper change skipped.' }" >nul 2>&1
:: Enable dark mode to save OLED power
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "AppsUseLightTheme" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "SystemUsesLightTheme" /t REG_DWORD /d 0 /f >nul 2>&1
:: Set video playback to power savings on battery (flagged in energy report)
powercfg /setdcvalueindex SCHEME_CURRENT 9596fb26-9850-41fd-ac3e-f7c3c00afd4b 34c7b151-7bf6-4e87-b075-e0f5f5899773 1 >nul 2>&1
call :log "OLED: brightness 25%%, dark mode ON, black wallpaper, video=powersave"

echo   [8/16] NVMe SSD power optimization...
:: NVMe-specific: enable APST (Autonomous Power State Transitions)
:: No spin-down needed for SSD, but enable NVMe sleep states
:: Set NVMe NOPPME (Non-Operational Power Management Enable)
powercfg /setdcvalueindex SCHEME_CURRENT SUB_DISK dbc9e238-6de9-49e3-92cd-8c2b4946b472 1 >nul 2>&1
:: Reduce NVMe power state transition latency tolerance on battery
powercfg /setdcvalueindex SCHEME_CURRENT SUB_DISK fc95af4d-40e7-4b6d-835a-56d131dbc80e 10 >nul 2>&1
:: FIX-4: Removed obsolete SATA AHCI Link PM GUID (0b2d69d7).
:: This machine uses NVMe SSD only — SATA HIPM/DIPM is irrelevant.
call :log "NVMe SSD: APST ON, latency tolerance aggressive"

echo   [8b/16] Disabling failed USB device (energy report)...
:: FIX-11: Energy report flagged Unknown USB Device (VID_0000/PID_0002)
:: Device Descriptor Request Failed — phantom device wasting power
powershell -NoProfile -Command ^
  "Get-PnpDevice | Where-Object { $_.InstanceId -like '*VID_0000*PID_0002*' } | ForEach-Object { " ^
  "  Disable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue " ^
  "}" >nul 2>&1
call :log "Failed USB device (VID_0000/PID_0002) disabled"

echo   [9/16] USB, PCIe, Wi-Fi power optimization...
:: Enable USB selective suspend on battery AND AC (energy report flagged AC disabled)
powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 >nul 2>&1
:: PCIe Link State Power Management: Maximum savings
:: NOTE: BIOS M3500QC.316 has ASPM hardware disabled - this is a best-effort
:: workaround via OS power policy (won't override BIOS, but sets intent)
powercfg /setdcvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 2 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 1 >nul 2>&1
:: Wi-Fi: Maximum Power Saving
powercfg /setdcvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 3 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 2 >nul 2>&1
:: Apply all powercfg changes
powercfg /setactive SCHEME_CURRENT >nul 2>&1
call :log "USB suspend ON (AC+DC), PCIe max savings, Wi-Fi max saving"

echo   [10/16] Disabling heavy background services (parallel)...
:: Use parallel stops to reduce the 30+ second bottleneck
powershell -NoProfile -Command ^
  "$svcs = @('WSearch','wuauserv','SysMain','WerSvc','DiagTrack','Spooler','BITS','WbioSrvc','TermService','Fax','UsoSvc','NVDisplay.ContainerLocalSystem','NvTelemetryContainer'); " ^
  "$jobs = $svcs | ForEach-Object { Start-Job -ScriptBlock { param($s) Stop-Service $s -Force -ErrorAction SilentlyContinue } -ArgumentList $_ }; " ^
  "$jobs | Wait-Job -Timeout 30 | Out-Null; " ^
  "$jobs | Remove-Job -Force" >nul 2>&1
call :log "Services stopped in parallel (including NVIDIA services)"

echo   [11/16] Disabling background scheduled tasks...
schtasks /change /tn "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Autochk\Proxy" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem" /disable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Windows Error Reporting\QueueReporting" /disable >nul 2>&1
:: Disable NVIDIA telemetry tasks
schtasks /change /tn "\NvTmMon_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}" /disable >nul 2>&1
schtasks /change /tn "\NvTmRep_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}" /disable >nul 2>&1
schtasks /change /tn "\NVIDIA GeForce Experience SelfUpdate_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}" /disable >nul 2>&1
call :log "Disabled heavy + NVIDIA scheduled tasks"

echo   [12/16] Fixing Edge timer resolution (power hog)...
:: Edge requests 1ms timer resolution which prevents deep CPU C-states
:: Disable Edge startup boost (reduces background Edge processes)
reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v "StartupBoostEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
:: Disable Edge background running
reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v "BackgroundModeEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
:: Set Edge to efficiency mode always
reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v "EfficiencyModeEnabled" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v "EfficiencyModeOnPowerEnabled" /t REG_DWORD /d 1 /f >nul 2>&1
:: Kill Edge background processes that are requesting 1ms timer
taskkill /IM msedge.exe /F >nul 2>&1
taskkill /IM msedgewebview2.exe /F >nul 2>&1
call :log "Edge timer fix: startup boost OFF, background OFF, efficiency ON"

echo   [13/16] USB device power management (webcam + phone)...
:: Energy report flagged webcam (VID_13D3/PID_3563) rarely entering suspend
:: Force USB devices to allow selective suspend via registry
powershell -NoProfile -Command ^
  "Get-PnpDevice | Where-Object { $_.InstanceId -like '*VID_13D3*PID_3563*' } | ForEach-Object { " ^
  "  $id = $_.InstanceId; " ^
  "  $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $id + '\Device Parameters'; " ^
  "  if (Test-Path $regPath) { " ^
  "    Set-ItemProperty -Path $regPath -Name 'SelectiveSuspendEnabled' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue; " ^
  "  }; " ^
  "}" >nul 2>&1
:: Energy report flagged Samsung phone (VID_04E8/PID_6863) not entering suspend
powershell -NoProfile -Command ^
  "Get-PnpDevice | Where-Object { $_.InstanceId -like '*VID_04E8*PID_6863*' } | ForEach-Object { " ^
  "  $id = $_.InstanceId; " ^
  "  $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $id + '\Device Parameters'; " ^
  "  if (Test-Path $regPath) { " ^
  "    Set-ItemProperty -Path $regPath -Name 'SelectiveSuspendEnabled' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue; " ^
  "  } " ^
  "}" >nul 2>&1
call :log "Webcam USB selective suspend enabled + Samsung phone USB selective suspend enabled"

echo   [14/16] Enabling Windows Energy Saver / Battery Saver...
:: Method 1: powercfg threshold
powercfg /setdcvalueindex SCHEME_CURRENT e73a048d-bf27-4f12-9731-8b2076e8891f 637ea02f-bbcb-4015-8e2c-a1c7b9c0b546 100 >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1
:: Method 2: Registry
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v "EnergySaverEnabled" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v "CsEnabled" /t REG_DWORD /d 1 /f >nul 2>&1
:: Method 3: PowerShell registry paths
powershell -NoProfile -Command ^
  "try { " ^
  "  $s = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GlobalSettings\EnergySaver'; " ^
  "  if (!(Test-Path $s)) { New-Item -Path $s -Force | Out-Null }; " ^
  "  Set-ItemProperty -Path $s -Name 'EnergySaverEnabled' -Value 1 -Type DWord -Force; " ^
  "  Set-ItemProperty -Path $s -Name 'BatterySaverEnabled' -Value 1 -Type DWord -Force; " ^
  "} catch { }; " ^
  "try { " ^
  "  $p = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\EnergySaver\Parameters'; " ^
  "  if (!(Test-Path $p)) { New-Item -Path $p -Force | Out-Null }; " ^
  "  Set-ItemProperty -Path $p -Name 'BatterySaverBatteryThreshold' -Value 100 -Type DWord -Force; " ^
  "  Set-ItemProperty -Path $p -Name 'BatterySaverEnabled' -Value 1 -Type DWord -Force; " ^
  "} catch { }" >nul 2>&1
call :log "Energy Saver enabled (threshold=100%%)"

echo   [15/16] Setting low battery protection...
:: BUG-20 FIX: Battery drained to 2%% on Jul 3 because hibernate thresholds
:: were only set on SCHEME_CURRENT. When the user switched power plans (e.g., 
:: to Ultimate Performance), the protections didn't carry over.
:: FIX: Set critical battery thresholds on ALL known power plan GUIDs.
:: Also raised critical threshold from 8%% to 10%% for safety margin.
:: BUG-24 FIX: Low battery action GUID was wrong (was using Energy Saver threshold).
:: Correct low battery action GUID: d8742dcb-3e6a-4b3c-b3fe-374623cdcf06 (verified)
set "BP_PLANS=SCHEME_CURRENT a1841308-3541-4fab-bc81-f71556f20b4a 381b4222-f694-41f0-9685-ff5bb260df2e 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c e9a42b02-d5df-448d-aa00-03f14749eb61"
for %%P in (%BP_PLANS%) do (
    :: Critical battery level: 10%%
    powercfg /setdcvalueindex %%P e73a048d-bf27-4f12-9731-8b2076e8891f 9a66d8d7-4ff7-4ef9-b5a2-5a326ca2a469 10 >nul 2>&1
    :: Critical battery action: Hibernate (3)
    powercfg /setdcvalueindex %%P e73a048d-bf27-4f12-9731-8b2076e8891f d8742dcb-3e6a-4b3c-b3fe-374623cdcf06 3 >nul 2>&1
    :: Low battery level: 20%%
    powercfg /setdcvalueindex %%P e73a048d-bf27-4f12-9731-8b2076e8891f 8183ba9a-e910-48da-8769-14ae6dc1170a 20 >nul 2>&1
    :: Low battery notification: ON
    powercfg /setdcvalueindex %%P e73a048d-bf27-4f12-9731-8b2076e8891f bcded951-187b-4d05-bccc-f7e51960c258 1 >nul 2>&1
)
powercfg /setactive SCHEME_CURRENT >nul 2>&1
call :log "Low battery protection: warn 20%%, hibernate 10%% (ALL plans)"

echo   [16/16] Setting up auto re-apply on wake (silent)...
:: FIX-16: Wake tasks now use wscript to launch a hidden cmd window.
:: Previously, each wake event opened a visible cmd.exe that blocked on
:: `pause` — extremely annoying. Now the VBS wrapper runs the script
:: with window style 0 (hidden), and the script detects SILENT_MODE
:: to skip pause/menu and exit cleanly.
:: FIX-2: Log each scheduled task creation independently.
set "_taskOK=0"
set "_taskFail=0"
:: Create a persistent VBS launcher that runs the .bat hidden
set "_vbsPath=%~dp0PowerOptimizer_silent.vbs"
>"!_vbsPath!" echo Set ws = CreateObject("WScript.Shell")
>>"!_vbsPath!" echo ws.Run "cmd /c """" ^& WScript.Arguments(0) ^& """" R", 0, False
:: Use wscript to launch the VBS which launches cmd hidden
schtasks /create /tn "PowerOptimizer_WakeReapply" /tr "wscript.exe //nologo \"%_vbsPath%\" \"%~f0\"" /sc ONEVENT /ec System /mo "*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and (EventID=1)]]" /f /rl HIGHEST >nul 2>&1
if !errorlevel! equ 0 (set /a "_taskOK+=1") else (set /a "_taskFail+=1")
schtasks /create /tn "PowerOptimizer_WakeReapply_Modern" /tr "wscript.exe //nologo \"%_vbsPath%\" \"%~f0\"" /sc ONEVENT /ec System /mo "*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and (EventID=507)]]" /f /rl HIGHEST >nul 2>&1
if !errorlevel! equ 0 (set /a "_taskOK+=1") else (set /a "_taskFail+=1")
schtasks /create /tn "PowerOptimizer_WakeReapply_Unlock" /tr "wscript.exe //nologo \"%_vbsPath%\" \"%~f0\"" /sc ONEVENT /ec Security /mo "*[System[(EventID=4801)]]" /f /rl HIGHEST >nul 2>&1
if !errorlevel! equ 0 (set /a "_taskOK+=1") else (set /a "_taskFail+=1")
call :log "Auto wake tasks: !_taskOK!/3 created (silent VBS launcher), !_taskFail!/3 failed"

echo.
echo   +==============================================================+
echo   :         ULTRA BATTERY SAVER v10.0 is now ON!                 :
echo   +--------------------------------------------------------------+
echo   :  Ryzen 5600H: 40%% cap / Boost OFF / Core parking ON         :
echo   :  RTX 3050:    DISABLED (Radeon iGPU only)                    :
echo   :  OLED:        25%% brightness / Dark Mode / Screen off 2m    :
echo   :  NVMe SSD:    APST ON / Link PM aggressive                   :
echo   :  Wi-Fi:       Max power saving / PCIe: Max savings           :
echo   :  Sleep: 5 min / Hibernate: 15 min                            :
echo   :  Services:    Parallel-stopped (Search, Update, NVIDIA, etc) :
echo   :  MongoDB:     STOPPED (timer hog)                            :
echo   :  Edge:        Efficiency mode ON / Background OFF            :
echo   :  Chrome:      Background processes killed                     :
echo   :  USB Devices: Webcam suspend ON + Samsung phone suspend ON    :
echo   :  Video:       Power-optimized playback                       :
echo   :  Energy Saver: FORCED ON                                     :
echo   :  MoUsoCoreWorker: STOPPED (was blocking sleep)               :
echo   :  Low Battery:  Warn 20%% / Auto-hibernate 10%% (ALL plans)    :
echo   :  Auto Re-apply: Scheduled task on wake                        :
echo   :  BIOS 316:    Latest (ASPM workaround applied)               :
echo   +--------------------------------------------------------------+
echo   :  TIP: After wake from sleep, press 'R' to quick re-apply     :
echo   +==============================================================+
echo.
echo   Log: %LOGFILE%
echo.
pause
goto menu

:: =============================================================
::              MAX PERFORMANCE MODE
:: =============================================================
:performance
cls
if not "!CURRENT_MODE!"=="PERFORMANCE" goto start_perf
echo.
echo   [!] Max Performance is already active. Skipping re-activation.
echo.
call :log "Performance activation skipped (already active)"
pause
goto menu
:start_perf
set "CURRENT_MODE=PERFORMANCE"
echo PERFORMANCE>"%~dp0.powermode.state"
call :log "=== MAX PERFORMANCE MODE ACTIVATED ==="
echo.
echo   +==============================================================+
echo   :     Applying MAX Performance for Vivobook Pro OLED           :
echo   +==============================================================+
echo.

echo   [1/10] Starting PowerToys...
if exist "C:\Program Files\PowerToys\PowerToys.exe" (
    start "" "C:\Program Files\PowerToys\PowerToys.exe"
    echo          Started from Program Files.
) else if exist "%LOCALAPPDATA%\PowerToys\PowerToys.exe" (
    start "" "%LOCALAPPDATA%\PowerToys\PowerToys.exe"
    echo          Started from AppData.
) else (
    echo          [!] PowerToys not found - skipping.
)
call :log "PowerToys start attempted"

echo   [2/10] Enabling NVIDIA RTX 3050...
:: Re-enable the discrete GPU for full performance
powershell -NoProfile -Command ^
  "$gpu = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' -and $_.Class -eq 'Display' }; " ^
  "if ($gpu) { $gpu | Enable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue; Write-Host 'RTX 3050 enabled.' } " ^
  "else { Write-Host 'NVIDIA GPU not found.' }"
:: Start NVIDIA services
net start NVDisplay.ContainerLocalSystem >nul 2>&1
net start NvTelemetryContainer >nul 2>&1
call :log "RTX 3050 ENABLED"

echo   [3/10] Setting Power Plan to Ultimate / High Performance...
:: Try Ultimate Performance first
powercfg -setactive e9a42b02-d5df-448d-aa00-03f14749eb61 >nul 2>&1
if %errorlevel% neq 0 (
    powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 >nul 2>&1
    powercfg -setactive e9a42b02-d5df-448d-aa00-03f14749eb61 >nul 2>&1
    if !errorlevel! neq 0 (
        powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >nul 2>&1
        if !errorlevel! neq 0 (
            powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e >nul 2>&1
        )
    )
)
call :log "Power plan set to Ultimate/High Performance"

echo   [4/10] Setting Windows Power Slider to Best Performance...
powercfg /SetActiveOverlay SCHEME_CURRENT ded574b5-45a0-4f42-8737-46345c09c238 >nul 2>&1

echo   [5/10] Unlocking Ryzen 5600H, Boost AGGRESSIVE...
:: Ryzen 5600H: Unlock full 45W TDP, all 6 cores / 12 threads
:: CPU max to 100% on AC and DC
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1
:: CPU min to 10%
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 10 >nul 2>&1
:: Enable AMD Precision Boost Overdrive (Aggressive)
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 2 >nul 2>&1
:: All 12 threads active - no core parking
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100 >nul 2>&1
:: AMD pstate driver: performance autonomous mode
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFAUTONOMOUS 0 >nul 2>&1
:: EPP: 0 = max performance
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 0 >nul 2>&1
call :log "Ryzen 5600H 100%%, Boost Aggressive, EPP=0, 12T active"

echo   [6/10] OLED Display: max brightness, always on...
:: Screen never turns off when plugged in
powercfg /change monitor-timeout-ac 0
:: Never sleep when plugged in
powercfg /change standby-timeout-ac 0
:: Disable hibernate when plugged in
powercfg /change hibernate-timeout-ac 0
:: OLED brightness to 85% (100% can cause faster degradation)
powershell -NoProfile -Command "(Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightnessMethods).WmiSetBrightness(1, 85)" >nul 2>&1
:: Re-enable light mode (user preference - can comment out)
:: reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "AppsUseLightTheme" /t REG_DWORD /d 1 /f >nul 2>&1
call :log "OLED 85%%, always on, no sleep"

echo   [7/10] NVMe SSD: max performance...
:: Disable NVMe power saving for max throughput
powercfg /setacvalueindex SCHEME_CURRENT SUB_DISK dbc9e238-6de9-49e3-92cd-8c2b4946b472 0 >nul 2>&1
:: Set max latency tolerance
powercfg /setacvalueindex SCHEME_CURRENT SUB_DISK fc95af4d-40e7-4b6d-835a-56d131dbc80e 0 >nul 2>&1
:: FIX-4: SATA AHCI Link PM GUID removed (NVMe-only machine)
call :log "NVMe SSD: max performance, no PM"

echo   [8/10] USB, PCIe, Wi-Fi: max performance...
:: Disable USB selective suspend on AC
powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 >nul 2>&1
:: PCIe Link State PM OFF (critical for RTX 3050 x8 PCIe lane)
powercfg /setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 >nul 2>&1
:: Wi-Fi: Maximum Performance
powercfg /setacvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 >nul 2>&1
:: Apply all powercfg changes
powercfg /setactive SCHEME_CURRENT >nul 2>&1
call :log "USB always on, PCIe no PM, Wi-Fi max perf"

echo   [9/10] Re-enabling background services + NVIDIA...
net start WSearch >nul 2>&1
net start wuauserv >nul 2>&1
net start SysMain >nul 2>&1
net start DiagTrack >nul 2>&1
net start Spooler >nul 2>&1
net start BITS >nul 2>&1
net start WbioSrvc >nul 2>&1
net start NVDisplay.ContainerLocalSystem >nul 2>&1
:: FIX-1: Restore MongoDB to auto start (was set to demand in saver/PSB modes)
sc config MongoDB start= auto >nul 2>&1
call :log "Services restored (including NVIDIA, MongoDB auto-start)"

:: Re-enable scheduled tasks
schtasks /change /tn "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Autochk\Proxy" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Windows Error Reporting\QueueReporting" /enable >nul 2>&1
schtasks /change /tn "\NvTmMon_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}" /enable >nul 2>&1
schtasks /change /tn "\NvTmRep_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}" /enable >nul 2>&1
call :log "Scheduled tasks re-enabled"

echo   [10/10] Disabling Windows Energy Saver...
powercfg /setdcvalueindex SCHEME_CURRENT e73a048d-bf27-4f12-9731-8b2076e8891f 637ea02f-bbcb-4015-8e2c-a1c7b9c0b546 20 >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v "EnergySaverEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
powershell -NoProfile -Command ^
  "try { " ^
  "  $s = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GlobalSettings\EnergySaver'; " ^
  "  if (Test-Path $s) { " ^
  "    Set-ItemProperty -Path $s -Name 'EnergySaverEnabled' -Value 0 -Type DWord -Force; " ^
  "    Set-ItemProperty -Path $s -Name 'BatterySaverEnabled' -Value 0 -Type DWord -Force; " ^
  "  } " ^
  "} catch { }; " ^
  "try { " ^
  "  $p = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\EnergySaver\Parameters'; " ^
  "  if (Test-Path $p) { " ^
  "    Set-ItemProperty -Path $p -Name 'BatterySaverBatteryThreshold' -Value 20 -Type DWord -Force; " ^
  "    Set-ItemProperty -Path $p -Name 'BatterySaverEnabled' -Value 0 -Type DWord -Force; " ^
  "  } " ^
  "} catch { }" >nul 2>&1
call :log "Energy Saver disabled"

echo.
echo   +==============================================================+
echo   :            MAX PERFORMANCE is now ON!                        :
echo   +--------------------------------------------------------------+
echo   :  Ryzen 5600H: 100%% / Boost AGGRESSIVE / 12 threads ON       :
echo   :  RTX 3050:    ENABLED / PCIe Link PM OFF                     :
echo   :  OLED:        85%% brightness / Always on / No sleep         :
echo   :  NVMe SSD:    Max throughput / APST OFF                      :
echo   :  Wi-Fi:       Max performance / USB: Always powered          :
echo   :  Services:    All restored + NVIDIA                          :
echo   :  Energy Saver: OFF                                           :
echo   +==============================================================+
echo.
echo   Log: %LOGFILE%
echo.
pause
goto menu

:: =============================================================
::                  BALANCED MODE
:: =============================================================
:balanced
cls
if not "!CURRENT_MODE!"=="BALANCED" goto start_bal
echo.
echo   [!] Balanced Mode is already active. Skipping re-activation.
echo.
call :log "Balanced activation skipped (already active)"
pause
goto menu
:start_bal
set "CURRENT_MODE=BALANCED"
echo BALANCED>"%~dp0.powermode.state"
call :log "=== BALANCED MODE ACTIVATED ==="
echo.
echo   +==============================================================+
echo   :         Restoring Balanced Settings for Vivobook Pro         :
echo   +==============================================================+
echo.

echo   [1/7] Re-enabling NVIDIA RTX 3050 (hybrid mode)...
powershell -NoProfile -Command ^
  "$gpu = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' -and $_.Class -eq 'Display' }; " ^
  "if ($gpu) { $gpu | Enable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue }"
net start NVDisplay.ContainerLocalSystem >nul 2>&1

echo   [2/7] Setting Balanced power plan...
powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e >nul 2>&1

echo   [3/7] Restoring Ryzen 5600H defaults...
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5 >nul 2>&1
:: Turbo Boost: Efficient (balanced for Ryzen)
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 4 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 4 >nul 2>&1
:: EPP: 50 = balanced
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 50 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 50 >nul 2>&1
:: Display / sleep
powercfg /change monitor-timeout-dc 5
powercfg /change monitor-timeout-ac 10
powercfg /change standby-timeout-dc 15
powercfg /change standby-timeout-ac 30
powercfg /change hibernate-timeout-dc 60
powercfg /change hibernate-timeout-ac 0
:: NVMe: balanced
powercfg /setdcvalueindex SCHEME_CURRENT SUB_DISK dbc9e238-6de9-49e3-92cd-8c2b4946b472 1 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT SUB_DISK dbc9e238-6de9-49e3-92cd-8c2b4946b472 0 >nul 2>&1
:: USB selective suspend: on battery, off on AC
powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 >nul 2>&1
:: PCIe: moderate on battery
powercfg /setdcvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 1 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 >nul 2>&1
:: Wi-Fi: medium saving on battery
powercfg /setdcvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 2 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 >nul 2>&1
:: OLED Brightness 60%
powershell -NoProfile -Command "(Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightnessMethods).WmiSetBrightness(1, 60)" >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1

echo   [4/7] Re-enabling services...
net start WSearch >nul 2>&1
net start wuauserv >nul 2>&1
net start SysMain >nul 2>&1
net start Spooler >nul 2>&1
net start BITS >nul 2>&1

echo   [5/7] Resetting Energy Saver to default (20%%)...
powercfg /setdcvalueindex SCHEME_CURRENT e73a048d-bf27-4f12-9731-8b2076e8891f 637ea02f-bbcb-4015-8e2c-a1c7b9c0b546 20 >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1

echo   [6/7] Resetting GPU preferences to auto (Optimus)...
:: Clear global GPU preference set by Ultra Performance mode
reg delete "HKLM\SOFTWARE\Microsoft\DirectX\UserGpuPreferences" /v "DirectXUserGlobalSettings" /f >nul 2>&1
:: FIX-6: Restore GPU registry to OEM defaults.
:: EnableMsHybrid: OEM default is KEY ABSENT (verified in registry).
:: Ultra Performance creates this key with value 2 to force NVIDIA rendering.
:: Deleting it returns the driver to its built-in Optimus auto-select behavior.
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001" /v "EnableMsHybrid" /f >nul 2>&1
:: DisablePowerMizer: Ultra Performance sets this to 1 (PowerMizer OFF).
:: Restore to 0 = PowerMizer enabled (normal NVIDIA power management).
reg add "HKCU\SOFTWARE\NVIDIA Corporation\Global\NVTweak" /v "DisablePowerMizer" /t REG_DWORD /d 0 /f >nul 2>&1
:: Restore MongoDB to auto start
sc config MongoDB start= auto >nul 2>&1
call :log "GPU preferences reset to Optimus auto (explicit defaults)"

echo   [7/7] Resetting video playback to balanced...
:: Video quality was set to power-save in saver, max in ultra perf — reset to default
powercfg /setdcvalueindex SCHEME_CURRENT 9596fb26-9850-41fd-ac3e-f7c3c00afd4b 34c7b151-7bf6-4e87-b075-e0f5f5899773 0 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT 9596fb26-9850-41fd-ac3e-f7c3c00afd4b 34c7b151-7bf6-4e87-b075-e0f5f5899773 0 >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1
call :log "Video playback reset to balanced"

:: Re-enable scheduled tasks
schtasks /change /tn "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Autochk\Proxy" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Windows Error Reporting\QueueReporting" /enable >nul 2>&1
schtasks /change /tn "\NvTmMon_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}" /enable >nul 2>&1
schtasks /change /tn "\NvTmRep_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}" /enable >nul 2>&1
call :log "Balanced mode restored (GPU prefs reset, video reset)"

echo.
echo   +==============================================================+
echo   :              BALANCED mode restored!                         :
echo   +--------------------------------------------------------------+
echo   :  Ryzen 5600H: 100%% / Boost: Efficient / EPP: 50             :
echo   :  RTX 3050:    ENABLED (hybrid/Optimus mode)                  :
echo   :  OLED:        60%% / Off 5/10 min / Sleep: 15/30 min         :
echo   :  NVMe SSD:    Balanced PM / Energy Saver: 20%% default       :
echo   :  GPU Prefs:   Reset to Optimus auto                           :
echo   :  Video:       Default quality (balanced)                      :
echo   :  All services running / Tasks enabled                        :
echo   +==============================================================+
echo.
pause
goto menu

:: =============================================================
::         POWER SAVING BALANCED MODE  [P]
::  The sweet spot: smooth performance + real battery savings
::  CPU fully unlocked (no 40% cap) — no lag
::  RTX 3050 OFF (saves ~15-25W)
::  Wi-Fi max power saving
::  PowerToys fully killed (Awake blocks sleep)
::  OLED 50% / screen off 3 min / sleep 10 min
:: =============================================================
:psbalanced
cls
if not "!CURRENT_MODE!"=="PSBALANCED" goto start_psbal
echo.
echo   [!] Power Saving Balanced is already active. Skipping re-activation.
echo       Use [R] to Quick Re-apply if settings have drifted.
echo.
call :log "Power Saving Balanced skipped (already active)"
pause
goto menu
:start_psbal
set "CURRENT_MODE=PSBALANCED"
echo PSBALANCED>"%~dp0.powermode.state"
call :logrotate
call :log "=== POWER SAVING BALANCED MODE ACTIVATED ==="
echo.
echo   +==============================================================+
echo   :      Applying POWER SAVING BALANCED for Vivobook Pro OLED    :
echo   :      Smooth performance + real battery savings               :
echo   +==============================================================+
echo.

echo   [1/9] Killing PowerToys + Antigravity (block sleep, all plugins off)...
:: PowerToys.Awake prevents system sleep — kill the whole suite
taskkill /IM "PowerToys.Awake.exe" /F /T >nul 2>&1
taskkill /FI "IMAGENAME eq PowerToys.exe" /F /T >nul 2>&1
taskkill /FI "IMAGENAME eq PowerToys.Settings.exe" /F /T >nul 2>&1
taskkill /FI "IMAGENAME eq PowerToys.Peek.UI.exe" /F /T >nul 2>&1
taskkill /FI "IMAGENAME eq PowerToys.FancyZones.exe" /F /T >nul 2>&1
taskkill /FI "IMAGENAME eq PowerToys.PowerLauncher.exe" /F /T >nul 2>&1
taskkill /FI "IMAGENAME eq PowerToys.ColorPicker.exe" /F /T >nul 2>&1
taskkill /FI "IMAGENAME eq PowerToys.ImageResizer.exe" /F /T >nul 2>&1
taskkill /FI "IMAGENAME eq PowerToys.KeyboardManager.exe" /F /T >nul 2>&1
:: Antigravity (energy report: execution-required request preventing sleep)
taskkill /IM "Antigravity.exe" /F /T >nul 2>&1
:: FIX-8: Kill Antigravity's language server (energy report: ~1%% combined CPU)
taskkill /IM "language_server_windows_x64.exe" /F >nul 2>&1
call :log "PowerToys + Antigravity + LSP fully killed (all plugins)"

echo   [2/9] Disabling NVIDIA RTX 3050 (iGPU only, saves ~15-25W)...
:: Force everything onto Radeon Vega 7 iGPU
:: RTX 3050 idle power draw alone is ~8-10W even when not rendering
powershell -NoProfile -Command ^
  "$gpu = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' -and $_.Class -eq 'Display' }; " ^
  "if ($gpu) { $gpu | Disable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue; Write-Host '  RTX 3050 disabled.' } " ^
  "else { Write-Host '  NVIDIA GPU not found or already disabled.' }"
:: Stop NVIDIA background services (they run even when GPU is idle)
net stop NVDisplay.ContainerLocalSystem >nul 2>&1
net stop NvTelemetryContainer >nul 2>&1
taskkill /IM "NVDisplay.Container.exe" /F /T >nul 2>&1
taskkill /IM "nvcontainer.exe" /F /T >nul 2>&1
taskkill /IM "NvTelemetryContainer.exe" /F /T >nul 2>&1
call :log "RTX 3050 DISABLED + NVIDIA services stopped"

echo   [3/9] Setting Balanced power plan (base)...
:: Use Balanced as the plan foundation — not Power Saver
:: This keeps the OS scheduler responsive and avoids CPU frequency floor issues
powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e >nul 2>&1
call :log "Power plan set to Balanced (base for PSB mode)"

echo   [4/9] CPU: Full speed, Boost efficient, EPP 50 (no lag!)...
:: KEY DIFFERENCE from Ultra Saver: CPU is NOT capped at 40%%
:: Full 100%% max frequency — the Ryzen 5600H can clock up when needed
:: No lag during bursts, no throttling on multi-tab browsing or compilation
:: CPU max: 100%% (both AC and DC — matches Balanced)
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1
:: CPU min: 5%% (deep idle, matches Balanced)
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5 >nul 2>&1
:: Boost mode: Efficient (4) — boosts when needed, backs off fast
:: Not Aggressive (2) which burns power, not Disabled (0) which causes lag
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 4 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 4 >nul 2>&1
:: Core parking: let OS park idle threads (balanced — not aggressive like Saver)
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 25 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 25 >nul 2>&1
:: Autonomous mode: let AMD pstate driver manage clocks (balanced)
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFAUTONOMOUS 1 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFAUTONOMOUS 1 >nul 2>&1
:: EPP: 50 = balanced (same as Balanced mode — performance when needed, saves at idle)
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 50 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 50 >nul 2>&1
call :log "CPU: 100%% max, Boost Efficient, EPP=50, CPMINCORES=25, Autonomous ON"

echo   [5/9] OLED: 50%% brightness, screen off 3min, sleep 10min...
:: Brightness at 50%% — comfortable for work, meaningful OLED power saving
:: (OLED power scales linearly: 50%% brightness ~ half the panel power vs 100%%)
powershell -NoProfile -Command "(Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightnessMethods).WmiSetBrightness(1, 50)" >nul 2>&1
:: Screen off after 3 minutes on battery (tighter than Balanced's 5 min)
powercfg /change monitor-timeout-dc 3
:: Screen off after 10 minutes on AC (same as Balanced)
powercfg /change monitor-timeout-ac 10
:: Sleep after 10 minutes on battery (tighter than Balanced's 15 min)
powercfg /change standby-timeout-dc 10
powercfg /change standby-timeout-ac 30
:: Hibernate after 30 minutes on battery
powercfg /change hibernate-timeout-dc 30
powercfg /change hibernate-timeout-ac 0
call :log "OLED: 50%% brightness, screen off 3/10min, sleep 10/30min"

echo   [6/9] Wi-Fi: max power saving (DC + AC)...
:: Set Wi-Fi to maximum power saving on battery
powercfg /setdcvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 3 >nul 2>&1
:: Also power saving on AC since we're targeting efficiency
powercfg /setacvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 2 >nul 2>&1
:: USB selective suspend: ON for battery, ON for AC (saves ~1-2W)
powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 >nul 2>&1
:: PCIe: moderate savings on battery (GPU is off so PCIe lane impact is minimal)
powercfg /setdcvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 1 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1
call :log "Wi-Fi max saving (DC+AC), USB suspend ON, PCIe moderate"

echo   [7/10] NVMe SSD: balanced power management...
:: NVMe APST ON for battery (same as Balanced)
powercfg /setdcvalueindex SCHEME_CURRENT SUB_DISK dbc9e238-6de9-49e3-92cd-8c2b4946b472 1 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT SUB_DISK dbc9e238-6de9-49e3-92cd-8c2b4946b472 0 >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1
call :log "NVMe: APST ON (battery), off (AC)"

echo   [8/10] Setting video playback to power-saving on battery...
:: FIX-9: PSB mode was missing video playback optimization.
:: Energy report flagged "Optimize for Video Quality" on battery — wasteful.
powercfg /setdcvalueindex SCHEME_CURRENT 9596fb26-9850-41fd-ac3e-f7c3c00afd4b 34c7b151-7bf6-4e87-b075-e0f5f5899773 1 >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1
call :log "Video playback set to power-saving on battery"

echo   [9/10] Keeping MongoDB at demand start...
:: FIX-10: PSB is a battery-saving mode. MongoDB 8.3 should stay at demand
:: start (like Saver). Only Performance/Balanced should restore it to auto.
:: Previous BUG-23 fix was wrong here — it restored MongoDB to auto in PSB.
sc config MongoDB start= demand >nul 2>&1
call :log "MongoDB kept at demand start (battery-saving mode)"

echo   [10/10] Resetting Energy Saver to default 20%% threshold...
:: Do NOT force Energy Saver to 100%% like Ultra Saver does
:: Keep it at 20%% so it only kicks in when truly low
powercfg /setdcvalueindex SCHEME_CURRENT e73a048d-bf27-4f12-9731-8b2076e8891f 637ea02f-bbcb-4015-8e2c-a1c7b9c0b546 20 >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v "EnergySaverEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
call :log "Energy Saver at 20%% default (not forced)"

echo.
echo   +==============================================================+
echo   :       POWER SAVING BALANCED v10.0 is now ON!                 :
echo   +--------------------------------------------------------------+
echo   :  Ryzen 5600H: 100%% max / Boost EFFICIENT / EPP 50           :
echo   :                No 40%% cap — smooth and responsive!           :
echo   :  RTX 3050:    DISABLED (Radeon iGPU only, saves ~15-25W)     :
echo   :  NVIDIA Svcs: STOPPED (no background GPU drain)              :
echo   :  PowerToys:   FULLY KILLED (all plugins, Awake OFF)          :
echo   :  OLED:        50%% brightness / Screen off 3min / Sleep 10m  :
echo   :  Wi-Fi:       Max power saving (DC + AC)                     :
echo   :  USB:         Selective suspend ON (AC + DC)                  :
echo   :  NVMe SSD:    Balanced PM (APST on battery)                  :
echo   :  Video:       Power-saving playback on battery               :
echo   :  MongoDB:     Kept at demand start (not auto)                :
echo   :  Energy Saver: Default 20%% threshold (not forced)           :
echo   +--------------------------------------------------------------+
echo   :  vs Ultra Saver [1]: CPU runs free — no lag. Less aggressive  :
echo   :  vs Balanced [3]:    RTX off + Wi-Fi saving + no PowerToys   :
echo   +--------------------------------------------------------------+
echo   :  TIP: Use Balanced [3] to restore RTX 3050 + PowerToys       :
echo   +==============================================================+
echo.
echo   Log: %LOGFILE%
echo.
pause
goto menu

:: =============================================================
::                  GPU SWITCH (RTX 3050 TOGGLE)
:: =============================================================
:gpuswitch
cls
call :log "GPU Switch menu accessed"
echo.
echo   +==============================================================+
echo   :                GPU SWITCH - RTX 3050 / iGPU                  :
echo   +==============================================================+
echo.
echo   Your laptop has two GPUs:
echo     - AMD Radeon Graphics (Vega 7) - integrated, low power ~5W
echo     - NVIDIA GeForce RTX 3050 4GB  - discrete, high power ~75W
echo.

:: Show current GPU state
echo   Current GPU status:
powershell -NoProfile -Command ^
  "Get-PnpDevice | Where-Object { $_.Class -eq 'Display' } | " ^
  "Select-Object FriendlyName, Status | Format-Table -AutoSize | Out-String"
echo.
echo   [1] Disable RTX 3050 (iGPU only - saves ~15-25W)
echo   [2] Enable RTX 3050 (full GPU power)
echo   [3] Set NVIDIA to prefer Maximum Performance
echo   [4] Set NVIDIA to prefer Power Saving (Optimus auto-switch)
echo   [5] Back to menu
echo.
set /p gpuChoice="  Select (1-5): "

if "%gpuChoice%"=="1" goto gpu1
if "%gpuChoice%"=="2" goto gpu2
if "%gpuChoice%"=="3" goto gpu3
if "%gpuChoice%"=="4" goto gpu4
if "%gpuChoice%"=="5" goto menu
goto gpuswitch

:gpu1
echo.
echo   Disabling RTX 3050...
powershell -NoProfile -Command ^
  "$gpu = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' -and $_.Class -eq 'Display' }; " ^
  "if ($gpu) { " ^
  "  $gpu | Disable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue; " ^
  "  Write-Host '  RTX 3050 DISABLED. Using Radeon iGPU only.'; " ^
  "} else { Write-Host '  NVIDIA GPU not found.' }"
net stop NVDisplay.ContainerLocalSystem >nul 2>&1
call :log "RTX 3050 manually disabled"
goto gpu_end

:gpu2
echo.
echo   Enabling RTX 3050...
powershell -NoProfile -Command ^
  "$gpu = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' -and $_.Class -eq 'Display' }; " ^
  "if ($gpu) { " ^
  "  $gpu | Enable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue; " ^
  "  Write-Host '  RTX 3050 ENABLED.'; " ^
  "} else { Write-Host '  NVIDIA GPU not found.' }"
net start NVDisplay.ContainerLocalSystem >nul 2>&1
call :log "RTX 3050 manually enabled"
goto gpu_end

:gpu3
echo.
echo   Setting NVIDIA to Maximum Performance globally...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001" /v "PerfLevelSrc" /t REG_DWORD /d 8738 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001" /v "PowerMizerEnable" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001" /v "PowerMizerLevel" /t REG_DWORD /d 1 /f >nul 2>&1
echo   NVIDIA set to Maximum Performance.
echo   (You may also set this in NVIDIA Control Panel for per-app control)
call :log "NVIDIA set to max performance"
goto gpu_end

:gpu4
echo.
echo   Setting NVIDIA to Power Saving (Optimus auto-switch)...
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001" /v "PerfLevelSrc" /t REG_DWORD /d 8738 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001" /v "PowerMizerEnable" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001" /v "PowerMizerLevel" /t REG_DWORD /d 3 /f >nul 2>&1
echo   NVIDIA set to Power Saving (auto Optimus switching).
call :log "NVIDIA set to power saving/Optimus"
goto gpu_end

:gpu_end
echo.
pause
goto gpuswitch

:: =============================================================
::                  SYSTEM STATUS DASHBOARD
:: =============================================================
:status
cls
call :log "Status dashboard viewed"
echo.
echo   +==============================================================+
echo   :          SYSTEM STATUS - Vivobook Pro OLED                   :
echo   +==============================================================+
echo.

:: Power source (CIM instead of deprecated WMIC)
echo   --- Power Source ---
powershell -NoProfile -Command ^
  "$b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue; " ^
  "if ($b) { " ^
  "  $src = if ($b.BatteryStatus -eq 2) {'Charging / Plugged In'} elseif ($b.BatteryStatus -eq 1) {'On Battery'} else {'Unknown'}; " ^
  "  Write-Host ('  Source: ' + $src); " ^
  "  Write-Host ('  Battery: ' + $b.EstimatedChargeRemaining + '%%'); " ^
  "} else { Write-Host '  Source: Desktop / No Battery' }"

:: Active power plan
echo   --- Active Power Plan ---
for /f "tokens=*" %%A in ('powercfg /getactivescheme 2^>nul') do echo   %%A
echo.

:: CPU info (CIM instead of deprecated WMIC)
echo   --- Ryzen 5 5600H ---
powershell -NoProfile -Command ^
  "$cpu = Get-CimInstance Win32_Processor; " ^
  "Write-Host ('  Processor: ' + $cpu.Name); " ^
  "Write-Host ('  Cores: ' + $cpu.NumberOfCores + ' (' + $cpu.NumberOfLogicalProcessors + ' Threads)'); " ^
  "Write-Host ('  Current Load: ' + $cpu.LoadPercentage + '%%'); " ^
  "Write-Host ('  Current Clock: ' + $cpu.CurrentClockSpeed + ' MHz (Base: 3300 MHz, Boost: 4200 MHz)')"
echo.

:: GPU status
echo   --- Graphics ---
powershell -NoProfile -Command ^
  "Get-PnpDevice | Where-Object { $_.Class -eq 'Display' } | " ^
  "ForEach-Object { Write-Host ('  ' + $_.FriendlyName + ': ' + $_.Status) }"
echo.

:: RAM usage (CIM instead of deprecated WMIC)
echo   --- Memory (16 GB DDR4) ---
powershell -NoProfile -Command ^
  "$os = Get-CimInstance Win32_OperatingSystem; " ^
  "$totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024); " ^
  "$freeMB = [math]::Round($os.FreePhysicalMemory / 1024); " ^
  "$usedMB = $totalMB - $freeMB; " ^
  "Write-Host ('  Total RAM: ' + $totalMB + ' MB'); " ^
  "Write-Host ('  Used RAM:  ' + $usedMB + ' MB'); " ^
  "Write-Host ('  Free RAM:  ' + $freeMB + ' MB')"

:: Storage
echo   --- NVMe SSD (512 GB) ---
powershell -NoProfile -Command ^
  "Get-PhysicalDisk | Select-Object FriendlyName, MediaType, Size, HealthStatus | " ^
  "ForEach-Object { " ^
  "  $sizeGB = [math]::Round($_.Size / 1GB, 1); " ^
  "  Write-Host ('  ' + $_.FriendlyName + ' (' + $_.MediaType + ') - ' + $sizeGB + ' GB - ' + $_.HealthStatus) " ^
  "}" 2>nul
echo.

:: Disk space (uses PowerShell to avoid 32-bit integer overflow in set /a)
echo   --- Disk Space ---
powershell -NoProfile -Command ^
  "$d = Get-PSDrive C; " ^
  "$freeGB = [math]::Round($d.Free / 1GB, 1); " ^
  "$usedGB = [math]::Round($d.Used / 1GB, 1); " ^
  "Write-Host ('  C: Free: ' + $freeGB + ' GB / Used: ' + $usedGB + ' GB')" 2>nul
echo.

:: Temperature (if available)
echo   --- Thermals ---
powershell -NoProfile -Command ^
  "try { " ^
  "  $temp = Get-CimInstance MSAcpi_ThermalZoneTemperature -Namespace 'root/WMI' -ErrorAction Stop; " ^
  "  foreach ($t in $temp) { " ^
  "    $celsius = [math]::Round(($t.CurrentTemperature - 2732) / 10.0, 1); " ^
  "    Write-Host ('  Thermal Zone: ' + $celsius + ' C'); " ^
  "  } " ^
  "} catch { Write-Host '  Temperature data not available (run as admin)' }" 2>nul
echo.

:: Key services
echo   --- Key Services ---
for %%S in (WSearch wuauserv SysMain DiagTrack Spooler BITS NVDisplay.ContainerLocalSystem) do (
    sc query %%S 2>nul | find "RUNNING" >nul 2>&1
    if !errorlevel! equ 0 (
        echo   %%S: RUNNING
    ) else (
        echo   %%S: STOPPED
    )
)
echo.

:: Uptime (CIM instead of deprecated WMIC)
echo   --- System Uptime ---
powershell -NoProfile -Command ^
  "$os = Get-CimInstance Win32_OperatingSystem; " ^
  "$boot = $os.LastBootUpTime; " ^
  "$up = (Get-Date) - $boot; " ^
  "Write-Host ('  Last Boot: ' + $boot.ToString('yyyy-MM-dd HH:mm')); " ^
  "Write-Host ('  Uptime: ' + [int]$up.TotalHours + 'h ' + $up.Minutes + 'm')"
echo.

echo   --- Network Adapters ---
powershell -NoProfile -Command "Get-NetAdapter | Where-Object Status -eq 'Up' | Format-Table Name, Status, LinkSpeed -AutoSize | Out-String" 2>nul
echo.

pause
goto menu

:: =============================================================
::                  BATTERY REPORT + HEALTH ANALYSIS
:: =============================================================
:batteryreport
cls
call :log "Battery report generated"
echo.
echo   Generating battery health report...
powercfg /batteryreport /output "%~dp0battery-report.html" >nul 2>&1
if %errorlevel% equ 0 (
    echo   Report saved to: %~dp0battery-report.html
) else (
    echo   [!] Could not generate battery report.
)
echo.

:: ---- Quick Battery Health Analysis (CIM-based) ----
echo   +--------------------------------------------------------------+
echo   :             BATTERY HEALTH ANALYSIS                         :
echo   +--------------------------------------------------------------+
powershell -NoProfile -Command ^
  "$b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue; " ^
  "if ($b) { " ^
  "  Write-Host ('  Current Charge:        ' + $b.EstimatedChargeRemaining + '%%'); " ^
  "  Write-Host ('  Battery Status:        ' + $b.Status); " ^
  "} else { Write-Host '  [!] No battery detected.' }; " ^
  "try { " ^
  "  $html = Get-Content '%~dp0energy-report.html' -Raw -ErrorAction Stop; " ^
  "  if ($html -match 'Design Capacity.*?(\d+)') { $dc = $Matches[1]; Write-Host ('  Design Capacity:       ' + $dc + ' mWh') }; " ^
  "  if ($html -match 'Last Full Charge.*?(\d+)') { $fc = $Matches[1]; Write-Host ('  Full Charge Capacity:  ' + $fc + ' mWh') }; " ^
  "  if ($html -match 'Cycle Count.*?(\d+)') { $cc = $Matches[1]; Write-Host ('  Cycle Count:           ' + $cc) }; " ^
  "  if ($dc -and $fc) { " ^
  "    $health = [math]::Round([int]$fc / [int]$dc * 100, 1); " ^
  "    Write-Host ('  Battery Health:        ' + $health + '%%'); " ^
  "    Write-Host; " ^
  "    if ($health -ge 80) { Write-Host '  Status: GOOD - Battery is healthy.' } " ^
  "    elseif ($health -ge 60) { Write-Host '  Status: FAIR - Consider monitoring degradation.' } " ^
  "    else { Write-Host '  Status: POOR - Battery replacement recommended.' }; " ^
  "    if ($health -le 85) { Write-Host '  TIP: Avoid draining below 20%% and charging above 80%%'; Write-Host '       to slow further degradation.' }; " ^
  "  }; " ^
  "} catch { Write-Host '  [!] Run energy report first for detailed capacity data.' }"
echo   +--------------------------------------------------------------+
echo.

echo   Opening battery report in browser...
if exist "%~dp0battery-report.html" start "" "%~dp0battery-report.html"
echo.
echo   Generating energy efficiency report (takes ~60 sec)...
echo   (Analyzes power usage and gives recommendations)
set /p genEnergy="  Generate energy report? (y/n): "
if /i "%genEnergy%"=="y" (
    powercfg /energy /output "%~dp0energy-report.html" >nul 2>&1
    if %errorlevel% equ 0 (
        echo   Energy report saved to: %~dp0energy-report.html
        start "" "%~dp0energy-report.html"
    ) else (
        echo   [!] Could not generate energy report. Requires admin.
    )
)
echo.
pause
goto menu

:: =============================================================
::                  NETWORK SAVER TOGGLE
:: =============================================================
:networksaver
cls
call :log "Network saver menu accessed"
echo.
echo   +==============================================================+
echo   :                  NETWORK POWER SAVER                         :
echo   +==============================================================+
echo.
echo   Current network adapters:
echo.
powershell -NoProfile -Command "Get-NetAdapter | Format-Table Name, Status, MediaType, LinkSpeed -AutoSize | Out-String"
echo.
echo   [1] Disable Bluetooth adapter (save ~2W)
echo   [2] Enable Bluetooth adapter
echo   [3] Set Wi-Fi to max power saving
echo   [4] Set Wi-Fi to max performance
echo   [5] Disable all unused adapters
echo   [6] Back to menu
echo.
set /p netChoice="  Select (1-6): "

if "%netChoice%"=="1" goto net1
if "%netChoice%"=="2" goto net2
if "%netChoice%"=="3" goto net3
if "%netChoice%"=="4" goto net4
if "%netChoice%"=="5" goto net5
if "%netChoice%"=="6" goto menu
goto networksaver

:net1
powershell -NoProfile -Command "Get-NetAdapter | Where-Object { $_.Name -like '*Bluetooth*' } | Disable-NetAdapter -Confirm:$false" >nul 2>&1
net stop bthserv >nul 2>&1
echo   Bluetooth disabled.
call :log "Bluetooth adapter disabled"
goto net_end

:net2
powershell -NoProfile -Command "Get-NetAdapter | Where-Object { $_.Name -like '*Bluetooth*' } | Enable-NetAdapter -Confirm:$false" >nul 2>&1
net start bthserv >nul 2>&1
echo   Bluetooth enabled.
call :log "Bluetooth adapter enabled"
goto net_end

:net3
powercfg /setdcvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 3 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 3 >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1
echo   Wi-Fi set to max power saving.
call :log "Wi-Fi max power saving"
goto net_end

:net4
powercfg /setdcvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 >nul 2>&1
powercfg /setacvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1
echo   Wi-Fi set to max performance.
call :log "Wi-Fi max performance"
goto net_end

:net5
echo   Disabling adapters that are disconnected...
powershell -NoProfile -Command "Get-NetAdapter | Where-Object { $_.Status -eq 'Disconnected' } | Disable-NetAdapter -Confirm:$false" >nul 2>&1
echo   Done.
call :log "Unused network adapters disabled"
goto net_end

:net_end
echo.
pause
goto networksaver

:: =============================================================
::                  STARTUP CLEANUP
:: =============================================================
:startupcleanup
cls
call :log "Startup cleanup accessed"
echo.
echo   +==============================================================+
echo   :                 STARTUP ITEMS CLEANUP                        :
echo   +==============================================================+
echo.
echo   Current startup programs (from registry):
echo   ------------------------------------------
echo.

powershell -NoProfile -Command ^
  "$paths = @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'); " ^
  "foreach ($p in $paths) { " ^
  "  if (Test-Path $p) { " ^
  "    $props = Get-ItemProperty $p; " ^
  "    $props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { " ^
  "      Write-Host ('  ' + $_.Name + ': ' + $_.Value); " ^
  "    } " ^
  "  } " ^
  "}"
echo.
echo   ------------------------------------------
echo.
echo   [1] Disable common bloatware startups
echo       (Cortana, OneDrive, Teams, Spotify, Discord, Asus bloat)
echo   [2] Re-enable startup policies
echo   [3] Show Task Manager startup list
echo   [4] Back to menu
echo.
set /p startChoice="  Select (1-4): "

if "%startChoice%"=="1" goto start1
if "%startChoice%"=="2" goto start2
if "%startChoice%"=="3" goto start3
if "%startChoice%"=="4" goto menu
goto startupcleanup

:start1
echo.
echo   Disabling common auto-start entries...
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "OneDrive" /f >nul 2>&1
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "com.squirrel.Teams.Teams" /f >nul 2>&1
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "MicrosoftTeams" /f >nul 2>&1
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "Spotify" /f >nul 2>&1
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "Discord" /f >nul 2>&1
REM Asus-specific bloatware
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "ArmouryCrate" /f >nul 2>&1
reg delete "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" /v "ArmouryCrate" /f >nul 2>&1
reg delete "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" /v "AsusSplendid" /f >nul 2>&1
reg delete "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" /v "AsusOptimization" /f >nul 2>&1
REM Cortana
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "AllowCortana" /t REG_DWORD /d 0 /f >nul 2>&1
REM Edge startup boost
reg add "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v "StartupBoostEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
REM NVIDIA GeForce Experience overlay (battery drain)
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "NvBackend" /f >nul 2>&1
echo   Done! Common + Asus + NVIDIA auto-start items disabled.
call :log "Startup bloatware disabled (incl. Asus + NVIDIA)"
goto start_end

:start2
echo.
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search" /v "AllowCortana" /f >nul 2>&1
reg delete "HKLM\SOFTWARE\Policies\Microsoft\Edge" /v "StartupBoostEnabled" /f >nul 2>&1
echo   Cortana and Edge startup boost policies removed.
call :log "Startup policies reset"
goto start_end

:start3
echo   Opening Task Manager Startup tab...
start taskmgr /7
goto start_end

:start_end
echo.
pause
goto startupcleanup

:: =============================================================
::                  OLED CARE & PROTECTION
:: =============================================================
:oledcare
cls
call :log "OLED care menu accessed"
echo.
echo   +==============================================================+
echo   :            OLED DISPLAY CARE - Burn-in Protection            :
echo   +--------------------------------------------------------------+
echo   :  Your 15.6" Samsung OLED panel is stunning but needs care.   :
echo   :  OLED pixels degrade over time, especially with static       :
echo   :  content at high brightness. These settings help.            :
echo   +==============================================================+
echo.
echo   [1] Enable dark mode + dark wallpaper
echo       (Saves power AND reduces OLED wear on static UI elements)
echo.
echo   [2] Disable dark mode
echo       (Restore default light theme)
echo.
echo   [3] Auto-hide taskbar
echo       (Prevents taskbar burn-in - biggest OLED risk)
echo.
echo   [4] Show taskbar (undo auto-hide)
echo.
echo   [5] Set screen timeout to 2 minutes
echo       (Prevents static image burn when idle)
echo.
echo   [6] Set OLED brightness to safe level (70%%)
echo       (High brightness accelerates pixel degradation)
echo.
echo   [7] Enable pixel shift / screen saver
echo       (Moves pixels slightly to prevent burn-in)
echo.
echo   [8] Back to menu
echo.
set /p oledChoice="  Select (1-8): "

if "%oledChoice%"=="1" goto oled1
if "%oledChoice%"=="2" goto oled2
if "%oledChoice%"=="3" goto oled3
if "%oledChoice%"=="4" goto oled4
if "%oledChoice%"=="5" goto oled5
if "%oledChoice%"=="6" goto oled6
if "%oledChoice%"=="7" goto oled7
if "%oledChoice%"=="8" goto menu
goto oledcare

:oled1
echo.
echo   Enabling dark mode and solid black wallpaper...
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "AppsUseLightTheme" /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "SystemUsesLightTheme" /t REG_DWORD /d 0 /f >nul 2>&1
REM Set solid black wallpaper
powershell -NoProfile -Command ^
  "try { " ^
  "  Add-Type @' " ^
  "  using System; using System.Runtime.InteropServices; " ^
  "  public class WP { " ^
  "    [DllImport(\"user32.dll\", CharSet=CharSet.Auto)] " ^
  "    public static extern int SystemParametersInfo(int a, int b, string c, int d); " ^
  "  } " ^
  "'@ -ErrorAction SilentlyContinue; " ^
  "  [WP]::SystemParametersInfo(0x0014, 0, '', 0x0001) | Out-Null; " ^
  "  Write-Host '  Black wallpaper set (OLED pixels OFF = 0 power).'; " ^
  "} catch { }" >nul 2>&1
echo   Dark mode + black wallpaper enabled.
call :log "OLED: dark mode + black wallpaper"
goto oled_end

:oled2
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "AppsUseLightTheme" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v "SystemUsesLightTheme" /t REG_DWORD /d 1 /f >nul 2>&1
echo   Light mode restored.
call :log "OLED: light mode restored"
goto oled_end

:oled3
echo   Auto-hiding taskbar...
:: FIX-5: Use WM_SETTINGCHANGE broadcast instead of restarting explorer.exe.
:: This preserves all open File Explorer windows.
powershell -NoProfile -Command ^
  "$p = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'; " ^
  "if (Test-Path $p) { " ^
  "  $v = (Get-ItemProperty -Path $p).Settings; " ^
  "  $v[8] = 3; " ^
  "  Set-ItemProperty -Path $p -Name Settings -Value $v; " ^
  "  Add-Type @' " ^
  "  using System; using System.Runtime.InteropServices; " ^
  "  public class TaskbarRefresh { " ^
  "    [DllImport(\"user32.dll\", SetLastError=true)] " ^
  "    public static extern IntPtr SendNotifyMessage(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam); " ^
  "    public static void Refresh() { " ^
  "      SendNotifyMessage((IntPtr)0xFFFF, 0x001A, UIntPtr.Zero, \"TraySettings\"); " ^
  "    } " ^
  "  } " ^
  "'@ -ErrorAction SilentlyContinue; " ^
  "  [TaskbarRefresh]::Refresh(); " ^
  "  Write-Host '  Taskbar auto-hidden (no explorer restart).'; " ^
  "}" >nul 2>&1
echo   Taskbar set to auto-hide (reduces burn-in risk).
call :log "OLED: taskbar auto-hidden"
goto oled_end

:oled4
echo   Showing taskbar...
:: FIX-5: Use WM_SETTINGCHANGE broadcast instead of restarting explorer.exe.
powershell -NoProfile -Command ^
  "$p = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'; " ^
  "if (Test-Path $p) { " ^
  "  $v = (Get-ItemProperty -Path $p).Settings; " ^
  "  $v[8] = 2; " ^
  "  Set-ItemProperty -Path $p -Name Settings -Value $v; " ^
  "  Add-Type @' " ^
  "  using System; using System.Runtime.InteropServices; " ^
  "  public class TaskbarRefresh { " ^
  "    [DllImport(\"user32.dll\", SetLastError=true)] " ^
  "    public static extern IntPtr SendNotifyMessage(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam); " ^
  "    public static void Refresh() { " ^
  "      SendNotifyMessage((IntPtr)0xFFFF, 0x001A, UIntPtr.Zero, \"TraySettings\"); " ^
  "    } " ^
  "  } " ^
  "'@ -ErrorAction SilentlyContinue; " ^
  "  [TaskbarRefresh]::Refresh(); " ^
  "  Write-Host '  Taskbar restored (no explorer restart).'; " ^
  "}" >nul 2>&1
echo   Taskbar visible again.
call :log "OLED: taskbar shown"
goto oled_end

:oled5
powercfg /change monitor-timeout-dc 2
powercfg /change monitor-timeout-ac 2
echo   Screen turns off after 2 minutes (both AC and battery).
call :log "OLED: screen timeout 2min"
goto oled_end

:oled6
powershell -NoProfile -Command "(Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightnessMethods).WmiSetBrightness(1, 70)" >nul 2>&1
echo   OLED brightness set to 70%% (safe for daily use).
call :log "OLED: brightness 70%%"
goto oled_end

:oled7
echo   Enabling screen saver (blank screen after 5 min)...
reg add "HKCU\Control Panel\Desktop" /v "ScreenSaveActive" /t REG_SZ /d "1" /f >nul 2>&1
reg add "HKCU\Control Panel\Desktop" /v "ScreenSaveTimeOut" /t REG_SZ /d "300" /f >nul 2>&1
reg add "HKCU\Control Panel\Desktop" /v "SCRNSAVE.EXE" /t REG_SZ /d "C:\Windows\System32\scrnsave.scr" /f >nul 2>&1
echo   Blank screen saver enabled (5 min timeout).
echo   NOTE: True pixel shift requires ASUS Splendid or manufacturer tool.
call :log "OLED: screen saver enabled"
goto oled_end

:oled_end
echo.
pause
goto oledcare

:: =============================================================
::       ULTRA PERFORMANCE MODE (NVIDIA-preferred rendering)
:: =============================================================
:: NOTE: M3500QC uses Optimus (no MUX switch). The internal OLED
:: is wired to the AMD iGPU. Disabling the iGPU = black screen.
:: Instead we keep iGPU as display bridge and force ALL rendering
:: tasks to the RTX 3050 via NVIDIA driver settings.
:: =============================================================
:ultraperformance
cls
if not "!CURRENT_MODE!"=="ULTRAPERF" goto start_ultraperf
echo.
echo   [!] Ultra Performance is already active. Skipping re-activation.
echo.
call :log "Ultra Performance activation skipped (already active)"
pause
goto menu
:start_ultraperf

:: Battery safety check — Ultra Perf on battery gives only ~1h30m life
set "upBatStatus="
powershell -NoProfile -Command ^
  "$b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue; " ^
  "if ($b -and $b.BatteryStatus -ne 2) { [System.IO.File]::WriteAllText('%TEMP%\po_upbat.txt', 'BATTERY') } " ^
  "else { [System.IO.File]::WriteAllText('%TEMP%\po_upbat.txt', 'AC') }" >nul 2>&1
if exist "%TEMP%\po_upbat.txt" ( set /p upBatStatus=<"%TEMP%\po_upbat.txt" & del "%TEMP%\po_upbat.txt" >nul 2>&1 )

if not "!upBatStatus!"=="BATTERY" goto skip_up_battery_check
echo.
echo   +==============================================================+
echo   :  WARNING: You are ON BATTERY!                                :
echo   :  Ultra Performance drains battery in ~1h30m.                 :
echo   :  Battery health is degraded and heavy drain accelerates      :
echo   :  further degradation. Consider using Balanced [3] instead.   :
echo   +==============================================================+
echo.
set /p upConfirm="  Continue anyway? (y/n): "
if /i "!upConfirm!"=="y" goto up_confirmed
call :log "Ultra Performance cancelled (on battery, user declined)"
goto menu

:up_confirmed
call :log "WARNING: Ultra Performance activated ON BATTERY (user confirmed)"
:skip_up_battery_check

set "CURRENT_MODE=ULTRAPERF"
echo ULTRAPERF>"%~dp0.powermode.state"
call :log "=== ULTRA PERFORMANCE MODE (NVIDIA-PREFERRED) ACTIVATED ==="
echo.
echo   +==============================================================+
echo   :   Applying ULTRA Performance - NVIDIA RTX 3050 Rendering     :
echo   :   iGPU stays as display bridge (Optimus - no MUX switch)     :
echo   :   ALL rendering forced to RTX 3050                           :
echo   +==============================================================+
echo.

echo   [1/12] Enabling NVIDIA RTX 3050 + starting services...
powershell -NoProfile -Command ^
  "$gpu = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' -and $_.Class -eq 'Display' }; " ^
  "if ($gpu) { $gpu | Enable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue; Write-Host 'RTX 3050 enabled.' } " ^
  "else { Write-Host 'NVIDIA GPU not found.' }"
net start NVDisplay.ContainerLocalSystem >nul 2>&1
net start NvTelemetryContainer >nul 2>&1
call :log "RTX 3050 ENABLED + services started"

echo   [2/12] Forcing all apps to render on RTX 3050...
:: Set NVIDIA as the preferred GPU for all applications globally
:: The iGPU stays active as the display output bridge (Optimus)
:: but the RTX 3050 handles ALL rendering workloads
reg add "HKLM\SOFTWARE\Microsoft\DirectX\UserGpuPreferences" /v "DirectXUserGlobalSettings" /t REG_SZ /d "GpuPreference=2;" /f >nul 2>&1
:: NVIDIA Control Panel: Global setting = High-performance NVIDIA processor
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001" /v "EnableMsHybrid" /t REG_DWORD /d 2 /f >nul 2>&1
:: Set Windows Graphics preference to High Performance for common apps
powershell -NoProfile -Command ^
  "$apps = @('chrome.exe','msedge.exe','firefox.exe','brave.exe','explorer.exe','code.exe','devenv.exe'); " ^
  "foreach ($app in $apps) { " ^
  "  $path = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'; " ^
  "  if (!(Test-Path $path)) { New-Item -Path $path -Force | Out-Null }; " ^
  "  $exe = (Get-Command $app -ErrorAction SilentlyContinue).Source; " ^
  "  if ($exe) { Set-ItemProperty -Path $path -Name $exe -Value 'GpuPreference=2;' -Force -ErrorAction SilentlyContinue }; " ^
  "}; " ^
  "Write-Host 'All detected apps set to prefer NVIDIA RTX 3050.'" >nul 2>&1
call :log "All rendering forced to RTX 3050 (iGPU = display bridge only)"

echo   [3/12] Setting NVIDIA to Maximum Performance globally...
:: Force NVIDIA to always run at max clocks (no PowerMizer downclocking)
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001" /v "PerfLevelSrc" /t REG_DWORD /d 8738 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001" /v "PowerMizerEnable" /t REG_DWORD /d 1 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0001" /v "PowerMizerLevel" /t REG_DWORD /d 1 /f >nul 2>&1
:: Set NVIDIA global power mode to "Prefer Maximum Performance"
reg add "HKCU\SOFTWARE\NVIDIA Corporation\Global\NVTweak" /v "DisablePowerMizer" /t REG_DWORD /d 1 /f >nul 2>&1
call :log "NVIDIA set to Maximum Performance (PowerMizer disabled)"

echo   [4/12] Setting Power Plan to Ultimate Performance...
powercfg -setactive e9a42b02-d5df-448d-aa00-03f14749eb61 >nul 2>&1
if %errorlevel% neq 0 (
    powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 >nul 2>&1
    powercfg -setactive e9a42b02-d5df-448d-aa00-03f14749eb61 >nul 2>&1
    if !errorlevel! neq 0 (
        powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c >nul 2>&1
    )
)
call :log "Power plan set to Ultimate Performance"

echo   [5/12] Setting Windows Power Slider to Best Performance...
powercfg /SetActiveOverlay SCHEME_CURRENT ded574b5-45a0-4f42-8737-46345c09c238 >nul 2>&1

echo   [6/12] Unlocking Ryzen 5600H to maximum - Boost AGGRESSIVE...
:: CPU max to 100%% on both AC and DC
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1
:: CPU min to 100%% (force max clocks - no downclocking)
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 >nul 2>&1
:: Enable AMD Precision Boost Overdrive (Aggressive)
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 2 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 2 >nul 2>&1
:: All 12 threads active - zero core parking
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100 >nul 2>&1
:: AMD pstate driver: OS-controlled for max performance
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFAUTONOMOUS 0 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFAUTONOMOUS 0 >nul 2>&1
:: EPP: 0 = max performance (both AC and DC)
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 0 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 0 >nul 2>&1
call :log "Ryzen 5600H 100%% min+max, Boost Aggressive, EPP=0, 12T active, no parking"

echo   [7/12] OLED Display: max brightness, always on...
:: Screen never turns off
powercfg /change monitor-timeout-ac 0
powercfg /change monitor-timeout-dc 0
:: Never sleep
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
:: Disable hibernate
powercfg /change hibernate-timeout-ac 0
powercfg /change hibernate-timeout-dc 0
:: OLED brightness 85%% (100%% can cause faster degradation)
powershell -NoProfile -Command "(Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightnessMethods).WmiSetBrightness(1, 85)" >nul 2>&1
:: Disable adaptive brightness
powercfg /setacvalueindex SCHEME_CURRENT 7516b95f-f776-4464-8c53-06167f40cc99 fbd9aa66-9553-4097-ba44-ed6e9d65eab8 0 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT 7516b95f-f776-4464-8c53-06167f40cc99 fbd9aa66-9553-4097-ba44-ed6e9d65eab8 0 >nul 2>&1
call :log "OLED 85%%, always on, no sleep, no hibernate"

echo   [8/12] NVMe SSD: maximum throughput...
:: Disable all NVMe power saving
powercfg /setacvalueindex SCHEME_CURRENT SUB_DISK dbc9e238-6de9-49e3-92cd-8c2b4946b472 0 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_DISK dbc9e238-6de9-49e3-92cd-8c2b4946b472 0 >nul 2>&1
:: Set max latency tolerance (no delay)
powercfg /setacvalueindex SCHEME_CURRENT SUB_DISK fc95af4d-40e7-4b6d-835a-56d131dbc80e 0 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_DISK fc95af4d-40e7-4b6d-835a-56d131dbc80e 0 >nul 2>&1
:: FIX-4: SATA AHCI Link PM GUID removed (NVMe-only machine)
call :log "NVMe SSD: max throughput, no PM, no sleep states"

echo   [9/12] USB, PCIe, Wi-Fi: maximum performance (all power states)...
:: Disable USB selective suspend on both AC and DC
powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 >nul 2>&1
:: PCIe Link State PM OFF (critical - RTX 3050 is on x8 PCIe lane)
powercfg /setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a8218c268e20 ee12f906-d277-404b-b6da-e5fa1a576df5 0 >nul 2>&1
:: Wi-Fi: Maximum Performance
powercfg /setacvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT 19cbb8fa-5279-450e-9fac-8a3d5fedd0c1 12bbebe6-58d6-4636-95bb-3217ef867c1a 0 >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1
call :log "USB always on, PCIe no PM (both AC/DC), Wi-Fi max perf"

echo   [10/12] Re-enabling all background services...
net start WSearch >nul 2>&1
net start wuauserv >nul 2>&1
net start SysMain >nul 2>&1
net start DiagTrack >nul 2>&1
net start Spooler >nul 2>&1
net start BITS >nul 2>&1
net start WbioSrvc >nul 2>&1
net start NVDisplay.ContainerLocalSystem >nul 2>&1
net start NvTelemetryContainer >nul 2>&1
:: FIX-1: Restore MongoDB to auto start (was set to demand in saver/PSB modes)
sc config MongoDB start= auto >nul 2>&1
call :log "All services started (including NVIDIA, MongoDB auto-start)"

:: Re-enable all scheduled tasks
schtasks /change /tn "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Autochk\Proxy" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem" /enable >nul 2>&1
schtasks /change /tn "\Microsoft\Windows\Windows Error Reporting\QueueReporting" /enable >nul 2>&1
schtasks /change /tn "\NvTmMon_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}" /enable >nul 2>&1
schtasks /change /tn "\NvTmRep_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}" /enable >nul 2>&1
schtasks /change /tn "\NVIDIA GeForce Experience SelfUpdate_{B2FE1952-0186-46C3-BAEC-A80AA35AC5B8}" /enable >nul 2>&1
call :log "All scheduled tasks re-enabled (including NVIDIA)"

echo   [11/12] Disabling Windows Energy Saver...
powercfg /setdcvalueindex SCHEME_CURRENT e73a048d-bf27-4f12-9731-8b2076e8891f 637ea02f-bbcb-4015-8e2c-a1c7b9c0b546 0 >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power" /v "EnergySaverEnabled" /t REG_DWORD /d 0 /f >nul 2>&1
powershell -NoProfile -Command ^
  "try { " ^
  "  $s = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GlobalSettings\EnergySaver'; " ^
  "  if (Test-Path $s) { " ^
  "    Set-ItemProperty -Path $s -Name 'EnergySaverEnabled' -Value 0 -Type DWord -Force; " ^
  "    Set-ItemProperty -Path $s -Name 'BatterySaverEnabled' -Value 0 -Type DWord -Force; " ^
  "  } " ^
  "} catch { }; " ^
  "try { " ^
  "  $p = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\EnergySaver\Parameters'; " ^
  "  if (Test-Path $p) { " ^
  "    Set-ItemProperty -Path $p -Name 'BatterySaverBatteryThreshold' -Value 0 -Type DWord -Force; " ^
  "    Set-ItemProperty -Path $p -Name 'BatterySaverEnabled' -Value 0 -Type DWord -Force; " ^
  "  } " ^
  "} catch { }" >nul 2>&1
call :log "Energy Saver completely disabled"

echo   [12/12] Setting video playback to max quality...
powercfg /setacvalueindex SCHEME_CURRENT 9596fb26-9850-41fd-ac3e-f7c3c00afd4b 34c7b151-7bf6-4e87-b075-e0f5f5899773 0 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT 9596fb26-9850-41fd-ac3e-f7c3c00afd4b 34c7b151-7bf6-4e87-b075-e0f5f5899773 0 >nul 2>&1
powercfg /setactive SCHEME_CURRENT >nul 2>&1
call :log "Video playback set to max quality"

echo.
echo   +==============================================================+
echo   :    ULTRA PERFORMANCE (NVIDIA-preferred) is now ON!           :
echo   +--------------------------------------------------------------+
echo   :  RTX 3050:    ALL rendering / Max Performance / No throttle  :
echo   :  AMD iGPU:    Active as display bridge (Optimus, safe)       :
echo   :  NVIDIA PowerMizer: DISABLED (max clocks always)             :
echo   :  GPU Preference: High-performance (all apps use RTX 3050)    :
echo   :  Ryzen 5600H: 100%% min+max / Boost AGGRESSIVE / 12T active  :
echo   :  Core Parking: NONE / EPP: 0 (max perf on AC+DC)             :
echo   :  OLED:        85%% brightness / Always on / No sleep          :
echo   :  NVMe SSD:    Max throughput / APST OFF / Link PM OFF         :
echo   :  PCIe:        Link PM OFF (full bandwidth to RTX 3050)        :
echo   :  Wi-Fi:       Max performance / USB: Always powered           :
echo   :  Services:    All running + NVIDIA fully active               :
echo   :  Energy Saver: OFF / Video: Max quality                       :
echo   +--------------------------------------------------------------+
echo   :  WARNING: This mode uses maximum power. Keep laptop plugged   :
echo   :  in! Battery will drain FAST if unplugged.                    :
echo   :  To restore defaults: use Balanced [3] or Battery Saver [1]   :
echo   +==============================================================+
echo.
echo   Log: %LOGFILE%
echo.
pause
goto menu

:: =============================================================
::         QUICK RE-APPLY (after wake from sleep)
:: =============================================================
:reapply
cls
:: FIX-7b: Lockfile mechanism to prevent duplicate cmd windows.
:: All 3 wake tasks (S3, Modern Standby, Unlock) can fire simultaneously,
:: each launching a separate cmd.exe instance. Only the first one should run.
set "LOCKFILE=%~dp0.reapply.lock"
set "_lockFresh=0"
if exist "!LOCKFILE!" (
    :: Check if lockfile is stale (older than 120 seconds = safety net)
    powershell -NoProfile -Command ^
      "$f = '%LOCKFILE%'; if ((Test-Path $f) -and ((Get-Date) - (Get-Item $f).LastWriteTime).TotalSeconds -lt 120) { exit 0 } else { exit 1 }" >nul 2>&1
    if !errorlevel! equ 0 set "_lockFresh=1"
)
if "!_lockFresh!"=="1" goto reapply_locked
goto reapply_proceed_lock
:reapply_locked
call :log "Re-apply skipped: another instance is already running (lockfile)"
exit /b
:reapply_proceed_lock
:: Create the lockfile — we are the first instance
echo %date% %time%>"%LOCKFILE%"
:: FIX-12: Log AFTER lockfile check to prevent duplicate log entries.
call :log "=== QUICK RE-APPLY AFTER WAKE ==="
echo.
echo   +==============================================================+
echo   :      Quick Re-apply - Fixing post-wake power settings        :
echo   +==============================================================+
echo.

:: ---- Detect power source before applying ----
set "wakeSource=BATTERY"
powershell -NoProfile -Command ^
  "$bs = (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue).BatteryStatus; " ^
  "if ($bs -eq 2) { [System.IO.File]::WriteAllText('%TEMP%\wakesrc.txt', 'CHARGING') } " ^
  "else { [System.IO.File]::WriteAllText('%TEMP%\wakesrc.txt', 'BATTERY') }" >nul 2>&1
if exist "%TEMP%\wakesrc.txt" (
    set /p wakeSource=<"%TEMP%\wakesrc.txt"
    del "%TEMP%\wakesrc.txt" >nul 2>&1
)

if not "!wakeSource!"=="CHARGING" goto proceed_reapply
if "!SILENT_MODE!"=="0" echo   Detected: PLUGGED IN after wake.
if "!SILENT_MODE!"=="0" echo   Skipping battery saver re-apply. Use menu option 2 or 3 instead.
call :log "Re-apply skipped: system is on AC power"
:: Clean up lockfile on AC early-exit — without this the lock stays stale
:: and could incorrectly block the next wake re-apply within 120 seconds.
if defined LOCKFILE if exist "!LOCKFILE!" del /f /q "!LOCKFILE!" >nul 2>&1
:: FIX-16: Silent exit when invoked from scheduled task (no pause, no menu)
if "!SILENT_MODE!"=="1" exit
echo.
pause
goto menu
:proceed_reapply

:: ---- Detect which mode to re-apply ----
:: Default to Ultra Saver if no mode is set (script was restarted)
if not defined CURRENT_MODE set "CURRENT_MODE=SAVER"
echo !CURRENT_MODE!>"%~dp0.powermode.state"

:: Show which mode we're re-applying
if "!CURRENT_MODE!"=="PSBALANCED" (
    echo   Detected: ON BATTERY - re-applying POWER SAVING BALANCED settings.
) else (
    echo   Detected: ON BATTERY - re-applying ULTRA SAVER settings.
)
echo.
echo   This fixes settings that Windows resets after sleep/wake:
echo   - Processes that restarted during sleep
echo   - Timer resolution fixes (Edge/MongoDB)
echo   - CPU throttle + boost settings
echo   - Brightness reset
echo.

echo   [1/6] Re-killing power-hungry processes...
:: PowerToys.Awake blocks sleep (energy report finding)
taskkill /IM "PowerToys.Awake.exe" /F /T >nul 2>&1
taskkill /FI "IMAGENAME eq PowerToys.exe" /F /T >nul 2>&1
taskkill /FI "IMAGENAME eq PowerToys.Settings.exe" /F /T >nul 2>&1
taskkill /FI "IMAGENAME eq PowerToys.PowerLauncher.exe" /F /T >nul 2>&1
taskkill /IM OneDrive.exe /F /T >nul 2>&1
taskkill /IM steam.exe /F /T >nul 2>&1
taskkill /IM steamwebhelper.exe /F /T >nul 2>&1
taskkill /IM discord.exe /F /T >nul 2>&1
taskkill /IM Spotify.exe /F /T >nul 2>&1
taskkill /IM Teams.exe /F /T >nul 2>&1
taskkill /IM ms-teams.exe /F /T >nul 2>&1
taskkill /IM Widgets.exe /F /T >nul 2>&1
net stop MongoDB >nul 2>&1
taskkill /IM mongod.exe /F /T >nul 2>&1
taskkill /IM msedge.exe /F >nul 2>&1
taskkill /IM msedgewebview2.exe /F >nul 2>&1
:: MoUsoCoreWorker blocks sleep (energy report finding)
taskkill /IM MoUsoCoreWorker.exe /F /T >nul 2>&1
net stop UsoSvc >nul 2>&1
:: NVIDIA background (may restart after wake)
taskkill /IM "NVDisplay.Container.exe" /F /T >nul 2>&1
taskkill /IM "NVIDIA Share.exe" /F /T >nul 2>&1
taskkill /IM "nvcontainer.exe" /F /T >nul 2>&1
net stop NVDisplay.ContainerLocalSystem >nul 2>&1
:: Antigravity.exe (execution-required request per energy report)
taskkill /IM "Antigravity.exe" /F /T >nul 2>&1
:: FIX-8: Kill Antigravity's language server (energy report: ~1%% combined CPU)
taskkill /IM "language_server_windows_x64.exe" /F >nul 2>&1
call :log "Re-killed processes after wake (on battery, incl. Antigravity + LSP)"

:: ---- Mode-aware CPU + brightness settings ----
:: BUG-18 FIX: Previously hardcoded Ultra Saver values (40%/EPP 100/brightness 25%)
:: which would silently break PSB mode after wake. Now branches on CURRENT_MODE.
if "!CURRENT_MODE!"=="PSBALANCED" goto reapply_psb_cpu
goto reapply_saver_cpu

:reapply_psb_cpu
echo   [2/6] Re-applying PSB CPU settings (100%% max, Boost Efficient, EPP 50)...
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 4 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 25 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 50 >nul 2>&1
call :log "PSB CPU re-applied: 100%% max, Boost Efficient, EPP=50"
goto reapply_brightness

:reapply_saver_cpu
echo   [2/6] Re-applying Ultra Saver CPU throttle (40%% cap, Boost OFF, EPP 100)...
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 40 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 0 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 5 >nul 2>&1
powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 100 >nul 2>&1
call :log "Saver CPU re-applied: 40%% max, Boost OFF, EPP=100"
goto reapply_brightness

:reapply_brightness
:: ---- Mode-aware brightness ----
if "!CURRENT_MODE!"=="PSBALANCED" goto reapply_psb_bright
goto reapply_saver_bright

:reapply_psb_bright
echo   [3/6] Re-setting OLED brightness to 50%% (PSB mode)...
powershell -NoProfile -Command "(Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightnessMethods).WmiSetBrightness(1, 50)" >nul 2>&1
call :log "Brightness re-set to 50%% (PSB mode)"
goto reapply_services

:reapply_saver_bright
echo   [3/6] Re-setting OLED brightness to 25%% (Ultra Saver)...
powershell -NoProfile -Command "(Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightnessMethods).WmiSetBrightness(1, 25)" >nul 2>&1
call :log "Brightness re-set to 25%% (Saver mode)"
goto reapply_services

:reapply_services
echo   [4/6] Re-disabling services that auto-restarted...
net stop WSearch >nul 2>&1
net stop SysMain >nul 2>&1
net stop DiagTrack >nul 2>&1
net stop NVDisplay.ContainerLocalSystem >nul 2>&1
call :log "Services re-stopped"

echo   [5/6] Verifying RTX 3050 is still disabled...
powershell -NoProfile -Command ^
  "$gpu = Get-PnpDevice | Where-Object { $_.FriendlyName -like '*NVIDIA*' -and $_.Class -eq 'Display' }; " ^
  "if ($gpu -and $gpu.Status -eq 'OK') { " ^
  "  $gpu | Disable-PnpDevice -Confirm:$false -ErrorAction SilentlyContinue; " ^
  "  Write-Host '  RTX 3050 was re-enabled by Windows - DISABLED again.'; " ^
  "} else { Write-Host '  RTX 3050 still disabled. Good.' }"
call :log "GPU check after wake"

echo   [6/6] Re-applying power plan settings...
powercfg /setactive SCHEME_CURRENT >nul 2>&1
call :log "Power plan re-applied"

:: ---- Mode-aware completion banner ----
echo.
if "!CURRENT_MODE!"=="PSBALANCED" (
    echo   +==============================================================+
    echo   :       Quick Re-apply Complete! [PSB MODE]                    :
    echo   :       CPU 100%% / Boost Efficient / EPP 50 / OLED 50%%       :
    echo   +==============================================================+
) else (
    echo   +==============================================================+
    echo   :       Quick Re-apply Complete! [ULTRA SAVER MODE]            :
    echo   :       CPU 40%% / Boost OFF / EPP 100 / OLED 25%%              :
    echo   +==============================================================+
)
echo.
:: Clean up lockfile — this re-apply instance is done
if defined LOCKFILE if exist "!LOCKFILE!" del /f /q "!LOCKFILE!" >nul 2>&1
:: FIX-16: Silent exit when invoked from scheduled task (no pause, no menu)
if "!SILENT_MODE!"=="1" exit
pause
goto menu

:: =============================================================
::                  EXIT
:: =============================================================
:exitscript
call :log "Script exited"
echo.
echo   Goodbye!
timeout /t 1 >nul
exit
