@if (@X)==(@Y) @end /*
@echo off
chcp 65001 >nul 2>nul
setlocal EnableExtensions DisableDelayedExpansion

set "TARGET=C:\AI\omostack"
set "PORT=4096"
set "KEEPALIVE_TASK=OmO OpenCode WSL Keepalive"
set "HOST_STATE=%LOCALAPPDATA%\OmOHostBootstrap"
set "LOG_FILE=%TEMP%\omo-cleanup.log"
set "CONFIRM="
set "SHOW_HELP=0"
set "CLEANUP_WARNINGS=0"
set "DELETE_TARGET_ON_EXIT=0"

call :main %*
set "OMO_CLEANUP_EXIT=%ERRORLEVEL%"
call :pause_before_exit %OMO_CLEANUP_EXIT%
if "%DELETE_TARGET_ON_EXIT%"=="1" (
    start "" /b cmd.exe /d /c "ping.exe 127.0.0.1 -n 3 ^>nul ^& rmdir /s /q ""%TARGET%"""
)
exit /b %OMO_CLEANUP_EXIT%

:main
call :parse_args %*
if errorlevel 1 exit /b 2
if "%SHOW_HELP%"=="1" exit /b 0

echo.
echo ===============================================================================
echo ВНИМАНИЕ: этот скрипт полностью удалит WSL и ВСЕ дистрибутивы Linux.
echo Все файлы, настройки и службы внутри WSL будут уничтожены без восстановления.
echo Если там есть важные данные или службы, сначала сделайте резервную копию.
echo.
echo WARNING: this script will completely remove WSL and ALL Linux distributions.
echo Every file, setting, and service inside WSL will be permanently destroyed.
echo Back up anything important before continuing.
echo ===============================================================================
echo.
echo To continue, type this exact uppercase phrase:
echo I AGREE TO DELETE MY WSL COMPLETELY
echo.
set /p "CONFIRM=> "
setlocal EnableDelayedExpansion
if not "!CONFIRM!"=="I AGREE TO DELETE MY WSL COMPLETELY" (
    endlocal
    echo.
    echo Confirmation did not match. Nothing was changed.
    echo Фраза подтверждения не совпала. Изменения не вносились.
    exit /b 2
)
endlocal

call :require_admin
if errorlevel 1 exit /b 1

> "%LOG_FILE%" echo OmOStack destructive cleanup started at %DATE% %TIME%
call :log "Stopping and deleting the OmO keep-alive task."
schtasks.exe /End /TN "%KEEPALIVE_TASK%" >>"%LOG_FILE%" 2>&1
schtasks.exe /Delete /TN "%KEEPALIVE_TASK%" /F >>"%LOG_FILE%" 2>&1

call :log "Removing the OpenCode loopback portproxy."
netsh.exe interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=%PORT% >>"%LOG_FILE%" 2>&1

call :log "Stopping WSL before destructive removal."
wsl.exe --shutdown >>"%LOG_FILE%" 2>&1

call :log "Unregistering every WSL distribution."
for /f "usebackq delims=" %%D in (`cscript.exe //nologo //E:JScript "%~f0" list-distros`) do call :unregister_distro "%%D"

call :log "Removing the Ubuntu application package when winget can identify it."
where winget.exe >nul 2>nul
if not errorlevel 1 (
    winget.exe uninstall --id Canonical.Ubuntu --exact --silent --disable-interactivity >>"%LOG_FILE%" 2>&1
)

call :log "Removing the modern WSL package/update when supported."
wsl.exe --uninstall >>"%LOG_FILE%" 2>&1

call :disable_feature Microsoft-Windows-Subsystem-Linux
call :disable_feature VirtualMachinePlatform

call :log "Deleting WSL host configuration and OmOStack host state."
del /f /q "%USERPROFILE%\.wslconfig" >>"%LOG_FILE%" 2>&1
reg.exe delete HKCU\Software\Canonical\Ubuntu /v UbuntuInsightsConsent /f >>"%LOG_FILE%" 2>&1
rmdir /s /q "%HOST_STATE%" >>"%LOG_FILE%" 2>&1
del /f /q "%TEMP%\omo-bootstrap-status.json" "%TEMP%\omo_bootstrap.sh" >>"%LOG_FILE%" 2>&1

call :log "Scheduling removal of the OmOStack checkout after this script exits: %TARGET%"
set "DELETE_TARGET_ON_EXIT=1"

echo.
if "%CLEANUP_WARNINGS%"=="1" (
    echo Cleanup completed with warnings. Review: %LOG_FILE%
    echo Очистка завершена с предупреждениями. Журнал: %LOG_FILE%
) else (
    echo Cleanup completed. A Windows restart is required.
    echo Очистка завершена. Требуется перезагрузка Windows.
)
exit /b 0

:parse_args
if "%~1"=="" exit /b 0
if /I "%~1"=="/target" (
    set "TARGET=%~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="/port" (
    set "PORT=%~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="/help" goto usage
if /I "%~1"=="-h" goto usage
echo Unknown argument: %~1
goto usage_error

:usage
set "SHOW_HELP=1"
echo Usage: omo_cleanup.cmd [/target C:\AI\omostack] [/port 4096]
echo Destructively removes all WSL distributions, WSL components, and OmOStack state.
exit /b 0

:usage_error
call :usage
exit /b 2

:require_admin
net session >nul 2>nul
if errorlevel 1 (
    echo ERROR: cleanup must be started from an elevated command prompt.
    echo Right-click omo_cleanup.cmd and choose "Run as administrator".
    echo ОШИБКА: запусти omo_cleanup.cmd от имени администратора.
    exit /b 1
)
exit /b 0

:unregister_distro
set "CLEAN_DISTRO=%~1"
if "%CLEAN_DISTRO%"=="" exit /b 0
call :log "Unregistering WSL distribution: %CLEAN_DISTRO%"
wsl.exe --unregister "%CLEAN_DISTRO%" >>"%LOG_FILE%" 2>&1
if errorlevel 1 (
    set "CLEANUP_WARNINGS=1"
    call :log "WARN: failed to unregister %CLEAN_DISTRO%."
)
exit /b 0

:disable_feature
set "FEATURE_NAME=%~1"
call :log "Disabling and removing Windows feature payload: %FEATURE_NAME%"
dism.exe /online /disable-feature /featurename:%FEATURE_NAME% /remove /norestart >>"%LOG_FILE%" 2>&1
if not errorlevel 1 exit /b 0
call :log "WARN: payload removal failed; retrying feature disable without /remove."
dism.exe /online /disable-feature /featurename:%FEATURE_NAME% /norestart >>"%LOG_FILE%" 2>&1
if errorlevel 1 (
    set "CLEANUP_WARNINGS=1"
    call :log "WARN: failed to disable %FEATURE_NAME%."
)
exit /b 0

:log
echo %DATE% %TIME% %*
>>"%LOG_FILE%" echo %DATE% %TIME% %*
exit /b 0

:pause_before_exit
set "OMO_CLEANUP_EXIT=%~1"
echo.
if "%OMO_CLEANUP_EXIT%"=="0" (
    echo Press any key to close this window...
    echo Нажми любую клавишу, чтобы закрыть окно...
) else (
    echo Cleanup stopped with exit code %OMO_CLEANUP_EXIT%.
    echo Очистка остановлена с кодом %OMO_CLEANUP_EXIT%.
    echo Press any key to close this window...
    echo Нажми любую клавишу, чтобы закрыть окно...
)
pause >nul
exit /b 0

*/

var shell = new ActiveXObject("WScript.Shell");
var args = WScript.Arguments;

function trim(s) {
    return String(s).replace(/^\s+|\s+$/g, "");
}

function runStdout(cmd) {
    var exec = shell.Exec("%ComSpec% /d /c " + cmd);
    var out = exec.StdOut.ReadAll();
    while (exec.Status === 0) {
        WScript.Sleep(20);
    }
    return out;
}

function listDistros() {
    var text = runStdout("wsl.exe --list --quiet");
    text = text.replace(/\u0000/g, "").replace(/\r/g, "\n");
    var lines = text.split(/\n+/);
    for (var i = 0; i < lines.length; i++) {
        var name = trim(lines[i]).replace(/^\*/, "");
        if (name) WScript.Echo(name);
    }
}

if (args.length > 0 && String(args(0)).toLowerCase() === "list-distros") {
    listDistros();
    WScript.Quit(0);
}

WScript.Quit(2);
