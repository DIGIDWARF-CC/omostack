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

$RepoUrl = "https://github.com/DIGIDWARF-CC/omostack.git"
$DistroName = "Ubuntu"
$OpenCodePort = 4096
$BootstrapRoot = Join-Path $env:LOCALAPPDATA "OmOBootstrap"
$StatePath = Join-Path $BootstrapRoot "state.json"
$LogPath = Join-Path $BootstrapRoot "bootstrap.log"
$Script:PlanOnlyMode = $false
$Script:ActiveDistroName = $null

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
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    Write-Log ("Команда: {0} {1}" -f $FilePath, $psi.Arguments)
    $p = [System.Diagnostics.Process]::Start($psi)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $p.HasExited) {
        $elapsed = $sw.Elapsed.ToString("hh\:mm\:ss")
        Write-Progress -Activity "OmO Bootstrap" -Status "Выполняется: $FilePath $($psi.Arguments) | прошло $elapsed" -PercentComplete -1
        Start-Sleep -Seconds 1
    }
    $sw.Stop()
    Write-Progress -Activity "OmO Bootstrap" -Completed
    Write-Log ("Команда завершена за {0}" -f $sw.Elapsed.ToString("hh\:mm\:ss"))
    if ($p.ExitCode -ne 0) {
        throw "$FilePath завершился с кодом $($p.ExitCode)"
    }
    return ""
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

function Get-SanitizedWindowsUser {
    $name = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    if ($name -match "\\") {
        $name = ($name -split "\\")[-1]
    }
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = $env:USERNAME
    }
    $user = $name.ToLowerInvariant()
    $user = $user -replace "[^a-z0-9_-]", "-"
    $user = $user.Trim("-_")
    if ([string]::IsNullOrWhiteSpace($user)) { $user = "omo" }
    if ($user -match "^[0-9]") { $user = "u$user" }
    if ($user.Length -gt 32) { $user = $user.Substring(0, 32).Trim("-_") }
    if ([string]::IsNullOrWhiteSpace($user)) { $user = "omo" }
    return $user
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

function Normalize-WslOutput {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    return ($Text -replace "`0", "" -replace "`r", "")
}

function Get-WslDistroNames {
    $raw = ""
    try { $raw = Normalize-WslOutput ((& wsl.exe --list --quiet 2>&1) -join "`n") } catch {}
    if (-not $raw) {
        try { $raw = Normalize-WslOutput ((& wsl.exe -l -q 2>&1) -join "`n") } catch {}
    }
    $names = @()
    foreach ($line in ($raw -split "`n")) {
        $name = ($line -replace "^\*", "").Trim()
        if ($name -and $name -notmatch "Windows Subsystem|Copyright|Usage|Ошибка|Error") {
            $names += $name
        }
    }
    return @($names | Select-Object -Unique)
}

