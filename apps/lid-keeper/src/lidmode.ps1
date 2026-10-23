<#
.SYNOPSIS
    Command line front end for the lid close action.

.PARAMETER Command
    status  show the current setting (no elevation needed)
    awake   do nothing when the lid closes
    sleep   sleep when the lid closes

.PARAMETER AcOnly
    With "awake", keep sleeping on battery and only stay awake while plugged in.

.EXAMPLE
    .\lidmode.ps1
    .\lidmode.ps1 awake
    .\lidmode.ps1 awake -AcOnly
    .\lidmode.ps1 sleep
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('status', 'awake', 'sleep')]
    [string]$Command = 'status',

    [switch]$AcOnly
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'LidPower.psm1') -Force

function Write-State {
    param($State)

    if (-not $State) {
        Write-Output 'This PC does not report a lid close action.'
        return
    }

    [pscustomobject]@{
        'Power plan'  = $State.PlanName
        'Plugged in'  = $State.AcName
        'On battery'  = $State.DcName
    } | Format-List
}

switch ($Command) {
    'status' {
        Write-State (Get-LidPowerState)
    }
    'awake' {
        $dc = if ($AcOnly) { 1 } else { 0 }
        Write-State (Set-LidPowerState -Ac 0 -Dc $dc)
    }
    'sleep' {
        Write-State (Set-LidPowerState -Ac 1 -Dc 1)
    }
}
