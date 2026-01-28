# Window Spawning on Cursor's Monitor — Implementation Plan

## Goal

Make new windows automatically spawn on the monitor where the cursor is located, instead of defaulting to the primary monitor or wherever the app last appeared.

## Context

- **Codebase**: Monolithic AHK v1.1 script (`AutoHotkey.ahk`, ~1430 lines)
- **Existing foundation**: `GetMonitor(winTitle)` at line 159 — determines which monitor a window is on by center point
- **Auto-execute section**: Lines 1-19 (directives + `MB_Debug` flag). Shell hook init must go here.
- **Helper functions**: Lines 94-212. New helpers (`GetCursorMonitor`, `MoveWindowToMonitor`) go here.
- **No shell hooks currently exist** in the codebase

---

## Sequential Design Walkthrough

### Step 1: What mechanism intercepts new window creation?

**Shell hooks** via `RegisterShellHookWindow`. Windows sends `HSHELL_WINDOWCREATED` (wParam=1) to any registered window when a new top-level window appears. This is the standard AHK v1.1 approach.

**Implementation**:
```autohotkey
; In auto-execute section (after line 19)
Gui, ShellHook:+LastFound
Gui, ShellHook:Show, Hide
G_ShellHookHwnd := WinExist()
DllCall("RegisterShellHookWindow", "Ptr", G_ShellHookHwnd)
G_ShellHookMsg := DllCall("RegisterWindowMessage", "Str", "SHELLHOOK")
OnMessage(G_ShellHookMsg, "OnShellHook")
```

This creates an invisible GUI window, registers it for shell messages, and routes all shell events to `OnShellHook()`.

### Step 2: What information do we need when a window is created?

1. **New window's hwnd** — from `lParam` of the shell message
2. **Cursor's current monitor** — new `GetCursorMonitor()` function
3. **New window's current monitor** — existing `GetMonitor()` function
4. **Target monitor's work area** — `SysGet, mon, MonitorWorkArea, N` for positioning

### Step 3: How do we determine the cursor's monitor?

Analogous to `GetMonitor()` but uses cursor coordinates instead of window center:

```autohotkey
GetCursorMonitor() {
  CoordMode, Mouse, Screen
  MouseGetPos, mx, my
  SysGet, monCount, MonitorCount
  Loop, %monCount% {
    SysGet, mon, Monitor, %A_Index%
    If (mx >= monLeft && mx <= monRight && my >= monTop && my <= monBottom)
      Return A_Index
  }
  Return 1
}
```

### Step 4: How do we move a window to a different monitor?

Strategy: **Preserve the window's relative position** within its current monitor, mapped to the target monitor. If the window is at 20% from the left edge of monitor A, place it at 20% from the left edge of monitor B.

```
Source monitor work area: (srcLeft, srcTop, srcW, srcH)
Window position:          (winX, winY, winW, winH)
Target monitor work area: (tgtLeft, tgtTop, tgtW, tgtH)

Relative position:
  relX = (winX - srcLeft) / srcW
  relY = (winY - srcTop)  / srcH

New position:
  newX = tgtLeft + relX * tgtW
  newY = tgtTop  + relY * tgtH

Clamp to target monitor bounds:
  newX = Max(tgtLeft, Min(newX, tgtLeft + tgtW - winW))
  newY = Max(tgtTop,  Min(newY, tgtTop  + tgtH - winH))
```

Special case: if the window was **centered** on the source monitor (common for new windows), center it on the target monitor instead.

### Step 5: What windows should we SKIP (not move)?

A window should NOT be moved if:

1. **Already on cursor's monitor** — most common case, no action needed
2. **Owned/child window** — dialogs should follow their parent, not the cursor. Check: `DllCall("GetWindow", "Ptr", hwnd, "UInt", 4)` returns owner hwnd
3. **Tool window** — has `WS_EX_TOOLWINDOW` (0x80) extended style. These are small utility windows (tooltips, floating toolbars)
4. **Not visible** — `WinGet, style` check for `WS_VISIBLE` (0x10000000)
5. **No title** — likely a transient or system window
6. **Excluded class** — system windows that shouldn't be touched: `tooltips_class32`, `NotifyIconOverflowWindow`, `Shell_TrayWnd`, `Progman`, `WorkerW`, `MultitaskingViewFrame`
7. **Cloaked window** — UWP apps create cloaked windows before showing them. Check `DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED=14)`

### Step 6: Timing — when is the window ready to move?

`HSHELL_WINDOWCREATED` fires when the window is first created, but:
- The window may not have its final size/position yet
- Some apps create windows at (0,0) then move them
- UWP apps go through a cloaked→uncloaked transition

**Solution**: Use a **deferred move** with a short `SetTimer` (50-100ms). Store the hwnd in a variable, and on timer fire, check if the window is visible, has a title, and has a reasonable position. If not ready, retry once more (100ms). If still not ready, give up.

