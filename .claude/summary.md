# AHK Project: Context Transfer Summary

## Current State (1/13/2026)

### === EXTENDED WINDOW SPY ===

**Status**: Stable, usable

**v1.1 Features** (completed):
- Persistent tooltip showing Active Window + Window Under Cursor info
- Hover-to-pause: hovering over tooltip pauses updates
- Press `#w` again to close tooltip
- 800ms update interval with content-change detection (reduces flicker)
- Click tooltip to open dialog for copying text
- Dialog auto-sizes to fit content, positions flush to bottom-right corner
- Controls sorted alphabetically, items >80 chars filtered out
- Window Text cleaned (non-ASCII removed, deduped if long, >80 char items filtered)
- Comprehensive info: title, ahk_id, ahk_class, ahk_exe, dir, cmdline, PID (elevated indicator), monitor, pos, size, style, exstyle, focused control with hWnd, UIA pointer, window text, controls
- `FilterLongItems()` to remove items >80 chars from Controls/Window Text
- `SortList()` to sort Controls alphabetically
- Dialog positioned flush to bottom-right

**Pending: Dialog Width Matching Tooltip** (not yet implemented):

- Tooltip width is captured via `WinGetPos` during updates (line 832) as WindowSpyTooltipW
- `WindowSpyShowDialog()` needs to use captured width instead of fixed 700px
- Expand dialog height to fit content (up to screen max)

**Helper Functions**:

- `GetExePath()`, `GetMonitor()`, `IsProcessElevated()`, `WrapList()`, `CleanWindowText()`, `FilterLongItems()`, `SortList()`

---

### Pending Goal: Spawn Windows on Cursor's Monitor

**Goal**: Make new windows spawn on the monitor where the cursor is located, not the primary monitor.

**Foundation**: Already have `GetMonitor()` helper that determines which monitor a window is on.

**Approach**:

1. Create `GetCursorMonitor()` to get monitor number from cursor position
2. Hook into window creation events (Shell hook or similar)
3. When new window detected, move it to cursor's monitor

**Implementation plan**:

```autohotkey
; Get monitor from cursor position
GetCursorMonitor() {
  CoordMode, Mouse, Screen
  MouseGetPos, x, y
  SysGet, monCount, MonitorCount
  Loop, %monCount% {
    SysGet, mon, Monitor, %A_Index%
    If (x >= monLeft && x <= monRight && y >= monTop && y <= monBottom)
      Return A_Index
  }
  Return 1
}

; Shell hook to detect new windows
Gui +LastFound
hWnd := WinExist()
DllCall("RegisterShellHookWindow", "Ptr", hWnd)
MsgNum := DllCall("RegisterWindowMessage", "Str", "SHELLHOOK")
OnMessage(MsgNum, "ShellEvent")

ShellEvent(wParam, lParam) {
  If (wParam = 1) {  ; HSHELL_WINDOWCREATED
    targetMon := GetCursorMonitor()
    ; Move window lParam to targetMon
  }
}
```

---

## === EXPLORER SMOOTH SCROLL ===

### Method Assignments

| App/Region                       | Method     | Target  | Timer | Status  |
| -------------------------------- | ---------- | ------- | ----- | ------- |
| mmc.exe                          | UIA        | Control | 10ms  | Working |
| Explorer file lists              | UIA        | Control | 10ms  | Working |
| Explorer nav bar (SysTreeView32) | VSCROLL    | Control | 50ms  | Working |
| SystemInformer                   | WHEEL_CTRL | Control | 10ms  | Working |
| VS Code                          | WHEEL      | Window  | 10ms  | Working |

### Scroll Methods Explained

| Method         | Mechanism                                          | Granularity  | Best For                                                                |
| -------------- | -------------------------------------------------- | ------------ | ----------------------------------------------------------------------- |
| **UIA**        | SetScrollPercent via IUIAutomationScrollPattern    | Fractional % | Apps exposing ScrollPattern (Explorer lists, mmc)                       |
| **WHEEL**      | WM_MOUSEWHEEL with sub-120 delta to window         | Sub-notch    | Apps with internal cursor routing (VS Code, Electron)                   |
| **WHEEL_CTRL** | WM_MOUSEWHEEL to control (with fallback detection) | 1 line\*     | Controls that scroll 1 line per message (SI)                            |
| **VSCROLL**    | WM_VSCROLL 1 line per tick, dynamic timer          | 1 line       | Universal fallback (tree views, controls that scroll 3 lines per wheel) |

### File Location

`c:\Dropbox\Projects\AHK\AutoHotkey.ahk` lines 920-1170 (approximately)

---

## Helper Functions Reference

### GetExePath(winTitle := "A")

Returns `{path: "C:\...\app.exe", dir: "C:\..."}` for a window's process.

```autohotkey
exe := GetExePath()
MsgBox % exe.path  ; Full path to executable
MsgBox % exe.dir   ; Directory containing executable
```

### GetMonitor(winTitle := "A")

Returns 1-based monitor number where window's center is located.

```autohotkey
mon := GetMonitor()  ; Which monitor is active window on?
```

### IsProcessElevated(pid)

Returns true if process is running with elevated (admin) privileges.

```autohotkey
WinGet, pid, PID, A
If (IsProcessElevated(pid))
  MsgBox, Running as admin
```

### ProcessExistsByCommandLine(cmdLine)

Returns PID if a process with matching command line exists, 0 otherwise.

```autohotkey
pid := ProcessExistsByCommandLine("Code.exe"" """ . A_ScriptFullPath)
If (pid)
  WinActivate, ahk_pid %pid%
```

### WrapList(text, delimiter := ",", maxLen := 100)

Wraps comma-separated text at ~100 chars, preserving whole items.

```autohotkey
wrapped := WrapList("item1, item2, item3, ...", ",", 100)
; Returns: "item1, item2, item3, item4
;           item5, item6, item7"
```

### FilterLongItems(text, maxItemLen := 80)

Removes items exceeding maxItemLen from comma-separated list.

```autohotkey
filtered := FilterLongItems("short, verylongitemthatexceeds80chars..., another")
; Returns: "short, another"
```

### SortList(text)

Sorts comma-separated items alphabetically.

```autohotkey
sorted := SortList("Zebra, Apple, Mango")
; Returns: "Apple, Mango, Zebra"
```

---

## Session History Notes

### Extended Window Spy Development

1. Started with one-shot GUI from previous commit
2. Converted to persistent tooltip with 250ms timer
3. Reduced to 1500ms timer + content-change detection
4. Added hover-to-pause functionality
5. Fixed click-to-dialog positioning bug
6. Added comprehensive info fields
7. Added UIA info matching Under Cursor format
8. v1.1: Added filtering/sorting, improved dialog sizing
