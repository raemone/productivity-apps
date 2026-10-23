<#
.SYNOPSIS
    Removes the LidKeeper logon task and restores sleep on lid close.

.DESCRIPTION
    Nothing is installed outside the repository folder, so removing the logon
    task is all the cleanup there is. Pass -KeepPowerSetting to leave the lid
    close action as it is.

.PARAMETER KeepPowerSetting
    Do not restore "sleep on lid close".
#>

#Requires -Version 5.1

[CmdletBinding()]
param([switch]$KeepPowerSetting)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\LidPower.psm1') -Force

if (Get-ScheduledTask -TaskName 'LidKeeper' -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName 'LidKeeper' -Confirm:$false
    Write-Output 'Removed the LidKeeper logon task.'
} else {
    Write-Output 'No LidKeeper logon task was registered.'
}

if (-not $KeepPowerSetting) {
    if (-not (Test-Elevated)) {
        Write-Warning 'Run this elevated to restore "sleep on lid close", or pass -KeepPowerSetting.'
    } else {
        Set-LidPowerState -Ac 1 -Dc 1 | Out-Null
        Write-Output 'Restored sleep on lid close for AC and battery.'
    }
}

Write-Output 'Delete the app folder to finish removing LidKeeper.'
