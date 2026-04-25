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

WS_Init() {
  global WS
  WS := {}
  WS.Debug := 0                    ; Debug logging (0=off, 1=on)
  WS.LogFile := A_Temp . "\WS_Debug.log"
  WS.LastForegroundHwnd := 0
  WS.OverlayTick := 0              ; A_TickCount when non-movable overlay activated
  WS.ZOrderFallbackTick := 0       ; A_TickCount when foreground destroyed (z-order fallback imminent)
  WS.RecentExes := {}              ; Tier 1: exe name -> A_TickCount (brief process detected)
  WS.RecentCreated := {}           ; Tier 1: hwnd -> {exe, tick} (window lifespan tracking)
  WS.Pending := {}                 ; Deferred windows: hwnd -> {mon, tick}
  WS.PendingAltTab := ""           ; Alt+Tab: {mon, tick} or ""
  WS.PrePending := {}              ; CREATE pre-registration: hwnd -> {mon, tick, qpc}
  WS.Hidden := {}                  ; Opacity-hidden windows: hwnd -> hadLayered (bool/-1 sentinel)
  WS.OwnerSentinel := {}           ; Owner hwnd -> A_TickCount (sibling CREATE suppression)
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
    WS_Log("ERROR: Shell hook failed — Hook=" . _hookOK . " Msg=" . _hookMsg)

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
  if (WS.Debug) {
    _logFile := WS.LogFile
    FileDelete, %_logFile%
    WS_Log("INIT: SHOW=" . (WS.EventHookShow ? "OK" : "FAIL")
      . " UNCLOAK=" . (WS.EventHookUncloak ? "OK" : "FAIL")
      . " CREATE=" . (WS.EventHookCreate ? "OK" : "FAIL"))
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
    ; Clear intent signals when foreground window closes — prevents false positives
    ; on the subsequent Z-order fallback activation.
    if (lParam == WS.LastForegroundHwnd) {
      WS.OverlayTick := 0
      WS.ZOrderFallbackTick := A_TickCount
    }
    ; Brief-process detection: if a recently-created window dies quickly,
    ; its exe is a single-instance app that just bounced a re-launch.
    if (WS.RecentCreated.HasKey(lParam + 0)) {
      _rcEntry := WS.RecentCreated.Delete(lParam + 0)
      _rcAge := A_TickCount - _rcEntry.tick
      if (_rcAge < 3000) {
        WS.RecentExes[_rcEntry.exe] := A_TickCount
        if (WS.Debug)
          WS_Log("INTENT-SIGNAL: exe=" . _rcEntry.exe . " lived=" . _rcAge . "ms")
      }
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
      ; Non-movable windows: record overlay timestamps for Tier 2 detection
      WinGetClass, _nmClass, ahk_id %lParam%
      if (_nmClass == "") {
        WS.OverlayTick := A_TickCount
        if (WS.Debug)
          WS_Log("OVERLAY (infra): hwnd=" . lParam)
        return
      }
      if (_nmClass == "Shell_TrayWnd" || _nmClass == "Shell_SecondaryTrayWnd") {
        WS.OverlayTick := A_TickCount
        if (WS.Debug)
          WS_Log("OVERLAY (taskbar): hwnd=" . lParam)
        return
      }
      if (_nmClass == "Windows.UI.Core.CoreWindow") {
        WinGet, _nmExe, ProcessName, ahk_id %lParam%
        if (_nmExe != "explorer.exe" && _nmExe != "StartMenuExperienceHost.exe")
          return
      }
      WS.OverlayTick := A_TickCount
      if (WS.Debug) {
        WinGet, _nmExe, ProcessName, ahk_id %lParam%
        WS_Log("OVERLAY: class=" . _nmClass . " exe=" . _nmExe . " hwnd=" . lParam)
      }
      return
    }

    ; --- Positive intent detection (default: no move) ---
    ; Z-order fallback guard: if foreground was just destroyed, this activation
    ; is Windows selecting the next window in z-order, not user intent.
    if (WS.ZOrderFallbackTick && (A_TickCount - WS.ZOrderFallbackTick) < 200) {
      WS.ZOrderFallbackTick := 0
      if (WS.Debug)
        WS_Log("SKIP (z-order-fallback): hwnd=" . lParam)
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
        if (WS.Debug)
          WS_Log("INTENT (brief-process): exe=" . _actExe . " age=" . _intentAge . "ms")
      }
    }

    ; Tier 2: Overlay launch (Start menu, Action Center → different window activated)
    if (!_hasIntent && WS.OverlayTick) {
      _overlayAge := A_TickCount - WS.OverlayTick
      if (_overlayAge < 2000 && lParam != prevHwnd) {
        _hasIntent := true
        if (WS.Debug)
          WS_Log("INTENT (overlay-launch): exe=" . _actExe . " overlay=" . _overlayAge . "ms ago")
      }
    }
    WS.OverlayTick := 0

    if (!_hasIntent) {
      if (WS.Debug) {
        WinGetTitle, _dbgTitle, ahk_id %lParam%
        WS_Log("SKIP (no-intent): """ . _dbgTitle . """ exe=" . _actExe)
      }
      return
    }

    ; Taskbar click guard: clicking a taskbar button is not a launch
    MouseGetPos,,, _mouseWin
    WinGetClass, _mouseClass, ahk_id %_mouseWin%
    if (_mouseClass == "Shell_TrayWnd" || _mouseClass == "Shell_SecondaryTrayWnd") {
      if (WS.Debug) {
        WinGetTitle, _dbgTitle, ahk_id %lParam%
        WS_Log("SKIP (taskbar-click): """ . _dbgTitle . """")
      }
      return
    }

    windowMon := GetMonitor("ahk_id " . lParam)
    if (windowMon == cursorMon)
      return
    WS_MoveToMonitor(lParam, windowMon, cursorMon)
    if (WS.Debug) {
      WinGetTitle, _dbgTitle, ahk_id %lParam%
      WS_Log("MOVED (activate): """ . _dbgTitle . """ mon " . windowMon . " -> " . cursorMon)
    }
    return
  }

  ; --- Creation path: new window ---

  ; Record exe for brief-process tracking (Tier 1: single-instance detection)
  WinGet, _createExe, ProcessName, ahk_id %lParam%
  if (_createExe != "")
    WS.RecentCreated[lParam + 0] := {exe: _createExe, tick: A_TickCount}

  ; Use pre-registered target from CREATE event if available
  if (WS.PrePending.HasKey(lParam + 0)) {
    ppEntry := WS.PrePending.Delete(lParam + 0)
    if (WS.Debug) {
      ctDeltaUs := Round((WS_QPC() - ppEntry.qpc) * 1000000 / WS.QPCFreq)
      WS_Log("SHELL: hwnd=" . lParam . " create-to-shell=" . ctDeltaUs . "µs")
    }
    targetMon := ppEntry.mon
    if (WS_IsReady(lParam)) {
      if (WS_IsMovable(lParam)) {
        windowMon := GetMonitor("ahk_id " . lParam)
        if (windowMon != targetMon) {
          WS_MoveToMonitor(lParam, windowMon, targetMon)
          if (WS.Debug) {
            WinGetTitle, _dbgTitle, ahk_id %lParam%
            WS_Log("MOVED (create-shell): """ . _dbgTitle . """ mon " . windowMon . " -> " . targetMon . " +" . (A_TickCount - ppEntry.tick) . "ms")
          }
        } else if (WS.Debug) {
          WinGetTitle, _dbgTitle, ahk_id %lParam%
          WS_Log("OK (create-shell): """ . _dbgTitle . """ already on mon " . windowMon)
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
    _fn := Func("WS_BackupPoll").Bind(lParam + 0)
    SetTimer, %_fn%, -200
    _fn2 := Func("WS_TimeoutPending").Bind(lParam + 0)
    SetTimer, %_fn2%, -2000
    if (WS.Debug) {
      WinGetTitle, _dbgTitle, ahk_id %lParam%
      WinGetClass, _dbgClass, ahk_id %lParam%
      WS_Log("DEFERRED (create-path): hwnd=" . lParam . " """ . _dbgTitle . """ class=" . _dbgClass)
    }
    return
  }

  ; Fallback: no CREATE pre-registration (window missed by CREATE hook)
  if (WS_IsReady(lParam)) {
    if (WS_IsMovable(lParam)) {
      windowMon := GetMonitor("ahk_id " . lParam)
      if (windowMon != cursorMon) {
        WS_MoveToMonitor(lParam, windowMon, cursorMon)
        if (WS.Debug) {
          WinGetTitle, _dbgTitle, ahk_id %lParam%
          WS_Log("MOVED (instant): """ . _dbgTitle . """ mon " . windowMon . " -> " . cursorMon)
        }
      } else if (WS.Debug) {
        WinGetTitle, _dbgTitle, ahk_id %lParam%
        WS_Log("OK (instant): """ . _dbgTitle . """ already on mon " . windowMon)
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
  _fn := Func("WS_BackupPoll").Bind(lParam + 0)
  SetTimer, %_fn%, -200
  _fn2 := Func("WS_TimeoutPending").Bind(lParam + 0)
  SetTimer, %_fn2%, -2000
  if (WS.Debug) {
    WinGetTitle, _dbgTitle, ahk_id %lParam%
    WinGetClass, _dbgClass, ahk_id %lParam%
    WS_Log("DEFERRED: hwnd=" . lParam . " """ . _dbgTitle . """ class=" . _dbgClass)
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
        if (WS.Debug) {
          WinGetClass, _dbgClass, ahk_id %hwnd%
          WS_Log("CREATE-SKIP-OWNER: hwnd=" . hwnd . " class=" . _dbgClass
            . " owner=" . Format("0x{:08X}", _ppOwner))
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
      , "UChar", WS.Debug ? 128 : 0, "UInt", 0x2)  ; LWA_ALPHA
    WS.Hidden[hwnd] := _hadLayered
    ; Now capture cursor/monitor (safe to do after hide)
    cursorMon := GetCursorMonitor()
    windowMon := GetMonitor("ahk_id " . hwnd)
    WS.PrePending[hwnd] := {mon: cursorMon, tick: A_TickCount, qpc: WS_QPC()}
    if (WS.Debug) {
      WinGetClass, _dbgClass, ahk_id %hwnd%
      WS_Log("CREATE: hwnd=" . hwnd . " class=" . _dbgClass . " hide mon " . cursorMon
        . (windowMon && windowMon != cursorMon ? " (from " . windowMon . ")" : ""))
    }
    return
  }

  ; --- PrePending SHOW/UNCLOAK fast path ---
  if (WS.PrePending.HasKey(hwnd)) {
    ppEntry := WS.PrePending.Delete(hwnd)
    if (WS.Debug) {
      _evName := (event == 0x8002) ? "SHOW" : "UNCLOAK"
      WinGetTitle, _dbgTitle, ahk_id %hwnd%
      WinGetClass, _dbgClass, ahk_id %hwnd%
      _deltaUs := Round((WS_QPC() - ppEntry.qpc) * 1000000 / WS.QPCFreq)
      WS_Log(_evName . ": hwnd=" . hwnd . " """ . _dbgTitle . """ class=" . _dbgClass
        . " create-to-" . _evName . "=" . (A_TickCount - ppEntry.tick) . "ms (" . _deltaUs . "µs)")
    }
    if (WS_IsReady(hwnd) && WS_IsMovable(hwnd)) {
      windowMon := GetMonitor("ahk_id " . hwnd)
      if (windowMon != ppEntry.mon) {
        WS_MoveToMonitor(hwnd, windowMon, ppEntry.mon)
        if (WS.Debug) {
          WinGetTitle, _dbgTitle, ahk_id %hwnd%
          WS_Log("MOVED (create-show): """ . _dbgTitle . """ mon " . windowMon . " -> " . ppEntry.mon . " +" . (A_TickCount - ppEntry.tick) . "ms")
        }
      } else if (WS.Debug) {
        WinGetTitle, _dbgTitle, ahk_id %hwnd%
        WS_Log("OK (create-show): """ . _dbgTitle . """ already on mon " . windowMon)
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
    if (WS.Debug) {
      _elapsed := tick ? A_TickCount - tick : 0
      WinGetTitle, _dbgTitle, ahk_id %hwnd%
      WS_Log("MOVED (" . source . "): """ . _dbgTitle . """ mon " . windowMon . " -> " . targetMon . " +" . _elapsed . "ms")
    }
  }
  WS_Reveal(hwnd)
}

; Single backup poll — catches windows where WinEvent arrived but wasn't ready/movable yet
WS_BackupPoll(hwnd) {
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
    }
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
    if (_val == -1)
      continue
    if (!WinExist("ahk_id " . _h)) {
      _staleKeys.Push(_h)
      continue
    }
    if (!WS.PrePending.HasKey(_h) && !WS.Pending.HasKey(_h)) {
      _staleKeys.Push(_h)
      if (WS.Debug)
        WS_Log("ORPHAN-REVEAL: hwnd=" . _h)
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

  ; Stale created-window tracking (>10s — not brief, not relevant)
  _staleKeys := []
  for _h, _entry in WS.RecentCreated {
    if (_now - _entry.tick > 10000)
      _staleKeys.Push(_h)
  }
  for _i, _k in _staleKeys
    WS.RecentCreated.Delete(_k)
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


WS_Cleanup() {
  global WS
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

WS_Log(msg) {
  global WS
  _logFile := WS.LogFile
  FileAppend, %A_Hour%:%A_Min%:%A_Sec% [%A_TickCount%] %msg%`n, %_logFile%
}
