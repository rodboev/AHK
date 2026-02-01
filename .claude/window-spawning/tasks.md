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

## Phase 10: Win32 Zero-Flash (Exploration)

### Stage A: Timing Measurement ✓
- [x] Hook `EVENT_OBJECT_CREATE` (0x8000) via `SetWinEventHook` in `WS_Init()`
- [x] Add `WS_QPC()` helper + `WS_QPCFreq` for µs-precision timing (120Hz = 8.3ms/frame)
- [x] Add `WS_CreateTiming` dict to record `{tick, qpc}` at CREATE time
- [x] Filter CREATE events to top-level root windows (`GetAncestor GA_ROOT`, unowned)
- [x] Log CREATE→SHOW/UNCLOAK delta in `WS_OnWinEvent` (ms + µs)
- [x] Log CREATE→ShellHook delta in `WS_OnShellHook` CREATED handler
- [x] Add 2s TTL cleanup timer for stale `WS_CreateTiming` entries
- [x] Add `WS_EventHookCreate` cleanup in `WS_Cleanup()`
- [x] **TEST:** Explorer shows CREATE→SHELL=55-77ms, CREATE→SHOW=119-156ms
- [x] **EVALUATE:** CREATE fires 55-77ms before shell hook — validates pipeline approach

### Stage B: CREATE → SHOW Pipeline with Early Positioning
- [x] Merge `WS_CreateTiming` into `WS_PrePending` (carries mon + tick + qpc)
- [x] Pre-register target monitor at CREATE time in `WS_PrePending`
- [x] Early `SetWindowPos` at CREATE time (position on target monitor before visibility)
- [x] Shell hook consumes `WS_PrePending` — uses pre-registered target for precise move
- [x] SHOW handler checks `WS_PrePending` as fallback (shell hook missed)
- [x] Shell hook fallback path preserved for non-CREATE-hooked windows
- [x] `WS_PrePending` cleanup on DESTROYED + 2s TTL timer
- [x] **TEST:** Explorer shows "OK (pre-pos verified)" on all 4 monitors — pre-positioning works
- [x] **EVALUATE:** Flash eliminated for Explorer/VS Code/Sublime (CREATE fires 55-77ms before shell hook)

### Stage B Fixes (bug fixes discovered during testing)
- [x] Fix SHOW handler fall-through: `WS_Pending.Delete` + `return` moved inside success block (UWP regression)
- [x] Fix relative positioning: replaced `SetWindowPos` pre-positioning with opacity suppression (was top-left corner → top-right after bad origX/origY mapping)
- [x] Smart owner check in CREATE handler: skip only if owner is `WS_VISIBLE` (Run dialog fix)
- [x] Add activation guard debug logging (`activate-destroy`, `activate-minimize`, `activate-taskbar`)
- [x] **Opacity approach:** `WS_EX_LAYERED` + alpha 0/128 at CREATE time (no position change)
- [x] **WS_Reveal():** idempotent restore — called in all 7 exit paths (shell, show, process, poll, timeout, fallback, cleanup)
- [x] **WS_Hidden dict:** tracks hidden windows independently of WS_PrePending/WS_Pending
- [x] **WS_MoveToMonitor:** removed origX/origY params — window position now reliable (never pre-moved)
- [x] **WS_Cleanup:** reveals all hidden windows on exit
- [x] **Sentinel fix:** `WS_Reveal` marks `WS_Hidden[hwnd] := -1` instead of Delete; CREATE handler skips re-hiding
- [x] **CREATE guard:** `WS_Hidden.HasKey(hwnd)` check prevents duplicate CREATE events from re-hiding revealed windows
- [x] **Faster cleanup:** `WS_CleanPrePending` timer 5s→1s, stale TTL 2s→500ms; also purges sentinel `-1` entries
- [x] **Debug log fix:** only says "hide" when actually hidden (`windowMon != cursorMon`)
- [x] **WS_Cleanup:** handles sentinel `-1` values (skips reveal for already-revealed windows)
- [x] **Race condition fix:** `WS_MoveToMonitor` pre-sets sentinel before `WinMove` (prevents concurrent CREATE re-hiding)
- [x] **UWP skip:** cloaked check in CREATE handler — `DwmGetWindowAttribute(DWMWA_CLOAKED)` skips opacity for DirectComposition windows
- [x] **Numeric coercion:** `hwnd := hwnd + 0` in `WS_Reveal` for consistent key lookup
- [x] **Inline reveal:** `WS_MoveToMonitor` restores opacity after move (external `WS_Reveal` calls become no-op safety nets)
- [x] **Universal sentinel:** `WS_MoveToMonitor` always sets `WS_Hidden[hwnd] := -1` after move (not just when HasKey); `WS_Reveal` sets sentinel for unknown windows
- [x] **CREATE-SKIP logging:** debug log when sentinel blocks duplicate CREATE events
- [x] **Timer race fix:** removed sentinel cleanup from `WS_CleanPrePending` timer (was deleting `-1` entries every 1s, causing race with async CREATE callbacks); sentinels now cleaned only by `HSHELL_WINDOWDESTROYED`
- [x] **TEST:** Chrome ✓ (`CREATE-SKIP`), Registry Workshop ✓ (`CREATE-SKIP`), Everything ✓, Run dialog (instant path) ✓ (`CREATE-SKIP`), Run dialog (create-shell path) ✗ partial — see remaining issue below
- [ ] **EVALUATE:** Flash eliminated for most apps. Run dialog fix (owner-based sentinel) needs testing.

