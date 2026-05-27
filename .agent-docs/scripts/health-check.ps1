[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = "Continue"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")

function Write-Check {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail
    )
    [pscustomobject]@{
        check  = $Name
        status = $Status
        detail = $Detail
    } | ConvertTo-Json -Compress
}

function Test-CommandAvailable {
    param([string]$CommandName)
    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
    return $null -ne $cmd
}

Write-Check "mode" "present" "health-check is non-destructive; WhatIf is accepted for operator safety"

if (Test-CommandAvailable "opencode") {
    try {
        $version = (& opencode --version 2>&1 | Select-Object -First 1) -join " "
        if ($LASTEXITCODE -eq 0) {
            Write-Check "opencode" "present" $version
        } else {
            Write-Check "opencode" "unhealthy" $version
        }
    } catch {
        Write-Check "opencode" "unhealthy" $_.Exception.Message
    }
} else {
    Write-Check "opencode" "missing" "command not found in PATH"
}

foreach ($command in @("node", "bun")) {
    if (Test-CommandAvailable $command) {
        try {
            $version = (& $command --version 2>&1 | Select-Object -First 1) -join " "
            if ($LASTEXITCODE -eq 0) {
                Write-Check $command "present" $version
            } else {
                Write-Check $command "unhealthy" $version
            }
        } catch {
            Write-Check $command "unhealthy" $_.Exception.Message
        }
    } else {
        Write-Check $command "missing" "command not found in PATH"
    }
}

if (Test-CommandAvailable "bunx") {
    Write-Check "oh-my-openagent-doctor" "present" "bunx is available; run bunx oh-my-openagent doctor for live diagnostics"
} elseif (Test-CommandAvailable "bun") {
    Write-Check "oh-my-openagent-doctor" "present" "bun is available; bunx may be provided by bun on this system"
} else {
    Write-Check "oh-my-openagent-doctor" "missing" "bun/bunx not found"
}

$paths = @(
    @{ Name = "base-marker"; Path = Join-Path $RepoRoot ".my-omo\omostack-base-install-done" },
    @{ Name = "private-install-state"; Path = Join-Path $RepoRoot ".my-omo\install-state.json" },
    @{ Name = "private-remote-access"; Path = Join-Path $RepoRoot ".my-omo\remote-access" },
    @{ Name = "opencode-user-config"; Path = Join-Path $env:APPDATA "opencode\opencode.json" },
    @{ Name = "opencode-user-config-jsonc"; Path = Join-Path $env:APPDATA "opencode\opencode.jsonc" },
    @{ Name = "opencode-cache"; Path = Join-Path $env:USERPROFILE ".cache\opencode" },
    @{ Name = "opencode-desktop-logs"; Path = Join-Path $env:APPDATA "ai.opencode.desktop\logs" }
)

foreach ($item in $paths) {
    if (Test-Path -LiteralPath $item.Path) {
        Write-Check $item.Name "present" $item.Path
    } else {
        Write-Check $item.Name "missing" $item.Path
    }
}

exit 0
