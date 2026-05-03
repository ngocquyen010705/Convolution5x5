[CmdletBinding()]
param(
    [string]$PythonExe = "python",
    [string]$CaptureRoot = "captures/d455/output_live",
    [int]$Width = 640,
    [int]$Height = 480,
    [int]$FeedWidth = 160,
    [int]$FeedHeight = 120,
    [int]$Fps = 30,
    [int]$Frames = 12,
    [double]$PreviewVideoFps = 12.0,
    [string[]]$Kernels = @("gaussian5", "sharpen5", "laplacian5"),
    [switch]$KeepIntermediates
)

$ErrorActionPreference = 'Stop'

$workspace = Split-Path -Parent $PSScriptRoot
Set-Location $workspace

$sourceDir = Join-Path $CaptureRoot "source"
$finalDir = Join-Path $CaptureRoot "final"

if (Test-Path $CaptureRoot) {
    Remove-Item -Recurse -Force $CaptureRoot
}

New-Item -ItemType Directory -Force -Path $CaptureRoot | Out-Null
New-Item -ItemType Directory -Force -Path $finalDir | Out-Null

Write-Host "[1/5] Capturing realtime frames from D455 once -> $sourceDir"
& $PythonExe .\python\d455_stream_process.py `
    --width $Width --height $Height --fps $Fps `
    --feed_width $FeedWidth --feed_height $FeedHeight `
    --duration_sec 0 --max_frames $Frames --save_every 1 `
    --out_dir $sourceDir
if ($LASTEXITCODE -ne 0) {
    throw "D455 capture/feed failed"
}

$kernelResults = @()

foreach ($k in $Kernels) {
    $kernelDir = Join-Path $CaptureRoot $k

    Write-Host "[2/5] Preparing dataset for kernel=$k -> $kernelDir"
    New-Item -ItemType Directory -Force -Path (Join-Path $kernelDir "raw") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $kernelDir "feed_rgb") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $kernelDir "hex_in") | Out-Null

    Copy-Item -Force (Join-Path $sourceDir "raw\*.png") (Join-Path $kernelDir "raw")
    Copy-Item -Force (Join-Path $sourceDir "feed_rgb\*.png") (Join-Path $kernelDir "feed_rgb")
    Copy-Item -Force (Join-Path $sourceDir "hex_in\*.hex") (Join-Path $kernelDir "hex_in")

    Write-Host "[3/5] RTL processing kernel=$k"
    & $PythonExe .\python\rtl_process_hex_frames.py `
        --workspace . `
        --in_dir "$kernelDir/hex_in" `
        --out_dir "$kernelDir" `
        --kernel $k `
        --width $FeedWidth --height $FeedHeight `
        --python_exe $PythonExe
    if ($LASTEXITCODE -ne 0) {
        throw "RTL processing failed for kernel=$k"
    }

    Write-Host "[4/5] Building preview video kernel=$k"
    & $PythonExe .\python\build_side_by_side_video.py `
        --raw_dir "$kernelDir/raw" `
        --processed_dir "$kernelDir/processed" `
        --output_video "$kernelDir/preview_side_by_side.mp4" `
        --fps $PreviewVideoFps `
        --label "Kernel=$k"
    if ($LASTEXITCODE -ne 0) {
        throw "Preview video generation failed for kernel=$k"
    }

    Write-Host "[5/5] Generating signoff kernel=$k"
    & $PythonExe .\python\signoff_level_a.py `
        --capture_dir "$kernelDir" `
        --kernel $k `
        --timing_period_ns 50.0 `
        --timing_wns 22.577 `
        --timing_tns 0.0
    if ($LASTEXITCODE -ne 0) {
        throw "Signoff generation failed for kernel=$k"
    }

    $kernelResults += [PSCustomObject]@{
        Kernel = $k
        Folder = $kernelDir
        Preview = (Join-Path $kernelDir "preview_side_by_side.mp4")
        Signoff = (Join-Path $kernelDir "level_a_signoff.md")
    }
}

Write-Host "[5/5] Building one combined comparison output"
& $PythonExe .\python\build_multi_kernel_comparison_video.py `
    --source_raw_dir "$sourceDir/raw" `
    --gaussian_dir "$(Join-Path $CaptureRoot 'gaussian5')" `
    --sharpen_dir "$(Join-Path $CaptureRoot 'sharpen5')" `
    --laplacian_dir "$(Join-Path $CaptureRoot 'laplacian5')" `
    --output_video "$(Join-Path $finalDir 'realtime_comparison_all_kernels.mp4')" `
    --fps $PreviewVideoFps
if ($LASTEXITCODE -ne 0) {
    throw "Combined output video generation failed"
}

if (-not $KeepIntermediates) {
    foreach ($d in @($sourceDir, (Join-Path $CaptureRoot 'gaussian5'), (Join-Path $CaptureRoot 'sharpen5'), (Join-Path $CaptureRoot 'laplacian5'))) {
        if (Test-Path $d) {
            Remove-Item -Recurse -Force $d
        }
    }
}

Write-Host "Realtime multi-kernel demo completed."
Write-Host "Single output folder: $finalDir"
Write-Host "- realtime_comparison_all_kernels.mp4"
