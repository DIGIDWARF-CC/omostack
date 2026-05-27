[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$ConfirmRepair
)

$ErrorActionPreference = "Stop"
$cachePath = Join-Path $env:USERPROFILE ".cache\opencode"

function Write-Repair {
    param([string]$Status, [string]$Detail)
    [pscustomobject]@{ check = "repair-opencode-cache"; status = $Status; detail = $Detail } | ConvertTo-Json -Compress
}

if (-not (Test-Path -LiteralPath $cachePath)) {
    Write-Repair "missing" "cache not found: $cachePath"
    exit 0
}

if (-not $ConfirmRepair) {
    Write-Repair "planned" "dry-run only; would remove cache with -ConfirmRepair: $cachePath"
    exit 0
}

if ($PSCmdlet.ShouldProcess($cachePath, "Remove OpenCode provider cache")) {
    Remove-Item -LiteralPath $cachePath -Recurse -Force
    Write-Repair "removed" $cachePath
} else {
    Write-Repair "planned" "would remove $cachePath"
}

exit 0
