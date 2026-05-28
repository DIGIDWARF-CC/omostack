<# 
OmO Bootstrap для человека в Windows.
Совместим с PowerShell 5.1, умеет продолжать установку и безопасен для повторного запуска.
#>
[CmdletBinding()]
param(
    [ValidateSet("Menu", "Install", "Status", "Plan", "Repair", "UninstallBootstrapArtifacts")]
    [string]$Mode = "Menu",
    [string]$TargetPath = "",
    [switch]$NoElevate,
    [switch]$Help
)

$ErrorActionPreference = "Stop"
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding = [Console]::OutputEncoding
} catch {}

$RepoUrl = "https://gitlab.kokoc.com/kg/crmbitrix-bitrix-crm/omo.git"
$DistroName = "Ubuntu-24.04"
$OpenCodePort = 4096
$BootstrapRoot = Join-Path $env:LOCALAPPDATA "OmOBootstrap"
$StatePath = Join-Path $BootstrapRoot "state.json"
$LogPath = Join-Path $BootstrapRoot "bootstrap.log"
$Script:PlanOnlyMode = $false

function Write-Log {
    param([string]$Message)
    if ($Script:PlanOnlyMode) {
        Write-Host $Message
        return
    }
    if (-not (Test-Path $BootstrapRoot)) {
        New-Item -ItemType Directory -Path $BootstrapRoot -Force | Out-Null
    }
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"), $Message
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
    Write-Host $Message
}

function Show-Help {
    Write-Host "OmO Bootstrap"
    Write-Host ""
    Write-Host "Использование:"
    Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap-for-human\omo_bootstrap.ps1"
    Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap-for-human\omo_bootstrap.ps1 -Mode Install -TargetPath S:\FastNeuros\omo"
    Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap-for-human\omo_bootstrap.ps1 -Mode Plan -TargetPath S:\FastNeuros\omo"
    Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap-for-human\omo_bootstrap.ps1 -Mode Status"
    Write-Host ""
    Write-Host "Режимы:"
    Write-Host "  Menu                         Интерактивное меню"
    Write-Host "  Install                      Установить или продолжить установку"
    Write-Host "  Plan                         Показать план без изменений в системе"
    Write-Host "  Status                       Показать текущее состояние"
    Write-Host "  Repair                       Починить WSL config, serve и portproxy"
    Write-Host "  UninstallBootstrapArtifacts  Убрать portproxy/firewall-артефакты бутстраппера"
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Save-State {
    param([hashtable]$State)
    if ($Script:PlanOnlyMode) { return }
    if (-not (Test-Path $BootstrapRoot)) {
        New-Item -ItemType Directory -Path $BootstrapRoot -Force | Out-Null
    }
    $State | ConvertTo-Json -Depth 8 | Set-Content -Path $StatePath -Encoding UTF8
}

function ConvertTo-PlainHashtable {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [hashtable]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $Value.Keys) { $result[$key] = ConvertTo-PlainHashtable $Value[$key] }
        return $result
    }
    if ($Value -is [pscustomobject]) {
        $result = @{}
        $Value.PSObject.Properties | ForEach-Object { $result[$_.Name] = ConvertTo-PlainHashtable $_.Value }
        return $result
    }
    return $Value
}

function Load-State {
    if (Test-Path $StatePath) {
        try {
            $obj = Get-Content -Path $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
            $state = ConvertTo-PlainHashtable $obj
            if (-not $state.ContainsKey("checkpoints") -or $null -eq $state["checkpoints"]) {
                $state["checkpoints"] = @{}
            }
            return $state
        } catch {
            Write-Log "Файл состояния не читается, начинаю с чистого состояния: $($_.Exception.Message)"
        }
    }
    return @{
        repo_url = $RepoUrl
        distro = $DistroName
        port = $OpenCodePort
        checkpoints = @{}
    }
}

