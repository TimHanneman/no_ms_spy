@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM ==========================================================================
REM  no_ms_spy_main.bat
REM  Started by no_ms_spy.bat, the launcher in the folder above this one.
REM  Disable Windows telemetry and privacy-invasive defaults, and put them
REM  back. Only settings that exist on the detected Windows build are used.
REM
REM  Supports: Windows 7, 8/8.1, 10, 11.  Must be run as Administrator.
REM
REM  Install (I on the main menu):
REM    Copies the launcher and the scripts folder to Program Files\no_ms_spy,
REM    where only administrators can change them. An install made before the
REM    folder layout is moved into it, keeping this PC's saved values. Partner/OEM scripts and the
REM    connectivity check rotation only run from the installed copy.
REM
REM  Configuration, config\no_ms_spy.cfg:
REM    NAME=1 applies the privacy setting. NAME=0 puts back the value that
REM    was there before this script changed it, or leaves it alone if the
REM    script never changed it.
REM    ORIG= lines hold those earlier values. They are written by the script.
REM    TIMEZONE, NCSI_ROTATE_HOURS, NCSI_DNS_HOST and NCSI_DNS_IP are
REM    optional text values. OEM_SCRIPT=name.bat can be repeated; the file
REM    must be in the scripts\oem folder.
REM    Lines with any of these characters are rejected: & | < > ^ % ! ( ) "
REM
REM  Profiles (P on the main menu):
REM    Work, Home (the default) and Maximum, from least to most privacy,
REM    each set every selection at once. C adjusts them afterwards. See
REM    :set_profile.
REM
REM  Managed PCs:
REM    On a PC joined to a domain or Entra ID, or enrolled in Intune or
REM    another MDM, the script warns once before changing anything. The
REM    user can continue.
REM
REM  Uninstall (U on the main menu):
REM    Puts back every value the script saved, removes its scheduled tasks
REM    and event log source, and then the launcher deletes the install
REM    folder. Nothing is deleted if any value could not be put back.
REM
REM  Offline mode (V, Advanced):
REM    Run this script from another Windows such as Hiren's BootCD PE to
REM    change or put back settings on an installation that will not boot.
REM
REM  Reapply at sign-in (V, Advanced):
REM    A scheduled task runs the installed copy as "no_ms_spy.bat reapply"
REM    at each sign-in of the account that set it up, and applies the saved
REM    configuration again without prompts. R and W remove the task.
REM
REM  Folder layout, the same installed and on a recovery disk:
REM    no_ms_spy.bat                 launcher - start this one
REM    scripts\no_ms_spy_main.bat    this script
REM    scripts\ncsi_rotate.ps1       connectivity check rotation
REM    scripts\oem_template.bat      template for partner scripts
REM    scripts\oem\                  partner and OEM scripts
REM    config\no_ms_spy.cfg          saved selections and earlier values
REM    config\ncsi_state.txt         rotation state, and pending signal files
REM    logs\no_ms_spy.log            this script's log
REM    logs\ncsi_rotate.log          the rotation's log
REM
REM  Note: HKCU settings apply to the account the script runs under. If you
REM  elevate with a different admin account, run it from the target account.
REM ==========================================================================

REM A 32-bit cmd on 64-bit Windows sees a redirected registry and Program
REM Files folder, so policies would land in the wrong place. Relaunch with
REM the native 64-bit cmd.
if not defined PROCESSOR_ARCHITEW6432 goto native_cmd
"%SystemRoot%\Sysnative\cmd.exe" /c ""%~f0" %*"
exit /b %errorlevel%
:native_cmd

REM "reapply" is passed by the reapply-at-sign-in task: the saved
REM configuration is applied without menus, prompts or pauses.
set "UNATTENDED="
if /i "%~1"=="reapply" set "UNATTENDED=1"

REM Call system tools by full path and work from System32, so a program with
REM the same name in the current folder or in PATH is never run.
set "SYS32=%SystemRoot%\System32"
cd /d "%SYS32%"
set "REG=%SYS32%\reg.exe"
set "SC=%SYS32%\sc.exe"
set "FINDSTR=%SYS32%\findstr.exe"
set "FIND=%SYS32%\find.exe"
set "SCHTASKS=%SYS32%\schtasks.exe"
set "TZUTIL=%SYS32%\tzutil.exe"
set "TASKKILL=%SYS32%\taskkill.exe"
set "FLTMC=%SYS32%\fltmc.exe"
set "ICACLS=%SYS32%\icacls.exe"
set "XCOPY=%SYS32%\xcopy.exe"
set "CERTUTIL=%SYS32%\certutil.exe"
set "EVENTCREATE=%SYS32%\eventcreate.exe"
set "MSG=%SYS32%\msg.exe"
set "PING=%SYS32%\PING.EXE"
set "MORE=%SYS32%\more.com"
set "CMD=%SYS32%\cmd.exe"
set "POWERSHELL=%SYS32%\WindowsPowerShell\v1.0\powershell.exe"
set "DISM=%SYS32%\dism.exe"

set "VERSION=2026.09.29"
Title Disable Windows Spy Services %VERSION%.
color 0a
set "FAILS=0"
set "SAVE_FAILED="
set "SAVE_NEEDED="
set "CURRENT_SETTING="
set "NCSI_TASK=no_ms_spy\NCSI rotate"
set "REAPPLY_TASK=no_ms_spy\Reapply at sign-in"
set INSTALL_FILES="no_ms_spy.bat" "scripts\no_ms_spy_main.bat" "scripts\ncsi_rotate.ps1" "scripts\oem_template.bat"

REM This script is in the scripts folder. ROOT_DIR is the folder above it,
REM which holds the launcher and the config and logs folders.
set "SCRIPT_DIR=%~dp0"
for %%D in ("%~dp0..") do set "ROOT_DIR=%%~fD\"
call :check_safe SCRIPT_DIR
if errorlevel 1 (
    color 0c
    Echo This script's folder path contains a character cmd treats as code:
    Echo one of  and  or  pipe  less  greater  caret  percent  exclamation
    Echo parentheses or a quote. Move the script to a simpler folder path.
    if not defined UNATTENDED pause
    goto end
)
set "CONFIG_DIR=%ROOT_DIR%config"
set "LOG_DIR=%ROOT_DIR%logs"
set "CONFIG=%CONFIG_DIR%\no_ms_spy.cfg"
set "LOG_FILE=%LOG_DIR%\no_ms_spy.log"
set "OEM_DIR=%SCRIPT_DIR%oem"

call :require_admin
if errorlevel 1 goto end

REM The config and logs folders are created on first use. On a read-only
REM recovery disk this fails quietly and nothing is saved.
for %%D in ("%CONFIG_DIR%" "%LOG_DIR%") do if not exist "%%~D\" mkdir "%%~D" 2>nul

REM reg.exe's error text goes here, so a failure in the log says why. Where
REM the logs folder cannot be written, the Windows temp folder is used.
set "ERR_FILE=%LOG_DIR%\last_error.txt"
(call ) 2>nul >"%ERR_FILE%" || set "ERR_FILE=%SystemRoot%\Temp\no_ms_spy_error.txt"

REM MiniNT only exists in Windows PE based recovery environments.
set "IN_PE="
%REG% QUERY "HKLM\SYSTEM\CurrentControlSet\Control\MiniNT" >nul 2>&1
if not errorlevel 1 set "IN_PE=1"

call :find_install_dir
call :use_running_windows

call :detect_windows
if errorlevel 1 goto end

call :define_settings
call :define_allowed
call :load_config
if errorlevel 1 (
    if not defined UNATTENDED pause
    goto end
)
call :trim_log
call :log INFO "Version %VERSION% started from %ROOT_DIR% on %OS_NAME% build %BUILD%, edition %EDITION%"
call :update_rotation_tasks
call :update_reapply_task

if defined UNATTENDED goto reapply
if defined TRUSTED goto menu


:trust_warning
cls
color 0e
Echo WARNING: this copy runs from %ROOT_DIR%
Echo.
Echo Other programs on this PC may be able to change files in that folder,
Echo and those changes would run with administrator rights. Install it to
Echo %INSTALL_DIR%, which only administrators can change,
Echo and run it from there.
Echo.
Echo   I  Install and start the installed copy - recommended
Echo   C  Continue from here - partner scripts and connectivity rotation stay off
Echo   X  Exit
Echo.
call :prompt_key ICX "Select an option [I,C,X]: "
if /i "%KEY%"=="I" goto install
if /i "%KEY%"=="C" goto menu
goto end


:menu
cls
color 0a
if defined OFFLINE Echo Target: offline Windows on %TARGET%, user %TARGET_USER%
if not defined OFFLINE Echo Target: this running Windows
Echo no_ms_spy %VERSION%
Echo Detected: %OS_NAME%, build %BUILD%, edition %EDITION%
if defined INSTALLED Echo Running the installed copy.
if not defined TRUSTED Echo Running an uninstalled copy - partner scripts and rotation are off.
if defined CONFIG_FOUND Echo Using saved configuration: %CONFIG%
if not defined CONFIG_FOUND Echo No saved configuration found. The Home profile will be used.
if defined PROFILE Echo Profile: %PROFILE%
if defined IN_PE if not defined OFFLINE Echo Recovery environment: select an offline Windows under V first.
Echo.
Echo   A  Apply settings
Echo   P  Pick a profile: Work, Home or Maximum - least to most privacy
Echo   C  Choose settings one by one and save them
Echo   R  Put back the settings from before this script
Echo   W  Reset every setting to the Windows default
Echo   S  Show current status
Echo   I  Install to Program Files
Echo   U  Uninstall: put everything back and remove the installed copy
Echo   V  Advanced options
Echo   X  Exit
Echo.
call :prompt_key APCRWSIUVX "Select an option [A,P,C,R,W,S,I,U,V,X]: "
if /i "%KEY%"=="A" goto apply
if /i "%KEY%"=="P" goto pick_profile
if /i "%KEY%"=="C" goto choose
if /i "%KEY%"=="R" goto restore_originals
if /i "%KEY%"=="W" goto windows_defaults
if /i "%KEY%"=="S" goto status
if /i "%KEY%"=="I" goto install
if /i "%KEY%"=="U" goto uninstall
if /i "%KEY%"=="V" goto advanced
if /i "%KEY%"=="X" goto end
goto menu


REM ==========================================================================
REM  Setting list
REM  call :define NAME  MINIMUM_BUILD  DEFAULT  "Description"
REM  Each NAME needs an :apply_NAME section, and a :restore_NAME section
REM  that sets the Windows default (used by W).
REM  :define_advanced settings are only offered in the Advanced menu.
REM  Builds: 7600 = Win 7, 9200 = Win 8, 9600 = Win 8.1, 10240 = Win 10,
REM          22000 = Win 11
REM ==========================================================================

:define_settings
set "SETTINGS="
REM            NAME                  BUILD DEFAULT DESCRIPTION
call :define TELEMETRY             7600  1 "Turn off diagnostic data and CEIP tasks - may delay feature upgrade offers"
call :define PUSH_SERVICE          10240 1 "Disable the WAP push service - skipped on Intune-managed PCs"
call :define ADVERTISING_ID        9600  1 "Turn off the advertising ID"
call :define TAILORED_EXPERIENCES  15063 1 "Turn off tailored experiences based on diagnostic data"
call :define ACTIVITY_HISTORY      17134 1 "Turn off activity history"
call :define WEB_SEARCH            10240 1 "Turn off web and Bing results in Start search"
call :define SUGGESTED_CONTENT     10240 1 "Turn off suggestions, Spotlight and silent app installs"
call :define LANGUAGE_LIST         9600  1 "Stop websites from reading your language list"
call :define INPUT_PERSONALIZATION 9200  1 "Turn off inking and typing personalization - voice typing stops working"
call :define ONLINE_SPEECH         17134 1 "Turn off online speech recognition - voice typing stops working"
call :define HANDWRITING_SHARING   7600  1 "Turn off handwriting data sharing and error reports"
call :define LOCATION              7600  1 "Turn off location and automatic time zone - set the zone by hand when traveling"
call :define CALL_HISTORY          10240 1 "Block app access to call history"
call :define PHONE_LINK            17763 0 "Turn off Phone Link - stops phone calls and texts syncing to the PC"
call :define FIND_MY_DEVICE        16299 1 "Turn off Find My Device - a lost PC cannot be located or locked"
call :define CLIPBOARD_HISTORY     17763 1 "Turn off clipboard history"
call :define CLIPBOARD_SYNC        17763 1 "Turn off clipboard sync across devices"
call :define ERROR_REPORTING       7600  1 "Turn off Windows Error Reporting - crashes are harder to diagnose"
call :define CLOUD_SEARCH          10240 1 "Turn off cloud content in search"
call :define SEARCH_HIGHLIGHTS     19041 1 "Turn off search highlights"
call :define APP_LAUNCH_TRACKING   7600  1 "Turn off app launch tracking - also clears Run dialog history"
call :define RECENT_FILES          7600  1 "Turn off recent file tracking - also empties Jump Lists"
call :define START_RECOMMENDATIONS 22621 1 "Turn off Start menu recommendations"
call :define WIDGETS               19041 1 "Turn off widgets and the news feed"
call :define SETTINGS_SYNC         9600  1 "Turn off settings sync"
call :define DELIVERY_OPTIMIZATION 10240 1 "Limit update sharing to PCs on the local network"
call :define EDGE_DIAGNOSTICS      10240 1 "Turn off Edge diagnostic data"
call :define RECALL                26100 1 "Turn off Recall and remove it - restart to finish"
call :define OFFICE_TELEMETRY      7600  1 "Turn off Office diagnostic data and feedback prompts"
call :define OFFICE_CONNECTED      7600  1 "Turn off Office optional connected experiences"
call :define DEV_TOOLS_TELEMETRY   7600  1 "Turn off .NET CLI, PowerShell 7 and Visual Studio telemetry"
call :define ONEDRIVE_REMOVE       7600  0 "Uninstall OneDrive and block it - cannot be undone by this script"
call :define COPILOT_REMOVE        10240 0 "Uninstall the Copilot app - cannot be undone by this script"
call :define OUTLOOK_REMOVE        10240 0 "Remove the new Outlook app and block its reinstall - cannot be undone by this script"
call :define CONNECTIVITY_CHECK    10240 0 "Rotate the connectivity check between providers - needs the installed copy"
call :define UPDATE_NOTIFY         10240 0 "Ask before Windows Update downloads - updates wait until you approve them"
call :define ACTIVATION_VALIDATION 9200  0 "Turn off KMS client online validation - activation still works"
call :define DEFENDER_CLOUD        7600  0 "Turn off Defender cloud protection - weakens security"
call :define DEFENDER_SAMPLES      7600  0 "Ask before Defender uploads any file sample"
call :define SMARTSCREEN           7600  0 "Turn off SmartScreen - weakens phishing protection"

REM Advanced: local network chatter. The defaults match the Home profile.
call :define_advanced LLMNR              7600  1 "Turn off LLMNR name broadcasts"
call :define_advanced NETBIOS            7600  0 "Turn off NetBIOS over TCP/IP on current adapters"
call :define_advanced MDNS               15063 0 "Turn off mDNS"
call :define_advanced SSDP_UPNP          7600  0 "Turn off SSDP and UPnP device discovery"
call :define_advanced NETWORK_PUBLISHING 7600  1 "Stop publishing this PC on the network"
call :define_advanced LLTD               7600  1 "Turn off Link Layer Topology Discovery"
call :define_advanced TEREDO             7600  0 "Turn off Teredo IPv6 tunneling"

REM Single text values and repeatable list values stored in the config.
set "TEXT_KEYS=PROFILE TIMEZONE NCSI_ROTATE_HOURS NCSI_DNS_HOST NCSI_DNS_IP"
set "LIST_KEYS=OEM_SCRIPT"
exit /b 0


:define
REM %1 = name, %2 = minimum build, %3 = default 1 or 0, %4 = description.
set "SETTINGS=%SETTINGS% %~1"
set "MIN_%~1=%~2"
set "OPT_%~1=%~3"
set "DESC_%~1=%~4"
exit /b 0


:define_advanced
call :define %1 %2 %3 %4
set "ADV_%~1=1"
exit /b 0


:define_allowed
REM Registry locations whose earlier values may be put back. A saved value
REM anywhere else is ignored, so an edited config cannot use a put-back to
REM write other registry values such as a service path or a Run key.
REM Entries end in ; when only that exact key is allowed.
set "CUP=CU@%CU_USER%"
set "CV=%CUP%\SOFTWARE\Microsoft\Windows\CurrentVersion"
set ALLOWED_REG="SW\Policies\" "%CUP%\SOFTWARE\Policies\"
set ALLOWED_REG=%ALLOWED_REG% "%CV%\AdvertisingInfo;" "%CV%\Privacy;" "%CV%\Search;"
set ALLOWED_REG=%ALLOWED_REG% "%CV%\SearchSettings;" "%CV%\ContentDeliveryManager;"
set ALLOWED_REG=%ALLOWED_REG% "%CV%\Explorer;" "%CV%\Explorer\Advanced;"
set ALLOWED_REG=%ALLOWED_REG% "%CUP%\SOFTWARE\Microsoft\InputPersonalization;"
set ALLOWED_REG=%ALLOWED_REG% "%CUP%\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore;"
set ALLOWED_REG=%ALLOWED_REG% "%CUP%\SOFTWARE\Microsoft\Personalization\Settings;"
set ALLOWED_REG=%ALLOWED_REG% "%CUP%\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy;"
set ALLOWED_REG=%ALLOWED_REG% "%CUP%\SOFTWARE\Microsoft\Siuf\Rules;"
set ALLOWED_REG=%ALLOWED_REG% "%CUP%\Control Panel\International\User Profile;"
set ALLOWED_REG=%ALLOWED_REG% "SYS\Services\NlaSvc\Parameters\Internet;"
set ALLOWED_REG=%ALLOWED_REG% "SYS\Services\Dnscache\Parameters;EnableMDNS"
set ALLOWED_REG=%ALLOWED_REG% "SYS\Control\Session Manager\Environment;DOTNET_CLI_TELEMETRY_OPTOUT"
set ALLOWED_REG=%ALLOWED_REG% "SYS\Control\Session Manager\Environment;POWERSHELL_TELEMETRY_OPTOUT"
set "ALLOWED_SERVICES=DiagTrack dmwappushservice tzautoupdate SSDPSRV upnphost FDResPub"
exit /b 0


REM ==========================================================================
REM  Main actions
REM ==========================================================================

:apply
call :require_target
if errorlevel 1 goto menu
call :confirm_managed
if errorlevel 1 goto menu
cls
color 07
Echo Applying settings for %OS_NAME%...
call :log INFO "Apply started"
set "FAILS=0"
set "SAVE_FAILED="
for %%S in (%SETTINGS%) do call :apply_option %%S
call :run_oem_scripts apply
if defined SAVE_NEEDED call :save_config
goto report


:restore_originals
call :require_target
if errorlevel 1 goto menu
call :confirm_managed
if errorlevel 1 goto menu
cls
color 07
Echo Putting back the values that were there before this script changed them.
Echo The selections in the configuration are not changed.
call :log INFO "Put back started"
set "FAILS=0"
set "SAVE_FAILED="
call :remove_reapply_task
for %%S in (%SETTINGS%) do call :put_back_option %%S
call :run_oem_scripts restore
if defined SAVE_NEEDED call :save_config
goto report


