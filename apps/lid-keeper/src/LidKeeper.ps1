<#
.SYNOPSIS
    Tray app that switches what Windows does when you close the laptop lid.

.DESCRIPTION
    Shows a tray icon for the current lid close action on the active power plan.
    Left-click toggles between "stay awake" and "sleep"; the right-click menu
    also offers staying awake only while plugged in, and starting at logon.

    Changing the setting needs administrator rights, so the script re-launches
    itself elevated unless -NoElevate is given.

.PARAMETER NoElevate
    Skip the self-elevation step. Used by the logon task, which already runs
    elevated, and useful when you only want to look at the current state.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\LidKeeper.ps1
#>

#Requires -Version 5.1

[CmdletBinding()]
param([switch]$NoElevate)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ('LidKeeper.Native' -as [type])) {
    Add-Type -Namespace LidKeeper -Name Native -MemberDefinition @'
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool DestroyIcon(System.IntPtr handle);

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        public static extern bool ShowWindow(System.IntPtr window, int command);

        [System.Runtime.InteropServices.DllImport("kernel32.dll")]
        public static extern System.IntPtr GetConsoleWindow();
'@
}

Import-Module (Join-Path $PSScriptRoot 'LidPower.psm1') -Force

$script:AppName  = 'LidKeeper'
$script:AppPath  = $PSCommandPath
$script:TaskName = 'LidKeeper'

# ---------------------------------------------------------------- elevation --

