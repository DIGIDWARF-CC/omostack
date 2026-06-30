@if (@X)==(@Y) @end /*
@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "MODE=install"
set "DISTRO=Ubuntu"
set "TARGET=C:\AI\omostack"
set "PORT=4096"
set "REPO=https://github.com/DIGIDWARF-CC/omostack.git"
set "DRY_RUN=0"
set "ROOT_DIR=%~dp0"
set "LOG_ENABLED=0"
set "LOG_FILE="
set "BACKUP_DIR="
set "WIN_VERSION=unknown"
set "WIN_BUILD=0"
set "NETWORK_MODE=best-effort"
set "WSL_SHUTDOWN_NEEDED=0"
set "REBOOT_REQUIRED=0"
set "STATUS_TMP=%TEMP%\omo-bootstrap-status.json"
set "KEEPALIVE_TASK=OmO OpenCode WSL Keepalive"
set "KEEPALIVE_SCRIPT=%LOCALAPPDATA%\OmOHostBootstrap\start-opencode-wsl.cmd"
set "KEEPALIVE_LAUNCHER=%LOCALAPPDATA%\OmOHostBootstrap\start-opencode-wsl-hidden.vbs"
set "SHOW_HELP=0"

call :main %*
set "OMO_BOOTSTRAP_EXIT=%ERRORLEVEL%"
call :pause_before_exit %OMO_BOOTSTRAP_EXIT%
exit /b %OMO_BOOTSTRAP_EXIT%

:main
call :parse_args %*
if errorlevel 1 exit /b 2
if "%SHOW_HELP%"=="1" exit /b 0

if /I not "%MODE%"=="install" if /I not "%MODE%"=="repair" if /I not "%MODE%"=="status" (
    echo Invalid /mode value: %MODE%
    exit /b 2
)

if "%DRY_RUN%"=="0" if /I not "%MODE%"=="status" (
    set "LOG_ENABLED=1"
    set "LOG_DIR=%LOCALAPPDATA%\OmOHostBootstrap"
    if not exist "%LOCALAPPDATA%\OmOHostBootstrap" mkdir "%LOCALAPPDATA%\OmOHostBootstrap" >nul 2>nul
    set "LOG_FILE=%LOCALAPPDATA%\OmOHostBootstrap\bootstrap.log"
    set "BACKUP_DIR=%LOCALAPPDATA%\OmOHostBootstrap\backups"
)

call :detect_windows
if errorlevel 1 exit /b 1

if /I "%MODE%"=="status" (
    call :status
    exit /b %ERRORLEVEL%
)

if "%DRY_RUN%"=="0" (
    call :require_admin
    if errorlevel 1 exit /b 1
) else (
    call :log "[dry-run] admin check skipped; real install/repair must be started with Run as administrator."
)

call :ensure_host_prereqs
if errorlevel 1 exit /b 1

call :ensure_windows_side
if errorlevel 1 exit /b 1

call :run_ubuntu_stage
if errorlevel 1 exit /b 1

call :configure_windows_access
if errorlevel 1 exit /b 1

call :configure_wsl_keepalive
if errorlevel 1 exit /b 1

call :log "OmO host bootstrap complete."
call :log "OpenCode URL: http://127.0.0.1:%PORT%/"
exit /b 0

:pause_before_exit
set "OMO_BOOTSTRAP_EXIT=%~1"
echo.
if "%OMO_BOOTSTRAP_EXIT%"=="0" (
    echo OmO host bootstrap finished successfully.
) else (
    echo OmO host bootstrap finished with exit code %OMO_BOOTSTRAP_EXIT%.
)
echo Press any key to close this window...
pause >nul
exit /b 0

:parse_args
if "%~1"=="" exit /b 0
if /I "%~1"=="/mode" (
    set "MODE=%~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="/distro" (
    set "DISTRO=%~2"
    shift
    shift
    goto parse_args
)
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
if /I "%~1"=="/repo" (
    set "REPO=%~2"
    shift
    shift
    goto parse_args
)
if /I "%~1"=="/dry-run" (
    set "DRY_RUN=1"
    shift
    goto parse_args
)
if /I "%~1"=="/help" goto usage
if /I "%~1"=="-h" goto usage
echo Unknown argument: %~1
goto usage_error

:usage
set "SHOW_HELP=1"
echo Usage: omo_host_bootstrap.cmd [/mode install^|repair^|status] [/distro Ubuntu] [/target C:\AI\omostack] [/port 4096] [/repo URL] [/dry-run]
echo.
echo Windows host bootstrap. No PowerShell is used. install/repair require Run as administrator unless /dry-run is used.
exit /b 0

:usage_error
call :usage
exit /b 2

:log
echo %DATE% %TIME% %*
if "%LOG_ENABLED%"=="1" >>"%LOG_FILE%" echo %DATE% %TIME% %*
exit /b 0

:require_admin
net session >nul 2>nul
if errorlevel 1 (
    echo ERROR: install/repair must be started from an elevated command prompt.
    echo Right-click omo_host_bootstrap.cmd and choose "Run as administrator".
    exit /b 1
)
call :log "Administrator token detected."
exit /b 0

:detect_windows
for /f "tokens=1,2 delims=|" %%A in ('cscript.exe //nologo //E:JScript "%~f0" windows-version') do (
    set "WIN_VERSION=%%A"
    set "WIN_BUILD=%%B"
)
if "%WIN_BUILD%"=="" set "WIN_BUILD=0"
if %WIN_BUILD% GEQ 22621 (
    set "NETWORK_MODE=mirrored"
) else (
    set "NETWORK_MODE=best-effort"
)
call :log "Windows version: %WIN_VERSION% (build %WIN_BUILD%); WSL networking mode: %NETWORK_MODE%"
exit /b 0

:ensure_host_prereqs
for %%T in (cscript.exe wscript.exe dism.exe reg.exe wsl.exe netsh.exe curl.exe schtasks.exe) do (
    where %%T >nul 2>nul
    if errorlevel 1 (
        echo ERROR: %%T is required but was not found in PATH.
        exit /b 1
    )
)
exit /b 0

:ensure_windows_side
call :log "Ensuring WSL optional features."
if "%DRY_RUN%"=="1" (
    call :log "[dry-run] dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart"
    call :log "[dry-run] dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart"
) else (
    call :enable_windows_feature Microsoft-Windows-Subsystem-Linux
    if errorlevel 1 exit /b 1
    call :enable_windows_feature VirtualMachinePlatform
    if errorlevel 1 exit /b 1
)

call :update_wsl
if errorlevel 1 exit /b 1

call :log "Setting WSL default version and Ubuntu Insights opt-out."
if "%DRY_RUN%"=="1" (
    call :log "[dry-run] wsl.exe --set-default-version 2"
    call :log "[dry-run] reg.exe add HKCU\Software\Canonical\Ubuntu /v UbuntuInsightsConsent /t REG_DWORD /d 0 /f"
) else (
    call :set_wsl_default_version
    if errorlevel 1 exit /b 1
    reg.exe add HKCU\Software\Canonical\Ubuntu /v UbuntuInsightsConsent /t REG_DWORD /d 0 /f >>"%LOG_FILE%" 2>&1
)

call :log "Writing minimal %USERPROFILE%\.wslconfig for %NETWORK_MODE%."
for /f "usebackq delims=" %%R in (`cscript.exe //nologo //E:JScript "%~f0" wslconfig "%USERPROFILE%\.wslconfig" "%NETWORK_MODE%" "%BACKUP_DIR%" "%DRY_RUN%"`) do (
    set "WSLCONFIG_RESULT=%%R"
)
call :log ".wslconfig: %WSLCONFIG_RESULT%"
if /I "%WSLCONFIG_RESULT%"=="updated" set "WSL_SHUTDOWN_NEEDED=1"

cscript.exe //nologo //E:JScript "%~f0" distro-exists "%DISTRO%" >nul
if errorlevel 1 (
    call :log "WSL distro %DISTRO% is missing."
    if "%DRY_RUN%"=="1" (
        call :log "[dry-run] wsl.exe --install -d %DISTRO% --no-launch --web-download"
    ) else (
        call :install_wsl_distro
        if errorlevel 1 exit /b 1
    )
) else (
    call :log "WSL distro %DISTRO% already exists."
)

if not "%DRY_RUN%"=="1" (
    call :verify_distro_available "after WSL install attempt"
    if errorlevel 1 exit /b 1
)

if "%DRY_RUN%"=="1" goto dry_run_set_default
wsl.exe --set-default %DISTRO% >>"%LOG_FILE%" 2>&1
set "WSL_SET_DEFAULT_EXIT=%ERRORLEVEL%"
if not "%WSL_SET_DEFAULT_EXIT%"=="0" (
    if "%REBOOT_REQUIRED%"=="1" (
        echo ERROR: Windows reported that a restart is required before WSL can finish setup.
        echo Restart Windows, then rerun this script.
    ) else (
        echo ERROR: wsl.exe --set-default %DISTRO% failed with exit code %WSL_SET_DEFAULT_EXIT%.
    )
    echo See log: %LOG_FILE%
    exit /b 1
)
goto after_set_default

:dry_run_set_default
call :log "[dry-run] wsl.exe --set-default %DISTRO%"

:after_set_default
if not "%WSL_SHUTDOWN_NEEDED%"=="1" goto after_shutdown
if "%DRY_RUN%"=="1" goto dry_run_shutdown
call :log ".wslconfig changed; shutting down WSL to apply host settings."
wsl.exe --shutdown >>"%LOG_FILE%" 2>&1
goto after_shutdown

:dry_run_shutdown
call :log "[dry-run] wsl.exe --shutdown"

:after_shutdown
exit /b 0

:enable_windows_feature
set "FEATURE_NAME=%~1"
dism.exe /online /enable-feature /featurename:%FEATURE_NAME% /all /norestart >>"%LOG_FILE%" 2>&1
set "DISM_EXIT=%ERRORLEVEL%"
if "%DISM_EXIT%"=="0" exit /b 0
if "%DISM_EXIT%"=="3010" (
    set "REBOOT_REQUIRED=1"
    call :log "WARN: %FEATURE_NAME% enabled, but Windows requires a restart before WSL may work."
    exit /b 0
)
echo ERROR: DISM failed while enabling %FEATURE_NAME% with exit code %DISM_EXIT%.
echo See log: %LOG_FILE%
exit /b 1

:update_wsl
call :log "Updating WSL."
if "%DRY_RUN%"=="1" (
    call :log "[dry-run] wsl.exe --update --web-download"
    exit /b 0
)
wsl.exe --update --web-download >>"%LOG_FILE%" 2>&1
set "WSL_UPDATE_EXIT=%ERRORLEVEL%"
if "%WSL_UPDATE_EXIT%"=="0" exit /b 0
call :log "WARN: wsl.exe --update --web-download failed with exit code %WSL_UPDATE_EXIT%; retrying without --web-download."
wsl.exe --update >>"%LOG_FILE%" 2>&1
set "WSL_UPDATE_EXIT=%ERRORLEVEL%"
if "%WSL_UPDATE_EXIT%"=="0" exit /b 0
call :log "WARN: wsl.exe --update failed with exit code %WSL_UPDATE_EXIT%; continuing to distro installation."
exit /b 0

:set_wsl_default_version
wsl.exe --set-default-version 2 >>"%LOG_FILE%" 2>&1
set "WSL_DEFAULT_VERSION_EXIT=%ERRORLEVEL%"
if "%WSL_DEFAULT_VERSION_EXIT%"=="0" exit /b 0
if "%REBOOT_REQUIRED%"=="1" (
    call :log "WARN: wsl.exe --set-default-version 2 failed before the pending Windows restart; continuing to the distro install attempt."
    exit /b 0
)
echo ERROR: wsl.exe --set-default-version 2 failed with exit code %WSL_DEFAULT_VERSION_EXIT%.
echo See log: %LOG_FILE%
exit /b 1

:install_wsl_distro
call :log "Installing WSL distro %DISTRO%."
wsl.exe --install -d %DISTRO% --no-launch --web-download >>"%LOG_FILE%" 2>&1
set "WSL_INSTALL_EXIT=%ERRORLEVEL%"
if "%WSL_INSTALL_EXIT%"=="0" exit /b 0
call :log "WARN: wsl.exe --install -d %DISTRO% --no-launch --web-download failed with exit code %WSL_INSTALL_EXIT%; retrying without --web-download."
wsl.exe --install -d %DISTRO% --no-launch >>"%LOG_FILE%" 2>&1
set "WSL_INSTALL_EXIT=%ERRORLEVEL%"
if "%WSL_INSTALL_EXIT%"=="0" exit /b 0
if "%REBOOT_REQUIRED%"=="1" (
    echo ERROR: Windows enabled WSL features but requires a restart before distro installation can complete.
    echo Restart Windows, then rerun this script.
) else (
    echo ERROR: wsl.exe --install -d %DISTRO% --no-launch failed with exit code %WSL_INSTALL_EXIT%.
)
echo See log: %LOG_FILE%
exit /b 1

:verify_distro_available
cscript.exe //nologo //E:JScript "%~f0" distro-exists "%DISTRO%" >nul
if errorlevel 1 (
    if "%REBOOT_REQUIRED%"=="1" (
        echo ERROR: WSL distro %DISTRO% is not available %~1 because Windows still needs a restart.
        echo Restart Windows, then rerun this script.
    ) else (
        echo ERROR: WSL distro %DISTRO% is not available %~1.
        echo Windows may need a reboot after enabling WSL features, or the distro install may still be pending.
        echo Rerun this script after reboot. If it still fails, install Ubuntu manually with:
        echo   wsl.exe --install -d %DISTRO%
    )
    exit /b 1
)
exit /b 0

:run_ubuntu_stage
set "STAGE_WIN=%ROOT_DIR%omo_bootstrap.sh"
if not exist "%STAGE_WIN%" (
    set "STAGE_WIN=%TEMP%\omo_bootstrap.sh"
    if "%DRY_RUN%"=="1" (
        call :log "[dry-run] curl.exe -fsSL -o %STAGE_WIN% https://raw.githubusercontent.com/DIGIDWARF-CC/omostack/main/bootstrap-for-human/omo_bootstrap.sh"
    ) else (
        curl.exe -fsSL -o "%STAGE_WIN%" "https://raw.githubusercontent.com/DIGIDWARF-CC/omostack/main/bootstrap-for-human/omo_bootstrap.sh"
        if errorlevel 1 exit /b 1
    )
)

for /f "usebackq delims=" %%P in (`cscript.exe //nologo //E:JScript "%~f0" win-to-wsl "%STAGE_WIN%"`) do set "STAGE_WSL=%%P"
for /f "usebackq delims=" %%P in (`cscript.exe //nologo //E:JScript "%~f0" win-to-wsl "%TARGET%"`) do set "TARGET_WSL=%%P"

if "%DRY_RUN%"=="1" (
    call :log "[dry-run] wsl.exe -d %DISTRO% -u root -- bash %STAGE_WSL% --mode %MODE% --target %TARGET_WSL% --repo %REPO% --port %PORT% --yes --host-managed --dry-run"
    cscript.exe //nologo //E:JScript "%~f0" distro-exists "%DISTRO%" >nul
    if errorlevel 1 exit /b 0
    wsl.exe -d %DISTRO% -u root -- bash "%STAGE_WSL%" --mode "%MODE%" --target "%TARGET_WSL%" --repo "%REPO%" --port "%PORT%" --yes --host-managed --dry-run
    if errorlevel 1 exit /b 1
    exit /b 0
)

call :verify_distro_available "before Ubuntu stage"
if errorlevel 1 exit /b 1

call :log "Running Ubuntu stage through WSL."
wsl.exe -d %DISTRO% -u root -- bash "%STAGE_WSL%" --mode "%MODE%" --target "%TARGET_WSL%" --repo "%REPO%" --port "%PORT%" --yes --host-managed
exit /b %ERRORLEVEL%

:configure_windows_access
if "%DRY_RUN%"=="1" (
    call :log "[dry-run] would read Ubuntu status JSON and configure loopback portproxy."
    exit /b 0
)

wsl.exe -d %DISTRO% -u root -- cat /root/.local/state/omo-bootstrap/host-status.json > "%STATUS_TMP%" 2>>"%LOG_FILE%"
if errorlevel 1 (
    echo ERROR: Ubuntu stage status JSON was not available.
    exit /b 1
)

set "WSL_IP="
for /f "usebackq delims=" %%I in (`cscript.exe //nologo //E:JScript "%~f0" json-field "%STATUS_TMP%" wsl_ip 2^>nul`) do set "WSL_IP=%%I"
if not "%WSL_IP%"=="" (
    cscript.exe //nologo //E:JScript "%~f0" is-ipv4 "%WSL_IP%" >nul
    if errorlevel 1 set "WSL_IP="
)
if "%WSL_IP%"=="" (
    for /f "tokens=1" %%I in ('wsl.exe -d %DISTRO% -u root -- hostname -I 2^>nul') do set "WSL_IP=%%I"
)
if not "%WSL_IP%"=="" (
    cscript.exe //nologo //E:JScript "%~f0" is-ipv4 "%WSL_IP%" >nul
    if errorlevel 1 set "WSL_IP="
)
if "%WSL_IP%"=="" (
    echo ERROR: cannot determine WSL IP for portproxy.
    exit /b 1
)

call :log "Configuring loopback-only portproxy 127.0.0.1:%PORT% -> %WSL_IP%:%PORT%."
netsh.exe interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=%PORT% >>"%LOG_FILE%" 2>&1
netsh.exe interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=%PORT% connectaddress=%WSL_IP% connectport=%PORT% >>"%LOG_FILE%" 2>&1
if errorlevel 1 exit /b 1

curl.exe -fsS --max-time 8 "http://127.0.0.1:%PORT%/" >nul 2>>"%LOG_FILE%"
if errorlevel 1 (
    call :log "WARN: Windows curl did not reach http://127.0.0.1:%PORT%/ yet."
) else (
    call :log "Windows curl reached http://127.0.0.1:%PORT%/."
)
exit /b 0

:configure_wsl_keepalive
if "%DRY_RUN%"=="1" (
    call :log "[dry-run] would write %KEEPALIVE_SCRIPT% and %KEEPALIVE_LAUNCHER%, then create the %KEEPALIVE_TASK% Scheduled Task."
    exit /b 0
)

if not exist "%LOCALAPPDATA%\OmOHostBootstrap" mkdir "%LOCALAPPDATA%\OmOHostBootstrap" >nul 2>nul
call :log "Writing OpenCode WSL keepalive scripts."
cscript.exe //nologo //E:JScript "%~f0" write-keepalive "%KEEPALIVE_SCRIPT%" "%DISTRO%" "%PORT%"
if errorlevel 1 exit /b 1
cscript.exe //nologo //E:JScript "%~f0" write-keepalive-launcher "%KEEPALIVE_LAUNCHER%"
if errorlevel 1 exit /b 1

schtasks.exe /Query /TN "%KEEPALIVE_TASK%" >nul 2>nul
if not errorlevel 1 (
    call :log "Stopping the previous OpenCode WSL keepalive task instance."
    schtasks.exe /End /TN "%KEEPALIVE_TASK%" >>"%LOG_FILE%" 2>&1
)

call :log "Creating Windows Scheduled Task: %KEEPALIVE_TASK%."
cscript.exe //nologo //E:JScript "%~f0" create-keepalive-task "%KEEPALIVE_TASK%" "%KEEPALIVE_LAUNCHER%"
if errorlevel 1 exit /b 1

schtasks.exe /Run /TN "%KEEPALIVE_TASK%" >>"%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo ERROR: failed to start Scheduled Task "%KEEPALIVE_TASK%".
    echo See log: %LOG_FILE%
    exit /b 1
)
call :log "OpenCode WSL keepalive task started."
exit /b 0

:status
call :log "Mode: status"
call :log "Admin: checking"
net session >nul 2>nul
if errorlevel 1 (call :log "Admin: no") else (call :log "Admin: yes")
call :log "Distro: %DISTRO%"
call :log "Target: %TARGET%"
call :log "Port: %PORT%"
call :log "Repo: %REPO%"
call :log "Windows version: %WIN_VERSION% (build %WIN_BUILD%); WSL networking mode: %NETWORK_MODE%"
echo.
echo === .wslconfig ===
if exist "%USERPROFILE%\.wslconfig" (type "%USERPROFILE%\.wslconfig") else (echo ^<missing^>)
echo.
echo === wsl --status ===
wsl.exe --status
echo.
echo === wsl -l -v ===
wsl.exe -l -v
echo.
echo === portproxy ===
netsh.exe interface portproxy show all
echo.
echo === OmO OpenCode WSL keepalive task ===
schtasks.exe /Query /TN "%KEEPALIVE_TASK%" /V /FO LIST

set "STAGE_WIN=%ROOT_DIR%omo_bootstrap.sh"
if exist "%STAGE_WIN%" (
    cscript.exe //nologo //E:JScript "%~f0" distro-exists "%DISTRO%" >nul
    if not errorlevel 1 (
        call :status_ubuntu_stage
    )
)
exit /b 0

:status_ubuntu_stage
for /f "usebackq delims=" %%P in (`cscript.exe //nologo //E:JScript "%~f0" win-to-wsl "%STAGE_WIN%"`) do set "STAGE_WSL=%%P"
for /f "usebackq delims=" %%P in (`cscript.exe //nologo //E:JScript "%~f0" win-to-wsl "%TARGET%"`) do set "TARGET_WSL=%%P"
echo.
echo === Ubuntu stage status ===
wsl.exe -d %DISTRO% -u root -- bash "%STAGE_WSL%" --mode status --target "%TARGET_WSL%" --repo "%REPO%" --port "%PORT%"
exit /b %ERRORLEVEL%

*/

