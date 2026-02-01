; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === SPAWN WINDOWS ON CURRENT MONITOR === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; Shell hook intercepts new window creation and moves the window
; to whichever monitor the cursor is on. WinEvent hooks (EVENT_OBJECT_SHOW,
; EVENT_OBJECT_UNCLOAKED) detect when deferred windows become visible,
; replacing timer-based polling with event-driven detection.

WS_Debug := 1 ; Window spawning debug tooltips (0=off, 1=on)

; Get which monitor the cursor is on (1-based)
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

WS_Init() {
  global
  WS_LastDestroyTick := 0
  WS_LastForegroundHwnd := 0
  WS_OverlayTick := 0             ; A_TickCount when non-movable overlay activated (0 = none)
  WS_Pending := {}            ; Deferred windows: hwnd -> {mon, tick}
  WS_PendingAltTab := ""      ; Alt+Tab: {mon, tick} or ""
  WS_PrePending := {}         ; Phase 10: CREATE pre-registration: hwnd -> {mon, tick, qpc}
  WS_Hidden := {}             ; Phase 10: opacity-hidden windows: hwnd -> hadLayered (bool)
  WS_OwnerSentinel := {}      ; Phase 10: owner hwnd -> A_TickCount (sibling CREATE suppression)
  DllCall("QueryPerformanceFrequency", "Int64*", WS_QPCFreq)
  WS_LogFile := A_Temp . "\WS_Debug.log"
  WS_ExcludedClasses := ["tooltips_class32", "NotifyIconOverflowWindow"
    , "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "Progman", "WorkerW"
    , "MultitaskingViewFrame", "Windows.UI.Core.CoreWindow", "ForegroundStaging"]
  ; Shell hook for window creation/activation detection
  Gui, ShellHook:+LastFound
  Gui, ShellHook:Show, Hide
  WS_HookHwnd := WinExist()
  WS_HookOK := DllCall("RegisterShellHookWindow", "Ptr", WS_HookHwnd)
  WS_HookMsg := DllCall("RegisterWindowMessage", "Str", "SHELLHOOK")
  if (WS_HookOK && WS_HookMsg > 0)
    OnMessage(WS_HookMsg, "WS_OnShellHook")
  else
    WS_Log("ERROR: Shell hook failed — Hook=" . WS_HookOK . " Msg=" . WS_HookMsg)
  ; WinEvent hooks for instant visibility/uncloak detection (UWP apps)
  DllCall("ole32\CoInitialize", "Ptr", 0)
  WS_WinEventCB := RegisterCallback("WS_OnWinEvent", "", 7)
  WS_EventHookShow := DllCall("SetWinEventHook"
    , "UInt", 0x8002, "UInt", 0x8002   ; EVENT_OBJECT_SHOW
    , "Ptr", 0, "Ptr", WS_WinEventCB
    , "UInt", 0, "UInt", 0, "UInt", 0x0002, "Ptr")
  WS_EventHookUncloak := DllCall("SetWinEventHook"
    , "UInt", 0x8018, "UInt", 0x8018   ; EVENT_OBJECT_UNCLOAKED
    , "Ptr", 0, "Ptr", WS_WinEventCB
    , "UInt", 0, "UInt", 0, "UInt", 0x0002, "Ptr")
  ; Phase 10: Hook CREATE for pre-visibility positioning
  WS_EventHookCreate := DllCall("SetWinEventHook"
    , "UInt", 0x8000, "UInt", 0x8000   ; EVENT_OBJECT_CREATE
    , "Ptr", 0, "Ptr", WS_WinEventCB
    , "UInt", 0, "UInt", 0, "UInt", 0x0002, "Ptr")
  if (WS_Debug) {
    FileDelete, %WS_LogFile%
    WS_Log("INIT: SHOW=" . (WS_EventHookShow ? "OK" : "FAIL")
      . " UNCLOAK=" . (WS_EventHookUncloak ? "OK" : "FAIL")
      . " CREATE=" . (WS_EventHookCreate ? "OK" : "FAIL"))
  }
  ; Phase 10: Periodic cleanup of stale PrePending entries (every 5s)
  SetTimer, WS_CleanPrePending, 1000
  OnExit("WS_Cleanup")
}

