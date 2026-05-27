[CmdletBinding()]
param(
    [ValidateSet("Scope", "RemoteAccess", "Templates", "ScriptSafety", "SetupDirectives", "Troubleshooting", "Gitignore", "Links", "All")]
    [string]$Check = "All"
)

$ErrorActionPreference = "Continue"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$Failures = New-Object System.Collections.Generic.List[string]

function Get-RepoPath {
    param([string]$RelativePath)
    return Join-Path $RepoRoot $RelativePath
}

function Read-Text {
    param([string]$RelativePath)
    $path = Get-RepoPath $RelativePath
    if (Test-Path -LiteralPath $path) {
        return Get-Content -LiteralPath $path -Raw
    }
    return ""
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $Failures.Add($Message) | Out-Null
        Write-Host "FAIL $Message"
    } else {
        Write-Host "PASS $Message"
    }
}

function Assert-File {
    param([string]$RelativePath)
    Assert-True (Test-Path -LiteralPath (Get-RepoPath $RelativePath)) "file exists: $RelativePath"
}

function Assert-Contains {
    param([string]$RelativePath, [string]$Pattern)
    $text = Read-Text $RelativePath
    Assert-True ($text -match [regex]::Escape($Pattern)) "$RelativePath contains '$Pattern'"
}

function Invoke-ScopeCheck {
    Assert-Contains "AGENTS.md" "omostack home"
    Assert-Contains "AGENTS.md" "not an application"
    Assert-Contains ".agent-docs/README.md" "omostack home"
    Assert-Contains ".agent-docs/agent-instructions.md" "not an application"
    Assert-Contains ".agent-docs/agent-instructions.md" ".my-omo/"
    Assert-Contains ".agent-docs/agent-instructions.md" ".omo/"
}

function Invoke-RemoteAccessCheck {
    Assert-Contains ".agent-docs/agent-remote-access.md" ".my-omo/remote-access/"
    Assert-Contains ".agent-docs/agent-remote-access.md" 'Do not add `.gitkeep`'
    $remoteAccessDoc = Read-Text ".agent-docs/agent-remote-access.md"
    $oldRemoteNamePattern = 'remote-access-' + 'keys'
    Assert-True ($remoteAccessDoc -notmatch $oldRemoteNamePattern) "remote access docs do not mention old folder names"
}

function Invoke-TemplatesCheck {
    $files = @(
        ".agent-docs/templates/README.md",
        ".agent-docs/templates/remote-access.example.jsonc",
        ".agent-docs/templates/opencode-global.example.jsonc",
        ".agent-docs/templates/oh-my-openagent.example.jsonc",
        ".agent-docs/templates/install-state.example.json"
    )
    foreach ($file in $files) { Assert-File $file }
    $combined = ($files | ForEach-Object { Read-Text $_ }) -join "`n"
    $sshPrivateKeyPattern = 'BEGIN OPENSSH' + ' PRIVATE KEY'
    $githubTokenPattern = 'ghp_' + '[A-Za-z0-9_]' + '{20,}'
    Assert-True ($combined -notmatch $sshPrivateKeyPattern) "templates contain no SSH private key material"
    Assert-True ($combined -notmatch $githubTokenPattern) "templates contain no GitHub token pattern"
    Assert-True ($combined -match 'example') "templates use example values"
}

function Invoke-ScriptSafetyCheck {
    $scripts = @(
        ".agent-docs/scripts/health-check.ps1",
        ".agent-docs/scripts/config-audit.ps1",
        ".agent-docs/scripts/backup-omostack.ps1",
        ".agent-docs/scripts/cleanup-temp.ps1",
        ".agent-docs/scripts/repair-opencode-cache.ps1",
        ".agent-docs/scripts/verify-scaffold.ps1"
    )
    foreach ($script in $scripts) { Assert-File $script }
    Assert-Contains ".agent-docs/scripts/repair-opencode-cache.ps1" "ConfirmRepair"
    Assert-Contains ".agent-docs/scripts/backup-omostack.ps1" "ShouldProcess"
    Assert-Contains ".agent-docs/scripts/cleanup-temp.ps1" "ShouldProcess"
    Assert-Contains ".agent-docs/scripts/repair-opencode-cache.ps1" "ShouldProcess"
}

