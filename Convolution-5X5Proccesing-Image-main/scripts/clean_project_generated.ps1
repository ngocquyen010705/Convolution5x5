[CmdletBinding()]
param(
    [string]$KeepOutputDir = "captures/d455/output_live/final"
)

$ErrorActionPreference = 'Stop'

$workspace = Split-Path -Parent $PSScriptRoot
Set-Location $workspace

$pathsToRemove = @(
    "captures/d455/benchmark640",
    "captures/d455/campaign640",
    "captures/d455/full640_smoke",
    "captures/d455/live_gaussian5",
    "captures/d455/live_multi",
    "captures/d455/rtl_only_smoke",
    "sim/dump.vcd",
    "sim/tb_out.hex",
    "sim/kernel.hex",
    "sim/expected.hex",
    "sim/sim.vvp"
)

foreach ($p in $pathsToRemove) {
    if (Test-Path $p) {
        Remove-Item -Recurse -Force $p
        Write-Host "Removed: $p"
    }
}

Get-ChildItem -Path "." -Recurse -File -Filter "*.log" -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -Force $_.FullName
    Write-Host "Removed: $($_.FullName)"
}

$keepFull = (Resolve-Path -Path $KeepOutputDir -ErrorAction SilentlyContinue)
Get-ChildItem -Path "captures/d455" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $candidate = $_.FullName
    if ($keepFull -and $candidate -eq (Split-Path -Parent $keepFull.Path)) {
        return
    }
}

Write-Host "Cleanup complete. Kept output: $KeepOutputDir"
