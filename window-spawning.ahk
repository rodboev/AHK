; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === SPAWN WINDOWS ON CURRENT MONITOR === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; Intercepts new window creation and moves windows to the cursor's monitor.
; Uses shell hooks (creation/activation) and WinEvent hooks (SHOW/UNCLOAK/CREATE)
; for instant, event-driven detection.

WS_Init() {
  global WS, Debug
  WS := {}
  WS.RecentExes := {}              ; WMI: exe name -> A_TickCount (process started)
  WS.Pending := {}                 ; Deferred windows: hwnd -> {mon, tick}
  WS.PendingAltTab := ""           ; Alt+Tab: {mon, tick} or ""
  WS.PrePending := {}              ; CREATE pre-registration: hwnd -> {mon, tick, qpc}
  WS.Hidden := {}                  ; Opacity-hidden windows: hwnd -> hadLayered (bool)
  WS.Processed := {}               ; Moved/revealed/skipped windows: hwnd -> A_TickCount
  WS.OwnerSentinel := {}           ; Owner hwnd -> A_TickCount (sibling CREATE suppression)
  WS.LastMoved := {}                ; hwnd -> A_TickCount (WMI-foreground re-move suppression)
  WS.SubsystemCache := {}           ; exe name -> PE subsystem (2=GUI, 3=CUI, 0=unknown)
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
  WS_Log("INIT: SHOW=" . (WS.EventHookShow ? "OK" : "FAIL")
    . " UNCLOAK=" . (WS.EventHookUncloak ? "OK" : "FAIL")
    . " CREATE=" . (WS.EventHookCreate ? "OK" : "FAIL"))
  ; WMI process start monitoring — detects launches from any source (Run dialog, shortcuts, etc.)
  ; Uses semi-sync ExecNotificationQuery + timer poll (async SWbemSink unreliable in AHK STA)
  Try {
    _locator := ComObjCreate("WbemScripting.SWbemLocator")
    WS.WMIService := _locator.ConnectServer(".", "root\cimv2")
    WS.WMIService.Security_.ImpersonationLevel := 3  ; wbemImpersonationLevelImpersonate
    WS.WMIEvents := WS.WMIService.ExecNotificationQuery("SELECT * FROM Win32_ProcessStartTrace")
    SetTimer, WS_WMIPoll, 50
    WS_Log("INIT: WMI=OK (polling)")
  } catch _e {
    WS_Log("INIT: WMI=FAIL err=" . _e.Message)
    ToolTip, WMI unavailable — single-instance re-launch moves disabled
    SetTimer, WS_ClearInitTip, -3000
  }

  SetTimer, WS_SweepTracking, 1000
  OnExit("WS_Cleanup")
}