:windows_defaults
call :require_target
if errorlevel 1 goto menu
call :confirm_managed
if errorlevel 1 goto menu
cls
color 0e
Echo This sets every setting to the Windows default, not to the values you
Echo had before. Your own earlier choices, such as a manually disabled
Echo advertising ID, are overwritten. Use R to put back your own values.
Echo.
call :prompt_key YN "Continue? [Y/N]: "
if /i "%KEY%"=="N" goto menu
color 07
call :log INFO "Windows defaults started"
set "FAILS=0"
set "SAVE_FAILED="
call :remove_reapply_task
for %%S in (%SETTINGS%) do call :restore_option %%S
call :run_oem_scripts restore
REM The saved earlier values no longer describe this PC.
for /f "delims==" %%A in ('set OV# 2^>nul') do set "%%A="
call :save_config
goto report


:choose
call :require_target
if errorlevel 1 goto menu
call :confirm_managed
if errorlevel 1 goto menu
cls
color 07
Echo For each setting type Y to apply the privacy setting or N to keep your
Echo own setting. Press Enter to keep the value shown.
Echo Settings that do not exist on %OS_NAME% are skipped.
Echo.
for %%S in (%SETTINGS%) do call :ask_option %%S main
call :warn_combinations
call :mark_profile_adjusted
call :ask_timezone
call :ask_connectivity
goto save_and_apply


REM ==========================================================================
REM  Profiles
REM  A profile sets every selection at once. C can adjust them afterwards.
REM  Settings a new profile turns off are put back to their earlier values
REM  on the next Apply, using the saved ORIG lines.
REM ==========================================================================

:pick_profile
call :require_target
if errorlevel 1 goto menu
call :confirm_managed
if errorlevel 1 goto menu
cls
color 07
Echo Profiles set every selection at once. You can adjust them with C later.
Echo They are listed from least to most privacy.
Echo.
Echo   1  Work      Least privacy. Keeps dictation, Office Editor and
Echo                translation, clipboard history, recent files, Find My
Echo                Device, error reports and network browsing for office
Echo                printers and file shares. 23 of 47 settings.
Echo   2  Home      More privacy. Strong privacy for a home or gaming PC.
Echo                Keeps NetBIOS for NAS and Samba shares, and Teredo for
Echo                Xbox party chat and multiplayer. The default. 33 of 47
Echo                settings.
Echo   3  Maximum   Most privacy. Every privacy setting, including uninstalling
Echo                Copilot, the new Outlook and OneDrive. Security settings
Echo                stay on. 43 of 47 settings.
Echo   4  Back
Echo.
call :prompt_key 1234 "Select a profile [1-4]: "
if "%KEY%"=="4" goto menu
if "%KEY%"=="1" set "NEW_PROFILE=Work"
if "%KEY%"=="2" set "NEW_PROFILE=Home"
if "%KEY%"=="3" set "NEW_PROFILE=Maximum"

if not "%NEW_PROFILE%"=="Maximum" goto pick_profile_set
cls
color 0e
Echo Maximum also does the following:
Echo   - Uninstalls Copilot and the new Outlook, and uninstalls OneDrive unless
Echo     your Desktop, Documents or Pictures are inside it. This script cannot
Echo     reinstall them.
Echo   - Turns off Phone Link, mDNS casting and printer discovery, and UPnP
Echo     device discovery and port mapping for games.
Echo   - Rotates the connectivity check, which needs the installed copy.
Echo.
call :prompt_key YN "Use Maximum? [Y/N]: "
color 07
if /i "%KEY%"=="N" goto pick_profile

:pick_profile_set
call :set_profile %NEW_PROFILE%
set "PROFILE=%NEW_PROFILE%"
call :log INFO "Profile %NEW_PROFILE% selected"
Echo.
Echo Profile %NEW_PROFILE% selected.
call :ask_timezone
call :ask_connectivity
Echo.
Echo   A  Save and apply now
Echo   C  Adjust the selections first
Echo   X  Cancel and keep the previous selections
Echo.
call :prompt_key ACX "Select an option [A,C,X]: "
if /i "%KEY%"=="A" goto save_and_apply
if /i "%KEY%"=="C" goto choose
call :reload_config
goto menu


:set_profile
REM %1 = Work, Home or Maximum. Sets every selection.
REM Everything starts at 0, then each profile lists what it turns on.
for %%S in (%SETTINGS%) do set "OPT_%%S=0"
REM The same in every profile.
set "COMMON=TELEMETRY ADVERTISING_ID TAILORED_EXPERIENCES ACTIVITY_HISTORY"
set "COMMON=%COMMON% WEB_SEARCH SUGGESTED_CONTENT LANGUAGE_LIST HANDWRITING_SHARING"
set "COMMON=%COMMON% CALL_HISTORY CLIPBOARD_SYNC CLOUD_SEARCH SEARCH_HIGHLIGHTS"
set "COMMON=%COMMON% START_RECOMMENDATIONS WIDGETS SETTINGS_SYNC DELIVERY_OPTIMIZATION"
set "COMMON=%COMMON% EDGE_DIAGNOSTICS RECALL OFFICE_TELEMETRY DEV_TOOLS_TELEMETRY"
set "COMMON=%COMMON% LLMNR LLTD"
REM The settings Work keeps for everyday use.
set "EVERYDAY=PUSH_SERVICE INPUT_PERSONALIZATION ONLINE_SPEECH LOCATION"
set "EVERYDAY=%EVERYDAY% FIND_MY_DEVICE CLIPBOARD_HISTORY ERROR_REPORTING"
set "EVERYDAY=%EVERYDAY% APP_LAUNCH_TRACKING RECENT_FILES OFFICE_CONNECTED"
for %%S in (%COMMON%) do set "OPT_%%S=1"
goto profile_%~1

:profile_Home
REM The default. NetBIOS stays on so NAS boxes and Samba shares can be
REM found by name, and Teredo stays on for Xbox party chat and multiplayer.
for %%S in (%EVERYDAY% NETWORK_PUBLISHING) do set "OPT_%%S=1"
exit /b 0

:profile_Work
for %%S in (TEREDO) do set "OPT_%%S=1"
exit /b 0

:profile_Maximum
for %%S in (%EVERYDAY% NETWORK_PUBLISHING NETBIOS TEREDO) do set "OPT_%%S=1"
for %%S in (PHONE_LINK DEFENDER_SAMPLES COPILOT_REMOVE OUTLOOK_REMOVE) do set "OPT_%%S=1"
for %%S in (ONEDRIVE_REMOVE CONNECTIVITY_CHECK MDNS SSDP_UPNP) do set "OPT_%%S=1"
exit /b 0


:mark_profile_adjusted
REM Shows in Status that the profile was changed with C afterwards.
if not defined PROFILE exit /b 0
if not "%PROFILE:adjusted=%"=="%PROFILE%" exit /b 0
set "PROFILE=%PROFILE% - adjusted"
exit /b 0


REM ==========================================================================
REM  Managed PCs
REM ==========================================================================

:confirm_managed
REM Warns once per target when the PC is managed by an organization. The
REM user can continue. Returns 1 when the user chooses not to.
if defined MANAGED_ACK exit /b 0
call :check_managed
if not defined MANAGED_KIND (
    set "MANAGED_ACK=1"
    exit /b 0
)
cls
color 0e
Echo WARNING: this PC appears to be managed by an organization:
Echo   %MANAGED_KIND%
Echo.
Echo The organization's policies may override these settings, or these
Echo settings may break the organization's rules, updates or tools. On a
Echo school or work PC, check with IT before continuing.
Echo.
call :prompt_key YN "Continue anyway? [Y/N]: "
color 07
if /i "%KEY%"=="N" exit /b 1
set "MANAGED_ACK=1"
call :log WARN "Continued on a managed PC: %MANAGED_KIND%"
exit /b 0


:check_managed
REM Sets MANAGED_KIND to the ways the target is managed, or clears it.
REM Works on the running and on an offline Windows.
set "MANAGED_KIND="
%REG% QUERY "%SW%\Microsoft\Windows\CurrentVersion\Group Policy\State\Machine" /v Distinguished-Name >nul 2>&1
if not errorlevel 1 call :add_managed "Active Directory domain"
if defined MANAGED_KIND goto check_managed_entra
%REG% QUERY "%SYS%\Services\Netlogon\Parameters" /v DynamicSiteName >nul 2>&1
if not errorlevel 1 call :add_managed "Active Directory domain"

:check_managed_entra
REM An Entra ID join leaves a subkey under JoinInfo.
%REG% QUERY "%SYS%\Control\CloudDomainJoin\JoinInfo" 2>nul | %FINDSTR% /r /i /c:"JoinInfo\\." >nul
if not errorlevel 1 call :add_managed "Microsoft Entra ID"
%REG% QUERY "%SW%\Microsoft\Enrollments" /s /v ProviderID 2>nul | %FINDSTR% /i /c:"MS DM Server" >nul
if not errorlevel 1 call :add_managed "Intune or another MDM"
exit /b 0


:add_managed
REM %1 = description
if defined MANAGED_KIND (
    set "MANAGED_KIND=%MANAGED_KIND%, %~1"
) else (
    set "MANAGED_KIND=%~1"
)
exit /b 0


:save_and_apply
call :save_config
if errorlevel 1 (
    color 0c
    Echo Could not write the configuration file.
    call :notify_error "Could not write the configuration file"
    pause
    goto menu
)
Echo.
Echo Configuration saved to %CONFIG%
pause
goto apply


:status
cls
color 07
Echo Status for %OS_NAME%, build %BUILD% - no_ms_spy %VERSION%
if defined CONFIG_FOUND Echo Configuration: %CONFIG%
if not defined CONFIG_FOUND Echo Configuration: script defaults, the Home profile
if defined PROFILE Echo Profile: %PROFILE%
call :check_managed
if defined MANAGED_KIND Echo Managed by an organization: %MANAGED_KIND%
if not defined MANAGED_KIND Echo Managed by an organization: no signs found
Echo.
Echo Selections - 1 = privacy setting, 0 = your own setting:
for %%S in (%SETTINGS%) do call :show_option %%S
Echo.
set "ORIG_COUNT=0"
for /f "delims==" %%A in ('set OV# 2^>nul') do set /a ORIG_COUNT+=1
Echo Earlier values saved for putting back: %ORIG_COUNT%
if defined TIMEZONE Echo Saved time zone: %TIMEZONE%
if not defined OFFLINE for /f "delims=" %%T in ('%TZUTIL% /g 2^>nul') do Echo Current time zone: %%T
call :show_value "%SYS%\Services\NlaSvc\Parameters\Internet" ActiveWebProbeHost
Echo.
Echo Services:
call :show_service DiagTrack
if %BUILD% GEQ 10240 call :show_service dmwappushservice
Echo.
Echo Essential services - should not be disabled:
call :show_service wuauserv
call :show_service sppsvc
call :show_service WinDefend
Echo.
Echo Partner and OEM scripts in the config: %OEM_SCRIPT_COUNT%
set "REAPPLY_STATE=off"
if not defined OFFLINE %SCHTASKS% /Query /TN "%REAPPLY_TASK%" >nul 2>&1 && set "REAPPLY_STATE=on"
if not defined OFFLINE Echo Reapply at every sign-in: %REAPPLY_STATE%
Echo Log file: %LOG_FILE%
Echo.
pause
goto menu


:report
Echo.
call :log INFO "Finished with %FAILS% failed changes"
if %FAILS% GTR 0 (
    color 0c
    Echo Number of failed changes: %FAILS%. See the FAILED lines above and the log.
    call :notify_error "%FAILS% changes failed. See %LOG_FILE%"
) else (
    color 0a
    Echo All applicable changes were applied.
)
if defined OFFLINE Echo Exit with X or detach under V so the offline registry is saved.
if not defined OFFLINE Echo Restart the computer to complete the process.
pause
goto menu


:reapply
REM Started by the reapply-at-sign-in task. Nobody may be watching, so there
REM are no prompts or pauses; failures are reported by :notify_error.
if not defined INSTALLED (
    call :notify_error "Reapply only runs from the installed copy"
    goto end
)
REM An R or W on the offline installation left this signal: the task
REM removes itself instead of applying the settings again.
if exist "%INSTALL_DIR%\config\reapply_off.signal" (
    %SCHTASKS% /Delete /TN "%REAPPLY_TASK%" /F >nul 2>&1
    del /q "%INSTALL_DIR%\config\reapply_off.signal"
    call :log INFO "Reapply task removed after a put-back on the offline installation"
    goto end
)
call :log INFO "Reapply at sign-in started for %CU_USER%"
REM Without the saved config the script defaults would be applied, which
REM may not be what was chosen, so nothing is changed.
if not defined CONFIG_FOUND (
    call :notify_error "Reapply at sign-in found no saved configuration in %CONFIG_DIR%, so nothing was changed"
    goto end
)
set "FAILS=0"
set "SAVE_FAILED="
for %%S in (%SETTINGS%) do call :apply_option %%S
call :run_oem_scripts apply
if defined SAVE_NEEDED call :save_config
call :log INFO "Reapply finished with %FAILS% failed changes"
if %FAILS% GTR 0 call :notify_error "Reapply at sign-in: %FAILS% changes failed. See %LOG_FILE%"
goto end


:install
cls
color 07
if defined INSTALLED (
    Echo This is already the installed copy.
    pause
    goto menu
)
if defined IN_PE (
    Echo Installing is not available in a recovery environment.
    pause
    goto menu
)
if not defined INSTALL_DIR (
    Echo The Program Files folder could not be found.
    pause
    goto menu
)
Echo Installing to %INSTALL_DIR%...
set "INSTALL_FAILED="
for %%D in ("%INSTALL_DIR%" "%INSTALL_DIR%\scripts" "%INSTALL_DIR%\config" "%INSTALL_DIR%\logs") do if not exist "%%~D\" mkdir "%%~D"
call :migrate_flat_install
for %%F in (%INSTALL_FILES%) do call :install_file "%%~F" required
REM An installed config holds the earlier values of this PC, so it is kept.
call :install_file "config\no_ms_spy.cfg" optional
if exist "%OEM_DIR%\" %XCOPY% "%OEM_DIR%" "%INSTALL_DIR%\scripts\oem\" /E /I /Y /Q >nul
REM Reset permissions to the Program Files defaults: only administrators and
REM SYSTEM can change the files.
%ICACLS% "%INSTALL_DIR%" /reset /T /C /Q >nul
if defined INSTALL_FAILED (
    color 0c
    Echo Installation failed. See the messages above.
    call :notify_error "Installation to %INSTALL_DIR% failed"
    pause
    goto menu
)
Echo.
Echo SHA-256 of the installed files. Compare them with the copies you trust:
for %%F in (%INSTALL_FILES%) do call :show_hash "%%~F"
call :log INFO "Installed to %INSTALL_DIR%"
Echo.
Echo Starting the installed copy...
pause
REM Started through the launcher, it starts the installed copy itself once
REM this copy has ended, so the new copy does not inherit its lock.
if defined NMS_LAUNCHER (
    set "START_INSTALLED=1"
    goto end
)
start "no_ms_spy" "%INSTALL_DIR%\no_ms_spy.bat"
goto end



:uninstall
cls
color 07
if defined OFFLINE (
    Echo Uninstall needs the installation running. Detach the offline Windows
    Echo under V first. R still puts settings back on an offline Windows.
    pause
    goto menu
)
if not defined INSTALLED (
    Echo Uninstall runs from the installed copy, which holds this PC's saved
    Echo values: %INSTALL_DIR%\no_ms_spy.bat
    Echo If it was never installed, R puts back what this copy changed.
    pause
    goto menu
)
if not defined NMS_LAUNCHER (
    Echo Start Uninstall from %INSTALL_DIR%\no_ms_spy.bat, the launcher, so
    Echo it can remove the folder afterwards.
    pause
    goto menu
)
call :confirm_managed
if errorlevel 1 goto menu
color 0e
Echo Uninstall puts back every value this script saved before changing it,
Echo removes its scheduled tasks and event log source, and then deletes
Echo %INSTALL_DIR% with its config and logs.
Echo.
Echo It cannot undo these:
Echo   - Apps it uninstalled: OneDrive, Copilot and the new Outlook. Reinstall
Echo     them from Microsoft or the Microsoft Store.
Echo   - The deleted OutlookUpdate key, so Windows may not offer the new
Echo     Outlook again by itself.
Echo   - Policies you set yourself, for example Widgets in gpedit.
Echo.
Echo Settings for other user accounts are put back only when Uninstall runs
Echo from that account. If anything cannot be put back, Uninstall asks
Echo before deleting anything.
Echo.
call :prompt_key YN "Uninstall? [Y/N]: "
if /i "%KEY%"=="N" goto menu
color 07
call :log INFO "Uninstall started"
set "FAILS=0"
set "SAVE_FAILED="
call :remove_reapply_task
REM The rotation tasks go first, and even when no earlier values were saved
REM for them, so a run in progress cannot change the values put back.
call :remove_rotation
for %%S in (%SETTINGS%) do call :put_back_option %%S
call :run_oem_scripts restore
if defined SAVE_NEEDED call :save_config
set "LEFT_COUNT=0"
for /f "delims==" %%A in ('set OV# 2^>nul') do set /a LEFT_COUNT+=1
if %FAILS% GTR 0 goto uninstall_stopped
if %LEFT_COUNT% GTR 0 goto uninstall_stopped

:uninstall_cleanup
Echo.
Echo [Clean up]
REM Created by eventcreate the first time the script reported an error.
%REG% QUERY "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Application\no_ms_spy" >nul 2>&1
if not errorlevel 1 (
    %REG% DELETE "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Application\no_ms_spy" /f >nul 2>&1
    Echo   Removed  event log source no_ms_spy
)
REM The tasks are gone, so their no_ms_spy folder in Task Scheduler is empty.
%POWERSHELL% -NoProfile -Command "try { $s = New-Object -ComObject Schedule.Service; $s.Connect(); $s.GetFolder('\').DeleteFolder('no_ms_spy', 0) } catch { }" >nul 2>&1
Echo   Removed  the no_ms_spy folder in Task Scheduler
Echo.
Echo Everything is put back. Restart the computer when the folder is removed.
set "UNINSTALL_READY=1"
goto end

:uninstall_stopped
color 0e
Echo.
if %FAILS% GTR 0 Echo %FAILS% changes failed. See the FAILED lines above.
if %LEFT_COUNT% GTR 0 Echo %LEFT_COUNT% saved values were not put back from this account.
Echo Some may belong to another user account. A Windows update can also
Echo remove or protect a setting so it cannot be changed back.
Echo.
Echo   K  Keep the install and its saved values, fix the problem or run
Echo      Uninstall from the other account, then try again
Echo   F  Finish the uninstall anyway - those values stay as they are now
Echo.
call :prompt_key KF "Select an option [K,F]: "
if /i "%KEY%"=="F" goto uninstall_forced
call :log WARN "Uninstall stopped: %FAILS% failed changes, %LEFT_COUNT% values not put back"
goto menu

:uninstall_forced
for /f "delims==" %%A in ('set OV# 2^>nul') do call :log WARN "Not put back: %%A"
call :log WARN "Uninstall finished anyway: %FAILS% failed changes, %LEFT_COUNT% values not put back"
color 07
goto uninstall_cleanup


