; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === SPAWN WINDOWS ON CURRENT MONITOR === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; Intercepts new window creation and moves windows to the cursor's monitor.
; Uses shell hooks (creation/activation) and WinEvent hooks (SHOW/UNCLOAK/CREATE)
; for instant, event-driven detection.
;
; Activation moves use positive intent detection:
;   Tier 1 — Brief-process detection (Win32 single-instance app re-launch)
;   Tier 2 — Overlay-launch detection (UWP apps via Start menu / Action Center)
;   Tier 3 — Alt+Tab detection (ExplorerPatcher MultitaskingViewFrame dismissed)

WS_Init() {
  global WS, Debug
  WS := {}
  WS.LastForegroundHwnd := 0
  WS.OverlayTick := 0              ; A_TickCount when non-movable overlay activated
  WS.AltTabTick := 0               ; A_TickCount when MultitaskingViewFrame (EP Alt+Tab) dismissed
  WS.AltTabHwnd := 0               ; hwnd of active MultitaskingViewFrame (EP Alt+Tab switcher)
  WS.ZOrderFallbackTick := 0       ; A_TickCount when foreground destroyed (z-order fallback imminent)
  WS.RecentExes := {}              ; Tier 1: exe name -> A_TickCount (brief process detected)
  WS.Pending := {}                 ; Deferred windows: hwnd -> {mon, tick}
  WS.PendingAltTab := ""           ; Alt+Tab: {mon, tick} or ""
  WS.PrePending := {}              ; CREATE pre-registration: hwnd -> {mon, tick, qpc}
  WS.Hidden := {}                  ; Opacity-hidden windows: hwnd -> hadLayered (bool/-1 sentinel)
  WS.OwnerSentinel := {}           ; Owner hwnd -> A_TickCount (sibling CREATE suppression)
  WS.LastMoved := {}                ; hwnd -> A_TickCount (WMI-foreground re-move suppression)
  WS.ExcludedClasses := ["tooltips_class32", "NotifyIconOverflowWindow"
    , "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "Progman", "WorkerW"
    , "MultitaskingViewFrame", "Windows.UI.Core.CoreWindow", "ForegroundStaging"
    , "RAIL_WINDOW"]
  DllCall("QueryPerformanceFrequency", "Int64*", _qpcFreq)
  WS.QPCFreq := _qpcFreq

  ; Shell hook for window creation/activation/destruction detection
  Gui, ShellHook:+LastFound
  Gui, ShellHook:Show, Hide
  WS.HookHwnd := WinExist()
  _hookOK := DllCall("RegisterShellHookWindow", "Ptr", WS.HookHwnd)
  _hookMsg := DllCall("RegisterWindowMessage", "Str", "SHELLHOOK")
  if (_hookOK && _hookMsg > 0)
    OnMessage(_hookMsg, "WS_OnShellHook")
  else
    FileAppend, % TS() " | window-spawning | " "ERROR: Shell hook failed — Hook=" . _hookOK . " Msg=" . _hookMsg . "`n", % Debug.Log.Path

  ; WinEvent hooks for instant visibility/uncloak/create detection
  DllCall("ole32\CoInitialize", "Ptr", 0)
  WS.WinEventCB := RegisterCallback("WS_OnWinEvent", "", 7)
  WS.EventHookShow := DllCall("SetWinEventHook"
    , "UInt", 0x8002, "UInt", 0x8002   ; EVENT_OBJECT_SHOW
    , "Ptr", 0, "Ptr", WS.WinEventCB
    , "UInt", 0, "UInt", 0, "UInt", 0x0002, "Ptr")  ; WINEVENT_OUTOFCONTEXT
  WS.EventHookUncloak := DllCall("SetWinEventHook"
    , "UInt", 0x8018, "UInt", 0x8018   ; EVENT_OBJECT_UNCLOAKED
    , "Ptr", 0, "Ptr", WS.WinEventCB
    , "UInt", 0, "UInt", 0, "UInt", 0x0002, "Ptr")  ; WINEVENT_OUTOFCONTEXT
  WS.EventHookCreate := DllCall("SetWinEventHook"
    , "UInt", 0x8000, "UInt", 0x8000   ; EVENT_OBJECT_CREATE
    , "Ptr", 0, "Ptr", WS.WinEventCB
    , "UInt", 0, "UInt", 0, "UInt", 0x0002, "Ptr")  ; WINEVENT_OUTOFCONTEXT
  if (Debug.Log["window-spawning"])
    FileAppend, % TS() " | window-spawning | " "INIT: SHOW=" . (WS.EventHookShow ? "OK" : "FAIL")
      . " UNCLOAK=" . (WS.EventHookUncloak ? "OK" : "FAIL")
      . " CREATE=" . (WS.EventHookCreate ? "OK" : "FAIL") . "`n", % Debug.Log.Path
  ; WMI process start monitoring — detects launches from any source (Run dialog, shortcuts, etc.)
  ; Uses semi-sync ExecNotificationQuery + timer poll (async SWbemSink unreliable in AHK STA)
  Try {
    _locator := ComObjCreate("WbemScripting.SWbemLocator")
    WS.WMIService := _locator.ConnectServer(".", "root\cimv2")
    WS.WMIService.Security_.ImpersonationLevel := 3  ; wbemImpersonationLevelImpersonate
    WS.WMIEvents := WS.WMIService.ExecNotificationQuery("SELECT * FROM Win32_ProcessStartTrace")
    SetTimer, WS_WMIPoll, 50
    if (Debug.Log["window-spawning"])
      FileAppend, % TS() " | window-spawning | INIT: WMI=OK (polling)`n", % Debug.Log.Path
  } catch _e {
    if (Debug.Log["window-spawning"])
      FileAppend, % TS() " | window-spawning | INIT: WMI=FAIL err=" . _e.Message . "`n", % Debug.Log.Path
  }

  SetTimer, WS_SweepTracking, 1000
  OnExit("WS_Cleanup")
}

