[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [int]$OlderThanDays = 7
)

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$cutoff = (Get-Date).AddDays(-1 * $OlderThanDays)
$targets = @(
    (Join-Path $RepoRoot ".my-omo\temp"),
    (Join-Path $RepoRoot ".omo\evidence")
)

function Write-Cleanup {
    param([string]$Status, [string]$Detail)
    [pscustomobject]@{ check = "cleanup-temp"; status = $Status; detail = $Detail } | ConvertTo-Json -Compress
}

foreach ($target in $targets) {
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Cleanup "missing" $target
        continue
    }
    Get-ChildItem -LiteralPath $target -Force -Recurse -File | Where-Object { $_.LastWriteTime -lt $cutoff } | ForEach-Object {
        if ($PSCmdlet.ShouldProcess($_.FullName, "Remove temp file")) {
            Remove-Item -LiteralPath $_.FullName -Force
            Write-Cleanup "removed" $_.FullName
        } else {
            Write-Cleanup "planned" "would remove $($_.FullName)"
        }
    }
}

exit 0
