# Window Spawning on Cursor's Monitor — Implementation Plan

## Goal

Make new windows automatically appear on the monitor where the cursor is located, instead of defaulting to the primary monitor or wherever the app last appeared. Also move already-open windows to the cursor's monitor when they are re-activated (e.g., launching an already-running app from Start Menu or taskbar). Move the Alt+Tab switcher to the cursor's monitor.

## Context

- **Codebase**: AHK v1.1.14+ multi-file script (~2100 lines across 4 files)
- **Existing foundation**: `GetMonitor(winTitle)` — determines which monitor a window is on by center point
- **New helper**: `GetCursorMonitor()` — determines which monitor the cursor is on
- **Shell hooks**: `RegisterShellHookWindow` + `OnMessage` for `HSHELL_WINDOWCREATED`, `HSHELL_WINDOWACTIVATED`, `HSHELL_WINDOWDESTROYED`
- **WinEvent hooks**: `SetWinEventHook` for `EVENT_OBJECT_SHOW` (0x8002) and `EVENT_OBJECT_UNCLOAKED` (0x8018)

---

## Approach Comparison

### A: Timer-Based Polling (committed @ `1961bd7`)

```
Shell Hook → CREATED → ready? → YES → instant move
                               → NO  → SetTimer -10ms → WS_TryMove (retry 0-3)
                                        Escalating: 10ms → 20ms → 50ms → 150ms
~!Tab::  → 20ms BoundFunc timer → WS_MoveAltTab()
```

**Pros**: Simple, single mechanism (shell hook + timers)
**Cons**: Blind retries with fixed delays; UWP apps may need >150ms; 20ms Alt+Tab blocks thread

### B: Event-Driven SetWinEventHook (current working state)

```
Shell Hook → CREATED → ready+movable? → YES → instant move (same as A)
                                       → NO  → WS_Pending[hwnd] := {mon, tick}
                                                + 200ms backup poll + 2s timeout
WinEvent   → SHOW/UNCLOAK → hwnd in pending? → ready+movable? → move it
                                               → ready+excluded? → discard from pending
                                               → not ready? → leave for UNCLOAK/poll
~!Tab::    → non-blocking: set WS_PendingAltTab → SHOW event moves overlay
```

**Pros**: Event-driven = instant UWP moves (~62ms from shell hook); non-blocking Alt+Tab; early discard of excluded classes
**Cons**: Win32 apps still use shell hook instant path (same timing as A); added complexity (WinEvent hooks, 32-bit masking, global scoping)

### How to compare

1. `git stash` to revert to committed timer approach (A)
2. Test: open Settings, Explorer, Run dialog from different monitors
3. `git stash pop` to restore event-driven approach (B)
4. Test same apps — observe UWP latency difference

---

## Architecture (B — Event-Driven, current)

```
Auto-Execute (AutoHotkey.ahk, lines 1-26)
  ├── #Requires AutoHotkey v1.1.14+
  ├── #If IsRemoteSession() guard
  ├── If !IsRemoteSession() → WS_Init()
  └── Return

WS_Init()  (window-spawning.ahk)
  ├── Single WS := {} object for all state
  ├── Shell hook: RegisterShellHookWindow + OnMessage → WS_OnShellHook
  ├── WinEvent hooks:
  │   ├── SetWinEventHook(EVENT_OBJECT_SHOW)     → WS_OnWinEvent
  │   ├── SetWinEventHook(EVENT_OBJECT_UNCLOAKED) → WS_OnWinEvent
  │   └── SetWinEventHook(EVENT_OBJECT_CREATE)    → WS_OnWinEvent
  └── OnExit → WS_Cleanup

WS_OnShellHook(wParam, lParam, msg, hwnd)
  ├── DESTROYED → brief-process detection (Tier 1) + cleanup
  ├── ACTIVATED → positive intent check (Tier 1 brief-process, Tier 2 overlay-launch) → move
  └── CREATED:
       ├── ready + movable → instant move
       ├── ready + has title + not movable → skip
       └── not ready OR no title → WS.Pending[hwnd] + backup poll + timeout

WS_OnWinEvent(hHook, event, hwnd, ...)  [7-param WinEventProc callback]
  ├── 32-bit mask idObject/idChild (x64 register junk fix)
  ├── Filter: OBJID_WINDOW only (idObject=0, idChild=0)
  ├── CREATE: pre-register in WS.PrePending + hide via opacity (zero-flash)
  ├── Pending creation: ready+movable → consume+move
  │                     ready+titled+excluded → discard
  │                     not ready → leave for next event
  └── Pending Alt+Tab: XamlExplorerHostIslandWindow → move

WS_BackupPoll(hwnd)     — 200ms single poll, same ready+movable+discard logic
WS_TimeoutPending(hwnd)  — 2s safety net, last-ditch attempt then discard
WS_ProcessPending(hwnd, targetMon) — movable check + monitor comparison + move
```

---

## Key Design Decisions

### 1. Two separate WinEvent hooks (not a range)
Two `SetWinEventHook` calls — one for SHOW (0x8002), one for UNCLOAK (0x8018) — instead of a range. A range 0x8002–0x8018 would include unrelated events (HIDE, FOCUS, LOCATIONCHANGE, etc.) causing unnecessary callback overhead.