```autohotkey
OnShellHook(wParam, lParam) {
  If (wParam != 1)  ; Only HSHELL_WINDOWCREATED
    Return
  global G_PendingHwnd
  G_PendingHwnd := lParam
  SetTimer, MoveNewWindow, -50  ; One-shot 50ms timer
}
```

### Step 7: Configuration and toggle

- **Global enable/disable**: `G_MoveNewWindows := 1` in auto-execute (on by default)
- **Hotkey toggle**: e.g., `#m` to toggle on/off with tooltip feedback
- **Exclusion list**: Array of window classes to never move

### Step 8: Cleanup on script exit

Unregister the shell hook to be a good citizen:
```autohotkey
OnExit, CleanupShellHook
; ...
CleanupShellHook:
  DllCall("DeregisterShellHookWindow", "Ptr", G_ShellHookHwnd)
  Gui, ShellHook:Destroy
  ExitApp
```

---

## Architecture Summary

```
Auto-Execute Section
  ├── Create hidden GUI (ShellHook)
  ├── RegisterShellHookWindow
  ├── OnMessage → OnShellHook()
  └── G_MoveNewWindows := 1

OnShellHook(wParam=1, lParam=hwnd)
  ├── Filter: HSHELL_WINDOWCREATED only
  ├── Store hwnd → G_PendingHwnd
  └── SetTimer, MoveNewWindow, -50

MoveNewWindow: (timer label, fires once)
  ├── Validate window (visible, has title, not owned, not tool window, not cloaked, not excluded class)
  ├── cursorMon := GetCursorMonitor()
  ├── windowMon := GetMonitor("ahk_id " . G_PendingHwnd)
  ├── If cursorMon = windowMon → Return (already correct)
  └── MoveWindowToMonitor(G_PendingHwnd, cursorMon)

Helper Functions
  ├── GetCursorMonitor() → 1-based monitor index
  ├── MoveWindowToMonitor(hwnd, targetMon) → repositions window
  └── IsWindowMovable(hwnd) → filters excluded windows
```

---

## File Changes

All changes in `AutoHotkey.ahk`:

| Location | Change |
|----------|--------|
| Lines 19-20 (auto-execute) | Add shell hook registration + `G_MoveNewWindows := 1` |
| Lines ~170 (after GetMonitor) | Add `GetCursorMonitor()` function |
| Lines ~175 (after GetCursorMonitor) | Add `MoveWindowToMonitor(hwnd, targetMon)` function |
| Lines ~180 (after MoveWindowToMonitor) | Add `IsWindowMovable(hwnd)` filter function |
| Lines ~185 (new section) | Add `OnShellHook()` callback + `MoveNewWindow:` timer label |
| End of hotkeys section | Add `#m::` toggle hotkey (optional) |
| End of script | Add `OnExit` cleanup label |

---

## Phases

### Phase 1: Core Infrastructure
- Shell hook registration in auto-execute
- `GetCursorMonitor()` helper
- `OnShellHook()` callback with basic filtering
- `MoveNewWindow:` timer with deferred move

### Phase 2: Window Movement
- `MoveWindowToMonitor()` with relative position mapping
- Work area awareness (respects taskbar)
- Size clamping for windows larger than target monitor

### Phase 3: Filtering & Edge Cases
- `IsWindowMovable()` with full exclusion logic
- Owned/child window detection
- Tool window filtering (`WS_EX_TOOLWINDOW`)
- Cloaked window detection (UWP apps)
- Class exclusion list

### Phase 4: Polish
- `#m` toggle hotkey with tooltip feedback
- OnExit cleanup
- Debug mode (tooltip showing moved windows)
- Test across apps: Notepad, Explorer, VS Code, Terminal, UWP apps, dialogs

---

## Verification

1. **Basic test**: Open Notepad while cursor is on monitor 2 → Notepad appears on monitor 2
2. **Multi-monitor**: Repeat on 3 monitors, different positions
3. **Dialog test**: Open File → Save As in Notepad → dialog should follow parent, not cursor
4. **UWP test**: Open Settings or Calculator → should appear on cursor's monitor after uncloaking
5. **Toggle test**: Press `#m` to disable → new windows use default positioning
6. **Explorer test**: Open new Explorer window → appears on cursor's monitor
7. **Terminal test**: Press F10 → Windows Terminal opens on cursor's monitor
8. **Rapid creation**: Open multiple windows quickly → all land on correct monitor

---

## Key Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Moving windows causes visual glitch (flash at wrong position then correct) | 50ms timer lets window settle; most apps create near final position |
| Breaking app state by moving during initialization | Only move after visible + titled + non-cloaked checks |
| Performance impact from shell hook | Callback is lightweight; only fires for top-level window creation |
| DPI differences between monitors | Use work area coordinates (already DPI-aware via SysGet) |
| AHK v1.1 `OnMessage` thread safety | Shell hook fires on AHK's main thread; no concurrency issues |
