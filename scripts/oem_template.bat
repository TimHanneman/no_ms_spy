@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM ==========================================================================
REM  oem_template.bat
REM  Template for a partner/OEM privacy script run by no_ms_spy.bat.
REM
REM  To use it:
REM    1. Copy it into the scripts\oem folder, for example
REM       scripts\oem\nvidia.bat. Only files in that folder are run.
REM    2. Add OEM_SCRIPT=nvidia.bat to config\no_ms_spy.cfg.
REM    3. Install with I in no_ms_spy.bat. Partner scripts only run from
REM       the installed copy in Program Files, or from a recovery disk.
REM
REM  no_ms_spy.bat runs it as "name.bat apply" or "name.bat restore", with
REM  administrator rights, and treats a non-zero exit code as a failure.
REM  "apply" runs on every Apply and "restore" on R, W and U, so both must
REM  be safe to run again on a PC where they already ran.
REM
REM  Variables passed in from no_ms_spy.bat. Use them instead of fixed
REM  paths so the script also works on an offline installation:
REM    %SW%       instead of HKLM\SOFTWARE
REM    %SYS%      instead of HKLM\SYSTEM\CurrentControlSet
REM    %CU%       instead of HKCU
REM    %REG%      full path of reg.exe; also %SC% and %SCHTASKS%
REM    %OFFLINE%  defined when the target Windows is not running. sc and
REM               schtasks do not work then; write the service Start value
REM               under %SYS%\Services\name instead (4 = disabled).
REM ==========================================================================

REM Stop if not started by no_ms_spy.bat, so the paths above are set.
if not defined SW (
    Echo Run this script through no_ms_spy.bat.
    exit /b 1
)

if /i "%~1"=="apply" goto apply
if /i "%~1"=="restore" goto restore
Echo Usage: %~nx0 apply or restore
exit /b 1


:apply
REM Example: disable a vendor telemetry service, online or offline. A
REM missing service is skipped, not counted as a failure. Note the start
REM type it had before (reg query ...\Services\name /v Start) and use that
REM value in :restore; 2 = automatic, 3 = manual.
REM %REG% QUERY "%SYS%\Services\VendorTelemetryService" >nul 2>&1
REM if errorlevel 1 exit /b 0
REM if defined OFFLINE (
REM     %REG% ADD "%SYS%\Services\VendorTelemetryService" /v Start /t REG_DWORD /d 4 /f >nul
REM ) else (
REM     %SC% stop "VendorTelemetryService" >nul 2>&1
REM     %SC% config "VendorTelemetryService" start= disabled >nul
REM )
REM if errorlevel 1 exit /b 1

REM Example: disable a vendor scheduled task. Only possible online.
REM if not defined OFFLINE %SCHTASKS% /Change /TN "\Vendor\UsageReport" /Disable >nul

REM Example: a vendor policy value.
REM %REG% ADD "%SW%\Policies\Vendor\App" /v SendUsageData /t REG_DWORD /d 0 /f >nul
exit /b 0


:restore
REM Undo everything done in :apply. Use the start type the service had
REM before :apply, not a guess.
REM %REG% QUERY "%SYS%\Services\VendorTelemetryService" >nul 2>&1
REM if errorlevel 1 exit /b 0
REM if defined OFFLINE (
REM     %REG% ADD "%SYS%\Services\VendorTelemetryService" /v Start /t REG_DWORD /d 2 /f >nul
REM ) else (
REM     %SC% config "VendorTelemetryService" start= auto >nul
REM )
REM if not defined OFFLINE %SCHTASKS% /Change /TN "\Vendor\UsageReport" /Enable >nul
REM %REG% DELETE "%SW%\Policies\Vendor\App" /v SendUsageData /f >nul 2>&1
exit /b 0