### Stage B Remaining Issue: Run Dialog Create-Shell Sentinel Failure

**Root cause analysis:** The "duplicate" `class=#32770` CREATE is most likely a **different window handle** (sibling dialog) created by the Win32 dialog manager during Run dialog initialization. Evidence: `WS_PrePending.HasKey(lParam + 0)` succeeds across OnMessage↔RegisterCallback boundaries, proving key types are compatible — ruling out a type mismatch.

**Fix applied:** Owner-based sentinel (`WS_OwnerSentinel`). When `WS_MoveToMonitor` processes a window, it records the window's owner hwnd with a timestamp. The CREATE handler checks if a new window's owner has a recent sentinel (<200ms) and skips hiding if so. This protects sibling `#32770` windows that share the same owner.

**Diagnostic logging added (3 locations):**
- `SENTINEL-SET` in WS_MoveToMonitor — logs hwnd hex + all WS_Hidden keys after sentinel set
- `CREATE-DIAG` in CREATE handler — logs hwnd hex + owner + HasKey for `#32770` windows
- `SHELL-DONE` in create-shell path — logs sentinel state after MoveToMonitor + Reveal

**Additional safety nets:**
- [x] **Empty-class filter:** CREATE handler skips windows with empty class name (transient Win32 objects)
- [x] **Orphan sweep:** `WS_CleanPrePending` timer reveals windows stuck in WS_Hidden that aren't tracked by PrePending/Pending
- [x] **Owner sentinel TTL:** 2s sweep in `WS_CleanPrePending`; reset in `WS_Cleanup()`

**Status:** Awaiting test. Run `WS_Debug := 1`, reproduce Win+R from non-primary monitor, check `%TEMP%\WS_Debug.log` for `CREATE-SKIP-OWNER` or `CREATE-DIAG` entries.

### Stage C: Evaluation (pending)
- [ ] Compare opacity approach vs `EVENT_OBJECT_LOCATIONCHANGE` snap-back (if needed)
- [ ] Test edge cases: already-layered windows, rapid spawn/close, multi-monitor drag