:install_file
REM %1 = path below the top folder, %2 = required or optional. Optional
REM files are only copied when the installed folder does not have them yet.
if /i "%~2"=="optional" if exist "%INSTALL_DIR%\%~1" (
    Echo   Kept     the installed %~1 - it holds this PC's saved values
    exit /b 0
)
if not exist "%ROOT_DIR%%~1" (
    if /i "%~2"=="required" (
        Echo   FAILED   %~1 not found in %ROOT_DIR%
        set "INSTALL_FAILED=1"
    )
    exit /b 0
)
copy /y "%ROOT_DIR%%~1" "%INSTALL_DIR%\%~1" >nul
if errorlevel 1 (
    Echo   FAILED   copy %~1
    set "INSTALL_FAILED=1"
) else (
    Echo   Copied   %~1
)
exit /b 0


:migrate_flat_install
REM An install made before the folder layout kept every file in one
REM folder. Its config holds this PC's earlier values, so it is moved
REM rather than replaced, and the old script files are removed.
for %%F in (no_ms_spy.cfg ncsi_state.txt restore.signal reapply_off.signal) do call :migrate_file %%F config
for %%F in (no_ms_spy.log ncsi_rotate.log) do call :migrate_file %%F logs
if exist "%INSTALL_DIR%\oem\" (
    %XCOPY% "%INSTALL_DIR%\oem" "%INSTALL_DIR%\scripts\oem\" /E /I /Y /Q >nul
    if not errorlevel 1 rmdir /s /q "%INSTALL_DIR%\oem"
)
for %%F in (ncsi_rotate.ps1 oem_template.bat) do if exist "%INSTALL_DIR%\%%F" del /q "%INSTALL_DIR%\%%F"
exit /b 0


:migrate_file
REM %1 = file name in the old single folder, %2 = its new subfolder
if not exist "%INSTALL_DIR%\%~1" exit /b 0
if exist "%INSTALL_DIR%\%~2\%~1" exit /b 0
move /y "%INSTALL_DIR%\%~1" "%INSTALL_DIR%\%~2\%~1" >nul
if errorlevel 1 (
    Echo   FAILED   move %~1 into %~2
    set "INSTALL_FAILED=1"
) else (
    Echo   Moved    %~1 into %~2
)
exit /b 0


:show_hash
REM %1 = path below the install folder
for /f "delims=" %%H in ('%CERTUTIL% -hashfile "%INSTALL_DIR%\%~1" SHA256 ^| %FINDSTR% /v /c:":"') do Echo   %%H  %~1
exit /b 0


REM ==========================================================================
REM  Advanced menu
REM ==========================================================================

:advanced
cls
color 07
Echo Advanced options
if defined OFFLINE Echo Target: offline Windows on %TARGET%, user %TARGET_USER%
Echo.
Echo   1  Choose local network chatter settings
Echo   2  Detect partner and OEM software
Echo   3  Run the partner and OEM scripts listed in the config
Echo   4  Select an offline Windows installation
Echo   5  Detach the offline Windows installation
Echo   6  Reapply the settings at every sign-in
Echo   7  Back
Echo.
call :prompt_key 1234567 "Select an option [1-7]: "
if "%KEY%"=="1" goto advanced_network
if "%KEY%"=="2" goto detect_oem
if "%KEY%"=="3" goto advanced_run
if "%KEY%"=="4" goto offline_select
if "%KEY%"=="5" goto offline_detach
if "%KEY%"=="6" goto advanced_reapply
if "%KEY%"=="7" goto menu
goto advanced


:advanced_network
call :require_target
if errorlevel 1 goto advanced
call :confirm_managed
if errorlevel 1 goto advanced
cls
color 0e
Echo WARNING: these settings stop this PC from announcing itself and
Echo discovering other devices on the local network. Possible effects:
Echo.
Echo   LLMNR       Devices without a DNS entry can no longer be found by
Echo               name. Also removes a common credential-theft path.
Echo   NetBIOS     Older NAS boxes, printers and \\NAME paths to old
Echo               devices can stop working. Adapters added later are
Echo               not covered until the script runs again.
Echo   mDNS        .local names, casting, AirPlay and some printers.
Echo   SSDP/UPnP   Media servers, smart TVs and UPnP port mapping for games.
Echo   Publishing  This PC no longer shows in the Network view of other PCs.
Echo   LLTD        The Network Map view only.
Echo   Teredo      Some peer-to-peer apps and Xbox party chat.
Echo.
Echo Each choice is saved to the config and can be reverted with N or R.
Echo.
call :prompt_key YN "Continue? [Y/N]: "
if /i "%KEY%"=="N" goto advanced
color 07
Echo.
for %%S in (%SETTINGS%) do call :ask_option %%S advanced
call :mark_profile_adjusted
if "%OPT_SSDP_UPNP%%OPT_TEREDO%"=="11" (
    Echo.
    Echo Note: with both SSDP/UPnP and Teredo off, online games usually report
    Echo a strict NAT type and Xbox party chat may fail.
    pause
)
goto save_and_apply


:advanced_run
call :require_target
if errorlevel 1 goto advanced
call :confirm_managed
if errorlevel 1 goto advanced
cls
set "FAILS=0"
set "SAVE_FAILED="
if %OEM_SCRIPT_COUNT% EQU 0 Echo No OEM_SCRIPT lines found in the config.
call :run_oem_scripts apply
goto report


:advanced_reapply
cls
color 07
if defined OFFLINE (
    Echo The task can only be set up on the running Windows. Detach the
    Echo offline installation first. R and W still turn it off there.
    pause
    goto advanced
)
if not defined INSTALLED (
    Echo The task runs the installed copy. Install with I on the main menu first.
    pause
    goto advanced
)
%SCHTASKS% /Query /TN "%REAPPLY_TASK%" >nul 2>&1
if not errorlevel 1 goto advanced_reapply_remove
set "RUN_AS=%USERDOMAIN%\%USERNAME%"
call :check_safe RUN_AS
if errorlevel 1 (
    Echo The account name contains a character cmd treats as code, so the
    Echo task cannot be created safely.
    pause
    goto advanced
)
Echo A task will apply the saved configuration again at every sign-in of
Echo %RUN_AS%, so settings changed by Windows updates or other programs are
Echo set back. It runs with administrator rights, shows a console window
Echo while it works, and reports failures like a normal Apply.
Echo.
Echo Set it up from the account whose settings you want kept. R and W on the
Echo main menu remove the task, so it does not undo them.
Echo.
call :prompt_key YN "Create the task? [Y/N]: "
if /i "%KEY%"=="N" goto advanced
set "FAILS=0"
set "SAVE_FAILED="
call :create_reapply_task
pause
goto advanced

:advanced_reapply_remove
Echo The settings are reapplied at every sign-in.
Echo.
call :prompt_key YN "Remove the task? [Y/N]: "
if /i "%KEY%"=="N" goto advanced
set "FAILS=0"
set "SAVE_FAILED="
call :remove_reapply_task
pause
goto advanced


:create_reapply_task
REM Uses RUN_AS. The task runs in that user's own session, so HKCU settings
REM reach that user and no password is stored, with the administrator
REM rights the script checks for. It starts one minute after that user,
REM and only that user, signs in, also on battery power.
if exist "%INSTALL_DIR%\config\reapply_off.signal" del /q "%INSTALL_DIR%\config\reapply_off.signal"
if %BUILD% LSS 9200 goto create_reapply_task_schtasks
REM The paths go through environment variables, so no character in them is
REM read as code.
set "NMS_REAPPLY_EXE=%INSTALL_DIR%\no_ms_spy.bat"
set "NMS_RUN_AS=%RUN_AS%"
%POWERSHELL% -NoProfile -Command "try { $a = New-ScheduledTaskAction -Execute ([char]34 + $env:NMS_REAPPLY_EXE + [char]34) -Argument 'reapply'; $t = New-ScheduledTaskTrigger -AtLogOn -User $env:NMS_RUN_AS; $t.Delay = 'PT1M'; $p = New-ScheduledTaskPrincipal -UserId $env:NMS_RUN_AS -LogonType Interactive -RunLevel Highest; $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1); Register-ScheduledTask -TaskPath '\no_ms_spy\' -TaskName 'Reapply at sign-in' -Action $a -Trigger $t -Principal $p -Settings $s -Force -ErrorAction Stop | Out-Null; exit 0 } catch { exit 1 }" >nul 2>&1
goto create_reapply_task_check

:create_reapply_task_schtasks
REM Windows 7 has no ScheduledTasks module. Input comes from nul, so a
REM password prompt fails at once instead of waiting unseen.
set "REAPPLY_COMMAND=\"%INSTALL_DIR%\no_ms_spy.bat\" reapply"
%SCHTASKS% /Create /TN "%REAPPLY_TASK%" /SC ONLOGON /DELAY 0001:00 /RU "%RUN_AS%" /IT /RL HIGHEST /TR "%REAPPLY_COMMAND%" /F <nul >nul 2>&1

:create_reapply_task_check
if errorlevel 1 (
    call :fail "Could not create the reapply task"
    exit /b 0
)
Echo   Created  task that reapplies the settings at every sign-in of %RUN_AS%
call :log INFO "Reapply task created for %RUN_AS%"
exit /b 0


:remove_reapply_task
REM The task would undo R and W at the next sign-in, so they remove it.
REM Offline, reapply_off.signal makes the task remove itself instead.
if defined OFFLINE goto remove_reapply_offline
%SCHTASKS% /Query /TN "%REAPPLY_TASK%" >nul 2>&1
if errorlevel 1 exit /b 0
%SCHTASKS% /Delete /TN "%REAPPLY_TASK%" /F >nul 2>&1
if errorlevel 1 (
    call :fail "Could not remove the reapply task"
    exit /b 0
)
Echo   Removed  task that reapplies the settings at sign-in
call :log INFO "Reapply task removed"
exit /b 0

:remove_reapply_offline
if not defined TARGET_INSTALL exit /b 0
if not exist "%TARGET_INSTALL%\no_ms_spy.bat" exit /b 0
> "%TARGET_CONFIG_DIR%\reapply_off.signal" Echo remove
if errorlevel 1 (
    call :fail "Could not write reapply_off.signal to %TARGET_CONFIG_DIR%"
    exit /b 0
)
Echo   Signal   the reapply task removes itself at the next sign-in on %TARGET%
exit /b 0


REM ==========================================================================
REM  Per-option dispatch
REM ==========================================================================

:apply_option
REM %1 = setting name. 1 applies the privacy setting. 0 puts back the
REM earlier values if this script changed them, and otherwise does nothing.
call set "MIN=%%MIN_%~1%%"
if %BUILD% LSS %MIN% exit /b 0
call set "DESC=%%DESC_%~1%%"
call set "VALUE=%%OPT_%~1%%"
Echo.
if "%VALUE%"=="1" goto apply_option_on
Echo [Yours]   %DESC%
REM The rotation is stopped first, so it cannot overwrite the values put back.
if /i "%~1"=="CONNECTIVITY_CHECK" call :remove_rotation
call :put_back_setting %~1
exit /b 0

:apply_option_on
Echo [Privacy] %DESC%
set "CURRENT_SETTING=%~1"
call :apply_%~1
set "CURRENT_SETTING="
REM The earlier values are written to the config after every setting, so
REM an Apply that is interrupted can still be put back.
if not defined SAVE_NEEDED exit /b 0
call :save_config
if not errorlevel 1 exit /b 0
if defined SAVE_FAILED exit /b 0
set "SAVE_FAILED=1"
call :fail "Could not write %CONFIG% - the values changed now cannot be put back later"
exit /b 0


:put_back_option
REM %1 = setting name
call set "MIN=%%MIN_%~1%%"
if %BUILD% LSS %MIN% exit /b 0
call set "DESC=%%DESC_%~1%%"
Echo.
Echo [Put back] %DESC%
REM The rotation is stopped first, so it cannot overwrite the values put back.
if /i "%~1"=="CONNECTIVITY_CHECK" call :remove_rotation
call :put_back_setting %~1
exit /b 0


:restore_option
REM %1 = setting name. Sets the Windows default.
call set "MIN=%%MIN_%~1%%"
if %BUILD% LSS %MIN% exit /b 0
call set "DESC=%%DESC_%~1%%"
Echo.
Echo [Default] %DESC%
call :restore_%~1
exit /b 0


:ask_option
REM %1 = setting name, %2 = main or advanced
if /i "%~2"=="main" if defined ADV_%~1 exit /b 0
if /i "%~2"=="advanced" if not defined ADV_%~1 exit /b 0
call set "MIN=%%MIN_%~1%%"
if %BUILD% LSS %MIN% exit /b 0
call set "DESC=%%DESC_%~1%%"
call set "CURRENT=%%OPT_%~1%%"
set "DEFAULT_KEY=Y"
if "%CURRENT%"=="0" set "DEFAULT_KEY=N"

:ask_option_again
set "ANSWER="
set /p "ANSWER=%DESC% [Y/N, Enter = %DEFAULT_KEY%]: "
if not defined ANSWER set "ANSWER=%DEFAULT_KEY%"
call :check_safe ANSWER
if errorlevel 1 goto ask_option_invalid
if /i "%ANSWER:~0,1%"=="Y" (
    set "OPT_%~1=1"
    exit /b 0
)
if /i "%ANSWER:~0,1%"=="N" (
    set "OPT_%~1=0"
    exit /b 0
)

:ask_option_invalid
Echo Please type Y or N.
goto ask_option_again


:show_option
REM %1 = setting name
call set "MIN=%%MIN_%~1%%"
if %BUILD% LSS %MIN% exit /b 0
call set "VALUE=%%OPT_%~1%%"
if defined ADV_%~1 (
    Echo   %VALUE%  %~1  - advanced
) else (
    Echo   %VALUE%  %~1
)
exit /b 0


:warn_combinations
if not "%OPT_DEFENDER_CLOUD%%OPT_SMARTSCREEN%"=="11" exit /b 0
Echo.
color 0e
Echo WARNING: with both Defender cloud protection and SmartScreen off, this
Echo PC has little protection against new malware and phishing downloads.
call :prompt_key YN "Keep both off? [Y/N]: "
color 07
if /i "%KEY%"=="Y" exit /b 0
set "OPT_DEFENDER_CLOUD=0"
set "OPT_SMARTSCREEN=0"
Echo Both are set back to your own setting.
exit /b 0


:ask_timezone
REM With location off, Windows can no longer detect the time zone, so the
REM zone is saved and set explicitly. Clock sync with NTP is not affected.
if not "%OPT_LOCATION%"=="1" exit /b 0
if defined OFFLINE exit /b 0
set "CURRENT_TZ="
for /f "delims=" %%T in ('%TZUTIL% /g') do set "CURRENT_TZ=%%T"
if not defined TIMEZONE set "TIMEZONE=%CURRENT_TZ%"
REM The config rejects parentheses, which some zone names contain, such as
REM Pacific Standard Time (Mexico). Such a zone is not saved.
call :check_safe TIMEZONE
if errorlevel 1 set "TIMEZONE="
Echo.
Echo Location will be off, so the time zone will be set from the config.
Echo Current time zone: %CURRENT_TZ%
Echo To list valid time zone names, run: tzutil /l
if not defined TIMEZONE Echo This zone's name has characters the config cannot store. Leave it empty and set the zone by hand when it changes.

:ask_timezone_again
set "ANSWER="
set /p "ANSWER=Time zone to save [Enter = %TIMEZONE%]: "
if not defined ANSWER exit /b 0
set "TZ_SAVED=%TIMEZONE%"
set "TIMEZONE=%ANSWER%"
call :valid_timezone
if not errorlevel 1 exit /b 0
set "TIMEZONE=%TZ_SAVED%"
Echo That is not a time zone name tzutil knows.
goto ask_timezone_again


:ask_connectivity
if not "%OPT_CONNECTIVITY_CHECK%"=="1" exit /b 0
Echo.
if not defined INSTALLED Echo The rotation needs the installed copy. Install with I, then apply again.
if not defined NCSI_ROTATE_HOURS set "NCSI_ROTATE_HOURS=1"
Echo The connectivity check will rotate between the providers built into ncsi_rotate.ps1.

:ask_hours
set "ANSWER="
set /p "ANSWER=Hours between rotations, 1 to 23 [Enter = %NCSI_ROTATE_HOURS%]: "
if not defined ANSWER goto ask_dns
call :check_safe ANSWER
if errorlevel 1 goto ask_hours
REM An invalid number such as 08 leaves the value unchanged, so start at 0.
set "HOURS_CHECK=0"
set /a HOURS_CHECK=ANSWER 2>nul
if %HOURS_CHECK% LSS 1 goto ask_hours
if %HOURS_CHECK% GTR 23 goto ask_hours
set "NCSI_ROTATE_HOURS=%HOURS_CHECK%"

:ask_dns
Echo.
Echo The DNS check rotates between the root server names and Microsoft's name.
Echo Optional, for administrators: a fixed DNS host you control and the IPv4
Echo address it always resolves to, used instead of the rotation. Press
Echo Enter to keep the current choice, or type - to go back to the rotation.
set "ANSWER="
set /p "ANSWER=DNS check host [Enter = %NCSI_DNS_HOST%]: "
if not defined ANSWER exit /b 0
call :check_safe ANSWER
if errorlevel 1 goto ask_dns
if "%ANSWER%"=="-" (
    set "NCSI_DNS_HOST="
    set "NCSI_DNS_IP="
    exit /b 0
)
set ANSWER| %FINDSTR% /r /i /x /c:"ANSWER=[a-z0-9.-]*" >nul
if errorlevel 1 goto ask_dns
set "NCSI_DNS_HOST=%ANSWER%"

:ask_dns_ip
set "ANSWER="
set /p "ANSWER=IPv4 address of %NCSI_DNS_HOST%: "
if not defined ANSWER goto ask_dns_ip
call :check_safe ANSWER
if errorlevel 1 goto ask_dns_ip
set ANSWER| %FINDSTR% /r /x /c:"ANSWER=[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*" >nul
if errorlevel 1 goto ask_dns_ip
set "NCSI_DNS_IP=%ANSWER%"
exit /b 0


REM ==========================================================================
REM  Config file
REM ==========================================================================

:load_config
set "CONFIG_FOUND="
set "OEM_SCRIPT_COUNT=0"
if not exist "%CONFIG%" exit /b 0

REM Reject the whole file if any line has a character cmd could run as code.
>nul %FINDSTR% /r /c:"[&|<>^%%!()]" "%CONFIG%"
if not errorlevel 1 goto config_unsafe
<"%CONFIG%" >nul %FINDSTR% /l "\""
if not errorlevel 1 goto config_unsafe

set "CONFIG_FOUND=1"
for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%CONFIG%") do (
    if /i "%%A"=="ORIG" (
        call :load_orig "%%B"
    ) else (
        call :load_option "%%A" "%%B"
    )
)
exit /b 0

:config_unsafe
color 0c
Echo The configuration file contains characters that could run commands.
Echo Lines with problems:
%FINDSTR% /n /r /c:"[&|<>^%%!()]" "%CONFIG%"
<"%CONFIG%" %FINDSTR% /n /l "\""
Echo Remove those characters or delete %CONFIG%, then start again.
call :notify_error "Configuration file rejected - it contains characters that could run commands"
exit /b 1


:load_option
REM %1 = name, %2 = value. Unknown names and values other than 0 or 1 are
REM ignored, so a missing or bad line falls back to the default.
for %%K in (%TEXT_KEYS%) do if /i "%~1"=="%%K" set "%%K=%~2"
for %%K in (%LIST_KEYS%) do if /i "%~1"=="%%K" call :add_list_item %%K "%~2"
if not defined MIN_%~1 exit /b 0
if "%~2"=="0" set "OPT_%~1=0"
if "%~2"=="1" set "OPT_%~1=1"
exit /b 0