function Mark-Checkpoint {
    param([hashtable]$State, [string]$Name, [string]$Status, [string]$Detail)
    if (-not $State.ContainsKey("checkpoints") -or $null -eq $State["checkpoints"]) {
        $State["checkpoints"] = @{}
    }
    $State["checkpoints"][$Name] = @{
        status = $Status
        detail = $Detail
        time = (Get-Date).ToString("o")
    }
    Save-State $State
}

function Require-Elevation {
    param([string]$Reason, [string]$ModeToRun, [string]$PathToUse)
    if ((Test-IsAdmin) -or $NoElevate) { return }
    Write-Log "Нужны права администратора: $Reason"
    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`"",
        "-Mode", $ModeToRun
    )
    if ($PathToUse) {
        $args += @("-TargetPath", "`"$PathToUse`"")
    }
    Start-Process -FilePath "powershell.exe" -ArgumentList ($args -join " ") -Verb RunAs | Out-Null
    exit 0
}

function Invoke-Step {
    param([string]$Description, [scriptblock]$Action, [switch]$PlanOnly)
    if ($PlanOnly) {
        Write-Host "[план] $Description"
        return $null
    }
    Write-Log "[запуск] $Description"
    return & $Action
}

function Invoke-Native {
    param([string]$FilePath, [string[]]$Arguments)
    function Quote-NativeArg {
        param([string]$Arg)
        if ($Arg -match '[\s"]') {
            return '"' + ($Arg -replace '"', '\"') + '"'
        }
        return $Arg
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = (($Arguments | ForEach-Object { Quote-NativeArg $_ }) -join " ")
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if ($stdout.Trim()) { Write-Log $stdout.Trim() }
    if ($stderr.Trim()) { Write-Log $stderr.Trim() }
    if ($p.ExitCode -ne 0) {
        throw "$FilePath завершился с кодом $($p.ExitCode)"
    }
    return $stdout
}

function Convert-ToWslPath {
    param([string]$WindowsPath)
    $full = [System.IO.Path]::GetFullPath($WindowsPath)
    if ($full -notmatch "^([A-Za-z]):\\(.*)$") {
        throw "Для преобразования в WSL-путь поддерживаются только локальные диски Windows: $full"
    }
    $drive = $matches[1].ToLowerInvariant()
    $rest = $matches[2] -replace "\\", "/"
    return "/mnt/$drive/$rest"
}

function Get-DefaultTargetPath {
    if ($TargetPath) { return $TargetPath }
    $state = Load-State
    if ($state.ContainsKey("target_path") -and $state["target_path"]) {
        return [string]$state["target_path"]
    }
    return (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "omo")
}

function Read-TargetPath {
    $default = Get-DefaultTargetPath
    $answer = Read-Host "Куда установить OmO? [$default]"
    if ([string]::IsNullOrWhiteSpace($answer)) { return $default }
    return $answer
}

function Test-Windows11_22H2OrNewer {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    return ($build -ge 22621)
}

function Get-WslStatus {
    $result = @{
        wsl = $false
        distro = $false
        default_distro = ""
        version_output = ""
        list_output = ""
    }
    try {
        $result.version_output = (& wsl.exe --version 2>&1) -join "`n"
        $result.wsl = $true
    } catch {
        try {
            $result.list_output = (& wsl.exe -l -v 2>&1) -join "`n"
            $result.wsl = $true
        } catch {}
    }
    if ($result.wsl) {
        $list = (& wsl.exe -l -v 2>&1) -join "`n"
        $result.list_output = $list
        $result.distro = ($list -match [regex]::Escape($DistroName))
        if ($list -match "\*\s+([^\s]+)") { $result.default_distro = $matches[1] }
    }
    return $result
}

function Ensure-Git {
    param([switch]$PlanOnly)
    if (Get-Command git.exe -ErrorAction SilentlyContinue) {
        Write-Log "Git найден."
        return
    }
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw "Git не найден, а winget недоступен. Установи Git for Windows или добавь git.exe в PATH."
    }
    Invoke-Step "Установить Git for Windows через winget" {
        Invoke-Native "winget.exe" @("install", "--id", "Git.Git", "-e", "--source", "winget", "--accept-package-agreements", "--accept-source-agreements")
    } -PlanOnly:$PlanOnly
}

