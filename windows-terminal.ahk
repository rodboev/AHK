; Windows Terminal scroll guard and hotkeys
; Always-on 50ms timer detects CC viewport hijacking (snaps to 0%/100%) and restores position
; ScrollLock toggle for indefinite lock, unfocused wheel forwarding

; ⇒ Initialize scroll guard globals and start timer
WTScrollInit() {
  global G_WTScrollLastPct, G_WTScrollLocked, G_WTScrollRestoreTick, G_WTScrollStatus
  G_WTScrollLastPct := -1
  G_WTScrollLocked := false
  G_WTScrollRestoreTick := 0
  G_WTScrollStatus := ""
  SetTimer, WTScrollGuard, 50
}

; ⇒ Check if cursor hovers over an unfocused Windows Terminal window
; Used as #If condition for forwarding wheel events to inactive WT
WTHoverCheck() {
  If (WinActive("ahk_exe WindowsTerminal.exe"))
    Return false
  If (!WinExist("ahk_exe WindowsTerminal.exe"))
    Return false
  MouseGetPos,,, _hwnd
  WinGet, _exe, ProcessName, ahk_id %_hwnd%
  Return (_exe = "WindowsTerminal.exe")
}

; ⇒ Get UIA RangeValuePattern for WT's vertical scrollbar
; Uses FindAll(ControlType=ScrollBar) to directly target ScrollBar.Vertical
; Caller must ObjRelease the returned pattern when done
WTGetScrollPattern() {
  global G_UIA
  Try {
    If (!G_UIA)
      G_UIA := ComObjCreate("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
    WinGet, _hwnd, ID, ahk_exe WindowsTerminal.exe
    If (!_hwnd)
      Return 0
    ; IUIAutomation::ElementFromHandle (vtable 6)
    _el := 0
    DllCall(NumGet(NumGet(G_UIA+0) + 6*A_PtrSize), "Ptr", G_UIA, "Ptr", _hwnd, "Ptr*", _el)
    If (!_el)
      Return 0
    ; Create condition: ControlType = ScrollBar (50029)
    VarSetCapacity(_var, 16, 0)
    NumPut(3, _var, 0, "UShort")
    NumPut(50029, _var, 8, "Int")
    _cond := 0
    ; IUIAutomation::CreatePropertyCondition (vtable 23)
    DllCall(NumGet(NumGet(G_UIA+0) + 23*A_PtrSize), "Ptr", G_UIA, "Int", 30003, "Ptr", &_var, "Ptr*", _cond)
    If (!_cond) {
      ObjRelease(_el)
      Return 0
    }
    ; IUIAutomationElement::FindAll (vtable 6), TreeScope_Descendants = 4
    _arr := 0
    DllCall(NumGet(NumGet(_el+0) + 6*A_PtrSize), "Ptr", _el, "Int", 4, "Ptr", _cond, "Ptr*", _arr)
    ObjRelease(_cond)
    ObjRelease(_el)
    If (!_arr)
      Return 0
    ; Iterate ScrollBar elements to find Name="Vertical"
    _len := 0
    DllCall(NumGet(NumGet(_arr+0) + 3*A_PtrSize), "Ptr", _arr, "Int*", _len)
    _pat := 0
    Loop, %_len% {
      _item := 0
      ; IUIAutomationElementArray::GetElement (vtable 4)
      DllCall(NumGet(NumGet(_arr+0) + 4*A_PtrSize), "Ptr", _arr, "Int", A_Index - 1, "Ptr*", _item)
      If (!_item)
        Continue
      _name := _GetUIAProp(_item, 30005)
      If (InStr(_name, "Vertical")) {
        ; IUIAutomationElement::GetCurrentPattern (vtable 16), RangeValuePattern = 10003
        DllCall(NumGet(NumGet(_item+0) + 16*A_PtrSize), "Ptr", _item, "Int", 10003, "Ptr*", _pat)
        ObjRelease(_item)
        Break
      }
      ObjRelease(_item)
    }
    ObjRelease(_arr)
    Return _pat
  }
  Return 0
}

; ⇒ Get WT vertical scroll position as percentage (0-100)
; Reads Value, Min, Max from ScrollBar.Vertical's RangeValuePattern
; Returns: -1 = not found/no scroll range, 0-100 = scroll position percentage
WTGetScrollPct() {
  ; Layer 3: RangeValuePattern on ScrollBar.Vertical (precise, line-unit based)
  _pat := WTGetScrollPattern()
  If (_pat) {
    _val := 0.0, _max := 0.0, _min := 0.0
    Try {
      ; IRangeValuePattern: get_CurrentValue (vtable 4)
      DllCall(NumGet(NumGet(_pat+0) + 4*A_PtrSize), "Ptr", _pat, "Double*", _val)
      ; IRangeValuePattern: get_CurrentMaximum (vtable 6)
      DllCall(NumGet(NumGet(_pat+0) + 6*A_PtrSize), "Ptr", _pat, "Double*", _max)
      ; IRangeValuePattern: get_CurrentMinimum (vtable 7)
      DllCall(NumGet(NumGet(_pat+0) + 7*A_PtrSize), "Ptr", _pat, "Double*", _min)
    } Finally {
      ObjRelease(_pat)
    }
    _range := _max - _min
    If (_range > 0)
      Return ((_val - _min) / _range) * 100
  }
  ; Layer 1 fallback: VerticalScrollPercent (30055) on root element
  global G_UIA
  Try {
    If (!G_UIA)
      Return -1
    WinGet, _hwnd, ID, ahk_exe WindowsTerminal.exe
    If (!_hwnd)
      Return -1
    _el := 0
    DllCall(NumGet(NumGet(G_UIA+0) + 6*A_PtrSize), "Ptr", G_UIA, "Ptr", _hwnd, "Ptr*", _el)
    If (!_el)
      Return -1
    Try {
      _pct := _GetUIAProp(_el, 30055)
      If (_pct != "" && _pct >= 0 && _pct <= 100)
        Return _pct
    } Finally {
      ObjRelease(_el)
    }
  }
  Return -1
}

; ⇒ Set WT vertical scroll position from percentage (0-100)
; Converts percentage back to raw value using current Min/Max range
WTSetScrollPct(pct) {
  _pat := WTGetScrollPattern()
  If (!_pat)
    Return
  Try {
    _max := 0.0, _min := 0.0
    ; IRangeValuePattern: get_CurrentMaximum (vtable 6)
    DllCall(NumGet(NumGet(_pat+0) + 6*A_PtrSize), "Ptr", _pat, "Double*", _max)
    ; IRangeValuePattern: get_CurrentMinimum (vtable 7)
    DllCall(NumGet(NumGet(_pat+0) + 7*A_PtrSize), "Ptr", _pat, "Double*", _min)
    _range := _max - _min
    If (_range > 0) {
      _raw := _min + (pct / 100) * _range
      ; IRangeValuePattern: SetValue (vtable 3)
      DllCall(NumGet(NumGet(_pat+0) + 3*A_PtrSize), "Ptr", _pat, "Double", _raw)
    }
  } Finally {
    ObjRelease(_pat)
  }
}

; ────────────────────────────────────────────────────────────
; Timer: Always-on scroll jump detection (50ms)
; ────────────────────────────────────────────────────────────

WTScrollGuard:
  Critical
  If (!WinActive("ahk_exe WindowsTerminal.exe"))
    Return  ; Don't clear status — Extended Spy may be reading cached values
  _pct := WTGetScrollPct()
  If (_pct = -1)
    Return
  ; === Always-on jump detection ===
  If (G_WTScrollLastPct != -1) {
    _delta := Abs(_pct - G_WTScrollLastPct)
    If (_delta > 30) {
      ; Jump to ~0%: CC header update — always restore
      If (_pct < 1 && G_WTScrollLastPct > 5) {
        WTSetScrollPct(G_WTScrollLastPct)
        G_WTScrollRestoreTick := A_TickCount
        Return  ; Don't update LastPct with the hijacked position
      }
      ; Jump to ~100%: CC auto-scroll — restore only if not initiated by input
      If (_pct > 99 && G_WTScrollLastPct < 95 && A_TimeIdlePhysical > 2000) {
        WTSetScrollPct(G_WTScrollLastPct)
        G_WTScrollRestoreTick := A_TickCount
        Return
      }
    }
  }
  ; === ScrollLock: freeze at locked position ===
  If (G_WTScrollLocked) {
    If (G_WTScrollLastPct != -1 && _pct != G_WTScrollLastPct)
      WTSetScrollPct(G_WTScrollLastPct)
    G_WTScrollStatus := "LOCKED"
    Return
  }
  ; Normal: track position continuously (small per-tick deltas follow gradual scroll)
  G_WTScrollLastPct := _pct
  ; Brief restore status (1.5s after a restore)
  If (G_WTScrollRestoreTick && (A_TickCount - G_WTScrollRestoreTick) < 1500) {
    G_WTScrollStatus := "Restored " Round(G_WTScrollLastPct, 0) "%"
  } Else {
    If (G_WTScrollRestoreTick)
      G_WTScrollRestoreTick := 0
    G_WTScrollStatus := ""
  }
Return

; ────────────────────────────────────────────────────────────
; Hotkeys
; ────────────────────────────────────────────────────────────

; ⇒ Windows Terminal
#IfWinActive ahk_exe WindowsTerminal.exe
  ^n::Send ^+t ; [ Ctrl+N] -> New tab

  ScrollLock:: ; [ ScrollLock ] -> Toggle indefinite scroll position lock
    G_WTScrollLocked := !G_WTScrollLocked
    If (G_WTScrollLocked) {
      G_WTScrollLastPct := WTGetScrollPct()
      G_WTScrollStatus := "LOCKED (ScrollLock to unlock)"
    } Else {
      G_WTScrollStatus := ""
    }
  Return
#IfWinActive

; ⇒ Scroll unfocused WT windows (forward wheel events when cursor hovers over inactive WT)
#If WTHoverCheck()
  WheelUp::
  WheelDown::
    CoordMode, Mouse, Screen
    MouseGetPos, _mx, _my, _hwnd
    _delta := InStr(A_ThisHotkey, "Up") ? 120 : -120
    _wParam := ((_delta & 0xFFFF) << 16)
    _lParam := ((_my & 0xFFFF) << 16) | (_mx & 0xFFFF)
    PostMessage, 0x20A, %_wParam%, %_lParam%,, ahk_id %_hwnd%
  Return
#If
