@echo off
setlocal EnableExtensions DisableDelayedExpansion

REM ==========================================================================
REM  no_ms_spy.bat - launcher
REM  Start this file. It asks for administrator rights with the UAC prompt
REM  when needed, then runs scripts\no_ms_spy_main.bat, which holds the menu
REM  and every setting. Arguments are passed on, so the reapply task's
REM  "no_ms_spy.bat reapply" also works.
REM
REM
REM  After an uninstall the main script returns 99, and this launcher then
REM  deletes its own folder.
REM ==========================================================================

REM A 32-bit cmd on 64-bit Windows sees a redirected registry and Program
REM Files folder. Relaunch with the native 64-bit cmd.
if not defined PROCESSOR_ARCHITEW6432 goto native_cmd
"%SystemRoot%\Sysnative\cmd.exe" /c ""%~f0" %*"
exit /b %errorlevel%
:native_cmd

REM Call system tools by full path and work from System32, so a program with
REM the same name in the current folder or in PATH is never run, and so the
REM install folder is not in use when an uninstall removes it.
set "SYS32=%SystemRoot%\System32"
cd /d "%SYS32%"
set "POWERSHELL=%SYS32%\WindowsPowerShell\v1.0\powershell.exe"
set "PING=%SYS32%\PING.EXE"
set "LOCK=%SystemRoot%\Temp\no_ms_spy.lock"
set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "MAIN=%ROOT%\scripts\no_ms_spy_main.bat"

if not exist "%MAIN%" (
    Echo scripts\no_ms_spy_main.bat was not found next to this launcher.
    Echo Keep the launcher together with its scripts folder.
    pause
    exit /b 1
)

REM fltmc needs administrator rights and exists in Windows and Windows PE.
"%SYS32%\fltmc.exe" >nul 2>&1
if not errorlevel 1 goto run_main

REM The reapply task always starts with administrator rights, and nobody is
REM there to answer a UAC prompt. The main script reports the problem.
if /i "%~1"=="reapply" goto run_main
if not exist "%POWERSHELL%" goto no_uac

REM Start this launcher again with administrator rights. Its path is passed
REM through an environment variable, so no character in it is read as code.
Echo Asking for administrator rights...
set "NMS_LAUNCHER_PATH=%~f0"
"%POWERSHELL%" -NoProfile -Command "try { Start-Process -FilePath '%SYS32%\cmd.exe' -ArgumentList ('/c ' + [char]34 + [char]34 + $env:NMS_LAUNCHER_PATH + [char]34 + [char]34) -Verb RunAs -ErrorAction Stop; exit 0 } catch { exit 1 }"
if errorlevel 1 goto uac_declined
exit /b 0

:uac_declined
Echo Administrator rights were not granted, so nothing was changed.
pause
exit /b 1

:no_uac
Echo This script needs administrator rights. Right-click no_ms_spy.bat and
Echo choose "Run as administrator".
pause
exit /b 1


:run_main
set "NMS_LAUNCHER=1"
REM Only one copy runs at a time, so two cannot overwrite each other's saved
REM values. A copy holds the lock file open while it runs. A few retries
REM cover the moment an install hands over to the installed copy.
set "LOCK_TRIES=0"

:lock_retry
(call ) 2>nul 9>>"%LOCK%" && goto lock_free
set /a LOCK_TRIES+=1
if %LOCK_TRIES% GEQ 5 goto already_running
"%PING%" -n 2 127.0.0.1 >nul
goto lock_retry

:lock_free
call "%MAIN%" %* 9>>"%LOCK%"
if "%errorlevel%"=="99" goto remove_install
if "%errorlevel%"=="98" goto start_installed
exit /b %errorlevel%


:start_installed
REM After an install: start the installed copy now that this copy has let
REM go of the lock. Program Files is read from the registry, not from the
REM environment, which the signed-in user can change.
set "REG=%SYS32%\reg.exe"
set "FIND=%SYS32%\find.exe"
set "PF="
for /f "tokens=2,*" %%A in ('%REG% QUERY "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion" /v ProgramFilesDir 2^>nul ^| %FIND% "ProgramFilesDir"') do set "PF=%%B"
if not defined PF exit /b 0
if exist "%PF%\no_ms_spy\no_ms_spy.bat" start "no_ms_spy" "%PF%\no_ms_spy\no_ms_spy.bat"
exit /b 0


:already_running
REM At sign-in the other copy is doing the work, so this one just stops.
if /i "%~1"=="reapply" exit /b 0
Echo Another copy of no_ms_spy is running. Close it, then start this again.
pause
exit /b 1


:remove_install
REM The main script put everything back and asked for the install folder to
REM be removed. This launcher is inside that folder, so the removal runs on
REM the same line as (goto): it ends this batch file first, and cmd then
REM finishes the line without reading the deleted file again.
if not exist "%ROOT%\scripts\no_ms_spy_main.bat" exit /b 1
Echo.
Echo Removing %ROOT%
(goto) 2>nul & rmdir /s /q "%ROOT%" & (if exist "%ROOT%\" (Echo Some files could not be removed. Delete %ROOT% by hand.) else (Echo no_ms_spy is uninstalled.)) & pause
