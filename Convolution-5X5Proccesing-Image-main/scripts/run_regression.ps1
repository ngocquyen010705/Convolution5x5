$ErrorActionPreference = 'Stop'

$workspace = Split-Path -Parent $PSScriptRoot
Set-Location $workspace

$kernels = @('identity5', 'gaussian5', 'sharpen5', 'emboss5', 'laplacian5')

python .\python\synthetic_frames.py --out .\hex --count 1 --width 16 --height 16
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to generate synthetic test frame'
}

$summary = @()

foreach ($k in $kernels) {
    Write-Host "=== Running kernel: $k ==="

    python .\python\prepare_case.py --in_hex .\hex\test_frame_0.hex --width 16 --height 16 --kernel $k --kernel_out .\sim\kernel.hex --expected_out .\sim\expected.hex
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to prepare case for kernel $k"
    }

    .\scripts\run_sim.ps1
    if ($LASTEXITCODE -ne 0) {
        throw "Simulation failed for kernel $k"
    }

    $lineCount = (Get-Content .\sim\tb_out.hex | Measure-Object -Line).Lines
    Copy-Item .\sim\tb_out.hex ".\sim\tb_out_$k.hex" -Force
    Copy-Item .\sim\expected.hex ".\sim\expected_$k.hex" -Force

    $status = if ($lineCount -eq 144) { 'PASS' } else { 'FAIL' }
    $summary += [PSCustomObject]@{ Kernel = $k; Lines = $lineCount; Status = $status }

    if ($status -ne 'PASS') {
        throw "Output line count check failed for kernel $k (got $lineCount, expected 144)"
    }
}

Write-Host "\n=== Regression Summary ==="
$summary | Format-Table -AutoSize
