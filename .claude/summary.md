# AHK Project: Context Transfer Summary

## Current State (Jan 30, 2026)

### Project Overview

Monolithic AutoHotkey v1.1 script (`AutoHotkey.ahk`, ~2000 lines) providing:
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
| 1434-2010 | Window Spawning (`WS_Init`, shell hook, WinEvent hooks, Phase 10 zero-flash, activation guards, Alt+Tab, cleanup) |

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

**Status**: Phase 10d (activation guard fix) **ACTIVE BUG** — overlay detection for Start menu. Full design and tasks at `.claude/window-spawning/`.

### Summary

Shell hook (`RegisterShellHookWindow`) intercepts `HSHELL_WINDOWCREATED`, `HSHELL_WINDOWACTIVATED`, and `HSHELL_WINDOWDESTROYED`. WinEvent hooks (`SetWinEventHook`) listen for `EVENT_OBJECT_SHOW` (0x8002), `EVENT_OBJECT_UNCLOAKED` (0x8018), and `EVENT_OBJECT_CREATE` (0x8000) to detect when windows are created or become visible.

**Three paths:**
- **Win32 instant**: Shell hook fires → window already ready → move immediately
- **UWP event-driven**: Shell hook fires → not ready → `WS_Pending[hwnd]` → SHOW/UNCLOAK event → move (~62ms)
- **CREATE pre-pipeline (Phase 10)**: CREATE event fires 55-77ms before shell hook → register target in `WS_PrePending` → hide via opacity (`WS_EX_LAYERED` + alpha 0) → shell hook moves → restore opacity

Activated windows are moved unless filtered by the activation guard chain. Alt+Tab switcher is moved via non-blocking `WS_PendingAltTab` + WinEvent SHOW detection.

Destroyed windows are cleaned from `WS_Pending`, `WS_PrePending`, and `WS_Hidden` immediately via `HSHELL_WINDOWDESTROYED`. All deferred MOVED log entries include elapsed timing (`+NNms`) and source label (show/uncloak/poll/timeout).

### Phase 10: Zero-Flash Opacity Approach

**Goal**: Eliminate the visual flash where windows briefly appear on the wrong monitor before being moved.

**Mechanism**: At `EVENT_OBJECT_CREATE` time, hide windows using `WS_EX_LAYERED` + `SetLayeredWindowAttributes` (alpha 0 in production, 128 in debug mode for 50% visibility). After `WS_MoveToMonitor` places the window on the correct monitor, restore full opacity.

**Key data structures:**
- `WS_PrePending` dict: `hwnd → {mon, tick, qpc}` — tracks CREATE-to-ShellHook/SHOW pipeline
- `WS_Hidden` dict: `hwnd → hadLayered` (bool if opacity-hidden, `-1` sentinel if "processed")

**Sentinel mechanism**: `WS_Hidden[hwnd] := -1` marks a window as "processed" so duplicate CREATE events don't re-hide an already-moved window. Sentinels are set by:
- `WS_MoveToMonitor()` — always, unconditionally after move
- `WS_Reveal()` — for any window passed through it

**Owner-based sentinel** (`WS_OwnerSentinel`): When `WS_MoveToMonitor` processes a window, it records the window's owner hwnd with a timestamp. The CREATE handler checks if a new window's owner has a recent sentinel (<200ms) and skips hiding. This protects sibling `#32770` windows (e.g., Run dialog) that the Win32 dialog manager creates during initialization — they share the same owner but have different HWNDs, so the per-hwnd sentinel doesn't cover them.

**Safety nets:**
- Empty-class filter in CREATE handler (skips transient Win32 objects with no class name)
- Orphan sweep in `WS_CleanPrePending` timer (reveals windows stuck in WS_Hidden not tracked elsewhere)
- Sentinels cleaned by `HSHELL_WINDOWDESTROYED`; owner sentinels expire via 2s TTL sweep

**Current status**: Works for Chrome, Registry Workshop, Everything, Explorer, UWP Settings. Owner-based sentinel fix for Run dialog create-shell path awaiting test confirmation.

### Activation Guard Chain (7 checks)

| # | Guard | Code |
|---|-------|------|
| 1 | System window filter | `WS_IsMovable(lParam)` (records `WS_OverlayTick` for: empty-class infrastructure, taskbar, explorer.exe/StartMenuExperienceHost.exe CoreWindow) |
| 2 | Overlay/Start menu bounce-back | `lParam == WS_LastForegroundHwnd` — Check A: overlay tick < 2000ms; Check B: Start menu visible (DWM uncloaked) |
| 3 | Tracker update | Save `prevHwnd`, set `WS_LastForegroundHwnd := lParam`, clear `WS_OverlayTick` |
| 4 | Foreground close fallback (500ms) | `A_TickCount - WS_LastDestroyTick < 500` (only armed when foreground window destroyed) |
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
| `WS_OverlayTick` | `A_TickCount` when overlay/infrastructure detected. Three sources: (1) empty-class infrastructure windows (fire before every activation), (2) taskbar activation (`Shell_TrayWnd`/`Shell_SecondaryTrayWnd`), (3) explorer.exe/StartMenuExperienceHost.exe CoreWindow. 2-band filter: 0-2000ms=bounce-back, >2000ms=allow. Guard #2 also directly checks Start menu visibility via DWM cloaked state |
| `WS_PrePending` | Associative array: CREATE-registered hwnd → `{mon, tick, qpc}` |
| `WS_Hidden` | Associative array: opacity-hidden hwnd → `hadLayered` (bool), or `-1` (sentinel = "processed") |
| `WS_OwnerSentinel` | Associative array: owner hwnd → `A_TickCount` (sibling CREATE suppression, 200ms active, 2s TTL) |
| `WS_EventHookCreate` | Handle from `SetWinEventHook` (EVENT_OBJECT_CREATE) |
| `WS_QPCFreq` | QPC frequency for µs-precision timing |

