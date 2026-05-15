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

; Get vertical scroll position for a control (cross-process safe)
GetScrollPos(hwnd) {
  Return DllCall("GetScrollPos", "Ptr", hwnd, "Int", 1, "Int")
}

; Check if a control has a Win32 vertical scrollbar (for fallback detection)
HasWin32Scrollbar(hwnd) {
  DllCall("GetScrollRange", "Ptr", hwnd, "Int", 1, "Int*", scrollMin, "Int*", scrollMax)
  Return (scrollMax > scrollMin)
}

; Power curve for scroll acceleration: gentle start, ramps up with distance
; Returns 0-63 for 0-100px, then slower growth beyond (0.6 exponent)
ScrollCurve(dist) {
  If (dist <= 100)
    Return dist ** 0.8
  Return (100 ** 0.8) + ((dist - 100) ** 0.6)
}

; -> [ MButton + drag ] -> Invoke smooth scrolling on any app; release to stop.
*MButton::
  global MB_Debug := 1  ; Debug tooltips (0=off, 1=on)
  global MB_X1, MB_Y1, MB_Win, MB_ClassName, MB_Triggered, MB_ProcName
  global MB_ScrollPattern := 0, MB_Element := 0, MB_Ctrl
  global MB_Disabled := 0, MB_DeferredDown := 0, MB_ViewSize := 10.0, MB_AccumPct := -1
  global MB_ViewSizeH := 10.0, MB_AccumPctH := -1
  global MB_Method := "VSCROLL" ; Default fallback
  global MB_FallbackChecked := 0  ; Check fallback once per drag
  global MB_NativeProbe := 0, MB_InitScrollPos := 0, MB_InitScrollPct := 0.0, MB_InitHCursor := 0
  global MB_ScrollTicks := 0, MB_SessionStart := 0  ; For logging
  ; LVM-specific: row-quantization detection and EMA axis tracking
  global MB_LVM_Detected := 0       ; 0=not yet, 1=detected
  global MB_LVM_RowQuantized := 0   ; 0=pixel-level (dual-axis OK), 1=row-quantized (needs EMA restriction)
  global MB_LVM_RowHeight := 20     ; Detected row height or default
  global MB_LVM_DetectConfident := 0  ; 1 if detection was high-confidence (ratio-based), prevents SLOW-TICK override
  global MB_EMA_Y := 0.0, MB_EMA_X := 0.0  ; Movement intensity EMAs for axis determination
  global MB_PrevDistY := 0, MB_PrevDistX := 0  ; Previous tick's distance (for delta calc)
  ; Boundary detection: tracks when vertical scrolling hits min/max and stops sending futile messages
  ; 0=free, -1=stuck at min (can't scroll up), 1=stuck at max (can't scroll down)
  global MB_LVM_BoundaryY := 0
  ; SizeAll cursor: shown during custom scroll to indicate drag-scroll mode
  global MB_CursorActive := 0

  ; ===========================================
  ; UI Automation (UIA) — Lazy init on first MButton use
  ; Docs: https://learn.microsoft.com/en-us/windows/win32/winauto/uiauto-entry
  ; ===========================================
  ; COM Class/Interface (from UIAutomationClient.h)
  ;   CLSID_CUIAutomation = {ff48dba4-60ef-4201-aa87-54103eef594e}
  ;   IID_IUIAutomation   = {30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}

  global G_UIA
  If (!G_UIA) {
    G_UIA := ComObjCreate("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
    OnExit("G_UIACleanup")  ; Register cleanup (G_UIACleanup defined in AutoHotkey.ahk)
  }

  ; SizeAll cursor: load once, reused across sessions
  global MB_hSizeAll
  If (!MB_hSizeAll)
    MB_hSizeAll := DllCall("LoadCursor", "Ptr", 0, "Ptr", 32646, "Ptr")  ; IDC_SIZEALL

  MouseGetPos,,, MB_Win, MB_ClassName
  WinGetClass, ahk_class, ahk_id %MB_Win%

  ; EXCLUDED CONTROLS (toolbars, edit boxes, headers — never scroll these)
  MB_ExcludedControls := ["ToolbarWindow", "ReBarWindow", "Edit", "AddressBandRoot", "statusbar", "SysHeader", "Shell_TrayWnd", "Shell_SecondaryTrayWnd"]
  IsExcludedRegion := HasVal(MB_ExcludedControls, MB_ClassName) or (not MB_ClassName and not (ahk_class = "Shell_TrayWnd" or ahk_class = "WorkerW"))
  If (IsExcludedRegion) {
    MB_Disabled := 1
    SendInput, {Blind}{MButton Down}
    Return
  }

  ; Capture cursor handle before passing MButton to app (Chrome changes cursor immediately)
  ; Uses HCURSOR handle (not A_Cursor name) to detect custom cursor changes
  VarSetCapacity(ci, 16 + A_PtrSize, 0)
  NumPut(16 + A_PtrSize, ci, 0, "UInt")
  DllCall("GetCursorInfo", "Ptr", &ci)
  MB_InitHCursor := NumGet(ci, 8, "UPtr")

  ; Defer MButton Down for Explorer to prevent click actions during scroll
  ; (e.g., middle-clicking a navbar item opens a new tab before scroll starts)
  ; Non-Explorer apps get immediate passthrough for native scroll detection
  If (ahk_class = "CabinetWClass") {
    MB_DeferredDown := 1
  } Else {
    SendInput, {Blind}{MButton Down}
  }
  MB_Disabled := 0

  ; Activate Explorer window if clicking on inactive one
  If (ahk_class = "CabinetWClass") {
    WinGet, activeWin, ID, A
    If (MB_Win != activeWin) {
      WinActivate, ahk_id %MB_Win%
    }
  }

  ; Capture initial mouse coords
  CoordMode, Mouse, Screen
  MouseGetPos, MB_X1, MB_Y1

  ; Get control window handle (hwnd) and process name for logging
  ControlGet, MB_Ctrl, Hwnd,, %MB_ClassName%, ahk_id %MB_Win%
  WinGet, MB_ProcName, ProcessName, ahk_id %MB_Win%
  MB_Triggered := 0
  MB_ScrollTicks := 0
  MB_SessionStart := A_TickCount

  ; TreeView controls → direct to VSCROLL (skip native probe, never has native MButton scroll)
  If (InStr(MB_ClassName, "SysTreeView32")) {
    MB_Method := "VSCROLL"
    MB_NativeProbe := 0
    ; Show cursor immediately (TreeView is always scrollable)
    MB_CursorActive := 1  ; Set flag first (race safety: cleanup will restore if interrupted)
    hCopy := DllCall("CopyImage", "Ptr", MB_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
    DllCall("SetSystemCursor", "Ptr", hCopy, "UInt", 32512)
    SetTimer, MBDragTimer, 150
    Return
  }

  ; SysListView32 controls → direct to LVM_SCROLL for pixel-level precision
  ; UIA SetScrollPercent causes jitter on short lists (percentage rounds to discrete positions)
  If (InStr(MB_ClassName, "SysListView32")) {
    MB_Method := "LVM"
    MB_NativeProbe := 0
    ; Show cursor immediately (ListView is always scrollable)
    MB_CursorActive := 1  ; Set flag first (race safety)
    hCopy := DllCall("CopyImage", "Ptr", MB_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
    DllCall("SetSystemCursor", "Ptr", hCopy, "UInt", 32512)
    If (MB_Debug)
      ToolTip, % "SysListView32 → LVM_SCROLL (pixel-level)"
    If (DebugLogEvents) {
      _ts := A_Now
      FileAppend, %_ts% | MBDrag | START | proc=%MB_ProcName% method=LVM ctrl=%MB_ClassName%`n, %DebugLogPath%
    }
    SetTimer, MBDragTimer, 10
    Return
  }

  ; SET UP UIA (for both native scroll detection and potential custom scroll)
  targetForUIA := MB_Ctrl ? MB_Ctrl : MB_Win
  DllCall(NumGet(NumGet(G_UIA+0)+6*A_PtrSize), "Ptr", G_UIA, "Ptr", targetForUIA, "Ptr*", MB_Element)
  If (MB_Element) {
    DllCall(NumGet(NumGet(MB_Element+0)+16*A_PtrSize), "Ptr", MB_Element, "Int", 10004, "Ptr*", MB_ScrollPattern)
    If (MB_ScrollPattern) {
      DllCall(NumGet(NumGet(MB_ScrollPattern+0)+8*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_ViewSize)
      If (MB_ViewSize < 1)
        MB_ViewSize := 10.0
      ; Horizontal ViewSize (vtable offset 7)
      DllCall(NumGet(NumGet(MB_ScrollPattern+0)+7*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_ViewSizeH)
      If (MB_ViewSizeH < 1)
        MB_ViewSizeH := 10.0
    }
  }

  ; Capture initial scroll state for native detection
  probeTarget := MB_Ctrl ? MB_Ctrl : MB_Win
  MB_InitScrollPos := GetScrollPos(probeTarget)
  MB_InitScrollPct := -1.0
  If (MB_ScrollPattern)
    DllCall(NumGet(NumGet(MB_ScrollPattern+0)+6*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_InitScrollPct)

  ; Show SizeAll cursor on MButton down IF area appears scrollable
  ; Scrollable = UIA ScrollPattern exists with ViewSize < 100 (content larger than view)
  ;            OR has Win32 scrollbar
  ; Note: When pattern=0, ViewSize defaults to 10.0 which is meaningless — don't use it
  MB_CursorPending := 0
  If (MB_ScrollPattern and (MB_ViewSize < 99.9 or MB_ViewSizeH < 99.9)) {
    ; Known scrollable (UIA confirms content > view)
    MB_CursorActive := 1  ; Set flag first (race safety)
    hCopy := DllCall("CopyImage", "Ptr", MB_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
    DllCall("SetSystemCursor", "Ptr", hCopy, "UInt", 32512)  ; OCR_NORMAL
    If (DebugLogEvents)
      FileAppend, % A_Now " | MBDrag | CURSOR_DOWN | pattern=" MB_ScrollPattern " viewV=" Round(MB_ViewSize, 1) " viewH=" Round(MB_ViewSizeH, 1) "`n", %DebugLogPath%
  } Else If (MB_ScrollPattern and MB_ViewSize >= 99.9 and MB_ViewSizeH >= 99.9) {
    ; Known non-scrollable (UIA confirms view == content)
    If (DebugLogEvents)
      FileAppend, % A_Now " | MBDrag | CURSOR_SKIP | pattern=" MB_ScrollPattern " viewV=" Round(MB_ViewSize, 1) " viewH=" Round(MB_ViewSizeH, 1) " (non-scrollable)`n", %DebugLogPath%
  } Else If (!MB_ScrollPattern and HasWin32Scrollbar(probeTarget)) {
    ; Known scrollable (Win32 scrollbar present)
    MB_CursorActive := 1  ; Set flag first (race safety)
    hCopy := DllCall("CopyImage", "Ptr", MB_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
    DllCall("SetSystemCursor", "Ptr", hCopy, "UInt", 32512)
    If (DebugLogEvents)
      FileAppend, % A_Now " | MBDrag | CURSOR_DOWN | win32scrollbar=1`n", %DebugLogPath%
  } Else {
    ; Unknown scrollability — defer cursor until first successful scroll
    MB_CursorPending := 1
    If (DebugLogEvents)
      FileAppend, % A_Now " | MBDrag | CURSOR_PENDING | pattern=" MB_ScrollPattern " viewV=" Round(MB_ViewSize, 1) " viewH=" Round(MB_ViewSizeH, 1) "`n", %DebugLogPath%
  }

  ; Start timer in native probe mode
  MB_NativeProbe := 1
  SetTimer, MBDragTimer, 10
Return 

MBDragTimer:
  Critical ; Prevent MButton Up from interrupting mid-DllCall (race condition safety)
  global MB_Debug, MB_AccumPct, MB_AccumPctH, MB_Method, MB_ViewSize, MB_ViewSizeH, MB_Ctrl, MB_FallbackChecked
  global MB_NativeProbe, MB_InitScrollPos, MB_InitScrollPct, MB_InitHCursor
  global MB_ProcName, MB_ScrollTicks, DebugLogEvents, DebugLogPath
  global MB_LVM_Detected, MB_LVM_RowQuantized, MB_LVM_RowHeight, MB_LVM_DetectConfident, MB_LVM_BoundaryY
  global MB_EMA_Y, MB_EMA_X, MB_PrevDistY, MB_PrevDistX
  global MB_CursorActive, MB_CursorPending, MB_hSizeAll
  ; Safety check: if MButton released, stop immediately
  If !GetKeyState("MButton", "P") {
    SetTimer, MBDragTimer, Off
    ; Restore cursor if we changed it (edge case: MButton Up didn't fire)
    If (MB_CursorActive) {
      DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)
      MB_CursorActive := 0
    }
    MB_CursorPending := 0
    If (MB_Debug)
      ToolTip
    Return
  }

  ; ===== NATIVE SCROLL PROBE PHASE =====
  ; Detect if the app handles MButton drag-scroll natively.
  ; Three signals: cursor change, Win32 scroll pos, UIA scroll percent.
  ; Movement-gated: cursor checked every tick; scroll pos checked after 3px; concludes at 8px.
  If (MB_NativeProbe > 0) {
    nativeDetected := false

    ; Signal 1: Cursor changed to a custom bitmap (e.g., Chrome/Firefox autoscroll icon)
    ; Requires A_Cursor = "Unknown" to ignore standard cursor changes (Explorer selection, etc.)
    VarSetCapacity(ci, 16 + A_PtrSize, 0)
    NumPut(16 + A_PtrSize, ci, 0, "UInt")
    DllCall("GetCursorInfo", "Ptr", &ci)
    If (NumGet(ci, 8, "UPtr") != MB_InitHCursor and A_Cursor = "Unknown")
      nativeDetected := true

    If (!nativeDetected) {
      CoordMode, Mouse, Screen
      MouseGetPos, probeX, probeY
      probeDragY := Abs(probeY - MB_Y1)
      probeDragX := Abs(probeX - MB_X1)
      probeDrag := (probeDragY > probeDragX) ? probeDragY : probeDragX

      ; Signals 2 & 3: check after 3px (filters cursor jitter)
      If (probeDrag >= 3) {
        ; Signal 2: Win32 scroll position changed
        probeTarget := MB_Ctrl ? MB_Ctrl : MB_Win
        currentScrollPos := GetScrollPos(probeTarget)
        If (currentScrollPos != MB_InitScrollPos)
          nativeDetected := true

        ; Signal 3: UIA scroll percent changed
        If (!nativeDetected and MB_ScrollPattern) {
          DllCall(NumGet(NumGet(MB_ScrollPattern+0)+6*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", currentPct)
          If (currentPct != MB_InitScrollPct)
            nativeDetected := true
        }
      }

      ; Keep probing until 8px movement gate (matches custom scroll threshold)
      If (!nativeDetected and probeDrag < 8)
        Return
    }

    If (nativeDetected) {
      ; App handles MButton scroll natively — stay passive
      MB_Disabled := 1
      ; Restore cursor if we changed it
      If (MB_CursorActive) {
        DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)  ; SPI_SETCURSORS
        MB_CursorActive := 0
      }
      If (MB_ScrollPattern) {
        ObjRelease(MB_ScrollPattern)
        MB_ScrollPattern := 0
      }
      If (MB_Element) {
        ObjRelease(MB_Element)
        MB_Element := 0
      }
      SetTimer, MBDragTimer, Off
      If (MB_Debug) {
        VarSetCapacity(ci2, 16 + A_PtrSize, 0)
        NumPut(16 + A_PtrSize, ci2, 0, "UInt")
        DllCall("GetCursorInfo", "Ptr", &ci2)
        ToolTip, % "Native scroll detected (hCursor=" NumGet(ci2, 8, "UPtr") " was=" MB_InitHCursor ")"
      }
      Return
    }

    ; No native scroll — engage custom scroll
    MB_NativeProbe := 0
    ; Show cursor now if it was pending (unknown scrollability case)
    If (MB_CursorPending) {
      MB_CursorActive := 1
      MB_CursorPending := 0
      hCopy := DllCall("CopyImage", "Ptr", MB_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
      DllCall("SetSystemCursor", "Ptr", hCopy, "UInt", 32512)
      If (DebugLogEvents)
        FileAppend, % A_Now " | MBDrag | CURSOR_CONFIRMED | native_probe_passed`n", %DebugLogPath%
    }
    If (MB_ScrollPattern) {
      MB_Method := "UIA"
    } Else {
      If (MB_Element) {
        ObjRelease(MB_Element)
        MB_Element := 0
      }
      MB_Method := "WHEEL"
    }
    If (MB_Debug)
      ToolTip, % "No native scroll — using " MB_Method
    ; Log session start
    If (DebugLogEvents) {
      _ts := A_Now
      FileAppend, %_ts% | MBDrag | START | proc=%MB_ProcName% method=%MB_Method% ctrl=%MB_ClassName% pattern=%MB_ScrollPattern% viewV=%MB_ViewSize% viewH=%MB_ViewSizeH%`n, %DebugLogPath%
    }
    ; Fall through to custom scroll logic below
  }

  CoordMode, Mouse, Screen
  MouseGetPos, MB_X2, Y2
  SignedDistY := Y2 - MB_Y1
  SignedDistX := MB_X2 - MB_X1
  AbsDistY := Abs(SignedDistY)
  AbsDistX := Abs(SignedDistX)

  If (AbsDistY >= 8 or AbsDistX >= 8) {
    If (!MB_Triggered)
      MB_Triggered := 1
    curveValueY := ScrollCurve(AbsDistY)
    curveValueX := ScrollCurve(AbsDistX)

    If (MB_Method = "UIA") {
      ; ===========================================
      ; UIA SCROLLING (auto-detected, fractional % via SetScrollPercent)
      ; Fallback: UIA → WHEEL if scroll is non-functional
      ; Two-tick verification: tick 1 captures before-state, tick 2 cross-validates
      ; ===========================================
      If (!MB_ScrollPattern) {
        SetTimer, MBDragTimer, Off
        Return
      }
      ; Initialize vertical accumulator
      If (MB_AccumPct < 0) {
        DllCall(NumGet(NumGet(MB_ScrollPattern+0)+6*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_AccumPct)
      }
      ; Initialize horizontal accumulator (vtable offset 5)
      If (MB_AccumPctH < 0) {
        DllCall(NumGet(NumGet(MB_ScrollPattern+0)+5*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_AccumPctH)
      }

      ; Normalize scroll speed based on ViewSize (applies to both axes):
      ; - ViewSize = 100%: only 1 item visible (small list), scroll FAST
      ; - ViewSize = 1%: 100 items visible (huge list), scroll SLOW
      ; Formula: mult = ViewSize / 3, clamped 0.25x to 50x

      ; Vertical scroll delta
      signDirY := (SignedDistY > 0) ? 1 : -1
      viewMultiplierY := MB_ViewSize / 3.0
      viewMultiplierY := Max(0.25, Min(viewMultiplierY, 50.0))
      deltaPctY := signDirY * curveValueY * 0.006 * viewMultiplierY
      MB_AccumPct := MB_AccumPct + deltaPctY
      MB_AccumPct := (MB_AccumPct < 0) ? 0 : (MB_AccumPct > 100) ? 100 : MB_AccumPct

      ; Horizontal scroll delta (skip if NoScroll sentinel -1) — 1.5x faster than vertical
      If (MB_AccumPctH >= 0) {
        signDirX := (SignedDistX > 0) ? 1 : -1
        viewMultiplierH := MB_ViewSizeH / 3.0
        viewMultiplierH := Max(0.25, Min(viewMultiplierH, 50.0))
        deltaPctH := signDirX * curveValueX * 0.006 * viewMultiplierH * 1.5
        MB_AccumPctH := MB_AccumPctH + deltaPctH
        MB_AccumPctH := (MB_AccumPctH < 0) ? 0 : (MB_AccumPctH > 100) ? 100 : MB_AccumPctH
      }

      If (MB_Debug)
        ToolTip, % "UIA: V=" Round(MB_AccumPct, 1) "%% H=" Round(MB_AccumPctH, 1) "%% | ViewV=" Round(MB_ViewSize, 1) " ViewH=" Round(MB_ViewSizeH, 1) " | Pattern=" MB_ScrollPattern
      ; SetScrollPercent(hPct, vPct) - vtable offset 4 (with timing)
      DllCall("QueryPerformanceCounter", "Int64*", _qpcBefore)
      DllCall(NumGet(NumGet(MB_ScrollPattern+0)+4*A_PtrSize), "Ptr", MB_ScrollPattern, "Double", MB_AccumPctH, "Double", MB_AccumPct)
      DllCall("QueryPerformanceCounter", "Int64*", _qpcAfter)
      MB_ScrollTicks++
      ; Log every 5 ticks for jitter debugging
      If (DebugLogEvents && Mod(MB_ScrollTicks, 5) = 0) {
        DllCall("QueryPerformanceFrequency", "Int64*", _qpcFreq)
        _uiaMs := Round((_qpcAfter - _qpcBefore) * 1000.0 / _qpcFreq, 2)
        _scrollTarget := MB_Ctrl ? MB_Ctrl : MB_Win
        _win32Pos := GetScrollPos(_scrollTarget)
        FileAppend, % A_Now " | MBDrag | UIA | proc=" MB_ProcName " tick=" MB_ScrollTicks " V=" Round(MB_AccumPct, 1) " H=" Round(MB_AccumPctH, 1) " win32=" _win32Pos " callMs=" _uiaMs "`n", %DebugLogPath%
      }

      ; Verify UIA: only fall back on NoScroll sentinel (-1)
      ; Trust that if we got a ScrollPattern, it works. For flaky async UIA (like ATL controls),
      ; position-change verification causes false positives. If UIA genuinely doesn't scroll,
      ; user sees no movement and releases — no harm done.
      If (MB_FallbackChecked = 0) {
        DllCall(NumGet(NumGet(MB_ScrollPattern+0)+6*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", verifyPct)
        If (verifyPct < -0.5) {
          ; NoScroll sentinel (-1) — UIA reports this axis isn't scrollable
          ObjRelease(MB_ScrollPattern)
          MB_ScrollPattern := 0
          ObjRelease(MB_Element)
          MB_Element := 0
          MB_Method := "WHEEL"
          If (MB_Debug)
            ToolTip, % "UIA->WHEEL (NoScroll sentinel)"
          If (DebugLogEvents)
            FileAppend, % A_Now " | MBDrag | FALLBACK | proc=" MB_ProcName " UIA->WHEEL (NoScroll sentinel)`n", %DebugLogPath%
        } Else {
          MB_FallbackChecked := 1  ; UIA is valid, no further verification needed
        }
      }

    } Else If (MB_Method = "LVM") {
      ; ===========================================
      ; LVM_SCROLL (0x1014) — pixel-level ListView scrolling
      ; Detects row-quantized vs pixel-level on first scroll:
      ;   - Pixel-level (TortoiseGit): dual-axis allowed freely
      ;   - Row-quantized (FullEventLogView): EMA axis restriction + 2x horizontal
      ; ===========================================
      target := MB_Ctrl ? MB_Ctrl : MB_Win

      ; Get item count for normalization (more items = slower scroll per tick)
      SendMessage, 0x1004, 0, 0,, ahk_id %target%  ; LVM_GETITEMCOUNT
      itemCount := ErrorLevel

      ; Normalize scroll speed based on item count (only for quantized controls)
      ; - Quantized: sqrt curve, 20 items = 1.0x, range 0.5x to 1.5x
      ; - Pixel-level: no normalization (1.0x always)
      If (MB_LVM_RowQuantized) {
        normMultiplier := (itemCount > 0) ? Max(0.5, Min(1.5, Sqrt(20.0 / itemCount))) : 1.0
      } Else {
        normMultiplier := 1.0
      }
      pixelMultiplier := 1.0 * normMultiplier

      ; Calculate scroll values (before detection, needed for detection probe)
      scrollPixelsY := 0
      scrollPixelsX := 0
      If (AbsDistY >= 8) {
        scrollPixelsY := Max(1, Min(MB_LVM_RowHeight + 1, Floor(curveValueY * pixelMultiplier)))
        If (SignedDistY < 0)
          scrollPixelsY := -scrollPixelsY
      }
      If (AbsDistX >= 8) {
        horizMultiplier := MB_LVM_RowQuantized ? 3.0 : 1.0
        scrollPixelsX := Max(1, Floor(curveValueX * pixelMultiplier * horizMultiplier))
        If (SignedDistX < 0)
          scrollPixelsX := -scrollPixelsX
      }

      ; --- Row-quantization detection on first vertical scroll ---
      If (!MB_LVM_Detected and AbsDistY >= 8) {
        posBefore := GetScrollPos(target)
        SendMessage, 0x1014, 0, %scrollPixelsY%,, ahk_id %target%
        posAfter := GetScrollPos(target)
        scrollDelta := Abs(posAfter - posBefore)
        sentPixels := Abs(scrollPixelsY)

        ; Check ListView styles for diagnosis
        WinGet, _lvStyle, Style, ahk_id %target%
        _isVirtual := (_lvStyle & 0x1000) ? 1 : 0      ; LVS_OWNERDATA
        _isOwnerDraw := (_lvStyle & 0x0400) ? 1 : 0   ; LVS_OWNERDRAWFIXED

        ; Detection logic:
        ; - delta ≈ sentPixels (within 0.3x-1.5x): pixel-level scrolling (HIGH CONFIDENCE)
        ; - delta=0 with virtual=1: below row threshold → row-quantized (HIGH CONFIDENCE)
        ; - delta=0 with virtual=0: might be at boundary, assume pixel-level (LOW CONFIDENCE)
        ; - delta way off from sent: row-quantized
        deltaRatio := (sentPixels > 0) ? (scrollDelta / sentPixels) : 0
        If (deltaRatio >= 0.3 and deltaRatio <= 1.5) {
          ; Pixel-level: delta ≈ sentPixels (high confidence - prevents SLOW-TICK override)
          MB_LVM_RowQuantized := 0
          MB_LVM_DetectConfident := 1
          If (DebugLogEvents)
            FileAppend, % A_Now " | MBDrag | DETECT | proc=" MB_ProcName " PIXEL-LEVEL delta=" scrollDelta " sent=" sentPixels " ratio=" Round(deltaRatio, 2) " virtual=" _isVirtual "`n", %DebugLogPath%
        } Else If (scrollDelta = 0 and !_isVirtual) {
          ; delta=0 on non-virtual ListView: likely at boundary, assume pixel-level (low confidence)
          MB_LVM_RowQuantized := 0
          MB_LVM_DetectConfident := 0  ; Allow SLOW-TICK to upgrade if truly slow
          If (DebugLogEvents)
            FileAppend, % A_Now " | MBDrag | DETECT | proc=" MB_ProcName " PIXEL-LEVEL (boundary) delta=0 sent=" sentPixels " virtual=" _isVirtual "`n", %DebugLogPath%
        } Else If (_isVirtual) {
          ; Virtual ListView with delta off → row-quantized (high confidence)
          MB_LVM_RowQuantized := 1
          MB_LVM_DetectConfident := 1
          MB_LVM_RowHeight := (scrollDelta > 0 and scrollDelta > sentPixels) ? scrollDelta : 20
          If (DebugLogEvents)
            FileAppend, % A_Now " | MBDrag | DETECT | proc=" MB_ProcName " ROW-QUANTIZED rowH=" MB_LVM_RowHeight " delta=" scrollDelta " sent=" sentPixels " ratio=" Round(deltaRatio, 2) " virtual=" _isVirtual "`n", %DebugLogPath%
        } Else {
          ; Non-virtual with weird ratio: uncertain, stay pixel-level but allow upgrade
          MB_LVM_RowQuantized := 0
          MB_LVM_DetectConfident := 0
          If (DebugLogEvents)
            FileAppend, % A_Now " | MBDrag | DETECT | proc=" MB_ProcName " PIXEL-LEVEL (uncertain) delta=" scrollDelta " sent=" sentPixels " ratio=" Round(deltaRatio, 2) " virtual=" _isVirtual "`n", %DebugLogPath%
        }
        MB_LVM_Detected := 1
        ; Show detection result in tooltip
        If (MB_Debug) {
          _mode := MB_LVM_RowQuantized ? "Q" : "P"
          ToolTip, % "LVM[" _mode "] detected (delta=" scrollDelta " virt=" _isVirtual ")"
        }
        ; Set position variables for tooltip (detection scroll already sent)
        _posBeforeY := posBefore, _posAfterY := posAfter
        DllCall("GetScrollRange", "Ptr", target, "Int", 1, "Int*", _scrollMinY, "Int*", _scrollMaxY)
        _atBoundaryY := false
        DllCall("QueryPerformanceCounter", "Int64*", _qpcScrollStart)  ; For timing calc
        ; First vertical scroll already sent, skip to EMA/horizontal below
        MB_ScrollTicks++
        Goto, LVM_PostVertical
      }

      ; --- EMA axis determination (row-quantized apps only) ---
      scrollAxisY := true
      scrollAxisX := true
      If (MB_LVM_RowQuantized) {
        ; Vertical bias: require horizontal distance >= rowHeight to consider horizontal
        ; (vertical scrolling is far more common in list views)
        horizThreshold := MB_LVM_RowHeight

        ; Calculate movement deltas since last tick
        deltaY := Abs(SignedDistY - MB_PrevDistY)
        deltaX := Abs(SignedDistX - MB_PrevDistX)
        MB_PrevDistY := SignedDistY
        MB_PrevDistX := SignedDistX

        ; Update EMAs (alpha=0.2: responsive but smooth, natural decay when still)
        alpha := 0.2
        MB_EMA_Y := alpha * deltaY + (1 - alpha) * MB_EMA_Y
        MB_EMA_X := alpha * deltaX + (1 - alpha) * MB_EMA_X

        ; Determine dominant axis (1.5x threshold for lock)
        ; Transition zone allows diagonal - if app chokes, user will notice and drag more deliberately
        dominanceRatio := 1.5
        If (MB_EMA_Y > MB_EMA_X * dominanceRatio) {
          scrollAxisY := true, scrollAxisX := false
        } Else If (MB_EMA_X > MB_EMA_Y * dominanceRatio and AbsDistX >= horizThreshold) {
          ; Horizontal only if EMA dominates AND distance exceeds row height
          scrollAxisY := false, scrollAxisX := true
        } Else {
          ; Default to vertical (more common), allow horizontal only if clearly intended
          scrollAxisY := (AbsDistY >= 8)
          scrollAxisX := (AbsDistX >= horizThreshold and MB_EMA_X > MB_EMA_Y)
        }
      }

      ; --- Boundary detection: clear flag when vertical direction reverses ---
      ; If stuck at min (boundary=-1) and now scrolling down (pixels>0), clear
      ; If stuck at max (boundary=1) and now scrolling up (pixels<0), clear
      If (scrollPixelsY > 0 and MB_LVM_BoundaryY = -1)
        MB_LVM_BoundaryY := 0
      Else If (scrollPixelsY < 0 and MB_LVM_BoundaryY = 1)
        MB_LVM_BoundaryY := 0

      ; --- Send scroll messages with timing for adaptive boost ---
      DllCall("QueryPerformanceCounter", "Int64*", _qpcScrollStart)

      ; Get current position and range BEFORE scroll (for boundary pre-check)
      _posBeforeY := GetScrollPos(target)
      DllCall("GetScrollRange", "Ptr", target, "Int", 1, "Int*", _scrollMinY, "Int*", _scrollMaxY)

      ; Pre-check: if already at boundary, set flag BEFORE attempting scroll
      ; This prevents the "one scroll overshoot" where we scroll then detect
      If (scrollPixelsY < 0 and _posBeforeY <= 0) {
        MB_LVM_BoundaryY := -1
      } Else If (scrollPixelsY > 0 and _posBeforeY >= _scrollMaxY and _scrollMaxY > 0) {
        MB_LVM_BoundaryY := 1
      }

      ; Check if at vertical boundary (used for both scroll skip and tooltip)
      _atBoundaryY := (scrollPixelsY < 0 and MB_LVM_BoundaryY = -1) or (scrollPixelsY > 0 and MB_LVM_BoundaryY = 1)

      ; Vertical scroll with boundary detection (skip if at boundary)
      _posAfterY := _posBeforeY  ; default if we skip
      If (scrollAxisY and AbsDistY >= 8 and !_atBoundaryY) {
        SendMessage, 0x1014, 0, %scrollPixelsY%,, ahk_id %target%
        _posAfterY := GetScrollPos(target)
        ; Post-check: if we landed at boundary, set flag for next tick
        ; For MIN: position must be <= 0
        ; For MAX: position >= declared max, OR position didn't change (actual max differs from GetScrollRange)
        ;          But only if pos > 0 to avoid false positive at pos=0 scrolling down
        If (scrollPixelsY < 0 and _posAfterY <= 0) {
          MB_LVM_BoundaryY := -1  ; At min, can't scroll up
        } Else If (scrollPixelsY > 0 and _posAfterY > 0 and (_posAfterY >= _scrollMaxY or _posBeforeY = _posAfterY)) {
          MB_LVM_BoundaryY := 1   ; At max (declared or actual), can't scroll down
        }
        ; If position didn't change but we're not at a boundary, don't set flag — scroll was just ignored
        If (MB_LVM_BoundaryY != 0 and DebugLogEvents)
          FileAppend, % A_Now " | MBDrag | BOUNDARY | Y axis dir=" MB_LVM_BoundaryY " before=" _posBeforeY " after=" _posAfterY " max=" _scrollMaxY "`n", %DebugLogPath%
      }

      LVM_PostVertical:
      ; Recalculate horizontal with correct multiplier (2x for row-quantized views)
      If (AbsDistX >= 8) {
        horizMultiplier := MB_LVM_RowQuantized ? 3.0 : 1.0
        scrollPixelsX := Max(1, Floor(curveValueX * pixelMultiplier * horizMultiplier))
        If (SignedDistX < 0)
          scrollPixelsX := -scrollPixelsX
      }

      ; Horizontal scroll (no boundary tracking needed)
      If (scrollAxisX and AbsDistX >= 8)
        SendMessage, 0x1014, %scrollPixelsX%, 0,, ahk_id %target%

      ; --- Timing-based detection: slow tick (>50ms) = virtualized/quantized control ---
      ; Virtualized ListViews are sluggish because they render rows on-demand.
      ; This triggers: EMA axis restriction + 2x horizontal boost (same as row-quantized)
      DllCall("QueryPerformanceCounter", "Int64*", _qpcScrollEnd)
      DllCall("QueryPerformanceFrequency", "Int64*", _qpcFreq)
      _scrollMs := (_qpcScrollEnd - _qpcScrollStart) * 1000.0 / _qpcFreq
      ; Only upgrade if: slow (>50ms), not already quantized, AND detection wasn't confident
      ; This prevents system hiccups from overriding a solid pixel-level detection
      If (_scrollMs > 50 and !MB_LVM_RowQuantized and !MB_LVM_DetectConfident) {
        ; Slow tick = virtualized control, needs axis restriction + horizontal boost
        MB_LVM_Detected := 1
        MB_LVM_RowQuantized := 1
        If (DebugLogEvents)
          FileAppend, % A_Now " | MBDrag | DETECT | proc=" MB_ProcName " SLOW-TICK->QUANTIZED ms=" Round(_scrollMs) "`n", %DebugLogPath%
      }

      MB_ScrollTicks++
      If (MB_Debug) {
        ; Mode format: Q:h (quantized high-conf), P:l (pixel low-conf), ? (not yet detected)
        ; High confidence: virtual flag or delta-ratio match. Low: boundary guess or slow-tick upgrade
        If (!MB_LVM_Detected)
          _mode := "?"
        Else
          _mode := (MB_LVM_RowQuantized ? "Q" : "P") . ":" . (MB_LVM_DetectConfident ? "h" : "l")
        _pxYSent := (scrollAxisY and AbsDistY >= 8 and !_atBoundaryY) ? scrollPixelsY : 0
        _pxXSent := (scrollAxisX and AbsDistX >= 8) ? scrollPixelsX : 0
        _boundY := (MB_LVM_BoundaryY = -1) ? " MIN" : (MB_LVM_BoundaryY = 1) ? " MAX" : ""
        ToolTip, % "LVM[" _mode "] dY=" _pxYSent " dX=" _pxXSent " pos=" _posAfterY "/" _scrollMaxY _boundY
      }
      ; Log every 5 ticks
      If (DebugLogEvents && Mod(MB_ScrollTicks, 5) = 0) {
        _pxYLog := (scrollAxisY and AbsDistY >= 8 and !_atBoundaryY) ? scrollPixelsY : 0
        _pxXLog := (scrollAxisX and AbsDistX >= 8) ? scrollPixelsX : 0
        If (!MB_LVM_Detected)
          _modeLog := "?"
        Else
          _modeLog := (MB_LVM_RowQuantized ? "Q" : "P") . ":" . (MB_LVM_DetectConfident ? "h" : "l")
        FileAppend, % A_Now " | MBDrag | LVM[" _modeLog "] | proc=" MB_ProcName " tick=" MB_ScrollTicks " dY=" _pxYLog " dX=" _pxXLog " pos=" _posAfterY "/" _scrollMaxY " ms=" Round(_scrollMs) "`n", %DebugLogPath%
      }

    } Else If (MB_Method = "WHEEL_CTRL") {
      ; ===========================================
      ; WM_MOUSEWHEEL to CONTROL with GetScrollPos fallback
      ; No fractional scrolling, better acceleration than WM_VSCROLL
      ; ===========================================
      target := MB_Ctrl ? MB_Ctrl : MB_Win

      ; Get position BEFORE scroll (only on first check)
      If (!MB_FallbackChecked) {
        posBefore := GetScrollPos(target)
      }

      ; Send WHEEL message (vertical) — only if vertical movement exceeds threshold
      lParam := ((MB_Y1 & 0xFFFF) << 16) | (MB_X1 & 0xFFFF)
      If (AbsDistY >= 8) {
        magnitudeY := Max(1, Min(119, Floor(curveValueY / 2)))
        DeltaY := (SignedDistY > 0) ? -magnitudeY : magnitudeY
        wParamY := DeltaY << 16
        PostMessage, 0x20A, %wParamY%, %lParam%,, ahk_id %target%  ; WM_MOUSEWHEEL

        ; Check for fallback on first vertical scroll only
        If (!MB_FallbackChecked) {
          Sleep, 10  ; Brief pause for scroll to complete
          posAfter := GetScrollPos(target)
          scrolledUnits := Abs(posAfter - posBefore)

          ; If jumped >40 units (typically >1 line), switch to VSCROLL
          If (scrolledUnits > 40) {
            MB_Method := "VSCROLL"
            SetTimer, MBDragTimer, 150
            ; Revert the jump by scrolling opposite direction
            revertDir := (posAfter > posBefore) ? 0 : 1  ; 0=up, 1=down
            PostMessage, 0x115, %revertDir%, 0,, ahk_id %target%  ; WM_VSCROLL
            If (MB_Debug)
              ToolTip, % "WHEEL_CTRL→VSCROLL (jumped " scrolledUnits " units)"
            If (DebugLogEvents)
              FileAppend, % A_Now " | MBDrag | FALLBACK | proc=" MB_ProcName " WHEEL_CTRL->VSCROLL (jumped " scrolledUnits " units)`n", %DebugLogPath%
          }
          MB_FallbackChecked := 1
          ; Scroll succeeded — show cursor if pending
          If (MB_CursorPending and scrolledUnits > 0) {
            MB_CursorActive := 1
            MB_CursorPending := 0
            hCopy := DllCall("CopyImage", "Ptr", MB_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
            DllCall("SetSystemCursor", "Ptr", hCopy, "UInt", 32512)
            If (DebugLogEvents)
              FileAppend, % A_Now " | MBDrag | CURSOR_CONFIRMED | method=WHEEL_CTRL`n", %DebugLogPath%
          }
        }
      }

      ; Horizontal: WM_MOUSEHWHEEL (0x20E) — 2x multiplier for perceptual parity with vertical
      If (AbsDistX >= 8) {
        magnitudeX := Max(1, Min(119, Floor(curveValueX)))  ; 2x: removed /2
        DeltaX := (SignedDistX > 0) ? magnitudeX : -magnitudeX
        wParamX := DeltaX << 16
        PostMessage, 0x20E, %wParamX%, %lParam%,, ahk_id %target%
      }

      If (MB_Debug && MB_Method = "WHEEL_CTRL")
        ToolTip, % "WHEEL_CTRL: dY=" DeltaY " dX=" (AbsDistX >= 8 ? DeltaX : 0)

    } Else If (MB_Method = "VSCROLL") {
      ; ===========================================
      ; WM_VSCROLL/HSCROLL LINE - dynamic timer based on drag distance
      ; No fractional scrolling, most compatible
      ; ===========================================
      target := MB_Ctrl ? MB_Ctrl : MB_Win

      ; Dynamic timer: use max of both axes for speed calculation
      maxDist := (AbsDistY > AbsDistX) ? AbsDistY : AbsDistX
      timerMs := 300 - Floor((Min(maxDist, 300) - 8) * (100 / 192))
      timerMs := Max(20, Min(300, timerMs / 2))
      SetTimer, MBDragTimer, %timerMs%

      ; Vertical: WM_VSCROLL (0x115)
      If (AbsDistY >= 8) {
        scrollDirY := (SignedDistY > 0) ? 1 : 0
        PostMessage, 0x115, %scrollDirY%, 0,, ahk_id %target%
      }

      ; Horizontal: WM_MOUSEHWHEEL (0x20E) — 5x multiplier with acceleration
      If (AbsDistX >= 8) {
        lParamV := ((MB_Y1 & 0xFFFF) << 16) | (MB_X1 & 0xFFFF)
        magnitudeX := Max(30, Min(360, Floor(curveValueX * 5)))  ; 5x, cap at 3 notches
        DeltaX := (SignedDistX > 0) ? magnitudeX : -magnitudeX
        wParamX := DeltaX << 16
        PostMessage, 0x20E, %wParamX%, %lParamV%,, ahk_id %target%
      }

      If (MB_Debug)
        ToolTip, % "VSCROLL: dirY=" (AbsDistY >= 8 ? scrollDirY : "-") " dX=" (AbsDistX >= 8 ? DeltaX : "-") " timer=" timerMs "ms"

    } Else {
      ; ===========================================
      ; WM_MOUSEWHEEL to WINDOW (Electron apps, auto-detected default)
      ; Fallback: WHEEL → WHEEL_CTRL if window-level message doesn't scroll
      ; ===========================================
      lParam := ((MB_Y1 & 0xFFFF) << 16) | (MB_X1 & 0xFFFF)

      ; Vertical: only if vertical movement exceeds threshold
      If (AbsDistY >= 8) {
        ; MUST cap below 120 for smooth scrolling (120 = 1 notch = 3 lines)
        magnitudeY := Max(1, Min(119, Floor(curveValueY / 2)))
        DeltaY := (SignedDistY > 0) ? -magnitudeY : magnitudeY
        wParamY := DeltaY << 16

        If (!MB_FallbackChecked) {
          ; Test if window-level WHEEL actually scrolls (first vertical scroll only)
          ctrlTarget := MB_Ctrl ? MB_Ctrl : MB_Win
          posBefore := GetScrollPos(ctrlTarget)
          PostMessage, 0x20A, %wParamY%, %lParam%,, ahk_id %MB_Win%
          Sleep, 15
          posAfter := GetScrollPos(ctrlTarget)
          If (posBefore = posAfter) {
            ; No movement detected — try sending to control directly
            MB_Method := "WHEEL_CTRL"
            MB_FallbackChecked := 0
            If (MB_Debug)
              ToolTip, % "WHEEL->WHEEL_CTRL (no movement)"
            If (DebugLogEvents)
              FileAppend, % A_Now " | MBDrag | FALLBACK | proc=" MB_ProcName " WHEEL->WHEEL_CTRL (no movement)`n", %DebugLogPath%
          } Else {
            MB_FallbackChecked := 1
            ; Scroll succeeded — show cursor if pending
            If (MB_CursorPending) {
              MB_CursorActive := 1
              MB_CursorPending := 0
              hCopy := DllCall("CopyImage", "Ptr", MB_hSizeAll, "UInt", 2, "Int", 0, "Int", 0, "UInt", 0, "Ptr")
              DllCall("SetSystemCursor", "Ptr", hCopy, "UInt", 32512)
              If (DebugLogEvents)
                FileAppend, % A_Now " | MBDrag | CURSOR_CONFIRMED | method=WHEEL`n", %DebugLogPath%
            }
          }
        } Else {
          PostMessage, 0x20A, %wParamY%, %lParam%,, ahk_id %MB_Win%
        }
      }

      ; Horizontal: WM_MOUSEHWHEEL (0x20E) — 2x multiplier for perceptual parity with vertical
      ; Before WHEEL is verified, send to control (like WHEEL_CTRL) to handle horizontal-only drags
      If (AbsDistX >= 8) {
        magnitudeX := Max(1, Min(119, Floor(curveValueX)))  ; 2x: removed /2
        DeltaX := (SignedDistX > 0) ? magnitudeX : -magnitudeX
        wParamX := DeltaX << 16
        hTarget := MB_FallbackChecked ? MB_Win : (MB_Ctrl ? MB_Ctrl : MB_Win)
        PostMessage, 0x20E, %wParamX%, %lParam%,, ahk_id %hTarget%
      }

      If (MB_Debug && MB_Method = "WHEEL")
        ToolTip, % "WHEEL: dY=" (AbsDistY >= 8 ? DeltaY : "-") " dX=" (AbsDistX >= 8 ? DeltaX : "-") " hTgt=" (MB_FallbackChecked ? "win" : "ctrl")
    }
  }
Return

*MButton Up::
  Critical ; Prevent timer from firing during cleanup (race condition safety)
  global MB_Disabled, MB_DeferredDown, MB_Triggered, MB_Win, MB_ScrollPattern, MB_Element
  global MB_ProcName, MB_Method, MB_ScrollTicks, MB_SessionStart, DebugLogEvents, DebugLogPath
  global MB_CursorActive, MB_CursorPending
  SetTimer, MBDragTimer, Off
  ; Restore system cursor
  If (MB_CursorActive) {
    DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)  ; SPI_SETCURSORS
    MB_CursorActive := 0
  }
  MB_CursorPending := 0
  ; Log session summary
  If (DebugLogEvents && MB_Triggered) {
    _duration := A_TickCount - MB_SessionStart
    FileAppend, % A_Now " | MBDrag | END | proc=" MB_ProcName " method=" MB_Method " ticks=" MB_ScrollTicks " duration=" _duration "ms`n", %DebugLogPath%
  }
  If (MB_Debug)
    ToolTip

  ; Release UIA objects
  If (MB_ScrollPattern) {
    ObjRelease(MB_ScrollPattern)
    MB_ScrollPattern := 0
  }
  If (MB_Element) {
    ObjRelease(MB_Element)
    MB_Element := 0
  }

  ; Release MButton to app
  If (MB_DeferredDown) {
    ; Explorer: MButton Down was deferred — only send click if no scroll occurred
    If (!MB_Triggered) {
      SendInput, {Blind}{MButton}
    }
  } Else {
    ; Non-Explorer: MButton Down was already sent, send Up to complete
    SendInput, {Blind}{MButton Up}
  }
Return

MB_Cleanup() {
  global MB_ScrollPattern, MB_Element, MB_CursorActive
  SetTimer, MBDragTimer, Off
  If (MB_CursorActive) {
    DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "Ptr", 0, "UInt", 0)  ; SPI_SETCURSORS
    MB_CursorActive := 0
  }
  If (MB_ScrollPattern) {
    ObjRelease(MB_ScrollPattern)
    MB_ScrollPattern := 0
  }
  If (MB_Element) {
    ObjRelease(MB_Element)
    MB_Element := 0
  }
}
