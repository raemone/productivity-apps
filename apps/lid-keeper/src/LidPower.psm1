<#
.SYNOPSIS
    Reads and writes the Windows "lid close action" power setting.

.DESCRIPTION
    State is read from the registry (locale independent, no elevation needed) and
    falls back to parsing powercfg output when the setting has never been changed
    from its default and therefore has no registry key yet.

    Writes always go through powercfg, which requires an elevated process.
#>

Set-StrictMode -Version Latest

# Power buttons and lid -> Lid close action
$script:SubButtonsGuid = '4f971e89-eebd-4455-a8de-9e59040e7347'
$script:LidActionGuid   = '5ca83367-6e45-459f-a27b-476b1d01c936'
$script:SchemesKey      = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes'

$script:ActionNames = @{
    0 = 'Do nothing'
    1 = 'Sleep'
    2 = 'Hibernate'
    3 = 'Shut down'
}

function Get-LidActionName {
    <#
    .SYNOPSIS
        Turns a lid action index into its friendly name.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Index)

    if ($script:ActionNames.ContainsKey($Index)) { $script:ActionNames[$Index] }
    else { "Unknown ($Index)" }
}

function Test-Elevated {
    <#
    .SYNOPSIS
        True when the current process runs as administrator.
    #>
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ActivePowerPlan {
    <#
    .SYNOPSIS
        Returns the active power plan's GUID and friendly name.
    #>
    [CmdletBinding()]
    param()

    $guid = $null
    try {
        $guid = (Get-ItemProperty -Path $script:SchemesKey -Name ActivePowerScheme -ErrorAction Stop).ActivePowerScheme
    } catch {
        Write-Verbose "Could not read ActivePowerScheme: $($_.Exception.Message)"
    }

    # powercfg prints: Power Scheme GUID: <guid>  (Balanced)
    # The label before the parentheses is localised; the name inside them is not.
    $name = $null
    $output = (& powercfg /getactivescheme 2>&1) -join ' '
    if ($LASTEXITCODE -eq 0) {
        $match = [regex]::Match($output, '([0-9a-fA-F-]{36})\s*\((.+?)\)\s*$')
        if ($match.Success) {
            if (-not $guid) { $guid = $match.Groups[1].Value }
            $name = $match.Groups[2].Value.Trim()
        }
    }

    # PowerShell 5.1 will not accept an if-statement as a hashtable value.
    $label = 'Unknown plan'
    if ($name) { $label = $name } elseif ($guid) { $label = $guid }

    [pscustomobject]@{
        Guid = $guid
        Name = $label
    }
}

function Get-LidPowerState {
    <#
    .SYNOPSIS
        Returns the lid close action for AC and battery on the active plan.

    .OUTPUTS
        A PSCustomObject, or $null on a machine with no lid setting (most desktops).
    #>
    [CmdletBinding()]
    param()

    $plan = Get-ActivePowerPlan
    $ac = $null
    $dc = $null

    if ($plan.Guid) {
        $key = Join-Path $script:SchemesKey (Join-Path $plan.Guid (Join-Path $script:SubButtonsGuid $script:LidActionGuid))
        try {
            $values = Get-ItemProperty -Path $key -ErrorAction Stop
            $ac = [int]$values.ACSettingIndex
            $dc = [int]$values.DCSettingIndex
        } catch {
            Write-Verbose "No registry override at $key; falling back to powercfg."
        }
    }

    if ($null -eq $ac -or $null -eq $dc) {
        $query = (& powercfg /query SCHEME_CURRENT $script:SubButtonsGuid $script:LidActionGuid 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0) { return $null }

        # The only 0x-prefixed values powercfg prints here are the current AC and
        # DC indices, in that order, so this survives any display language.
        $hex = [regex]::Matches($query, '0x([0-9a-fA-F]{8})')
        if ($hex.Count -lt 2) { return $null }
        $ac = [Convert]::ToInt32($hex[0].Groups[1].Value, 16)
        $dc = [Convert]::ToInt32($hex[1].Groups[1].Value, 16)
    }

    [pscustomobject]@{
        PlanName     = $plan.Name
        PlanGuid     = $plan.Guid
        Ac           = $ac
        Dc           = $dc
        AcName       = Get-LidActionName $ac
        DcName       = Get-LidActionName $dc
        StaysAwakeAc = ($ac -eq 0)
        StaysAwakeDc = ($dc -eq 0)
    }
}

function Set-LidPowerState {
    <#
    .SYNOPSIS
        Sets the lid close action on the active power plan.

    .PARAMETER Ac
        Action index to use while plugged in. Omit to leave it unchanged.

    .PARAMETER Dc
        Action index to use while on battery. Omit to leave it unchanged.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateRange(0, 3)][Nullable[int]]$Ac,
        [ValidateRange(0, 3)][Nullable[int]]$Dc
    )

    if ($null -eq $Ac -and $null -eq $Dc) {
        throw 'Specify -Ac, -Dc, or both.'
    }
    if (-not (Test-Elevated)) {
        throw 'Changing the lid close action needs an elevated process. Run as administrator.'
    }

    $steps = @()
    if ($null -ne $Ac) { $steps += , @('/setacvalueindex', $Ac) }
    if ($null -ne $Dc) { $steps += , @('/setdcvalueindex', $Dc) }

    foreach ($step in $steps) {
        $target = "lid close action ($($step[0])) to $(Get-LidActionName $step[1])"
        if (-not $PSCmdlet.ShouldProcess($target, 'powercfg')) { continue }

        $output = & powercfg $step[0] SCHEME_CURRENT $script:SubButtonsGuid $script:LidActionGuid $step[1] 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "powercfg $($step[0]) failed: $($output -join ' ')"
        }
    }

    # powercfg only commits edits to the active scheme when it is re-activated.
    if ($PSCmdlet.ShouldProcess('active power plan', 'powercfg /setactive')) {
        $output = & powercfg /setactive SCHEME_CURRENT 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "powercfg /setactive failed: $($output -join ' ')"
        }
    }

    Get-LidPowerState
}

Export-ModuleMember -Function Get-LidActionName, Test-Elevated, Get-ActivePowerPlan, Get-LidPowerState, Set-LidPowerState