### Critical AHK v1.1 Details
- **32-bit masking**: `idObject & 0xFFFFFFFF` — WinEventProc uses 32-bit params but AHK reads 64-bit register slots on x64
- **Numeric coercion**: `hwnd + 0` — ensures consistent object key type in `WS_Pending`
- **Global discipline**: Every function accessing `WS_Pending` must declare `global WS_Pending`
- **No Fast flag**: `RegisterCallback("WS_OnWinEvent", "", 7)` — isolated pseudo-thread per callback

---

## Phase 10d: Overlay Detection — FIXED (Jan 30, 2026)

### Problem Summary

Guard #2 (overlay bounce-back) relied entirely on shell hooks to detect overlay windows like the Start menu. But the Start menu's CoreWindow does **not** fire `HSHELL_WINDOWACTIVATED`. Result: `WS_OverlayTick` was never set → bounce-back never triggered → windows incorrectly moved when Start menu closed.

### Previous Attempts (8 iterations)

| # | Approach | Failure |
|---|----------|---------|
| 1 | Time-bounded tick | Tick only set for movable windows; Start menu never refreshed it |
| 2 | Cursor-monitor comparison | Cursor moves freely between monitors |
| 3 | Boolean overlay flag | UWP internal CoreWindow set flag, blocking all UWP |
| 4 | 3-band timing | Correct timing logic but wrong detection source |
| 5a | PID-based source filter | UWP split-process makes PIDs always differ |
| 5b | explorer.exe source filter | Start menu CoreWindow doesn't fire shell hook at all |
| 6 | `GetKeyState("LWin", "P")` in Guard #1b | Doesn't work in shell hook `OnMessage` callback context — zero log entries despite LWin held |
| 7 | `~LWin Up::` hotkey only | Sets tick on key RELEASE, but UWP cascade fires on key DOWN (too late for same-tick activations) |

### Fix: Activation-Based Overlay Detection (Iteration 8)

**Key insight from debug log:** An empty-class infrastructure window (class="", exe="") fires a `HSHELL_WINDOWACTIVATED` event **before every window activation**. This is Windows' focus management signaling. Previously Guard #1 skipped these entirely — now they set `WS_OverlayTick`.

**Why this is safe:** Guard #2 requires `lParam == WS_LastForegroundHwnd` (same window re-activates). Non-movable windows never update `WS_LastForegroundHwnd`. So:
- **Start menu bounce-back:** Settings foreground → empty-class fires → Settings re-activates → same hwnd → **blocked** ✓
- **Normal switch:** Settings foreground → empty-class fires → VSCodium activates → different hwnd → **allowed** ✓
- **Alt+Tab round-trip:** Settings → VSCodium (updates tracker) → Settings → different from VSCodium → **allowed** ✓

**Guard #2 Check B — Direct Start menu detection:** Guard #2 also checks if `StartMenuExperienceHost.exe` is currently visible (uncloaked) via `DwmGetWindowAttribute(DWMWA_CLOAKED)`. This is reliable because the Start menu must still be open when the bounce-back activation fires — the activation is caused by its dismissal. Catches all Start menu open methods (Win key, mouse click, touch, Ctrl+Esc) without any hooks or hotkeys.

**Complementary signals (Guard #1 → Guard #2 Check A):**
- Empty-class infrastructure: fires before every activation (primary overlay tick signal).
- Taskbar activation: `Shell_TrayWnd`/`Shell_SecondaryTrayWnd` activations set `WS_OverlayTick`.
- CoreWindow: `explorer.exe` (Action Center) and `StartMenuExperienceHost.exe` (if it fires shell hooks).

**Timing simplified from 3-band to 2-band:** The <50ms exception (originally for UWP internal CoreWindow→Frame cascade) was removed because empty-class → re-activation fires at 0ms delta (same tick). The `lParam == WS_LastForegroundHwnd` check already prevents false positives for different-window switches.

**`~LWin Up::` hotkey removed (iteration 9):** Caused delays for Win+key hotkeys and didn't catch mouse Start button clicks. Replaced by direct Start menu visibility detection in Guard #2 Check B.

### UWP Split-Process Architecture (Reference)

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

---

## Phase 10d-2: Minimized Window Move — FIXED (Jan 30, 2026)

### Problem

`WS_MoveToMonitor` only handled maximized windows (`minMax == 1`). Minimized windows (`minMax == -1`) fell through to the normal path where `WinGetPos` returns garbage dimensions (~160×28 at position -32000,-32000). Result: windows activated from minimized state (e.g., via Alt+Tab) appeared at tiny size.

### Fix

Added `minMax == -1` branch using `GetWindowPlacement` API to retrieve the window's normal (restored) rectangle — accurate even while minimized. Window is then restored, sized correctly, and centered on the target monitor.
