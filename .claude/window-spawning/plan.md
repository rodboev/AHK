# Window Spawning on Cursor's Monitor — Implementation Plan

## Goal

Make new windows automatically appear on the monitor where the cursor is located, instead of defaulting to the primary monitor or wherever the app last appeared. Also move already-open windows to the cursor's monitor when they are re-activated (e.g., launching an already-running app from Start Menu or taskbar). Move the Alt+Tab switcher to the cursor's monitor.

## Context

- **Codebase**: Monolithic AHK v1.1 script (`AutoHotkey.ahk`, ~1700 lines with this feature)
- **Existing foundation**: `GetMonitor(winTitle)` — determines which monitor a window is on by center point
- **New helper**: `GetCursorMonitor()` — determines which monitor the cursor is on
- **Shell hooks**: `RegisterShellHookWindow` + `OnMessage` for `HSHELL_WINDOWCREATED`, `HSHELL_WINDOWACTIVATED`, and `HSHELL_WINDOWDESTROYED`

---

## Architecture (as implemented)

```
Auto-Execute (lines 20-31)
  ├── WS_Debug := 0  (debug tooltips — set to 1 to diagnose)
  ├── #If (RDP/Hyper-V/VMWare)  ← hotkey context directive
  ├── If !(RDP/Hyper-V/VMWare) → WS_Init()  ← runtime guard
  └── Return  ← ends auto-execute

WS_Init()  (line ~1441, in window spawning section)
  ├── WS_LastDestroyTick := 0
  ├── WS_LastForegroundHwnd := 0
  ├── WS_ExcludedClasses := [...]
  ├── Gui, ShellHook:+LastFound / Show Hide
  ├── WS_HookHwnd := WinExist()
  ├── RegisterShellHookWindow (+ verify return value)
  ├── RegisterWindowMessage("SHELLHOOK") (+ verify > 0)
  ├── OnMessage → WS_OnShellHook()
  └── OnExit → WS_Cleanup()

WS_OnShellHook(wParam, lParam, msg, hwnd)
  ├── wParam == 2: HSHELL_WINDOWDESTROYED
  │   └── Record WS_LastDestroyTick := A_TickCount (for activation guard)
  ├── wParam == 1: HSHELL_WINDOWCREATED
  │   ├── Try instant move (no timer) if window is already ready
  │   └── Else defer via BoundFunc timer (-10ms) → WS_TryMove()
  ├── wParam == 4 or 0x8004: HSHELL_WINDOWACTIVATED / RUDE
  │   └── Activation guard chain (see below)
  └── All other wParam values → ignored

Activation Guard Chain (7 checks, in order):
  1. WS_IsMovable(lParam)          → filter system windows (prevents tracker pollution)
  2. lParam == WS_LastForegroundHwnd → skip overlay re-activation (Start menu, etc.)
  3. Save prevHwnd, update tracker  → WS_LastForegroundHwnd := lParam
  4. A_TickCount - WS_LastDestroyTick < 500 → skip Z-order fallback after close
  5. prevHwnd MinMax == -1          → skip Z-order fallback after minimize
  6. Cursor over taskbar?           → skip taskbar button clicks
  7. windowMon == cursorMon?        → already on correct monitor

WS_TryMove(hwnd, targetMon, attempt)          ← BoundFunc callback
  ├── if !WS_IsReady(hwnd) → retry with attempt+1 (max 3)
  │   Escalating delays: 20ms → 50ms → 150ms
  ├── if !WS_IsMovable(hwnd) → return (skip)
  ├── windowMon := GetMonitor("ahk_id " . hwnd)
  ├── if windowMon == targetMon → return (already correct)
  └── WS_MoveToMonitor(hwnd, windowMon, targetMon)

~!Tab:: hotkey  (line ~1680)
  ├── Capture cursor monitor
  ├── 20ms BoundFunc timer → WS_MoveAltTab()
  └── Finds "Task Switching ahk_class XamlExplorerHostIslandWindow" and moves it

Helper Functions (lines ~190-200)
  └── GetCursorMonitor() → 1-based monitor index from mouse position

Feature Functions (lines ~1441-1700)
  ├── WS_Init()              → hook registration, globals, OnExit
  ├── WS_OnShellHook()       → shell hook message handler (created + activated + destroyed)
  ├── WS_TryMove()           → deferred per-window processing via BoundFunc
  ├── WS_IsReady(hwnd)       → timing: visible, sized, uncloaked?
  ├── WS_IsMovable(hwnd)     → policy: not dialog, not tool, not excluded?
  ├── WS_MoveToMonitor()     → reposition with relative mapping + maximize handling
  ├── ~!Tab:: hotkey         → Alt+Tab switcher passthrough hook
  ├── WS_MoveAltTab()        → moves Task Switching window to cursor's monitor
  └── WS_Cleanup()           → deregister shell hook on exit
```

