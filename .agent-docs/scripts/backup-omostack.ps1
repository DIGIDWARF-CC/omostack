[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Destination
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$destPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)

function Write-BackupRecord {
    param([string]$Status, [string]$Detail)
    [pscustomobject]@{ check = "backup"; status = $Status; detail = $Detail } | ConvertTo-Json -Compress
}

$sources = @(
    (Join-Path $RepoRoot ".my-omo"),
    (Join-Path $env:APPDATA "opencode"),
    (Join-Path $env:APPDATA "ai.opencode.desktop\logs")
)

if ($PSCmdlet.ShouldProcess($destPath, "Create omostack backup")) {
    New-Item -ItemType Directory -Force -Path $destPath | Out-Null
    foreach ($source in $sources) {
        if (Test-Path -LiteralPath $source) {
            $leaf = Split-Path -Leaf $source
            Copy-Item -LiteralPath $source -Destination (Join-Path $destPath $leaf) -Recurse -Force
            Write-BackupRecord "present" "copied $source"
        } else {
            Write-BackupRecord "missing" "source not found: $source"
        }
    }
    Write-BackupRecord "present" "backup destination: $destPath"
} else {
    Write-BackupRecord "planned" "would create backup at $destPath"
    foreach ($source in $sources) {
        Write-BackupRecord "planned" "would include $source"
    }
}

exit 0