:load_orig
REM %1 = OV#location;name;=SETTING;TYPE;DATA. Only names starting with OV#
REM are accepted, so the config cannot overwrite other variables.
set "ORIG_LINE=%~1"
if not "%ORIG_LINE:~0,3%"=="OV#" exit /b 0
set "%~1"
exit /b 0


:add_list_item
REM %1 = list name, %2 = value. Stored as NAME_1, NAME_2 ... NAME_COUNT.
set /a %~1_COUNT+=1
call set "%~1_%%%~1_COUNT%%=%~2"
exit /b 0


:save_config
REM The new config is written to a temporary file and then moved over the
REM old one in one step, so an interruption cannot leave a half-written
REM config and the rotation script never reads one.
REM Redirection is placed first so NAME=1 is not read as handle 1.
set "CONFIG_OUT=%CONFIG%.new"
> "%CONFIG_OUT%" Echo # no_ms_spy.bat configuration, written by version %VERSION%
if errorlevel 1 exit /b 1
>> "%CONFIG_OUT%" Echo # 1 = apply the privacy setting, 0 = keep or put back your own setting
>> "%CONFIG_OUT%" Echo # OEM_SCRIPT=name.bat can be repeated. The file must be in the scripts\oem folder.
>> "%CONFIG_OUT%" Echo # OEM scripts are run as:  name.bat apply  or  name.bat restore
>> "%CONFIG_OUT%" Echo # ORIG lines are earlier values saved by the script. Do not edit them.
>> "%CONFIG_OUT%" Echo # Do not use these characters: and, pipe, less, greater, caret, percent,
>> "%CONFIG_OUT%" Echo # exclamation, parentheses or quotes.
for %%S in (%SETTINGS%) do call :save_option %%S
for %%K in (%TEXT_KEYS%) do call :save_text %%K
for %%K in (%LIST_KEYS%) do call :save_list %%K
REM FOR variables are expanded after cmd parses the line, so saved values
REM cannot run as code here.
for /f "tokens=1,* delims==" %%A in ('set OV# 2^>nul') do >> "%CONFIG_OUT%" Echo ORIG=%%A=%%B
move /y "%CONFIG_OUT%" "%CONFIG%" >nul
if errorlevel 1 (
    del /q "%CONFIG_OUT%" 2>nul
    exit /b 1
)
set "CONFIG_FOUND=1"
set "SAVE_NEEDED="
exit /b 0


:save_option
REM %1 = setting name. Settings that do not apply to this build are still
REM saved so the same config works on other Windows versions.
call set "VALUE=%%OPT_%~1%%"
>> "%CONFIG_OUT%" Echo %~1=%VALUE%
exit /b 0


:save_text
REM %1 = variable name. Empty values are not written.
set "VALUE="
call set "VALUE=%%%~1%%"
if defined VALUE >> "%CONFIG_OUT%" Echo %~1=%VALUE%
exit /b 0


:save_list
REM %1 = list name
call set "COUNT=%%%~1_COUNT%%"
for /l %%I in (1,1,%COUNT%) do call :save_list_item %~1 %%I
exit /b 0


:save_list_item
REM %1 = list name, %2 = item number
call set "VALUE=%%%~1_%~2%%"
>> "%CONFIG_OUT%" Echo %~1=%VALUE%
exit /b 0


:reload_config
REM Clears everything loaded from a config and loads CONFIG again.
for /f "delims==" %%A in ('set OV# 2^>nul') do set "%%A="
for /f "delims==" %%A in ('set OEM_SCRIPT_ 2^>nul') do set "%%A="
call :define_settings
for %%K in (%TEXT_KEYS%) do set "%%K="
call :define_allowed
call :load_config
exit /b %errorlevel%


REM ==========================================================================
REM  Earlier values: save before the first change, put back later
REM
REM  Each earlier value is kept in a variable named
REM    OV#location;name;       for example OV#SW\Policies\X;Value;
REM  with the value SETTING;TYPE;DATA. TYPE - means the value did not exist.
REM  Locations: SW, SYS and CU@user are registry roots. SVC holds a service
REM  start type, TASK a scheduled task state and TZ the time zone.
REM ==========================================================================

:key_id
REM %1 = registry key. Sets KEY_ID with SW, SYS or CU@user in place of
REM the root, so the same entry works online and offline.
set "KEY_ID=%~1"
call set "KEY_ID=%%KEY_ID:%SW%\=SW\%%"
call set "KEY_ID=%%KEY_ID:%SYS%\=SYS\%%"
call set "KEY_ID=%%KEY_ID:%CU%\=CU@%CU_USER%\%%"
exit /b 0


:id_to_key
REM %1 = saved location. Sets KEY, or clears it when the entry belongs to
REM another user's profile.
set "KEY="
set "ID_ROOT="
set "ID_REST="
for /f "tokens=1,* delims=\" %%P in ("%~1") do (
    set "ID_ROOT=%%P"
    set "ID_REST=%%Q"
)
if /i "%ID_ROOT%"=="SW" set "KEY=%SW%\%ID_REST%"
if /i "%ID_ROOT%"=="SYS" set "KEY=%SYS%\%ID_REST%"
if /i "%ID_ROOT%"=="CU@%CU_USER%" set "KEY=%CU%\%ID_REST%"
exit /b 0


:remember_value
REM %1 = key, %2 = value name. Saves the value that is there now, once,
REM before the script first changes it.
set "NEW_OV="
if not defined CURRENT_SETTING exit /b 0
call :key_id "%~1"
set "OV#%KEY_ID%;%~2;" >nul 2>&1
if not errorlevel 1 exit /b 0
set "ORIG_TYPE=-"
set "ORIG_DATA=-"
for /f "tokens=2,*" %%A in ('%REG% QUERY "%~1" /v "%~2" 2^>nul ^| %FINDSTR% /i /r /c:"^    %~2 "') do (
    set "ORIG_TYPE=%%A"
    set "ORIG_DATA=%%B"
)
call :check_safe ORIG_DATA
if errorlevel 1 (
    call :note "The earlier value of %~2 cannot be saved safely and will not be put back"
    exit /b 0
)
set "OV#%KEY_ID%;%~2;=%CURRENT_SETTING%;%ORIG_TYPE%;%ORIG_DATA%"
set "NEW_OV=OV#%KEY_ID%;%~2;"
set "SAVE_NEEDED=1"
exit /b 0


:remember_service
REM %1 = service name. Saves the start type from the registry: 2 automatic,
REM 2d delayed automatic, 3 manual, 4 disabled.
set "NEW_OV="
if not defined CURRENT_SETTING exit /b 0
set "OV#SVC;%~1;" >nul 2>&1
if not errorlevel 1 exit /b 0
set "ORIG_DATA="
for /f "tokens=3" %%A in ('%REG% QUERY "%SYS%\Services\%~1" /v Start 2^>nul ^| %FIND% "Start"') do set /a ORIG_DATA=%%A
if not defined ORIG_DATA exit /b 0
for /f "tokens=3" %%A in ('%REG% QUERY "%SYS%\Services\%~1" /v DelayedAutostart 2^>nul ^| %FIND% "DelayedAutostart"') do if /i "%%A"=="0x1" if "%ORIG_DATA%"=="2" set "ORIG_DATA=2d"
set "OV#SVC;%~1;=%CURRENT_SETTING%;SVC;%ORIG_DATA%"
set "NEW_OV=OV#SVC;%~1;"
set "SAVE_NEEDED=1"
exit /b 0


:remember_task
REM %1 = full task path. Saves Ready or Disabled.
set "NEW_OV="
if not defined CURRENT_SETTING exit /b 0
if defined OFFLINE exit /b 0
set "OV#TASK;%~1;" >nul 2>&1
if not errorlevel 1 exit /b 0
for %%T in ("%~1") do (
    set "TASK_FOLDER=%%~pT"
    set "TASK_NAME=%%~nxT"
)
set "ORIG_DATA="
for /f "delims=" %%S in ('%POWERSHELL% -NoProfile -Command "Get-ScheduledTask -TaskPath '%TASK_FOLDER%' -TaskName '%TASK_NAME%' -ErrorAction SilentlyContinue | ForEach-Object { $_.State }"') do set "ORIG_DATA=%%S"
if defined ORIG_DATA goto remember_task_save
REM Windows 7 has no Get-ScheduledTask, so the task definition is read
REM instead. A disabled task has Enabled set to false.
set "ORIG_DATA=Ready"
%SCHTASKS% /Query /TN "%~1" /XML 2>nul | %FINDSTR% /i /c:"<Enabled>false</Enabled>" >nul
if not errorlevel 1 set "ORIG_DATA=Disabled"

:remember_task_save
set "OV#TASK;%~1;=%CURRENT_SETTING%;TASK;%ORIG_DATA%"
set "NEW_OV=OV#TASK;%~1;"
set "SAVE_NEEDED=1"
exit /b 0


:remember_feature
REM %1 = optional feature name. Saved only while it is on, which is the
REM only state the script changes.
set "NEW_OV="
if not defined CURRENT_SETTING exit /b 0
set "OV#FEATURE;%~1;" >nul 2>&1
if not errorlevel 1 exit /b 0
set "OV#FEATURE;%~1;=%CURRENT_SETTING%;FEATURE;Enabled"
set "NEW_OV=OV#FEATURE;%~1;"
set "SAVE_NEEDED=1"
exit /b 0


:remember_timezone
set "NEW_OV="
if not defined CURRENT_SETTING exit /b 0
set "OV#TZ;TimeZone;" >nul 2>&1
if not errorlevel 1 exit /b 0
set "ORIG_DATA="
for /f "delims=" %%T in ('%TZUTIL% /g') do set "ORIG_DATA=%%T"
if not defined ORIG_DATA exit /b 0
call :check_safe ORIG_DATA
if errorlevel 1 exit /b 0
set "OV#TZ;TimeZone;=%CURRENT_SETTING%;TZ;%ORIG_DATA%"
set "SAVE_NEEDED=1"
exit /b 0


:forget_new_value
REM The change just failed, so the earlier value saved for it describes
REM nothing this script changed. Keeping it would make R and U try, and
REM fail, to put it back.
if defined NEW_OV set "%NEW_OV%="
set "NEW_OV="
exit /b 0


:put_back_setting
REM %1 = setting name. Puts back every earlier value saved for it. Nothing
REM is changed when the script never changed this setting.
set "PUT_BACK_COUNT=0"
for /f "tokens=1,* delims==" %%A in ('set OV# 2^>nul') do call :put_back_entry "%%A" "%%B" %~1
if %PUT_BACK_COUNT% EQU 0 Echo   Nothing to put back
exit /b 0


:put_back_entry
REM %1 = entry name, %2 = SETTING;TYPE;DATA, %3 = setting being put back
set "ENTRY_SETTING="
set "ENTRY_TYPE="
set "ENTRY_DATA="
for /f "tokens=1,2,* delims=;" %%S in ("%~2") do (
    set "ENTRY_SETTING=%%S"
    set "ENTRY_TYPE=%%T"
    set "ENTRY_DATA=%%U"
)
if /i not "%ENTRY_SETTING%"=="%~3" exit /b 0
set "ENTRY=%~1"
set "ENTRY_LOC="
set "ENTRY_NAME="
for /f "tokens=1,2 delims=;" %%L in ("%ENTRY:~3%") do (
    set "ENTRY_LOC=%%L"
    set "ENTRY_NAME=%%M"
)
call :allowed_entry
if errorlevel 1 goto put_back_not_allowed
if /i "%ENTRY_LOC%"=="SVC" goto put_back_service
if /i "%ENTRY_LOC%"=="FEATURE" goto put_back_feature
if /i "%ENTRY_LOC%"=="TASK" goto put_back_task
if /i "%ENTRY_LOC%"=="TZ" goto put_back_timezone
call :id_to_key "%ENTRY_LOC%"
if not defined KEY exit /b 0
REM An adapter removed since has no key left; writing one would leave a stub.
if /i "%ENTRY_NAME%"=="NetbiosOptions" %REG% QUERY "%KEY%" >nul 2>&1 || goto put_back_done
if /i "%ENTRY_NAME%"=="AllowNewsAndInterests" goto put_back_dsh
if "%ENTRY_TYPE%"=="-" goto put_back_delete
set "TYPE_OK="
for %%T in (REG_SZ REG_EXPAND_SZ REG_MULTI_SZ REG_DWORD REG_QWORD REG_BINARY) do if /i "%ENTRY_TYPE%"=="%%T" set "TYPE_OK=1"
if not defined TYPE_OK goto put_back_not_allowed
call :write_value "%KEY%" "%ENTRY_NAME%" %ENTRY_TYPE% "%ENTRY_DATA%"
goto put_back_done

:put_back_delete
call :delete_value "%KEY%" "%ENTRY_NAME%"
goto put_back_done

:put_back_dsh
REM Windows can block changes to this value even for administrators, and
REM gpedit can still change it, so a blocked put-back is only a note.
if "%ENTRY_TYPE%"=="-" goto put_back_dsh_delete
%REG% ADD "%KEY%" /v "%ENTRY_NAME%" /t %ENTRY_TYPE% /d "%ENTRY_DATA%" /f >nul 2>&1
if errorlevel 1 goto put_back_dsh_blocked
Echo   Put back %KEY%\%ENTRY_NAME% = %ENTRY_DATA%
goto put_back_done

:put_back_dsh_delete
%REG% QUERY "%KEY%" /v "%ENTRY_NAME%" >nul 2>&1
if errorlevel 1 goto put_back_done
%REG% DELETE "%KEY%" /v "%ENTRY_NAME%" /f >nul 2>&1
if errorlevel 1 goto put_back_dsh_blocked
Echo   Removed  %KEY%\%ENTRY_NAME%
goto put_back_done

:put_back_dsh_blocked
call :note "Windows blocked putting back %ENTRY_NAME%. To turn widgets back on, set Allow widgets to Not Configured in gpedit.msc"
goto put_back_done

:put_back_service
if defined OFFLINE goto put_back_service_offline
set "SC_START="
if "%ENTRY_DATA%"=="2" set "SC_START=auto"
if "%ENTRY_DATA%"=="2d" set "SC_START=delayed-auto"
if "%ENTRY_DATA%"=="3" set "SC_START=demand"
if "%ENTRY_DATA%"=="4" set "SC_START=disabled"
if not defined SC_START goto put_back_done
REM A Windows update can remove a service; there is then nothing to put back.
%SC% query "%ENTRY_NAME%" >nul 2>&1
if errorlevel 1 (
    call :note "Service %ENTRY_NAME% no longer exists, so there is nothing to put back"
    goto put_back_done
)
%SC% config "%ENTRY_NAME%" start= %SC_START% >nul 2>&1
if errorlevel 1 goto put_back_failed
Echo   Put back service %ENTRY_NAME% start type = %SC_START%
if /i "%SC_START%"=="auto" %SC% start "%ENTRY_NAME%" >nul 2>&1
if /i "%SC_START%"=="delayed-auto" %SC% start "%ENTRY_NAME%" >nul 2>&1
goto put_back_done

:put_back_service_offline
REM Only the start types this script saves are accepted.
set "START_OK="
for %%V in (2 2d 3 4) do if "%ENTRY_DATA%"=="%%V" set "START_OK=1"
if not defined START_OK goto put_back_not_allowed
%REG% QUERY "%SYS%\Services\%ENTRY_NAME%" >nul 2>&1
if errorlevel 1 (
    call :note "Service %ENTRY_NAME% no longer exists, so there is nothing to put back"
    goto put_back_done
)
call :set_dword "%SYS%\Services\%ENTRY_NAME%" Start %ENTRY_DATA:~0,1%
if "%ENTRY_DATA%"=="2d" call :set_dword "%SYS%\Services\%ENTRY_NAME%" DelayedAutostart 1
goto put_back_done

:put_back_task
if defined OFFLINE (
    Echo   Skipped  task %ENTRY_NAME% - needs the installation running
    exit /b 0
)
REM A Windows update can remove a task; there is then nothing to put back.
%SCHTASKS% /Query /TN "%ENTRY_NAME%" >nul 2>&1
if errorlevel 1 (
    call :note "Task %ENTRY_NAME% no longer exists, so there is nothing to put back"
    goto put_back_done
)
set "TASK_SWITCH=/Enable"
if /i "%ENTRY_DATA%"=="Disabled" set "TASK_SWITCH=/Disable"
%SCHTASKS% /Change /TN "%ENTRY_NAME%" %TASK_SWITCH% >nul 2>&1
if errorlevel 1 goto put_back_failed
Echo   Put back task %ENTRY_NAME% %TASK_SWITCH%
goto put_back_done

:put_back_timezone
if defined OFFLINE (
    Echo   Skipped  time zone - needs the installation running
    exit /b 0
)
%TZUTIL% /s "%ENTRY_DATA%" >nul 2>&1
if errorlevel 1 goto put_back_failed
Echo   Put back time zone %ENTRY_DATA%
goto put_back_done

:put_back_feature
if defined OFFLINE (
    Echo   Skipped  feature %ENTRY_NAME% - needs the installation running
    exit /b 0
)
Echo   Working  turning the %ENTRY_NAME% feature back on - this can take a few minutes
%DISM% /Online /English /Enable-Feature /FeatureName:%ENTRY_NAME% /NoRestart /Quiet >nul 2>&1
if errorlevel 3011 goto put_back_failed
if errorlevel 3010 goto put_back_feature_done
if errorlevel 1 goto put_back_failed

:put_back_feature_done
Echo   Put back feature %ENTRY_NAME% - restart to finish
goto put_back_done

:put_back_not_allowed
call :note "Ignored a saved value for %ENTRY_NAME% - that location is not one this script changes"
set "%~1="
set "SAVE_NEEDED=1"
exit /b 0

:put_back_failed
call :fail "put back %ENTRY_LOC% %ENTRY_NAME%"
exit /b 0

:put_back_done
set "%~1="
set /a PUT_BACK_COUNT+=1
set "SAVE_NEEDED=1"
exit /b 0


:allowed_entry
REM Uses ENTRY_LOC and ENTRY_NAME. Returns 0 when the saved entry is in a
REM location this script changes.
if /i "%ENTRY_LOC%"=="TZ" exit /b 0
if /i "%ENTRY_LOC%"=="TASK" goto allowed_task
if /i "%ENTRY_LOC%"=="FEATURE" goto allowed_feature
if /i "%ENTRY_LOC%"=="SVC" goto allowed_service
set "CHECK_TEXT=%ENTRY_LOC%;%ENTRY_NAME%"
for %%P in (%ALLOWED_REG%) do call :starts_with "%%~P" && exit /b 0
call :starts_with "SYS\Services\NetBT\Parameters\Interfaces\Tcpip_"
if not errorlevel 1 if /i "%ENTRY_NAME%"=="NetbiosOptions" exit /b 0
exit /b 1

:allowed_task
set "CHECK_TEXT=%ENTRY_NAME%"
call :starts_with "\Microsoft\Windows\"
exit /b %errorlevel%

:allowed_service
for %%S in (%ALLOWED_SERVICES%) do if /i "%%S"=="%ENTRY_NAME%" exit /b 0
exit /b 1

:allowed_feature
if /i "%ENTRY_NAME%"=="Recall" exit /b 0
exit /b 1


:starts_with
REM %1 = prefix. Returns 0 when CHECK_TEXT starts with it.
set "PREFIX=%~1"
call set "REST=%%CHECK_TEXT:*%PREFIX%=%%"
if /i "%PREFIX%%REST%"=="%CHECK_TEXT%" exit /b 0
exit /b 1


