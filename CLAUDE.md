# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Language Requirement

**AutoHotkey v1.1** — This codebase uses AHK v1.1 syntax exclusively. Do NOT use v2.0 syntax. Key differences:
- Commands use `Command, Param1, Param2` syntax (not function calls)
- Variables use `%var%` for dereferencing in commands
- Legacy `#IfWinActive` directives (not `#HotIf`)

## Architecture

Single-script design with `AutoHotkey.ahk` as the monolithic entrypoint. All hotkeys are registered here. The `includes/` directory contains reference libraries (loosely coupled, mostly for inspiration).

### Key Regions in AutoHotkey.ahk
- **Lines 1-24**: Configuration directives (`#SingleInstance`, `#UseHook`, etc.)
- **Lines 29-90**: Script control and editor-specific hotkeys
- **Lines 94-212**: Helper functions (`GetExePath`, `UserRun`, `IsProcessElevated`, etc.)
- **Lines 290-530**: Windows Terminal and elevation hotkeys (F10 variants)
- **Lines 531-865**: Extended Window Spy (`#w`)
- **Lines 1029-1284**: MButton smooth scroll implementation

### Core Features
1. **Explorer Smooth Scroll** (`MButton + drag`) — 4-method system: UIA, WHEEL, WHEEL_CTRL, VSCROLL
2. **Extended Window Spy** (`Win+W`) — Persistent tooltip with window/control info
3. **Terminal/Elevation** (`F10`, `Shift+F10`, `Ctrl+Shift+F10`) — Context-aware terminal launching

## Running & Debugging

```powershell
# Launch script
start "" "C:\Program Files\AutoHotkey\AutoHotkey.exe" AutoHotkey.ahk

# Or double-click AutoHotkey.ahk in Explorer
```

**Debug tools**: Use tray icon menu (`ListLines`, `Pause`, `Reload`). Insert `ToolTip`, `MsgBox`, or `OutputDebug` for quick inspection.

**Reload on save**: `Ctrl+S` in the script editor auto-reloads via hotkey.

## Code Patterns

### Timer-based Acceleration
Smooth animations use `SetTimer` with dynamic intervals (10-150ms). Follow this pattern for scroll/animation features:
```autohotkey
SetTimer, MyTimer, %interval%
; ...
MyTimer:
  ; Calculate and apply incremental changes
Return
```

### UserRun Helper
Use `UserRun(Executable, Args*)` for all process execution—handles elevation, env var expansion, and PowerShell argument parsing consistently.

### Message Synthesis
Scroll methods use `PostMessage`/`SendMessage` for WM_MOUSEWHEEL (0x20A), WM_VSCROLL (0x115). UIA uses COM `SetScrollPercent`.

### COM/UIA Pointer Dereferencing (CRITICAL)

When calling COM vtable methods via `DllCall`, **always use `+0` suffix** on pointer variables in the inner `NumGet()`:

```autohotkey
; ✅ CORRECT - Forces numeric evaluation before dereferencing
DllCall(NumGet(NumGet(MB_ScrollPattern+0)+8*A_PtrSize), "Ptr", MB_ScrollPattern, ...)

; ❌ BROKEN - AHK v1.1 may misinterpret the variable
DllCall(NumGet(NumGet(MB_ScrollPattern)+8*A_PtrSize), "Ptr", MB_ScrollPattern, ...)
```

**Why:** In AHK v1.1, `NumGet(var)` can behave differently than `NumGet(var+0)`. The `+0` forces AHK to evaluate `var` as a number first, ensuring proper pointer arithmetic.

**Also avoid:** Capturing return values from COM vtable DllCalls:
```autohotkey
; ❌ BROKEN - Interferes with output parameters
hr := DllCall(NumGet(NumGet(ptr+0)+N*A_PtrSize), ..., "Ptr*", outVar)

; ✅ CORRECT - Just call, don't capture HRESULT
DllCall(NumGet(NumGet(ptr+0)+N*A_PtrSize), ..., "Ptr*", outVar)
```

### Configuration Arrays
App-specific behavior is controlled via arrays:
```autohotkey
MB_PassthroughApps := ["chrome.exe", "everything64.exe"]  ; Native scroll
MB_EnabledApps := ["mmc.exe", "code.exe"]                 ; Custom scroll
MB_ExcludedControls := ["ToolbarWindow", "Edit"]          ; Skip these
```

## Testing

No automated tests. Manual verification required:
1. **MButton scroll**: Test in Windows Explorer (file lists + nav tree) and VS Code
2. **Window Spy**: Press `Win+W`, hover different windows, click tooltip to copy
3. **Terminal hotkeys**: Test `F10` from Explorer, Desktop, and applications

## Key Helper Functions

| Function | Purpose |
|----------|---------|
| `GetExePath(winTitle)` | Returns `{path, dir}` for process |
| `GetMonitor(winTitle)` | Returns 1-based monitor number |
| `IsProcessElevated(pid)` | Checks admin privileges |
| `UserRun(exe, args*)` | Smart process execution with elevation |
| `HasVal(arr, val)` | Check if array contains value (partial match) |

## Conventions

- **Naming**: PascalCase functions, `MB_` prefix for MButton globals, `G_` for persistent globals
- **Sections**: Use ASCII box dividers for major sections
- **Dependencies**: Avoid external non-AHK dependencies; prefer Win32/UIA in-script
- **PRs**: Reference affected hotkeys/timers, include manual test steps

## Related Documentation

- `README.md` — Feature showcase and release notes
- `.claude/summary.md` — Technical architecture for AI context transfer
- `.github/copilot-instructions.md` — AI agent editing guidelines
