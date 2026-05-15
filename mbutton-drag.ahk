; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === MIDDLE-BUTTON SMOOTH-SCROLL === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; Description: Smooth, fractional scrolling in Explorer (and other capable apps system-wide)
; on middle mouse button drag, mimicking Chrome's behavior as closely as possible.
; Permalink (latest): https://github.com/rodboev/AHK/
; Forum thread: https://autohotkey.com/boards/viewtopic.php?t=43715
; Author: @rodboev
; Version: 3.0

; MB_Debug: MButton scroll debug tooltips (0=off, 1=on) — set in *MButton::
; OnExit("MB_Cleanup") — registered in AutoHotkey.ahk auto-execute section

; Get scroll position for a control (cross-process safe)
; bar: 1 = vertical (default), 0 = horizontal
GetScrollPos(hwnd, bar := 1) {
  Return DllCall("GetScrollPos", "Ptr", hwnd, "Int", bar, "Int")
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
  global DebugLogEvents, DebugLogPath
  ; SCROLLINFO struct: cbSize, fMask, nMin, nMax, nPage, nPos, nTrackPos
  VarSetCapacity(_si, 28, 0)
  NumPut(28, _si, 0, "UInt")  ; cbSize
  NumPut(0x7, _si, 4, "UInt")  ; fMask = SIF_RANGE | SIF_PAGE (0x1 | 0x2 | 0x4)

  _checkV := (axis = "V" or axis = "any")
  _checkH := (axis = "H" or axis = "any")

  If (_checkV) {
    _ret := DllCall("GetScrollInfo", "Ptr", hwnd, "Int", 1, "Ptr", &_si, "Int")  ; SB_VERT=1
    _min := NumGet(_si, 8, "Int"), _max := NumGet(_si, 12, "Int"), _page := NumGet(_si, 16, "UInt")
    If (DebugLogEvents)
      FileAppend, % A_Now " | MBDrag | SCROLL_INFO_V | hwnd=" hwnd " ret=" _ret " min=" _min " max=" _max " page=" _page "`n", %DebugLogPath%
    If (_ret and _max - _min > _page)
      Return true
  }
  If (_checkH) {
    _ret := DllCall("GetScrollInfo", "Ptr", hwnd, "Int", 0, "Ptr", &_si, "Int")  ; SB_HORZ=0
    _min := NumGet(_si, 8, "Int"), _max := NumGet(_si, 12, "Int"), _page := NumGet(_si, 16, "UInt")
    If (DebugLogEvents)
      FileAppend, % A_Now " | MBDrag | SCROLL_INFO_H | hwnd=" hwnd " ret=" _ret " min=" _min " max=" _max " page=" _page "`n", %DebugLogPath%
    If (_ret and _max - _min > _page)
      Return true
  }
  Return false
}

