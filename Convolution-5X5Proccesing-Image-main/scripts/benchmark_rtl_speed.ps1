[CmdletBinding()]
param(
    [string]$PythonExe = "C:/Users/ADMIN/AppData/Local/Programs/Python/Python310/python.exe",
    [string]$OutDir = "captures/benchmark/rtl_speed",
    [int[]]$Widths = @(160, 320, 640),
    [int[]]$Heights = @(120, 240, 480),
    [string[]]$Kernels = @("gaussian5", "sharpen5", "laplacian5")
)

$ErrorActionPreference = 'Stop'

$workspace = Split-Path -Parent $PSScriptRoot
Set-Location $workspace

if ($Widths.Count -ne $Heights.Count) {
    throw "Widths and Heights must have same length"
}

if (Test-Path $OutDir) {
    Remove-Item -Recurse -Force $OutDir
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$rows = @()

for ($i = 0; $i -lt $Widths.Count; $i++) {
    $w = $Widths[$i]
    $h = $Heights[$i]

    $caseBase = Join-Path $OutDir ("{0}x{1}" -f $w, $h)
    $hexDir = Join-Path $caseBase "hex_in"
    New-Item -ItemType Directory -Force -Path $hexDir | Out-Null

    & $PythonExe .\python\synthetic_frames.py --out $hexDir --count 1 --width $w --height $h
    if ($LASTEXITCODE -ne 0) {
        throw "synthetic_frames.py failed for ${w}x${h}"
    }

    if (Test-Path (Join-Path $hexDir "test_frame_0.hex")) {
        Move-Item -Force (Join-Path $hexDir "test_frame_0.hex") (Join-Path $hexDir "frame_000000.hex")
    }

    foreach ($k in $Kernels) {
        $runOut = Join-Path $caseBase $k
        New-Item -ItemType Directory -Force -Path $runOut | Out-Null

        & $PythonExe .\python\rtl_process_hex_frames.py `
            --workspace . `
            --in_dir "$hexDir" `
            --out_dir "$runOut" `
            --kernel $k `
            --width $w --height $h `
            --python_exe $PythonExe
        if ($LASTEXITCODE -ne 0) {
            throw "rtl_process_hex_frames.py failed for kernel=$k size=${w}x${h}"
        }

        $jsonPath = Join-Path $runOut ("rtl_benchmark_{0}.json" -f $k)
        $rep = Get-Content -Raw -LiteralPath $jsonPath | ConvertFrom-Json

        $simTimePs = [double]$rep.per_frame[0].sim_time_ps
        $simCycles = [math]::Round($simTimePs / 10000.0, 0)
        $hwFpsAt20 = if ($simCycles -gt 0) { 20e6 / $simCycles } else { 0 }
        $hwFpsAt40 = if ($simCycles -gt 0) { 40e6 / $simCycles } else { 0 }

        $rows += [PSCustomObject]@{
            Width = $w
            Height = $h
            Kernel = $k
            SimWallMs = [math]::Round([double]$rep.sim_wall_ms_mean, 3)
            SimFps = [math]::Round([double]$rep.sim_fps_mean, 6)
            SimCycles = [int]$simCycles
            HwFpsAt20MHz = [math]::Round($hwFpsAt20, 3)
            HwFpsAt40MHz = [math]::Round($hwFpsAt40, 3)
            TbAllPass = [bool]$rep.all_tb_pass
        }
    }
}

$csvPath = Join-Path $OutDir "rtl_speed_summary.csv"
$jsonPath = Join-Path $OutDir "rtl_speed_summary.json"
$rows | Export-Csv -NoTypeInformation -Encoding ascii -Path $csvPath
$rows | ConvertTo-Json -Depth 5 | Set-Content -Encoding ascii -Path $jsonPath

$rows | Format-Table -AutoSize
Write-Host "RTL speed summary CSV: $csvPath"
Write-Host "RTL speed summary JSON: $jsonPath"