var fso = new ActiveXObject("Scripting.FileSystemObject");
var shell = new ActiveXObject("WScript.Shell");
var args = WScript.Arguments;

function trim(s) {
    return String(s).replace(/^\s+|\s+$/g, "");
}

function runText(cmd) {
    var exec = shell.Exec('%ComSpec% /d /c ' + cmd);
    var out = exec.StdOut.ReadAll();
    var err = exec.StdErr.ReadAll();
    while (exec.Status === 0) {
        WScript.Sleep(20);
    }
    return out + err;
}

function ensureDir(path) {
    if (!path || fso.FolderExists(path)) return;
    var parent = fso.GetParentFolderName(path);
    if (parent && !fso.FolderExists(parent)) ensureDir(parent);
    fso.CreateFolder(path);
}

function readFile(path) {
    if (!fso.FileExists(path)) return "";
    var file = fso.OpenTextFile(path, 1, false);
    var text = file.ReadAll();
    file.Close();
    return text;
}

function writeFile(path, text) {
    var parent = fso.GetParentFolderName(path);
    if (parent) ensureDir(parent);
    var file = fso.OpenTextFile(path, 2, true, false);
    file.Write(text);
    file.Close();
}

function backupFile(path, backupDir) {
    if (!backupDir || !fso.FileExists(path)) return;
    ensureDir(backupDir);
    var stamp = new Date().getTime();
    fso.CopyFile(path, fso.BuildPath(backupDir, ".wslconfig." + stamp + ".bak"), true);
}