function Test-WslDistroRunnable {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    try {
        & wsl.exe -d $Name -u root -- true *> $null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Get-WslDistroVersion {
    param([string]$Name)
    if (-not (Test-WslDistroRunnable $Name)) { return "" }
    try {
        return (Normalize-WslOutput ((& wsl.exe -d $Name -u root -- bash -lc '. /etc/os-release 2>/dev/null; printf "%s" "${VERSION_ID:-unknown}"' 2>$null) -join "`n")).Trim()
    } catch {
        return ""
    }
}

function Resolve-WslDistroName {
    if ($Script:ActiveDistroName) { return $Script:ActiveDistroName }
    $names = @(Get-WslDistroNames)
    $candidates = @($DistroName, "Ubuntu") + $names
    foreach ($name in ($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        if (Test-WslDistroRunnable $name) {
            $version = Get-WslDistroVersion $name
            if ($name -eq $DistroName -or $version -eq "24.04" -or ($name -eq "Ubuntu" -and -not $Script:ActiveDistroName)) {
                $Script:ActiveDistroName = $name
                if ($name -ne $DistroName) {
                    Write-Log "WSL distro '$DistroName' не найден как имя, использую фактический distro '$name' (Ubuntu $version)."
                }
                return $Script:ActiveDistroName
            }
        }
    }
    return $DistroName
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
        $names = @(Get-WslDistroNames)
        $quiet = ($names -join "`n")
        $list = Normalize-WslOutput ((& wsl.exe -l -v 2>&1) -join "`n")
        $result.list_output = $list
        $combined = Normalize-WslOutput ($quiet + "`n" + $list)
        $result.distro = ($combined -match "(?m)^\s*\*?\s*$([regex]::Escape($DistroName))(\s|$)") -or `
            ($names -contains "Ubuntu" -and (Get-WslDistroVersion "Ubuntu") -eq "24.04")
        if ($list -match "\*\s+([^\s]+)") { $result.default_distro = $matches[1] }
    }
    return $result
}

function Test-RebootPending {
    # Проверяем CBS registry key — стандартный способ детекта pending reboot от Windows Installer и DISM
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
        return $true
    }
    # Secondary check: PendingFileRenameOperations (MSI/Setup)
    try {
        $sm = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
        if ($null -ne $sm.PendingFileRenameOperations) { return $true }
    } catch {}
    return $false
}

function Test-FeatureEnabled {
    param([string]$FeatureName, [switch]$PlanOnly)
    try {
        # Пробуем Get-WindowsOptionalFeature (PS5.1 DISM module)
        if (-not $PlanOnly) { Require-Elevation "Для проверки WSL features" "Install" (Get-DefaultTargetPath) }
        $feat = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
        return ($null -ne $feat -and $feat.State -eq 'Enabled')
    } catch {
        # Fallback: DISM CLI
        try {
            if (-not $PlanOnly) { Require-Elevation "Для проверки WSL features" "Install" (Get-DefaultTargetPath) }
            $dismOut = dism.exe /online /get-feature /featurename:$FeatureName 2>&1 | Out-String
            return ($dismOut -match "State\s+:\s+Enabled")
        } catch { return $false }
    }
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

function Ensure-WSLBase {
    # Основная стратегия: wsl --install включает ВСЕ нужные фичи и ставит Ubuntu.
    # Fallback (Windows 10 без встроенного wsl --install): ручное включение feature'ов + ребут.
    param([switch]$PlanOnly)

    if (-not $PlanOnly) {
        Require-Elevation "Для установки WSL могут понадобиться права администратора." "Install" (Get-DefaultTargetPath)
    }

    # Проверяем, работает ли wsl уже
    $wslOk = $false
    try {
        & wsl.exe --version *> $null 2>&1
        if ($LASTEXITCODE -eq 0) { $wslOk = $true }
    } catch {}

    if ($wslOk) {
        Write-Log "WSL уже установлен и работает."
        return
    }

    # Проверяем, есть ли wsl.exe в PATH (может быть установлен но не активирован)
    $hasWslExe = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $hasWslExe) {
        Write-Log "wsl.exe не найден. Включаем компоненты WSL вручную..."

        # Проверяем текущее состояние фичей ДО включения
        $wslState = 'Disabled'
        $vmState = 'Disabled'
        try {
            $wslFeat = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
            if ($null -ne $wslFeat) { $wslState = $wslFeat.State }
        } catch {}
        try {
            $vmFeat = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
            if ($null -ne $vmFeat) { $vmState = $vmFeat.State }
        } catch {}

        Write-Log "Текущее состояние: WSL=$wslState, VMP=$vmState"

        # Включаем только если не Enabled
        if ($wslState -ne 'Enabled') {
            Invoke-Step "Включить компонент Windows Subsystem for Linux" {
                Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
            } -PlanOnly:$PlanOnly
        } else {
            Write-Log "WSL feature уже Enabled, пропускаем."
        }

        if ($vmState -ne 'Enabled') {
            Invoke-Step "Включить компонент Virtual Machine Platform" {
                Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
            } -PlanOnly:$PlanOnly
        } else {
            Write-Log "VMP feature уже Enabled, пропускаем."
        }

        # Re-query state после включения (DISM не сбрасывает State до ребута)
        $wslStateAfter = 'Unknown'
        $vmStateAfter = 'Unknown'
        try {
            $wslFeat2 = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
            if ($null -ne $wslFeat2) { $wslStateAfter = $wslFeat2.State }
        } catch {}
        try {
            $vmFeat2 = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
            if ($null -ne $vmFeat2) { $vmStateAfter = $vmFeat2.State }
        } catch {}

        Write-Log "После включения: WSL=$wslStateAfter, VMP=$vmStateAfter"

        # Если хоть одна фича не Enabled — нужен ребут
        if ($wslStateAfter -ne 'Enabled' -or $vmStateAfter -ne 'Enabled') {
            Write-Log "WSL компоненты включены, но требуют перезагрузку (CBS defer)."
            if (-not $PlanOnly) {
                # Запускаем wsl --install — он сам доделает оставшиеся фичи после ребута
                Write-Log "Запуск wsl --install для завершения активации..."
                Invoke-Native "wsl.exe" @("--install")
            } else {
                Write-Host "[план] wsl --install (завершит активацию фич после ребута)"
            }
        } else {
            # Обе фичи Enabled — пробуем wsl сразу
            Start-Sleep -Seconds 3
            try {
                & wsl.exe --version *> $null 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "WSL компоненты активированы без перезагрузки."
                    return
                }
            } catch {}
        }
    } else {
        # wsl.exe есть, но не работает (exit code != 0 — вероятно WSL_E_WSL_OPTIONAL_COMPONENT_REQUIRED)
        # Это значит фичи включены но не активированы до ребута
        Write-Log "wsl.exe найден но не работает. Активируем компоненты..."

        # Включаем обе фичи на всякий случай (не повредит если уже Enabled)
        Invoke-Step "Включить компонент Windows Subsystem for Linux" {
            Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
        } -PlanOnly:$PlanOnly
        Invoke-Step "Включить компонент Virtual Machine Platform" {
            Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
        } -PlanOnly:$PlanOnly

        Start-Sleep -Seconds 3
        try {
            & wsl.exe --version *> $null 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Log "WSL компоненты активированы без перезагрузки."
                return
            }
        } catch {}

        # Fallback: wsl --install доделает остальное
        if (-not $PlanOnly) {
            Invoke-Native "wsl.exe" @("--install")
        } else {
            Write-Host "[план] wsl --install (завершит активацию фич после ребута)"
        }
    }

    # Если PlanOnly — на этом хватит, дальше пойдёт Ensure-Ubuntu
}

function Test-WSLReady {
    # Использует ProcessStartInfo для надёжного exit code capture в PS5.1 (wsl --status exit 0 = ready)
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "wsl.exe"
        $psi.Arguments = "--status"
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        $finished = $p.WaitForExit(5000)
        if ($finished -and $p.ExitCode -eq 0) { return $true }
    } catch {}
    return $false
}

function Ensure-Ubuntu {
    param([switch]$PlanOnly)
    $status = Get-WslStatus
    if (-not $PlanOnly -and -not $status.distro -and (Test-WslDistroRunnable (Resolve-WslDistroName))) {
        Write-Log "$DistroName не распознан через wsl --list как точное имя, но рабочий Ubuntu-дистрибутив найден. Считаю WSL готовым."
        $status.distro = $true
    }
    if (-not $status.distro) {
        Invoke-Step "Установить $DistroName через WSL без интерактивного первого запуска (обычно 5-20 минут; после установки Windows может попросить перезапуск)" {
            $installError = $null
            try {
                Invoke-Native "wsl.exe" @("--install", "-d", $DistroName, "--no-launch")
            } catch {
                $installError = $_.Exception.Message
                Write-Log "Основная установка WSL вернула ошибку: $installError"
                Write-Log "Пробую fallback через --web-download."
                try {
                    Invoke-Native "wsl.exe" @("--install", "--web-download", "-d", $DistroName, "--no-launch")
                    $installError = $null
                } catch {
                    $installError = $_.Exception.Message
                    Write-Log "Fallback WSL install тоже вернул ошибку: $installError"
                }
            }

            # wsl --install может вернуть success но фичи ещё не активированы (нужен ребут)
            # Ждём и проверяем несколько раз — используем Test-WSLReady для надёжного exit code capture
            $retries = 8
            for ($i = 0; $i -lt $retries; $i++) {
                Start-Sleep -Seconds 5
                if (Test-WSLReady) {
                    Write-Log "WSL стал активен после $($i * 5 + 5) сек ожидания."
                    break
                }

                # Если wsl --install уже запустился, ждём дальше — он сам активирует фичи
                $hasWsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
                if ($hasWsl) {
                    try {
                        $psi2 = New-Object System.Diagnostics.ProcessStartInfo
                        $psi2.FileName = "wsl.exe"
                        $psi2.Arguments = "--list --quiet 2>$null"
                        $psi2.RedirectStandardError = $true
                        $psi2.UseShellExecute = $false
                        $p2 = [System.Diagnostics.Process]::Start($psi2)
                        $done = $p2.WaitForExit(3000)
                        if ($done -and $p2.ExitCode -eq 0) {
                            Write-Log "Ubuntu найден после $($i * 5 + 5) сек ожидания."
                            break
                        }
                    } catch {}
                }

                Write-Log "Ожидание WSL активности... попытка $((($i)+1))/$retries"
            }

            # Финальная проверка
            $afterInstall = Get-WslStatus
            $resolved = Resolve-WslDistroName
            if ($afterInstall.distro -or (Test-WslDistroRunnable $resolved)) {
                Write-Log "Ubuntu-дистрибутив найден после установки как '$resolved'. Продолжаю бутстрап."
            } else {
                # Проверяем, есть ли wsl.exe — если да, но не работает, нужен ребут
                $hasWsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
                if ($hasWsl) {
                    Write-Host ""
                    Write-Host "WSL компоненты включены, но требуют перезагрузку." -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "Что делать:"
                    Write-Host "  1. Перезагрузи компьютер (обязательно!)"
                    if (-not $PlanOnly) {
                        Write-Host "    (нажми Y для перезагрузки сейчас, или любую другую клавишу для выхода)" -ForegroundColor Yellow
                        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                        if ($key.Character -eq 'y' -or $key.Character -eq 'Y') {
                            Write-Log "Перезагрузка компьютера..."
                            Restart-Computer -Force
                            exit 0
                        }
                    } else {
                        Write-Host "    (в режиме плана — перезагрузи вручную)" -ForegroundColor Yellow
                    }
                    Write-Host "  2. После перезагрузки запусти этот же omo_bootstrap.ps1 ещё раз,"
                    Write-Host "     пункт 1 'Установить / продолжить'."
                    Write-Host ""
                    Write-Host "Скрипт продолжит установку Ubuntu после ребута." -ForegroundColor Yellow
                    throw "WSL требует перезагрузку. Перезагрузи и запусти скрипт повторно."
                }

                Write-Host ""
                Write-Host "WSL/Ubuntu ещё не готовы для продолжения."
                Write-Host "Что делать:"
                Write-Host "  1. Если Windows просит перезагрузку - перезагрузи компьютер."
                Write-Host "  2. Если установка Ubuntu ещё скачивается в этом окне - дождись завершения."
                Write-Host "  3. Потом запусти этот же omo_bootstrap.ps1 ещё раз, пункт 1 'Установить / продолжить'."
                Write-Host "  4. Для диагностики выполни: wsl.exe --list --verbose"
                if ($installError) { Write-Host "Последняя ошибка WSL: $installError" }
                throw "$DistroName не найден в списке WSL после установки."
            }
        } -PlanOnly:$PlanOnly
    } else {
        Write-Log "$(Resolve-WslDistroName) уже установлен."
    }
    $resolvedDistro = if ($PlanOnly) { $DistroName } else { Resolve-WslDistroName }
    Invoke-Step "Сделать $resolvedDistro дистрибутивом WSL по умолчанию" {
        Invoke-Native "wsl.exe" @("--set-default", $resolvedDistro)
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
    Invoke-Native "wsl.exe" @("-d", (Resolve-WslDistroName), "-u", "root", "--", "bash", "-lc", $Command)
}

function Invoke-WslUser {
    param([string]$Command)
    Invoke-Native "wsl.exe" @("-d", (Resolve-WslDistroName), "--", "bash", "-lc", $Command)
}

function Ensure-WslDefaultUser {
    param([switch]$PlanOnly)
    $unixUser = Get-SanitizedWindowsUser
    Invoke-Step "Создать default Unix user '$unixUser' из Windows whoami и подготовить sudo без пароля" {
        Invoke-WslRoot "set -e; if ! id -u '$unixUser' >/dev/null 2>&1; then useradd -m -s /bin/bash -G sudo '$unixUser'; fi; passwd -d '$unixUser' >/dev/null 2>&1 || true; printf '%s ALL=(ALL) NOPASSWD:ALL\n' '$unixUser' > /etc/sudoers.d/90-omo-bootstrap-user; chmod 440 /etc/sudoers.d/90-omo-bootstrap-user"
    } -PlanOnly:$PlanOnly
    return $unixUser
}

function Ensure-WslInsideConfig {
    param([switch]$PlanOnly)
    $unixUser = Get-SanitizedWindowsUser
    $conf = @"
[boot]
systemd=true

[interop]
enabled=true
appendWindowsPath=true

[automount]
enabled=true
root=/mnt/

[user]
default=$unixUser
"@
    $escaped = $conf -replace "'", "'\''"
    Invoke-Step "Настроить /etc/wsl.conf для systemd, interop, автомонтирования /mnt и default user '$unixUser'" {
        Invoke-WslRoot "printf '%s\n' '$escaped' > /etc/wsl.conf"
        wsl.exe --shutdown | Out-Null
    } -PlanOnly:$PlanOnly
}

function Ensure-WslPackagesAndOpenCode {
    param([switch]$PlanOnly)
    Invoke-Step "Установить базовые пакеты WSL и OpenCode" {
        $cmd = @'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git nodejs npm procps iproute2

if ! command -v opencode >/dev/null 2>&1 && [ ! -x /root/.opencode/bin/opencode ]; then
    curl -fsSL https://opencode.ai/install | bash || npm install -g opencode-ai
fi

opencode_bin=""
for candidate in /usr/local/bin/opencode /root/.opencode/bin/opencode /root/.local/bin/opencode /root/.local/share/opencode/bin/opencode; do
    if [ -f "$candidate" ] || [ -L "$candidate" ]; then
        chmod +x "$candidate" 2>/dev/null || true
    fi
    if [ -x "$candidate" ]; then
        opencode_bin="$candidate"
        break
    fi
done
if [ -z "$opencode_bin" ]; then
    opencode_bin="$(bash -lc 'command -v opencode' 2>/dev/null || true)"
fi
if [ -z "$opencode_bin" ]; then
    opencode_bin="$(find /root /usr/local /opt -maxdepth 7 \( -type f -o -type l \) -name opencode 2>/dev/null | head -1 || true)"
    if [ -n "$opencode_bin" ]; then
        chmod +x "$opencode_bin" 2>/dev/null || true
    fi
fi
if [ -z "$opencode_bin" ] || [ ! -x "$opencode_bin" ]; then
    echo "ERROR: opencode binary not found after install" >&2
    echo "Diagnostic candidates:" >&2
    find /root /usr/local /opt -maxdepth 7 \( -name opencode -o -name '*opencode*' \) -print 2>/dev/null | head -100 >&2 || true
    exit 30
fi
if [ "$opencode_bin" != /usr/local/bin/opencode ]; then
    ln -sf "$opencode_bin" /usr/local/bin/opencode
fi
chmod +x "$opencode_bin" /usr/local/bin/opencode
cat > /etc/profile.d/opencode.sh <<'PROFILE'
export PATH=/usr/local/bin:/root/.opencode/bin:$PATH
PROFILE
/usr/local/bin/opencode --version
'@
        Invoke-WslRoot $cmd
    } -PlanOnly:$PlanOnly
}

function Ensure-WslOpenCodeConfig {
    param([switch]$PlanOnly)
    $unixUser = Get-SanitizedWindowsUser
    $config = @'
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {},
  "plugin": []
}
'@
    $escaped = $config -replace "'", "'\''"
    Invoke-Step "Создать минимальный конфиг OpenCode, если его ещё нет" {
        $cmd = @'
set -e
unix_user='__UNIX_USER__'
config='__CONFIG__'
mkdir -p /root/.config/opencode
test -f /root/.config/opencode/opencode.jsonc || printf '%s\n' "$config" > /root/.config/opencode/opencode.jsonc
if id -u "$unix_user" >/dev/null 2>&1; then
    user_home="$(getent passwd "$unix_user" | cut -d: -f6)"
    mkdir -p "$user_home/.config/opencode"
    test -f "$user_home/.config/opencode/opencode.jsonc" || printf '%s\n' "$config" > "$user_home/.config/opencode/opencode.jsonc"
    chown -R "$unix_user:$unix_user" "$user_home/.config"
fi
'@
        $cmd = $cmd.Replace("__UNIX_USER__", $unixUser).Replace("__CONFIG__", $escaped)
        Invoke-WslRoot $cmd
    } -PlanOnly:$PlanOnly
}

function Ensure-OpenCodeSystemdService {
    param([string]$WslRepoPath, [switch]$PlanOnly)
    $safeRepo = $WslRepoPath -replace "'", "'\''"
    Invoke-Step "Создать и, если systemd активен, запустить opencode-serve.service" {
        $cmd = @'
set -e
repo_path='__WSL_REPO__'
opencode_port='__OPENCODE_PORT__'
opencode_bin="$(command -v opencode || true)"
if [ -z "$opencode_bin" ] && [ -x /usr/local/bin/opencode ]; then
    opencode_bin=/usr/local/bin/opencode
fi
if [ -z "$opencode_bin" ]; then
    echo "ERROR: opencode is not in PATH for service setup" >&2
    exit 31
fi
cat > /etc/systemd/system/opencode-serve.service <<SVC
[Unit]
Description=OpenCode headless server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=$repo_path
Environment=HOME=/root
Environment=XDG_CONFIG_HOME=/root/.config
ExecStart=/usr/local/bin/opencode serve --hostname 0.0.0.0 --port $opencode_port
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
SVC
if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl enable opencode-serve.service
    systemctl restart opencode-serve.service
    systemctl --no-pager --full status opencode-serve.service || true
else
    echo "systemd is not active yet; service file was written, one-shot serve will be used now"
fi
'@
        $cmd = $cmd.Replace("__WSL_REPO__", $safeRepo).Replace("__OPENCODE_PORT__", [string]$OpenCodePort)
        Invoke-WslRoot $cmd
    } -PlanOnly:$PlanOnly
}

function Start-OpenCodeServe {
    param([string]$WslRepoPath, [switch]$PlanOnly)
    $safeRepo = $WslRepoPath -replace "'", "'\''"
    Invoke-Step "Запустить разовый OpenCode web server в WSL для проекта $WslRepoPath" {
        $cmd = @'
set -e
repo_path='__WSL_REPO__'
opencode_port='__OPENCODE_PORT__'
mkdir -p /root/.local/state/omo
cd "$repo_path"
opencode_bin="$(command -v opencode || true)"
if [ -z "$opencode_bin" ]; then
    opencode_bin=/usr/local/bin/opencode
fi
if [ ! -x "$opencode_bin" ]; then
    echo "ERROR: opencode binary is not executable for serve" >&2
    exit 32
fi
if ss -tln 2>/dev/null | grep -q ":$opencode_port "; then
    echo "OpenCode already listens on port $opencode_port"
else
    nohup "$opencode_bin" serve --hostname 0.0.0.0 --port "$opencode_port" > /root/.local/state/omo/opencode-serve.log 2>&1 &
fi
sleep 4
if ! ss -tln 2>/dev/null | grep -q ":$opencode_port "; then
    echo "ERROR: OpenCode did not start listening on port $opencode_port" >&2
    tail -120 /root/.local/state/omo/opencode-serve.log >&2 || true
    exit 33
fi
curl -fsS --max-time 5 "http://127.0.0.1:$opencode_port/" >/dev/null
'@
        $cmd = $cmd.Replace("__WSL_REPO__", $safeRepo).Replace("__OPENCODE_PORT__", [string]$OpenCodePort)
        Invoke-WslRoot $cmd
    } -PlanOnly:$PlanOnly
}

function Get-WslIp {
    try {
        $ip = (& wsl.exe -d (Resolve-WslDistroName) -- bash -lc "hostname -I | cut -d' ' -f1" 2>$null).Trim()
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
        $netsh = Join-Path $env:WINDIR "System32\netsh.exe"
        & $netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=$OpenCodePort | Out-Null
        & $netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=$OpenCodePort connectaddress=$wslIp connectport=$OpenCodePort | Out-Null
        if (-not (Get-NetFirewallRule -DisplayName "OmO OpenCode local web" -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName "OmO OpenCode local web" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $OpenCodePort -Profile Private,Domain | Out-Null
        }
        $curl = Join-Path $env:WINDIR "System32\curl.exe"
        if (Test-Path $curl) {
            & $curl -fsS --max-time 8 "http://127.0.0.1:$OpenCodePort/" | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Windows URL проверен: http://127.0.0.1:$OpenCodePort/"
            } else {
                Write-Log "Windows URL пока не ответил через curl.exe. Проверь WSL serve log и попробуй обновить браузер через несколько секунд."
            }
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

        Ensure-WSLBase -PlanOnly:$PlanOnly
        Ensure-Ubuntu -PlanOnly:$PlanOnly
        Ensure-WslDefaultUser -PlanOnly:$PlanOnly | Out-Null
        Ensure-WslConfig -PlanOnly:$PlanOnly
        Ensure-WslInsideConfig -PlanOnly:$PlanOnly
        if (-not $PlanOnly) { Mark-Checkpoint $state "wsl" "present" $DistroName }

        Ensure-WslPackagesAndOpenCode -PlanOnly:$PlanOnly
        Ensure-WslOpenCodeConfig -PlanOnly:$PlanOnly
        Ensure-OpenCodeSystemdService -WslRepoPath $wslRepo -PlanOnly:$PlanOnly
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

function Show-Pause {
    param([switch]$IsError)
    if ($Mode -eq "Menu") { return }
    Write-Host ""
    if ($IsError) { Write-Host "Нажмите любую клавишу для выхода..." }
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
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
    Ensure-Ubuntu
    Ensure-WslDefaultUser | Out-Null
    Ensure-WslConfig
    Ensure-WslInsideConfig
    if (Test-Path $target) {
        $wslRepo = Convert-ToWslPath $target
        Ensure-WslPackagesAndOpenCode
        Ensure-WslOpenCodeConfig
        Ensure-OpenCodeSystemdService -WslRepoPath $wslRepo
        Start-OpenCodeServe -WslRepoPath $wslRepo
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

try {
    switch ($Mode) {
        "Menu" { Show-Menu; return }
        "Install" { Run-Install; Show-Pause; return }
        "Plan" { Run-Install -PlanOnly; Show-Pause; return }
        "Status" { Show-Status; Show-Pause; return }
        "Repair" { Repair-Bootstrap; Show-Pause; return }
        "UninstallBootstrapArtifacts" { Remove-BootstrapArtifacts; Show-Pause; return }
    }
} catch [System.Exception] {
    Write-Host ""
    Write-Host "=== ОШИБКА ===" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($_.ScriptStackTrace) { Write-Host ""; Write-Host $_.ScriptStackTrace }
    Show-Pause -IsError
}
