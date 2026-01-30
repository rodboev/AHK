# AHK Project: Context Transfer Summary

## Current State (Jan 29, 2026)

### Project Overview

Monolithic AutoHotkey v1.1 script (`AutoHotkey.ahk`, ~1700 lines) providing:
- **Explorer Smooth Scroll**: Multi-method MButton drag-scrolling with automatic fallback chain
- **Window Spawning**: Auto-move new/activated windows and Alt+Tab to cursor's monitor via shell hooks
- **Extended Window Spy**: Real-time window info tooltip with click-to-dialog
- **Windows Terminal / Elevation**: Context-aware terminal launching with de-escalation and TrustedInstaller
- **Global hotkeys**: Volume control, window manipulation, app launchers

### Key Regions in AutoHotkey.ahk

| Lines | Section |
|-------|---------|
| 1-19 | Directives, config (`SendMode`, `SetWorkingDir`, `SetTitleMatchMode`) |
| 20-21 | Debug flags (`MB_Debug`, `WS_Debug`) |
| 23-31 | Auto-execute: `#If` RDP context, `If` guard → `WS_Init()`, `Return` |
| 34-91 | Bindings, remaps, script control |
| 94-212 | Helper functions (`HasVal`, `GetExePath`, `GetMonitor`, `GetCursorMonitor`, etc.) |
| 215-285 | `UserRun()` - process execution with elevation support |
| 287-521 | Windows Terminal / elevation hotkeys (F10, Shift+F10, Ctrl+Alt+Shift+F10) |
| 523-1018 | Extended Window Spy (`#w` toggle, dialog, text processing) |
| 1020-1430 | Explorer Smooth Scroll (MButton drag implementation) |
| 1434-1782 | Window Spawning (`WS_Init`, shell hook, WinEvent hooks, activation guards, Alt+Tab, cleanup) |

---

## Explorer Smooth Scroll (MButton)

### Architecture

The MButton scroll system intercepts middle-click-drag and converts it to smooth scrolling. It uses a **10ms timer** (`MBScrollTimer`) for continuous scrolling while the button is held, with a power-curve acceleration model (`absEffective^0.8` up to 100px, `+ (excess)^0.6` beyond).

### Scroll Methods

| Method | Mechanism | Granularity | Best For |
|--------|-----------|-------------|----------|
| **UIA** | `SetScrollPercent` via IUIAutomationScrollPattern | Fractional % | Explorer file lists, mmc.exe |
| **WHEEL** | `WM_MOUSEWHEEL` sub-120 delta to window | Sub-notch | Electron apps (VS Code) |
| **WHEEL_CTRL** | `WM_MOUSEWHEEL` to control (with fallback detection) | 1 line* | SystemInformer |
| **VSCROLL** | `WM_VSCROLL` line-by-line, dynamic timer (300ms→20ms) | 1 line | Tree views, universal fallback |

### Automatic Fallback Chain (Phase 4)

Methods are **auto-detected at runtime** — no hardcoded per-app flags. The chain probes each method starting from highest quality and cascades on failure:

```
MButton Down
    ├── TreeView control? ──────────────────→ VSCROLL (direct)
    └── Try UIA setup
         ├── Element + ScrollPattern found → UIA
         │    └── Two-tick verification:
         │         Tick 1: capture GetScrollPos before
         │         Tick 2: check NoScroll sentinel OR Win32 scrollbar didn't move
         │         → fail → WHEEL
         └── Setup failed ──────────────────→ WHEEL
              └── First scroll: GetScrollPos before/after
                   ├── No movement → WHEEL_CTRL
                   │    └── First scroll: GetScrollPos → jumped >40 units → VSCROLL
                   └── Movement detected → stay WHEEL
```

Each fallback resets `MB_FallbackChecked := 0`, enabling the next method's first-scroll check. Worst-case cascade latency: ~30ms (happens once per drag session).

### UIA Two-Tick Verification

The UIA fallback uses a two-tick approach to avoid Sleep() in the 10ms timer:
- **Tick 1** (`MB_FallbackChecked = 0`): Captures `GetScrollPos` of control, sends UIA scroll, sets `MB_FallbackChecked := -1`
- **Tick 2** (`MB_FallbackChecked = -1`): Checks if UIA reports NoScroll sentinel (-1), OR cross-validates that Win32 scrollbar actually moved via `HasWin32Scrollbar()` + `GetScrollPos` comparison. Falls to WHEEL on failure.

This catches apps like SystemInformer that expose a ScrollPattern but ignore `SetScrollPercent`.

### App Selection Logic — Auto-Detection Model (Phase 5)

```autohotkey
MB_ExcludedControls := ["ToolbarWindow", "ReBarWindow", "Edit", "AddressBandRoot", "statusbar", "SysHeader"]
IsExcludedRegion := HasVal(MB_ExcludedControls, MBScroll_CtrlClassNN) or (...)
```

