[CmdletBinding()]
param(
    [double[]]$PeriodsNs = @(30.0, 27.0, 25.0),
    [string]$FrameHex = '.\captures\d455\full640_smoke\hex_in\frame_000000.hex',
    [ValidateSet('identity5', 'gaussian5', 'sharpen5', 'emboss5', 'laplacian5')][string]$Kernel = 'gaussian5',
    [int]$Width = 640,
    [int]$Height = 480,
    [string]$VivadoBat = 'D:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat',
    [string]$SaifOut = '.\sim\activity.saif'
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
$xdcPath = Join-Path $repoRoot 'vivado_project\constraints.xdc'
if (-not (Test-Path -LiteralPath $xdcPath)) {
    throw "constraints.xdc not found: $xdcPath"
}

$origXdc = Get-Content -LiteralPath $xdcPath -Raw
$results = @()

Push-Location $repoRoot
try {
    foreach ($p in $PeriodsNs) {
        $newXdc = [regex]::Replace(
            $origXdc,
            'create_clock\s+-period\s+[0-9]+(?:\.[0-9]+)?\s+\[get_ports\s+clk\]',
            ('create_clock -period {0:N3} [get_ports clk]' -f $p),
            1
        )
        Set-Content -LiteralPath $xdcPath -Value $newXdc -Encoding ascii

        .\scripts\generate_saif_from_hex.ps1 -FrameHex $FrameHex -Kernel $Kernel -Width $Width -Height $Height -ClockPeriodNs $p -SaifOut $SaifOut

        $env:POWER_ACTIVITY_FILE = (Resolve-Path $SaifOut).Path
        $env:POWER_ACTIVITY_STRIP_PATH = 'tb_activity_saif/dut'

        $pTag = $p.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture).Replace('.', 'p')
        $vivadoLog = Join-Path $repoRoot ("vivado_project\\reports\\vivado_sweep_${pTag}ns.log")
        Invoke-VivadoStrict -VivadoBatPath $VivadoBat -RepoRoot $repoRoot -LogPath $vivadoLog -AllowRepair

        $timing = Get-Content -LiteralPath .\vivado_project\reports\timing_post_route.rpt
        $line = ($timing | Select-String '^\s*-?[0-9]+\.[0-9]+\s+-?[0-9]+\.[0-9]+' | Select-Object -First 1).Line
        if ($line) {
            $parts = ($line -split '\s+') | Where-Object { $_ -ne '' }
            $wns = [double]$parts[0]
            $tns = [double]$parts[1]
        } else {
            $wns = -9999
            $tns = -9999
        }

        $pow = Get-Content -LiteralPath .\vivado_project\reports\power_post_route.rpt
        $confLine = ($pow | Select-String '\| Overall confidence level\s*\|' | Select-Object -First 1).Line
        $conf = if ($confLine) {
            (($confLine -split '\|') | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne 'Overall confidence level' } | Select-Object -First 1)
        } else {
            'NA'
        }

        $annotLine = ($pow | Select-String 'of nets annotated' | Select-Object -First 1).Line
        $annot = if ($annotLine) { $annotLine.Trim() } else { 'NA' }

        $status = if ($wns -ge 0 -and $tns -ge 0) { 'PASS' } else { 'FAIL' }
        $results += [pscustomobject]@{
            PeriodNs = $p
            FreqMHz = [math]::Round(1000.0 / $p, 3)
            WNS = $wns
            TNS = $tns
            Status = $status
            PowerConfidence = $conf
            NetsAnnotated = $annot
        }

        Remove-Item Env:POWER_ACTIVITY_FILE -ErrorAction SilentlyContinue
        Remove-Item Env:POWER_ACTIVITY_STRIP_PATH -ErrorAction SilentlyContinue
    }
}
finally {
    Set-Content -LiteralPath $xdcPath -Value $origXdc -Encoding ascii
    Remove-Item Env:POWER_ACTIVITY_FILE -ErrorAction SilentlyContinue
    Remove-Item Env:POWER_ACTIVITY_STRIP_PATH -ErrorAction SilentlyContinue
    Pop-Location
}

$results | Format-Table -AutoSize
