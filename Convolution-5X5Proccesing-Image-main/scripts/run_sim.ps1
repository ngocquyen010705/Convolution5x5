[CmdletBinding()]
param(
    [int]$Width = 16,
    [int]$Height = 16,
    [switch]$CompileOnly,
    [switch]$RunOnly
)

$ErrorActionPreference = 'Stop'

if ($CompileOnly -and $RunOnly) {
    throw "CompileOnly and RunOnly cannot both be set"
}

Push-Location "$PSScriptRoot\..\tb"
try {
    if (-not $RunOnly) {
        $iverilogArgs = @(
            '-g2012',
            '-Wall',
            "-DTB_IMAGE_W=$Width",
            "-DTB_IMAGE_H=$Height",
            '-o',
            '..\sim\sim.vvp',
            '..\src\top_convolution.sv',
            '..\src\line_buffer_4.sv',
            '..\src\kernel_loader.sv',
            '..\src\mac_array_25x3.sv',
            'tb_convolution.sv'
        )

        & iverilog @iverilogArgs
        if ($LASTEXITCODE -ne 0) {
            throw "iverilog compile failed"
        }

        if ($CompileOnly) {
            Write-Host "Compile completed. Size=${Width}x${Height}. Image: ..\sim\sim.vvp"
            return
        }
    }

    if (-not (Test-Path "..\sim\sim.vvp")) {
        throw "Simulation image not found: ..\\sim\\sim.vvp"
    }

    vvp ..\sim\sim.vvp
    if ($LASTEXITCODE -ne 0) {
        throw "vvp simulation failed"
    }

    Write-Host "Simulation completed. Size=${Width}x${Height}. VCD: ..\sim\dump.vcd"
} finally {
    Pop-Location
}