function winToWsl(path) {
    path = String(path).replace(/\r|\n/g, "");
    if (/^\/mnt\//i.test(path) || /^\//.test(path)) return path;
    var match = /^([A-Za-z]):[\\\/]?(.*)$/.exec(path);
    if (!match) return path;
    return "/mnt/" + match[1].toLowerCase() + "/" + match[2].replace(/\\/g, "/");
}

function windowsVersion() {
    var text = runText("ver");
    var match = /([0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?)/.exec(text);
    var version = match ? match[1] : "unknown";
    var parts = version.split(".");
    var build = parts.length >= 3 ? parts[2] : "0";
    WScript.Echo(version + "|" + build);
}

function distroExists(name) {
    var text = runText("wsl.exe -l -q");
    text = text.replace(/\u0000/g, "").replace(/\r/g, "\n");
    var wanted = String(name).toLowerCase();
    var lines = text.split(/\n+/);
    for (var i = 0; i < lines.length; i++) {
        var line = trim(lines[i]).replace(/^\*/, "");
        if (line.toLowerCase() === wanted) WScript.Quit(0);
    }
    WScript.Quit(1);
}

function desiredWslConfig(mode) {
    if (String(mode).toLowerCase() === "mirrored") {
        return "[wsl2]\r\n"
            + "dnsTunneling=true\r\n"
            + "autoProxy=true\r\n"
            + "networkingMode=mirrored\r\n"
            + "firewall=true\r\n";
    }
    return "[wsl2]\r\nlocalhostForwarding=true\r\n";
}

function normalizeNewlines(text) {
    return String(text).replace(/\r\n/g, "\n").replace(/\r/g, "\n").replace(/\s+$/g, "");
}

function wslconfig(path, mode, backupDir, dryRun) {
    var desired = desiredWslConfig(mode);
    var current = readFile(path);
    if (normalizeNewlines(current) === normalizeNewlines(desired)) {
        WScript.Echo("unchanged");
        return;
    }
    if (String(dryRun) === "1") {
        WScript.Echo("would-update");
        return;
    }
    backupFile(path, backupDir);
    writeFile(path, desired);
    WScript.Echo("updated");
}

function escapeRegExp(s) {
    return String(s).replace(/([.*+?^${}()|\[\]\/\\])/g, "\\$1");
}

function decodeJsonString(s) {
    return String(s)
        .replace(/\\u([0-9a-fA-F]{4})/g, function(_, hex) {
            return String.fromCharCode(parseInt(hex, 16));
        })
        .replace(/\\"/g, "\"")
        .replace(/\\\\/g, "\\")
        .replace(/\\\//g, "/")
        .replace(/\\b/g, "\b")
        .replace(/\\f/g, "\f")
        .replace(/\\n/g, "\n")
        .replace(/\\r/g, "\r")
        .replace(/\\t/g, "\t");
}

function jsonField(path, field) {
    var text = readFile(path);
    if (!text) WScript.Quit(1);
    if (!/^\s*\{/.test(text)) WScript.Quit(1);
    if (typeof JSON !== "undefined" && JSON.parse) {
        try {
            var obj = JSON.parse(text);
            if (obj && obj.hasOwnProperty(field)) {
                WScript.Echo(String(obj[field]));
                WScript.Quit(0);
            }
        } catch (e) {
            WScript.Quit(1);
        }
    }
    var re = new RegExp("\"" + escapeRegExp(field) + "\"\\s*:\\s*(\"(?:[^\"\\\\]|\\\\.)*\"|[^,}\\r\\n]+)");
    var match = re.exec(text);
    if (!match) WScript.Quit(1);
    var value = trim(match[1]);
    if (value.charAt(0) === "\"" && value.charAt(value.length - 1) === "\"") {
        value = decodeJsonString(value.substring(1, value.length - 1));
    }
    WScript.Echo(value);
    WScript.Quit(0);
}

function isIPv4(value) {
    var parts = trim(value).split(".");
    if (parts.length !== 4) WScript.Quit(1);
    for (var i = 0; i < parts.length; i++) {
        if (!/^[0-9]+$/.test(parts[i])) WScript.Quit(1);
        var n = Number(parts[i]);
        if (n < 0 || n > 255) WScript.Quit(1);
    }
    WScript.Quit(0);
}

function pad2(n) {
    return n < 10 ? "0" + n : String(n);
}

function localTaskDate(date) {
    return date.getFullYear() + "-"
        + pad2(date.getMonth() + 1) + "-"
        + pad2(date.getDate()) + "T"
        + pad2(date.getHours()) + ":"
        + pad2(date.getMinutes()) + ":"
        + pad2(date.getSeconds());
}

function safeSet(object, property, value) {
    try {
        object[property] = value;
    } catch (e) {
    }
}

function writeKeepalive(path, distro, port) {
    var lines = [
        "@echo off",
        "setlocal EnableExtensions DisableDelayedExpansion",
        "set \"DISTRO=" + String(distro) + "\"",
        "set \"PORT=" + String(port) + "\"",
        "set \"LOG=%LOCALAPPDATA%\\OmOHostBootstrap\\opencode-wsl-keepalive.log\"",
        "if not exist \"%LOCALAPPDATA%\\OmOHostBootstrap\" mkdir \"%LOCALAPPDATA%\\OmOHostBootstrap\" >nul 2>nul",
        "echo %DATE% %TIME% starting OmO OpenCode WSL keepalive>>\"%LOG%\"",
        "set \"WSL_IP=\"",
        "for /f \"tokens=1\" %%I in ('wsl.exe -d %DISTRO% -u root -- hostname -I 2^>nul') do if not defined WSL_IP set \"WSL_IP=%%I\"",
        "if defined WSL_IP (",
        "  netsh.exe interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=%PORT% >>\"%LOG%\" 2>&1",
        "  netsh.exe interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=%PORT% connectaddress=%WSL_IP% connectport=%PORT% >>\"%LOG%\" 2>&1",
        ") else (",
        "  echo %DATE% %TIME% WARN could not determine WSL IP>>\"%LOG%\"",
        ")",
        "echo %DATE% %TIME% entering long-running WSL keepalive>>\"%LOG%\"",
        "wsl.exe -d %DISTRO% -u root -- bash -lc \"systemctl start opencode-serve.service 2>/dev/null || (mkdir -p /root/.local/state/omo-bootstrap; pgrep -af 'opencode serve.*--port %PORT%' >/dev/null || nohup env HOME=/root XDG_CONFIG_HOME=/root/.config XDG_STATE_HOME=/root/.local/state /usr/local/bin/opencode serve --hostname 0.0.0.0 --port %PORT% >/root/.local/state/omo-bootstrap/opencode-serve.log 2>&1 &); exec sleep infinity\" >>\"%LOG%\" 2>&1",
        "set \"KEEPALIVE_EXIT=%ERRORLEVEL%\"",
        "echo %DATE% %TIME% keepalive exited with code %KEEPALIVE_EXIT%>>\"%LOG%\"",
        "exit /b %KEEPALIVE_EXIT%"
    ];
    writeFile(path, lines.join("\r\n") + "\r\n");
}

function writeKeepaliveLauncher(path) {
    var lines = [
        "Option Explicit",
        "",
        "Dim shell, fileSystem, scriptDir, command, exitCode",
        "Set shell = CreateObject(\"WScript.Shell\")",
        "Set fileSystem = CreateObject(\"Scripting.FileSystemObject\")",
        "scriptDir = fileSystem.GetParentFolderName(WScript.ScriptFullName)",
        "command = \"cmd.exe /d /c \" & Chr(34) & Chr(34) & scriptDir & \"\\start-opencode-wsl.cmd\" & Chr(34) & Chr(34)",
        "exitCode = shell.Run(command, 0, True)",
        "WScript.Quit exitCode"
    ];
    writeFile(path, lines.join("\r\n") + "\r\n");
}

function createKeepaliveTask(taskName, launcherPath) {
    var service = new ActiveXObject("Schedule.Service");
    service.Connect();

    var root = service.GetFolder("\\");
    var task = service.NewTask(0);
    var user = shell.ExpandEnvironmentStrings("%USERDOMAIN%\\%USERNAME%");

    task.RegistrationInfo.Description = "Keeps Ubuntu WSL OpenCode service and Windows loopback portproxy alive for OmO.";
    task.Principal.UserId = user;
    task.Principal.LogonType = 3; // TASK_LOGON_INTERACTIVE_TOKEN
    task.Principal.RunLevel = 1; // TASK_RUNLEVEL_HIGHEST

    task.Settings.Enabled = true;
    task.Settings.AllowDemandStart = true;
    task.Settings.StartWhenAvailable = true;
    task.Settings.DisallowStartIfOnBatteries = false;
    task.Settings.StopIfGoingOnBatteries = false;
    task.Settings.ExecutionTimeLimit = "PT0S";
    safeSet(task.Settings, "MultipleInstances", 2); // TASK_INSTANCES_IGNORE_NEW
    safeSet(task.Settings, "RestartCount", 3);
    safeSet(task.Settings, "RestartInterval", "PT1M");

    var logonTrigger = task.Triggers.Create(9); // TASK_TRIGGER_LOGON
    logonTrigger.Enabled = true;
    logonTrigger.UserId = user;

    var timeTrigger = task.Triggers.Create(1); // TASK_TRIGGER_TIME
    timeTrigger.Enabled = true;
    timeTrigger.StartBoundary = localTaskDate(new Date(new Date().getTime() + 60000));
    timeTrigger.Repetition.Interval = "PT5M";
    timeTrigger.Repetition.Duration = "P3650D";
    timeTrigger.Repetition.StopAtDurationEnd = false;

    var action = task.Actions.Create(0); // TASK_ACTION_EXEC
    action.Path = shell.ExpandEnvironmentStrings("%SystemRoot%\\System32\\wscript.exe");
    action.Arguments = "//B //NoLogo \"" + launcherPath + "\"";
    action.WorkingDirectory = fso.GetParentFolderName(launcherPath);

    root.RegisterTaskDefinition(taskName, task, 6, user, null, 3); // TASK_CREATE_OR_UPDATE + TASK_LOGON_INTERACTIVE_TOKEN
}

if (args.length < 1) WScript.Quit(2);
var command = String(args.Item(0)).toLowerCase();
if (command === "windows-version") {
    windowsVersion();
} else if (command === "win-to-wsl") {
    WScript.Echo(winToWsl(args.Item(1)));
} else if (command === "distro-exists") {
    distroExists(args.Item(1));
} else if (command === "wslconfig") {
    wslconfig(args.Item(1), args.Item(2), args.Item(3), args.Item(4));
} else if (command === "json-field") {
    jsonField(args.Item(1), args.Item(2));
} else if (command === "is-ipv4") {
    isIPv4(args.Item(1));
} else if (command === "write-keepalive") {
    writeKeepalive(args.Item(1), args.Item(2), args.Item(3));
} else if (command === "write-keepalive-launcher") {
    writeKeepaliveLauncher(args.Item(1));
} else if (command === "create-keepalive-task") {
    createKeepaliveTask(args.Item(1), args.Item(2));
} else {
    WScript.Echo("Unknown helper command: " + command);
    WScript.Quit(2);
}
