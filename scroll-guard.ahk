; Windows Terminal scroll guard and hotkeys
; Always-on 50ms timer detects CC viewport hijacking (snaps to 0%/100%) and restores position
; ScrollLock toggle for indefinite lock, unfocused wheel forwarding

; ⇒ Initialize scroll guard globals and start timer
SG_ScrollInit() {
  global SG_ScrollLastPct, SG_ScrollLocked, SG_ScrollRestoreTick, SG_ScrollStatus, SG_ScrollDiag
  SG_ScrollLastPct := -1
  SG_ScrollLocked := false
  SG_ScrollRestoreTick := 0
  SG_ScrollStatus := ""
  SG_ScrollDiag := ""
  SetTimer, SG_ScrollGuard, 50
}

; ────────────────────────-─────────
; === PERSISTENT JUMP PREVENTION ===
; ────────────────────────-─────────
; [ always on ] => Checks every 30s
SG_ScrollGuard:
  Critical
  If (!WinActive("ahk_exe WindowsTerminal.exe"))
    Return  ; Don't clear status — Extended Spy may be reading cached values
  _pct := SG_GetScrollPct()
  If (_pct = -1)
    Return
  ; === Always-on jump detection ===
  If (SG_ScrollLastPct != -1) {
    _delta := Abs(_pct - SG_ScrollLastPct)
    If (_delta > 30) {
      ; Jump to ~0%: CC header update — always restore
      If (_pct < 1 && SG_ScrollLastPct > 5) {
        SG_SetScrollPct(SG_ScrollLastPct)
        SG_ScrollRestoreTick := A_TickCount
        Return  ; Don't update LastPct with the hijacked position
      }
      ; Jump to ~100%: CC auto-scroll — restore only if not initiated by input
      If (_pct > 99 && SG_ScrollLastPct < 95 && A_TimeIdlePhysical > 2000) {
        SG_SetScrollPct(SG_ScrollLastPct)
        SG_ScrollRestoreTick := A_TickCount
        Return
      }
    }
  }
  ; === ScrollLock: freeze at locked position ===
  If (SG_ScrollLocked) {
    If (SG_ScrollLastPct != -1 && _pct != SG_ScrollLastPct)
      SG_SetScrollPct(SG_ScrollLastPct)
    SG_ScrollStatus := "LOCKED"
    Return
  }
  ; Normal: track position continuously (small per-tick deltas follow gradual scroll)
  SG_ScrollLastPct := _pct
  ; Brief restore status (1.5s after a restore)
  If (SG_ScrollRestoreTick && (A_TickCount - SG_ScrollRestoreTick) < 1500) {
    SG_ScrollStatus := "Restored " Round(SG_ScrollLastPct, 0) "%"
  } Else {
    If (SG_ScrollRestoreTick)
      SG_ScrollRestoreTick := 0
    SG_ScrollStatus := ""
  }
Return

; ────────────────────────-────────
; === UIA ScrollPattern helpers ===
; ────────────────────────-────────
; ⇒ Get UIA ScrollPattern for WT via ElementFromHandle
; Caller must ObjRelease the returned pattern when done
SG_GetScrollPattern() {
  global SG_ScrollDiag
  Try {
    targetForUIA := MB_Ctrl ? MB_Ctrl : MB_Win
    WinGet, _hwnd, ID, ahk_exe WindowsTerminal.exe
    If (!_hwnd) {
      SG_ScrollDiag := "no hwnd"
      Return 0
    }
    _el := 0
    ; IUIAutomation::ElementFromHandle (vtable 6)
    DllCall(NumGet(NumGet(G_UIA+0) + 6*A_PtrSize), "Ptr", G_UIA, "Ptr", _hwnd, "Ptr*", _el)
    If (!_el) {
      SG_ScrollDiag := "no element"
      Return 0
    }
    _pat := 0
    Try {
      ; IUIAutomationElement::GetCurrentPattern (vtable 16), ScrollPattern = 10004
      DllCall(NumGet(NumGet(_el+0) + 16*A_PtrSize), "Ptr", _el, "Int", 10004, "Ptr*", _pat)
    } Finally {
      ObjRelease(_el)
    }
    SG_ScrollDiag := _pat ? "ok" : "no ScrollPattern"
    Return _pat
  }
  SG_ScrollDiag := "exception"
  Return 0
}

; ⇒ Get WT vertical scroll position as percentage (0-100)
; Reads VerticalScrollPercent from ScrollPattern (returns -1 for NoScroll)
SG_GetScrollPct() {
  global SG_ScrollDiag
  _pat := SG_GetScrollPattern()
  If (!_pat)
    Return -1
  _pct := 0.0
  Try {
    ; IScrollPattern::get_CurrentVerticalScrollPercent (vtable 6)
    DllCall(NumGet(NumGet(_pat+0) + 6*A_PtrSize), "Ptr", _pat, "Double*", _pct)
  } Finally {
    ObjRelease(_pat)
  }
  SG_ScrollDiag .= " | pct=" Round(_pct, 1)
  If (_pct < 0)  ; -1 = NoScroll sentinel (content fits viewport)
    Return -1
  Return _pct
}

; ⇒ Set WT vertical scroll position from percentage (0-100)
; Uses ScrollPattern::SetScrollPercent(-1, pct) — -1 means no horizontal change
SG_SetScrollPct(pct) {
  _pat := SG_GetScrollPattern()
  If (!_pat)
    Return
  Try {
    ; IScrollPattern::SetScrollPercent (vtable 4), -1.0 = no horizontal change
    DllCall(NumGet(NumGet(_pat+0) + 4*A_PtrSize), "Ptr", _pat, "Double", -1.0, "Double", pct)
  } Finally {
    ObjRelease(_pat)
  }
}

; ────────────────────────────────────────────────────────────
; Hotkeys
; ────────────────────────────────────────────────────────────

; ⇒ Windows Terminal
#IfWinActive ahk_exe WindowsTerminal.exe
  ^n::Send ^+t ; [ Ctrl+N] -> New tab

  ScrollLock:: ; [ ScrollLock ] -> Toggle indefinite scroll position lock
    SG_ScrollLocked := !SG_ScrollLocked
    If (SG_ScrollLocked) {
      SG_ScrollLastPct := SG_GetScrollPct()
      SG_ScrollStatus := "LOCKED (ScrollLock to unlock)"
    } Else {
      SG_ScrollStatus := ""
    }
  Return
#IfWinActive

; ⇒ Scroll unfocused WT windows (forward wheel events when cursor hovers over inactive WT)
#If SG_HoverCheck()
  WheelUp::
  WheelDown::
  ~LButton::
  ~MButton::
    CoordMode, Mouse, Screen
    MouseGetPos, _mx, _my, _hwnd
    _delta := InStr(A_ThisHotkey, "Up") ? 120 : -120
    _wParam := ((_delta & 0xFFFF) << 16)
    _lParam := ((_my & 0xFFFF) << 16) | (_mx & 0xFFFF)
    PostMessage, 0x20A, %_wParam%, %_lParam%,, ahk_id %_hwnd%
  Return
#If

; ⇒ Check if cursor hovers over an unfocused Windows Terminal window
; Used as #If condition for unfocused wheel forwarding above
SG_HoverCheck() {
  If (WinActive("ahk_exe WindowsTerminal.exe"))
    Return false
  If (!WinExist("ahk_exe WindowsTerminal.exe"))
    Return false
  MouseGetPos,,, _hwnd
  WinGet, _exe, ProcessName, ahk_id %_hwnd%
  Return (_exe = "WindowsTerminal.exe")
}
