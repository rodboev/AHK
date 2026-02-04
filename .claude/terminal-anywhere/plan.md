# Terminal Anywhere — Architecture

## Overview

`terminal-anywhere.ahk` provides context-aware Windows Terminal launching at three privilege tiers from any window. All three hotkeys resolve the working directory from the active window, then route through `UserRun()` for consistent process management.

## Privilege Tiers

| Hotkey | Privilege | Mechanism |
|--------|-----------|-----------|
| `F10` | User | `UserRun("wt", "-d " . path)` — spawns via `RunFromProcess explorer.exe` |
| `Shift+F10` | Admin | `UserRun("elevate", "wt", "-d " . path)` — `Start-Process -Verb RunAs` |
| `Ctrl+Alt+Shift+F10` | SYSTEM (TI) | `UserRun("elevate", "ti", fullWtPath, "-d " . path)` — `ti.exe` via admin elevation |

## Working Directory Resolution

All three tiers share the same directory resolution logic:

1. **Desktop** (`Progman`): Use `A_Desktop`
2. **Explorer** (`CabinetWClass`): Use `GetExplorerPath()` (Shell.Application COM)
3. **Any other app**: Use `GetExePath().dir` (process directory), fallback to `A_UserProfile`

## SYSTEM PATH Resolution (`Ctrl+Alt+Shift+F10`)

`ti.exe` runs commands as `NT AUTHORITY\SYSTEM`, whose PATH is minimal (`%SystemRoot%\system32` and few others). User-installed programs like Windows Terminal are absent.

**Solution**: `FindInPath("wt.exe")` resolves to the full absolute path (e.g., `C:\Program Files\WindowsTerminalPreview\wt.exe`) while still running in AHK's admin context with the user's full PATH. This resolved path is passed directly to `ti.exe`.

A confirmation MsgBox displays the constructed command before execution — SYSTEM elevation is irreversible and the user should verify the target.

## TI App Relaunch (`Ctrl+Shift+Plus`, in AutoHotkey.ahk)

A related but separate hotkey (`^+=`) relaunches the focused app as SYSTEM:

1. `GetActiveWindowCommandLine(pid)` fetches the WMI command line
2. `GetExePath().path` resolves the exe to a full path
3. `RegExReplace` swaps the command-line's executable portion with the resolved full path
4. `Run, ti.exe <full-command-line>` — if the new process doesn't appear within 250ms, the original is closed and retried

This lives in `AutoHotkey.ahk` because it operates on the active window (not terminal-specific).

## UserRun Routing

All terminal hotkeys use `UserRun()` which handles:
- **PowerShell env var expansion**: `-d %UserProfile%\Desktop` → `-d $env:UserProfile\Desktop`
- **Argument quoting**: Single-quoted in PowerShell paths (`'` escaped as `''`), double-quoted in direct paths
- **Elevated quoting**: Inner `psCmd` quotes escaped (`'` → `''`) before embedding in `-ArgumentList '...'`
- **Process tree**: Spawned from `explorer.exe` via `RunFromProcess-x64` for clean process ancestry

## Dependencies (from parent script)

| Helper | Purpose |
|--------|---------|
| `GetExplorerPath()` | Active Explorer window's filesystem path |
| `GetExePath()` | Process executable path and directory |
| `FindInPath(exe)` | Resolve short name to full PATH entry |
| `UserRun(exe, args*)` | Unified process launcher with elevation support |