### 2. RegisterCallback without Fast flag
`RegisterCallback("WS_OnWinEvent", "", 7)` — no "F" (Fast) flag. Each callback gets an isolated pseudo-thread, preventing interference with AHK's last-found window and ErrorLevel. Critical for stability when WinEvent fires during other AHK operations.

### 3. 32-bit parameter masking
`idObject := idObject & 0xFFFFFFFF` before comparing. On x64 Windows, `RegisterCallback` reads full 64-bit register slots, but WinEventProc parameters are 32-bit LONG/DWORD. Upper 32 bits may contain junk (observed: `child=4294967296` = 0x100000000). Masking extracts the actual 32-bit value.

### 4. Numeric coercion for object keys
`hwnd := hwnd + 0` ensures consistent key type in `WS_Pending` associative array. AHK v1.1 object keys are strings internally; without coercion, `hwnd` from DllCall (integer) and `hwnd` from RegisterCallback (possibly string) could create different keys.

### 5. Idempotent event handling
WinEvent callback only consumes `WS_Pending` entries when the window is fully ready AND movable. If not ready, the entry stays for subsequent events (UNCLOAK after SHOW) or backup poll. Multiple events hitting the same entry is harmless — first success calls `Delete()`, rest find nothing.

### 6. Early discard of permanently excluded windows
When a pending window becomes ready (`WS_IsReady` true) but has a title and fails `WS_IsMovable` (excluded class, tool window, etc.), it's immediately discarded from `WS_Pending`. This prevents `Windows.UI.Core.CoreWindow` entries from lingering for the full 2s timeout.

### 7. CoInitialize for COM compatibility
`DllCall("ole32\CoInitialize", "Ptr", 0)` before `SetWinEventHook`. MS docs recommend COM initialization. AHK already calls `OleInitialize` but the extra call is harmless (returns `S_FALSE`). Paired with `CoUninitialize` in `WS_Cleanup`.

### 8. Cursor captured at shell hook time
`GetCursorMonitor()` is called inside `WS_OnShellHook()` and stored in `WS_Pending[hwnd].mon`. Even if the cursor moves during the delay before SHOW/UNCLOAK fires, the window goes to the correct monitor.

### 9. Non-blocking Alt+Tab
Old approach: `WinWait` blocked the hotkey thread for up to 300ms. New approach: sets `WS_PendingAltTab` and returns immediately. `WS_OnWinEvent` catches the SHOW event for `XamlExplorerHostIslandWindow` and moves it. 500ms timeout clears stale state.

### 10. Global declaration discipline
AHK v1.1 functions default to local scope. All WS_* functions declare `global WS` — a single object containing all state (replaces 12+ individual globals from earlier phases). This eliminates the class of bugs where a missing global declaration causes silent failures.

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

## Win32 Zero-Flash (Phase 10 — Implemented)

Win32 zero-flash is now implemented using the CREATE + SHOW pipeline with opacity hiding:

```
EVENT_OBJECT_CREATE → WS.PrePending[hwnd] := {mon, tick, qpc}
                    → Hide via WS_EX_LAYERED + alpha 0
Shell Hook / SHOW   → WS_MoveToMonitor() → restore opacity
```

**Key details:**
- CREATE fires 55-77ms before the shell hook — enough time to hide the window before first paint
- Opacity approach (not pre-positioning) avoids coordinate mapping issues with unknown origin monitors
- Owner-based sentinel (`WS.OwnerSentinel`) prevents sibling dialogs from being re-hidden
- Sentinel mechanism (`WS.Hidden[hwnd] := -1`) prevents duplicate CREATE events from re-hiding moved windows
- Debug mode uses alpha 128 (50% visibility) instead of alpha 0 for easier troubleshooting

---

## Verification

| # | Test | Expected |
|---|------|----------|
| 1 | Script reload (Shift+Alt+R) | No errors → hooks registered OK |
| 2 | Cursor on monitor 2, open Notepad | `MOVED (instant)` in log → Win32 instant path |
| 3 | Cursor on monitor 2, open Settings | `MOVED (event)` in log → UWP event path |
| 4 | File → Save As in app | Dialog stays with parent (owner filter) |
| 5 | Win+R Run dialog | Moves to cursor's monitor (hidden-owner allowed) |
| 6 | Launch already-open app from Start | `MOVED (activate)` in log |
| 7 | Open 3 Explorer windows rapidly | All 3 land on cursor's monitor |
| 8 | Close a window | Next window stays put (destroy guard) |
| 9 | Alt+Tab with cursor on different monitor | Switcher appears on cursor's monitor |
| 10 | `git stash` / `git stash pop` | Compare timer vs event latency on UWP apps |

### Debug Log Reference (`WS_Debug := 1`)
Log file: `%TEMP%\WS_Debug.log`
- `INIT:` — hook registration status
- `DEFERRED:` — window deferred to event/poll pipeline
- `MOVED (instant):` — Win32 instant path (shell hook)
- `MOVED (event):` — UWP event path (SHOW/UNCLOAK)
- `MOVED (activate):` — re-activation of existing window