### Deferred MButton Down (Explorer)

For Explorer (`CabinetWClass`), MButton Down is **deferred** — not passed through to the app on press. This prevents Explorer from triggering click actions (e.g., opening a new tab when middle-clicking a navbar item) or entering selection mode (which blocks UIA scrolling) before the user's intent (scroll vs click) is determined.

- **If scroll occurs** (drag ≥8px): MButton Down is never sent to Explorer. Custom scroll handles everything.
- **If no scroll** (release without drag): `{Blind}{MButton}` (full click) is synthesized on MButton Up, preserving normal middle-click behavior.

For non-Explorer apps, MButton Down is **passed through immediately** to enable native scroll detection.

### Native Scroll Probe

A movement-gated **native scroll probe** determines whether the app handles MButton drag-scroll natively using three signals:

1. **Cursor change** (HCURSOR handle via `GetCursorInfo` + `A_Cursor = "Unknown"`): Checked every tick. The initial HCURSOR is captured *before* any MButton event is sent. A change is only detected when the handle differs AND `A_Cursor` reports `"Unknown"` (custom bitmap cursor). This dual check prevents false positives from standard cursor changes while reliably catching custom autoscroll icons (Chrome, Firefox).
2. **Win32 scroll position** (`GetScrollPos`): Checked after drag threshold (≥3px). Catches classic Win32 apps with native scrollbars.
3. **UIA scroll percent** (`GetVerticalScrollPercent`): Checked after drag threshold. Catches modern apps using custom renderers.

The probe runs continuously until **8px of vertical movement** (the same threshold used for custom scroll activation). Signal 1 is checked every tick from 0px; signals 2/3 start after 3px (filters cursor jitter). If any signal fires → **native scroll detected**. If none fire by 8px → engage custom scroll (UIA → WHEEL → WHEEL_CTRL → VSCROLL fallback chain).

No hardcoded app exclusion list is needed. Only excluded **controls** (toolbars, edit boxes, headers) are skipped via `MB_ExcludedControls`.

### Key Helper Functions (Scroll)

- `GetScrollPos(hwnd)` (line 1030) — Win32 `GetScrollPos` wrapper, returns vertical scroll position
- `HasWin32Scrollbar(hwnd)` (line 1035) — Checks if `GetScrollRange(SB_VERT)` indicates a scrollbar exists

---

## Extended Window Spy

**Status**: Stable, usable

### Features
- Persistent tooltip showing Active Window + Window Under Cursor info
- Hover-to-pause: hovering over tooltip pauses updates
- Press `#w` again to close tooltip
- 800ms update interval with content-change detection (reduces flicker)
- Click tooltip to open dialog for copying text
- Dialog auto-sizes to fit content, positions flush to bottom-right corner
- Controls sorted alphabetically, items >80 chars filtered out
- Comprehensive info: title, ahk_id, ahk_class, ahk_exe, dir, cmdline, PID (elevated indicator), monitor, pos, size, style, exstyle, focused control with hWnd, UIA pointer, window text, controls

### Pending Improvement
- Dialog width should match tooltip width (captured as `WindowSpyTooltipW` at line ~832)
- Currently uses fixed 700px width

---

## Critical AHK v1.1 Patterns

### COM/UIA Pointer Dereferencing

Always use `ptr+0` in the inner `NumGet()`:
```autohotkey
; CORRECT — Forces numeric evaluation before dereferencing
DllCall(NumGet(NumGet(MB_ScrollPattern+0)+8*A_PtrSize), "Ptr", MB_ScrollPattern, ...)

; BROKEN — AHK v1.1 may misinterpret the variable
DllCall(NumGet(NumGet(MB_ScrollPattern)+8*A_PtrSize), "Ptr", MB_ScrollPattern, ...)
```

### COM DllCall Return Values

Never capture HRESULT from COM vtable DllCalls:
```autohotkey
; BROKEN — Interferes with output parameters
hr := DllCall(NumGet(NumGet(ptr+0)+N*A_PtrSize), ..., "Ptr*", outVar)

; CORRECT — Just call, don't capture return
DllCall(NumGet(NumGet(ptr+0)+N*A_PtrSize), ..., "Ptr*", outVar)
```

### Auto-Execute Section

In AHK v1.1, the auto-execute section runs from line 1 until the first hotkey label. Code placed between hotkey subroutines is **unreachable dead code**. Global config must be in the auto-execute section (lines 1-24).

---

## Helper Functions Reference

