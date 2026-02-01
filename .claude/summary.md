# AHK Project: Context Transfer Summary

## Current State (Feb 1, 2026)

### Project Overview

AutoHotkey v1.1 project split across two files:
- **`AutoHotkey.ahk`** (~1022 lines) — main script with hotkeys, helpers, and smooth scroll
- **`window-spawning.ahk`** (~720 lines) — included via `#Include`, all window spawning logic

Features:
- **Explorer Smooth Scroll**: Multi-method MButton drag-scrolling with automatic fallback chain
- **Window Spawning**: Auto-move new/activated windows and Alt+Tab to cursor's monitor via shell hooks
- **Extended Window Spy**: Real-time window info tooltip with click-to-dialog
- **Windows Terminal / Elevation**: Context-aware terminal launching with de-escalation and TrustedInstaller
- **Global hotkeys**: Volume control, window manipulation, app launchers

### Key Regions in AutoHotkey.ahk

| Lines | Section |
|-------|---------|
| 1-19 | Directives, config (`SendMode`, `SetWorkingDir`, `SetTitleMatchMode`) |
| 20-21 | Debug flags (`MB_Debug`, `WS.Debug`) |
| 23-31 | Auto-execute: `#If` RDP context, `If` guard → `WS_Init()`, `Return` |
| 34-91 | Bindings, remaps, script control |
| 94-212 | Helper functions (`HasVal`, `GetExePath`, `GetMonitor`, `GetCursorMonitor`, etc.) |
| 215-285 | `UserRun()` - process execution with elevation support |
| 287-521 | Windows Terminal / elevation hotkeys (F10, Shift+F10, Ctrl+Alt+Shift+F10) |
| 523-1018 | Extended Window Spy (`#w` toggle, dialog, text processing) |
| 1020-1022 | `#Include window-spawning.ahk` + Explorer Smooth Scroll begins |

### Key Regions in window-spawning.ahk

| Section | Content |
|---------|---------|
| `WS_Init()` | Initialize `WS` object, register shell hook, SetWinEventHook (SHOW, UNCLOAKED, CREATE), CoInitialize, cleanup timer |
| `WS_OnShellHook()` | Handle DESTROYED (brief-process detection + cleanup), ACTIVATED (positive intent detection), CREATED (exe recording + pre-pending + deferred move) |
| `WS_OnWinEvent()` | Handle EVENT_OBJECT_SHOW, UNCLOAKED, CREATE (opacity hiding, deferred window processing) |
| `WS_IsReady()` | Timing gate: visible, sized, uncloaked |
| `WS_IsMovable()` | Policy gate: skip tool windows, cloaked, no-title, excluded classes, visible-owner |
| `WS_MoveToMonitor()` | Relative position mapping across monitors with taskbar-aware clamping, maximized/minimized handling, inline opacity reveal |
| `WS_Reveal()` | Idempotent opacity restore + sentinel set |
| `WS_Log()` | Debug logging to `%TEMP%\WS_Debug.log` |
| `WS_CleanPrePending` | Timer: stale entry cleanup for PrePending, Hidden, OwnerSentinel, RecentCreated, RecentExes |
| `WS_Cleanup()` | OnExit: unhook WinEvents, reveal hidden windows, CoUninitialize |
| `~!Tab::` | Alt+Tab passthrough hotkey with non-blocking WinEvent detection |

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

- `GetScrollPos(hwnd)` (AutoHotkey.ahk line 1030) — Win32 `GetScrollPos` wrapper, returns vertical scroll position
- `HasWin32Scrollbar(hwnd)` (AutoHotkey.ahk line 1035) — Checks if `GetScrollRange(SB_VERT)` indicates a scrollbar exists

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

### FileDelete/FileAppend with Object Properties

AHK v1.1 commands take plain string parameters. Forced expression syntax (`% WS.Property`) is unreliable for `FileDelete`/`FileAppend`. Always dereference to a local variable first:
```autohotkey
; BROKEN — unreliable with object property access
FileDelete, % WS.LogFile

; CORRECT — local variable + traditional dereferencing
_logFile := WS.LogFile
FileDelete, %_logFile%
```

### Auto-Execute Section

In AHK v1.1, the auto-execute section runs from line 1 until the first hotkey label. Code placed between hotkey subroutines is **unreachable dead code**. Global config must be in the auto-execute section (lines 1-24).

---

## Helper Functions Reference