---

## Key Design Decisions

### 1. BoundFunc per window (no race condition)

Each `HSHELL_WINDOWCREATED` event creates a unique `Func("WS_TryMove").Bind(hwnd, cursorMon, attempt)` function object. AHK v1.1 treats each BoundFunc as an independent timer key, so multiple windows spawning rapidly each get their own processing pipeline. No shared global state to overwrite.

### 2. Instant-first, defer-second

The shell hook callback tries to move the window **immediately** (inside `WS_OnShellHook`). If the window is already visible and sized, this avoids any visible "jump" between monitors. Only if the window isn't ready yet does it fall back to the timer path with short escalating delays (10ms → 20ms → 50ms → 150ms).

### 3. SetWinDelay, -1

AHK v1.1 defaults to `SetWinDelay, 100` — a 100ms sleep after every `WinMove`, `WinGet`, `WinRestore`, etc. A single `WS_MoveToMonitor` call chains ~3 Win* commands = 300ms of hidden sleep. Setting `SetWinDelay, -1` in the shell hook and timer callbacks eliminates this entirely. Thread-safe because AHK pseudo-threads have independent settings.

### 4. Cursor captured at event time

`GetCursorMonitor()` is called inside `WS_OnShellHook()` — the instant the event fires — not when the deferred timer processes it 10-150ms later. The cursor monitor is passed through the BoundFunc so even if the cursor moves during the delay, the window goes to the right monitor.

### 5. Activation events for already-open windows

Handles `HSHELL_WINDOWACTIVATED` (wParam=4) and `HSHELL_RUDEAPPACTIVATED` (wParam=0x8004) in addition to creation. When a user launches an already-running app (e.g., Settings from Start Menu), the window is activated rather than created — we move it to the cursor's monitor. Naturally safe: clicking directly on a window means cursor is on that monitor → no move.

### 6. Smart owner filtering

Owned windows with a **visible** owner are skipped (real dialogs like Save As should stay with their parent). Owned windows with a **hidden** owner are allowed through (standalone system dialogs like Win+R Run, whose owner is the hidden Explorer shell).

### 7. Foreground tracking (overlay dismissal guard)

`WS_LastForegroundHwnd` tracks the last **movable** window that was activated. When a system overlay (Start menu, Action Center, notifications) opens, no shell hook fires — so the tracker stays pointed at the window that was active before the overlay. When the overlay closes and re-activates that same window, `lParam == WS_LastForegroundHwnd` → skip. The tracker is only updated for windows that pass `WS_IsMovable()`, preventing system windows from polluting it.

### 8. Destroy tracking (close-then-activate guard)

When a window is closed, Windows auto-activates the next window in the Z-order. This is system-initiated, not user-initiated. `HSHELL_WINDOWDESTROYED` records `WS_LastDestroyTick`, and any activation within 500ms is suppressed.

### 9. Alt+Tab via passthrough hotkey

The Alt+Tab switcher (`XamlExplorerHostIslandWindow`) is a DWM overlay invisible to shell hooks. A `~!Tab::` hotkey (passthrough — `~` lets Alt+Tab work normally) fires a 20ms BoundFunc timer to find and move the Task Switching window after it appears.