| Function | Location | Purpose |
|----------|----------|---------|
| `HasVal(arr, val)` | line 97 | Check if array contains value (partial match via InStr) |
| `GetExePath(winTitle)` | line 108 | Returns `{path, dir}` for window's process |
| `GetMonitor(winTitle)` | line 130 | Returns 1-based monitor number for window center |
| `ProcessExistsByCommandLine(cmdLine)` | line 148 | Find PID by command line match via WMI |
| `IsProcessElevated(pid)` | line 203 | Checks admin privileges via token |
| `UserRun(exe, args*)` | line 218 | Smart process execution with elevation support |
| `WrapList(text, delim, maxLen)` | ~line 830 | Wraps delimited text at maxLen preserving items |
| `CleanWindowText(text)` | ~line 840 | Removes non-ASCII, dedupes long window text |
| `FilterLongItems(text, maxLen)` | ~line 855 | Removes items >maxLen from delimited list |
| `SortList(text)` | ~line 870 | Sorts comma-separated items alphabetically |
| `GetScrollPos(hwnd)` | line 1030 | Win32 vertical scroll position |
| `HasWin32Scrollbar(hwnd)` | line 1035 | Checks if Win32 scrollbar exists |

---

## Conventions

- **AHK v1.1 syntax only** — no v2 syntax
- **Naming**: PascalCase functions, `MB_` prefix for MButton globals, `WS_` prefix for window spawning globals
- **Process launching**: Always use `UserRun()` for consistent elevation/env handling
- **App lists**: Partial matching via `HasVal()` — add exe names without full paths
- **Sections**: ASCII box dividers for major regions
- **Debug flags** (line 20-21): `MB_Debug` for MButton scroll, `WS_Debug` for window spawning

---

## Window Spawning (Cursor's Monitor)

**Status**: Implemented (event-driven). Full design and tasks at `.claude/window-spawning/`.

### Summary

Shell hook (`RegisterShellHookWindow`) intercepts `HSHELL_WINDOWCREATED`, `HSHELL_WINDOWACTIVATED`, and `HSHELL_WINDOWDESTROYED`. WinEvent hooks (`SetWinEventHook`) listen for `EVENT_OBJECT_SHOW` (0x8002) and `EVENT_OBJECT_UNCLOAKED` (0x8018) to detect when deferred windows become visible.

**Two paths:**
- **Win32 instant**: Shell hook fires → window already ready → move immediately
- **UWP event-driven**: Shell hook fires → not ready → `WS_Pending[hwnd]` → SHOW/UNCLOAK event → move (~62ms)

Activated windows are moved unless filtered by the activation guard chain. Alt+Tab switcher is moved via non-blocking `WS_PendingAltTab` + WinEvent SHOW detection.

Destroyed windows are cleaned from `WS_Pending` immediately via `HSHELL_WINDOWDESTROYED`. All deferred MOVED log entries include elapsed timing (`+NNms`) and source label (show/uncloak/poll/timeout) for Phase 10 analysis.

### Activation Guard Chain (7 checks)

| # | Guard | Code |
|---|-------|------|
| 1 | System window filter | `WS_IsMovable(lParam)` |
| 2 | Overlay re-activation | `lParam == WS_LastForegroundHwnd` |
| 3 | Tracker update | Save `prevHwnd`, set `WS_LastForegroundHwnd := lParam` |
| 4 | Close fallback (500ms) | `A_TickCount - WS_LastDestroyTick < 500` |
| 5 | Minimize fallback | `WinGet, prevMinMax, MinMax` on previous foreground; skip if `-1` |
| 6 | Taskbar click | Cursor over `Shell_TrayWnd` or `Shell_SecondaryTrayWnd` |
| 7 | Same monitor | `windowMon == cursorMon` |

### Key Globals

| Variable | Purpose |
|----------|---------|
| `WS_Debug` | Debug log toggle (line 21). Logs to `%TEMP%\WS_Debug.log` |
| `WS_Pending` | Associative array: deferred hwnd → `{mon, tick}` |
| `WS_PendingAltTab` | Alt+Tab state: `{mon, tick}` or `""` |
| `WS_ExcludedClasses` | Array of 9 window classes to skip |
| `WS_HookHwnd` | Hidden GUI window for shell hook |
| `WS_EventHookShow` | Handle from `SetWinEventHook` (EVENT_OBJECT_SHOW) |
| `WS_EventHookUncloak` | Handle from `SetWinEventHook` (EVENT_OBJECT_UNCLOAKED) |
| `WS_WinEventCB` | `RegisterCallback` pointer for WinEventProc |
| `WS_LastDestroyTick` | Timestamp of last window close (activation guard) |
| `WS_LastForegroundHwnd` | Last movable foreground hwnd (overlay dismissal guard) |

### Critical AHK v1.1 Details
- **32-bit masking**: `idObject & 0xFFFFFFFF` — WinEventProc uses 32-bit params but AHK reads 64-bit register slots on x64
- **Numeric coercion**: `hwnd + 0` — ensures consistent object key type in `WS_Pending`
- **Global discipline**: Every function accessing `WS_Pending` must declare `global WS_Pending`
- **No Fast flag**: `RegisterCallback("WS_OnWinEvent", "", 7)` — isolated pseudo-thread per callback
