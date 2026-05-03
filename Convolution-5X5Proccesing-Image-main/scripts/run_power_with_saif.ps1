[CmdletBinding()]
param(
    [string]$FrameHex = '.\captures\d455\full640_smoke\hex_in\frame_000000.hex',
    [ValidateSet('identity5', 'gaussian5', 'sharpen5', 'emboss5', 'laplacian5')][string]$Kernel = 'gaussian5',
    [int]$Width = 640,
    [int]$Height = 480,
    [string]$SaifOut = '.\sim\activity.saif',
    [string]$VivadoBat = 'E:\Vivado\2023.2\bin\vivado.bat'
)

$ErrorActionPreference = 'Stop'

function Invoke-VivadoStrict {
    param(
        [Parameter(Mandatory = $true)][string]$VivadoBatPath,
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$LogPath,
        [switch]$AllowRepair
    )

    $args = @('-mode', 'batch', '-source', '.\\vivado_project\\run_synth.tcl', '-nojournal', '-nolog')
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $vivOut = & $VivadoBatPath @args 2>&1 | Tee-Object -FilePath $LogPath
    $ErrorActionPreference = $oldEap
    $exitCode = $LASTEXITCODE
    $txt = ($vivOut | Out-String)

    if ($exitCode -ne 0) {
        throw "Vivado run_synth.tcl failed (exit=$exitCode). Log: $LogPath"
    }

    if ($txt -match 'The system cannot find the path specified\\.') {
        if ($AllowRepair) {
            Write-Warning "Path error detected in Vivado output. Attempting one repair pass by regenerating project scripts."
            $repairLog = Join-Path $RepoRoot 'vivado_project\\reports\\vivado_path_repair.log'
            $oldEapRepair = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & $VivadoBatPath -mode batch -source .\\vivado_project\\project_create.tcl -nojournal -nolog 2>&1 | Tee-Object -FilePath $repairLog | Out-Null
            $ErrorActionPreference = $oldEapRepair
            if ($LASTEXITCODE -ne 0) {
                throw "Project regeneration failed during path repair. Log: $repairLog"
            }

            $oldEap2 = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $vivOut2 = & $VivadoBatPath @args 2>&1 | Tee-Object -FilePath $LogPath
            $ErrorActionPreference = $oldEap2
            $exitCode2 = $LASTEXITCODE
            $txt2 = ($vivOut2 | Out-String)
            if ($exitCode2 -ne 0) {
                throw "Vivado failed after repair (exit=$exitCode2). Log: $LogPath"
            }
            if ($txt2 -match 'The system cannot find the path specified\\.') {
                throw "Path error still present after repair. Aborting by design. Check log: $LogPath"
            }
            return
        }

        throw "Path error detected in Vivado output. Aborting by design. Check log: $LogPath"
    }
}

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$constraints = Join-Path $repoRoot 'vivado_project\constraints.xdc'
$clockPeriodNs = 25.0
if (Test-Path $constraints) {
    $xdcText = Get-Content -LiteralPath $constraints -Raw
    $m = [regex]::Match($xdcText, 'create_clock\s+-period\s+([0-9]+(?:\.[0-9]+)?)\s+\[get_ports\s+clk\]')
    if ($m.Success) {
        $clockPeriodNs = [double]$m.Groups[1].Value
    }
}

Push-Location $repoRoot
try {
    .\scripts\generate_saif_from_hex.ps1 -FrameHex $FrameHex -Kernel $Kernel -Width $Width -Height $Height -ClockPeriodNs $clockPeriodNs -SaifOut $SaifOut

    $env:POWER_ACTIVITY_FILE = (Resolve-Path $SaifOut).Path
    $env:POWER_ACTIVITY_STRIP_PATH = 'tb_activity_saif/dut'

    $vivadoLog = Join-Path $repoRoot 'vivado_project\reports\vivado_power_with_saif.log'
    Invoke-VivadoStrict -VivadoBatPath $VivadoBat -RepoRoot $repoRoot -LogPath $vivadoLog -AllowRepair

    Write-Host "Power flow completed. See vivado_project/reports/power_post_route.rpt"
} finally {
    Remove-Item Env:POWER_ACTIVITY_FILE -ErrorAction SilentlyContinue
    Remove-Item Env:POWER_ACTIVITY_STRIP_PATH -ErrorAction SilentlyContinue
    Pop-Location
}