REM ==========================================================================
REM  Settings: apply, and restore to the Windows default
REM  %SW%, %SYS% and %CU% point at the running Windows or the offline one.
REM ==========================================================================

:apply_TELEMETRY
REM On Windows 7/8.1, DiagTrack exists only if the telemetry updates
REM (KB3080149 and related) were installed. Missing services are skipped.
call :disable_service DiagTrack
call :set_dword "%SW%\Policies\Microsoft\SQMClient\Windows" CEIPEnable 0
call :disable_task "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator"
call :disable_task "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip"
call :disable_task "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask"
call :disable_task "\Microsoft\Windows\Application Experience\ProgramDataUpdater"
call :disable_task "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser"
call :disable_task "\Microsoft\Windows\Autochk\Proxy"
call :note "The compatibility appraiser feeds upgrade checks; feature upgrades may be offered later"
if %BUILD% LSS 10240 exit /b 0
call :set_dword "%SW%\Policies\Microsoft\Windows\DataCollection" AllowTelemetry 0
if not defined IS_ENTERPRISE call :note "%EDITION% treats AllowTelemetry 0 as 1, Required - the lowest level it allows"
call :set_dword "%SW%\Policies\Microsoft\Windows\DataCollection" DoNotShowFeedbackNotifications 1
call :set_dword "%CU%\SOFTWARE\Microsoft\Siuf\Rules" NumberOfSIUFInPeriod 0
exit /b 0

:restore_TELEMETRY
call :restore_service DiagTrack auto
call :delete_value "%SW%\Policies\Microsoft\SQMClient\Windows" CEIPEnable
call :enable_task "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator"
call :enable_task "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip"
call :enable_task "\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask"
call :enable_task "\Microsoft\Windows\Application Experience\ProgramDataUpdater"
call :enable_task "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser"
call :enable_task "\Microsoft\Windows\Autochk\Proxy"
call :delete_value "%SW%\Policies\Microsoft\Windows\DataCollection" AllowTelemetry
call :delete_value "%SW%\Policies\Microsoft\Windows\DataCollection" DoNotShowFeedbackNotifications
call :delete_value "%CU%\SOFTWARE\Microsoft\Siuf\Rules" NumberOfSIUFInPeriod
exit /b 0


:apply_PUSH_SERVICE
REM dmwappushservice is needed for MDM/Intune enrollment and management.
%REG% QUERY "%SW%\Microsoft\Enrollments" /s /v ProviderID 2>nul | %FINDSTR% /i /c:"MS DM Server" >nul
if not errorlevel 1 (
    call :note "This PC is enrolled in Intune or another MDM, so the push service was left on"
    exit /b 0
)
call :disable_service dmwappushservice
exit /b 0

:restore_PUSH_SERVICE
call :restore_service dmwappushservice demand
exit /b 0


:apply_ADVERTISING_ID
call :set_dword "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" Enabled 0
call :delete_value "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" Id
call :set_dword "%SW%\Policies\Microsoft\Windows\AdvertisingInfo" DisabledByGroupPolicy 1
exit /b 0

:restore_ADVERTISING_ID
call :set_dword "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo" Enabled 1
call :delete_value "%SW%\Policies\Microsoft\Windows\AdvertisingInfo" DisabledByGroupPolicy
exit /b 0


:apply_TAILORED_EXPERIENCES
call :set_dword "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" TailoredExperiencesWithDiagnosticDataEnabled 0
call :set_dword "%CU%\SOFTWARE\Policies\Microsoft\Windows\CloudContent" DisableTailoredExperiencesWithDiagnosticData 1
exit /b 0

:restore_TAILORED_EXPERIENCES
call :set_dword "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy" TailoredExperiencesWithDiagnosticDataEnabled 1
call :delete_value "%CU%\SOFTWARE\Policies\Microsoft\Windows\CloudContent" DisableTailoredExperiencesWithDiagnosticData
exit /b 0


:apply_ACTIVITY_HISTORY
call :set_dword "%SW%\Policies\Microsoft\Windows\System" EnableActivityFeed 0
call :set_dword "%SW%\Policies\Microsoft\Windows\System" PublishUserActivities 0
call :set_dword "%SW%\Policies\Microsoft\Windows\System" UploadUserActivities 0
exit /b 0

:restore_ACTIVITY_HISTORY
call :delete_value "%SW%\Policies\Microsoft\Windows\System" EnableActivityFeed
call :delete_value "%SW%\Policies\Microsoft\Windows\System" PublishUserActivities
call :delete_value "%SW%\Policies\Microsoft\Windows\System" UploadUserActivities
exit /b 0


:apply_WEB_SEARCH
REM The first three apply to Windows 10 up to 1909. The policy value is
REM what disables web results in Start search on Windows 10 2004+ and 11.
call :set_dword "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" BingSearchEnabled 0
call :set_dword "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" CortanaConsent 0
call :set_dword "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" AllowSearchToUseLocation 0
call :set_dword "%CU%\SOFTWARE\Policies\Microsoft\Windows\Explorer" DisableSearchBoxSuggestions 1
exit /b 0

:restore_WEB_SEARCH
call :delete_value "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" BingSearchEnabled
call :delete_value "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" CortanaConsent
call :delete_value "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\Search" AllowSearchToUseLocation
call :delete_value "%CU%\SOFTWARE\Policies\Microsoft\Windows\Explorer" DisableSearchBoxSuggestions
exit /b 0


:apply_SUGGESTED_CONTENT
set "CDM=%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
call :set_dword "%CDM%" SilentInstalledAppsEnabled 0
call :set_dword "%CDM%" SystemPaneSuggestionsEnabled 0
call :set_dword "%CDM%" SubscribedContent-338388Enabled 0
call :set_dword "%CDM%" SubscribedContent-338389Enabled 0
call :set_dword "%CDM%" SubscribedContent-353694Enabled 0
call :set_dword "%CDM%" SubscribedContent-353696Enabled 0
call :set_dword "%CDM%" RotatingLockScreenEnabled 0
call :set_dword "%CDM%" RotatingLockScreenOverlayEnabled 0
call :set_dword "%SW%\Policies\Microsoft\Windows\CloudContent" DisableWindowsConsumerFeatures 1
call :set_dword "%CU%\SOFTWARE\Policies\Microsoft\Windows\CloudContent" DisableWindowsSpotlightFeatures 1
if not defined IS_ENTERPRISE call :note "%EDITION% ignores the two CloudContent policies; the other values above still apply"
exit /b 0

:restore_SUGGESTED_CONTENT
set "CDM=%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
call :delete_value "%CDM%" SilentInstalledAppsEnabled
call :delete_value "%CDM%" SystemPaneSuggestionsEnabled
call :delete_value "%CDM%" SubscribedContent-338388Enabled
call :delete_value "%CDM%" SubscribedContent-338389Enabled
call :delete_value "%CDM%" SubscribedContent-353694Enabled
call :delete_value "%CDM%" SubscribedContent-353696Enabled
call :delete_value "%CDM%" RotatingLockScreenEnabled
call :delete_value "%CDM%" RotatingLockScreenOverlayEnabled
call :delete_value "%SW%\Policies\Microsoft\Windows\CloudContent" DisableWindowsConsumerFeatures
call :delete_value "%CU%\SOFTWARE\Policies\Microsoft\Windows\CloudContent" DisableWindowsSpotlightFeatures
exit /b 0


:apply_LANGUAGE_LIST
call :set_dword "%CU%\Control Panel\International\User Profile" HttpAcceptLanguageOptOut 1
exit /b 0

:restore_LANGUAGE_LIST
call :delete_value "%CU%\Control Panel\International\User Profile" HttpAcceptLanguageOptOut
exit /b 0


:apply_INPUT_PERSONALIZATION
call :set_dword "%CU%\SOFTWARE\Microsoft\InputPersonalization" RestrictImplicitTextCollection 1
call :set_dword "%CU%\SOFTWARE\Microsoft\InputPersonalization" RestrictImplicitInkCollection 1
call :set_dword "%CU%\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" HarvestContacts 0
if %BUILD% LSS 10240 exit /b 0
call :set_dword "%CU%\SOFTWARE\Microsoft\Personalization\Settings" AcceptedPrivacyPolicy 0
call :set_dword "%SW%\Policies\Microsoft\InputPersonalization" AllowInputPersonalization 0
exit /b 0

:restore_INPUT_PERSONALIZATION
call :set_dword "%CU%\SOFTWARE\Microsoft\InputPersonalization" RestrictImplicitTextCollection 0
call :set_dword "%CU%\SOFTWARE\Microsoft\InputPersonalization" RestrictImplicitInkCollection 0
call :set_dword "%CU%\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore" HarvestContacts 1
call :delete_value "%CU%\SOFTWARE\Microsoft\Personalization\Settings" AcceptedPrivacyPolicy
call :delete_value "%SW%\Policies\Microsoft\InputPersonalization" AllowInputPersonalization
exit /b 0


:apply_ONLINE_SPEECH
call :set_dword "%CU%\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" HasAccepted 0
exit /b 0

:restore_ONLINE_SPEECH
REM Removing the value makes Windows ask again instead of accepting for the user.
call :delete_value "%CU%\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" HasAccepted
exit /b 0


:apply_HANDWRITING_SHARING
call :set_dword "%SW%\Policies\Microsoft\Windows\TabletPC" PreventHandwritingDataSharing 1
call :set_dword "%SW%\Policies\Microsoft\Windows\HandwritingErrorReports" PreventHandwritingErrorReports 1
exit /b 0

:restore_HANDWRITING_SHARING
call :delete_value "%SW%\Policies\Microsoft\Windows\TabletPC" PreventHandwritingDataSharing
call :delete_value "%SW%\Policies\Microsoft\Windows\HandwritingErrorReports" PreventHandwritingErrorReports
exit /b 0


:apply_LOCATION
REM Set the saved time zone first, then stop Windows from changing it
REM based on location. tzautoupdate is the "Set time zone automatically"
REM switch; it does not exist on Windows 7 and is skipped there.
REM At sign-in the zone is left alone, so a zone changed by hand while
REM traveling is not reset.
if defined TIMEZONE if not defined UNATTENDED call :set_timezone
if not defined TIMEZONE call :note "No time zone saved - the current one stays until you change it by hand"
call :disable_service tzautoupdate
call :set_dword "%SW%\Policies\Microsoft\Windows\LocationAndSensors" DisableLocation 1
if %BUILD% LSS 10240 exit /b 0
call :set_dword "%SW%\Policies\Microsoft\Windows\AppPrivacy" LetAppsAccessLocation 2
exit /b 0

:restore_LOCATION
call :restore_service tzautoupdate demand
call :delete_value "%SW%\Policies\Microsoft\Windows\LocationAndSensors" DisableLocation
call :delete_value "%SW%\Policies\Microsoft\Windows\AppPrivacy" LetAppsAccessLocation
exit /b 0


:apply_CALL_HISTORY
call :set_dword "%SW%\Policies\Microsoft\Windows\AppPrivacy" LetAppsAccessCallHistory 2
exit /b 0

:restore_CALL_HISTORY
call :delete_value "%SW%\Policies\Microsoft\Windows\AppPrivacy" LetAppsAccessCallHistory
exit /b 0


:apply_PHONE_LINK
call :set_dword "%SW%\Policies\Microsoft\Windows\System" EnableMmx 0
exit /b 0

:restore_PHONE_LINK
call :delete_value "%SW%\Policies\Microsoft\Windows\System" EnableMmx
exit /b 0


:apply_FIND_MY_DEVICE
call :set_dword "%SW%\Policies\Microsoft\FindMyDevice" AllowFindMyDevice 0
exit /b 0

:restore_FIND_MY_DEVICE
call :delete_value "%SW%\Policies\Microsoft\FindMyDevice" AllowFindMyDevice
exit /b 0


:apply_CLIPBOARD_HISTORY
call :set_dword "%SW%\Policies\Microsoft\Windows\System" AllowClipboardHistory 0
exit /b 0

:restore_CLIPBOARD_HISTORY
call :delete_value "%SW%\Policies\Microsoft\Windows\System" AllowClipboardHistory
exit /b 0


:apply_CLIPBOARD_SYNC
call :set_dword "%SW%\Policies\Microsoft\Windows\System" AllowCrossDeviceClipboard 0
exit /b 0

:restore_CLIPBOARD_SYNC
call :delete_value "%SW%\Policies\Microsoft\Windows\System" AllowCrossDeviceClipboard
exit /b 0


:apply_ERROR_REPORTING
call :set_dword "%SW%\Policies\Microsoft\Windows\Windows Error Reporting" Disabled 1
exit /b 0

:restore_ERROR_REPORTING
call :delete_value "%SW%\Policies\Microsoft\Windows\Windows Error Reporting" Disabled
exit /b 0


:apply_CLOUD_SEARCH
call :set_dword "%SW%\Policies\Microsoft\Windows\Windows Search" AllowCloudSearch 0
call :set_dword "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings" IsMSACloudSearchEnabled 0
call :set_dword "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings" IsAADCloudSearchEnabled 0
exit /b 0

:restore_CLOUD_SEARCH
call :delete_value "%SW%\Policies\Microsoft\Windows\Windows Search" AllowCloudSearch
call :delete_value "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings" IsMSACloudSearchEnabled
call :delete_value "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings" IsAADCloudSearchEnabled
exit /b 0


:apply_SEARCH_HIGHLIGHTS
call :set_dword "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings" IsDynamicSearchBoxEnabled 0
call :set_dword "%SW%\Policies\Microsoft\Windows\Windows Search" EnableDynamicContentInWSB 0
exit /b 0

:restore_SEARCH_HIGHLIGHTS
call :delete_value "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings" IsDynamicSearchBoxEnabled
call :delete_value "%SW%\Policies\Microsoft\Windows\Windows Search" EnableDynamicContentInWSB
exit /b 0


:apply_APP_LAUNCH_TRACKING
call :set_dword "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" Start_TrackProgs 0
exit /b 0

:restore_APP_LAUNCH_TRACKING
call :delete_value "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" Start_TrackProgs
exit /b 0


:apply_RECENT_FILES
REM Recent files in Start, Jump Lists and File Explorer Quick Access.
set "EXPLORER=%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer"
call :set_dword "%EXPLORER%\Advanced" Start_TrackDocs 0
if %BUILD% LSS 10240 exit /b 0
call :set_dword "%EXPLORER%" ShowRecent 0
call :set_dword "%EXPLORER%" ShowFrequent 0
call :set_dword "%EXPLORER%" ShowCloudFilesInQuickAccess 0
exit /b 0

:restore_RECENT_FILES
set "EXPLORER=%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer"
call :delete_value "%EXPLORER%\Advanced" Start_TrackDocs
call :delete_value "%EXPLORER%" ShowRecent
call :delete_value "%EXPLORER%" ShowFrequent
call :delete_value "%EXPLORER%" ShowCloudFilesInQuickAccess
exit /b 0


:apply_START_RECOMMENDATIONS
call :set_dword "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" Start_IrisRecommendations 0
exit /b 0

:restore_START_RECOMMENDATIONS
call :delete_value "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" Start_IrisRecommendations
exit /b 0


:apply_WIDGETS
REM Windows 10 calls it News and Interests; Windows 11 calls it Widgets.
if %BUILD% LSS 22000 (
    call :set_dword "%SW%\Policies\Microsoft\Windows\Windows Feeds" EnableFeeds 0
    exit /b 0
)
set "DSH_KEY=%SW%\Policies\Microsoft\Dsh"
REM Already set, for example through the Group Policy editor.
%REG% QUERY "%DSH_KEY%" /v AllowNewsAndInterests 2>nul | %FINDSTR% /i /r /c:"AllowNewsAndInterests  *REG_DWORD  *0x0$" >nul
if not errorlevel 1 (
    Echo   Already  %DSH_KEY%\AllowNewsAndInterests = 0
    exit /b 0
)
REM If Windows blocks the write nothing changes, so an earlier value saved
REM only for this attempt is dropped again. R and U would otherwise try,
REM and fail, to put it back.
call :key_id "%DSH_KEY%"
set "DSH_SAVED="
set "OV#%KEY_ID%;AllowNewsAndInterests;" >nul 2>&1 && set "DSH_SAVED=1"
call :remember_value "%DSH_KEY%" AllowNewsAndInterests
%REG% ADD "%DSH_KEY%" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f >nul 2>&1
if not errorlevel 1 (
    Echo   Set      %DSH_KEY%\AllowNewsAndInterests = 0
    exit /b 0
)
if not defined DSH_SAVED set "OV#%KEY_ID%;AllowNewsAndInterests;="
REM The User Choice Protection Driver blocks this value on recent Windows 11
REM builds, even for administrators. It is a note, not a failure, so the
REM reapply task does not report it at every sign-in.
if defined IS_HOME (
    call :note "Windows blocked AllowNewsAndInterests - turn off Widgets in Settings, Personalization, Taskbar"
) else (
    call :note "Windows blocked AllowNewsAndInterests - set it in gpedit.msc: Windows Components, Widgets, Allow widgets = Disabled"
)
exit /b 0

:restore_WIDGETS
call :delete_value "%SW%\Policies\Microsoft\Windows\Windows Feeds" EnableFeeds
REM Windows can block this value even for administrators; gpedit can still
REM change it, so a blocked removal is a note, not a failure.
%REG% QUERY "%SW%\Policies\Microsoft\Dsh" /v AllowNewsAndInterests >nul 2>&1
if errorlevel 1 exit /b 0
%REG% DELETE "%SW%\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /f >nul 2>&1
if errorlevel 1 (
    call :note "Windows blocked removing AllowNewsAndInterests - set Allow widgets to Not Configured in gpedit.msc"
) else (
    Echo   Removed  %SW%\Policies\Microsoft\Dsh\AllowNewsAndInterests
)
exit /b 0


:apply_SETTINGS_SYNC
call :set_dword "%SW%\Policies\Microsoft\Windows\SettingSync" DisableSettingSync 2
call :set_dword "%SW%\Policies\Microsoft\Windows\SettingSync" DisableSettingSyncUserOverride 1
exit /b 0

:restore_SETTINGS_SYNC
call :delete_value "%SW%\Policies\Microsoft\Windows\SettingSync" DisableSettingSync
call :delete_value "%SW%\Policies\Microsoft\Windows\SettingSync" DisableSettingSyncUserOverride
exit /b 0


:apply_DELIVERY_OPTIMIZATION
REM 1 = download from and share with PCs on the local network only.
call :set_dword "%SW%\Policies\Microsoft\Windows\DeliveryOptimization" DODownloadMode 1
exit /b 0

:restore_DELIVERY_OPTIMIZATION
call :delete_value "%SW%\Policies\Microsoft\Windows\DeliveryOptimization" DODownloadMode
exit /b 0


:apply_EDGE_DIAGNOSTICS
REM Edge will show "Managed by your organization" while these are set.
call :set_dword "%SW%\Policies\Microsoft\Edge" DiagnosticData 0
call :set_dword "%SW%\Policies\Microsoft\Edge" PersonalizationReportingEnabled 0
exit /b 0

:restore_EDGE_DIAGNOSTICS
call :delete_value "%SW%\Policies\Microsoft\Edge" DiagnosticData
call :delete_value "%SW%\Policies\Microsoft\Edge" PersonalizationReportingEnabled
exit /b 0