### 10. Init in function, not auto-execute

All initialization is in `WS_Init()` (called from auto-execute) rather than inline. This keeps the auto-execute section clean and groups all WS_* code in the window spawning section. The auto-execute uses a runtime `If` guard to skip init in RDP/Hyper-V/VMWare sessions.

---

## Window Filtering

### WS_IsReady(hwnd) — timing gate
- Window must exist
- Must be visible (`WS_VISIBLE`)
- Must not be cloaked (`DwmGetWindowAttribute` with `DWMWA_CLOAKED=14`)
- Must have non-zero size

### WS_IsMovable(hwnd) — policy gate
- Must have a non-empty title
- Owner check: skip only if owner is visible (allows hidden-owner dialogs like Win+R)
- Skip tool windows (`WS_EX_TOOLWINDOW` = 0x80)
- Skip excluded classes (see list below)

### Excluded Classes
| Class | Reason |
|-------|--------|
| `tooltips_class32` | System tooltip popups |
| `NotifyIconOverflowWindow` | System tray overflow |
| `Shell_TrayWnd` | Main taskbar |
| `Shell_SecondaryTrayWnd` | Secondary monitor taskbar |
| `Progman` | Desktop window manager |
| `WorkerW` | Desktop wallpaper layer |
| `MultitaskingViewFrame` | Old Alt-Tab / Task View |
| `Windows.UI.Core.CoreWindow` | UWP hosted windows, Start menu |
| `ForegroundStaging` | Windows transition animations |

---

## File Locations

All changes in `AutoHotkey.ahk`:

| Location | What |
|----------|------|
| Lines 20-21 | Debug flags (`MB_Debug`, `WS_Debug`) |
| Lines 23-31 | Auto-execute: `#If` context, `If` guard → `WS_Init()`, `Return` |
| Lines ~190-200 | `GetCursorMonitor()` helper (after `GetMonitor()`) |
| Lines ~1441-1700 | Feature section: `WS_Init()`, all WS_* functions, `~!Tab::` hotkey, cleanup |

---

## Verification

| # | Test | Expected |
|---|------|----------|
| 1 | Script reload (Shift+Alt+R) | No `WS ERROR:` tooltip → hooks registered OK |
| 2 | Open Sublime Text, watch tooltip | `WS HOOK` appears → shell hook works |
| 3 | Cursor on monitor 2, open Sublime Text | `WS MOVED (instant)` → window on monitor 2 |
| 4 | Cursor on monitor 1, open Explorer (Win+E) | Explorer appears on monitor 1 |
| 5 | Open File → Save As in app | `WS SKIP:` → dialog stays with parent |
| 6 | Win+R Run dialog | Moves to cursor's monitor (hidden-owner dialog allowed) |
| 7 | Launch already-open Settings app | `WS MOVED (activate)` → moves to cursor's monitor |
| 8 | Click directly on window on other monitor | No move (cursor already on that monitor) |
| 9 | Open 3 Explorer windows rapidly | All 3 land on cursor's monitor |
| 10 | Close a window | Next window stays on its monitor (destroy guard) |
| 11 | Open/close Start menu | Previously active window stays put (foreground guard) |
| 12 | Alt+Tab with cursor on different monitor | Task Switcher appears on cursor's monitor |
| 13 | Once stable | Set `WS_Debug := 0` to silence tooltips |

### Debug Tooltip Reference
- `WS HOOK` — shell hook fired for created window
- `WS MOVED (instant)` — moved immediately in callback (fastest path)
- `WS MOVED (activate)` — moved on re-activation of existing window
- `WS MOVED` — moved via deferred timer
- `WS RETRY` — window not ready, retrying
- `WS SKIP` — filtered out (shows class for diagnosis)
- `WS OK` — already on correct monitor
- `WS ERROR` — shell hook registration failed (shown at startup)
