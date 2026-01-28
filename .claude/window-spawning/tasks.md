# Window Spawning on Cursor's Monitor

## Phase 1: Core Infrastructure
- [ ] Register shell hook in auto-execute section (hidden GUI + `RegisterShellHookWindow` + `OnMessage`)
- [ ] Add `G_MoveNewWindows := 1` global toggle
- [ ] Implement `GetCursorMonitor()` helper (cursor coordinates → 1-based monitor index)
- [ ] Implement `OnShellHook(wParam, lParam)` callback — filter for `HSHELL_WINDOWCREATED` (wParam=1)
- [ ] Implement `MoveNewWindow:` timer label — deferred (50ms) window move with basic validation

## Phase 2: Window Movement
- [ ] Implement `MoveWindowToMonitor(hwnd, targetMon)` — relative position mapping between monitors
- [ ] Use `SysGet MonitorWorkArea` for taskbar-aware positioning
- [ ] Clamp window position to target monitor bounds (handle oversized windows)
- [ ] Center detection: if window is centered on source monitor, center on target instead

## Phase 3: Filtering & Edge Cases
- [ ] Implement `IsWindowMovable(hwnd)` — comprehensive filter function
- [ ] Skip owned/child windows (`GetWindow(hwnd, GW_OWNER)`)
- [ ] Skip tool windows (`WS_EX_TOOLWINDOW` = 0x80)
- [ ] Skip cloaked UWP windows (`DwmGetWindowAttribute` with `DWMWA_CLOAKED=14`)
- [ ] Skip windows with no title
- [ ] Class exclusion list: `tooltips_class32`, `NotifyIconOverflowWindow`, `Shell_TrayWnd`, `Progman`, `WorkerW`, `MultitaskingViewFrame`
- [ ] Retry logic: if window not ready at 50ms, retry once at 150ms

## Phase 4: Polish
- [ ] Add `#m` toggle hotkey with tooltip feedback ("Window spawning: ON/OFF")
- [ ] Add `OnExit` cleanup label (`DeregisterShellHookWindow` + `Gui Destroy`)
- [ ] Debug mode: tooltip showing "Moved [title] to monitor N"
- [ ] Test: Notepad, Explorer, VS Code, Terminal, UWP Settings, dialogs, rapid creation
- [ ] Set `MB_Debug := 0` if still on