| Function | Location | Purpose |
|----------|----------|---------|
| `HasVal(arr, val)` | AutoHotkey.ahk line 97 | Check if array contains value (partial match via InStr) |
| `GetExePath(winTitle)` | AutoHotkey.ahk line 108 | Returns `{path, dir}` for window's process |
| `GetMonitor(winTitle)` | AutoHotkey.ahk line 130 | Returns 1-based monitor number for window center |
| `GetCursorMonitor()` | AutoHotkey.ahk line ~145 | Returns 1-based monitor index for cursor position |
| `ProcessExistsByCommandLine(cmdLine)` | AutoHotkey.ahk line 148 | Find PID by command line match via WMI |
| `IsProcessElevated(pid)` | AutoHotkey.ahk line 203 | Checks admin privileges via token |
| `UserRun(exe, args*)` | AutoHotkey.ahk line 218 | Smart process execution with elevation support |
| `WrapList(text, delim, maxLen)` | AutoHotkey.ahk ~line 830 | Wraps delimited text at maxLen preserving items |
| `CleanWindowText(text)` | AutoHotkey.ahk ~line 840 | Removes non-ASCII, dedupes long window text |
| `FilterLongItems(text, maxLen)` | AutoHotkey.ahk ~line 855 | Removes items >maxLen from delimited list |
| `SortList(text)` | AutoHotkey.ahk ~line 870 | Sorts comma-separated items alphabetically |
| `GetScrollPos(hwnd)` | AutoHotkey.ahk line 1030 | Win32 vertical scroll position |
| `HasWin32Scrollbar(hwnd)` | AutoHotkey.ahk line 1035 | Checks if Win32 scrollbar exists |

---

## Conventions

- **AHK v1.1 syntax only** — no v2 syntax
- **Naming**: PascalCase functions, `MB_` prefix for MButton globals, `WS` object for window spawning state, `WS_` prefix for window spawning functions
- **Process launching**: Always use `UserRun()` for consistent elevation/env handling
- **App lists**: Partial matching via `HasVal()` — add exe names without full paths
- **Sections**: ASCII box dividers for major regions
- **Debug flags**: `MB_Debug` (AutoHotkey.ahk line 20) for MButton scroll, `WS.Debug` (window-spawning.ahk) for window spawning

---

## Window Spawning (Cursor's Monitor)

**Status**: Phase 11 complete (positive intent detection). Full design and tasks at `.claude/window-spawning/`.

**File**: `window-spawning.ahk` — included from `AutoHotkey.ahk` line 1021.

### Architecture

Shell hook (`RegisterShellHookWindow`) intercepts `HSHELL_WINDOWCREATED`, `HSHELL_WINDOWACTIVATED`, and `HSHELL_WINDOWDESTROYED`. WinEvent hooks (`SetWinEventHook`) listen for `EVENT_OBJECT_SHOW` (0x8002), `EVENT_OBJECT_UNCLOAKED` (0x8018), and `EVENT_OBJECT_CREATE` (0x8000).

All state is stored in a single `WS := {}` object (replaces 12+ individual `WS_*` globals). Every function declares only `global WS`.

### New Window Creation Paths

- **Win32 instant**: Shell hook fires → window already ready → move immediately
- **UWP event-driven**: Shell hook fires → not ready → `WS.Pending[hwnd]` → SHOW/UNCLOAK event → move (~62ms)
- **CREATE pre-pipeline (zero-flash)**: CREATE event fires 55-77ms before shell hook → register target in `WS.PrePending` → hide via opacity (`WS_EX_LAYERED` + alpha 0) → shell hook moves → restore opacity

### Activation Path: Positive Intent Detection (Phase 11)

**Architecture**: Default-skip — activated windows are NOT moved unless positive intent is detected.
Replaces the previous 7-guard negative-filtering chain (~125 lines → ~55 lines).

**Tier 1 — Brief-process detection** (Win32 single-instance re-launch):
When a single-instance Win32 app is re-launched, a new process briefly exists (100-500ms). It detects the existing instance via mutex/named pipe, sends a message, then exits. We detect this pattern:
1. `HSHELL_WINDOWCREATED` → record `{exe, tick}` in `WS.RecentCreated`
2. `HSHELL_WINDOWDESTROYED` → if window died within 3s, record exe in `WS.RecentExes`
3. `HSHELL_WINDOWACTIVATED` → if exe matches a `WS.RecentExes` entry (<5s) → **move**

**Tier 2 — Overlay-launch detection** (UWP single-instance re-launch):
UWP apps don't create a new process on re-launch (shell uses `IApplicationActivationManager`).
If overlay (Start menu) was recently visible (`WS.OverlayTick` < 2s) AND a **different** window activates (`lParam != prevHwnd`) → **move**.
The `lParam != prevHwnd` check distinguishes "user launched something" from "Start menu closed, same window bounced back."

**Z-order fallback protection**: `WS.OverlayTick` is cleared when the foreground window is destroyed (prevents false Tier 2 on close-fallback) and when the previous window was minimized (prevents false Tier 2 on minimize-fallback).

**Retained guards** (not intent-based):
- Taskbar cursor check: cursor over `Shell_TrayWnd`/`Shell_SecondaryTrayWnd` → skip
- Same-monitor optimization: `windowMon == cursorMon` → skip

### Zero-Flash Opacity Approach (Phase 10)

**Goal**: Eliminate the visual flash where windows briefly appear on the wrong monitor before being moved.

**Mechanism**: At `EVENT_OBJECT_CREATE` time, hide windows using `WS_EX_LAYERED` + `SetLayeredWindowAttributes` (alpha 0 in production, 128 in debug mode for 50% visibility). After `WS_MoveToMonitor` places the window on the correct monitor, restore full opacity.