WS_Log(msg) {
  global Debug
  if (!Debug.Log["window-spawning"])
    return
  _p := Debug.Log.Path
  FileAppend, % TS() " | window-spawning | " . msg . "`n", %_p%
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

  if (isDestroyed) {
    WS.Pending.Delete(lParam + 0)
    WS.PrePending.Delete(lParam + 0)
    WS.Hidden.Delete(lParam + 0)
    return
  }

  cursorMon := GetCursorMonitor()

  if (isActivated) {
    if (!WS_IsMovable(lParam))
      return
    WinGet, _actExe, ProcessName, ahk_id %lParam%
    if (!WS.RecentExes.HasKey(_actExe))
      return
    _intentAge := A_TickCount - WS.RecentExes[_actExe]
    if (_intentAge > 5000)
      return
    windowMon := GetMonitor("ahk_id " . lParam)
    if (windowMon == cursorMon) {
      WS.RecentExes.Delete(_actExe)
      return
    }
    WS.RecentExes.Delete(_actExe)
    WS_MoveToMonitor(lParam, windowMon, cursorMon)
    if (Debug.Log["window-spawning"]) {
      WinGetTitle, _dbgTitle, ahk_id %lParam%
      WS_Log("MOVED (activate): """ . _dbgTitle . """ exe=" . _actExe . " mon " . windowMon . " -> " . cursorMon)
    }
    return
  }

  ; --- Creation path: new window ---

  ; Skip if already processed (duplicate HSHELL_WINDOWCREATED for same hwnd)
  ; Only suppress within 5s — long-lived single-instance apps reuse the same hwnd on re-launch
  if (WS.Processed.HasKey(lParam + 0)) {
    if (Debug.Log["window-spawning"]) {
      WinGetTitle, _dbgTitle, ahk_id %lParam%
      WS_Log("SKIP (already-handled): """ . _dbgTitle . """ hwnd=" . lParam)
    }
    return
  }

  ; Use pre-registered target from CREATE event if available
  if (WS.PrePending.HasKey(lParam + 0)) {
    ppEntry := WS.PrePending.Delete(lParam + 0)
    if (Debug.Log["window-spawning"]) {
      ctDeltaUs := Round((WS_QPC() - ppEntry.qpc) * 1000000 / WS.QPCFreq)
      WS_Log("SHELL: hwnd=" . lParam . " create-to-shell=" . ctDeltaUs . "µs")
    }
    WS_TryMoveOrDefer(lParam, ppEntry.mon, ppEntry.tick)
    return
  }

  ; Fallback: no CREATE pre-registration (window missed by CREATE hook)
  WS_TryMoveOrDefer(lParam, cursorMon, A_TickCount)
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
        cursorMon := GetCursorMonitor()
        windowMon := GetMonitor("ahk_id " . hwnd)
        if (windowMon != cursorMon) {
          WS_MoveToMonitor(hwnd, windowMon, cursorMon)
          WS_Log("MOVED (start-menu): mon " . windowMon . " -> " . cursorMon . " exe=" . _evExe)
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
    if (WS.Processed.HasKey(hwnd))
      return
    ; Owner sentinel — skip if owner was recently moved (sibling protection)
    _ppOwner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")  ; GW_OWNER=4
    if (_ppOwner && WS.OwnerSentinel.HasKey(_ppOwner + 0)) {
      if (A_TickCount - WS.OwnerSentinel[_ppOwner + 0] < 200) {
        WS.Processed[hwnd] := A_TickCount
        if (Debug.Log["window-spawning"]) {
          WinGetClass, _dbgClass, ahk_id %hwnd%
          WS_Log("CREATE-SKIP-OWNER: hwnd=" . hwnd . " class=" . _dbgClass
            . " owner=" . Format("0x{:08X}", _ppOwner))
        }
        return
      }
    }
    if (_ppOwner) {
      if (WS.Processed.HasKey(_ppOwner + 0))
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
      WS_Log("CREATE: hwnd=" . hwnd . " class=" . _dbgClass . " hide mon " . cursorMon
        . (windowMon && windowMon != cursorMon ? " (from " . windowMon . ")" : ""))
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
      WS_Log(_evName . ": hwnd=" . hwnd . " """ . _dbgTitle . """ class=" . _dbgClass
        . " create-to-" . _evName . "=" . (A_TickCount - ppEntry.tick) . "ms (" . _deltaUs . "µs)")
    }
    if (WS_TryMoveOrDefer(hwnd, ppEntry.mon, ppEntry.tick, false))
      WS.Pending.Delete(hwnd)
    return
  }

  ; --- Pending creation moves ---
  if (WS.Pending.HasKey(hwnd)) {
    if (WS_IsReady(hwnd)) {
      entry := WS.Pending.Delete(hwnd)
      if (entry)
        WS_TryMoveOrDefer(hwnd, entry.mon, entry.tick, false)
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

; Returns true if handled (moved or determined non-movable), false if deferred
WS_TryMoveOrDefer(hwnd, targetMon, tick, shouldDefer:=true) {
  global WS
  hwnd := hwnd + 0
  if (WS_IsReady(hwnd)) {
    if (WS_IsMovable(hwnd)) {
      windowMon := GetMonitor("ahk_id " . hwnd)
      if (windowMon != targetMon)
        WS_MoveToMonitor(hwnd, windowMon, targetMon)
      WS_Reveal(hwnd)
      return true
    }
    WinGetTitle, _chkTitle, ahk_id %hwnd%
    if (_chkTitle != "") {
      WS_Reveal(hwnd)
      return true
    }
  }
  if (!shouldDefer)
    return false
  WS.Pending[hwnd] := {mon: targetMon, tick: tick}
  _fn := Func("WS_BackupPoll").Bind(hwnd, 1)
  SetTimer, %_fn%, -100
  _fn2 := Func("WS_TimeoutPending").Bind(hwnd)
  SetTimer, %_fn2%, -2000
  return false
}

; Escalating backup poll — catches windows where WinEvent didn't fire (e.g. elevated processes)
; Polls at ~100, 300, 600, 1000ms cumulative; 2s timeout remains as safety net
WS_BackupPoll(hwnd, attempt:=1) {
  global WS
  if (!WS.Pending.HasKey(hwnd))
    return
  SetWinDelay, -1
  if (WS_IsReady(hwnd)) {
    entry := WS.Pending.Delete(hwnd)
    if (entry)
      WS_TryMoveOrDefer(hwnd, entry.mon, entry.tick, false)
    return
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
  if (entry)
    WS_TryMoveOrDefer(hwnd, entry.mon, entry.tick, false)
  else
    WS_Reveal(hwnd)
}

SweepStale(dict, maxAge) {
  _now := A_TickCount
  _stale := []
  for _k, _v in dict
    if (_now - _v > maxAge)
      _stale.Push(_k)
  for _i, _k in _stale
    dict.Delete(_k)
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
  SweepStale(WS.OwnerSentinel, 2000)

  ; Orphan sweep: reveal windows stuck in Hidden that aren't tracked
  _staleKeys := []
  for _h, _val in WS.Hidden {
    if (!WinExist("ahk_id " . _h)) {
      _staleKeys.Push(_h)
      continue
    }
    if (!WS.PrePending.HasKey(_h) && !WS.Pending.HasKey(_h)) {
      _staleKeys.Push(_h)
      WS_Log("ORPHAN-REVEAL: hwnd=" . _h)
      WS_RestoreOpacity(_h, _val)
    }
  }
  for _i, _k in _staleKeys
    WS.Hidden.Delete(_k)

  ; Stale Processed entries (>5s)
  SweepStale(WS.Processed, 5000)

  ; Stale recent-exe intent signals (>10s)
  SweepStale(WS.RecentExes, 10000)

  ; Stale move-cooldown entries (>5s)
  SweepStale(WS.LastMoved, 5000)

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
  _wasHidden := false
  _hadLayered := 0
  if (WS.Hidden.HasKey(hwnd)) {
    _hadLayered := WS.Hidden.Delete(hwnd)
    _wasHidden := true
  }
  WS.Processed[hwnd] := A_TickCount

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
  if (_wasHidden)
    WS_RestoreOpacity(hwnd, _hadLayered)
}

WS_RestoreOpacity(hwnd, hadLayered) {
  DllCall("SetLayeredWindowAttributes", "Ptr", hwnd, "UInt", 0, "UChar", 255, "UInt", 0x2)
  if (!hadLayered)
    WinSet, ExStyle, -0x80000, ahk_id %hwnd%
}

; Restore opacity for a window hidden at CREATE time (idempotent)
WS_Reveal(hwnd) {
  global WS
  hwnd := hwnd + 0
  if (!WS.Hidden.HasKey(hwnd)) {
    WS.Processed[hwnd] := A_TickCount
    return
  }
  _hadLayered := WS.Hidden.Delete(hwnd)
  WS.Processed[hwnd] := A_TickCount
  if !WinExist("ahk_id " . hwnd)
    return
  WS_RestoreOpacity(hwnd, _hadLayered)
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

WS_ClearInitTip:
  ToolTip
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
    _parentPid := _evt.ParentProcessID
    if (_procName != "") {
      if (WS_GetSubsystem(_evt.ProcessID, _procName) = 3 || _procName = "conhost.exe")
        continue
      ; Skip if same exe already has windows (protocol handler / URL stub, not a fresh launch)
      if (WinExist("ahk_exe " . _procName)) {
        WS_Log("SKIP (already-running): exe=" . _procName . " parentPid=" . _parentPid)
        continue
      }
      WS.RecentExes[_procName] := A_TickCount
      WS_Log("WMI-PROC: " . _procName . " parentPid=" . _parentPid)
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
  for _h, _hadLayered in WS.Hidden
    WS_RestoreOpacity(_h, _hadLayered)
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

WS_GetSubsystem(pid, procName) {
  global WS
  if (WS.SubsystemCache.HasKey(procName))
    return WS.SubsystemCache[procName]
  _exePath := ""
  _hProc := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")
  if (_hProc) {
    VarSetCapacity(_pathBuf, 520, 0)
    _pathLen := 260
    _ok := DllCall("QueryFullProcessImageNameW", "Ptr", _hProc, "UInt", 0, "Ptr", &_pathBuf, "UInt*", _pathLen)
    DllCall("CloseHandle", "Ptr", _hProc)
    if (_ok && _pathLen > 0)
      _exePath := StrGet(&_pathBuf, _pathLen, "UTF-16")
  }
  if (_exePath = "") {
    VarSetCapacity(_pathBuf, 520, 0)
    _found := DllCall("SearchPathW", "Ptr", 0, "Str", procName, "Ptr", 0, "UInt", 260, "Ptr", &_pathBuf, "Ptr", 0, "UInt")
    if (_found > 0)
      _exePath := StrGet(&_pathBuf, _found, "UTF-16")
  }
  if (_exePath = "")
    return 0
  _subsys := 0
  Try {
    _f := FileOpen(_exePath, "r")
    if (IsObject(_f)) {
      _f.Seek(0x3C, 0)
      _peOffset := _f.ReadUInt()
      _f.Seek(_peOffset + 92, 0)
      _subsys := _f.ReadUShort()
      _f.Close()
    }
  }
  if (_subsys)
    WS.SubsystemCache[procName] := _subsys
  return _subsys
}