WS_OnShellHook(wParam, lParam, msg, hwnd) {
  global WS
  ; HSHELL_WINDOWCREATED=1, HSHELL_WINDOWACTIVATED=4, HSHELL_RUDEAPPACTIVATED=0x8004
  isCreated := (wParam == 1)
  isActivated := (wParam == 4 || wParam == 0x8004)
  isDestroyed := (wParam == 2)
  if (!isCreated && !isActivated && !isDestroyed)
    return
  Critical
  SetWinDelay, -1

  ; --- Destruction: clean up tracking, detect brief processes (Tier 1) ---
  if (isDestroyed) {
    ; Tier 3 — ExplorerPatcher Alt+Tab: MultitaskingViewFrame dismissed → next activation is intentional
    if (WS.AltTabHwnd && lParam == WS.AltTabHwnd) {
      WS.AltTabHwnd := 0
      WS.AltTabTick := A_TickCount
      if (Debug.Log["window-spawning"])
        FileAppend, % TS() " | window-spawning | " "ALTTAB-DISMISS: hwnd=" . lParam . "`n", % Debug.Log.Path
    }
    ; Clear intent signals when foreground window closes — prevents false positives
    ; on the subsequent Z-order fallback activation.
    if (lParam == WS.LastForegroundHwnd) {
      WS.OverlayTick := 0
      WS.ZOrderFallbackTick := A_TickCount
    }
    WS.Pending.Delete(lParam + 0)
    WS.PrePending.Delete(lParam + 0)
    WS.Hidden.Delete(lParam + 0)
    return
  }

  cursorMon := GetCursorMonitor()

  ; --- Activation path: positive intent detection ---
  if (isActivated) {
    if (!WS_IsMovable(lParam)) {
      ; Non-movable windows: record overlay timestamps for Tier 2/3 detection
      WinGetClass, _nmClass, ahk_id %lParam%
      if (_nmClass == "") {
        WS.OverlayTick := A_TickCount
        if (Debug.Log["window-spawning"]) {
          WinGet, _nmExe, ProcessName, ahk_id %lParam%
          FileAppend, % TS() " | window-spawning | " "OVERLAY (infra): hwnd=" . lParam . " exe=" . _nmExe . "`n", % Debug.Log.Path
        }
        return
      }
      if (_nmClass == "Shell_TrayWnd" || _nmClass == "Shell_SecondaryTrayWnd") {
        WS.OverlayTick := A_TickCount
        if (Debug.Log["window-spawning"])
          FileAppend, % TS() " | window-spawning | " "OVERLAY (taskbar): hwnd=" . lParam . "`n", % Debug.Log.Path
        return
      }
      ; Tier 3 — ExplorerPatcher Alt+Tab: track switcher hwnd for destruction detection
      if (_nmClass == "MultitaskingViewFrame") {
        WS.AltTabHwnd := lParam + 0
        if (Debug.Log["window-spawning"])
          FileAppend, % TS() " | window-spawning | " "ALTTAB-OPEN: hwnd=" . lParam . "`n", % Debug.Log.Path
        return
      }
      if (_nmClass == "Windows.UI.Core.CoreWindow") {
        WinGet, _nmExe, ProcessName, ahk_id %lParam%
        if (_nmExe != "explorer.exe" && _nmExe != "StartMenuExperienceHost.exe")
          return
      }
      WS.OverlayTick := A_TickCount
      if (Debug.Log["window-spawning"]) {
        WinGet, _nmExe, ProcessName, ahk_id %lParam%
        FileAppend, % TS() " | window-spawning | " "OVERLAY: class=" . _nmClass . " exe=" . _nmExe . " hwnd=" . lParam . "`n", % Debug.Log.Path
      }
      return
    }

    ; Z-order fallback guard: if foreground was just destroyed, this activation
    ; is Windows selecting the next window in z-order, not user intent.
    if (WS.ZOrderFallbackTick && (A_TickCount - WS.ZOrderFallbackTick) < 200) {
      WS.ZOrderFallbackTick := 0
      if (Debug.Log["window-spawning"])
        FileAppend, % TS() " | window-spawning | " "SKIP (z-order-fallback): hwnd=" . lParam . "`n", % Debug.Log.Path
      return
    }
    WS.ZOrderFallbackTick := 0
    prevHwnd := WS.LastForegroundHwnd
    WS.LastForegroundHwnd := lParam
    ; Clear overlay tick if previous window was minimized (Z-order fallback, not user launch)
    if (prevHwnd) {
      WinGet, _prevMinMax, MinMax, ahk_id %prevHwnd%
      if (_prevMinMax == -1)
        WS.OverlayTick := 0
    }
    WinGet, _actExe, ProcessName, ahk_id %lParam%
    _hasIntent := false

    ; Tier 1: Brief process of same exe name (Win32 single-instance re-launch)
    if (WS.RecentExes.HasKey(_actExe)) {
      _intentAge := A_TickCount - WS.RecentExes[_actExe]
      if (_intentAge < 5000) {
        _hasIntent := true
        WS.RecentExes.Delete(_actExe)
        if (Debug.Log["window-spawning"])
          FileAppend, % TS() " | window-spawning | " "INTENT (brief-process): exe=" . _actExe . " age=" . _intentAge . "ms" . "`n", % Debug.Log.Path
      }
    }

    ; Tier 2: Overlay launch (Start menu, Action Center → different window activated)
    if (!_hasIntent && WS.OverlayTick) {
      _overlayAge := A_TickCount - WS.OverlayTick
      if (_overlayAge < 2000 && lParam != prevHwnd) {
        _hasIntent := true
        if (Debug.Log["window-spawning"])
          FileAppend, % TS() " | window-spawning | " "INTENT (overlay-launch): exe=" . _actExe . " overlay=" . _overlayAge . "ms ago" . "`n", % Debug.Log.Path
      }
    }
    WS.OverlayTick := 0

    ; Tier 3: ExplorerPatcher Alt+Tab (MultitaskingViewFrame dismissed → first activation is the chosen window)
    ; Guard: lParam != prevHwnd ensures Escape (re-activating the same window) doesn't trigger a move.
    if (!_hasIntent && WS.AltTabTick) {
      _altTabAge := A_TickCount - WS.AltTabTick
      WS.AltTabTick := 0
      if (_altTabAge < 2000 && lParam != prevHwnd) {
        _hasIntent := true
        if (Debug.Log["window-spawning"])
          FileAppend, % TS() " | window-spawning | " "INTENT (alttab-launch): exe=" . _actExe . " alttab=" . _altTabAge . "ms ago" . "`n", % Debug.Log.Path
      }
    }

    if (!_hasIntent) {
      if (Debug.Log["window-spawning"]) {
        WinGetTitle, _dbgTitle, ahk_id %lParam%
        FileAppend, % TS() " | window-spawning | " "SKIP (no-intent): """ . _dbgTitle . """ exe=" . _actExe . "`n", % Debug.Log.Path
      }
      return
    }

    ; Taskbar click guard: clicking a taskbar button is not a launch
    MouseGetPos,,, _mouseWin
    WinGetClass, _mouseClass, ahk_id %_mouseWin%
    if (_mouseClass == "Shell_TrayWnd" || _mouseClass == "Shell_SecondaryTrayWnd") {
      if (Debug.Log["window-spawning"]) {
        WinGetTitle, _dbgTitle, ahk_id %lParam%
        FileAppend, % TS() " | window-spawning | " "SKIP (taskbar-click): """ . _dbgTitle . """" . "`n", % Debug.Log.Path
      }
      return
    }

    windowMon := GetMonitor("ahk_id " . lParam)
    if (windowMon == cursorMon)
      return
    WS_MoveToMonitor(lParam, windowMon, cursorMon)
    if (Debug.Log["window-spawning"]) {
      WinGetTitle, _dbgTitle, ahk_id %lParam%
      FileAppend, % TS() " | window-spawning | " "MOVED (activate): """ . _dbgTitle . """ mon " . windowMon . " -> " . cursorMon . "`n", % Debug.Log.Path
    }
    return
  }

  ; --- Creation path: new window ---

  ; Skip if already processed (duplicate HSHELL_WINDOWCREATED for same hwnd)
  ; Only suppress within 5s — long-lived single-instance apps reuse the same hwnd on re-launch
  if (WS.Hidden.HasKey(lParam + 0) && WS.Hidden[lParam + 0] == -1
      && WS.Pending.HasKey(lParam + 0)) {
    if (Debug.Log["window-spawning"]) {
      WinGetTitle, _dbgTitle, ahk_id %lParam%
      FileAppend, % TS() " | window-spawning | " "SKIP (already-handled): """ . _dbgTitle . """ hwnd=" . lParam . "`n", % Debug.Log.Path
    }
    return
  }

  ; Use pre-registered target from CREATE event if available
  if (WS.PrePending.HasKey(lParam + 0)) {
    ppEntry := WS.PrePending.Delete(lParam + 0)
    if (Debug.Log["window-spawning"]) {
      ctDeltaUs := Round((WS_QPC() - ppEntry.qpc) * 1000000 / WS.QPCFreq)
      FileAppend, % TS() " | window-spawning | " "SHELL: hwnd=" . lParam . " create-to-shell=" . ctDeltaUs . "µs" . "`n", % Debug.Log.Path
    }
    targetMon := ppEntry.mon
    if (WS_IsReady(lParam)) {
      if (WS_IsMovable(lParam)) {
        windowMon := GetMonitor("ahk_id " . lParam)
        if (windowMon != targetMon) {
          WS_MoveToMonitor(lParam, windowMon, targetMon)
          if (Debug.Log["window-spawning"]) {
            WinGetTitle, _dbgTitle, ahk_id %lParam%
            FileAppend, % TS() " | window-spawning | " "MOVED (create-shell): """ . _dbgTitle . """ mon " . windowMon . " -> " . targetMon . " +" . (A_TickCount - ppEntry.tick) . "ms" . "`n", % Debug.Log.Path
          }
        } else if (Debug.Log["window-spawning"]) {
          WinGetTitle, _dbgTitle, ahk_id %lParam%
          FileAppend, % TS() " | window-spawning | " "OK (create-shell): """ . _dbgTitle . """ already on mon " . windowMon . "`n", % Debug.Log.Path
        }
        WS_Reveal(lParam)
        return
      }
      WinGetTitle, _chkTitle, ahk_id %lParam%
      if (_chkTitle != "") {
        WS_Reveal(lParam)
        return
      }
    }
    ; Not ready — defer with pre-registered target
    WS.Pending[lParam + 0] := {mon: targetMon, tick: ppEntry.tick}
    _fn := Func("WS_BackupPoll").Bind(lParam + 0, 1)
    SetTimer, %_fn%, -100
    _fn2 := Func("WS_TimeoutPending").Bind(lParam + 0)
    SetTimer, %_fn2%, -2000
    if (Debug.Log["window-spawning"]) {
      WinGetTitle, _dbgTitle, ahk_id %lParam%
      WinGetClass, _dbgClass, ahk_id %lParam%
      FileAppend, % TS() " | window-spawning | " "DEFERRED (create-path): hwnd=" . lParam . " """ . _dbgTitle . """ class=" . _dbgClass . "`n", % Debug.Log.Path
    }
    return
  }

  ; Fallback: no CREATE pre-registration (window missed by CREATE hook)
  if (WS_IsReady(lParam)) {
    if (WS_IsMovable(lParam)) {
      windowMon := GetMonitor("ahk_id " . lParam)
      if (windowMon != cursorMon) {
        WS_MoveToMonitor(lParam, windowMon, cursorMon)
        if (Debug.Log["window-spawning"]) {
          WinGetTitle, _dbgTitle, ahk_id %lParam%
          FileAppend, % TS() " | window-spawning | " "MOVED (instant): """ . _dbgTitle . """ mon " . windowMon . " -> " . cursorMon . "`n", % Debug.Log.Path
        }
      } else if (Debug.Log["window-spawning"]) {
        WinGetTitle, _dbgTitle, ahk_id %lParam%
        FileAppend, % TS() " | window-spawning | " "OK (instant): """ . _dbgTitle . """ already on mon " . windowMon . "`n", % Debug.Log.Path
      }
      WS_Reveal(lParam)
      return
    }
    WinGetTitle, _chkTitle, ahk_id %lParam%
    if (_chkTitle != "") {
      WS_Reveal(lParam)
      return
    }
  }
  WS.Pending[lParam + 0] := {mon: cursorMon, tick: A_TickCount}
  _fn := Func("WS_BackupPoll").Bind(lParam + 0, 1)
  SetTimer, %_fn%, -100
  _fn2 := Func("WS_TimeoutPending").Bind(lParam + 0)
  SetTimer, %_fn2%, -2000
  if (Debug.Log["window-spawning"]) {
    WinGetTitle, _dbgTitle, ahk_id %lParam%
    WinGetClass, _dbgClass, ahk_id %lParam%
    FileAppend, % TS() " | window-spawning | " "DEFERRED: hwnd=" . lParam . " """ . _dbgTitle . """ class=" . _dbgClass . "`n", % Debug.Log.Path
  }
}

; WinEvent callback — fires for CREATE, SHOW, UNCLOAK events
WS_OnWinEvent(hHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) {
  global WS
  ; Mask 32-bit params (upper bits may contain junk on x64)
  idObject := idObject & 0xFFFFFFFF
  idChild := idChild & 0xFFFFFFFF
  if (idObject != 0 || idChild != 0 || !hwnd)  ; OBJID_WINDOW = 0
    return
  Critical
  SetWinDelay, -1
  hwnd := hwnd + 0  ; Ensure numeric type for consistent object key lookup

  ; --- Start menu: move to cursor monitor on UNCLOAK ---
  if (event == 0x8018) {
    WinGetClass, _evClass, ahk_id %hwnd%
    if (_evClass == "Windows.UI.Core.CoreWindow") {
      WinGet, _evExe, ProcessName, ahk_id %hwnd%
      if (_evExe == "StartMenuExperienceHost.exe" || _evExe == "SearchHost.exe") {
        WS.OverlayTick := A_TickCount
        cursorMon := GetCursorMonitor()
        windowMon := GetMonitor("ahk_id " . hwnd)
        if (windowMon != cursorMon) {
          WS_MoveToMonitor(hwnd, windowMon, cursorMon)
          if (Debug.Log["window-spawning"])
            FileAppend, % TS() " | window-spawning | " "MOVED (start-menu): mon " . windowMon . " -> " . cursorMon . " exe=" . _evExe . "`n", % Debug.Log.Path
        }
        return
      }
    }
  }

  ; --- CREATE: pre-register + hide for zero-flash move ---
  if (event == 0x8000) {
    if (DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != hwnd)  ; GA_ROOT=2
      return
    WinGetClass, _createClass, ahk_id %hwnd%
    if (_createClass == "")
      return
    if (WS.Hidden.HasKey(hwnd))
      return
    ; Owner sentinel — skip if owner was recently moved (sibling protection)
    _ppOwner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")  ; GW_OWNER=4
    if (_ppOwner && WS.OwnerSentinel.HasKey(_ppOwner + 0)) {
      if (A_TickCount - WS.OwnerSentinel[_ppOwner + 0] < 200) {
        WS.Hidden[hwnd] := -1
        if (Debug.Log["window-spawning"]) {
          WinGetClass, _dbgClass, ahk_id %hwnd%
          FileAppend, % TS() " | window-spawning | " "CREATE-SKIP-OWNER: hwnd=" . hwnd . " class=" . _dbgClass
            . " owner=" . Format("0x{:08X}", _ppOwner) . "`n", % Debug.Log.Path
        }
        return
      }
    }
    if (_ppOwner) {
      if (WS.Hidden.HasKey(_ppOwner + 0) && WS.Hidden[_ppOwner + 0] == -1)
        return
      WinGet, _ppOwnerStyle, Style, ahk_id %_ppOwner%
      if (_ppOwnerStyle & 0x10000000)  ; Owner is WS_VISIBLE → real dialog, skip
        return
    }
    ; Hide FIRST — minimize latency before next VSYNC paints the window
    _ppExStyle := DllCall("GetWindowLong", "Ptr", hwnd, "Int", -20)  ; GWL_EXSTYLE
    _hadLayered := !!(_ppExStyle & 0x80000)  ; WS_EX_LAYERED
    if (!_hadLayered)
      DllCall("SetWindowLong", "Ptr", hwnd, "Int", -20, "Ptr", _ppExStyle | 0x80000)  ; +WS_EX_LAYERED
    DllCall("SetLayeredWindowAttributes", "Ptr", hwnd, "UInt", 0
      , "UChar", Debug.Log["window-spawning"] ? 128 : 0, "UInt", 0x2)  ; LWA_ALPHA
    WS.Hidden[hwnd] := _hadLayered
    ; Now capture cursor/monitor (safe to do after hide)
    cursorMon := GetCursorMonitor()
    windowMon := GetMonitor("ahk_id " . hwnd)
    WS.PrePending[hwnd] := {mon: cursorMon, tick: A_TickCount, qpc: WS_QPC()}
    if (Debug.Log["window-spawning"]) {
      WinGetClass, _dbgClass, ahk_id %hwnd%
      FileAppend, % TS() " | window-spawning | " "CREATE: hwnd=" . hwnd . " class=" . _dbgClass . " hide mon " . cursorMon
        . (windowMon && windowMon != cursorMon ? " (from " . windowMon . ")" : "") . "`n", % Debug.Log.Path
    }
    return
  }

  ; --- PrePending SHOW/UNCLOAK fast path ---
  if (WS.PrePending.HasKey(hwnd)) {
    ppEntry := WS.PrePending.Delete(hwnd)
    if (Debug.Log["window-spawning"]) {
      _evName := (event == 0x8002) ? "SHOW" : "UNCLOAK"
      WinGetTitle, _dbgTitle, ahk_id %hwnd%
      WinGetClass, _dbgClass, ahk_id %hwnd%
      _deltaUs := Round((WS_QPC() - ppEntry.qpc) * 1000000 / WS.QPCFreq)
      FileAppend, % TS() " | window-spawning | " _evName . ": hwnd=" . hwnd . " """ . _dbgTitle . """ class=" . _dbgClass
        . " create-to-" . _evName . "=" . (A_TickCount - ppEntry.tick) . "ms (" . _deltaUs . "µs)" . "`n", % Debug.Log.Path
    }
    if (WS_IsReady(hwnd) && WS_IsMovable(hwnd)) {
      windowMon := GetMonitor("ahk_id " . hwnd)
      if (windowMon != ppEntry.mon) {
        WS_MoveToMonitor(hwnd, windowMon, ppEntry.mon)
        if (Debug.Log["window-spawning"]) {
          WinGetTitle, _dbgTitle, ahk_id %hwnd%
          FileAppend, % TS() " | window-spawning | " "MOVED (create-show): """ . _dbgTitle . """ mon " . windowMon . " -> " . ppEntry.mon . " +" . (A_TickCount - ppEntry.tick) . "ms" . "`n", % Debug.Log.Path
        }
      } else if (Debug.Log["window-spawning"]) {
        WinGetTitle, _dbgTitle, ahk_id %hwnd%
        FileAppend, % TS() " | window-spawning | " "OK (create-show): """ . _dbgTitle . """ already on mon " . windowMon . "`n", % Debug.Log.Path
      }
      WS_Reveal(hwnd)
      WS.Pending.Delete(hwnd)
      return
    }
  }

  ; --- Pending creation moves ---
  if (WS.Pending.HasKey(hwnd)) {
    if (WS_IsReady(hwnd)) {
      if (WS_IsMovable(hwnd)) {
        entry := WS.Pending.Delete(hwnd)
        _evName := (event == 0x8002) ? "show" : "uncloak"
        WS_ProcessPending(hwnd, entry.mon, _evName, entry.tick)
      } else {
        WinGetTitle, _chkTitle, ahk_id %hwnd%
        if (_chkTitle != "")
          WS.Pending.Delete(hwnd)
      }
    }
    return
  }

  ; --- Pending Alt+Tab ---
  if (WS.PendingAltTab != "") {
    WinGetClass, _cls, ahk_id %hwnd%
    if (_cls == "XamlExplorerHostIslandWindow") {
      entry := WS.PendingAltTab
      WS.PendingAltTab := ""
      windowMon := GetMonitor("ahk_id " . hwnd)
      if (windowMon != entry.mon)
        WS_MoveToMonitor(hwnd, windowMon, entry.mon)
    }
  }
}

; Process a deferred window that is now ready
WS_ProcessPending(hwnd, targetMon, source:="event", tick:=0) {
  global WS
  if (!WS_IsMovable(hwnd)) {
    WS_Reveal(hwnd)
    return
  }
  windowMon := GetMonitor("ahk_id " . hwnd)
  if (windowMon != targetMon) {
    WS_MoveToMonitor(hwnd, windowMon, targetMon)
    if (Debug.Log["window-spawning"]) {
      _elapsed := tick ? A_TickCount - tick : 0
      WinGetTitle, _dbgTitle, ahk_id %hwnd%
      FileAppend, % TS() " | window-spawning | " "MOVED (" . source . "): """ . _dbgTitle . """ mon " . windowMon . " -> " . targetMon . " +" . _elapsed . "ms" . "`n", % Debug.Log.Path
    }
  }
  WS_Reveal(hwnd)
}

; Escalating backup poll — catches windows where WinEvent didn't fire (e.g. elevated processes)
; Polls at ~100, 300, 600, 1000ms cumulative; 2s timeout remains as safety net
WS_BackupPoll(hwnd, attempt:=1) {
  global WS
  if (!WS.Pending.HasKey(hwnd))
    return
  SetWinDelay, -1
  if (WS_IsReady(hwnd)) {
    if (WS_IsMovable(hwnd)) {
      entry := WS.Pending.Delete(hwnd)
      WS_ProcessPending(hwnd, entry.mon, "poll", entry.tick)
      return
    }
    WinGetTitle, _chkTitle, ahk_id %hwnd%
    if (_chkTitle != "") {
      WS.Pending.Delete(hwnd)
      WS_Reveal(hwnd)
      return
    }
  }
  if (attempt < 4) {
    _delay := attempt == 1 ? 200 : attempt == 2 ? 300 : 400
    _fn := Func("WS_BackupPoll").Bind(hwnd, attempt + 1)
    SetTimer, %_fn%, % -_delay
  }
}

; 2s safety net — last-ditch attempt, then discard
WS_TimeoutPending(hwnd) {
  global WS
  if (!WS.Pending.HasKey(hwnd))
    return
  entry := WS.Pending.Delete(hwnd)
  SetWinDelay, -1
  if (WS_IsReady(hwnd))
    WS_ProcessPending(hwnd, entry.mon, "timeout", entry.tick)
  else
    WS_Reveal(hwnd)
}

; Periodic cleanup of stale entries
WS_SweepTracking:
  _now := A_TickCount

  ; Stale PrePending (windows created but never shown)
  _staleKeys := []
  for _h, _entry in WS.PrePending {
    if (_now - _entry.tick > 500)
      _staleKeys.Push(_h)
  }
  for _i, _k in _staleKeys {
    WS.PrePending.Delete(_k)
    WS_Reveal(_k)
  }

  ; Stale owner sentinels
  _staleKeys := []
  for _h, _tick in WS.OwnerSentinel {
    if (_now - _tick > 2000)
      _staleKeys.Push(_h)
  }
  for _i, _k in _staleKeys
    WS.OwnerSentinel.Delete(_k)

  ; Orphan sweep: reveal windows stuck in Hidden that aren't tracked
  _staleKeys := []
  for _h, _val in WS.Hidden {
    if (_val == -1) {
      if (!WS.PrePending.HasKey(_h) && !WS.Pending.HasKey(_h))
        _staleKeys.Push(_h)
      continue
    }
    if (!WinExist("ahk_id " . _h)) {
      _staleKeys.Push(_h)
      continue
    }
    if (!WS.PrePending.HasKey(_h) && !WS.Pending.HasKey(_h)) {
      _staleKeys.Push(_h)
      if (Debug.Log["window-spawning"])
        FileAppend, % TS() " | window-spawning | " "ORPHAN-REVEAL: hwnd=" . _h . "`n", % Debug.Log.Path
      DllCall("SetLayeredWindowAttributes", "Ptr", _h, "UInt", 0, "UChar", 255, "UInt", 0x2)
      if (!_val)
        WinSet, ExStyle, -0x80000, ahk_id %_h%  ; -WS_EX_LAYERED (restore)
    }
  }
  for _i, _k in _staleKeys
    WS.Hidden.Delete(_k)

  ; Stale recent-exe intent signals (>10s)
  _staleKeys := []
  for _exe, _tick in WS.RecentExes {
    if (_now - _tick > 10000)
      _staleKeys.Push(_exe)
  }
  for _i, _k in _staleKeys
    WS.RecentExes.Delete(_k)

  ; Stale move-cooldown entries (>5s)
  _staleKeys := []
  for _h, _tick in WS.LastMoved {
    if (_now - _tick > 5000)
      _staleKeys.Push(_h)
  }
  for _i, _k in _staleKeys
    WS.LastMoved.Delete(_k)

return

WS_IsReady(hwnd) {
  if !WinExist("ahk_id " . hwnd)
    return false
  WinGet, _style, Style, ahk_id %hwnd%
  if !(_style & 0x10000000)  ; WS_VISIBLE
    return false
  VarSetCapacity(_cloaked, 4, 0)
  DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Ptr", &_cloaked, "UInt", 4)
  if (NumGet(_cloaked, 0, "UInt"))
    return false
  WinGetPos,,, _w, _h, ahk_id %hwnd%
  if (_w <= 0 || _h <= 0)
    return false
  return true
}

WS_IsMovable(hwnd) {
  global WS
  WinGetClass, _cls, ahk_id %hwnd%
  if HasVal(WS.ExcludedClasses, _cls)
    return false
  WinGetTitle, _title, ahk_id %hwnd%
  if (_title == "" && _cls != "ApplicationFrameWindow")
    return false
  _owner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")  ; GW_OWNER=4
  if (_owner) {
    WinGet, _ownerStyle, Style, ahk_id %_owner%
    if (_ownerStyle & 0x10000000)  ; Owner is WS_VISIBLE
      return false
  }
  WinGet, _exStyle, ExStyle, ahk_id %hwnd%
  if (_exStyle & 0x80)  ; WS_EX_TOOLWINDOW
    return false
  return true
}

WS_MoveToMonitor(hwnd, srcMon, tgtMon) {
  global WS
  hwnd := hwnd + 0
  WS.LastMoved[hwnd] := A_TickCount
  if !WinExist("ahk_id " . hwnd) {
    WS.Hidden.Delete(hwnd)
    return
  }
  ; Pre-set sentinel BEFORE WinMove (prevents race with synchronous CREATE callbacks)
  _wasHidden := false
  _hadLayered := 0
  if (WS.Hidden.HasKey(hwnd)) {
    _hadLayered := WS.Hidden[hwnd]
    if (_hadLayered != -1)
      _wasHidden := true
  }
  WS.Hidden[hwnd] := -1

  ; Owner sentinel — protect sibling windows from re-hiding
  _moveOwner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")  ; GW_OWNER=4
  if (_moveOwner)
    WS.OwnerSentinel[_moveOwner + 0] := A_TickCount

  ; Get work areas (taskbar-aware) for both monitors
  SysGet, src, MonitorWorkArea, %srcMon%
  SysGet, tgt, MonitorWorkArea, %tgtMon%
  srcW := srcRight - srcLeft, srcH := srcBottom - srcTop
  tgtW := tgtRight - tgtLeft, tgtH := tgtBottom - tgtTop

  WinGetPos, winX, winY, winW, winH, ahk_id %hwnd%
  WinGet, _minMax, MinMax, ahk_id %hwnd%

  if (_minMax == -1) {
    ; Minimized: use GetWindowPlacement for real restored dimensions
    VarSetCapacity(_wp, 44, 0)
    NumPut(44, _wp, 0, "UInt")
    DllCall("GetWindowPlacement", "Ptr", hwnd, "Ptr", &_wp)
    winW := NumGet(_wp, 36, "Int") - NumGet(_wp, 28, "Int")
    winH := NumGet(_wp, 40, "Int") - NumGet(_wp, 32, "Int")
    if (winW > tgtW)
      winW := tgtW
    if (winH > tgtH)
      winH := tgtH
    newX := tgtLeft + (tgtW - winW) // 2
    newY := tgtTop + (tgtH - winH) // 2
    WinRestore, ahk_id %hwnd%
    WinMove, ahk_id %hwnd%,, %newX%, %newY%, %winW%, %winH%
  } else if (_minMax == 1) {
    ; Maximized: restore, move, re-maximize
    WinRestore, ahk_id %hwnd%
    _centerX := tgtLeft + (tgtW - winW) // 2
    _centerY := tgtTop + (tgtH - winH) // 2
    WinMove, ahk_id %hwnd%,, %_centerX%, %_centerY%
    WinMaximize, ahk_id %hwnd%
  } else {
    ; Normal: relative position mapping with clamping
    if (winW > tgtW)
      winW := tgtW
    if (winH > tgtH)
      winH := tgtH
    ; Titleless windows (popups/dialogs): center on cursor instead of relative mapping
    WinGetTitle, _moveTitle, ahk_id %hwnd%
    if (_moveTitle == "") {
      CoordMode, Mouse, Screen
      MouseGetPos, _mx, _my
      newX := _mx - winW // 2
      newY := _my - winH // 2
    } else {
      _relX := (winX - srcLeft) / srcW
      _relY := (winY - srcTop) / srcH
      newX := Round(tgtLeft + _relX * tgtW)
      newY := Round(tgtTop + _relY * tgtH)
    }
    if (newX < tgtLeft)
      newX := tgtLeft
    if (newY < tgtTop)
      newY := tgtTop
    if (newX + winW > tgtRight)
      newX := tgtRight - winW
    if (newY + winH > tgtBottom)
      newY := tgtBottom - winH
    WinMove, ahk_id %hwnd%,, %newX%, %newY%, %winW%, %winH%
  }

  ; Restore opacity after move
  if (_wasHidden) {
    DllCall("SetLayeredWindowAttributes", "Ptr", hwnd, "UInt", 0, "UChar", 255, "UInt", 0x2)
    if (!_hadLayered)
      WinSet, ExStyle, -0x80000, ahk_id %hwnd%
  }
}

; Restore opacity for a window hidden at CREATE time (idempotent)
WS_Reveal(hwnd) {
  global WS
  hwnd := hwnd + 0
  if (!WS.Hidden.HasKey(hwnd)) {
    WS.Hidden[hwnd] := -1
    return
  }
  _hadLayered := WS.Hidden[hwnd]
  if (_hadLayered == -1)
    return
  WS.Hidden[hwnd] := -1
  if !WinExist("ahk_id " . hwnd)
    return
  DllCall("SetLayeredWindowAttributes", "Ptr", hwnd, "UInt", 0, "UChar", 255, "UInt", 0x2)
  if (!_hadLayered)
    WinSet, ExStyle, -0x80000, ahk_id %hwnd%
}

; Alt+Tab switcher (DWM overlay — doesn't trigger shell hooks)
~!Tab::
  WS.AltTabTick := A_TickCount
  _targetMon := GetCursorMonitor()
  _hwnd := WinExist("Task Switching ahk_class XamlExplorerHostIslandWindow")
  if (_hwnd) {
    _windowMon := GetMonitor("ahk_id " . _hwnd)
    if (_windowMon != _targetMon)
      WS_MoveToMonitor(_hwnd, _windowMon, _targetMon)
  } else {
    WS.PendingAltTab := {mon: _targetMon, tick: A_TickCount}
    SetTimer, WS_TimeoutAltTab, -500
  }
Return

WS_TimeoutAltTab:
  WS.PendingAltTab := ""
Return


WS_WMIPoll:
  Critical
  if (!IsObject(WS) || !IsObject(WS.WMIEvents))
    return
  Loop {
    Try {
      _evt := WS.WMIEvents.NextEvent(0)
    } catch {
      break
    }
    if (!IsObject(_evt))
      break
    _procName := _evt.ProcessName
    if (_procName != "") {
      if (RegExMatch(_procName, "i)^(bash|sh|conhost|pwsh|powershell|cmd|git|node|npm|env|uname|hostname|which|locale|cat|grep|sed|awk|find|wc|sort|tr|head|tail|tee|xargs)\.exe$"))
        continue
      WS.RecentExes[_procName] := A_TickCount
      if (Debug.Log["window-spawning"])
        FileAppend, % TS() " | window-spawning | WMI-PROC: " . _procName . "`n", % Debug.Log.Path
      ; If foreground window is this exe and on a different monitor, move it now
      ; (no activation event fires when the window is already foreground)
      if (WS.ZOrderFallbackTick && (A_TickCount - WS.ZOrderFallbackTick) < 1000)
        continue
      _fgHwnd := WinExist("A")
      _fgKey := _fgHwnd + 0
      _lastMove := WS.LastMoved.HasKey(_fgKey) ? WS.LastMoved[_fgKey] : 0
      if (_lastMove && (A_TickCount - _lastMove) < 3000)
        continue
      WinGet, _fgExe, ProcessName, ahk_id %_fgHwnd%
      if (_fgExe = _procName) {
        SetWinDelay, -1
        _curMon := GetCursorMonitor()
        _winMon := GetMonitor("ahk_id " . _fgHwnd)
        if (_curMon != _winMon && WS_IsMovable(_fgHwnd)) {
          WS_MoveToMonitor(_fgHwnd, _winMon, _curMon)
          if (Debug.Log["window-spawning"])
            FileAppend, % TS() " | window-spawning | MOVED (wmi-foreground): exe=" . _procName . " mon " . _winMon . " -> " . _curMon . "`n", % Debug.Log.Path
        }
      }
    }
    _evt := ""
  }
Return

WS_Cleanup() {
  global WS
  ; Stop WMI process monitoring
  SetTimer, WS_WMIPoll, Off
  WS.WMIEvents := ""
  WS.WMIService := ""
  for _h, _hadLayered in WS.Hidden {
    if (_hadLayered == -1)
      continue
    DllCall("SetLayeredWindowAttributes", "Ptr", _h, "UInt", 0, "UChar", 255, "UInt", 0x2)
    if (!_hadLayered)
      WinSet, ExStyle, -0x80000, ahk_id %_h%
  }
  WS.Hidden := {}
  WS.OwnerSentinel := {}
  DllCall("DeregisterShellHookWindow", "Ptr", WS.HookHwnd)
  Gui, ShellHook:Destroy
  if (WS.EventHookShow)
    DllCall("UnhookWinEvent", "Ptr", WS.EventHookShow)
  if (WS.EventHookUncloak)
    DllCall("UnhookWinEvent", "Ptr", WS.EventHookUncloak)
  if (WS.EventHookCreate)
    DllCall("UnhookWinEvent", "Ptr", WS.EventHookCreate)
  DllCall("ole32\CoUninitialize")
}

WS_QPC() {
  DllCall("QueryPerformanceCounter", "Int64*", _count)
  return _count
}