; Find a visible ScrollBar control with actual scroll range (recursive)
; This detects true scrollability for apps like Explorer where DirectUIHWND
; doesn't respond to GetScrollInfo, but has separate ScrollBar controls
FindVisibleScrollBar(parentHwnd) {
  global DebugLogEvents, DebugLogPath
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
        If (DebugLogEvents)
          FileAppend, % A_Now " | MBDrag | SCROLLBAR_FOUND | hwnd=" _child " ret=" _ret " min=" _min " max=" _max " page=" _page "`n", %DebugLogPath%
        If (_ret and _max > _min)
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

; Power curve for scroll acceleration
; steep=false (UIA): sub-linear throughout, gentle
; steep=true (non-UIA): gentle start, steep end (slow near center, fast when dragged far)
ScrollCurve(dist, steep := false) {
  If (!steep)
    Return dist ** 0.8  ; UIA: gentle throughout
  ; Non-UIA: exponent increases with distance (0.7 at 0px → 1.4 at 200px)
  ; This gives gentle start but aggressive acceleration when dragged far
  exp := 0.7 + (dist / 300)
  Return dist ** exp
}

; Find a scrollable child window at the given point (mimics Windhawk smooth-scroll FindChild)
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
  global DebugLogPath
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
    FileAppend, %_info%`n, %DebugLogPath%
    ; Recurse (limit depth to 5 for more detail)
    If (indent < 5)
      LogControlTree(_child, indent + 1)
    _child := DllCall("GetWindow", "Ptr", _child, "UInt", 2, "Ptr")  ; GW_HWNDNEXT
  }
}

; -> [ MButton + drag ] -> Invoke smooth scrolling on any app; release to stop.
*MButton::
  ; Session state object — single global, properties need no separate declarations
  global MB := {Debug: 1, Threshold: 8}  ; Debug tooltips, activation distance (px)

  ; Core session state
  MB.X1 := 0, MB.Y1 := 0, MB.Win := 0, MB.Ctrl := 0
  MB.ClassName := "", MB.ProcName := ""
  MB.Triggered := 0, MB.Disabled := 0, MB.DeferredDown := 0
  MB.Method := "VSCROLL", MB.FallbackChecked := 0, MB.ScrollBarChecked := 0
  MB.ScrollTicks := 0, MB.SessionStart := 0

  ; UIA state (COM pointers and scroll accumulators)
  MB.UIA := {Pattern: 0, Element: 0, ViewSize: 10.0, ViewSizeH: 10.0, AccumPct: -1, AccumPctH: -1}

  ; Native scroll probe state
  MB.Probe := {Active: 0, InitScrollPos: 0, InitScrollPct: 0.0, InitHCursor: 0}

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
      hCopy := DllCall("CopyImage", "Ptr", G_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
      DllCall("SetSystemCursor", "Ptr", hCopy, "UInt", 32512)
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
      hCopy := DllCall("CopyImage", "Ptr", G_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
      DllCall("SetSystemCursor", "Ptr", hCopy, "UInt", 32512)
    } Else {
      MB.Cursor.Pending := 1
    }
    If (MB.Debug)
      ToolTip, % "SysListView32 -> LVM_SCROLL (pixel-level)"
    If (DebugLogEvents) {
      _ts := A_Now
      _proc := MB.ProcName, _class := MB.ClassName
      FileAppend, %_ts% | MBDrag | START | proc=%_proc% method=LVM ctrl=%_class%`n, %DebugLogPath%
    }
    SetTimer, MBDragTimer, 10
    Return
  }

  ; SET UP UIA (for both native scroll detection and potential custom scroll)
  ; Use FindScrollableChild to enumerate child windows and find one with ScrollPattern.
  ; This mimics Windhawk's smooth-scroll approach: MouseGetPos can pick the wrong DirectUIHWND
  ; in tabbed Explorer, so we enumerate all children and find the one that's actually scrollable.

  ; Dump control tree for Explorer windows (debug)
  If (DebugLogEvents and MB.WinClass = "CabinetWClass") {
    FileAppend, % A_Now " | MBDrag | CONTROL_TREE | win=" MB.Win "`n", %DebugLogPath%
    LogControlTree(MB.Win)
    FileAppend, % "--- END TREE ---`n", %DebugLogPath%
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

  If (DebugLogEvents)
    FileAppend, % A_Now " | MBDrag | UIA_SETUP | scrollChild=" _scrollChild " scrollElement=" _scrollElement " pattern=" _pattern " fallback=" _fallback "`n", %DebugLogPath%

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
  _pattern := MB.UIA.Pattern
  If (_pattern)
    DllCall(NumGet(NumGet(_pattern+0)+6*A_PtrSize), "Ptr", _pattern, "Double*", _initPct)
    , MB.Probe.InitScrollPct := _initPct

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
      If (DebugLogEvents)
        FileAppend, % A_Now " | MBDrag | SCROLLBAR_VISIBLE | hwnd=" _visibleScrollBar "`n", %DebugLogPath%
    }
  }

  If (_hasScrollRange) {
    ; Win32 confirms scroll range exists — show immediately
    MB.Cursor.Active := 1
    hCopy := DllCall("CopyImage", "Ptr", G_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
    DllCall("SetSystemCursor", "Ptr", hCopy, "UInt", 32512)
    If (DebugLogEvents)
      FileAppend, % A_Now " | MBDrag | CURSOR_DOWN | scrollRange=1`n", %DebugLogPath%
  } Else If (MB.UIA.Pattern) {
    ; Has UIA pattern but no Win32 scrollbar detected — defer cursor until scroll verified
    MB.Cursor.Pending := 1
    If (DebugLogEvents)
      FileAppend, % A_Now " | MBDrag | CURSOR_PENDING | pattern=" MB.UIA.Pattern " viewV=" Round(MB.UIA.ViewSize, 1) " noScrollBar`n", %DebugLogPath%
  } Else {
    ; No UIA pattern and no scrollbar — skip cursor entirely
    If (DebugLogEvents)
      FileAppend, % A_Now " | MBDrag | CURSOR_SKIP | noPattern noScrollBar`n", %DebugLogPath%
  }

  ; Start timer in native probe mode
  MB.Probe.Active := 1
  SetTimer, MBDragTimer, 10
Return 

MBDragTimer:
  Critical ; Prevent MButton Up from interrupting mid-DllCall (race condition safety)
  global MB, G_hSizeAll, DebugLogEvents, DebugLogPath  ; MB object + singletons + external globals

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
    If (MB.Debug)
      ToolTip
    Return
  }

  ; ===== NATIVE SCROLL PROBE PHASE =====
  ; Detect if the app handles MButton drag-scroll natively.
  ; Three signals: cursor change, Win32 scroll pos, UIA scroll percent.
  ; Movement-gated: cursor checked every tick; scroll pos checked after 3px; concludes at 8px.
  If (MB.Probe.Active > 0) {
    nativeDetected := false

    ; Signal 1: Cursor changed to a custom bitmap (e.g., Chrome/Firefox autoscroll icon)
    ; Requires A_Cursor = "Unknown" to ignore standard cursor changes (Explorer selection, etc.)
    VarSetCapacity(ci, 16 + A_PtrSize, 0)
    NumPut(16 + A_PtrSize, ci, 0, "UInt")
    DllCall("GetCursorInfo", "Ptr", &ci)
    If (NumGet(ci, 8, "UPtr") != MB.Probe.InitHCursor and A_Cursor = "Unknown")
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

      ; Keep probing until 8px movement gate (matches custom scroll threshold)
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
      If (MB.Debug) {
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
    If (MB.Debug)
      ToolTip, % "No native scroll — using " MB.Method
    ; Log session start
    If (DebugLogEvents) {
      _ts := A_Now
      _proc := MB.ProcName, _method := MB.Method, _class := MB.ClassName
      _pattern := MB.UIA.Pattern, _viewV := MB.UIA.ViewSize, _viewH := MB.UIA.ViewSizeH
      FileAppend, %_ts% | MBDrag | START | proc=%_proc% method=%_method% ctrl=%_class% pattern=%_pattern% viewV=%_viewV% viewH=%_viewH%`n, %DebugLogPath%
    }
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
      If (MB.Debug)
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
        If (_newPctV != MB.Probe.InitScrollPct or (_newPctH >= 0 and _newPctH != MB.UIA.AccumPctH)) {
          MB.Cursor.Active := 1
          MB.Cursor.Pending := 0
          hCopy := DllCall("CopyImage", "Ptr", G_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
          DllCall("SetSystemCursor", "Ptr", hCopy, "UInt", 32512)
          If (DebugLogEvents)
            FileAppend, % A_Now " | MBDrag | CURSOR_CONFIRMED | method=UIA pctV=" Round(_newPctV, 1) "`n", %DebugLogPath%
        }
      }

      ; Log every 5 ticks for jitter debugging
      If (DebugLogEvents && Mod(MB.ScrollTicks, 5) = 0) {
        DllCall("QueryPerformanceFrequency", "Int64*", _qpcFreq)
        _uiaMs := Round((_qpcAfter - _qpcBefore) * 1000.0 / _qpcFreq, 2)
        _scrollTarget := MB.Ctrl ? MB.Ctrl : MB.Win
        _win32Pos := GetScrollPos(_scrollTarget)
        FileAppend, % A_Now " | MBDrag | UIA | proc=" MB.ProcName " tick=" MB.ScrollTicks " V=" Round(MB.UIA.AccumPct, 1) " H=" Round(MB.UIA.AccumPctH, 1) " win32=" _win32Pos " callMs=" _uiaMs "`n", %DebugLogPath%
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
        ; Fall back only if ALL intended axes report NoScroll
        _vertIntended := (AbsDistY >= MB.Threshold)
        _horizIntended := (AbsDistX >= MB.Threshold)
        _allNoScroll := (_vertIntended and _noScrollV or !_vertIntended) and (_horizIntended and _noScrollH or !_horizIntended)
        If (_vertIntended and _noScrollV and _horizIntended and _noScrollH) or (_vertIntended and _noScrollV and !_horizIntended) or (!_vertIntended and _horizIntended and _noScrollH) {
          ; Intended axis(es) report NoScroll — fall back to WHEEL
          ObjRelease(_pattern)
          MB.UIA.Pattern := 0
          _element := MB.UIA.Element
          ObjRelease(_element)
          MB.UIA.Element := 0
          MB.Method := "WHEEL"
          If (MB.Debug)
            ToolTip, % "UIA->WHEEL (NoScroll sentinel)"
          If (DebugLogEvents)
            FileAppend, % A_Now " | MBDrag | FALLBACK | proc=" MB.ProcName " UIA->WHEEL (NoScroll V=" _noScrollV " H=" _noScrollH ")`n", %DebugLogPath%
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
        ; Cap at 3x rowHeight to prevent jumping too many rows at once
        If (MB.LVM.RowQuantized) {
          scrollPixelsY := Max(MB.LVM.RowHeight + 1, scrollPixelsY)
          scrollPixelsY := Min(MB.LVM.RowHeight * 3, scrollPixelsY)
        }
        If (SignedDistY < 0)
          scrollPixelsY := -scrollPixelsY
      }
      If (AbsDistX >= MB.Threshold) {
        horizMultiplier := MB.LVM.RowQuantized ? 3.0 : 1.0
        scrollPixelsX := Max(1, Floor(curveValueX * pixelMultiplier * horizMultiplier))
        If (SignedDistX < 0)
          scrollPixelsX := -scrollPixelsX
      }

      ; --- Row-quantization detection on first vertical scroll ---
      If (!MB.LVM.Detected and AbsDistY >= MB.Threshold) {
        ; Cap detection scroll to 50px max — we don't know row height yet, and
        ; uncapped values (thousands of pixels) cause massive jumps before cap kicks in
        detectScrollY := (scrollPixelsY > 0) ? Min(50, scrollPixelsY) : Max(-50, scrollPixelsY)
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
        ; - delta ≈ sentPixels (within 0.3x-1.5x): pixel-level scrolling (HIGH CONFIDENCE)
        ; - delta=0 with virtual=1: below row threshold -> row-quantized (HIGH CONFIDENCE)
        ; - delta=0 with virtual=0: might be at boundary, assume pixel-level (LOW CONFIDENCE)
        ; - delta way off from sent: row-quantized
        deltaRatio := (sentPixels > 0) ? (scrollDelta / sentPixels) : 0
        If (deltaRatio >= 0.3 and deltaRatio <= 1.5) {
          ; Pixel-level: delta ≈ sentPixels (high confidence - prevents SLOW-TICK override)
          MB.LVM.RowQuantized := 0
          MB.LVM.DetectConfident := 1
          If (DebugLogEvents)
            FileAppend, % A_Now " | MBDrag | DETECT | proc=" MB.ProcName " PIXEL-LEVEL delta=" scrollDelta " sent=" sentPixels " ratio=" Round(deltaRatio, 2) " virtual=" _isVirtual "`n", %DebugLogPath%
        } Else If (scrollDelta = 0 and !_isVirtual) {
          ; delta=0 on non-virtual ListView: likely at boundary, assume pixel-level (low confidence)
          MB.LVM.RowQuantized := 0
          MB.LVM.DetectConfident := 0  ; Allow SLOW-TICK to upgrade if truly slow
          If (DebugLogEvents)
            FileAppend, % A_Now " | MBDrag | DETECT | proc=" MB.ProcName " PIXEL-LEVEL (boundary) delta=0 sent=" sentPixels " virtual=" _isVirtual "`n", %DebugLogPath%
        } Else If (_isVirtual) {
          ; Virtual ListView with delta off -> row-quantized (high confidence)
          MB.LVM.RowQuantized := 1
          MB.LVM.DetectConfident := 1
          ; Set row height from detection or use conservative default
          ; (LVM_GETITEMRECT requires cross-process memory allocation, too complex)
          If (scrollDelta > 0 and scrollDelta > sentPixels) {
            MB.LVM.RowHeight := scrollDelta
          } Else {
            MB.LVM.RowHeight := 25  ; Conservative default when we can't measure
          }
          If (DebugLogEvents)
            FileAppend, % A_Now " | MBDrag | DETECT | proc=" MB.ProcName " ROW-QUANTIZED rowH=" MB.LVM.RowHeight " delta=" scrollDelta " sent=" sentPixels " ratio=" Round(deltaRatio, 2) " virtual=" _isVirtual "`n", %DebugLogPath%
        } Else {
          ; Non-virtual with weird ratio: uncertain, stay pixel-level but allow upgrade
          MB.LVM.RowQuantized := 0
          MB.LVM.DetectConfident := 0
          If (DebugLogEvents)
            FileAppend, % A_Now " | MBDrag | DETECT | proc=" MB.ProcName " PIXEL-LEVEL (uncertain) delta=" scrollDelta " sent=" sentPixels " ratio=" Round(deltaRatio, 2) " virtual=" _isVirtual "`n", %DebugLogPath%
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
        If (MB.Debug) {
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
        If (MB.LVM.BoundaryY != 0 and DebugLogEvents)
          FileAppend, % A_Now " | MBDrag | BOUNDARY | Y axis dir=" MB.LVM.BoundaryY " before=" _posBeforeY " after=" _posAfterY " max=" _scrollMaxY "`n", %DebugLogPath%
      }

      LVM_PostVertical:
      ; Recalculate horizontal with correct multiplier (2x for row-quantized views)
      If (AbsDistX >= MB.Threshold) {
        horizMultiplier := MB.LVM.RowQuantized ? 3.0 : 1.0
        scrollPixelsX := Max(1, Floor(curveValueX * pixelMultiplier * horizMultiplier))
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
        hCopy := DllCall("CopyImage", "Ptr", G_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
        DllCall("SetSystemCursor", "Ptr", hCopy, "UInt", 32512)
        If (DebugLogEvents)
          FileAppend, % A_Now " | MBDrag | CURSOR_CONFIRMED | method=LVM`n", %DebugLogPath%
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
        If (DebugLogEvents)
          FileAppend, % A_Now " | MBDrag | DETECT | proc=" MB.ProcName " SLOW-TICK->QUANTIZED ms=" Round(_scrollMs) "`n", %DebugLogPath%
      }

      MB.ScrollTicks++
      If (MB.Debug) {
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
      If (DebugLogEvents && Mod(MB.ScrollTicks, 5) = 0) {
        _pxYLog := (scrollAxisY and AbsDistY >= MB.Threshold and !_atBoundaryY) ? scrollPixelsY : 0
        _pxXLog := (scrollAxisX and AbsDistX >= MB.Threshold) ? scrollPixelsX : 0
        If (!MB.LVM.Detected)
          _modeLog := "?"
        Else
          _modeLog := (MB.LVM.RowQuantized ? "Q" : "P") . ":" . (MB.LVM.DetectConfident ? "h" : "l")
        FileAppend, % A_Now " | MBDrag | LVM[" _modeLog "] | proc=" MB.ProcName " tick=" MB.ScrollTicks " dY=" _pxYLog " dX=" _pxXLog " pos=" _posAfterY "/" _scrollMaxY " ms=" Round(_scrollMs) "`n", %DebugLogPath%
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
            If (MB.Debug)
              ToolTip, % "WHEEL_CTRL->VSCROLL (jumped " scrolledUnits " units)"
            If (DebugLogEvents)
              FileAppend, % A_Now " | MBDrag | FALLBACK | proc=" MB.ProcName " WHEEL_CTRL->VSCROLL (jumped " scrolledUnits " units)`n", %DebugLogPath%
          }
          ; Scroll succeeded — show cursor if pending (position changed OR was already non-zero)
          If (MB.Cursor.Pending and (scrolledUnits > 0 or posBefore > 0)) {
            If (scrolledUnits > 0) {
              MB.Cursor.Active := 1
              MB.Cursor.Pending := 0
              hCopy := DllCall("CopyImage", "Ptr", G_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
              DllCall("SetSystemCursor", "Ptr", hCopy, "UInt", 32512)
              If (DebugLogEvents)
                FileAppend, % A_Now " | MBDrag | CURSOR_CONFIRMED | method=WHEEL_CTRL scrolled=%scrolledUnits%`n", %DebugLogPath%
            }
            ; posBefore > 0 but no scroll: scrollbar exists, might be at boundary — keep trying
          }
          ; posBefore=0, posAfter=0: can't verify (custom scrollbar) — will use tick-count fallback below
          If (scrolledUnits > 0)
            MB.FallbackChecked := 1
        }
      }

      ; Fallback for custom scrollbars (like SystemInformer's PhTreeNew)
      ; Check after 8px movement threshold, only once per session
      ; Only activate if the TARGET CONTROL has VISIBLE ScrollBar children with actual scroll range
      ; Explorer has hidden scrollbars always present - must check visibility
      If (MB.Cursor.Pending and !MB.ScrollBarChecked and (AbsDistY >= MB.Threshold or AbsDistX >= MB.Threshold)) {
        MB.ScrollBarChecked := 1
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
            _min := NumGet(_si, 8, "Int"), _max := NumGet(_si, 12, "Int")
            _scrollbarHasRange := (_ret and _max > _min)
          }
        }
        If (DebugLogEvents)
          FileAppend, % A_Now " | MBDrag | SCROLLBAR_CHECK | ctrl=" MB.Ctrl " childScrollbar=" _childScrollbar " visible=" _scrollbarVisible " hasRange=" _scrollbarHasRange "`n", %DebugLogPath%
        If (_scrollbarHasRange) {
          MB.Cursor.Active := 1
          MB.Cursor.Pending := 0
          hCopy := DllCall("CopyImage", "Ptr", G_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
          DllCall("SetSystemCursor", "Ptr", hCopy, "UInt", 32512)
          If (DebugLogEvents)
            FileAppend, % A_Now " | MBDrag | CURSOR_CONFIRMED | method=WHEEL_CTRL (ctrl has scrollbar child)`n", %DebugLogPath%
        }
      }

      MB.ScrollTicks++

      ; Horizontal: WM_MOUSEHWHEEL (0x20E) — 2x multiplier for perceptual parity with vertical
      If (AbsDistX >= MB.Threshold) {
        magnitudeX := Max(1, Min(119, Floor(curveValueX)))  ; 2x: removed /2
        DeltaX := (SignedDistX > 0) ? magnitudeX : -magnitudeX
        wParamX := DeltaX << 16
        PostMessage, 0x20E, %wParamX%, %lParam%,, ahk_id %target%
      }

      If (MB.Debug && MB.Method = "WHEEL_CTRL")
        ToolTip, % "WHEEL_CTRL: dY=" (AbsDistY >= MB.Threshold ? DeltaY : 0) " dX=" (AbsDistX >= MB.Threshold ? DeltaX : 0)

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
            hCopy := DllCall("CopyImage", "Ptr", G_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
            DllCall("SetSystemCursor", "Ptr", hCopy, "UInt", 32512)
            If (DebugLogEvents)
              FileAppend, % A_Now " | MBDrag | CURSOR_CONFIRMED | method=VSCROLL`n", %DebugLogPath%
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

      If (MB.Debug)
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
            If (MB.Debug)
              ToolTip, % "WHEEL->WHEEL_CTRL (no movement)"
            If (DebugLogEvents)
              FileAppend, % A_Now " | MBDrag | FALLBACK | proc=" MB.ProcName " WHEEL->WHEEL_CTRL (no movement)`n", %DebugLogPath%
          } Else If (_hasScrollbar) {
            MB.FallbackChecked := 1
            ; Scroll succeeded — show cursor if pending
            If (MB.Cursor.Pending) {
              MB.Cursor.Active := 1
              MB.Cursor.Pending := 0
              hCopy := DllCall("CopyImage", "Ptr", G_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
              DllCall("SetSystemCursor", "Ptr", hCopy, "UInt", 32512)
              If (DebugLogEvents)
                FileAppend, % A_Now " | MBDrag | CURSOR_CONFIRMED | method=WHEEL`n", %DebugLogPath%
            }
          } Else If (MB.Ctrl) {
            ; No scrollbar + has control — can't verify via GetScrollPos, but WHEEL_CTRL
            ; (sends to control) is more likely to work than WHEEL (sends to window)
            MB.Method := "WHEEL_CTRL"
            MB.FallbackChecked := 0
            If (MB.Debug)
              ToolTip, % "WHEEL->WHEEL_CTRL (no scrollbar, has control)"
            If (DebugLogEvents)
              FileAppend, % A_Now " | MBDrag | FALLBACK | proc=" MB.ProcName " WHEEL->WHEEL_CTRL (no scrollbar, control=" MB.ClassName ")`n", %DebugLogPath%
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

      If (MB.Debug && MB.Method = "WHEEL")
        ToolTip, % "WHEEL: dY=" (AbsDistY >= MB.Threshold ? DeltaY : "-") " dX=" (AbsDistX >= MB.Threshold ? DeltaX : "-") " hTgt=" (MB.FallbackChecked ? "win" : "ctrl")
    }
  }
Return

*MButton Up::
  Critical ; Prevent timer from firing during cleanup (race condition safety)
  global MB, DebugLogEvents, DebugLogPath
  SetTimer, MBDragTimer, Off
  ; Restore system cursor
  If (MB.Cursor.Active) {
    DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)  ; SPI_SETCURSORS
    MB.Cursor.Active := 0
  }
  MB.Cursor.Pending := 0
  ; Log session summary
  If (DebugLogEvents && MB.Triggered) {
    _duration := A_TickCount - MB.SessionStart
    FileAppend, % A_Now " | MBDrag | END | proc=" MB.ProcName " method=" MB.Method " ticks=" MB.ScrollTicks " duration=" _duration "ms`n", %DebugLogPath%
  }
  If (MB.Debug)
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
