# LidKeeper

A Windows tray app that switches what happens when you close your laptop lid:
stay awake, or sleep. It also offers a middle setting — stay awake only while
plugged in.

- **Stack:** PowerShell 5.1 + Windows Forms. No install, no SDK, no dependencies;
  everything it needs ships with Windows.
- **Platform:** Windows 10 / 11 laptops.

## Why

The lid close action lives four clicks deep in Windows power options, and it is
two settings (plugged in and on battery), not one. If you flip it regularly —
docked at a desk, then on a plane — a tray toggle is faster.

## Run it

```powershell
# from the repo root
.\apps\lid-keeper\LidKeeper.cmd
```

Or double-click `LidKeeper.cmd`. A tray icon appears:

| Icon | Meaning |
| --- | --- |
| Green, lid open | Stays awake on AC **and** battery |
| Amber, lid open | Stays awake on AC only |
| Grey, lid closed | Sleeps when the lid closes |

- **Left-click** — toggle between "stay awake" and "sleep".
- **Right-click** — pick a mode, see the active power plan and both current
  values, open Windows power options, or turn on start-with-Windows.

Changing the setting requires administrator rights, so the app asks for
elevation when it starts. Turning on **Start with Windows** registers a logon
task that runs it elevated, so you only see that prompt once.

## Command line

For scripts and shortcuts, `src\lidmode.ps1` does the same thing without a GUI:

```powershell
powershell -ExecutionPolicy Bypass -File .\apps\lid-keeper\src\lidmode.ps1            # status
powershell -ExecutionPolicy Bypass -File .\apps\lid-keeper\src\lidmode.ps1 awake      # never sleep on lid close
powershell -ExecutionPolicy Bypass -File .\apps\lid-keeper\src\lidmode.ps1 awake -AcOnly
powershell -ExecutionPolicy Bypass -File .\apps\lid-keeper\src\lidmode.ps1 sleep
```

`status` works unelevated; `awake` and `sleep` need an elevated prompt.

## How it works

Windows stores the lid close action as a per-power-plan setting:

- Subgroup `4f971e89-eebd-4455-a8de-9e59040e7347` (power buttons and lid)
- Setting `5ca83367-6e45-459f-a27b-476b1d01c936` (lid close action)
- Values: `0` do nothing, `1` sleep, `2` hibernate, `3` shut down

`src\LidPower.psm1` reads the current values straight from
`HKLM\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes`, which needs no
elevation and does not depend on your Windows display language. If the setting
has never been changed and has no registry key yet, it falls back to parsing
`powercfg /query`.

Writes go through `powercfg /setacvalueindex` and `/setdcvalueindex`, followed by
`powercfg /setactive SCHEME_CURRENT` — without that last step Windows keeps using
the old value.

Settings apply to the **active** power plan. Switch plans and you may get a
different lid behaviour; the tray icon polls every 10 seconds, so it follows
along.

## Things worth knowing

- **It changes a real Windows setting.** Whatever you pick here shows up in
  Windows power options, and survives reboots and app exit. Closing the app does
  not restore sleep — use the tray menu or `lidmode.ps1 sleep`.
- **Staying awake with the lid shut means the machine keeps running warm** in a
  bag. That is the setting doing its job, not a bug, but it is the reason the
  "AC only" mode exists.
- **Modern Standby** laptops (most recent ultrabooks) may still enter a low power
  state with the lid closed even with "do nothing" set. Check
  `powercfg /a` to see which sleep states your machine actually supports.
- **Desktops** have no lid setting. The app detects this and disables the modes
  instead of writing nonsense.
- Group policy, or a vendor power utility (Dell Power Manager, Lenovo Vantage),
  can overwrite the setting behind your back. The 10-second poll will show it.

## Remove it

```powershell
powershell -ExecutionPolicy Bypass -File .\apps\lid-keeper\install\Uninstall.ps1
```

Removes the logon task and restores sleep on lid close. Pass `-KeepPowerSetting`
to leave the power setting alone. Nothing is written outside the repo folder and
the logon task, so deleting the folder finishes the job.
