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

## Phase 4: Performance
- [x] Instant-first: try moving immediately in shell hook callback (no timer delay)
- [x] `SetWinDelay, -1` in callback and timer threads (eliminates 100ms default per Win* command)

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
- [x] Non-blocking: `WS_PendingAltTab` + WinEvent SHOW detection (replaces 20ms BoundFunc timer)

## Phase 8: Code Restructure
- [x] Move init from inline auto-execute to `WS_Init()` function in window spawning section
- [x] Add `If` guard for RDP/Hyper-V/VMWare sessions (runtime check, not `#If` directive)
- [x] Move `WS_Debug` to top of file alongside `MB_Debug` for easy toggling

## Phase 9: Event-Driven UWP Detection (SetWinEventHook)
- [x] Register `EVENT_OBJECT_SHOW` (0x8002) hook via `SetWinEventHook`
- [x] Register `EVENT_OBJECT_UNCLOAKED` (0x8018) hook via `SetWinEventHook`
- [x] `RegisterCallback("WS_OnWinEvent", "", 7)` — 7-param WinEventProc, no Fast flag
- [x] 32-bit parameter masking for x64 register junk (`idObject & 0xFFFFFFFF`)
- [x] Numeric coercion `hwnd + 0` for consistent object key lookup
- [x] `CoInitialize` / `CoUninitialize` lifecycle
- [x] Idempotent event handling — only consume pending entry when ready+movable
- [x] Early discard of permanently excluded windows (ready + titled + not movable)
- [x] Replace 4 escalating polls with single 200ms backup + 2s timeout
- [x] `WS_Cleanup()` — unhook WinEvents before exit
- [x] Fix: add `WS_Pending` to `global` declaration in `WS_OnShellHook`

## Phase 9b: Cleanup
- [x] Remove `WS_FallbackRetry()` (dead code after event-skip refactor)
- [x] Remove RAW-UNCLOAK pre-filter diagnostic logging
- [x] Remove per-event/per-poll verbose debug lines
- [x] Streamline debug output to essential entries only (DEFERRED, MOVED, INIT)
- [x] Clean `WS_Pending` on `HSHELL_WINDOWDESTROYED` (immediate cleanup of destroyed deferred windows)
- [x] Restore shell hook error feedback via `WS_Log()` when registration fails
- [x] Add elapsed timing (`+NNms`) to MOVED log entries with source labels (show/uncloak/poll/timeout)
- [ ] Set `WS_Debug := 0` once feature is fully stable

## Phase 10: Win32 Zero-Flash (Exploration)
- [ ] Investigate `EVENT_OBJECT_CREATE` (0x8000) for pre-visibility interception
- [ ] Prototype CREATE → SHOW pipeline (bypass shell hook for creation detection)
- [ ] Measure actual Win32 flash duration with high-resolution timing (use `+NNms` log data)
- [ ] Test `EVENT_OBJECT_LOCATIONCHANGE` as alternative snap-back mechanism
- [ ] Evaluate top-level window filtering heuristics for CREATE events
- [ ] Compare approaches and select best trade-off

## Remaining / Future
- [ ] Test across apps: Sublime Text, Explorer, VS Code, Terminal, UWP Settings, dialogs
- [ ] Evaluate if any additional classes need exclusion based on testing
- [ ] Consider per-app exclusion list if certain apps fight the move
- [ ] Consider `TaskbarCreated` message handler to re-register hook after explorer.exe restart