function Ensure-Repo {
    param([string]$PathToUse, [switch]$PlanOnly)
    $parent = Split-Path -Parent $PathToUse
    Invoke-Step "Создать родительскую папку репозитория: $parent" {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    } -PlanOnly:$PlanOnly
    if (Test-Path (Join-Path $PathToUse ".git")) {
        Write-Log "Репозиторий OmO уже есть в $PathToUse"
        return
    }
    Invoke-Step "Склонировать репозиторий OmO в $PathToUse" {
        Invoke-Native "git.exe" @("clone", $RepoUrl, $PathToUse)
    } -PlanOnly:$PlanOnly
}

function Ensure-WslFeature {
    param([switch]$PlanOnly)
    if (-not $PlanOnly) {
        Require-Elevation "Для включения компонентов WSL могут понадобиться права администратора." "Install" (Get-DefaultTargetPath)
    }
    Invoke-Step "Включить компонент Windows Subsystem for Linux" {
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
    } -PlanOnly:$PlanOnly
    Invoke-Step "Включить компонент Virtual Machine Platform" {
        Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
    } -PlanOnly:$PlanOnly
}

function Ensure-Ubuntu {
    param([switch]$PlanOnly)
    $status = Get-WslStatus
    if (-not $status.distro) {
        Invoke-Step "Установить $DistroName через WSL" {
            try {
                Invoke-Native "wsl.exe" @("--install", "-d", $DistroName)
            } catch {
                Write-Log "Основная установка WSL не удалась, пробую fallback через --web-download."
                Invoke-Native "wsl.exe" @("--install", "--web-download", "-d", $DistroName)
            }
        } -PlanOnly:$PlanOnly
    } else {
        Write-Log "$DistroName уже установлен."
    }
    Invoke-Step "Сделать $DistroName дистрибутивом WSL по умолчанию" {
        Invoke-Native "wsl.exe" @("--set-default", $DistroName)
    } -PlanOnly:$PlanOnly
}

function Ensure-WslConfig {
    param([switch]$PlanOnly)
    $wslConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
    $networkMode = "best-effort"
    if (Test-Windows11_22H2OrNewer) { $networkMode = "mirrored" }
    $content = @"
[wsl2]
localhostForwarding=true
dnsTunneling=true
autoProxy=true
"@
    if ($networkMode -eq "mirrored") {
        $content += "`nnetworkingMode=mirrored`nfirewall=true`n"
    }
    Invoke-Step "Записать Windows-конфиг WSL в $wslConfigPath (VPN-режим: $networkMode)" {
        Set-Content -Path $wslConfigPath -Value $content -Encoding ASCII
        wsl.exe --shutdown | Out-Null
    } -PlanOnly:$PlanOnly
}

function Invoke-WslRoot {
    param([string]$Command)
    Invoke-Native "wsl.exe" @("-d", $DistroName, "-u", "root", "--", "bash", "-lc", $Command)
}

function Invoke-WslUser {
    param([string]$Command)
    Invoke-Native "wsl.exe" @("-d", $DistroName, "--", "bash", "-lc", $Command)
}

function Ensure-WslInsideConfig {
    param([switch]$PlanOnly)
    $conf = @"
[boot]
systemd=true

[interop]
enabled=true
appendWindowsPath=true

[automount]
enabled=true
root=/mnt/
"@
    $escaped = $conf -replace "'", "'\''"
    Invoke-Step "Настроить /etc/wsl.conf для systemd, interop и автомонтирования /mnt" {
        Invoke-WslRoot "printf '%s\n' '$escaped' > /etc/wsl.conf"
        wsl.exe --shutdown | Out-Null
    } -PlanOnly:$PlanOnly
}

