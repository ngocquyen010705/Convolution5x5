[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$FrameHex,
    [ValidateSet('identity5', 'gaussian5', 'sharpen5', 'emboss5', 'laplacian5')][string]$Kernel = 'gaussian5',
    [int]$Width = 640,
    [int]$Height = 480,
    [double]$ClockPeriodNs = 25.0,
    [string]$PythonExe = "python",
    [string]$SaifOut = ".\sim\activity.saif"
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$framePath = (Resolve-Path $FrameHex).Path
$hexTarget = Join-Path $repoRoot 'hex\test_frame_0.hex'

if ([System.IO.Path]::GetFullPath($framePath) -ne [System.IO.Path]::GetFullPath($hexTarget)) {
    Copy-Item -LiteralPath $framePath -Destination $hexTarget -Force
}

Push-Location $repoRoot
try {
    $prepareArgs = @(
        'python/prepare_case.py',
        '--in_hex', 'hex/test_frame_0.hex',
        '--width', $Width,
        '--height', $Height,
        '--kernel', $Kernel,
        '--kernel_out', 'sim/kernel.hex',
        '--expected_out', 'sim/expected.hex'
    )
    & $PythonExe @prepareArgs
    if ($LASTEXITCODE -ne 0) {
        throw "prepare_case.py failed"
    }

    & '.\scripts\run_xsim_saif.ps1' -Width $Width -Height $Height -ClockPeriodNs $ClockPeriodNs -SaifOut $SaifOut
    if ($LASTEXITCODE -ne 0) {
        throw "run_xsim_saif.ps1 failed"
    }

    Write-Host "SAIF generated from frame: $framePath"
} finally {
    Pop-Location
}