:apply_RECALL
REM DisableAIDataAnalysis stops snapshots. AllowRecallEnablement 0 means
REM Recall can never be turned on and Windows removes it. The optional
REM feature is also turned off now, rather than waiting for Windows.
call :set_dword "%CU%\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" DisableAIDataAnalysis 1
call :set_dword "%SW%\Policies\Microsoft\Windows\WindowsAI" DisableAIDataAnalysis 1
call :set_dword "%SW%\Policies\Microsoft\Windows\WindowsAI" AllowRecallEnablement 0
call :disable_feature Recall
exit /b 0

:restore_RECALL
call :delete_value "%CU%\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" DisableAIDataAnalysis
call :delete_value "%SW%\Policies\Microsoft\Windows\WindowsAI" DisableAIDataAnalysis
call :delete_value "%SW%\Policies\Microsoft\Windows\WindowsAI" AllowRecallEnablement
call :note "The Recall feature stays off. To turn it on: Dism /Online /Enable-Feature /FeatureName:Recall"
exit /b 0


:apply_OFFICE_TELEMETRY
REM 16.0 covers Office 2016, 2019, 2021, 2024 and Microsoft 365 Apps.
REM SendTelemetry 3 = send neither required nor optional diagnostic data.
set "OFFICE=%CU%\SOFTWARE\Policies\Microsoft\Office"
call :set_dword "%OFFICE%\Common\ClientTelemetry" SendTelemetry 3
call :set_dword "%OFFICE%\16.0\Common\ClientTelemetry" SendTelemetry 3
call :set_dword "%OFFICE%\16.0\Common\ClientTelemetry" DisableTelemetry 1
call :set_dword "%OFFICE%\16.0\Common\Feedback" Enabled 0
call :set_dword "%OFFICE%\16.0\Common\Feedback" SurveyEnabled 0
exit /b 0

:restore_OFFICE_TELEMETRY
set "OFFICE=%CU%\SOFTWARE\Policies\Microsoft\Office"
call :delete_value "%OFFICE%\Common\ClientTelemetry" SendTelemetry
call :delete_value "%OFFICE%\16.0\Common\ClientTelemetry" SendTelemetry
call :delete_value "%OFFICE%\16.0\Common\ClientTelemetry" DisableTelemetry
call :delete_value "%OFFICE%\16.0\Common\Feedback" Enabled
call :delete_value "%OFFICE%\16.0\Common\Feedback" SurveyEnabled
exit /b 0


:apply_OFFICE_CONNECTED
REM 2 = disabled. Turns off features that send document content to
REM Microsoft, such as Designer, Editor, online pictures and translation.
set "PRIVACY=%CU%\SOFTWARE\Policies\Microsoft\Office\16.0\Common\Privacy"
call :set_dword "%PRIVACY%" usercontentdisabled 2
call :set_dword "%PRIVACY%" downloadcontentdisabled 2
call :set_dword "%PRIVACY%" controllerconnectedservicesenabled 2
exit /b 0

:restore_OFFICE_CONNECTED
set "PRIVACY=%CU%\SOFTWARE\Policies\Microsoft\Office\16.0\Common\Privacy"
call :delete_value "%PRIVACY%" usercontentdisabled
call :delete_value "%PRIVACY%" downloadcontentdisabled
call :delete_value "%PRIVACY%" controllerconnectedservicesenabled
exit /b 0


:apply_DEV_TOOLS_TELEMETRY
REM System environment variables take effect after sign-out or restart.
set "ENV=%SYS%\Control\Session Manager\Environment"
call :set_string "%ENV%" DOTNET_CLI_TELEMETRY_OPTOUT 1
call :set_string "%ENV%" POWERSHELL_TELEMETRY_OPTOUT 1
call :set_dword "%SW%\Policies\Microsoft\VisualStudio\SQM" OptIn 0
exit /b 0

:restore_DEV_TOOLS_TELEMETRY
set "ENV=%SYS%\Control\Session Manager\Environment"
call :delete_value "%ENV%" DOTNET_CLI_TELEMETRY_OPTOUT
call :delete_value "%ENV%" POWERSHELL_TELEMETRY_OPTOUT
call :delete_value "%SW%\Policies\Microsoft\VisualStudio\SQM" OptIn
exit /b 0


:apply_ONEDRIVE_REMOVE
REM If Desktop, Documents or Pictures were moved into OneDrive, removing it
REM leaves those folders pointing into the OneDrive folder and files that
REM were only in the cloud can no longer be opened from this PC.
call :onedrive_folders_moved
if not errorlevel 1 (
    call :fail "OneDrive not removed: Desktop, Documents or Pictures are inside OneDrive. Stop folder backup in OneDrive settings first"
    exit /b 0
)
call :onedrive_signed_in
if not errorlevel 1 (
    call :fail "OneDrive not removed: it is signed in. Make sure every file you need is on this PC, sign out in OneDrive settings, then apply again"
    exit /b 0
)
call :set_dword "%SW%\Policies\Microsoft\Windows\OneDrive" DisableFileSyncNGSC 1
if defined OFFLINE (
    Echo   Skipped  OneDrive uninstall - needs the installation running
    exit /b 0
)
call :note "The OneDrive block applies to every account on this PC, not only this one"
REM Only this account's OneDrive is stopped; other signed-in accounts may be
REM in the middle of a sync.
if not "%CU_USER%"=="current" %TASKKILL% /f /im OneDrive.exe /fi "USERNAME eq %CU_USER%" >nul 2>&1
call :find_winget
if not defined WINGET goto onedrive_setup_exe
"%WINGET%" list --id Microsoft.OneDrive -e --accept-source-agreements >nul 2>&1
if errorlevel 1 (
    Echo   Skipped  OneDrive - not installed
    exit /b 0
)
"%WINGET%" uninstall --id Microsoft.OneDrive -e --silent --accept-source-agreements >nul 2>&1
if errorlevel 1 goto onedrive_setup_exe
Echo   Removed  OneDrive
exit /b 0

:onedrive_setup_exe
REM Fallback: OneDrive's own uninstaller from folders only administrators
REM can change.
set "ONEDRIVE_SETUP="
if exist "%SYS32%\OneDriveSetup.exe" set "ONEDRIVE_SETUP=%SYS32%\OneDriveSetup.exe"
if exist "%SystemRoot%\SysWOW64\OneDriveSetup.exe" set "ONEDRIVE_SETUP=%SystemRoot%\SysWOW64\OneDriveSetup.exe"
for /d %%D in ("%PROGRAM_FILES%\Microsoft OneDrive\*") do if exist "%%D\OneDriveSetup.exe" set "ONEDRIVE_SETUP=%%D\OneDriveSetup.exe"
if not defined ONEDRIVE_SETUP (
    call :fail "OneDrive uninstaller not found - remove it from Settings, Apps"
    exit /b 0
)
"%ONEDRIVE_SETUP%" /uninstall
Echo   Ran      OneDrive uninstaller
exit /b 0

:restore_ONEDRIVE_REMOVE
REM Only the block is removed. Reinstall OneDrive from Microsoft.
call :delete_value "%SW%\Policies\Microsoft\Windows\OneDrive" DisableFileSyncNGSC
exit /b 0


:apply_COPILOT_REMOVE
REM The policy covers Windows 11 23H2, where Copilot was built in.
call :set_dword "%CU%\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" TurnOffWindowsCopilot 1
call :remove_appx Microsoft.Copilot "Copilot app"
exit /b 0

:restore_COPILOT_REMOVE
REM Only the policy is removed. Reinstall Copilot from the Microsoft Store.
call :delete_value "%CU%\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" TurnOffWindowsCopilot
exit /b 0


:apply_OUTLOOK_REMOVE
REM Deleting OutlookUpdate stops Windows from reinstalling the new Outlook.
REM This key cannot be saved and put back. HideNewOutlookToggle removes
REM "Try the new Outlook" from classic Outlook.
call :remove_appx Microsoft.OutlookForWindows "New Outlook"
call :delete_key "%SW%\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate"
call :set_dword "%CU%\SOFTWARE\Policies\Microsoft\Office\16.0\Outlook\Options\General" HideNewOutlookToggle 1
exit /b 0

:restore_OUTLOOK_REMOVE
REM Only the toggle policy is removed. Reinstall from the Microsoft Store.
call :delete_value "%CU%\SOFTWARE\Policies\Microsoft\Office\16.0\Outlook\Options\General" HideNewOutlookToggle
exit /b 0


:apply_CONNECTIVITY_CHECK
REM Runs ncsi_rotate.ps1 from the installed folder as SYSTEM every few hours
REM and at startup. The earlier connectivity check values are saved first.
if defined OFFLINE (
    Echo   Skipped  rotation - needs the installation running
    exit /b 0
)
if not defined INSTALLED (
    call :fail "Connectivity rotation needs the installed copy - install with I first"
    exit /b 0
)
if not exist "%INSTALL_DIR%\scripts\ncsi_rotate.ps1" (
    call :fail "ncsi_rotate.ps1 is missing from %INSTALL_DIR%\scripts"
    exit /b 0
)
REM At sign-in the rotation is already running on its own schedule, and
REM testing every provider again would only slow the sign-in down.
if defined UNATTENDED %SCHTASKS% /Query /TN "%NCSI_TASK%" >nul 2>&1 && exit /b 0
set "NCSI_KEY=%SYS%\Services\NlaSvc\Parameters\Internet"
for %%V in (ActiveWebProbeHost ActiveWebProbePath ActiveWebProbeContent ActiveWebProbeHostV6 ActiveWebProbePathV6 ActiveWebProbeContentV6) do call :remember_value "%NCSI_KEY%" %%V
for %%V in (ActiveDnsProbeHost ActiveDnsProbeContent ActiveDnsProbeHostV6 ActiveDnsProbeContentV6) do call :remember_value "%NCSI_KEY%" %%V
REM A fixed DNS host set by the administrator replaces the DNS rotation.
REM Values edited into the config get the same checks as the C menu.
if defined NCSI_DNS_HOST call :valid_dns_host
if errorlevel 1 (
    call :fail "NCSI_DNS_HOST or NCSI_DNS_IP in the config is not a host name and IPv4 address - the DNS check was not changed"
    set "NCSI_DNS_HOST="
)
if defined NCSI_DNS_HOST if defined NCSI_DNS_IP (
    call :set_string "%NCSI_KEY%" ActiveDnsProbeHost "%NCSI_DNS_HOST%"
    call :set_string "%NCSI_KEY%" ActiveDnsProbeContent "%NCSI_DNS_IP%"
)
if exist "%INSTALL_DIR%\config\restore.signal" del /q "%INSTALL_DIR%\config\restore.signal"
REM Saving now puts the earlier values in the installed config before the
REM rotation script, which reads that config, first runs.
call :save_config

call :create_rotation_tasks
if errorlevel 1 goto ncsi_task_failed
Echo   Created  rotation tasks: every %HOURS% hours and at startup
Echo   Testing  connectivity check providers - this can take a minute
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -File "%INSTALL_DIR%\scripts\ncsi_rotate.ps1"
if errorlevel 1 call :fail "First rotation did not find a working provider - see logs\ncsi_rotate.log"
exit /b 0

:ncsi_task_failed
call :fail "Could not create the rotation tasks"
exit /b 0


:create_rotation_tasks
REM Creates or replaces both rotation tasks, using NCSI_ROTATE_HOURS. Sets
REM HOURS. Returns 1 when a task could not be created.
REM An invalid number such as 08 leaves the value unchanged, so start at 1.
set "HOURS=1"
set /a HOURS=NCSI_ROTATE_HOURS 2>nul
if %HOURS% LSS 1 set "HOURS=1"
if %HOURS% GTR 23 set "HOURS=23"
set "TASK_COMMAND=%POWERSHELL% -NoProfile -ExecutionPolicy Bypass -File \"%INSTALL_DIR%\scripts\ncsi_rotate.ps1\""
%SCHTASKS% /Create /TN "%NCSI_TASK%" /SC HOURLY /MO %HOURS% /RU SYSTEM /RL HIGHEST /TR "%TASK_COMMAND%" /F >nul 2>&1
if errorlevel 1 exit /b 1
%SCHTASKS% /Create /TN "%NCSI_TASK% at startup" /SC ONSTART /DELAY 0002:00 /RU SYSTEM /RL HIGHEST /TR "%TASK_COMMAND%" /F >nul 2>&1
if errorlevel 1 exit /b 1
REM schtasks makes tasks that do not start on battery power and are stopped
REM when the laptop unplugs. These settings let them run and stop a hung run
REM after 30 minutes. The tasks still work if this step fails.
%POWERSHELL% -NoProfile -Command "$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 30); foreach ($n in 'NCSI rotate', 'NCSI rotate at startup') { Set-ScheduledTask -TaskPath '\no_ms_spy\' -TaskName $n -Settings $s | Out-Null }" >nul 2>&1
exit /b 0


:update_rotation_tasks
REM Rotation tasks made before the folder layout run ncsi_rotate.ps1 from
REM the top folder, where it no longer is, so they are pointed at scripts.
if not defined INSTALLED exit /b 0
if defined OFFLINE exit /b 0
%SCHTASKS% /Query /TN "%NCSI_TASK%" >nul 2>&1
if errorlevel 1 exit /b 0
%POWERSHELL% -NoProfile -Command "$t = Get-ScheduledTask -TaskPath '\no_ms_spy\' -TaskName 'NCSI rotate' -ErrorAction SilentlyContinue; if ($t -and ($t.Actions.Arguments -like '*\scripts\ncsi_rotate.ps1*') -and -not $t.Settings.DisallowStartIfOnBatteries) { exit 0 } else { exit 1 }" >nul 2>&1
if not errorlevel 1 exit /b 0
call :create_rotation_tasks
if errorlevel 1 (
    call :notify_error "Could not update the connectivity rotation tasks"
    exit /b 0
)
call :log INFO "Rotation tasks updated to run scripts\ncsi_rotate.ps1, also on battery"
exit /b 0


:update_reapply_task
REM A reapply task made by an earlier version starts at every user's
REM sign-in and not on battery, so it is registered again for its user.
if not defined INSTALLED exit /b 0
if defined OFFLINE exit /b 0
if defined UNATTENDED exit /b 0
if exist "%INSTALL_DIR%\config\reapply_off.signal" exit /b 0
if %BUILD% LSS 9200 exit /b 0
set "RUN_AS="
for /f "delims=" %%U in ('%POWERSHELL% -NoProfile -Command "$t = Get-ScheduledTask -TaskPath '\no_ms_spy\' -TaskName 'Reapply at sign-in' -ErrorAction SilentlyContinue; if ($t -and (-not $t.Triggers[0].UserId -or $t.Settings.DisallowStartIfOnBatteries)) { $t.Principal.UserId }"') do set "RUN_AS=%%U"
if not defined RUN_AS exit /b 0
call :check_safe RUN_AS
if errorlevel 1 exit /b 0
call :create_reapply_task >nul
call :log INFO "Reapply task registered again for %RUN_AS%"
exit /b 0

:restore_CONNECTIVITY_CHECK
REM These are service parameters, not policies, so the defaults are written.
call :remove_rotation
set "NCSI_KEY=%SYS%\Services\NlaSvc\Parameters\Internet"
call :set_string "%NCSI_KEY%" ActiveWebProbeHost "www.msftconnecttest.com"
call :set_string "%NCSI_KEY%" ActiveWebProbePath "connecttest.txt"
call :set_string "%NCSI_KEY%" ActiveWebProbeContent "Microsoft Connect Test"
call :set_string "%NCSI_KEY%" ActiveWebProbeHostV6 "ipv6.msftconnecttest.com"
call :set_string "%NCSI_KEY%" ActiveWebProbePathV6 "connecttest.txt"
call :set_string "%NCSI_KEY%" ActiveWebProbeContentV6 "Microsoft Connect Test"
call :set_string "%NCSI_KEY%" ActiveDnsProbeHost "dns.msftncsi.com"
call :set_string "%NCSI_KEY%" ActiveDnsProbeContent "131.107.255.255"
call :set_string "%NCSI_KEY%" ActiveDnsProbeHostV6 "dns.msftncsi.com"
call :set_string "%NCSI_KEY%" ActiveDnsProbeContentV6 "fd3e:4f5a:5b81::1"
exit /b 0


:remove_rotation
REM Running Windows: stop a run in progress and delete the tasks now.
REM Offline Windows: write restore.signal, which makes ncsi_rotate.ps1 put
REM back the original values and delete its own tasks at the next start.
if defined OFFLINE goto remove_rotation_offline
REM Both tasks are deleted even if one of them is already gone.
set "TASKS_FOUND="
%SCHTASKS% /Query /TN "%NCSI_TASK%" >nul 2>&1
if not errorlevel 1 set "TASKS_FOUND=1"
%SCHTASKS% /Query /TN "%NCSI_TASK% at startup" >nul 2>&1
if not errorlevel 1 set "TASKS_FOUND=1"
if not defined TASKS_FOUND exit /b 0
%SCHTASKS% /End /TN "%NCSI_TASK%" >nul 2>&1
%SCHTASKS% /End /TN "%NCSI_TASK% at startup" >nul 2>&1
%SCHTASKS% /Delete /TN "%NCSI_TASK%" /F >nul 2>&1
%SCHTASKS% /Delete /TN "%NCSI_TASK% at startup" /F >nul 2>&1
Echo   Removed  connectivity rotation tasks
REM The rotation no longer runs, so its state file is not needed. Its log is
REM kept as a record.
if defined INSTALL_DIR if exist "%INSTALL_DIR%\config\ncsi_state.txt" del /q "%INSTALL_DIR%\config\ncsi_state.txt"
exit /b 0

:remove_rotation_offline
if not defined TARGET_INSTALL exit /b 0
if not exist "%TARGET_SCRIPT_DIR%\ncsi_rotate.ps1" exit /b 0
> "%TARGET_CONFIG_DIR%\restore.signal" Echo restore
if errorlevel 1 (
    call :fail "Could not write restore.signal to %TARGET_CONFIG_DIR%"
    exit /b 0
)
Echo   Signal   the rotation turns itself off at the next start of %TARGET%
exit /b 0


:apply_UPDATE_NOTIFY
REM 2 = notify before downloading. Updates still install when approved.
call :set_dword "%SW%\Policies\Microsoft\Windows\WindowsUpdate\AU" NoAutoUpdate 0
call :set_dword "%SW%\Policies\Microsoft\Windows\WindowsUpdate\AU" AUOptions 2
if defined IS_HOME call :note "Home edition may ignore this policy"
call :note "Security updates wait until someone approves them - check Windows Update regularly"
exit /b 0

:restore_UPDATE_NOTIFY
call :delete_value "%SW%\Policies\Microsoft\Windows\WindowsUpdate\AU" NoAutoUpdate
call :delete_value "%SW%\Policies\Microsoft\Windows\WindowsUpdate\AU" AUOptions
exit /b 0


:apply_ACTIVATION_VALIDATION
REM Only affects KMS (volume license) clients. Retail and digital
REM licenses are not changed.
call :set_dword "%SW%\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform" NoGenTicket 1
exit /b 0

:restore_ACTIVATION_VALIDATION
REM Left alone unless it was turned on in this script, so a policy set by
REM an organization for its KMS clients is never removed.
if not "%OPT_ACTIVATION_VALIDATION%"=="1" (
    Echo   Left alone - only changed when turned on in this script
    exit /b 0
)
call :delete_value "%SW%\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform" NoGenTicket
exit /b 0


:apply_DEFENDER_CLOUD
call :set_dword "%SW%\Policies\Microsoft\Windows Defender\Spynet" SpynetReporting 0
call :tamper_protection_on
if defined TAMPER call :note "Tamper Protection is on, so Defender ignores this setting. Turn it off in Windows Security first if you really want this"
exit /b 0