function Ensure-WslPackagesAndOpenCode {
    param([switch]$PlanOnly)
    Invoke-Step "Установить базовые пакеты WSL и OpenCode" {
        Invoke-WslRoot "export DEBIAN_FRONTEND=noninteractive; apt-get update; apt-get install -y ca-certificates curl git nodejs npm; if ! command -v opencode >/dev/null 2>&1; then curl -fsSL https://opencode.ai/install | bash || npm install -g opencode-ai; fi; if [ -x /root/.opencode/bin/opencode ] && [ ! -e /usr/local/bin/opencode ]; then ln -s /root/.opencode/bin/opencode /usr/local/bin/opencode; fi"
    } -PlanOnly:$PlanOnly
}

function Ensure-WslOpenCodeConfig {
    param([switch]$PlanOnly)
    $config = @'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {},
  "plugin": []
}
'@
    $escaped = $config -replace "'", "'\''"
    Invoke-Step "Создать минимальный конфиг OpenCode, если его ещё нет" {
        Invoke-WslRoot "mkdir -p /root/.config/opencode; test -f /root/.config/opencode/opencode.jsonc || printf '%s\n' '$escaped' > /root/.config/opencode/opencode.jsonc"
    } -PlanOnly:$PlanOnly
}

function Start-OpenCodeServe {
    param([string]$WslRepoPath, [switch]$PlanOnly)
    Invoke-Step "Запустить разовый OpenCode web server в WSL для проекта $WslRepoPath" {
        Invoke-WslRoot "mkdir -p /root/.local/state/omo; cd '$WslRepoPath'; if ! ss -tln 2>/dev/null | grep -q ':$OpenCodePort '; then nohup opencode serve --hostname 0.0.0.0 --port $OpenCodePort --log-level INFO > /root/.local/state/omo/opencode-serve.log 2>&1 & fi"
    } -PlanOnly:$PlanOnly
}

function Get-WslIp {
    try {
        $ip = (& wsl.exe -d $DistroName -- bash -lc "hostname -I | cut -d' ' -f1" 2>$null).Trim()
        if ($ip) { return $ip }
    } catch {}
    return "127.0.0.1"
}

