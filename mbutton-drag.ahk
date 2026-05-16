; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === MIDDLE-BUTTON SMOOTH-SCROLL === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; Description: Smooth, fractional scrolling in Explorer (and all other apps system-wide)
; on middle mouse button drag, mimicking Chrome's behavior as closely as possible.
; Permalink (latest): https://github.com/rodboev/AHK/
; Forum thread: https://autohotkey.com/boards/viewtopic.php?t=43715
; Author: @rodboev
; Version: 4.0

; -> [ MButton + drag ] -> Invoke smooth scrolling on any app; release to stop.
*MButton::
  global MB, Debug

  ; Core session state
  MB := { Threshold: 2
    , X1: 0, Y1: 0
    , Win: 0, Ctrl: 0
    , ClassName: "", ProcName: ""
    , Triggered: 0, Disabled: 0, DeferredDown: 0
    , Method: "VSCROLL", FallbackChecked: 0, ScrollBarChecked: 0
    , ScrollTicks: 0, SessionStart: 0 }

  ; UIA state (COM pointers and scroll accumulators)
  MB.UIA := {Pattern: 0, Element: 0, ViewSize: 10.0, ViewSizeH: 10.0, AccumPct: -1, AccumPctH: -1}

  ; Native scroll probe state
  MB.Probe := {Active: 0, InitScrollPos: 0, InitScrollPct: 0.0, InitScrollPctH: 0.0, InitHCursor: 0}

  ; LVM (SysListView32) state
  MB.LVM := {Detected: 0, RowQuantized: 0, RowHeight: 20, DetectConfident: 0, BoundaryY: 0}

  ; EMA axis tracking (for row-quantized LVM)
  MB.EMA := {Y: 0.0, X: 0.0, PrevDistY: 0, PrevDistX: 0}

  ; Cursor state
  MB.Cursor := {Active: 0, Pending: 0}

  ; ===========================================
  ; UI Automation (UIA) — Lazy init on first MButton use
  ; Docs: https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-entry
  ; ===========================================
  ; COM Class/Interface (from UIAutomationClient.h)
  ;   CLSID_CUIAutomation = {ff48dba4-60ef-4201-aa87-54103eef594e}
  ;   IID_IUIAutomation   = {30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}

  global G_UIA  ; Singleton: UIA root object (persists across sessions)
  If (!G_UIA) {
    G_UIA := ComObjCreate("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
    OnExit("G_UIACleanup")  ; Register cleanup (G_UIACleanup defined in AutoHotkey.ahk)
  }

  ; SizeAll cursor: load once, reused across sessions
  global G_hSizeAll  ; Singleton: cursor handle
  If (!G_hSizeAll)
    G_hSizeAll := DllCall("LoadCursor", "Ptr", 0, "Ptr", 32646, "Ptr")  ; IDC_SIZEALL

  MouseGetPos,,, _win, _className
  MB.Win := _win, MB.ClassName := _className
  WinGetClass, _winClass, ahk_id %_win%
  MB.WinClass := _winClass

  ; EXCLUDED CONTROLS (toolbars, edit boxes, headers — never scroll these)
  _excludedControls := ["ToolbarWindow", "ReBarWindow", "Edit", "AddressBandRoot", "statusbar", "SysHeader", "Shell_TrayWnd", "Shell_SecondaryTrayWnd"]
  If (HasVal(_excludedControls, MB.ClassName)) {
    MB.Disabled := 1
    SendInput, {Blind}{MButton Down}
    Return
  }

  ; Capture cursor handle before passing MButton to app (Chrome changes cursor immediately)
  ; Uses HCURSOR handle (not A_Cursor name) to detect custom cursor changes
  VarSetCapacity(ci, 16 + A_PtrSize, 0)
  NumPut(16 + A_PtrSize, ci, 0, "UInt")
  DllCall("GetCursorInfo", "Ptr", &ci)
  MB.Probe.InitHCursor := NumGet(ci, 8, "UPtr")
  MB.Probe.InitCursorUnknown := (A_Cursor = "Unknown")

  ; Defer MButton Down for Explorer and custom-rendered apps (no Win32 controls)
  ; Explorer: prevents click actions during scroll (e.g., navbar opens tab)
  ; Custom apps (Sublime, etc.): prevents unwanted side effects and allows WHEEL to work
  ;   without app-specific mouse capture requirements
  If (MB.WinClass = "CabinetWClass" or !MB.ClassName) {
    MB.DeferredDown := 1
  } Else {
    SendInput, {Blind}{MButton Down}
  }
  MB.Disabled := 0

  ; Activate Explorer window if clicking on inactive one
  _mbWin := MB.Win
  If (MB.WinClass = "CabinetWClass") {
    WinGet, activeWin, ID, A
    If (_mbWin != activeWin) {
      WinActivate, ahk_id %_mbWin%
    }
  }

  ; Capture initial mouse coords
  CoordMode, Mouse, Screen
  MouseGetPos, _x1, _y1
  MB.X1 := _x1, MB.Y1 := _y1

  ; Get control window handle (hwnd) and process name for logging
  _mbClassName := MB.ClassName
  ControlGet, _ctrl, Hwnd,, %_mbClassName%, ahk_id %_mbWin%
  WinGet, _procName, ProcessName, ahk_id %_mbWin%
  MB.Ctrl := _ctrl, MB.ProcName := _procName
  MB.Triggered := 0
  MB.ScrollTicks := 0
  MB.SessionStart := A_TickCount

  ; TreeView controls -> direct to VSCROLL (skip native probe, never has native MButton scroll)
  If (InStr(MB.ClassName, "SysTreeView32")) {
    MB.Method := "VSCROLL"
    MB.Probe.Active := 0
    ; If scrollbar exists, show cursor immediately; otherwise verify on scroll
    If (HasWin32Scrollbar(MB.Ctrl)) {
      MB.Cursor.Active := 1
      SetDragCursor()
    } Else {
      MB.Cursor.Pending := 1
    }
    SetTimer, MBDragTimer, 150
    Return
  }

  ; SysListView32 controls -> direct to LVM_SCROLL for pixel-level precision
  ; UIA SetScrollPercent causes jitter on short lists (percentage rounds to discrete positions)
  If (InStr(MB.ClassName, "SysListView32")) {
    MB.Method := "LVM"
    MB.Probe.Active := 0
    ; Get control handle for scrollbar check
    ControlGet, _lvmCtrl, Hwnd,, %_mbClassName%, ahk_id %_mbWin%
    ; If any scrollbar exists (vertical OR horizontal), show cursor immediately
    If (HasWin32Scrollbar(_lvmCtrl, "any")) {
      MB.Cursor.Active := 1
      SetDragCursor()
    } Else {
      MB.Cursor.Pending := 1
    }
    If (Debug.Tooltips["mbutton-drag"])
      ToolTip, % "SysListView32 -> LVM_SCROLL (pixel-level)"
    If (Debug.Log["mbutton-drag"]) {
      FileAppend, % TS() " | mbutton-drag | START | proc=" MB.ProcName " method=LVM ctrl=" MB.ClassName "`n", % Debug.Log.Path
    }
    SetTimer, MBDragTimer, 10
    Return
  }

  ; SET UP UIA (for both native scroll detection and potential custom scroll)
  ; Use FindScrollableChild to enumerate child windows and find one with ScrollPattern.

  ; Dump control tree for debugging (Explorer, Windows Terminal)
  If (Debug.Log["mbutton-drag"] and (MB.WinClass = "CabinetWClass" or MB.WinClass = "CASCADIA_HOSTING_WINDOW_CLASS")) {
    FileAppend, % TS() " | mbutton-drag | CONTROL_TREE | win=" MB.Win " class=" MB.WinClass "`n", % Debug.Log.Path
    LogControlTree(MB.Win)
    FileAppend, % "--- END TREE ---`n", % Debug.Log.Path
  }

  _scrollChild := FindScrollableChild(MB.Win, MB.X1, MB.Y1)
  _scrollElement := 0
  _pattern := 0
  _fallback := 0
  If (_scrollChild) {
    DllCall(NumGet(NumGet(G_UIA+0)+6*A_PtrSize), "Ptr", G_UIA, "Ptr", _scrollChild, "Ptr*", _scrollElement)
    If (_scrollElement) {
      DllCall(NumGet(NumGet(_scrollElement+0)+16*A_PtrSize), "Ptr", _scrollElement, "Int", 10004, "Ptr*", _pattern)
      If (!_pattern) {
        ObjRelease(_scrollElement)
        _scrollElement := 0
      }
    }
  }
  ; Fallback: if no scrollable child found, try the control/window itself
  If (!_pattern) {
    _fallback := 1
    _targetHwnd := MB.Ctrl ? MB.Ctrl : MB.Win
    DllCall(NumGet(NumGet(G_UIA+0)+6*A_PtrSize), "Ptr", G_UIA, "Ptr", _targetHwnd, "Ptr*", _scrollElement)
    If (_scrollElement) {
      DllCall(NumGet(NumGet(_scrollElement+0)+16*A_PtrSize), "Ptr", _scrollElement, "Int", 10004, "Ptr*", _pattern)
      If (!_pattern) {
        ObjRelease(_scrollElement)
        _scrollElement := 0
      }
    }
  }

  If (Debug.Log["mbutton-drag"])
    FileAppend, % TS() " | mbutton-drag | UIA_SETUP | scrollChild=" _scrollChild " scrollElement=" _scrollElement " pattern=" _pattern " fallback=" _fallback "`n", % Debug.Log.Path

  MB.UIA.Element := _scrollElement
  MB.UIA.Pattern := _pattern
  If (_pattern) {
    DllCall(NumGet(NumGet(_pattern+0)+8*A_PtrSize), "Ptr", _pattern, "Double*", _viewSize)
    MB.UIA.ViewSize := (_viewSize < 1) ? 10.0 : _viewSize
    ; Horizontal ViewSize (vtable offset 7)
    DllCall(NumGet(NumGet(_pattern+0)+7*A_PtrSize), "Ptr", _pattern, "Double*", _viewSizeH)
    MB.UIA.ViewSizeH := (_viewSizeH < 1) ? 10.0 : _viewSizeH
  }

  ; Capture initial scroll state for native detection
  probeTarget := MB.Ctrl ? MB.Ctrl : MB.Win
  MB.Probe.InitScrollPos := GetScrollPos(probeTarget)
  MB.Probe.InitScrollPct := -1.0
  MB.Probe.InitScrollPctH := -1.0
  _pattern := MB.UIA.Pattern
  If (_pattern) {
    DllCall(NumGet(NumGet(_pattern+0)+6*A_PtrSize), "Ptr", _pattern, "Double*", _initPct)
    DllCall(NumGet(NumGet(_pattern+0)+5*A_PtrSize), "Ptr", _pattern, "Double*", _initPctH)
    MB.Probe.InitScrollPct := _initPct
    MB.Probe.InitScrollPctH := _initPctH
  }

  ; Show SizeAll cursor on MButton down IF area appears scrollable
  ; Strategy: Check multiple signals for scrollability
  ; 1. GetScrollInfo on target controls (works for standard Win32)
  ; 2. Find visible ScrollBar controls in window tree (works for Explorer DirectUIHWND)
  ; UIA ViewSize is unreliable - it reports 35-55% even when not scrollable
  MB.Cursor.Pending := 0
  _hasScrollRange := 0

  ; Try GetScrollInfo on scrollChild and probeTarget
  _scrollRangeTarget := _scrollChild ? _scrollChild : probeTarget
  _hasScrollRange := HasScrollRange(_scrollRangeTarget, "any")
  If (!_hasScrollRange and _scrollRangeTarget != probeTarget)
    _hasScrollRange := HasScrollRange(probeTarget, "any")

  ; For Explorer and similar: look for actual ScrollBar controls with scroll range
  If (!_hasScrollRange) {
    _visibleScrollBar := FindVisibleScrollBar(MB.Win)
    If (_visibleScrollBar) {
      _hasScrollRange := 1
      If (Debug.Log["mbutton-drag"]) {
        FileAppend, % TS() " | mbutton-drag | SCROLLBAR_VISIBLE | hwnd=" _visibleScrollBar "`n", % Debug.Log.Path
        ; Dump full window tree to diagnose false positives (scrollbar not in click area)
        FileAppend, % TS() " | mbutton-drag | TREE_START | win=" MB.Win " click=" MB.X1 "," MB.Y1 "`n", % Debug.Log.Path
        DumpWindowTree(MB.Win, 0, MB.X1, MB.Y1)
        FileAppend, % TS() " | mbutton-drag | TREE_END |`n", % Debug.Log.Path
      }
    }
  }

  ; For UWP/XAML apps (Windows Terminal, etc.): walk UIA tree from cursor position
  ; ElementFromHandle on the window doesn't find XAML ScrollViewers, but ElementFromPoint does
  ; Search UIA tree for scrollability (works for UWP/XAML apps like Windows Terminal)
  If (!_hasScrollRange and !MB.UIA.Pattern) {
    _ancestorResult := FindUIAScrollAncestor(MB.X1, MB.Y1)
    If (IsObject(_ancestorResult)) {
      If (_ancestorResult.pattern) {
        ; Found ScrollPattern via ancestor walk - use it for scrolling
        MB.UIA.Pattern := _ancestorResult.pattern
        MB.UIA.Element := _ancestorResult.element
        MB.UIA.ViewSize := (_ancestorResult.viewV < 1) ? 10.0 : _ancestorResult.viewV
        MB.UIA.ViewSizeH := (_ancestorResult.viewH < 1) ? 10.0 : _ancestorResult.viewH
        _hasScrollRange := 1
        If (Debug.Log["mbutton-drag"])
          FileAppend, % TS() " | mbutton-drag | UIA_ANCESTOR_USED | pattern=" MB.UIA.Pattern " viewV=" Round(MB.UIA.ViewSize, 1) "`n", % Debug.Log.Path
      } Else If (_ancestorResult.scrollable) {
        ; Found XAML ScrollBar with Maximum > 0 - scrollable but no pattern (use WHEEL_CTRL)
        _hasScrollRange := 1
        If (_ancestorResult.scrollbar)
          ObjRelease(_ancestorResult.scrollbar)  ; Don't need to keep reference
        If (Debug.Log["mbutton-drag"])
          FileAppend, % TS() " | mbutton-drag | UIA_SCROLLBAR_FOUND | maximum=" _ancestorResult.maximum "`n", % Debug.Log.Path
      }
    }
  }

  If (_hasScrollRange and !MB.Probe.InitCursorUnknown) {
    ; Win32 confirms scroll range exists — show immediately
    MB.Cursor.Active := 1
    SetDragCursor()
    If (Debug.Log["mbutton-drag"])
      FileAppend, % TS() " | mbutton-drag | CURSOR_DOWN | scrollRange=1`n", % Debug.Log.Path
  } Else If (_hasScrollRange and MB.Probe.InitCursorUnknown) {
    ; App already has a custom cursor (likely native autoscroll from prior click) — defer
    MB.Cursor.Pending := 1
    If (Debug.Log["mbutton-drag"])
      FileAppend, % TS() " | mbutton-drag | CURSOR_DEFERRED | scrollRange=1 initCursorUnknown=1`n", % Debug.Log.Path
  } Else If (MB.UIA.Pattern) {
    ; Has UIA pattern but no Win32 scrollbar detected — defer cursor until scroll verified
    MB.Cursor.Pending := 1
    If (Debug.Log["mbutton-drag"])
      FileAppend, % TS() " | mbutton-drag | CURSOR_PENDING | pattern=" MB.UIA.Pattern " viewV=" Round(MB.UIA.ViewSize, 1) " noScrollBar`n", % Debug.Log.Path
  } Else {
    ; No UIA pattern and no scrollbar — skip cursor entirely
    If (Debug.Log["mbutton-drag"])
      FileAppend, % TS() " | mbutton-drag | CURSOR_SKIP | noPattern noScrollBar`n", % Debug.Log.Path
  }

  ; Start timer in native probe mode
  MB.Probe.Active := 1
  SetTimer, MBDragTimer, 10
Return 

MBDragTimer:
  Critical ; Prevent MButton Up from interrupting mid-DllCall (race condition safety)
  global MB, G_hSizeAll, Debug

  ; Safety check: if MButton released, stop immediately
  If !GetKeyState("MButton", "P") {
    SetTimer, MBDragTimer, Off
    ; Release UIA resources (edge case: MButton Up didn't fire)
    If (MB.UIA.Pattern) {
      ObjRelease(MB.UIA.Pattern)
      MB.UIA.Pattern := 0
    }
    If (MB.UIA.Element) {
      ObjRelease(MB.UIA.Element)
      MB.UIA.Element := 0
    }
    ; Restore cursor if we changed it
    If (MB.Cursor.Active) {
      DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)
      MB.Cursor.Active := 0
    }
    MB.Cursor.Pending := 0
    If (Debug.Tooltips["mbutton-drag"])
      ToolTip
    Return
  }

  ; ===== NATIVE SCROLL PROBE PHASE =====
  ; Detect if the app handles MButton drag-scroll natively.
  ; Three signals: cursor change, Win32 scroll pos, UIA scroll percent.
  ; Movement-gated: cursor checked every tick; concludes at threshold (1px).
  If (MB.Probe.Active > 0) {
    nativeDetected := false

    ; Signal 1: Cursor change indicates native scroll handling
    ; Case A: App set a custom cursor (e.g., Chrome autoscroll icon) — A_Cursor = "Unknown"
    ; Case B: App had a custom cursor on MButton Down and dismissed it — cursor reverted to standard
    VarSetCapacity(ci, 16 + A_PtrSize, 0)
    NumPut(16 + A_PtrSize, ci, 0, "UInt")
    DllCall("GetCursorInfo", "Ptr", &ci)
    If (NumGet(ci, 8, "UPtr") != MB.Probe.InitHCursor and A_Cursor = "Unknown")
      nativeDetected := true
    If (!nativeDetected and MB.Probe.InitCursorUnknown and A_Cursor != "Unknown")
      nativeDetected := true

    If (!nativeDetected) {
      CoordMode, Mouse, Screen
      MouseGetPos, probeX, probeY
      probeDragY := Abs(probeY - MB.Y1)
      probeDragX := Abs(probeX - MB.X1)
      probeDrag := (probeDragY > probeDragX) ? probeDragY : probeDragX

      ; Signals 2 & 3: check after 3px (filters cursor jitter)
      If (probeDrag >= 3) {
        ; Signal 2: Win32 scroll position changed
        probeTarget := MB.Ctrl ? MB.Ctrl : MB.Win
        currentScrollPos := GetScrollPos(probeTarget)
        If (currentScrollPos != MB.Probe.InitScrollPos)
          nativeDetected := true

        ; Signal 3: UIA scroll percent changed
        _pattern := MB.UIA.Pattern
        If (!nativeDetected and _pattern) {
          DllCall(NumGet(NumGet(_pattern+0)+6*A_PtrSize), "Ptr", _pattern, "Double*", currentPct)
          If (currentPct != MB.Probe.InitScrollPct)
            nativeDetected := true
        }
      }

      ; Keep probing until movement threshold reached
      If (!nativeDetected and probeDrag < MB.Threshold)
        Return
    }

    If (nativeDetected) {
      ; App handles MButton scroll natively — stay passive
      MB.Disabled := 1
      ; Restore cursor if we changed it
      If (MB.Cursor.Active) {
        DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)  ; SPI_SETCURSORS
        MB.Cursor.Active := 0
      }
      If (MB.UIA.Pattern) {
        ObjRelease(MB.UIA.Pattern)
        MB.UIA.Pattern := 0
      }
      If (MB.UIA.Element) {
        ObjRelease(MB.UIA.Element)
        MB.UIA.Element := 0
      }
      SetTimer, MBDragTimer, Off
      If (Debug.Tooltips["mbutton-drag"]) {
        VarSetCapacity(ci2, 16 + A_PtrSize, 0)
        NumPut(16 + A_PtrSize, ci2, 0, "UInt")
        DllCall("GetCursorInfo", "Ptr", &ci2)
        ToolTip, % "Native scroll detected (hCursor=" NumGet(ci2, 8, "UPtr") " was=" MB.Probe.InitHCursor ")"
      }
      Return
    }

    ; No native scroll — engage custom scroll
    MB.Probe.Active := 0
    If (MB.UIA.Pattern) {
      MB.Method := "UIA"
      ; Cursor remains pending — UIA ViewSize is unreliable for scrollability detection
      ; Cursor will be shown when actual scroll is verified (position changes)
    } Else {
      ; WHEEL/WHEEL_CTRL — keep cursor pending until first scroll movement confirmed
      If (MB.UIA.Element) {
        ObjRelease(MB.UIA.Element)
        MB.UIA.Element := 0
      }
      MB.Method := "WHEEL"
    }
    If (Debug.Tooltips["mbutton-drag"])
      ToolTip, % "No native scroll — using " MB.Method
    ; Log session start
    If (Debug.Log["mbutton-drag"])
      FileAppend, % TS() " | mbutton-drag | START | proc=" MB.ProcName " method=" MB.Method " ctrl=" MB.ClassName " pattern=" MB.UIA.Pattern " viewV=" MB.UIA.ViewSize " viewH=" MB.UIA.ViewSizeH " click=" MB.X1 "," MB.Y1 "`n", % Debug.Log.Path
    ; Fall through to custom scroll logic below
  }

  CoordMode, Mouse, Screen
  MouseGetPos, _x2, _y2
  SignedDistY := _y2 - MB.Y1
  SignedDistX := _x2 - MB.X1
  AbsDistY := Abs(SignedDistY)
  AbsDistX := Abs(SignedDistX)

  If (AbsDistY >= MB.Threshold or AbsDistX >= MB.Threshold) {
    If (!MB.Triggered)
      MB.Triggered := 1
    ; UIA uses gentler curve (0.8), non-UIA uses steeper curve (1.2) for more responsiveness
    ; UIA: gentle curve throughout; non-UIA: gentle start, steep at distance
    _steepCurve := (MB.Method != "UIA")
    curveValueY := ScrollCurve(AbsDistY, _steepCurve)
    curveValueX := ScrollCurve(AbsDistX, _steepCurve)

    If (MB.Method = "UIA") {
      ; ===========================================
      ; UIA SCROLLING (auto-detected, fractional % via SetScrollPercent)
      ; Fallback: UIA -> WHEEL if scroll is non-functional
      ; Two-tick verification: tick 1 captures before-state, tick 2 cross-validates
      ; ===========================================
      _pattern := MB.UIA.Pattern  ; Dereference for pointer arithmetic (AHK v1.1 quirk)
      If (!_pattern) {
        SetTimer, MBDragTimer, Off
        Return
      }
      ; Initialize vertical accumulator
      If (MB.UIA.AccumPct < 0) {
        DllCall(NumGet(NumGet(_pattern+0)+6*A_PtrSize), "Ptr", _pattern, "Double*", _accumPct)
        MB.UIA.AccumPct := _accumPct
      }
      ; Initialize horizontal accumulator (vtable offset 5)
      If (MB.UIA.AccumPctH < 0) {
        DllCall(NumGet(NumGet(_pattern+0)+5*A_PtrSize), "Ptr", _pattern, "Double*", _accumPctH)
        MB.UIA.AccumPctH := _accumPctH
      }

      ; Normalize scroll speed based on ViewSize (applies to both axes):
      ; - ViewSize = 100%: only 1 item visible (small list), scroll FAST
      ; - ViewSize = 1%: 100 items visible (huge list), scroll SLOW
      ; Formula: mult = ViewSize / 3, clamped 0.25x to 50x

      ; Vertical scroll delta (only if vertical movement crosses threshold)
      If (AbsDistY >= MB.Threshold) {
        signDirY := (SignedDistY > 0) ? 1 : -1
        viewMultiplierY := MB.UIA.ViewSize / 3.0
        viewMultiplierY := Max(0.25, Min(viewMultiplierY, 50.0))
        deltaPctY := signDirY * curveValueY * 0.006 * viewMultiplierY
        MB.UIA.AccumPct := MB.UIA.AccumPct + deltaPctY
        MB.UIA.AccumPct := (MB.UIA.AccumPct < 0) ? 0 : (MB.UIA.AccumPct > 100) ? 100 : MB.UIA.AccumPct
      }

      ; Horizontal scroll delta (only if horizontal movement crosses threshold, skip if NoScroll sentinel -1)
      If (AbsDistX >= MB.Threshold and MB.UIA.AccumPctH >= 0) {
        signDirX := (SignedDistX > 0) ? 1 : -1
        viewMultiplierH := MB.UIA.ViewSizeH / 3.0
        viewMultiplierH := Max(0.25, Min(viewMultiplierH, 50.0))
        deltaPctH := signDirX * curveValueX * 0.006 * viewMultiplierH * 1.5
        MB.UIA.AccumPctH := MB.UIA.AccumPctH + deltaPctH
        MB.UIA.AccumPctH := (MB.UIA.AccumPctH < 0) ? 0 : (MB.UIA.AccumPctH > 100) ? 100 : MB.UIA.AccumPctH
      }

      ; Read actual current scroll position for tooltip
      DllCall(NumGet(NumGet(_pattern+0)+6*A_PtrSize), "Ptr", _pattern, "Double*", _curPctV)
      DllCall(NumGet(NumGet(_pattern+0)+5*A_PtrSize), "Ptr", _pattern, "Double*", _curPctH)
      If (Debug.Tooltips["mbutton-drag"])
        ToolTip, % "UIA: pos=" Round(_curPctV, 1) "%% view=" Round(MB.UIA.ViewSize, 1) "%% (H:" Round(_curPctH, 1) "%%)"
      ; SetScrollPercent(hPct, vPct) - vtable offset 4 (with timing)
      _accumH := MB.UIA.AccumPctH, _accumV := MB.UIA.AccumPct
      DllCall("QueryPerformanceCounter", "Int64*", _qpcBefore)
      DllCall(NumGet(NumGet(_pattern+0)+4*A_PtrSize), "Ptr", _pattern, "Double", _accumH, "Double", _accumV)
      DllCall("QueryPerformanceCounter", "Int64*", _qpcAfter)
      MB.ScrollTicks++

      ; Confirm cursor after first successful UIA scroll (position actually changed)
      If (MB.Cursor.Pending) {
        DllCall(NumGet(NumGet(_pattern+0)+6*A_PtrSize), "Ptr", _pattern, "Double*", _newPctV)
        DllCall(NumGet(NumGet(_pattern+0)+5*A_PtrSize), "Ptr", _pattern, "Double*", _newPctH)
        If (_newPctV != MB.Probe.InitScrollPct or (_newPctH >= 0 and _newPctH != MB.Probe.InitScrollPctH)) {
          MB.Cursor.Active := 1
          MB.Cursor.Pending := 0
          SetDragCursor()
          If (Debug.Log["mbutton-drag"])
            FileAppend, % TS() " | mbutton-drag | CURSOR_CONFIRMED | method=UIA pctV=" Round(_newPctV, 1) "`n", % Debug.Log.Path
        }
      }

      ; Log every 5 ticks for jitter debugging
      If (Debug.Log["mbutton-drag"] && Mod(MB.ScrollTicks, 5) = 0) {
        DllCall("QueryPerformanceFrequency", "Int64*", _qpcFreq)
        _uiaMs := Round((_qpcAfter - _qpcBefore) * 1000.0 / _qpcFreq, 2)
        _scrollTarget := MB.Ctrl ? MB.Ctrl : MB.Win
        _win32Pos := GetScrollPos(_scrollTarget)
        FileAppend, % TS() " | mbutton-drag | UIA | proc=" MB.ProcName " tick=" MB.ScrollTicks " V=" Round(MB.UIA.AccumPct, 1) " H=" Round(MB.UIA.AccumPctH, 1) " win32=" _win32Pos " callMs=" _uiaMs "`n", % Debug.Log.Path
      }

      ; Verify UIA: only fall back on NoScroll sentinel (-1) for the axis being scrolled
      ; Trust that if we got a ScrollPattern, it works. For flaky async UIA (like ATL controls),
      ; position-change verification causes false positives. If UIA genuinely doesn't scroll,
      ; user sees no movement and releases — no harm done.
      If (MB.FallbackChecked = 0) {
        _noScrollV := false, _noScrollH := false
        If (AbsDistY >= MB.Threshold) {
          DllCall(NumGet(NumGet(_pattern+0)+6*A_PtrSize), "Ptr", _pattern, "Double*", verifyPctV)
          _noScrollV := (verifyPctV < -0.5)
        }
        If (AbsDistX >= MB.Threshold) {
          DllCall(NumGet(NumGet(_pattern+0)+5*A_PtrSize), "Ptr", _pattern, "Double*", verifyPctH)
          _noScrollH := (verifyPctH < -0.5)
        }
        ; If horizontal NoScroll but vertical available, just disable horizontal and continue UIA
        ; Don't fall back completely - user may switch to vertical movement
        If (_noScrollH and !_noScrollV and MB.UIA.ViewSize < 99.9) {
          MB.UIA.AccumPctH := -1  ; Mark horizontal as disabled
          MB.FallbackChecked := 1
          If (Debug.Log["mbutton-drag"])
            FileAppend, % TS() " | mbutton-drag | UIA_HORIZ_DISABLED | proc=" MB.ProcName " (vertical still available)`n", % Debug.Log.Path
        ; Fall back only if vertical is NoScroll (horizontal-only NoScroll doesn't warrant full fallback)
        } Else If (_noScrollV) {
          ; Vertical is NoScroll — fall back to WHEEL
          ObjRelease(_pattern)
          MB.UIA.Pattern := 0
          _element := MB.UIA.Element
          ObjRelease(_element)
          MB.UIA.Element := 0
          MB.Method := "WHEEL"
          If (Debug.Tooltips["mbutton-drag"])
            ToolTip, % "UIA->WHEEL (NoScroll sentinel)"
          If (Debug.Log["mbutton-drag"])
            FileAppend, % TS() " | mbutton-drag | FALLBACK | proc=" MB.ProcName " UIA->WHEEL (NoScroll V=" _noScrollV " H=" _noScrollH ")`n", % Debug.Log.Path
        } Else {
          MB.FallbackChecked := 1  ; UIA is valid, no further verification needed
        }
      }

    } Else If (MB.Method = "LVM") {
      ; ===========================================
      ; LVM_SCROLL (0x1014) — pixel-level ListView scrolling
      ; Detects row-quantized vs pixel-level on first scroll:
      ;   - Pixel-level (TortoiseGit): dual-axis allowed freely
      ;   - Row-quantized (FullEventLogView): EMA axis restriction + 2x horizontal
      ; ===========================================
      target := MB.Ctrl ? MB.Ctrl : MB.Win

      ; Get item count for normalization (more items = slower scroll per tick)
      SendMessage, 0x1004, 0, 0,, ahk_id %target%  ; LVM_GETITEMCOUNT
      itemCount := ErrorLevel

      ; Normalize scroll speed based on item count (only for quantized controls)
      ; - Quantized: sqrt curve, 20 items = 1.0x, range 0.5x to 1.5x
      ; - Pixel-level: no normalization (1.0x always)
      If (MB.LVM.RowQuantized) {
        normMultiplier := (itemCount > 0) ? Max(0.5, Min(1.5, Sqrt(20.0 / itemCount))) : 1.0
      } Else {
        normMultiplier := 1.0
      }
      pixelMultiplier := 1.0 * normMultiplier

      ; Calculate scroll values (before detection, needed for detection probe)
      scrollPixelsY := 0
      scrollPixelsX := 0
      If (AbsDistY >= MB.Threshold) {
        scrollPixelsY := Max(1, Floor(curveValueY * pixelMultiplier))
        ; Row-quantized views need rowHeight+1 pixels to guarantee crossing row boundary
        If (MB.LVM.RowQuantized)
          scrollPixelsY := Max(MB.LVM.RowHeight + 1, scrollPixelsY)
        If (SignedDistY < 0)
          scrollPixelsY := -scrollPixelsY
      }
      If (AbsDistX >= MB.Threshold) {
        scrollPixelsX := Max(1, Floor(curveValueX * pixelMultiplier))
        If (SignedDistX < 0)
          scrollPixelsX := -scrollPixelsX
      }

      ; --- Row-quantization detection on first vertical scroll ---
      If (!MB.LVM.Detected and AbsDistY >= MB.Threshold) {
        ; Use 50px for detection probe — enough to cross a typical row boundary (20-25px)
        ; This prevents false "pixel-level at boundary" when sent pixels are too small
        detectScrollY := (SignedDistY > 0) ? 50 : -50
        posBefore := GetScrollPos(target)
        SendMessage, 0x1014, 0, %detectScrollY%,, ahk_id %target%
        posAfter := GetScrollPos(target)
        scrollDelta := Abs(posAfter - posBefore)
        sentPixels := Abs(detectScrollY)

        ; Check ListView styles for diagnosis
        WinGet, _lvStyle, Style, ahk_id %target%
        _isVirtual := (_lvStyle & 0x1000) ? 1 : 0      ; LVS_OWNERDATA
        _isOwnerDraw := (_lvStyle & 0x0400) ? 1 : 0   ; LVS_OWNERDRAWFIXED

        ; Detection logic:
        ; - delta ≈ sentPixels (0.85-1.15 ratio): pixel-level scrolling (HIGH CONFIDENCE)
        ; - delta=0: at boundary or no scrollbar, assume pixel-level (LOW CONFIDENCE)
        ; - delta > 0 but < 0.85*sent: row-quantized (rounded to row boundaries)
        ; Row-quantized is the default for most ListViews; pixel-level is rare (TortoiseGit)
        deltaRatio := (sentPixels > 0) ? (scrollDelta / sentPixels) : 0
        If (deltaRatio >= 0.85 and deltaRatio <= 1.15) {
          ; Pixel-level: delta ≈ sentPixels (high confidence - prevents SLOW-TICK override)
          MB.LVM.RowQuantized := 0
          MB.LVM.DetectConfident := 1
          If (Debug.Log["mbutton-drag"])
            FileAppend, % TS() " | mbutton-drag | DETECT | proc=" MB.ProcName " PIXEL-LEVEL delta=" scrollDelta " sent=" sentPixels " ratio=" Round(deltaRatio, 2) " virtual=" _isVirtual "`n", % Debug.Log.Path
        } Else If (scrollDelta = 0) {
          ; delta=0: at boundary or no scrollbar, assume pixel-level (low confidence)
          MB.LVM.RowQuantized := 0
          MB.LVM.DetectConfident := 0  ; Allow SLOW-TICK to upgrade if truly slow
          If (Debug.Log["mbutton-drag"])
            FileAppend, % TS() " | mbutton-drag | DETECT | proc=" MB.ProcName " PIXEL-LEVEL (boundary) delta=0 sent=" sentPixels " virtual=" _isVirtual "`n", % Debug.Log.Path
        } Else {
          ; delta > 0 but ratio outside 0.85-1.15: row-quantized
          ; GetScrollPos returns ROWS not pixels for row-quantized ListViews
          ; So delta=1 means 1 row scrolled, delta=2 means 2 rows, etc.
          MB.LVM.RowQuantized := 1
          MB.LVM.DetectConfident := 1
          ; Estimate row height: sentPixels / scrollDelta = pixels per row
          ; scrollDelta is in rows, sentPixels is in pixels
          If (scrollDelta > 0 and scrollDelta <= 5) {
            ; Small delta = few rows scrolled, estimate row height
            MB.LVM.RowHeight := Floor(sentPixels / scrollDelta)
            ; Sanity check: row heights are typically 16-40px
            MB.LVM.RowHeight := Max(16, Min(40, MB.LVM.RowHeight))
          } Else {
            MB.LVM.RowHeight := 25  ; Conservative default
          }
          If (Debug.Log["mbutton-drag"])
            FileAppend, % TS() " | mbutton-drag | DETECT | proc=" MB.ProcName " ROW-QUANTIZED rowH=" MB.LVM.RowHeight " delta=" scrollDelta " sent=" sentPixels " ratio=" Round(deltaRatio, 2) " virtual=" _isVirtual "`n", % Debug.Log.Path
        }
        MB.LVM.Detected := 1
        ; If row-quantized detected and our sent pixels were below threshold, send another scroll
        ; to actually move the list on this first tick (not wait until tick 2)
        If (MB.LVM.RowQuantized and sentPixels < MB.LVM.RowHeight) {
          _extra := MB.LVM.RowHeight - sentPixels + 1  ; Send remaining pixels to cross threshold
          If (SignedDistY < 0)
            _extra := -_extra
          SendMessage, 0x1014, 0, %_extra%,, ahk_id %target%
          posAfter := GetScrollPos(target)
        }
        ; Show detection result in tooltip
        If (Debug.Tooltips["mbutton-drag"]) {
          _mode := MB.LVM.RowQuantized ? "Q" : "P"
          ToolTip, % "LVM[" _mode "] detected (delta=" scrollDelta " virt=" _isVirtual " rowH=" MB.LVM.RowHeight ")"
        }
        ; Set position variables for tooltip (detection scroll already sent)
        _posBeforeY := posBefore, _posAfterY := posAfter
        _posBeforeX := GetScrollPos(target, 0)  ; Initialize for horizontal tracking
        DllCall("GetScrollRange", "Ptr", target, "Int", 1, "Int*", _scrollMinY, "Int*", _scrollMaxY)
        _atBoundaryY := false
        DllCall("QueryPerformanceCounter", "Int64*", _qpcScrollStart)  ; For timing calc
        ; First vertical scroll already sent, skip to EMA/horizontal below
        MB.ScrollTicks++
        Goto, LVM_PostVertical
      }

      ; --- EMA axis determination (row-quantized apps only) ---
      scrollAxisY := true
      scrollAxisX := true
      If (MB.LVM.RowQuantized) {
        ; Vertical bias: require horizontal distance >= rowHeight to consider horizontal
        ; (vertical scrolling is far more common in list views)
        horizThreshold := MB.LVM.RowHeight

        ; Calculate movement deltas since last tick
        deltaY := Abs(SignedDistY - MB.EMA.PrevDistY)
        deltaX := Abs(SignedDistX - MB.EMA.PrevDistX)
        MB.EMA.PrevDistY := SignedDistY
        MB.EMA.PrevDistX := SignedDistX

        ; Update EMAs (alpha=0.2: responsive but smooth, natural decay when still)
        alpha := 0.2
        MB.EMA.Y := alpha * deltaY + (1 - alpha) * MB.EMA.Y
        MB.EMA.X := alpha * deltaX + (1 - alpha) * MB.EMA.X

        ; Determine dominant axis (1.5x threshold for lock)
        ; Transition zone allows diagonal - if app chokes, user will notice and drag more deliberately
        dominanceRatio := 1.5
        If (MB.EMA.Y > MB.EMA.X * dominanceRatio) {
          scrollAxisY := true, scrollAxisX := false
        } Else If (MB.EMA.X > MB.EMA.Y * dominanceRatio and AbsDistX >= horizThreshold) {
          ; Horizontal only if EMA dominates AND distance exceeds row height
          scrollAxisY := false, scrollAxisX := true
        } Else {
          ; Default to vertical (more common), allow horizontal only if clearly intended
          scrollAxisY := (AbsDistY >= MB.Threshold)
          scrollAxisX := (AbsDistX >= horizThreshold and MB.EMA.X > MB.EMA.Y)
        }
      }

      ; --- Boundary detection: clear flag when vertical direction reverses ---
      ; If stuck at min (boundary=-1) and now scrolling down (pixels>0), clear
      ; If stuck at max (boundary=1) and now scrolling up (pixels<0), clear
      If (scrollPixelsY > 0 and MB.LVM.BoundaryY = -1)
        MB.LVM.BoundaryY := 0
      Else If (scrollPixelsY < 0 and MB.LVM.BoundaryY = 1)
        MB.LVM.BoundaryY := 0

      ; --- Send scroll messages with timing for adaptive boost ---
      DllCall("QueryPerformanceCounter", "Int64*", _qpcScrollStart)

      ; Get current position and range BEFORE scroll (for boundary pre-check)
      _posBeforeY := GetScrollPos(target, 1)  ; Vertical
      _posBeforeX := GetScrollPos(target, 0)  ; Horizontal
      DllCall("GetScrollRange", "Ptr", target, "Int", 1, "Int*", _scrollMinY, "Int*", _scrollMaxY)

      ; Pre-check: if already at boundary, set flag BEFORE attempting scroll
      ; This prevents the "one scroll overshoot" where we scroll then detect
      If (scrollPixelsY < 0 and _posBeforeY <= 0) {
        MB.LVM.BoundaryY := -1
      } Else If (scrollPixelsY > 0 and _posBeforeY >= _scrollMaxY and _scrollMaxY > 0) {
        MB.LVM.BoundaryY := 1
      }

      ; Check if at vertical boundary (used for both scroll skip and tooltip)
      _atBoundaryY := (scrollPixelsY < 0 and MB.LVM.BoundaryY = -1) or (scrollPixelsY > 0 and MB.LVM.BoundaryY = 1)

      ; Vertical scroll with boundary detection (skip if at boundary)
      _posAfterY := _posBeforeY  ; default if we skip
      If (scrollAxisY and AbsDistY >= MB.Threshold and !_atBoundaryY) {
        SendMessage, 0x1014, 0, %scrollPixelsY%,, ahk_id %target%
        _posAfterY := GetScrollPos(target, 1)
        ; Post-check: if we landed at boundary, set flag for next tick
        ; For MIN: position must be <= 0
        ; For MAX: position >= declared max, OR position didn't change (actual max differs from GetScrollRange)
        ;          The "no change" heuristic requires scroll magnitude >= row height to avoid false positives
        ;          when mouse briefly crosses zero velocity (small scroll that can't move a full row)
        If (scrollPixelsY < 0 and _posAfterY <= 0) {
          MB.LVM.BoundaryY := -1  ; At min, can't scroll up
        } Else If (scrollPixelsY > 0 and _posAfterY > 0 and _posAfterY >= _scrollMaxY) {
          MB.LVM.BoundaryY := 1   ; At declared max
        }
        ; NOTE: Removed "no change = boundary" heuristic — it caused false positives mid-list
        ; when row-quantized scrolling didn't move at certain pixel amounts
        ; If position didn't change but we're not at a boundary, don't set flag — scroll was just ignored
        If (MB.LVM.BoundaryY != 0 and Debug.Log["mbutton-drag"])
          FileAppend, % TS() " | mbutton-drag | BOUNDARY | Y axis dir=" MB.LVM.BoundaryY " before=" _posBeforeY " after=" _posAfterY " max=" _scrollMaxY "`n", % Debug.Log.Path
      }

      LVM_PostVertical:
      ; Recalculate horizontal if detection changed multiplier
      If (AbsDistX >= MB.Threshold) {
        scrollPixelsX := Max(1, Floor(curveValueX * pixelMultiplier))
        If (SignedDistX < 0)
          scrollPixelsX := -scrollPixelsX
      }

      ; Horizontal scroll (no boundary tracking needed)
      _posAfterX := _posBeforeX  ; default if we skip
      If (scrollAxisX and AbsDistX >= MB.Threshold) {
        SendMessage, 0x1014, %scrollPixelsX%, 0,, ahk_id %target%
        _posAfterX := GetScrollPos(target, 0)
      }

      ; Confirm cursor after verified scroll (either axis position changed)
      If (MB.Cursor.Pending and (_posAfterY != _posBeforeY or _posAfterX != _posBeforeX)) {
        MB.Cursor.Active := 1
        MB.Cursor.Pending := 0
        SetDragCursor()
        If (Debug.Log["mbutton-drag"])
          FileAppend, % TS() " | mbutton-drag | CURSOR_CONFIRMED | method=LVM`n", % Debug.Log.Path
      }

      ; --- Timing-based detection: slow tick (>50ms) = virtualized/quantized control ---
      ; Virtualized ListViews are sluggish because they render rows on-demand.
      ; This triggers: EMA axis restriction + 2x horizontal boost (same as row-quantized)
      DllCall("QueryPerformanceCounter", "Int64*", _qpcScrollEnd)
      DllCall("QueryPerformanceFrequency", "Int64*", _qpcFreq)
      _scrollMs := (_qpcScrollEnd - _qpcScrollStart) * 1000.0 / _qpcFreq
      ; Only upgrade if: slow (>50ms), not already quantized, AND detection wasn't confident
      ; This prevents system hiccups from overriding a solid pixel-level detection
      If (_scrollMs > 50 and !MB.LVM.RowQuantized and !MB.LVM.DetectConfident) {
        ; Slow tick = virtualized control, needs axis restriction + horizontal boost
        MB.LVM.Detected := 1
        MB.LVM.RowQuantized := 1
        If (Debug.Log["mbutton-drag"])
          FileAppend, % TS() " | mbutton-drag | DETECT | proc=" MB.ProcName " SLOW-TICK->QUANTIZED ms=" Round(_scrollMs) "`n", % Debug.Log.Path
      }

      MB.ScrollTicks++
      If (Debug.Tooltips["mbutton-drag"]) {
        ; Mode format: Q:h (quantized high-conf), P:l (pixel low-conf), ? (not yet detected)
        ; High confidence: virtual flag or delta-ratio match. Low: boundary guess or slow-tick upgrade
        If (!MB.LVM.Detected)
          _mode := "?"
        Else
          _mode := (MB.LVM.RowQuantized ? "Q" : "P") . ":" . (MB.LVM.DetectConfident ? "h" : "l")
        _pxYSent := (scrollAxisY and AbsDistY >= MB.Threshold and !_atBoundaryY) ? scrollPixelsY : 0
        _pxXSent := (scrollAxisX and AbsDistX >= MB.Threshold) ? scrollPixelsX : 0
        _boundY := (MB.LVM.BoundaryY = -1) ? " MIN" : (MB.LVM.BoundaryY = 1) ? " MAX" : ""
        ToolTip, % "LVM[" _mode "] dY=" _pxYSent " dX=" _pxXSent " pos=" _posAfterY "/" _scrollMaxY _boundY
      }
      ; Log every 5 ticks
      If (Debug.Log["mbutton-drag"] && Mod(MB.ScrollTicks, 5) = 0) {
        _pxYLog := (scrollAxisY and AbsDistY >= MB.Threshold and !_atBoundaryY) ? scrollPixelsY : 0
        _pxXLog := (scrollAxisX and AbsDistX >= MB.Threshold) ? scrollPixelsX : 0
        If (!MB.LVM.Detected)
          _modeLog := "?"
        Else
          _modeLog := (MB.LVM.RowQuantized ? "Q" : "P") . ":" . (MB.LVM.DetectConfident ? "h" : "l")
        FileAppend, % TS() " | mbutton-drag | LVM[" _modeLog "] | proc=" MB.ProcName " tick=" MB.ScrollTicks " dY=" _pxYLog " dX=" _pxXLog " pos=" _posAfterY "/" _scrollMaxY " ms=" Round(_scrollMs) "`n", % Debug.Log.Path
      }

    } Else If (MB.Method = "WHEEL_CTRL") {
      ; ===========================================
      ; WM_MOUSEWHEEL to CONTROL with GetScrollPos fallback
      ; No fractional scrolling, better acceleration than WM_VSCROLL
      ; ===========================================
      target := MB.Ctrl ? MB.Ctrl : MB.Win

      ; Get position BEFORE scroll (always try - some apps have scrollbars without WS_VSCROLL)
      If (!MB.FallbackChecked) {
        posBefore := GetScrollPos(target)
      }

      ; Send WHEEL message (vertical) — only if vertical movement exceeds threshold
      lParam := ((MB.Y1 & 0xFFFF) << 16) | (MB.X1 & 0xFFFF)
      If (AbsDistY >= MB.Threshold) {
        magnitudeY := Max(1, Min(119, Floor(curveValueY / 2)))
        DeltaY := (SignedDistY > 0) ? -magnitudeY : magnitudeY
        wParamY := DeltaY << 16
        PostMessage, 0x20A, %wParamY%, %lParam%,, ahk_id %target%  ; WM_MOUSEWHEEL

        ; Check for fallback on first vertical scroll only
        If (!MB.FallbackChecked) {
          Sleep, 10  ; Brief pause for scroll to complete
          posAfter := GetScrollPos(target)
          scrolledUnits := Abs(posAfter - posBefore)

          ; If jumped >40 units (typically >1 line), switch to VSCROLL
          If (scrolledUnits > 40) {
            MB.Method := "VSCROLL"
            SetTimer, MBDragTimer, 150
            ; Revert the jump by scrolling opposite direction
            revertDir := (posAfter > posBefore) ? 0 : 1  ; 0=up, 1=down
            PostMessage, 0x115, %revertDir%, 0,, ahk_id %target%  ; WM_VSCROLL
            If (Debug.Tooltips["mbutton-drag"])
              ToolTip, % "WHEEL_CTRL->VSCROLL (jumped " scrolledUnits " units)"
            If (Debug.Log["mbutton-drag"])
              FileAppend, % TS() " | mbutton-drag | FALLBACK | proc=" MB.ProcName " WHEEL_CTRL->VSCROLL (jumped " scrolledUnits " units)`n", % Debug.Log.Path
          }
          ; Scroll succeeded — show cursor if pending (position changed OR was already non-zero)
          If (MB.Cursor.Pending and (scrolledUnits > 0 or posBefore > 0)) {
            If (scrolledUnits > 0) {
              MB.Cursor.Active := 1
              MB.Cursor.Pending := 0
              SetDragCursor()
              If (Debug.Log["mbutton-drag"])
                FileAppend, % TS() " | mbutton-drag | CURSOR_CONFIRMED | method=WHEEL_CTRL scrolled=" scrolledUnits "`n", % Debug.Log.Path
            }
            ; posBefore > 0 but no scroll: scrollbar exists, might be at boundary — keep trying
          }
          ; posBefore=0, posAfter=0: can't verify (custom scrollbar) — will use tick-count fallback below
          If (scrolledUnits > 0)
            MB.FallbackChecked := 1
        }
      }

      ; Fallback for custom scrollbars (like SystemInformer's PhTreeNew)
      ; Check after movement threshold, only once per session
      ; Only activate if the TARGET CONTROL has VISIBLE ScrollBar children with actual scroll range
      ; Explorer has hidden scrollbars always present - must check visibility
      If (MB.Cursor.Pending and !MB.ScrollBarChecked and (AbsDistY >= MB.Threshold or AbsDistX >= MB.Threshold)) {
        _childScrollbar := MB.Ctrl ? FindScrollBarChild(MB.Ctrl) : 0
        _scrollbarHasRange := 0
        _scrollbarVisible := 0
        If (_childScrollbar) {
          _scrollbarVisible := DllCall("IsWindowVisible", "Ptr", _childScrollbar, "Int")
          If (_scrollbarVisible) {
            ; Verify the scrollbar has actual scroll range (not just present but empty)
            VarSetCapacity(_si, 28, 0)
            NumPut(28, _si, 0, "UInt")
            NumPut(0x3, _si, 4, "UInt")  ; SIF_RANGE | SIF_PAGE
            _ret := DllCall("GetScrollInfo", "Ptr", _childScrollbar, "Int", 2, "Ptr", &_si, "Int")  ; SB_CTL
            _min := NumGet(_si, 8, "Int"), _max := NumGet(_si, 12, "Int"), _page := NumGet(_si, 16, "UInt")
            _scrollbarHasRange := (_ret and _max - _min > _page)
          }
        }
        If (Debug.Log["mbutton-drag"])
          FileAppend, % TS() " | mbutton-drag | SCROLLBAR_CHECK | ctrl=" MB.Ctrl " childScrollbar=" _childScrollbar " visible=" _scrollbarVisible " hasRange=" _scrollbarHasRange "`n", % Debug.Log.Path
        ; Only mark as checked if: (1) no scrollbar child exists, or (2) scrollbar is visible and has range
        ; If scrollbar exists but is temporarily invisible, allow recheck on subsequent ticks
        If (!_childScrollbar or _scrollbarHasRange)
          MB.ScrollBarChecked := 1
        If (_scrollbarHasRange) {
          MB.Cursor.Active := 1
          MB.Cursor.Pending := 0
          SetDragCursor()
          If (Debug.Log["mbutton-drag"])
            FileAppend, % TS() " | mbutton-drag | CURSOR_CONFIRMED | method=WHEEL_CTRL (ctrl has scrollbar child)`n", % Debug.Log.Path
        }
      }

      MB.ScrollTicks++

      ; Horizontal: WM_MOUSEHWHEEL (0x20E) — 1.5x boost for perceptual parity
      If (AbsDistX >= MB.Threshold) {
        magnitudeX := Max(1, Floor(curveValueX * 1.5))
        DeltaX := (SignedDistX > 0) ? magnitudeX : -magnitudeX
        wParamX := DeltaX << 16
        PostMessage, 0x20E, %wParamX%, %lParam%,, ahk_id %target%
      }

      If (Debug.Tooltips["mbutton-drag"] && MB.Method = "WHEEL_CTRL")
        ToolTip, % "WHEEL_CTRL: dY=" (AbsDistY >= MB.Threshold ? DeltaY : 0) " dX=" (AbsDistX >= MB.Threshold ? DeltaX : 0)

      ; Log every 5 ticks for comparison with LVM
      If (Debug.Log["mbutton-drag"] && Mod(MB.ScrollTicks, 5) = 0) {
        _dYLog := (AbsDistY >= MB.Threshold) ? DeltaY : 0
        _dXLog := (AbsDistX >= MB.Threshold) ? DeltaX : 0
        _curveXLog := (AbsDistX >= MB.Threshold) ? Round(curveValueX, 1) : 0
        FileAppend, % TS() " | mbutton-drag | WHEEL_CTRL | proc=" MB.ProcName " tick=" MB.ScrollTicks " dY=" _dYLog " dX=" _dXLog " curveX=" _curveXLog "`n", % Debug.Log.Path
      }

    } Else If (MB.Method = "VSCROLL") {
      ; ===========================================
      ; WM_VSCROLL/HSCROLL LINE - dynamic timer based on drag distance
      ; No fractional scrolling, most compatible
      ; ===========================================
      target := MB.Ctrl ? MB.Ctrl : MB.Win

      ; Dynamic timer: use max of both axes for speed calculation
      maxDist := (AbsDistY > AbsDistX) ? AbsDistY : AbsDistX
      timerMs := 300 - Floor((Min(maxDist, 300) - MB.Threshold) * (100 / 192))
      timerMs := Max(20, Min(300, timerMs / 2))
      SetTimer, MBDragTimer, %timerMs%

      ; Vertical: WM_VSCROLL (0x115)
      If (AbsDistY >= MB.Threshold) {
        _posBefore := MB.Cursor.Pending ? GetScrollPos(target) : 0
        scrollDirY := (SignedDistY > 0) ? 1 : 0
        PostMessage, 0x115, %scrollDirY%, 0,, ahk_id %target%
        ; Confirm cursor after verified scroll
        If (MB.Cursor.Pending) {
          Sleep, 10
          _posAfter := GetScrollPos(target)
          If (_posAfter != _posBefore) {
            MB.Cursor.Active := 1
            MB.Cursor.Pending := 0
            SetDragCursor()
            If (Debug.Log["mbutton-drag"])
              FileAppend, % TS() " | mbutton-drag | CURSOR_CONFIRMED | method=VSCROLL`n", % Debug.Log.Path
          }
        }
      }

      ; Horizontal: WM_MOUSEHWHEEL (0x20E) — 5x multiplier with acceleration
      If (AbsDistX >= MB.Threshold) {
        lParamV := ((MB.Y1 & 0xFFFF) << 16) | (MB.X1 & 0xFFFF)
        magnitudeX := Max(30, Min(360, Floor(curveValueX * 5)))  ; 5x, cap at 3 notches
        DeltaX := (SignedDistX > 0) ? magnitudeX : -magnitudeX
        wParamX := DeltaX << 16
        PostMessage, 0x20E, %wParamX%, %lParamV%,, ahk_id %target%
      }

      If (Debug.Tooltips["mbutton-drag"])
        ToolTip, % "VSCROLL: dirY=" (AbsDistY >= MB.Threshold ? scrollDirY : "-") " dX=" (AbsDistX >= MB.Threshold ? DeltaX : "-") " timer=" timerMs "ms"

    } Else {
      ; ===========================================
      ; WM_MOUSEWHEEL to WINDOW (Electron apps, auto-detected default)
      ; Fallback: WHEEL -> WHEEL_CTRL if window-level message doesn't scroll
      ; ===========================================
      lParam := ((MB.Y1 & 0xFFFF) << 16) | (MB.X1 & 0xFFFF)

      ; Vertical: only if vertical movement exceeds threshold
      If (AbsDistY >= MB.Threshold) {
        ; MUST cap below 120 for smooth scrolling (120 = 1 notch = 3 lines)
        magnitudeY := Max(1, Min(119, Floor(curveValueY / 2)))
        DeltaY := (SignedDistY > 0) ? -magnitudeY : magnitudeY
        wParamY := DeltaY << 16

        If (!MB.FallbackChecked) {
          ; Test if window-level WHEEL actually scrolls (first vertical scroll only)
          ctrlTarget := MB.Ctrl ? MB.Ctrl : MB.Win
          _hasScrollbar := HasWin32Scrollbar(ctrlTarget)
          posBefore := _hasScrollbar ? GetScrollPos(ctrlTarget) : 0
          _mbWin := MB.Win
          PostMessage, 0x20A, %wParamY%, %lParam%,, ahk_id %_mbWin%
          Sleep, 15
          posAfter := _hasScrollbar ? GetScrollPos(ctrlTarget) : 0
          ; For apps without Win32 scrollbars (Sublime, etc.), skip fallback — trust WHEEL works
          ; GetScrollPos can't detect their scroll state, so 0=0 would always trigger false fallback
          If (_hasScrollbar and posBefore = posAfter) {
            ; No movement detected — try sending to control directly
            MB.Method := "WHEEL_CTRL"
            MB.FallbackChecked := 0
            If (Debug.Tooltips["mbutton-drag"])
              ToolTip, % "WHEEL->WHEEL_CTRL (no movement)"
            If (Debug.Log["mbutton-drag"])
              FileAppend, % TS() " | mbutton-drag | FALLBACK | proc=" MB.ProcName " WHEEL->WHEEL_CTRL (no movement)`n", % Debug.Log.Path
          } Else If (_hasScrollbar) {
            MB.FallbackChecked := 1
            ; Scroll succeeded — show cursor if pending
            If (MB.Cursor.Pending) {
              MB.Cursor.Active := 1
              MB.Cursor.Pending := 0
              SetDragCursor()
              If (Debug.Log["mbutton-drag"])
                FileAppend, % TS() " | mbutton-drag | CURSOR_CONFIRMED | method=WHEEL`n", % Debug.Log.Path
            }
          } Else If (MB.Ctrl) {
            ; No scrollbar + has control — can't verify via GetScrollPos, but WHEEL_CTRL
            ; (sends to control) is more likely to work than WHEEL (sends to window)
            MB.Method := "WHEEL_CTRL"
            MB.FallbackChecked := 0
            If (Debug.Tooltips["mbutton-drag"])
              ToolTip, % "WHEEL->WHEEL_CTRL (no scrollbar, has control)"
            If (Debug.Log["mbutton-drag"])
              FileAppend, % TS() " | mbutton-drag | FALLBACK | proc=" MB.ProcName " WHEEL->WHEEL_CTRL (no scrollbar, control=" MB.ClassName ")`n", % Debug.Log.Path
          } Else {
            ; No scrollbar, no control — truly can't verify, trust WHEEL
            MB.FallbackChecked := 1
            MB.ScrollTicks++
          }
        } Else {
          _mbWin := MB.Win
          PostMessage, 0x20A, %wParamY%, %lParam%,, ahk_id %_mbWin%
        }
      }

      ; Horizontal: WM_MOUSEHWHEEL (0x20E) — 2x multiplier for perceptual parity with vertical
      ; Before WHEEL is verified, send to control (like WHEEL_CTRL) to handle horizontal-only drags
      If (AbsDistX >= MB.Threshold) {
        magnitudeX := Max(1, Min(119, Floor(curveValueX)))  ; 2x: removed /2
        DeltaX := (SignedDistX > 0) ? magnitudeX : -magnitudeX
        wParamX := DeltaX << 16
        hTarget := MB.FallbackChecked ? MB.Win : (MB.Ctrl ? MB.Ctrl : MB.Win)
        PostMessage, 0x20E, %wParamX%, %lParam%,, ahk_id %hTarget%
      }

      If (Debug.Tooltips["mbutton-drag"] && MB.Method = "WHEEL")
        ToolTip, % "WHEEL: dY=" (AbsDistY >= MB.Threshold ? DeltaY : "-") " dX=" (AbsDistX >= MB.Threshold ? DeltaX : "-") " hTgt=" (MB.FallbackChecked ? "win" : "ctrl")
    }
  }
Return

*MButton Up::
  Critical ; Prevent timer from firing during cleanup (race condition safety)
  global MB, Debug
  SetTimer, MBDragTimer, Off
  ; Restore system cursor
  If (MB.Cursor.Active) {
    DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)  ; SPI_SETCURSORS
    MB.Cursor.Active := 0
  }
  MB.Cursor.Pending := 0
  ; Log session summary
  If (Debug.Log["mbutton-drag"] && MB.Triggered) {
    _duration := A_TickCount - MB.SessionStart
    FileAppend, % TS() " | mbutton-drag | END | proc=" MB.ProcName " method=" MB.Method " ticks=" MB.ScrollTicks " duration=" _duration "ms`n", % Debug.Log.Path
  }
  If (Debug.Tooltips["mbutton-drag"])
    ToolTip

  ; Release UIA objects
  If (MB.UIA.Pattern) {
    ObjRelease(MB.UIA.Pattern)
    MB.UIA.Pattern := 0
  }
  If (MB.UIA.Element) {
    ObjRelease(MB.UIA.Element)
    MB.UIA.Element := 0
  }

  ; Release MButton to app
  If (MB.DeferredDown) {
    ; Explorer: MButton Down was deferred — only send click if no scroll occurred
    If (!MB.Triggered) {
      SendInput, {Blind}{MButton}
    }
  } Else {
    ; Non-Explorer: MButton Down was already sent, send Up to complete
    SendInput, {Blind}{MButton Up}
  }
Return

; Get scroll position for a control (cross-process safe)
; bar: 1 = vertical (default), 0 = horizontal
GetScrollPos(hwnd, bar := 1) {
  Return DllCall("GetScrollPos", "Ptr", hwnd, "Int", bar, "Int")
}

; Set drag cursor (SizeAll) by replacing both IDC_ARROW and IDC_IBEAM
; Returns 1 on success. Logs current cursor type for debugging.
SetDragCursor() {
  global G_hSizeAll, Debug
  _cursor := A_Cursor
  ; Replace IDC_ARROW (32512)
  hCopy1 := DllCall("CopyImage", "Ptr", G_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
  DllCall("SetSystemCursor", "Ptr", hCopy1, "UInt", 32512)
  ; Replace IDC_IBEAM (32513) for text editors
  hCopy2 := DllCall("CopyImage", "Ptr", G_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
  DllCall("SetSystemCursor", "Ptr", hCopy2, "UInt", 32513)
  If (Debug.Log["mbutton-drag"])
    FileAppend, % TS() " | mbutton-drag | CURSOR_SET | activeCursor=" _cursor "`n", % Debug.Log.Path
  Return 1
}

; Check if a control has a visible Win32 scrollbar (window style check)
; axis: "V" for vertical (default), "H" for horizontal, "any" for either
HasWin32Scrollbar(hwnd, axis := "V") {
  WinGet, _style, Style, ahk_id %hwnd%
  If (axis = "H")
    Return (_style & 0x00100000)  ; WS_HSCROLL
  If (axis = "any")
    Return (_style & 0x00300000)  ; WS_VSCROLL or WS_HSCROLL
  Return (_style & 0x00200000)  ; WS_VSCROLL (default)
}

; Check if a control has scrollable content via GetScrollInfo
; Returns true if scroll range exists (nMax - nMin > nPage)
; axis: "V" for vertical (default), "H" for horizontal, "any" for either
HasScrollRange(hwnd, axis := "V") {
  global Debug
  ; SCROLLINFO struct: cbSize, fMask, nMin, nMax, nPage, nPos, nTrackPos
  VarSetCapacity(_si, 28, 0)
  NumPut(28, _si, 0, "UInt")  ; cbSize
  NumPut(0x7, _si, 4, "UInt")  ; fMask = SIF_RANGE | SIF_PAGE (0x1 | 0x2 | 0x4)

  _checkV := (axis = "V" or axis = "any")
  _checkH := (axis = "H" or axis = "any")

  If (_checkV) {
    _ret := DllCall("GetScrollInfo", "Ptr", hwnd, "Int", 1, "Ptr", &_si, "Int")  ; SB_VERT=1
    _min := NumGet(_si, 8, "Int"), _max := NumGet(_si, 12, "Int"), _page := NumGet(_si, 16, "UInt")
    If (Debug.Log["mbutton-drag"])
      FileAppend, % TS() " | mbutton-drag | SCROLL_INFO_V | hwnd=" hwnd " ret=" _ret " min=" _min " max=" _max " page=" _page "`n", % Debug.Log.Path
    If (_ret and _max - _min > _page)
      Return true
  }
  If (_checkH) {
    _ret := DllCall("GetScrollInfo", "Ptr", hwnd, "Int", 0, "Ptr", &_si, "Int")  ; SB_HORZ=0
    _min := NumGet(_si, 8, "Int"), _max := NumGet(_si, 12, "Int"), _page := NumGet(_si, 16, "UInt")
    If (Debug.Log["mbutton-drag"])
      FileAppend, % TS() " | mbutton-drag | SCROLL_INFO_H | hwnd=" hwnd " ret=" _ret " min=" _min " max=" _max " page=" _page "`n", % Debug.Log.Path
    If (_ret and _max - _min > _page)
      Return true
  }
  Return false
}

; Find a visible ScrollBar control with actual scroll range (recursive)
; This detects true scrollability for apps like Explorer where DirectUIHWND
; doesn't respond to GetScrollInfo, but has separate ScrollBar controls
FindVisibleScrollBar(parentHwnd) {
  global Debug
  _child := DllCall("GetWindow", "Ptr", parentHwnd, "UInt", 5, "Ptr")  ; GW_CHILD
  While (_child) {
    If (DllCall("IsWindowVisible", "Ptr", _child, "Int")) {
      VarSetCapacity(_className, 256)
      DllCall("GetClassName", "Ptr", _child, "Str", _className, "Int", 255)
      If (InStr(_className, "ScrollBar")) {
        ; Found a visible ScrollBar - check if it has a scroll range
        VarSetCapacity(_si, 28, 0)
        NumPut(28, _si, 0, "UInt")
        NumPut(0x3, _si, 4, "UInt")  ; SIF_RANGE | SIF_PAGE
        ; For standalone ScrollBar controls, use SB_CTL (2)
        _ret := DllCall("GetScrollInfo", "Ptr", _child, "Int", 2, "Ptr", &_si, "Int")
        _min := NumGet(_si, 8, "Int"), _max := NumGet(_si, 12, "Int"), _page := NumGet(_si, 16, "UInt")
        If (Debug.Log["mbutton-drag"]) {
          ; Get scrollbar bounds and parent class for debugging false positives
          VarSetCapacity(_rect, 16, 0)
          DllCall("GetWindowRect", "Ptr", _child, "Ptr", &_rect)
          _sbL := NumGet(_rect, 0, "Int"), _sbT := NumGet(_rect, 4, "Int")
          _sbR := NumGet(_rect, 8, "Int"), _sbB := NumGet(_rect, 12, "Int")
          _parent := DllCall("GetParent", "Ptr", _child, "Ptr")
          VarSetCapacity(_parentClass, 256)
          DllCall("GetClassName", "Ptr", _parent, "Str", _parentClass, "Int", 255)
          FileAppend, % TS() " | mbutton-drag | SCROLLBAR_FOUND | hwnd=" _child " parent=" _parentClass " ret=" _ret " min=" _min " max=" _max " page=" _page " rect=" _sbL "," _sbT "," _sbR "," _sbB "`n", % Debug.Log.Path
        }
        If (_ret and _max - _min > _page)
          Return _child
      }
      ; Recursively check descendants
      _found := FindVisibleScrollBar(_child)
      If (_found)
        Return _found
    }
    _child := DllCall("GetWindow", "Ptr", _child, "UInt", 2, "Ptr")  ; GW_HWNDNEXT
  }
  Return 0
}

; Dump window tree for debugging hierarchy issues
; Logs each visible window with: depth, hwnd, class, rect, scrollbar info
; Controls containing click point are marked with * prefix
DumpWindowTree(parentHwnd, depth := 0, clickX := 0, clickY := 0) {
  global Debug
  If (!Debug.Log["mbutton-drag"])
    Return

  _child := DllCall("GetWindow", "Ptr", parentHwnd, "UInt", 5, "Ptr")  ; GW_CHILD
  While (_child) {
    If (DllCall("IsWindowVisible", "Ptr", _child, "Int")) {
      VarSetCapacity(_className, 256)
      DllCall("GetClassName", "Ptr", _child, "Str", _className, "Int", 255)

      ; Get window rect
      VarSetCapacity(_rect, 16, 0)
      DllCall("GetWindowRect", "Ptr", _child, "Ptr", &_rect)
      _l := NumGet(_rect, 0, "Int"), _t := NumGet(_rect, 4, "Int")
      _r := NumGet(_rect, 8, "Int"), _b := NumGet(_rect, 12, "Int")

      ; Check if click is inside this control
      _containsClick := (clickX >= _l and clickX <= _r and clickY >= _t and clickY <= _b) ? "*" : ""

      ; Check for scrollbar info if it's a ScrollBar control
      _scrollInfo := ""
      If (InStr(_className, "ScrollBar")) {
        VarSetCapacity(_si, 28, 0)
        NumPut(28, _si, 0, "UInt")
        NumPut(0x3, _si, 4, "UInt")
        _ret := DllCall("GetScrollInfo", "Ptr", _child, "Int", 2, "Ptr", &_si, "Int")
        _min := NumGet(_si, 8, "Int"), _max := NumGet(_si, 12, "Int"), _page := NumGet(_si, 16, "UInt")
        _scrollInfo := " scroll=" _min "-" _max "/" _page
      }

      ; Build indent
      _indent := ""
      Loop, %depth%
        _indent .= "  "

      FileAppend, % TS() " | mbutton-drag | TREE | " _indent _containsClick _className " hwnd=" _child " rect=" _l "," _t "," _r "," _b _scrollInfo "`n", % Debug.Log.Path

      ; Recurse into children (limit depth to avoid infinite loops)
      If (depth < 6)
        DumpWindowTree(_child, depth + 1, clickX, clickY)
    }
    _child := DllCall("GetWindow", "Ptr", _child, "UInt", 2, "Ptr")  ; GW_HWNDNEXT
  }
}

; Power curve for scroll acceleration
; steep=false (UIA): sub-linear throughout, gentle
; steep=true (non-UIA): gentle start, steep end (slow near center, fast when dragged far)
ScrollCurve(dist, steep := false) {
  If (!steep) {
    ; UIA: gentle throughout, with damping at small distances to compensate for low threshold
    ; Damping factor: dist/(dist+12) approaches 1 as distance grows
    ; At 2px: 0.25, at 8px: 2.11, at 50px: 19.1, at 100px: 35.5
    Return dist ** 0.8 * (dist / (dist + 12))
  }
  ; Non-UIA: self-limiting curve using harmonic dampening
  ; Naturally approaches ceiling without needing caps, works across resolutions
  base := dist ** 0.9 * 2
  ceiling := 400
  Return base * ceiling / (base + ceiling)
}

; Find a scrollable child window at the given point
; Recursively enumerates all descendant windows and returns the first visible one that:
; 1. Contains the point
; 2. Has UIA ScrollPattern with ViewSize < 100 (actually scrollable)
; This fixes tabbed Explorer where MouseGetPos picks the wrong DirectUIHWND.
FindScrollableChild(parentHwnd, ptX, ptY) {
  global G_UIA
  If (!G_UIA)
    Return 0
  ; GW_CHILD=5, GW_HWNDNEXT=2
  _child := DllCall("GetWindow", "Ptr", parentHwnd, "UInt", 5, "Ptr")
  While (_child) {
    ; Check if visible
    If (DllCall("IsWindowVisible", "Ptr", _child, "Int")) {
      ; Check if point is inside window rect
      VarSetCapacity(_rect, 16, 0)
      DllCall("GetWindowRect", "Ptr", _child, "Ptr", &_rect)
      _left := NumGet(_rect, 0, "Int"), _top := NumGet(_rect, 4, "Int")
      _right := NumGet(_rect, 8, "Int"), _bottom := NumGet(_rect, 12, "Int")
      If (ptX >= _left && ptX < _right && ptY >= _top && ptY < _bottom) {
        ; Point is inside - check if this child has UIA ScrollPattern
        _el := 0, _pat := 0
        DllCall(NumGet(NumGet(G_UIA+0)+6*A_PtrSize), "Ptr", G_UIA, "Ptr", _child, "Ptr*", _el)
        If (_el) {
          DllCall(NumGet(NumGet(_el+0)+16*A_PtrSize), "Ptr", _el, "Int", 10004, "Ptr*", _pat)
          If (_pat) {
            ; Check ViewSize - must be < 100 on either axis to be scrollable
            DllCall(NumGet(NumGet(_pat+0)+8*A_PtrSize), "Ptr", _pat, "Double*", _viewSizeV)
            DllCall(NumGet(NumGet(_pat+0)+7*A_PtrSize), "Ptr", _pat, "Double*", _viewSizeH)
            ObjRelease(_pat)
            ObjRelease(_el)
            If (_viewSizeV < 99.9 || _viewSizeH < 99.9)
              Return _child  ; Found scrollable child
          } Else {
            ObjRelease(_el)
          }
        }
        ; Not scrollable - recursively check this child's descendants
        _found := FindScrollableChild(_child, ptX, ptY)
        If (_found)
          Return _found
      }
    }
    _child := DllCall("GetWindow", "Ptr", _child, "UInt", 2, "Ptr")
  }
  Return 0
}

; Find UIA ScrollPattern by walking up ancestors from a point
; Used for UWP/XAML apps (like Windows Terminal) where Win32 scrollbars don't exist
; and ElementFromHandle on the window doesn't find the ScrollViewer
; Returns: {pattern: ptr, element: ptr} if found, 0 otherwise
; Helper: Get ClassName property from UIA element (returns empty string on failure)
GetUIAClass(element) {
  VarSetCapacity(_var, 24, 0)
  DllCall("OleAut32\VariantInit", "Ptr", &_var)
  DllCall(NumGet(NumGet(element+0)+10*A_PtrSize), "Ptr", element, "Int", 30012, "Ptr", &_var)
  _class := ""
  If (NumGet(_var, 0, "UShort") = 8) {
    _bstr := NumGet(_var, 8, "Ptr")
    If (_bstr)
      _class := StrGet(_bstr, "UTF-16")
  }
  DllCall("OleAut32\VariantClear", "Ptr", &_var)
  Return _class
}

; Search UIA tree for scrollable elements (ScrollPattern or XAML ScrollBar)
; Used for UWP/XAML apps where Win32 scrollbar detection fails
FindUIAScrollAncestor(ptX, ptY) {
  global G_UIA, Debug
  If (!G_UIA)
    Return 0

  ; Get element at point: IUIAutomation::ElementFromPoint (vtable offset 7)
  VarSetCapacity(_pt, 8, 0)
  NumPut(ptX, _pt, 0, "Int"), NumPut(ptY, _pt, 4, "Int")
  _startEl := 0
  DllCall(NumGet(NumGet(G_UIA+0)+7*A_PtrSize), "Ptr", G_UIA, "Int64", NumGet(_pt, 0, "Int64"), "Ptr*", _startEl)
  If (!_startEl)
    Return 0

  _startClass := GetUIAClass(_startEl)
  _ancestorPath := _startClass  ; Build arrow-separated path for logging

  ; Get TreeWalker: IUIAutomation::get_RawViewWalker (vtable offset 14)
  _walker := 0
  DllCall(NumGet(NumGet(G_UIA+0)+14*A_PtrSize), "Ptr", G_UIA, "Ptr*", _walker)
  If (!_walker) {
    ObjRelease(_startEl)
    Return 0
  }

  ; Walk up ancestors checking for ScrollPattern (also check siblings at each level)
  _current := _startEl
  _depth := 0
  Loop {
    If (_depth >= 20)
      Break

    ; Check current element for ScrollPattern (10004)
    _pattern := 0
    DllCall(NumGet(NumGet(_current+0)+16*A_PtrSize), "Ptr", _current, "Int", 10004, "Ptr*", _pattern)
    If (_pattern) {
      DllCall(NumGet(NumGet(_pattern+0)+8*A_PtrSize), "Ptr", _pattern, "Double*", _viewSizeV)
      DllCall(NumGet(NumGet(_pattern+0)+7*A_PtrSize), "Ptr", _pattern, "Double*", _viewSizeH)
      If (_viewSizeV < 99.9 or _viewSizeH < 99.9) {
        ObjRelease(_walker)
        If (_current != _startEl)
          ObjRelease(_startEl)
        If (Debug.Log["mbutton-drag"])
          FileAppend, % TS() " | mbutton-drag | UIA_TREE | FOUND ScrollPattern | " _ancestorPath "`n", % Debug.Log.Path
        Return {pattern: _pattern, element: _current, viewV: _viewSizeV, viewH: _viewSizeH}
      }
      ObjRelease(_pattern)
    }

    ; Check siblings for ScrollPattern (some XAML layouts have ScrollViewer as sibling)
    _sibling := 0
    DllCall(NumGet(NumGet(_walker+0)+6*A_PtrSize), "Ptr", _walker, "Ptr", _current, "Ptr*", _sibling)
    _sibCount := 0
    While (_sibling and _sibCount < 10) {
      _sibCount++
      _pattern := 0
      DllCall(NumGet(NumGet(_sibling+0)+16*A_PtrSize), "Ptr", _sibling, "Int", 10004, "Ptr*", _pattern)
      If (_pattern) {
        DllCall(NumGet(NumGet(_pattern+0)+8*A_PtrSize), "Ptr", _pattern, "Double*", _viewSizeV)
        DllCall(NumGet(NumGet(_pattern+0)+7*A_PtrSize), "Ptr", _pattern, "Double*", _viewSizeH)
        If (_viewSizeV < 99.9 or _viewSizeH < 99.9) {
          ObjRelease(_walker)
          If (_current != _startEl)
            ObjRelease(_current)
          ObjRelease(_startEl)
          If (Debug.Log["mbutton-drag"])
            FileAppend, % TS() " | mbutton-drag | UIA_TREE | FOUND sibling ScrollPattern | " _ancestorPath "`n", % Debug.Log.Path
          Return {pattern: _pattern, element: _sibling, viewV: _viewSizeV, viewH: _viewSizeH}
        }
        ObjRelease(_pattern)
      }
      _nextSib := 0
      DllCall(NumGet(NumGet(_walker+0)+6*A_PtrSize), "Ptr", _walker, "Ptr", _sibling, "Ptr*", _nextSib)
      ObjRelease(_sibling)
      _sibling := _nextSib
    }
    If (_sibling)
      ObjRelease(_sibling)

    ; Get parent: IUIAutomationTreeWalker::GetParentElement (vtable offset 3)
    _parent := 0
    DllCall(NumGet(NumGet(_walker+0)+3*A_PtrSize), "Ptr", _walker, "Ptr", _current, "Ptr*", _parent)

    If (_current != _startEl) {
      ObjRelease(_current)
      _current := 0
    }

    If (!_parent)
      Break

    _parentClass := GetUIAClass(_parent)
    _ancestorPath .= " <- " . _parentClass
    _current := _parent
    _depth++
  }

  ; Parent walk failed - search children for XAML ScrollBar (UWP apps like Windows Terminal)
  _result := FindScrollInChildren(_walker, _startEl, 0, _startClass)
  If (IsObject(_result)) {
    ObjRelease(_walker)
    ObjRelease(_startEl)
    If (_current and _current != _startEl)
      ObjRelease(_current)
    Return _result
  }

  ; Not found - cleanup and log
  ObjRelease(_walker)
  ObjRelease(_startEl)
  If (_current and _current != _startEl)
    ObjRelease(_current)
  If (Debug.Log["mbutton-drag"])
    FileAppend, % TS() " | mbutton-drag | UIA_TREE | not found | " _ancestorPath "`n", % Debug.Log.Path
  Return 0
}

; Helper: recursively search children for XAML ScrollBar with Maximum > 0
; For UWP apps like Windows Terminal, the ScrollBar is a child of the content control
; and its Maximum property indicates scrollability (0 = not scrollable, >0 = scrollable)
; path: arrow-separated class path for logging (built recursively)
FindScrollInChildren(walker, element, depth, path) {
  global Debug
  If (depth > 20)
    Return 0

  _class := GetUIAClass(element)
  _curPath := path ? (path " -> " _class) : _class

  ; Check if it's a ScrollBar with Maximum > 0
  If (InStr(_class, "ScrollBar")) {
    ; Get RangeValue Maximum property (30050)
    VarSetCapacity(_var, 24, 0)
    DllCall("OleAut32\VariantInit", "Ptr", &_var)
    DllCall(NumGet(NumGet(element+0)+10*A_PtrSize), "Ptr", element, "Int", 30050, "Ptr", &_var)
    _vt := NumGet(_var, 0, "UShort")
    _maximum := 0
    If (_vt = 5)  ; VT_R8 (Double)
      _maximum := NumGet(_var, 8, "Double")
    Else If (_vt = 3)  ; VT_I4
      _maximum := NumGet(_var, 8, "Int")
    DllCall("OleAut32\VariantClear", "Ptr", &_var)

    If (_maximum > 0) {
      If (Debug.Log["mbutton-drag"])
        FileAppend, % TS() " | mbutton-drag | UIA_CHILD | FOUND ScrollBar(max=" _maximum ") | " _curPath "`n", % Debug.Log.Path
      DllCall(NumGet(NumGet(element+0)+1*A_PtrSize), "Ptr", element)  ; AddRef
      Return {scrollbar: element, maximum: _maximum, scrollable: 1}
    }
    If (Debug.Log["mbutton-drag"])
      FileAppend, % TS() " | mbutton-drag | UIA_CHILD | ScrollBar max=0 (not scrollable) | " _curPath "`n", % Debug.Log.Path
    Return 0  ; Found ScrollBar but not scrollable - no need to search deeper
  }

  ; Get first child: IUIAutomationTreeWalker::GetFirstChildElement (vtable offset 4)
  _child := 0
  DllCall(NumGet(NumGet(walker+0)+4*A_PtrSize), "Ptr", walker, "Ptr", element, "Ptr*", _child)
  While (_child) {
    _result := FindScrollInChildren(walker, _child, depth + 1, _curPath)
    If (IsObject(_result)) {
      ObjRelease(_child)
      Return _result
    }
    ; Get next sibling
    _nextSib := 0
    DllCall(NumGet(NumGet(walker+0)+6*A_PtrSize), "Ptr", walker, "Ptr", _child, "Ptr*", _nextSib)
    ObjRelease(_child)
    _child := _nextSib
  }
  Return 0
}

; Find any ScrollBar control in the window hierarchy (recursive)
; Used to detect apps with custom scrollbar controls (like SystemInformer)
FindScrollBarChild(parentHwnd) {
  _child := DllCall("GetWindow", "Ptr", parentHwnd, "UInt", 5, "Ptr")  ; GW_CHILD
  While (_child) {
    VarSetCapacity(_className, 256)
    DllCall("GetClassName", "Ptr", _child, "Str", _className, "Int", 255)
    If (InStr(_className, "ScrollBar"))
      Return _child
    ; Recursively check descendants
    _found := FindScrollBarChild(_child)
    If (_found)
      Return _found
    _child := DllCall("GetWindow", "Ptr", _child, "UInt", 2, "Ptr")  ; GW_HWNDNEXT
  }
  Return 0
}

; Log window control tree with visibility and scroll info (for debugging)
LogControlTree(parentHwnd, indent := 0) {
  global Debug
  _child := DllCall("GetWindow", "Ptr", parentHwnd, "UInt", 5, "Ptr")  ; GW_CHILD
  While (_child) {
    VarSetCapacity(_className, 256)
    DllCall("GetClassName", "Ptr", _child, "Str", _className, "Int", 255)
    _visible := DllCall("IsWindowVisible", "Ptr", _child, "Int")
    _pad := ""
    Loop, %indent%
      _pad .= "  "
    _info := _pad . _className . " [" . (_visible ? "V" : "H") . "]"
    ; For ScrollBar controls, show scroll info
    If (InStr(_className, "ScrollBar")) {
      VarSetCapacity(_si, 28, 0)
      NumPut(28, _si, 0, "UInt")
      NumPut(0x17, _si, 4, "UInt")  ; SIF_ALL
      DllCall("GetScrollInfo", "Ptr", _child, "Int", 2, "Ptr", &_si, "Int")  ; SB_CTL
      _min := NumGet(_si, 8, "Int"), _max := NumGet(_si, 12, "Int")
      _page := NumGet(_si, 16, "UInt"), _pos := NumGet(_si, 20, "Int")
      _info .= " min=" . _min . " max=" . _max . " page=" . _page . " pos=" . _pos
    }
    FileAppend, % _info "`n", % Debug.Log.Path
    ; Recurse (limit depth to 5 for more detail)
    If (indent < 5)
      LogControlTree(_child, indent + 1)
    _child := DllCall("GetWindow", "Ptr", _child, "UInt", 2, "Ptr")  ; GW_HWNDNEXT
  }
}

; Registered via OnExit("MB_Cleanup") in AutoHotkey.ahk
MB_Cleanup() {
  global MB
  If (!IsObject(MB))
    Return
  SetTimer, MBDragTimer, Off
  If (MB.Cursor.Active) {
    DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)  ; SPI_SETCURSORS
    MB.Cursor.Active := 0
  }
  If (MB.UIA.Pattern) {
    ObjRelease(MB.UIA.Pattern)
    MB.UIA.Pattern := 0
  }
  If (MB.UIA.Element) {
    ObjRelease(MB.UIA.Element)
    MB.UIA.Element := 0
  }
}