:restore_DEFENDER_CLOUD
call :delete_value "%SW%\Policies\Microsoft\Windows Defender\Spynet" SpynetReporting
exit /b 0


:apply_DEFENDER_SAMPLES
REM 0 = always prompt before sending a sample.
call :set_dword "%SW%\Policies\Microsoft\Windows Defender\Spynet" SubmitSamplesConsent 0
exit /b 0

:restore_DEFENDER_SAMPLES
call :delete_value "%SW%\Policies\Microsoft\Windows Defender\Spynet" SubmitSamplesConsent
exit /b 0


:apply_SMARTSCREEN
call :set_dword "%SW%\Policies\Microsoft\Windows\System" EnableSmartScreen 0
call :set_dword "%SW%\Policies\Microsoft\Edge" SmartScreenEnabled 0
exit /b 0

:restore_SMARTSCREEN
call :delete_value "%SW%\Policies\Microsoft\Windows\System" EnableSmartScreen
call :delete_value "%SW%\Policies\Microsoft\Edge" SmartScreenEnabled
exit /b 0


REM ---------- Advanced: local network chatter ----------

:apply_LLMNR
call :set_dword "%SW%\Policies\Microsoft\Windows NT\DNSClient" EnableMulticast 0
exit /b 0

:restore_LLMNR
call :delete_value "%SW%\Policies\Microsoft\Windows NT\DNSClient" EnableMulticast
exit /b 0


:apply_NETBIOS
REM 2 = disabled, 0 = use the DHCP server's setting (Windows default).
call :set_netbios 2
exit /b 0

:restore_NETBIOS
call :set_netbios 0
exit /b 0

:set_netbios
REM %1 = NetbiosOptions value for every network adapter present now.
set "NETBT=%SYS%\Services\NetBT\Parameters\Interfaces"
for /f "delims=" %%K in ('%REG% QUERY "%NETBT%" 2^>nul ^| %FINDSTR% /i /c:"Tcpip_"') do call :set_netbios_key "%%K" %~1
exit /b 0

:set_netbios_key
REM %1 = full key from reg query, %2 = value. The key is rebuilt from
REM NETBT so it uses the same root as the rest of the script.
for %%N in ("%~1") do call :set_dword "%NETBT%\%%~nxN" NetbiosOptions %~2
exit /b 0


:apply_MDNS
call :set_dword "%SYS%\Services\Dnscache\Parameters" EnableMDNS 0
exit /b 0

:restore_MDNS
call :delete_value "%SYS%\Services\Dnscache\Parameters" EnableMDNS
exit /b 0


:apply_SSDP_UPNP
REM upnphost depends on SSDPSRV, so it is stopped first.
call :disable_service upnphost
call :disable_service SSDPSRV
exit /b 0

:restore_SSDP_UPNP
call :restore_service SSDPSRV demand
call :restore_service upnphost demand
exit /b 0


:apply_NETWORK_PUBLISHING
call :disable_service FDResPub
exit /b 0

:restore_NETWORK_PUBLISHING
call :restore_service FDResPub demand
exit /b 0


:apply_LLTD
call :set_dword "%SW%\Policies\Microsoft\Windows\LLTD" EnableLLTDIO 0
call :set_dword "%SW%\Policies\Microsoft\Windows\LLTD" EnableRspndr 0
exit /b 0

:restore_LLTD
call :delete_value "%SW%\Policies\Microsoft\Windows\LLTD" EnableLLTDIO
call :delete_value "%SW%\Policies\Microsoft\Windows\LLTD" EnableRspndr
exit /b 0


:apply_TEREDO
call :set_string "%SW%\Policies\Microsoft\Windows\TCPIP\v6Transition" Teredo_State "Disabled"
exit /b 0

:restore_TEREDO
call :delete_value "%SW%\Policies\Microsoft\Windows\TCPIP\v6Transition" Teredo_State
exit /b 0


REM ==========================================================================
REM  Partner and OEM software
REM ==========================================================================

:detect_oem
cls
Echo Looking for partner and OEM services known to collect usage data.
Echo This list is a starting point, not a complete inventory.
Echo.
set "FOUND=0"
call :detect_vendor "NVIDIA"   "NvTelemetryContainer NvContainerLocalSystem"
call :detect_vendor "Intel"    "ESRV_SVC_QUEENCREEK SystemUsageReportSvc_QUEENCREEK DSAService"
call :detect_vendor "AMD"      "AUEPLauncher"
call :detect_vendor "Dell"     "SupportAssistAgent DDVDataCollector DDVRulesProcessor DDVCollectorSvcApi"
call :detect_vendor "HP"       "HpTouchpointAnalyticsService HPAppHelperCap HPDiagsCap HPSysInfoCap HPNetworkCap"
call :detect_vendor "Lenovo"   "ImControllerService LenovoVantageService UDCService"
call :detect_vendor "ASUS"     "ASUSOptimization ASUSSystemAnalysis ASUSSystemDiagnosis ArmouryCrateService"
call :detect_vendor "Razer"    "Razer"
call :detect_vendor "Logitech" "LGHUBUpdaterService logi_lamparray_service"
call :detect_vendor "Adobe"    "AdobeARMservice AGSService AdobeUpdateService"
call :detect_vendor "Google"   "GoogleUpdater gupdate"
call :detect_vendor "Mozilla"  "MozillaMaintenance"
if %FOUND% EQU 0 Echo   None of the known services were found.
Echo.
Echo To handle a vendor, write a BAT that accepts "apply" and "restore", put
Echo it in %OEM_DIR% and add an OEM_SCRIPT=name.bat line to the config.
pause
goto advanced


:detect_vendor
REM %1 = vendor name, %2 = space-separated service name fragments.
REM /r is used instead of /l: findstr can miss matches when it is given
REM several literal strings of different lengths with /i. The service list
REM is read straight from sc or reg, not from a temporary file.
set "VENDOR_SHOWN="
if defined OFFLINE (
    set "LIST_COMMAND=%REG% QUERY "%SYS%\Services""
) else (
    set "LIST_COMMAND=%SC% query type^= service state^= all"
)
for /f "delims=" %%A in ('%LIST_COMMAND% 2^>nul ^| %FINDSTR% /i /r "%~2"') do (
    if not defined VENDOR_SHOWN (
        Echo   Found %~1:
        set "VENDOR_SHOWN=1"
        set /a FOUND+=1
    )
    Echo       %%A
)
exit /b 0


:run_oem_scripts
REM %1 = apply or restore
if %OEM_SCRIPT_COUNT% EQU 0 exit /b 0
Echo.
Echo [Partner and OEM scripts]
if not defined TRUSTED (
    call :note "Skipped - partner scripts only run from the installed copy or a recovery disk"
    exit /b 0
)
for /l %%I in (1,1,%OEM_SCRIPT_COUNT%) do call :run_oem_script %%I %~1
exit /b 0


:run_oem_script
REM %1 = OEM script number, %2 = apply or restore
REM Only a .bat or .cmd file name in the oem folder is accepted. Each script
REM runs in its own cmd so it cannot change this script's variables. It
REM inherits SW, SYS, CU and OFFLINE so it can target an offline installation.
call set "OEM_NAME=%%OEM_SCRIPT_%~1%%"
call :valid_oem_name
if errorlevel 1 (
    call :fail "OEM_SCRIPT=%OEM_NAME% must be a .bat or .cmd file name in the oem folder"
    exit /b 0
)
set "OEM_PATH=%OEM_DIR%\%OEM_NAME%"
if not exist "%OEM_PATH%" (
    call :fail "OEM script not found: %OEM_PATH%"
    exit /b 0
)
Echo   Running  %OEM_NAME% %~2
"%CMD%" /c ""%OEM_PATH%" %~2"
if errorlevel 1 (
    call :fail "%OEM_NAME% returned an error"
    exit /b 0
)
Echo   Finished %OEM_NAME%
exit /b 0


:valid_oem_name
REM Uses OEM_NAME. Returns 0 for a plain .bat or .cmd file name.
if not defined OEM_NAME exit /b 1
if not "%OEM_NAME:\=%"=="%OEM_NAME%" exit /b 1
if not "%OEM_NAME:/=%"=="%OEM_NAME%" exit /b 1
if not "%OEM_NAME::=%"=="%OEM_NAME%" exit /b 1
if not "%OEM_NAME:..=%"=="%OEM_NAME%" exit /b 1
for %%F in ("%OEM_NAME%") do if /i "%%~xF"==".bat" exit /b 0
for %%F in ("%OEM_NAME%") do if /i "%%~xF"==".cmd" exit /b 0
exit /b 1


REM ==========================================================================
REM  Offline Windows installation
REM ==========================================================================

:offline_select
cls
color 07
if defined OFFLINE call :offline_detach_quiet
Echo Work on a Windows installation that is not running, for example from
Echo Hiren's BootCD PE. Its registry is loaded, changed, then saved on detach.
Echo.

:offline_drive
set "ANSWER="
set /p "ANSWER=Drive letter of the Windows installation, for example D: "
if not defined ANSWER goto advanced
call :check_safe ANSWER
if errorlevel 1 goto offline_drive
set "ANSWER=%ANSWER:~0,1%"
set "TARGET="
for %%L in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do if /i "%ANSWER%"=="%%L" set "TARGET=%%L:"
if not defined TARGET goto offline_drive
if not exist "%TARGET%\Windows\System32\config\SOFTWARE" (
    Echo No Windows installation found on %TARGET%
    pause
    goto advanced
)
if /i "%TARGET%"=="%SystemDrive%" if not defined IN_PE (
    Echo %TARGET% is the running Windows. Use the main menu instead.
    pause
    goto advanced
)

REM A Windows that was hibernated, or shut down with Fast Startup (the
REM default on Windows 10 and 11), resumes its saved session at the next
REM start. Changes made here would then be undone, or the file system on
REM that disk damaged.
call :target_hibernated
if errorlevel 1 goto offline_users
color 0e
Echo.
Echo WARNING: %TARGET% holds a saved hibernation or Fast Startup session.
Echo Windows would resume it at the next start, which can undo the changes
Echo made here or damage the file system on that disk.
Echo.
Echo Best: start that Windows and shut it down fully with  shutdown /s /t 0
Echo If it will not start, the saved session can be discarded instead.
Echo Programs that were open in it are lost; saved files are not affected.
Echo.
call :prompt_key DC "D discards the saved session, C cancels [D,C]: "
color 07
if /i "%KEY%"=="C" goto advanced
del /a /f /q "%TARGET%\hiberfil.sys" >nul 2>&1
if exist "%TARGET%\hiberfil.sys" (
    Echo Could not delete %TARGET%\hiberfil.sys, so nothing was changed.
    pause
    goto advanced
)
call :log INFO "Discarded the saved session on %TARGET%"
Echo Saved session discarded. Windows starts fresh next time.

:offline_users
Echo.
Echo User profiles on %TARGET%:
for /d %%U in ("%TARGET%\Users\*") do if exist "%%U\NTUSER.DAT" Echo   %%~nxU

:offline_user
set "ANSWER="
set /p "ANSWER=User whose settings to change: "
if not defined ANSWER goto advanced
call :check_safe ANSWER
if errorlevel 1 goto offline_user
if not "%ANSWER:\=%"=="%ANSWER%" goto offline_user
if not "%ANSWER:/=%"=="%ANSWER%" goto offline_user
if not "%ANSWER:..=%"=="%ANSWER%" goto offline_user
if not exist "%TARGET%\Users\%ANSWER%\NTUSER.DAT" (
    Echo Profile not found.
    goto offline_user
)
set "TARGET_USER=%ANSWER%"

REM Hives left loaded by a run that was closed would make the loads fail.
call :offline_unload
%REG% LOAD HKLM\NMS_SOFTWARE "%TARGET%\Windows\System32\config\SOFTWARE" >nul 2>&1
if errorlevel 1 goto offline_load_failed
%REG% LOAD HKLM\NMS_SYSTEM "%TARGET%\Windows\System32\config\SYSTEM" >nul 2>&1
if errorlevel 1 goto offline_load_failed
%REG% LOAD HKLM\NMS_USER "%TARGET%\Users\%TARGET_USER%\NTUSER.DAT" >nul 2>&1
if errorlevel 1 goto offline_load_failed

REM CurrentControlSet only exists while Windows runs; Select\Current says
REM which ControlSet00N the installation boots with.
set "CONTROL_SET=1"
for /f "tokens=3" %%A in ('%REG% QUERY "HKLM\NMS_SYSTEM\Select" /v Current 2^>nul ^| %FIND% "Current"') do set /a CONTROL_SET=%%A
set "SW=HKLM\NMS_SOFTWARE"
set "SYS=HKLM\NMS_SYSTEM\ControlSet00%CONTROL_SET%"
set "CU=HKLM\NMS_USER"
set "CU_USER=%TARGET_USER%"
set "OFFLINE=1"
REM A different Windows gets its own managed-PC check.
set "MANAGED_ACK="

call :detect_windows
if errorlevel 1 goto offline_version_failed

REM The installed copy on the offline disk, if any, holds that PC's own
REM config with its earlier values, so it is used instead of this one.
set "TARGET_INSTALL="
set "TARGET_PF="
for /f "tokens=2,*" %%A in ('%REG% QUERY "%SW%\Microsoft\Windows\CurrentVersion" /v ProgramFilesDir 2^>nul ^| %FIND% "ProgramFilesDir"') do set "TARGET_PF=%%B"
if defined TARGET_PF call :check_safe TARGET_PF
if not errorlevel 1 if defined TARGET_PF set "TARGET_INSTALL=%TARGET%%TARGET_PF:~2%\no_ms_spy"
REM An install made before the folder layout keeps everything in one folder.
set "TARGET_CONFIG_DIR=%TARGET_INSTALL%\config"
set "TARGET_SCRIPT_DIR=%TARGET_INSTALL%\scripts"
if defined TARGET_INSTALL if not exist "%TARGET_INSTALL%\scripts\" (
    set "TARGET_CONFIG_DIR=%TARGET_INSTALL%"
    set "TARGET_SCRIPT_DIR=%TARGET_INSTALL%"
)
if defined TARGET_INSTALL if exist "%TARGET_CONFIG_DIR%\no_ms_spy.cfg" set "CONFIG=%TARGET_CONFIG_DIR%\no_ms_spy.cfg"
if /i "%CONFIG%"=="%CONFIG_DIR%\no_ms_spy.cfg" call :use_target_config
call :reload_config
if errorlevel 1 (
    pause
    call :offline_detach_quiet
    goto advanced
)

call :log INFO "Offline Windows on %TARGET% loaded for user %TARGET_USER%"
Echo.
Echo Loaded %OS_NAME%, build %BUILD% on %TARGET%.
Echo Configuration: %CONFIG%
pause
goto menu

:use_target_config
REM The target has no installed config. Its earlier values are kept in a
REM file named after that PC, so they are never put back on another PC. A
REM new file starts with this disk's selections but none of its saved values.
set "TARGET_NAME="
for /f "tokens=2,*" %%A in ('%REG% QUERY "%SYS%\Control\ComputerName\ComputerName" /v ComputerName 2^>nul ^| %FIND% "ComputerName"') do set "TARGET_NAME=%%B"
if not defined TARGET_NAME set "TARGET_NAME=unnamed"
call :check_safe TARGET_NAME
if errorlevel 1 set "TARGET_NAME=unnamed"
set "TARGET_CFG=%CONFIG_DIR%\offline_%TARGET_NAME%.cfg"
if not exist "%TARGET_CFG%" if exist "%CONFIG%" %FINDSTR% /v /b /i /c:"ORIG=" "%CONFIG%" > "%TARGET_CFG%" 2>nul
set "CONFIG=%TARGET_CFG%"
exit /b 0


:offline_load_failed
Echo Could not load the registry of %TARGET%. If the installation uses
Echo BitLocker, unlock the drive first.
call :offline_detach_quiet
pause
goto advanced

:offline_version_failed
Echo The registry of %TARGET% was loaded, but its Windows version could not
Echo be read, so nothing was changed. The installation may be damaged or
Echo not a supported Windows version.
call :offline_detach_quiet
pause
goto advanced


:offline_detach
if not defined OFFLINE goto advanced
call :offline_detach_quiet
if defined UNLOAD_FAILED (
    pause
    goto advanced
)
Echo Offline registry saved and detached.
pause
goto menu


:offline_detach_quiet
REM Unloads the hives, which writes the changes back, then switches back to
REM the running Windows and this script's own config.
call :offline_unload
call :use_running_windows
set "CONFIG=%CONFIG_DIR%\no_ms_spy.cfg"
call :detect_windows
call :reload_config
exit /b 0


:offline_unload
set "UNLOAD_FAILED="
for %%H in (NMS_USER NMS_SYSTEM NMS_SOFTWARE) do call :unload_hive %%H
exit /b 0


:unload_hive
REM %1 = hive name under HKLM. Retries once after a short wait.
%REG% QUERY "HKLM\%~1" >nul 2>&1
if errorlevel 1 exit /b 0
%REG% UNLOAD "HKLM\%~1" >nul 2>&1
if not errorlevel 1 exit /b 0
%PING% -n 4 127.0.0.1 >nul
%REG% UNLOAD "HKLM\%~1" >nul 2>&1
if not errorlevel 1 exit /b 0
set "UNLOAD_FAILED=1"
color 0c
Echo Could not save and unload %~1. Close regedit or any other program using
Echo it, then choose Detach again. Do not shut down before it succeeds.
call :notify_error "Could not unload offline registry hive %~1 - changes may not be saved"
exit /b 0


:use_running_windows
set "OFFLINE="
set "MANAGED_ACK="
set "TARGET="
set "TARGET_USER="
set "TARGET_INSTALL="
set "TARGET_CONFIG_DIR="
set "TARGET_SCRIPT_DIR="
set "SW=HKLM\SOFTWARE"
set "SYS=HKLM\SYSTEM\CurrentControlSet"
set "CU=HKCU"
set "CU_USER=%USERNAME%"
call :check_safe CU_USER
if errorlevel 1 set "CU_USER=current"
exit /b 0


:require_target
REM Stops changes to a recovery environment's own temporary registry.
if not defined IN_PE exit /b 0
if defined OFFLINE exit /b 0
Echo This is a recovery environment. Select an offline Windows
Echo installation under V, Advanced first.
pause
exit /b 1


REM ==========================================================================
REM  Setup helpers
REM ==========================================================================

:require_admin
REM fltmc needs admin rights and exists in both Windows and Windows PE.
%FLTMC% >nul 2>&1
if errorlevel 1 (
    color 0c
    Echo This script must be run as Administrator.
    Echo Right-click the file and choose "Run as administrator".
    if defined UNATTENDED call :notify_error "Reapply at sign-in did not get administrator rights"
    if not defined UNATTENDED pause
    exit /b 1
)
exit /b 0


:find_install_dir
REM Program Files is read from the registry, not from the environment,
REM which the signed-in user can change.
set "PROGRAM_FILES="
for /f "tokens=2,*" %%A in ('%REG% QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion" /v ProgramFilesDir 2^>nul ^| %FIND% "ProgramFilesDir"') do set "PROGRAM_FILES=%%B"
set "INSTALL_DIR="
set "INSTALLED="
set "TRUSTED="
if defined PROGRAM_FILES call :check_safe PROGRAM_FILES
if not errorlevel 1 if defined PROGRAM_FILES set "INSTALL_DIR=%PROGRAM_FILES%\no_ms_spy"
if defined INSTALL_DIR if /i "%ROOT_DIR%"=="%INSTALL_DIR%\" set "INSTALLED=1"
if defined INSTALLED set "TRUSTED=1"
REM A recovery disk is under the control of whoever booted it.
if defined IN_PE set "TRUSTED=1"
exit /b 0