WS_OnShellHook(wParam, lParam, msg, hwnd) {
  ; HSHELL_WINDOWCREATED=1, HSHELL_WINDOWACTIVATED=4, HSHELL_RUDEAPPACTIVATED=0x8004
  isCreated := (wParam == 1)
  isActivated := (wParam == 4 || wParam == 0x8004)
  isDestroyed := (wParam == 2)
  if (!isCreated && !isActivated && !isDestroyed)
    return
  SetWinDelay, -1  ; No delay between window commands (AHK default is 100ms)
  global WS_Debug, WS_LastDestroyTick, WS_LastForegroundHwnd, WS_OverlayTick, WS_Pending, WS_PrePending, WS_QPCFreq, WS_Hidden, WS_OwnerSentinel

  ; Track foreground window destruction to suppress Z-order fallback activation.
  ; Only the foreground window's close triggers Z-order fallback — background/transient
  ; windows (e.g., single-instance app second process) don't cause fallback activation.
  if (isDestroyed) {
    if (lParam == WS_LastForegroundHwnd)
      WS_LastDestroyTick := A_TickCount
    if (WS_Debug && lParam == WS_LastForegroundHwnd) {
      WinGetTitle, dbgTitle, ahk_id %lParam%
      WS_Log("DESTROYED (fg): hwnd=" . lParam . " """ . dbgTitle . """")
    }
    WS_Pending.Delete(lParam + 0)
    WS_PrePending.Delete(lParam + 0)
    WS_Hidden.Delete(lParam + 0)  ; No reveal needed — window is gone
    return
  }

  cursorMon := GetCursorMonitor()

  ; --- Activation path: move existing window to cursor's monitor ---
  if (isActivated) {
    _actMovable := WS_IsMovable(lParam)
    if (WS_Debug) {
      WinGetClass, _dbgActClass, ahk_id %lParam%
      WinGet, _dbgActExe, ProcessName, ahk_id %lParam%
      WS_Log("ACTIVATE: hwnd=" . lParam . " class=" . _dbgActClass . " exe=" . _dbgActExe
        . " movable=" . _actMovable)
    }
    ; Ignore system windows (Start menu, tool windows, excluded classes).
    ; Record overlay timestamp for guard #2 bounce-back detection.
    ; Empty-class infrastructure windows fire before every activation — they signal
    ; that something briefly took focus (Start menu, overlays, UWP cascades).
    ; Guard #2 uses lParam == WS_LastForegroundHwnd to distinguish bounce-back from
    ; genuine switches, so setting WS_OverlayTick broadly is safe.
    if (!_actMovable) {
      WinGetClass, _nmClass, ahk_id %lParam%
      ; Infrastructure windows with no class fire before every activation sequence.
      ; Set overlay tick so Guard #2 can detect same-window bounce-back.
      if (_nmClass == "") {
        WS_OverlayTick := A_TickCount
        if (WS_Debug)
          WS_Log("OVERLAY (infra): hwnd=" . lParam)
        return
      }
      ; Taskbar activation: set overlay tick for Start button / taskbar interaction bounce-back.
      ; Safe: different-window clicks don't match Guard #2 (lParam != WS_LastForegroundHwnd);
      ; same-window taskbar clicks are caught by Guard #6 (cursor over taskbar).
      if (_nmClass == "Shell_TrayWnd" || _nmClass == "Shell_SecondaryTrayWnd") {
        WS_OverlayTick := A_TickCount
        if (WS_Debug)
          WS_Log("OVERLAY (taskbar): class=" . _nmClass . " hwnd=" . lParam)
        return
      }
      ; UWP apps activate their own CoreWindow internally — only count as overlay
      ; if it belongs to explorer.exe (Action Center) or StartMenuExperienceHost.exe.
      ; UWP apps use split-process (ApplicationFrameHost.exe + app.exe), so PID check won't work.
      if (_nmClass == "Windows.UI.Core.CoreWindow") {
        WinGet, _nmExe, ProcessName, ahk_id %lParam%
        if (_nmExe != "explorer.exe" && _nmExe != "StartMenuExperienceHost.exe")
          return
      }
      WS_OverlayTick := A_TickCount
      if (WS_Debug) {
        if (!_nmExe) {
          WinGet, _nmExe, ProcessName, ahk_id %lParam%
        }
        WS_Log("OVERLAY: class=" . _nmClass . " exe=" . _nmExe . " hwnd=" . lParam)
      }
      return
    }
    ; Guard #2: Skip re-activation of the same window after overlay or Start menu.
    if (lParam == WS_LastForegroundHwnd) {
      ; Check A: Recent overlay signal (empty-class infrastructure, taskbar, CoreWindow).
      ; Two timing bands: 0-2000ms = bounce-back → block; >2000ms = user launched → allow.
      if (WS_OverlayTick) {
        _overlayElapsed := A_TickCount - WS_OverlayTick
        if (_overlayElapsed < 2000) {
          WS_OverlayTick := 0
          if (WS_Debug) {
            WinGetTitle, dbgTitle, ahk_id %lParam%
            WS_Log("SKIP (overlay-bounce): """ . dbgTitle . """ overlay " . _overlayElapsed . "ms ago")
          }
          return
        }
      }
      ; Check B: Start menu currently visible — direct detection via DWM cloaked state.
      ; The Start menu doesn't fire HSHELL_WINDOWACTIVATED, but it must still be visible
      ; when the bounce-back activation fires (the activation is caused by its dismissal).
      _smHwnd := WinExist("ahk_exe StartMenuExperienceHost.exe")
      if (_smHwnd) {
        VarSetCapacity(_cloaked, 4, 0)
        DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", _smHwnd, "UInt", 14, "Ptr", &_cloaked, "UInt", 4)
        if (!NumGet(_cloaked, 0, "UInt")) {
          WS_OverlayTick := 0
          if (WS_Debug) {
            WinGetTitle, dbgTitle, ahk_id %lParam%
            WS_Log("SKIP (startmenu-open): """ . dbgTitle . """")
          }
          return
        }
      }
    }
    WS_OverlayTick := 0
    ; Save previous foreground before updating tracker
    prevHwnd := WS_LastForegroundHwnd
    WS_LastForegroundHwnd := lParam
    ; Skip auto-activation after window close (system Z-order fallback, not user action)
    if (A_TickCount - WS_LastDestroyTick < 500) {
      if (WS_Debug) {
        WinGetTitle, dbgTitle, ahk_id %lParam%
        WS_Log("SKIP (activate-destroy): """ . dbgTitle . """ within " . (A_TickCount - WS_LastDestroyTick) . "ms of close")
      }
      return
    }
    ; Skip auto-activation after window minimize (system Z-order fallback, not user action)
    if (prevHwnd) {
      WinGet, prevMinMax, MinMax, ahk_id %prevHwnd%
      if (prevMinMax == -1) {
        if (WS_Debug) {
          WinGetTitle, dbgTitle, ahk_id %lParam%
          WS_Log("SKIP (activate-minimize): """ . dbgTitle . """ prev window minimized")
        }
        return
      }
    }
    ; Skip if cursor is over the taskbar (user clicked a taskbar button)
    MouseGetPos,,, mouseWin
    WinGetClass, mouseClass, ahk_id %mouseWin%
    if (mouseClass == "Shell_TrayWnd" || mouseClass == "Shell_SecondaryTrayWnd") {
      if (WS_Debug) {
        WinGetTitle, dbgTitle, ahk_id %lParam%
        WS_Log("SKIP (activate-taskbar): """ . dbgTitle . """ cursor over taskbar")
      }
      return
    }
    windowMon := GetMonitor("ahk_id " . lParam)
    if (windowMon == cursorMon)
      return  ; Already on correct monitor — silent, no tooltip
    WS_MoveToMonitor(lParam, windowMon, cursorMon)
    if (WS_Debug) {
      WinGetTitle, dbgTitle, ahk_id %lParam%
      WS_Log("MOVED (activate): """ . dbgTitle . """ mon " . windowMon . " -> " . cursorMon)
    }
    return
  }

  ; --- Creation path: new window ---

  ; Phase 10: Use pre-registered target from CREATE event if available
  if (WS_PrePending.HasKey(lParam + 0)) {
    ppEntry := WS_PrePending.Delete(lParam + 0)
    if (WS_Debug) {
      ctDeltaUs := Round((WS_QPC() - ppEntry.qpc) * 1000000 / WS_QPCFreq)
      WS_Log("SHELL: hwnd=" . lParam . " create-to-shell=" . ctDeltaUs . "µs")
    }
    targetMon := ppEntry.mon
    ; Try to move immediately using pre-registered target
    if (WS_IsReady(lParam)) {
      if (WS_IsMovable(lParam)) {
        windowMon := GetMonitor("ahk_id " . lParam)
        if (windowMon != targetMon) {
          WS_MoveToMonitor(lParam, windowMon, targetMon)
          if (WS_Debug) {
            WinGetTitle, dbgTitle, ahk_id %lParam%
            WS_Log("MOVED (create-shell): """ . dbgTitle . """ mon " . windowMon . " -> " . targetMon . " +" . (A_TickCount - ppEntry.tick) . "ms")
          }
        } else if (WS_Debug) {
          WinGetTitle, dbgTitle, ahk_id %lParam%
          WS_Log("OK (create-shell): """ . dbgTitle . """ already on mon " . windowMon)
        }
        WS_Reveal(lParam)
        if (WS_Debug) {
          WS_Log("SHELL-DONE: hwnd=" . lParam . " hex=" . Format("0x{:08X}", lParam + 0)
            . " HasKey=" . WS_Hidden.HasKey(lParam + 0)
            . " val=" . (WS_Hidden.HasKey(lParam + 0) ? WS_Hidden[lParam + 0] : "N/A"))
        }
        return
      }
      WinGetTitle, chkTitle, ahk_id %lParam%
      if (chkTitle != "") {
        WS_Reveal(lParam)  ; Permanently excluded — still reveal
        return
      }
    }
    ; Not ready — defer with pre-registered target
    WS_Pending[lParam + 0] := {mon: targetMon, tick: ppEntry.tick}
    fn := Func("WS_BackupPoll").Bind(lParam + 0)
    SetTimer, %fn%, -200
    fn2 := Func("WS_TimeoutPending").Bind(lParam + 0)
    SetTimer, %fn2%, -2000
    if (WS_Debug) {
      WinGetTitle, dbgTitle, ahk_id %lParam%
      WinGetClass, dbgClass, ahk_id %lParam%
      WS_Log("DEFERRED (create-path): hwnd=" . lParam . " """ . dbgTitle . """ class=" . dbgClass)
    }
    return
  }

  ; Fallback: no CREATE pre-registration (window missed by CREATE hook)
  if (WS_IsReady(lParam)) {
    if (WS_IsMovable(lParam)) {
      windowMon := GetMonitor("ahk_id " . lParam)
      if (windowMon != cursorMon) {
        WS_MoveToMonitor(lParam, windowMon, cursorMon)
        if (WS_Debug) {
          WinGetTitle, dbgTitle, ahk_id %lParam%
          WS_Log("MOVED (instant): """ . dbgTitle . """ mon " . windowMon . " -> " . cursorMon)
        }
      } else if (WS_Debug) {
        WinGetTitle, dbgTitle, ahk_id %lParam%
        WS_Log("OK (instant): """ . dbgTitle . """ already on mon " . windowMon)
      }
      WS_Reveal(lParam)  ; Safety net for CREATE-hidden windows consumed by SHOW before shell hook
      return
    }
    WinGetTitle, chkTitle, ahk_id %lParam%
    if (chkTitle != "") {
      WS_Reveal(lParam)  ; Permanently excluded but might be hidden
      return
    }
  }
  WS_Pending[lParam + 0] := {mon: cursorMon, tick: A_TickCount}
  fn := Func("WS_BackupPoll").Bind(lParam + 0)
  SetTimer, %fn%, -200
  fn2 := Func("WS_TimeoutPending").Bind(lParam + 0)
  SetTimer, %fn2%, -2000
  if (WS_Debug) {
    WinGetTitle, dbgTitle, ahk_id %lParam%
    WinGetClass, dbgClass, ahk_id %lParam%
    WS_Log("DEFERRED: hwnd=" . lParam . " """ . dbgTitle . """ class=" . dbgClass)
  }
}

; WinEvent callback — fires when any window becomes visible (SHOW) or uncloaked (UNCLOAK)
WS_OnWinEvent(hHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) {
  global WS_Pending, WS_PendingAltTab, WS_Debug, WS_PrePending, WS_QPCFreq, WS_Hidden, WS_OwnerSentinel
  ; WinEventProc uses 32-bit LONG params, but AHK reads 64-bit register slots on x64.
  ; Upper 32 bits may contain junk — mask to lower 32 before comparing.
  idObject := idObject & 0xFFFFFFFF
  idChild := idChild & 0xFFFFFFFF
  if (idObject != 0 || idChild != 0 || !hwnd)  ; OBJID_WINDOW = 0
    return
  SetWinDelay, -1
  hwnd := hwnd + 0  ; Ensure numeric type for consistent object key lookup

  ; --- Phase 10: CREATE pre-registration + early positioning ---
  if (event == 0x8000) {  ; EVENT_OBJECT_CREATE
    ; Filter to top-level root windows only (CREATE fires for all objects)
    if (DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != hwnd)  ; GA_ROOT=2
      return
    ; Skip transient windows with no class (message-only, DDE, internal Win32 objects)
    WinGetClass, _createClass, ahk_id %hwnd%
    if (_createClass == "")
      return
    if (WS_Debug) {
      WinGetClass, _dbgCls, ahk_id %hwnd%
      if (_dbgCls == "#32770") {
        _dbgKeys := ""
        for _k, _v in WS_Hidden
          _dbgKeys .= Format("{}({}) ", _k, _v)
        _dbgOwner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")
        WS_Log("CREATE-DIAG: hwnd=" . hwnd . " hex=" . Format("0x{:08X}", hwnd)
          . " class=" . _dbgCls . " owner=" . Format("0x{:08X}", _dbgOwner)
          . " HasKey=" . WS_Hidden.HasKey(hwnd) . " keys=[" . _dbgKeys . "]")
      }
    }
    if (WS_Hidden.HasKey(hwnd)) {
      if (WS_Debug) {
        WinGetClass, dbgClass, ahk_id %hwnd%
        WS_Log("CREATE-SKIP: hwnd=" . hwnd . " class=" . dbgClass . " (sentinel)")
      }
      return
    }
    ; Phase 10: Owner sentinel — if this window's owner was recently moved, skip (sibling protection)
    ppOwner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")  ; GW_OWNER=4
    if (ppOwner && WS_OwnerSentinel.HasKey(ppOwner + 0)) {
      if (A_TickCount - WS_OwnerSentinel[ppOwner + 0] < 200) {
        WS_Hidden[hwnd] := -1
        if (WS_Debug) {
          WinGetClass, dbgClass, ahk_id %hwnd%
          WS_Log("CREATE-SKIP-OWNER: hwnd=" . hwnd . " class=" . dbgClass
            . " owner=" . Format("0x{:08X}", ppOwner) . " (sibling sentinel)")
        }
        return
      }
    }
    if (ppOwner) {
      ; Owner already processed by us (sentinel) → skip child windows (e.g., WTL tab controls)
      if (WS_Hidden.HasKey(ppOwner + 0) && WS_Hidden[ppOwner + 0] == -1) {
        if (WS_Debug) {
          WinGetClass, dbgClass, ahk_id %hwnd%
          WS_Log("CREATE-SKIP-CHILD: hwnd=" . hwnd . " class=" . dbgClass
            . " owner=" . Format("0x{:08X}", ppOwner) . " (owner sentinel)")
        }
        return
      }
      WinGet, ppOwnerStyle, Style, ahk_id %ppOwner%
      if (ppOwnerStyle & 0x10000000)  ; Owner is WS_VISIBLE → real dialog, skip
        return
      ; Owner is hidden → treat as top-level (e.g., Win+R Run dialog)
    }
    cursorMon := GetCursorMonitor()
    windowMon := GetMonitor("ahk_id " . hwnd)
    WS_PrePending[hwnd] := {mon: cursorMon, tick: A_TickCount, qpc: WS_QPC()}
    ; Suppress visibility until shell hook does proper relative-position move then reveals.
    ; Window stays at its natural position — no pre-positioning, so WinGetPos is accurate later.
    ; Skip UWP/cloaked windows — they use DirectComposition, not GDI. DWM cloaking already hides them.
    ppDidHide := false
    if (windowMon && windowMon != cursorMon) {
      VarSetCapacity(ppCloaked, 4, 0)
      DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Ptr", &ppCloaked, "UInt", 4)
      if (!NumGet(ppCloaked, 0, "UInt")) {
        ppExStyle := DllCall("GetWindowLong", "Ptr", hwnd, "Int", -20)  ; GWL_EXSTYLE
        hadLayered := !!(ppExStyle & 0x80000)  ; WS_EX_LAYERED
        if (!hadLayered)
          DllCall("SetWindowLong", "Ptr", hwnd, "Int", -20, "Ptr", ppExStyle | 0x80000)
        DllCall("SetLayeredWindowAttributes", "Ptr", hwnd, "UInt", 0
          , "UChar", WS_Debug ? 128 : 0, "UInt", 0x2)  ; LWA_ALPHA: 50% debug, 0% normal
        WS_Hidden[hwnd] := hadLayered
        ppDidHide := true
      }
    }
    if (WS_Debug) {
      WinGetClass, dbgClass, ahk_id %hwnd%
      hideLabel := ppDidHide ? " hide" : ""
      WS_Log("CREATE: hwnd=" . hwnd . " class=" . dbgClass . hideLabel . " mon " . cursorMon
        . (windowMon && windowMon != cursorMon ? " (from " . windowMon . ")" : ""))
    }
    return
  }

  ; --- Phase 10: PrePending SHOW/UNCLOAK fast path ---
  if (WS_PrePending.HasKey(hwnd)) {
    ppEntry := WS_PrePending.Delete(hwnd)
    if (WS_Debug) {
      deltaTick := A_TickCount - ppEntry.tick
      deltaUs := Round((WS_QPC() - ppEntry.qpc) * 1000000 / WS_QPCFreq)
      evName := (event == 0x8002) ? "SHOW" : "UNCLOAK"
      WinGetTitle, dbgTitle, ahk_id %hwnd%
      WinGetClass, dbgClass, ahk_id %hwnd%
      WS_Log(evName . ": hwnd=" . hwnd . " """ . dbgTitle . """ class=" . dbgClass
        . " create-to-" . evName . "=" . deltaTick . "ms (" . deltaUs . "µs)")
    }
    ; Move to target using current (real) position — window was never pre-positioned
    if (WS_IsReady(hwnd) && WS_IsMovable(hwnd)) {
      windowMon := GetMonitor("ahk_id " . hwnd)
      if (windowMon != ppEntry.mon) {
        WS_MoveToMonitor(hwnd, windowMon, ppEntry.mon)
        if (WS_Debug) {
          elapsed := A_TickCount - ppEntry.tick
          WinGetTitle, dbgTitle, ahk_id %hwnd%
          WS_Log("MOVED (create-show): """ . dbgTitle . """ mon " . windowMon . " -> " . ppEntry.mon . " +" . elapsed . "ms")
        }
      } else if (WS_Debug) {
        WinGetTitle, dbgTitle, ahk_id %hwnd%
        WS_Log("OK (create-show): """ . dbgTitle . """ already on mon " . windowMon)
      }
      WS_Reveal(hwnd)
      ; Successfully processed — clean up any shell hook deferral too
      WS_Pending.Delete(hwnd)
      return
    }
    ; Not ready or not movable yet — fall through to WS_Pending handler
    ; (shell hook may have deferred this window; let existing logic handle it)
  }

  ; --- Pending creation moves ---
  if (WS_Pending.HasKey(hwnd)) {
    if (WS_IsReady(hwnd)) {
      if (WS_IsMovable(hwnd)) {
        entry := WS_Pending.Delete(hwnd)
        evName := (event == 0x8002) ? "show" : "uncloak"
        WS_ProcessPending(hwnd, entry.mon, evName, entry.tick)
      } else {
        ; Ready but not movable — discard if permanently excluded (has title)
        WinGetTitle, chkTitle, ahk_id %hwnd%
        if (chkTitle != "")
          WS_Pending.Delete(hwnd)
        ; else: no title yet — leave in pending for backup poll
      }
    }
    ; Not ready at all — leave in pending for UNCLOAK or backup poll
    return
  }

  ; --- Pending Alt+Tab ---
  if (WS_PendingAltTab != "") {
    WinGetClass, cls, ahk_id %hwnd%
    if (cls == "XamlExplorerHostIslandWindow") {
      entry := WS_PendingAltTab
      WS_PendingAltTab := ""
      windowMon := GetMonitor("ahk_id " . hwnd)
      if (windowMon != entry.mon)
        WS_MoveToMonitor(hwnd, windowMon, entry.mon)
    }
  }
}

; Process a deferred window that is now ready
WS_ProcessPending(hwnd, targetMon, source:="event", tick:=0) {
  global WS_Debug
  if (!WS_IsMovable(hwnd)) {
    WS_Reveal(hwnd)
    return
  }
  windowMon := GetMonitor("ahk_id " . hwnd)
  if (windowMon != targetMon) {
    WS_MoveToMonitor(hwnd, windowMon, targetMon)
    if (WS_Debug) {
      elapsed := tick ? A_TickCount - tick : 0
      WinGetTitle, dbgTitle, ahk_id %hwnd%
      WS_Log("MOVED (" . source . "): """ . dbgTitle . """ mon " . windowMon . " -> " . targetMon . " +" . elapsed . "ms")
    }
  }
  WS_Reveal(hwnd)
}

; Single backup poll — catches windows where WinEvent arrived but wasn't ready/movable yet
WS_BackupPoll(hwnd) {
  global WS_Pending, WS_Debug
  if (!WS_Pending.HasKey(hwnd))
    return
  SetWinDelay, -1
  if (WS_IsReady(hwnd)) {
    if (WS_IsMovable(hwnd)) {
      entry := WS_Pending.Delete(hwnd)
      WS_ProcessPending(hwnd, entry.mon, "poll", entry.tick)
      return
    }
    ; Ready but not movable — discard if permanently excluded (has title)
    WinGetTitle, chkTitle, ahk_id %hwnd%
    if (chkTitle != "") {
      WS_Pending.Delete(hwnd)
      WS_Reveal(hwnd)
    }
  }
}

; 2s safety net — last-ditch attempt, then discard
WS_TimeoutPending(hwnd) {
  global WS_Pending
  if (!WS_Pending.HasKey(hwnd))
    return
  entry := WS_Pending.Delete(hwnd)
  SetWinDelay, -1
  if (WS_IsReady(hwnd))
    WS_ProcessPending(hwnd, entry.mon, "timeout", entry.tick)
  else
    WS_Reveal(hwnd)  ; Safety net: reveal even if window never became ready
}

; Phase 10: Purge stale PrePending entries (windows created but never shown/hooked)
; Sentinel cleanup handled by HSHELL_WINDOWDESTROYED
WS_CleanPrePending:
  WS_staleKeys := []
  WS_now := A_TickCount
  for h, entry in WS_PrePending {
    if (WS_now - entry.tick > 500)
      WS_staleKeys.Push(h)
  }
  for i, k in WS_staleKeys {
    WS_PrePending.Delete(k)
    WS_Reveal(k)  ; Reveal windows that were hidden but never processed
  }
  ; Purge stale owner sentinels (200ms active window + 2s safety margin)
  WS_staleOwners := []
  for h, tick in WS_OwnerSentinel {
    if (WS_now - tick > 2000)
      WS_staleOwners.Push(h)
  }
  for i, k in WS_staleOwners
    WS_OwnerSentinel.Delete(k)
  ; Orphan sweep: reveal windows stuck in WS_Hidden that aren't tracked by PrePending/Pending
  WS_orphanKeys := []
  for h, val in WS_Hidden {
    if (val == -1)
      continue  ; Sentinel — already processed, cleaned by DESTROYED
    if (!WinExist("ahk_id " . h)) {
      WS_orphanKeys.Push(h)  ; Window gone — just remove
      continue
    }
    if (!WS_PrePending.HasKey(h) && !WS_Pending.HasKey(h)) {
      WS_orphanKeys.Push(h)
      if (WS_Debug)
        WS_Log("ORPHAN-REVEAL: hwnd=" . h)
      DllCall("SetLayeredWindowAttributes", "Ptr", h, "UInt", 0, "UChar", 255, "UInt", 0x2)
      if (!val)
        WinSet, ExStyle, -0x80000, ahk_id %h%
    }
  }
  for i, k in WS_orphanKeys
    WS_Hidden.Delete(k)
return

WS_IsReady(hwnd) {
  ; Window must still exist
  if !WinExist("ahk_id " . hwnd)
    return false
  ; Must be visible
  WinGet, style, Style, ahk_id %hwnd%
  if !(style & 0x10000000)  ; WS_VISIBLE
    return false
  ; Must not be cloaked (UWP pre-show transition)
  VarSetCapacity(cloaked, 4, 0)
  DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Ptr", &cloaked, "UInt", 4)
  if (NumGet(cloaked, 0, "UInt"))
    return false
  ; Must have non-zero size
  WinGetPos,,, w, h, ahk_id %hwnd%
  if (w <= 0 || h <= 0)
    return false
  return true
}

WS_IsMovable(hwnd) {
  global WS_ExcludedClasses
  ; Must have a title (transient/system windows often don't)
  WinGetTitle, title, ahk_id %hwnd%
  if (title == "")
    return false
  ; Skip owned windows whose owner is visible (dialogs should follow their parent)
  ; But allow owned windows with hidden owners (e.g., Win+R Run dialog owned by hidden shell)
  owner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")  ; GW_OWNER=4
  if (owner) {
    WinGet, ownerStyle, Style, ahk_id %owner%
    if (ownerStyle & 0x10000000)  ; Owner is WS_VISIBLE → real parent dialog
      return false
  }
  ; Skip tool windows (tooltips, floating toolbars)
  WinGet, exStyle, ExStyle, ahk_id %hwnd%
  if (exStyle & 0x80)  ; WS_EX_TOOLWINDOW
    return false
  ; Skip excluded window classes
  WinGetClass, cls, ahk_id %hwnd%
  if HasVal(WS_ExcludedClasses, cls)
    return false
  return true
}

WS_MoveToMonitor(hwnd, srcMon, tgtMon) {
  global WS_Hidden, WS_OwnerSentinel, WS_Debug
  ; Phase 10: Pre-set sentinel BEFORE any WinMove calls. WinMove triggers SetWindowPos
  ; which dispatches WinEvent callbacks synchronously — a duplicate CREATE event during the
  ; move would re-hide the window. Setting the sentinel first prevents this race condition.
  hwnd := hwnd + 0
  _wasHidden := false
  _hadLayered := 0
  if (WS_Hidden.HasKey(hwnd)) {
    _hadLayered := WS_Hidden[hwnd]
    if (_hadLayered != -1) {
      _wasHidden := true
    }
  }
  ; Always mark as processed — prevents late CREATE events from re-hiding this window.
  ; Covers windows that were never opacity-hidden (same monitor, cloaked, no monitor at CREATE time).
  WS_Hidden[hwnd] := -1
  if (WS_Debug) {
    _dbgKeys := ""
    for _k, _v in WS_Hidden
      _dbgKeys .= Format("{}({}) ", _k, _v)
    WS_Log("SENTINEL-SET: hwnd=" . hwnd . " hex=" . Format("0x{:08X}", hwnd)
      . " HasKey=" . WS_Hidden.HasKey(hwnd) . " keys=[" . _dbgKeys . "]")
  }
  ; Phase 10: Owner sentinel — protect sibling #32770 windows from re-hiding
  _moveOwner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")  ; GW_OWNER=4
  if (_moveOwner)
    WS_OwnerSentinel[_moveOwner + 0] := A_TickCount

  ; Get work areas (taskbar-aware) for both monitors
  SysGet, src, MonitorWorkArea, %srcMon%
  SysGet, tgt, MonitorWorkArea, %tgtMon%
  srcW := srcRight - srcLeft, srcH := srcBottom - srcTop
  tgtW := tgtRight - tgtLeft, tgtH := tgtBottom - tgtTop

  ; Get current window geometry (Phase 10: position is reliable — opacity approach preserves natural position)
  WinGetPos, winX, winY, winW, winH, ahk_id %hwnd%
  WinGet, minMax, MinMax, ahk_id %hwnd%
  if (WS_Debug)
    WS_Log("MOVE-START: hwnd=" . hwnd . " pos=" . winX . "," . winY . " size=" . winW . "x" . winH . " minMax=" . minMax)

  ; Minimized window: use GetWindowPlacement for real restored dimensions (WinGetPos returns ~160x28 at -32000,-32000)
  if (minMax == -1) {
    VarSetCapacity(_wp, 44, 0)
    NumPut(44, _wp, 0, "UInt")  ; cbSize
    DllCall("GetWindowPlacement", "Ptr", hwnd, "Ptr", &_wp)
    winW := NumGet(_wp, 36, "Int") - NumGet(_wp, 28, "Int")  ; rcNormalPosition width
    winH := NumGet(_wp, 40, "Int") - NumGet(_wp, 32, "Int")  ; rcNormalPosition height
    if (winW > tgtW)
      winW := tgtW
    if (winH > tgtH)
      winH := tgtH
    ; Center on target (no meaningful source-relative position for minimized windows)
    newX := tgtLeft + (tgtW - winW) // 2
    newY := tgtTop + (tgtH - winH) // 2
    WinRestore, ahk_id %hwnd%
    WinMove, ahk_id %hwnd%,, %newX%, %newY%, %winW%, %winH%
  } else if (minMax == 1) {
    ; Maximized window: restore, move to target, re-maximize
    WinRestore, ahk_id %hwnd%
    centerX := tgtLeft + (tgtW - winW) // 2
    centerY := tgtTop + (tgtH - winH) // 2
    WinMove, ahk_id %hwnd%,, %centerX%, %centerY%
    WinMaximize, ahk_id %hwnd%
  } else {
    ; Clamp window size to target work area
    if (winW > tgtW)
      winW := tgtW
    if (winH > tgtH)
      winH := tgtH

    ; Map relative position: source monitor -> target monitor
    relX := (winX - srcLeft) / srcW
    relY := (winY - srcTop) / srcH
    newX := Round(tgtLeft + relX * tgtW)
    newY := Round(tgtTop + relY * tgtH)

    ; Clamp to target bounds
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

  ; Phase 10: Restore opacity after move (window is now on correct monitor)
  if (_wasHidden) {
    DllCall("SetLayeredWindowAttributes", "Ptr", hwnd, "UInt", 0, "UChar", 255, "UInt", 0x2)
    if (!_hadLayered)
      WinSet, ExStyle, -0x80000, ahk_id %hwnd%
  }
}

; Phase 10: Restore opacity for a window hidden at CREATE time (idempotent — safe to call anytime)
WS_Reveal(hwnd) {
  global WS_Hidden
  hwnd := hwnd + 0  ; Ensure numeric key matches CREATE handler's storage
  if (!WS_Hidden.HasKey(hwnd)) {
    WS_Hidden[hwnd] := -1  ; Mark as processed even if never hidden
    return
  }
  hadLayered := WS_Hidden[hwnd]
  if (hadLayered == -1)
    return  ; Already revealed — sentinel prevents duplicate work
  WS_Hidden[hwnd] := -1  ; Mark as revealed (sentinel: CREATE handler checks this to avoid re-hiding)
  DllCall("SetLayeredWindowAttributes", "Ptr", hwnd, "UInt", 0, "UChar", 255, "UInt", 0x2)  ; LWA_ALPHA=2
  if (!hadLayered)
    WinSet, ExStyle, -0x80000, ahk_id %hwnd%  ; Remove WS_EX_LAYERED only if we added it
}

; Alt+Tab switcher doesn't trigger shell hooks (DWM overlay), so use WinEvent hook
~!Tab::
  targetMon := GetCursorMonitor()
  hwnd := WinExist("Task Switching ahk_class XamlExplorerHostIslandWindow")
  if (hwnd) {
    ; Already visible (fast re-press)
    windowMon := GetMonitor("ahk_id " . hwnd)
    if (windowMon != targetMon)
      WS_MoveToMonitor(hwnd, windowMon, targetMon)
  } else {
    ; Defer — WS_OnWinEvent catches the SHOW event
    WS_PendingAltTab := {mon: targetMon, tick: A_TickCount}
    SetTimer, WS_TimeoutAltTab, -500
  }
Return

WS_TimeoutAltTab:
  WS_PendingAltTab := ""
Return


WS_Cleanup() {
  global WS_HookHwnd, WS_EventHookShow, WS_EventHookUncloak, WS_EventHookCreate, WS_Hidden, WS_OwnerSentinel
  ; Reveal all hidden windows before shutting down (skip sentinels: -1 = already revealed)
  for h, hadLayered in WS_Hidden {
    if (hadLayered == -1)
      continue  ; Already revealed, nothing to restore
    DllCall("SetLayeredWindowAttributes", "Ptr", h, "UInt", 0, "UChar", 255, "UInt", 0x2)
    if (!hadLayered)
      WinSet, ExStyle, -0x80000, ahk_id %h%
  }
  WS_Hidden := {}
  WS_OwnerSentinel := {}
  DllCall("DeregisterShellHookWindow", "Ptr", WS_HookHwnd)
  Gui, ShellHook:Destroy
  if (WS_EventHookShow)
    DllCall("UnhookWinEvent", "Ptr", WS_EventHookShow)
  if (WS_EventHookUncloak)
    DllCall("UnhookWinEvent", "Ptr", WS_EventHookUncloak)
  if (WS_EventHookCreate)
    DllCall("UnhookWinEvent", "Ptr", WS_EventHookCreate)
  DllCall("ole32\CoUninitialize")
}

WS_QPC() {
  DllCall("QueryPerformanceCounter", "Int64*", count)
  return count
}

WS_Log(msg) {
  global WS_LogFile
  FileAppend, %A_Hour%:%A_Min%:%A_Sec% [%A_TickCount%] %msg%`n, %WS_LogFile%
}