**Key data structures:**
- `WS.PrePending` dict: `hwnd → {mon, tick, qpc}` — tracks CREATE-to-ShellHook/SHOW pipeline
- `WS.Hidden` dict: `hwnd → hadLayered` (bool if opacity-hidden, `-1` sentinel if "processed")

**Sentinel mechanism**: `WS.Hidden[hwnd] := -1` marks a window as "processed" so duplicate CREATE events don't re-hide an already-moved window. Sentinels are set by:
- `WS_MoveToMonitor()` — always, unconditionally after move
- `WS_Reveal()` — for any window passed through it

**Owner-based sentinel** (`WS.OwnerSentinel`): When `WS_MoveToMonitor` processes a window, it records the window's owner hwnd with a timestamp. The CREATE handler checks if a new window's owner has a recent sentinel (<200ms) and skips hiding. This protects sibling `#32770` windows (e.g., Run dialog) that the Win32 dialog manager creates during initialization.

### WS Object Properties

| Property | Purpose |
|----------|---------|
| `WS.Debug` | Debug log toggle. Logs to `%TEMP%\WS_Debug.log` |
| `WS.LogFile` | Path to debug log file |
| `WS.HookHwnd` | Hidden GUI window for shell hook |
| `WS.Pending` | Associative array: deferred hwnd → `{mon, tick}` |
| `WS.PendingAltTab` | Alt+Tab state: `{mon, tick}` or `""` |
| `WS.ExcludedClasses` | Array of 9 window classes to skip |
| `WS.PrePending` | CREATE-registered hwnd → `{mon, tick, qpc}` |
| `WS.Hidden` | Opacity-hidden hwnd → `hadLayered` (bool), or `-1` (sentinel) |
| `WS.OwnerSentinel` | Owner hwnd → `A_TickCount` (sibling CREATE suppression, 200ms active) |
| `WS.RecentCreated` | hwnd → `{exe, tick}` — window lifespan tracking for Tier 1 |
| `WS.RecentExes` | exe name → `A_TickCount` — brief-process signal for Tier 1 |
| `WS.LastForegroundHwnd` | Last movable foreground hwnd (Tier 2 overlay detection) |
| `WS.OverlayTick` | `A_TickCount` when overlay/infrastructure detected (Tier 2) |
| `WS.EventHookShow` | Handle from `SetWinEventHook` (EVENT_OBJECT_SHOW) |
| `WS.EventHookUncloak` | Handle from `SetWinEventHook` (EVENT_OBJECT_UNCLOAKED) |
| `WS.EventHookCreate` | Handle from `SetWinEventHook` (EVENT_OBJECT_CREATE) |
| `WS.WinEventCB` | `RegisterCallback` pointer for WinEventProc |
| `WS.QPCFreq` | QPC frequency for µs-precision timing |

### Critical AHK v1.1 Details (Window Spawning)
- **32-bit masking**: `idObject & 0xFFFFFFFF` — WinEventProc uses 32-bit params but AHK reads 64-bit register slots on x64
- **Numeric coercion**: `hwnd + 0` — ensures consistent object key type in `WS.Pending` etc.
- **Global discipline**: Every function declares `global WS` (single object replaces 12+ individual globals)
- **No Fast flag**: `RegisterCallback("WS_OnWinEvent", "", 7)` — isolated pseudo-thread per callback
- **Command parameter syntax**: `FileDelete`/`FileAppend` require local variable intermediary for `WS.Property` access

---

## Minimized Window Move — FIXED (Jan 30, 2026)

### Problem

`WS_MoveToMonitor` only handled maximized windows (`minMax == 1`). Minimized windows (`minMax == -1`) fell through to the normal path where `WinGetPos` returns garbage dimensions (~160×28 at position -32000,-32000). Result: windows activated from minimized state (e.g., via Alt+Tab) appeared at tiny size.

### Fix

Added `minMax == -1` branch using `GetWindowPlacement` API to retrieve the window's normal (restored) rectangle — accurate even while minimized. Window is then restored, sized correctly, and centered on the target monitor.

---

## UWP Split-Process Architecture (Reference)

```
ApplicationFrameHost.exe          SystemSettings.exe (or other UWP app)
  └── ApplicationFrameWindow        └── Windows.UI.Core.CoreWindow
       (visible frame, movable)          (render surface, non-movable)
       PID = X                           PID = Y  ← different!

explorer.exe
  └── Windows.UI.Core.CoreWindow
       (Start menu overlay — does NOT fire HSHELL_WINDOWACTIVATED)
       PID = Z
```

This architecture is relevant to:
- **WS_IsMovable()**: ApplicationFrameWindow is movable, CoreWindow is not
- **Tier 2 overlay detection**: Start menu CoreWindow doesn't fire shell hooks, so overlay detection relies on empty-class infrastructure events and `WS.OverlayTick`
- **Brief-process detection**: UWP re-launch doesn't create a new process (Tier 1 misses), hence Tier 2 exists