function Ensure-PortProxy {
    param([switch]$PlanOnly)
    if (-not $PlanOnly) {
        Require-Elevation "Для изменения netsh portproxy/firewall нужны права администратора." "Install" (Get-DefaultTargetPath)
    }
    if ($PlanOnly) { $wslIp = "<текущий-wsl-ip>" } else { $wslIp = Get-WslIp }
    Invoke-Step "Настроить Windows portproxy 127.0.0.1:$OpenCodePort -> ${wslIp}:$OpenCodePort" {
        & netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=$OpenCodePort | Out-Null
        & netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=$OpenCodePort connectaddress=$wslIp connectport=$OpenCodePort | Out-Null
        if (-not (Get-NetFirewallRule -DisplayName "OmO OpenCode local web" -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName "OmO OpenCode local web" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $OpenCodePort -Profile Private,Domain | Out-Null
        }
    } -PlanOnly:$PlanOnly
}

function Run-Install {
    param([switch]$PlanOnly)
    $previousPlanMode = $Script:PlanOnlyMode
    $Script:PlanOnlyMode = [bool]$PlanOnly
    try {
    $target = Get-DefaultTargetPath
    if (-not $TargetPath -and -not $PlanOnly) { $target = Read-TargetPath }
    $state = Load-State
    $state["target_path"] = $target
    $state["repo_url"] = $RepoUrl
    $state["distro"] = $DistroName
    if (-not $PlanOnly) { Save-State $state }

    Write-Log "Целевая папка: $target"
    $wslRepo = Convert-ToWslPath $target
    Write-Log "Путь проекта в WSL: $wslRepo"

    Ensure-Git -PlanOnly:$PlanOnly
    Ensure-Repo -PathToUse $target -PlanOnly:$PlanOnly
    if (-not $PlanOnly) { Mark-Checkpoint $state "repo" "present" $target }

    Ensure-WslFeature -PlanOnly:$PlanOnly
    Ensure-Ubuntu -PlanOnly:$PlanOnly
    Ensure-WslConfig -PlanOnly:$PlanOnly
    Ensure-WslInsideConfig -PlanOnly:$PlanOnly
    if (-not $PlanOnly) { Mark-Checkpoint $state "wsl" "present" $DistroName }

    Ensure-WslPackagesAndOpenCode -PlanOnly:$PlanOnly
    Ensure-WslOpenCodeConfig -PlanOnly:$PlanOnly
    Start-OpenCodeServe -WslRepoPath $wslRepo -PlanOnly:$PlanOnly
    Ensure-PortProxy -PlanOnly:$PlanOnly
    if (-not $PlanOnly) { Mark-Checkpoint $state "opencode_web" "present" "http://127.0.0.1:$OpenCodePort/" }

    Write-Host ""
    Write-Host "Бутстрап OmO завершён."
    Write-Host "Репозиторий: $target"
    Write-Host "Путь в WSL:  $wslRepo"
    Write-Host "OpenCode:    http://127.0.0.1:$OpenCodePort/"
    } finally {
        $Script:PlanOnlyMode = $previousPlanMode
    }
}

function Show-Status {
    $state = Load-State
    Write-Host "=== Статус OmO Bootstrap ==="
    Write-Host "Состояние: $StatePath"
    Write-Host "Журнал:    $LogPath"
    Write-Host "Репо:      $($state['target_path'])"
    $wsl = Get-WslStatus
    Write-Host "WSL установлен: $($wsl.wsl)"
    Write-Host "$DistroName установлен: $($wsl.distro)"
    Write-Host "Дистрибутив по умолчанию: $($wsl.default_distro)"
    Write-Host ""
    if ($state["checkpoints"]) {
        Write-Host "Чекпоинты:"
        foreach ($key in $state["checkpoints"].Keys) {
            $checkpoint = $state["checkpoints"][$key]
            Write-Host ("  {0}: {1}" -f $key, $checkpoint["status"])
        }
    }
}

function Repair-Bootstrap {
    $target = Get-DefaultTargetPath
    Write-Log "Ремонт использует целевую папку: $target"
    Ensure-WslConfig
    Ensure-WslInsideConfig
    if (Test-Path $target) {
        Start-OpenCodeServe -WslRepoPath (Convert-ToWslPath $target)
        Ensure-PortProxy
    }
}

function Remove-BootstrapArtifacts {
    Require-Elevation "Для очистки portproxy/firewall могут понадобиться права администратора." "UninstallBootstrapArtifacts" ""
    Write-Log "Удаляю portproxy и firewall rule бутстраппера OmO."
    & netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=$OpenCodePort | Out-Null
    Get-NetFirewallRule -DisplayName "OmO OpenCode local web" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Write-Log "Состояние бутстраппера оставлено в $BootstrapRoot для аудита. При необходимости его можно удалить вручную."
}

function Show-Menu {
    while ($true) {
        Write-Host ""
        Write-Host "=== OmO Bootstrap ==="
        Write-Host "1) Установить / продолжить"
        Write-Host "2) Показать план без изменений"
        Write-Host "3) Статус"
        Write-Host "4) Починить сеть / serve"
        Write-Host "5) Убрать portproxy/firewall-артефакты бутстраппера"
        Write-Host "0) Выход"
        $choice = Read-Host "Выбери пункт"
        switch ($choice) {
            "1" { Run-Install; return }
            "2" { Run-Install -PlanOnly; return }
            "3" { Show-Status }
            "4" { Repair-Bootstrap; return }
            "5" { Remove-BootstrapArtifacts; return }
            "0" { return }
            default { Write-Host "Неизвестный пункт меню." }
        }
    }
}

if ($Help) {
    Show-Help
    exit 0
}

switch ($Mode) {
    "Menu" { Show-Menu }
    "Install" { Run-Install }
    "Plan" { Run-Install -PlanOnly }
    "Status" { Show-Status }
    "Repair" { Repair-Bootstrap }
    "UninstallBootstrapArtifacts" { Remove-BootstrapArtifacts }
}