function Invoke-SetupDirectivesCheck {
    Assert-File ".agent-docs/setup-directives.md"
    $text = Read-Text ".agent-docs/setup-directives.md"
    $placeholderPattern = (('write ' + 'your'), ('TO' + 'DO'), ('T' + 'BD')) -join '|'
    Assert-True ($text -notmatch $placeholderPattern) "setup directives contain no placeholders"
    foreach ($token in @("Status Detection", "Health Check", "Config Audit", "Provider Auth", "Backup and Rollback", "Cache Repair", "Temp Cleanup", "Remote-Access Initialization", "Upgrade Flow", "Escalation")) {
        Assert-True ($text -match [regex]::Escape($token)) "setup directives include $token"
    }
}

function Invoke-TroubleshootingCheck {
    Assert-File ".agent-docs/troubleshooting.md"
    Assert-File ".agent-docs/provider-auth.md"
    Assert-File ".agent-docs/model-and-config-reference.md"
    $combined = (Read-Text ".agent-docs/troubleshooting.md") + (Read-Text ".agent-docs/provider-auth.md") + (Read-Text ".agent-docs/model-and-config-reference.md")
    foreach ($token in @("ProviderInitError", "ProviderModelNotFoundError", "oh-my-opencode", "oh-my-openagent", "missing", "unhealthy", "opencode auth list", "doctor")) {
        Assert-True ($combined -match [regex]::Escape($token)) "troubleshooting docs include $token"
    }
}

function Test-GitIgnored {
    param([string]$Path)
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $gitCommand) {
        $gitignore = Read-Text ".gitignore"
        if ($Path -like ".my-omo/*") { return ($gitignore -match '/\.my-omo/') }
        if ($Path -like ".omo/*") { return ($gitignore -match '/\.omo/') }
        return $false
    }
    $old = Get-Location
    try {
        Set-Location $RepoRoot
        & $gitCommand.Source check-ignore -q -- $Path
        return ($LASTEXITCODE -eq 0)
    } finally {
        Set-Location $old
    }
}

function Test-GitTracked {
    param([string]$Path)
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $gitCommand) {
        return $false
    }
    $old = Get-Location
    try {
        Set-Location $RepoRoot
        $result = & $gitCommand.Source ls-files -- $Path
        return (-not [string]::IsNullOrWhiteSpace(($result -join "")))
    } finally {
        Set-Location $old
    }
}

function Invoke-GitignoreCheck {
    Assert-True (Test-GitIgnored ".my-omo/remote-access/example.local.jsonc") ".my-omo private remote-access is ignored"
    Assert-True (Test-GitIgnored ".omo/boulder.json") ".omo runtime state is ignored"
    Assert-True (-not (Test-GitIgnored ".agent-docs/templates/remote-access.example.jsonc")) "templates are trackable"
    Assert-True (-not (Test-GitIgnored ".agent-docs/scripts/health-check.ps1")) "scripts are trackable"
}

function Invoke-LinksCheck {
    Assert-File ".agent-docs/self-bootstrap-checklist.md"
    $readme = Read-Text ".agent-docs/README.md"
    $checklist = Read-Text ".agent-docs/self-bootstrap-checklist.md"
    foreach ($token in @("setup-directives.md", "agent-remote-access.md", "troubleshooting.md", "provider-auth.md", "model-and-config-reference.md", "self-bootstrap-checklist.md", "scripts/", "templates/")) {
        Assert-True ((($readme + $checklist) -match [regex]::Escape($token))) "navigation links include $token"
    }
}

$checksToRun = if ($Check -eq "All") {
    @("Scope", "RemoteAccess", "Templates", "ScriptSafety", "SetupDirectives", "Troubleshooting", "Gitignore", "Links")
} else {
    @($Check)
}

foreach ($item in $checksToRun) {
    Write-Host "== $item =="
    switch ($item) {
        "Scope" { Invoke-ScopeCheck }
        "RemoteAccess" { Invoke-RemoteAccessCheck }
        "Templates" { Invoke-TemplatesCheck }
        "ScriptSafety" { Invoke-ScriptSafetyCheck }
        "SetupDirectives" { Invoke-SetupDirectivesCheck }
        "Troubleshooting" { Invoke-TroubleshootingCheck }
        "Gitignore" { Invoke-GitignoreCheck }
        "Links" { Invoke-LinksCheck }
    }
}

if ($Failures.Count -gt 0) {
    Write-Host "FAILED $($Failures.Count) scaffold checks"
    exit 1
}

Write-Host "OK scaffold checks passed"
exit 0