## Phase 10d: Activation Guard Regression Fix
- [x] Fix guard #4 (destroy guard): foreground-only — skip `WS_LastDestroyTick` for background/transient windows
- [x] Fix guard #2 (overlay re-activation): overlay flag + 3-band timing
  - Replaced tick-only (can't detect overlay), cursor-monitor (cursor moves freely), and flag-only (blocks UWP internal + launches) approaches
  - `WS_OverlayTick` records when non-taskbar non-movable window activates (Start menu, Action Center)
  - Excluded for `Shell_TrayWnd`/`Shell_SecondaryTrayWnd` (taskbar clicks don't fire activation)
  - Guard #2 three timing bands since overlay opened:
    - `<50ms` — UWP internal CoreWindow activation → allow (not a real overlay)
    - `50-2000ms` — quick overlay dismiss (Win key, Start menu close) → block (bounce-back)
    - `>2000ms` — user launched from overlay (Start menu search/click) → allow (intentional)
  - Debug logging: `OVERLAY` when flag set, `SKIP (overlay-bounce)` when guard blocks
- [x] Fix guard #1 (overlay detection): source filtering for `WS_OverlayTick`
  - Root cause: UWP activation fires 3 `HSHELL_WINDOWACTIVATED` events in sequence:
    1. Empty-class infrastructure window (hwnd=592370) — ~1s before app frame
    2. UWP app's `Windows.UI.Core.CoreWindow` (hwnd=328388) — ~100ms before app frame
    3. `ApplicationFrameWindow` (the actual app) — movable, goes through guard #2
  - All three were setting `WS_OverlayTick`, so #3 always fell in the 50-2000ms "block" band
  - Fix v1 (PID check — FAILED): `_nmPID == _fgPID` to detect same-process CoreWindow.
    Broken because UWP uses split-process: ApplicationFrameHost.exe owns the frame,
    app.exe (e.g. SystemSettings.exe) owns the CoreWindow → PIDs always differ.
  - Fix v2 (explorer.exe check — PARTIAL): Only `explorer.exe` CoreWindows classified as overlay.
    UWP re-activation now works ✓ but Start menu bounce-back is broken ✗.
    Start menu's CoreWindow apparently does NOT fire `HSHELL_WINDOWACTIVATED`.
  - Empty-class windows (`_nmClass == ""`) → skip entirely (transient infrastructure)
- [x] UWP re-activation test: Settings moves from different monitor ✓ (with explorer.exe check)
- [x] **FIX:** Start menu open/close overlay detection — activation-based approach (Jan 30, 2026)
  - Root cause: Start menu CoreWindow does NOT fire `HSHELL_WINDOWACTIVATED`
  - Iteration 6 (`GetKeyState("LWin", "P")`) failed: doesn't work in shell hook `OnMessage` context
  - Iteration 7 (`~LWin Up::` hotkey only) failed: sets tick on key RELEASE, UWP cascade fires on key DOWN
  - **Iteration 8 (activation-based):** Empty-class infrastructure windows (class="") fire before every activation.
    Guard #1 now sets `WS_OverlayTick` on these events instead of skipping them.
    Guard #2's `lParam == WS_LastForegroundHwnd` check prevents false positives for different-window switches.
    Removed <50ms timing exception (empty-class→re-activation fires at 0ms delta).
  - Complementary signals: taskbar activation, explorer.exe/StartMenuExperienceHost.exe CoreWindow
  - Guard #1b (`GetKeyState`) removed as non-functional
  - Guard #2 simplified from 3-band to 2-band timing: 0-2000ms=block, >2000ms=allow
- [x] **Iteration 9:** Replace `~LWin Up::` with direct Start menu detection (Jan 31, 2026)
  - `~LWin Up::` removed: caused delays for Win+key hotkeys, didn't catch mouse Start clicks
  - Guard #1: added `StartMenuExperienceHost.exe` to CoreWindow overlay sources (free, if shell hooks fire)
  - Guard #2 Check B: direct `WinExist` + `DwmGetWindowAttribute(DWMWA_CLOAKED)` on `StartMenuExperienceHost.exe`
  - Causality guarantee: Start menu must be visible when bounce-back fires (it caused the activation)
- [ ] Test Start menu fix: keyboard Win key, mouse Start button, Win+combo pass-through
- [ ] Test taskbar overlay tick safety: clicking different app via taskbar should still move
- [ ] Test normal window switching: empty-class overlay tick should NOT block different-window activations
- [ ] Test Win+key hotkey latency: Win+E, Win+R, Win+T should have no delay

## Phase 10d-2: Minimized Window Move Fix
- [x] Fix `WS_MoveToMonitor` for `minMax == -1` — `GetWindowPlacement` for real dimensions (Jan 30, 2026)
  - `WinGetPos` on minimized windows returns ~160×28 at -32000,-32000
  - `GetWindowPlacement.rcNormalPosition` always returns correct restored size
  - Window restored, then moved with correct dimensions, centered on target monitor
- [x] Add `MOVE-START` debug logging with dimensions and minMax state
- [ ] Test minimized window move: Alt+Tab to minimized app on different monitor

## Remaining / Future
- [ ] Test Run dialog create-shell fix (owner-based sentinel) — look for `CREATE-SKIP-OWNER`
- [ ] Remove diagnostic logging after confirming all fixes (keep `CREATE-SKIP-OWNER` as standard log)
- [ ] Test across apps: Sublime Text, Explorer, VS Code, Terminal, UWP Settings, dialogs
- [ ] Evaluate if any additional classes need exclusion based on testing
- [ ] Consider per-app exclusion list if certain apps fight the move
- [ ] Consider `TaskbarCreated` message handler to re-register hook after explorer.exe restart
