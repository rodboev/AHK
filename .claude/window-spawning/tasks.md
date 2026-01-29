# Window Spawning on Cursor's Monitor

## Phase 1: Core Infrastructure
- [x] Register shell hook in auto-execute section (hidden GUI + `RegisterShellHookWindow` + `OnMessage`)
- [x] Verify registration return values (show `WS ERROR:` tooltip on failure)
- [x] Implement `GetCursorMonitor()` helper (cursor coordinates → 1-based monitor index)
- [x] Implement `WS_OnShellHook()` callback — handle `HSHELL_WINDOWCREATED` (wParam=1)
- [x] BoundFunc per-window timers (no race condition with rapid window creation)
- [x] Capture cursor monitor at event time (not timer time)

## Phase 2: Window Movement
- [x] Implement `WS_MoveToMonitor(hwnd, srcMon, tgtMon)` — relative position mapping
- [x] Use `SysGet MonitorWorkArea` for taskbar-aware positioning
- [x] Clamp window position to target monitor bounds (handle oversized windows)
- [x] Handle maximized windows (restore → move → re-maximize)

## Phase 3: Filtering & Edge Cases
- [x] Implement `WS_IsReady(hwnd)` — timing gate (visible, sized, uncloaked)
- [x] Implement `WS_IsMovable(hwnd)` — policy gate
- [x] Smart owner check: skip only if owner is visible (allows Win+R Run dialog)
- [x] Skip tool windows (`WS_EX_TOOLWINDOW` = 0x80)
- [x] Skip cloaked UWP windows (`DwmGetWindowAttribute` with `DWMWA_CLOAKED=14`)
- [x] Skip windows with no title
- [x] Class exclusion list (9 classes: tooltips, taskbar, desktop, UWP splash, etc.)
- [x] Retry logic with escalating delays: 10ms → 20ms → 50ms → 150ms (3 retries)

## Phase 4: Performance
- [x] Instant-first: try moving immediately in shell hook callback (no timer delay)
- [x] `SetWinDelay, -1` in callback and timer threads (eliminates 100ms default per Win* command)
- [x] Short fallback timer (-10ms) only when window isn't ready yet

## Phase 5: Activation Support
- [x] Handle `HSHELL_WINDOWACTIVATED` (wParam=4) — move existing windows to cursor's monitor
- [x] Handle `HSHELL_RUDEAPPACTIVATED` (wParam=0x8004) — fullscreen/elevated apps
- [x] No readiness check needed (activated windows are already visible)
- [x] Natural click protection (cursor on same monitor = no move)

## Phase 6: Activation Guards
- [x] Track `HSHELL_WINDOWDESTROYED` (wParam=2) → suppress activation within 500ms of close
- [x] Track `WS_LastForegroundHwnd` → suppress re-activation of same window (overlay dismissal)
- [x] Guard ordering: `WS_IsMovable()` before tracker update (prevents system window pollution)
- [x] Taskbar cursor check (skip activation when cursor is over taskbar)

## Phase 7: Alt+Tab Support
- [x] `~!Tab::` passthrough hotkey — intercepts Alt+Tab without blocking native behavior
- [x] `WS_MoveAltTab()` — finds `Task Switching ahk_class XamlExplorerHostIslandWindow`
- [x] 20ms BoundFunc timer — allows DWM overlay to appear before checking

## Phase 8: Code Restructure
- [x] Move init from inline auto-execute to `WS_Init()` function in window spawning section
- [x] Add `If` guard for RDP/Hyper-V/VMWare sessions (runtime check, not `#If` directive)
- [x] Move `#If...Return...#If` block back above init call for readability
- [x] Rename `G_WS_` prefix → `WS_` prefix (matches `MB_` convention)
- [x] Move `WS_Debug` to top of file alongside `MB_Debug` for easy toggling

## Phase 9: Cleanup & Debug
- [x] `WS_Cleanup()` on exit: `DeregisterShellHookWindow` + `Gui Destroy`
- [x] `WS_Debug` with comprehensive tooltips at every decision point
- [x] Debug tooltips: HOOK, MOVED (instant/activate/deferred), RETRY, SKIP, OK, ERROR
- [ ] Set `WS_Debug := 0` once feature is fully stable

## Remaining / Future
- [ ] Test across apps: Sublime Text, Explorer, VS Code, Terminal, UWP Settings, dialogs
- [ ] Evaluate if any additional classes need exclusion based on testing
- [ ] Consider per-app exclusion list if certain apps fight the move
- [ ] Consider `TaskbarCreated` message handler to re-register hook after explorer.exe restart
