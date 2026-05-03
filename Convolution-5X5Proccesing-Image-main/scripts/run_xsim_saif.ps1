[CmdletBinding()]
param(
    [int]$Width = 640,
    [int]$Height = 480,
    [double]$ClockPeriodNs = 25.0,
    [string]$SaifOut = "..\sim\activity.saif",
    [string]$VivadoBin = "D:\AMDDesignTools\2025.2\Vivado\bin"
)

$ErrorActionPreference = 'Stop'

$xvlogExe = Join-Path $VivadoBin 'xvlog.bat'
$xelabExe = Join-Path $VivadoBin 'xelab.bat'
$xsimExe = Join-Path $VivadoBin 'xsim.bat'

foreach ($exe in @($xvlogExe, $xelabExe, $xsimExe)) {
    if (-not (Test-Path $exe)) {
        throw "Required simulator executable not found: $exe"
    }
}

Push-Location "$PSScriptRoot\..\tb"
try {
    $halfNs = [Math]::Max(0.001, ($ClockPeriodNs / 2.0))
    $halfNsText = $halfNs.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
    $cfgFile = Join-Path (Get-Location).Path 'saif_clock_cfg.svh'
    $cfgText = @'
`ifndef TB_CLK_HALF_NS
`define TB_CLK_HALF_NS __HALF_NS__
`endif
'@.Replace('__HALF_NS__', $halfNsText)
    Set-Content -LiteralPath $cfgFile -Value $cfgText -Encoding ascii

    $xvlogArgs = @(
        '-sv',
        '..\src\top_convolution.sv',
        '..\src\line_buffer_4.sv',
        '..\src\kernel_loader.sv',
        '..\src\mac_array_25x3.sv',
        'tb_activity_saif.sv'
    )
    & $xvlogExe @xvlogArgs
    if ($LASTEXITCODE -ne 0) {
        throw "xvlog compile failed"
    }

    & $xelabExe 'tb_activity_saif' '-debug' 'typical' '-s' 'tb_activity_saif_xsim'
    if ($LASTEXITCODE -ne 0) {
        throw "xelab elaboration failed"
    }

    $saifArg = $SaifOut
    if (-not [System.IO.Path]::IsPathRooted($saifArg)) {
        $saifArg = Join-Path (Resolve-Path '..').Path $saifArg
    }
    $saifDir = Split-Path -Parent $saifArg
    if ($saifDir -and -not (Test-Path $saifDir)) {
        New-Item -ItemType Directory -Path $saifDir -Force | Out-Null
    }

    $env:SAIF_OUT = $saifArg
    $env:SAIF_SCOPE = '/tb_activity_saif/dut/*'
    & $xsimExe 'tb_activity_saif_xsim' '-tclbatch' 'xsim_saif.tcl'
    Remove-Item Env:SAIF_OUT -ErrorAction SilentlyContinue
    Remove-Item Env:SAIF_SCOPE -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0) {
        throw "xsim execution failed"
    }

    if (-not (Test-Path $saifArg)) {
        throw "SAIF was not generated: $saifArg"
    }

    Write-Host "XSIM SAIF generation completed. Size=${Width}x${Height}. SAIF: $saifArg"
} finally {
    Pop-Location
}
