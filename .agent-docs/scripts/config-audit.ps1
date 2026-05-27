[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = "Continue"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")

function Write-Audit {
    param([string]$Name, [string]$Status, [string]$Detail)
    [pscustomobject]@{ check = $Name; status = $Status; detail = $Detail } | ConvertTo-Json -Compress
}

function Test-JsonReadable {
    param([string]$Path)
    try {
        $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $withoutLineComments = ($text -split "`n" | ForEach-Object { $_ -replace '^\s*//.*$', '' }) -join "`n"
        $withoutLineComments | ConvertFrom-Json -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

$configRoot = Join-Path $env:APPDATA "opencode"
$projectConfigRoot = Join-Path $RepoRoot ".opencode"
$candidates = @(
    (Join-Path $configRoot "opencode.json"),
    (Join-Path $configRoot "opencode.jsonc"),
    (Join-Path $configRoot "oh-my-openagent.json"),
    (Join-Path $configRoot "oh-my-openagent.jsonc"),
    (Join-Path $configRoot "oh-my-opencode.json"),
    (Join-Path $configRoot "oh-my-opencode.jsonc"),
    (Join-Path $projectConfigRoot "oh-my-openagent.json"),
    (Join-Path $projectConfigRoot "oh-my-openagent.jsonc"),
    (Join-Path $projectConfigRoot "oh-my-opencode.json"),
    (Join-Path $projectConfigRoot "oh-my-opencode.jsonc")
)

foreach ($path in $candidates) {
    if (Test-Path -LiteralPath $path) {
        $readable = Test-JsonReadable $path
        if ($readable) {
            Write-Audit "config-file" "present" $path
        } else {
            Write-Audit "config-file" "unhealthy" "not readable as JSON/JSONC-lite: $path"
        }
    } else {
        Write-Audit "config-file" "missing" $path
    }
}

$currentNames = @(
    (Join-Path $configRoot "oh-my-openagent.json"),
    (Join-Path $configRoot "oh-my-openagent.jsonc"),
    (Join-Path $projectConfigRoot "oh-my-openagent.json"),
    (Join-Path $projectConfigRoot "oh-my-openagent.jsonc")
)
$legacyNames = @(
    (Join-Path $configRoot "oh-my-opencode.json"),
    (Join-Path $configRoot "oh-my-opencode.jsonc"),
    (Join-Path $projectConfigRoot "oh-my-opencode.json"),
    (Join-Path $projectConfigRoot "oh-my-opencode.jsonc")
)

$hasCurrent = $currentNames | Where-Object { Test-Path -LiteralPath $_ }
$hasLegacy = $legacyNames | Where-Object { Test-Path -LiteralPath $_ }

if ($hasCurrent -and $hasLegacy) {
    Write-Audit "oh-my-openagent-name-collision" "unhealthy" "current and legacy config names both exist"
} elseif ($hasLegacy) {
    Write-Audit "oh-my-openagent-name-collision" "unhealthy" "legacy oh-my-opencode config exists without current name"
} else {
    Write-Audit "oh-my-openagent-name-collision" "present" "no legacy/current collision detected"
}

$opencodeJson = Join-Path $configRoot "opencode.json"
if (Test-Path -LiteralPath $opencodeJson) {
    $text = Get-Content -LiteralPath $opencodeJson -Raw
    if ($text -match "oh-my-opencode") {
        Write-Audit "plugin-name" "unhealthy" "legacy plugin name found in opencode.json"
    } elseif ($text -match "oh-my-openagent") {
        Write-Audit "plugin-name" "present" "current plugin name found in opencode.json"
    } else {
        Write-Audit "plugin-name" "missing" "no oh-my plugin entry found in opencode.json"
    }
} else {
    Write-Audit "plugin-name" "missing" "opencode.json not found"
}

exit 0