:detect_windows
REM Build numbers are used instead of ProductName because Windows 11
REM still reports "Windows 10" in ProductName.
set "NT_KEY=%SW%\Microsoft\Windows NT\CurrentVersion"
set "BUILD="
set "EDITION=Unknown"
for /f "tokens=2,*" %%A in ('%REG% QUERY "%NT_KEY%" /v CurrentBuildNumber 2^>nul ^| %FIND% "CurrentBuildNumber"') do set "BUILD=%%B"
for /f "tokens=2,*" %%A in ('%REG% QUERY "%NT_KEY%" /v EditionID 2^>nul ^| %FIND% "EditionID"') do set "EDITION=%%B"
call :check_safe EDITION
if errorlevel 1 set "EDITION=Unknown"

if not defined BUILD (
    color 0c
    Echo Could not read the Windows build number.
    exit /b 1
)
set /a BUILD=BUILD

set "OS="
if %BUILD% GEQ 7600 set "OS=7"
if %BUILD% GEQ 9200 set "OS=8"
if %BUILD% GEQ 10240 set "OS=10"
if %BUILD% GEQ 22000 set "OS=11"

if not defined OS (
    color 0c
    Echo Build %BUILD% is older than Windows 7 and is not supported.
    exit /b 1
)

set "OS_NAME=Windows %OS%"
if "%OS%"=="8" set "OS_NAME=Windows 8/8.1"

REM Some policies are only honored on these editions.
set "IS_ENTERPRISE="
set "IS_HOME="
set EDITION| %FINDSTR% /i /r "Enterprise Education Server" >nul
if not errorlevel 1 set "IS_ENTERPRISE=1"
set EDITION| %FINDSTR% /i /r /c:"=Core" >nul
if not errorlevel 1 set "IS_HOME=1"
exit /b 0


:prompt_key
REM %1 = allowed keys, %2 = prompt text. The key typed is returned in KEY.
REM set /p is used instead of choice.exe, which some recovery disks lack.
REM After 20 empty answers in a row the input is treated as closed: the
REM error is logged and reported and the script stops instead of looping.
set "EMPTY_ANSWERS=0"

:prompt_key_again
set "KEY="
set /p "KEY=%~2"
if defined KEY goto prompt_key_check
set /a EMPTY_ANSWERS+=1
if %EMPTY_ANSWERS% LSS 20 goto prompt_key_again
call :notify_error "The menu received no keyboard input and stopped"
if defined OFFLINE call :offline_unload
exit 1

:prompt_key_check
set "EMPTY_ANSWERS=0"
call :check_safe KEY
if errorlevel 1 goto prompt_key_again
set "KEY=%KEY:~0,1%"
Echo %~1| %FINDSTR% /i /l /c:"%KEY%" >nul
if errorlevel 1 goto prompt_key_again
exit /b 0


:check_safe
REM %1 = variable name. Returns 1 when the value contains a character cmd
REM could treat as code: & | < > ^ % ! ( ) or a quote. SET prints the value
REM without expanding it, so the check itself is safe.
set "%~1" 2>nul | %FINDSTR% /r /c:"[&|<>^%%!()]" >nul
if not errorlevel 1 exit /b 1
set "%~1" 2>nul | >nul %FINDSTR% /l "\""
if not errorlevel 1 exit /b 1
exit /b 0


:valid_timezone
REM Uses TIMEZONE. Returns 0 when it is a name tzutil knows.
if not defined TIMEZONE exit /b 1
call :check_safe TIMEZONE
if errorlevel 1 exit /b 1
set "TZ_NAME=%TIMEZONE:_dstoff=%"
%TZUTIL% /l | %FINDSTR% /i /x /l /c:"%TZ_NAME%" >nul
exit /b %errorlevel%


:valid_dns_host
REM Uses NCSI_DNS_HOST and NCSI_DNS_IP. Returns 0 when both look valid.
set NCSI_DNS_HOST| %FINDSTR% /r /i /x /c:"NCSI_DNS_HOST=[a-z0-9.-]*" >nul
if errorlevel 1 exit /b 1
set NCSI_DNS_IP 2>nul | %FINDSTR% /r /x /c:"NCSI_DNS_IP=[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*" >nul
exit /b %errorlevel%


:tamper_protection_on
REM Sets TAMPER when Defender Tamper Protection is on (value 5).
set "TAMPER="
for /f "tokens=3" %%A in ('%REG% QUERY "%SW%\Microsoft\Windows Defender\Features" /v TamperProtection 2^>nul ^| %FIND% "TamperProtection"') do if /i "%%A"=="0x5" set "TAMPER=1"
exit /b 0


:target_hibernated
REM Uses TARGET. Returns 0 when hiberfil.sys holds a saved session: its
REM first four bytes are then hibr, wake or rstr. After a full shutdown
REM they are zero. SET prints the binary text without running it. The
REM three strings are the same length, which avoids a findstr bug.
if not exist "%TARGET%\hiberfil.sys" exit /b 1
set "HIBER_HEADER="
set /p HIBER_HEADER=<"%TARGET%\hiberfil.sys"
if not defined HIBER_HEADER exit /b 1
set HIBER_HEADER| %FINDSTR% /i /b /c:"HIBER_HEADER=hibr" /c:"HIBER_HEADER=wake" /c:"HIBER_HEADER=rstr" >nul
exit /b %errorlevel%


:onedrive_signed_in
REM Returns 0 when OneDrive is signed in to a personal or work account.
REM Removing it then stops the sync, and files that are only online, or not
REM uploaded yet, could no longer be opened or could be lost.
%REG% QUERY "%CU%\SOFTWARE\Microsoft\OneDrive\Accounts" /s /v UserFolder 2>nul | %FINDSTR% /i /c:"UserFolder" >nul
exit /b %errorlevel%


:onedrive_folders_moved
REM Returns 0 when Desktop, Documents or Pictures are inside OneDrive.
%REG% QUERY "%CU%\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" 2>nul | %FINDSTR% /i /r /c:"^ *Desktop .*OneDrive" /c:"^ *Personal .*OneDrive" /c:"^ *My Pictures .*OneDrive" >nul
exit /b %errorlevel%


:find_winget
REM winget is started from its package folder in Program Files\WindowsApps,
REM which only the system can change, not through the user's PATH.
set "WINGET="
set "WINGET_DIR="
for /f "delims=" %%W in ('%POWERSHELL% -NoProfile -Command "Get-AppxPackage -Name Microsoft.DesktopAppInstaller | Select-Object -Last 1 -ExpandProperty InstallLocation"') do set "WINGET_DIR=%%W"
if not defined WINGET_DIR exit /b 0
call :check_safe WINGET_DIR
if errorlevel 1 exit /b 0
set "CHECK_TEXT=%WINGET_DIR%"
call :starts_with "%PROGRAM_FILES%\WindowsApps\"
if errorlevel 1 exit /b 0
if exist "%WINGET_DIR%\winget.exe" set "WINGET=%WINGET_DIR%\winget.exe"
exit /b 0


REM ==========================================================================
REM  Logging and notification
REM ==========================================================================

:log
REM %1 = level, %2 = message
>> "%LOG_FILE%" 2>nul Echo %DATE% %TIME% %~1 %~2
exit /b 0


:trim_log
REM Past 1 MB, only the newest 2000 lines are kept, in the same file.
if not exist "%LOG_FILE%" exit /b 0
for %%L in ("%LOG_FILE%") do set "LOG_SIZE=%%~zL"
if %LOG_SIZE% LSS 1048576 exit /b 0
set "LOG_LINES=0"
for /f %%N in ('%FIND% /c /v "" ^< "%LOG_FILE%"') do set "LOG_LINES=%%N"
set /a LOG_SKIP=LOG_LINES-2000
if %LOG_SKIP% LEQ 0 exit /b 0
%MORE% +%LOG_SKIP% "%LOG_FILE%" > "%LOG_FILE%.tmp" 2>nul
if errorlevel 1 (
    del /q "%LOG_FILE%.tmp" 2>nul
    exit /b 0
)
move /y "%LOG_FILE%.tmp" "%LOG_FILE%" >nul
exit /b 0


:read_error
REM Sets ERR_TEXT to " - " and the first line of ERR_FILE, the error text
REM of the command that just failed. It is left empty if that text holds a
REM character cmd could run as code.
set "ERR_TEXT="
set "ERR_LINE="
if exist "%ERR_FILE%" set /p ERR_LINE=<"%ERR_FILE%"
if not defined ERR_LINE exit /b 0
call :check_safe ERR_LINE
if errorlevel 1 exit /b 0
set "ERR_TEXT= - %ERR_LINE%"
exit /b 0


:note
REM %1 = message. Shown and logged; does not count as a failure.
Echo   Note     %~1
call :log NOTE "%~1"
exit /b 0


:fail
REM %1 = message. Shown, logged and counted.
Echo   FAILED   %~1
set /a FAILS+=1
call :log ERROR "%~1"
exit /b 0


:notify_error
REM %1 = message. Logged, written to the Application event log with source
REM no_ms_spy, and shown as a message box where msg.exe exists.
call :log ERROR "%~1"
if exist "%EVENTCREATE%" %EVENTCREATE% /T ERROR /ID 100 /L APPLICATION /SO no_ms_spy /D "%~1" >nul 2>&1
if exist "%MSG%" %MSG% * /TIME:60 "no_ms_spy: %~1" >nul 2>&1
exit /b 0


REM ==========================================================================
REM  Registry, service and task helpers
REM  Each helper saves the earlier value first when a setting is being
REM  applied, so it can be put back later.
REM ==========================================================================

:set_dword
REM %1 = key, %2 = value name, %3 = data, a single digit
call :remember_value "%~1" "%~2"
%REG% ADD "%~1" /v "%~2" /t REG_DWORD /d %~3 /f >nul 2>"%ERR_FILE%"
if not errorlevel 1 goto set_dword_check
call :forget_new_value
call :read_error
call :fail "%~1\%~2%ERR_TEXT%"
exit /b 0

:set_dword_check
REM Read back: a filter driver or a policy engine can let a write report
REM success without keeping the value.
%REG% QUERY "%~1" /v "%~2" 2>nul | %FINDSTR% /i /r /c:"^    %~2  *REG_DWORD  *0x%~3$" >nul
if errorlevel 1 (
    call :fail "%~1\%~2 was written but reads back differently"
    exit /b 0
)
Echo   Set      %~1\%~2 = %~3
exit /b 0


:set_string
REM %1 = key, %2 = value name, %3 = text data
call :remember_value "%~1" "%~2"
%REG% ADD "%~1" /v "%~2" /t REG_SZ /d "%~3" /f >nul 2>"%ERR_FILE%"
if errorlevel 1 (
    call :forget_new_value
    call :read_error
    call :fail "%~1\%~2%%ERR_TEXT%%"
) else (
    Echo   Set      %~1\%~2 = %~3
)
exit /b 0


:write_value
REM %1 = key, %2 = value name, %3 = type, %4 = data. Used to put back.
%REG% ADD "%~1" /v "%~2" /t %~3 /d "%~4" /f >nul 2>"%ERR_FILE%"
if errorlevel 1 (
    call :read_error
    call :fail "put back %~1\%~2%%ERR_TEXT%%"
) else (
    Echo   Put back %~1\%~2 = %~4
)
exit /b 0


:set_timezone
if defined OFFLINE (
    Echo   Skipped  time zone - needs the installation running
    exit /b 0
)
call :valid_timezone
if errorlevel 1 (
    call :fail "TIMEZONE=%TIMEZONE% is not a name tzutil knows - see tzutil /l"
    exit /b 0
)
call :remember_timezone
%TZUTIL% /s "%TIMEZONE%" >nul 2>&1
if errorlevel 1 (
    call :fail "set time zone to %TIMEZONE%"
) else (
    Echo   Time zone set to %TIMEZONE%
)
exit /b 0


:delete_key
REM %1 = key. A missing key is not an error. A deleted key is not saved.
%REG% QUERY "%~1" >nul 2>&1
if errorlevel 1 exit /b 0
%REG% DELETE "%~1" /f >nul 2>&1
if errorlevel 1 (
    call :fail "remove %~1"
) else (
    Echo   Removed  %~1
)
exit /b 0


:remove_appx
REM %1 = package name, %2 = friendly name. Removes the app for all users
REM and the provisioned copy, so new user accounts do not get it either.
if defined OFFLINE (
    Echo   Skipped  %~2 removal - needs the installation running
    exit /b 0
)
set "PS=%POWERSHELL% -NoProfile -Command"
%PS% "if (Get-AppxPackage -AllUsers -Name '%~1') { exit 0 } else { exit 1 }" >nul 2>&1
if errorlevel 1 (
    Echo   Skipped  %~2 - not installed
    exit /b 0
)
%PS% "Get-AppxPackage -AllUsers -Name '%~1' | Remove-AppxPackage -AllUsers" >nul 2>&1
%PS% "Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq '%~1' | Remove-AppxProvisionedPackage -Online" >nul 2>&1
%PS% "if (Get-AppxPackage -AllUsers -Name '%~1') { exit 1 } else { exit 0 }" >nul 2>&1
if errorlevel 1 (
    call :fail "remove %~2"
) else (
    Echo   Removed  %~2
)
exit /b 0


:disable_feature
REM %1 = optional feature name. It is turned off, not deleted, so R can
REM turn it on again. /English keeps the output the same on every Windows
REM language, so the check below works everywhere.
if defined OFFLINE (
    Echo   Skipped  %~1 feature - needs the installation running
    exit /b 0
)
%DISM% /Online /English /Get-FeatureInfo /FeatureName:%~1 2>nul | %FINDSTR% /i /r /c:"^State : Enable" >nul
if errorlevel 1 (
    Echo   Skipped  %~1 feature - not present or already off
    exit /b 0
)
call :remember_feature %~1
Echo   Working  turning off the %~1 feature - this can take a few minutes
%DISM% /Online /English /Disable-Feature /FeatureName:%~1 /NoRestart /Quiet >nul 2>&1
REM 3010 means it worked and a restart finishes it.
if errorlevel 3011 goto disable_feature_failed
if errorlevel 3010 goto disable_feature_done
if errorlevel 1 goto disable_feature_failed

:disable_feature_done
Echo   Disabled feature %~1 - restart to finish
exit /b 0

:disable_feature_failed
call :forget_new_value
call :fail "disable feature %~1"
exit /b 0


:delete_value
REM %1 = key, %2 = value name. Missing values are not an error.
%REG% QUERY "%~1" /v "%~2" >nul 2>&1
if errorlevel 1 exit /b 0
call :remember_value "%~1" "%~2"
%REG% DELETE "%~1" /v "%~2" /f >nul 2>"%ERR_FILE%"
if errorlevel 1 (
    call :forget_new_value
    call :read_error
    call :fail "remove %~1\%~2%%ERR_TEXT%%"
) else (
    Echo   Removed  %~1\%~2
)
exit /b 0


:disable_service
REM %1 = service name. Offline, the Start value is written directly.
call :remember_service %~1
if defined OFFLINE goto disable_service_offline
%SC% query "%~1" >nul 2>&1
if errorlevel 1 (
    Echo   Skipped  %~1 - service not present
    exit /b 0
)
%SC% stop "%~1" >nul 2>&1
%SC% config "%~1" start= disabled >nul 2>&1
if errorlevel 1 (
    call :forget_new_value
    call :fail "disable service %~1"
) else (
    Echo   Disabled service %~1
)
exit /b 0

:disable_service_offline
%REG% QUERY "%SYS%\Services\%~1" >nul 2>&1
if errorlevel 1 (
    Echo   Skipped  %~1 - service not present
    exit /b 0
)
REM Start 4 = disabled
%REG% ADD "%SYS%\Services\%~1" /v Start /t REG_DWORD /d 4 /f >nul 2>&1
if errorlevel 1 (
    call :forget_new_value
    call :fail "disable service %~1"
) else (
    Echo   Disabled service %~1
)
exit /b 0


:restore_service
REM %1 = service name, %2 = start type: auto or demand. Windows default.
if defined OFFLINE goto restore_service_offline
%SC% query "%~1" >nul 2>&1
if errorlevel 1 (
    Echo   Skipped  %~1 - service not present
    exit /b 0
)
%SC% config "%~1" start= %~2 >nul 2>&1
if errorlevel 1 (
    call :fail "restore service %~1"
    exit /b 0
)
Echo   Service  %~1 start type = %~2
if /i "%~2"=="auto" %SC% start "%~1" >nul 2>&1
exit /b 0

:restore_service_offline
%REG% QUERY "%SYS%\Services\%~1" >nul 2>&1
if errorlevel 1 (
    Echo   Skipped  %~1 - service not present
    exit /b 0
)
REM Start 2 = automatic, 3 = manual (demand)
set "START_VALUE=3"
if /i "%~2"=="auto" set "START_VALUE=2"
%REG% ADD "%SYS%\Services\%~1" /v Start /t REG_DWORD /d %START_VALUE% /f >nul 2>&1
if errorlevel 1 (
    call :fail "restore service %~1"
) else (
    Echo   Service  %~1 Start = %START_VALUE%
)
exit /b 0


:disable_task
REM %1 = full task path. Missing tasks are skipped.
if defined OFFLINE (
    Echo   Skipped  task %~1 - needs the installation running
    exit /b 0
)
%SCHTASKS% /Query /TN "%~1" >nul 2>&1
if errorlevel 1 exit /b 0
call :remember_task "%~1"
%SCHTASKS% /Change /TN "%~1" /Disable >nul 2>&1
if errorlevel 1 (
    call :forget_new_value
    call :fail "disable task %~1"
) else (
    Echo   Disabled task %~1
)
exit /b 0


:enable_task
REM %1 = full task path. Missing tasks are skipped.
if defined OFFLINE (
    Echo   Skipped  task %~1 - needs the installation running
    exit /b 0
)
%SCHTASKS% /Query /TN "%~1" >nul 2>&1
if errorlevel 1 exit /b 0
%SCHTASKS% /Change /TN "%~1" /Enable >nul 2>&1
if errorlevel 1 (
    call :fail "enable task %~1"
) else (
    Echo   Enabled  task %~1
)
exit /b 0


:show_service
REM %1 = service name. Start: 2 automatic, 3 manual, 4 disabled.
set "VALUE=not present"
for /f "tokens=3" %%A in ('%REG% QUERY "%SYS%\Services\%~1" /v Start 2^>nul ^| %FIND% "Start"') do set "VALUE=%%A"
Echo   %~1 Start value: %VALUE%
exit /b 0


:show_value
REM %1 = key, %2 = value name. The value is printed by a FOR variable so it
REM cannot run as code.
set "VALUE_SHOWN="
for /f "tokens=2,*" %%A in ('%REG% QUERY "%~1" /v "%~2" 2^>nul ^| %FIND% /i "%~2"') do (
    Echo %~2: %%B
    set "VALUE_SHOWN=1"
)
if not defined VALUE_SHOWN Echo %~2: not set
exit /b 0


:end
if defined OFFLINE call :offline_unload
if defined UNLOAD_FAILED pause
REM 98 tells the launcher to start the installed copy, 99 to delete the
REM install folder.
if defined START_INSTALLED (
    endlocal
    exit /b 98
)
if defined UNINSTALL_READY (
    endlocal
    exit /b 99
)
endlocal
exit /b 0