if (-not (Test-Elevated) -and -not $NoElevate) {
    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-WindowStyle', 'Hidden'
        '-File', "`"$script:AppPath`""
    )
    try {
        Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $arguments -Verb RunAs | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "$script:AppName needs administrator rights to change the lid close action.`n`n$($_.Exception.Message)",
            $script:AppName, 'OK', 'Warning') | Out-Null
    }
    exit
}

# One icon per session is plenty.
$createdNew = $false
$script:Mutex = New-Object System.Threading.Mutex($true, 'Local\LidKeeperSingleInstance', [ref]$createdNew)
if (-not $createdNew) {
    exit
}

# Hide the console the script was launched from; the tray icon is the UI.
$console = [LidKeeper.Native]::GetConsoleWindow()
if ($console -ne [IntPtr]::Zero) { [void][LidKeeper.Native]::ShowWindow($console, 0) }

# -------------------------------------------------------------------- icons --

function New-LidIcon {
    <#
    .SYNOPSIS
        Draws a laptop glyph in the given colour and returns it as an icon.
    #>
    param(
        [Parameter(Mandatory)][System.Drawing.Color]$Color,
        [Parameter(Mandatory)][bool]$LidOpen
    )

    $bitmap = New-Object System.Drawing.Bitmap 32, 32
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $body = New-Object System.Drawing.SolidBrush $Color
    $screen = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(235, 250, 250, 252))

    if ($LidOpen) {
        $graphics.FillRectangle($body, 6, 3, 20, 16)    # lid
        $graphics.FillRectangle($screen, 8, 5, 16, 12)   # screen
        $graphics.FillRectangle($body, 2, 21, 28, 5)     # base
    } else {
        $graphics.FillRectangle($body, 3, 12, 26, 7)     # closed lid
        $graphics.FillRectangle($body, 2, 22, 28, 4)     # base
    }

    $handle = $bitmap.GetHicon()
    try {
        $icon = [System.Drawing.Icon]::FromHandle($handle)
        # Clone first: the icon is only valid while the handle lives.
        [System.Drawing.Icon]$icon.Clone()
    } finally {
        [void][LidKeeper.Native]::DestroyIcon($handle)
        $screen.Dispose()
        $body.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$script:Icons = @{
    Awake  = New-LidIcon -Color ([System.Drawing.Color]::FromArgb(255, 46, 160, 67))  -LidOpen $true   # green
    AcOnly = New-LidIcon -Color ([System.Drawing.Color]::FromArgb(255, 219, 154, 4))  -LidOpen $true   # amber
    Sleeps = New-LidIcon -Color ([System.Drawing.Color]::FromArgb(255, 110, 118, 129)) -LidOpen $false # slate
}

# ------------------------------------------------------------------ startup --

function Test-StartupTask {
    [CmdletBinding()] param()
    $null -ne (Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue)
}

function Enable-StartupTask {
    <#
    .SYNOPSIS
        Registers a logon task so the tray app starts elevated without a UAC prompt.
    #>
    [CmdletBinding()] param()

    $powershell = (Get-Process -Id $PID).Path
    $argument = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden ' +
                "-File `"$script:AppPath`" -NoElevate"

    $action = New-ScheduledTaskAction -Execute $powershell -Argument $argument
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
        -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)

    Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force `
        -Description 'Starts LidKeeper in the notification area at logon.' | Out-Null
}

function Disable-StartupTask {
    [CmdletBinding()] param()
    Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false -ErrorAction SilentlyContinue
}

# --------------------------------------------------------------------- tray --

$script:Notify = New-Object System.Windows.Forms.NotifyIcon
$script:Notify.Icon = $script:Icons.Sleeps
$script:Notify.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$script:Notify.ContextMenuStrip = $menu

function New-MenuItem {
    param([string]$Text, [scriptblock]$OnClick, [switch]$Disabled)

    $item = New-Object System.Windows.Forms.ToolStripMenuItem
    $item.Text = $Text
    if ($Disabled) { $item.Enabled = $false }
    if ($OnClick) { $item.add_Click($OnClick) }
    $item
}

$script:HeaderItem  = New-MenuItem -Text 'Reading current state...' -Disabled
$script:AwakeItem   = New-MenuItem -Text 'Stay awake (plugged in and on battery)' -OnClick { Set-Mode -Ac 0 -Dc 0 }
$script:AcOnlyItem  = New-MenuItem -Text 'Stay awake only when plugged in' -OnClick { Set-Mode -Ac 0 -Dc 1 }
$script:SleepItem   = New-MenuItem -Text 'Sleep when I close the lid' -OnClick { Set-Mode -Ac 1 -Dc 1 }
$script:StartupItem = New-MenuItem -Text 'Start with Windows' -OnClick { Switch-Startup }

$powerOptionsItem = New-MenuItem -Text 'Open Windows power options...' -OnClick {
    Start-Process -FilePath 'control.exe' -ArgumentList '/name Microsoft.PowerOptions'
}
$refreshItem = New-MenuItem -Text 'Refresh' -OnClick { Update-Tray }
$aboutItem = New-MenuItem -Text "About $script:AppName" -OnClick {
    [System.Windows.Forms.MessageBox]::Show(
        ("$script:AppName controls the 'lid close action' of your active Windows " +
         "power plan, for both AC and battery.`n`nIt is a thin wrapper around " +
         "powercfg, so anything it sets is visible in Windows power options too."),
        $script:AppName, 'OK', 'Information') | Out-Null
}
$exitItem = New-MenuItem -Text 'Exit' -OnClick { Stop-App }

[void]$menu.Items.Add($script:HeaderItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($script:AwakeItem)
[void]$menu.Items.Add($script:AcOnlyItem)
[void]$menu.Items.Add($script:SleepItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($refreshItem)
[void]$menu.Items.Add($powerOptionsItem)
[void]$menu.Items.Add($script:StartupItem)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($aboutItem)
[void]$menu.Items.Add($exitItem)

function Show-Balloon {
    param([string]$Message, [string]$Kind = 'Info')
    $script:Notify.ShowBalloonTip(3000, $script:AppName, $Message, $Kind)
}

function Update-Tray {
    <#
    .SYNOPSIS
        Re-reads the lid setting and repaints icon, tooltip and menu checks.
    #>
    [CmdletBinding()] param()

    $state = Get-LidPowerState

    if (-not $state) {
        $script:Notify.Icon = $script:Icons.Sleeps
        $script:Notify.Text = "$script:AppName - no lid setting on this PC"
        $script:HeaderItem.Text = 'This PC reports no lid close action'
        foreach ($item in @($script:AwakeItem, $script:AcOnlyItem, $script:SleepItem)) {
            $item.Enabled = $false
            $item.Checked = $false
        }
        return
    }

    if ($state.StaysAwakeAc -and $state.StaysAwakeDc) {
        $script:Notify.Icon = $script:Icons.Awake
        $summary = 'stays awake'
    } elseif ($state.StaysAwakeAc) {
        $script:Notify.Icon = $script:Icons.AcOnly
        $summary = 'awake on AC only'
    } else {
        $script:Notify.Icon = $script:Icons.Sleeps
        $summary = "lid close: $($state.AcName.ToLower())"
    }

    # NotifyIcon.Text is capped at 63 characters.
    $tooltip = "$script:AppName - $summary"
    if ($tooltip.Length -gt 63) { $tooltip = $tooltip.Substring(0, 63) }
    $script:Notify.Text = $tooltip

    $script:HeaderItem.Text = "$($state.PlanName): plugged in - $($state.AcName), battery - $($state.DcName)"
    $script:AwakeItem.Checked  = ($state.Ac -eq 0 -and $state.Dc -eq 0)
    $script:AcOnlyItem.Checked = ($state.Ac -eq 0 -and $state.Dc -ne 0)
    $script:SleepItem.Checked  = ($state.Ac -ne 0)
    $script:StartupItem.Checked = Test-StartupTask
}

function Set-Mode {
    <#
    .SYNOPSIS
        Applies a lid close action and reports the result in a balloon tip.
    #>
    param([int]$Ac, [int]$Dc)

    try {
        $state = Set-LidPowerState -Ac $Ac -Dc $Dc
        Update-Tray
        Show-Balloon -Message "Lid close: $($state.AcName) on AC, $($state.DcName) on battery."
    } catch {
        Show-Balloon -Message $_.Exception.Message -Kind 'Error'
    }
}

function Switch-Mode {
    <#
    .SYNOPSIS
        Left-click behaviour: flip between staying awake everywhere and sleeping.
    #>
    [CmdletBinding()] param()

    $state = Get-LidPowerState
    if (-not $state) { return }

    if ($state.StaysAwakeAc) { Set-Mode -Ac 1 -Dc 1 } else { Set-Mode -Ac 0 -Dc 0 }
}

function Switch-Startup {
    [CmdletBinding()] param()

    try {
        if (Test-StartupTask) {
            Disable-StartupTask
            Show-Balloon -Message "$script:AppName will no longer start with Windows."
        } else {
            Enable-StartupTask
            Show-Balloon -Message "$script:AppName will start with Windows."
        }
    } catch {
        Show-Balloon -Message $_.Exception.Message -Kind 'Error'
    }
    Update-Tray
}

function Stop-App {
    [CmdletBinding()] param()

    $script:Timer.Stop()
    $script:Notify.Visible = $false
    $script:Notify.Dispose()
    $script:Context.ExitThread()
}

# An explicit param block is the reliable way to reach the event args here.
$script:Notify.add_MouseUp({
    param($eventSender, $eventArgs)
    if ($eventArgs.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Switch-Mode }
})

# The lid action can also change from power options or a plan switch, so poll.
$script:Timer = New-Object System.Windows.Forms.Timer
$script:Timer.Interval = 10000
$script:Timer.add_Tick({ Update-Tray })
$script:Timer.Start()

Update-Tray

$script:Context = New-Object System.Windows.Forms.ApplicationContext
[System.Windows.Forms.Application]::Run($script:Context)

$script:Mutex.ReleaseMutex()
$script:Mutex.Dispose()
