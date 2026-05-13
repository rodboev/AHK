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
    SetTimer, MBScrollTimer, 150
    Return
  }

  ; SysListView32 controls → direct to LVM_SCROLL for pixel-level precision
  ; UIA SetScrollPercent causes jitter on short lists (percentage rounds to discrete positions)
  If (InStr(MB_ClassName, "SysListView32")) {
    MB_Method := "LVM"
    MB_NativeProbe := 0
    If (MB_Debug)
      ToolTip, % "SysListView32 → LVM_SCROLL (pixel-level)"
    If (DebugLogEvents) {
      _ts := A_Now
      FileAppend, %_ts% | MBScroll | START | proc=%MB_ProcName% method=LVM ctrl=%MB_ClassName%`n, %DebugLogPath%
    }
    SetTimer, MBScrollTimer, 10
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

  ; Start timer in native probe mode
  MB_NativeProbe := 1
  SetTimer, MBScrollTimer, 10
Return 

MBScrollTimer:
  Critical ; Prevent MButton Up from interrupting mid-DllCall (race condition safety)
  global MB_Debug, MB_AccumPct, MB_AccumPctH, MB_Method, MB_ViewSize, MB_ViewSizeH, MB_Ctrl, MB_FallbackChecked
  global MB_NativeProbe, MB_InitScrollPos, MB_InitScrollPct, MB_InitHCursor
  global MB_ProcName, MB_ScrollTicks, DebugLogEvents, DebugLogPath
  ; Safety check: if MButton released, stop immediately
  If !GetKeyState("MButton", "P") {
    SetTimer, MBScrollTimer, Off
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
      If (MB_ScrollPattern) {
        ObjRelease(MB_ScrollPattern)
        MB_ScrollPattern := 0
      }
      If (MB_Element) {
        ObjRelease(MB_Element)
        MB_Element := 0
      }
      SetTimer, MBScrollTimer, Off
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
      FileAppend, %_ts% | MBScroll | START | proc=%MB_ProcName% method=%MB_Method% ctrl=%MB_ClassName% pattern=%MB_ScrollPattern% viewV=%MB_ViewSize% viewH=%MB_ViewSizeH%`n, %DebugLogPath%
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
        SetTimer, MBScrollTimer, Off
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

      ; Horizontal scroll delta (skip if NoScroll sentinel -1)
      If (MB_AccumPctH >= 0) {
        signDirX := (SignedDistX > 0) ? 1 : -1
        viewMultiplierH := MB_ViewSizeH / 3.0
        viewMultiplierH := Max(0.25, Min(viewMultiplierH, 50.0))
        deltaPctH := signDirX * curveValueX * 0.006 * viewMultiplierH
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
        FileAppend, % A_Now " | MBScroll | UIA | proc=" MB_ProcName " tick=" MB_ScrollTicks " V=" Round(MB_AccumPct, 1) " H=" Round(MB_AccumPctH, 1) " win32=" _win32Pos " callMs=" _uiaMs "`n", %DebugLogPath%
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
            FileAppend, % A_Now " | MBScroll | FALLBACK | proc=" MB_ProcName " UIA->WHEEL (NoScroll sentinel)`n", %DebugLogPath%
        } Else {
          MB_FallbackChecked := 1  ; UIA is valid, no further verification needed
        }
      }

    } Else If (MB_Method = "LVM") {
      ; ===========================================
      ; LVM_SCROLL (0x1014) — pixel-level ListView scrolling
      ; Avoids UIA percentage quantization jitter on short lists
      ; ===========================================
      target := MB_Ctrl ? MB_Ctrl : MB_Win

      ; Apply power curve with scroll speed scaling
      ; Pixels per tick at 10ms: ~1px at threshold (8px drag), ~25px at 100px drag, ~40px at 300px
      pixelMultiplier := 0.6  ; Base sensitivity

      ; SCROLLINFO struct for proper bounds (accounts for page size)
      ; Max scrollable position = nMax - max(nPage - 1, 0)
      VarSetCapacity(si, 28, 0)
      NumPut(28, si, 0, "UInt")  ; cbSize
      NumPut(0x17, si, 4, "UInt")  ; fMask = SIF_ALL

      ; Vertical: only if vertical movement exceeds threshold
      If (AbsDistY >= 8) {
        scrollPixelsY := Max(1, Floor(curveValueY * pixelMultiplier))
        If (SignedDistY < 0)
          scrollPixelsY := -scrollPixelsY

        ; Get scroll info for proper bounds
        DllCall("GetScrollInfo", "Ptr", target, "Int", 1, "Ptr", &si)  ; SB_VERT=1
        siMin := NumGet(si, 8, "Int")
        siMax := NumGet(si, 12, "Int")
        siPage := NumGet(si, 16, "UInt")
        siPos := NumGet(si, 20, "Int")
        ; Actual max position accounts for page size
        actualMaxY := siMax - (siPage > 1 ? siPage - 1 : 0)

        newPosY := siPos + scrollPixelsY
        If (newPosY < siMin)
          scrollPixelsY := siMin - siPos
        Else If (newPosY > actualMaxY)
          scrollPixelsY := actualMaxY - siPos

        If (scrollPixelsY != 0)
          SendMessage, 0x1014, 0, %scrollPixelsY%,, ahk_id %target%
      }

      ; Horizontal: same treatment with bounds check
      If (AbsDistX >= 8) {
        scrollPixelsX := Max(1, Floor(curveValueX * pixelMultiplier))
        If (SignedDistX < 0)
          scrollPixelsX := -scrollPixelsX

        ; Get scroll info for proper bounds
        DllCall("GetScrollInfo", "Ptr", target, "Int", 0, "Ptr", &si)  ; SB_HORZ=0
        siMin := NumGet(si, 8, "Int")
        siMax := NumGet(si, 12, "Int")
        siPage := NumGet(si, 16, "UInt")
        siPos := NumGet(si, 20, "Int")
        actualMaxX := siMax - (siPage > 1 ? siPage - 1 : 0)

        newPosX := siPos + scrollPixelsX
        If (newPosX < siMin)
          scrollPixelsX := siMin - siPos
        Else If (newPosX > actualMaxX)
          scrollPixelsX := actualMaxX - siPos

        If (scrollPixelsX != 0)
          SendMessage, 0x1014, %scrollPixelsX%, 0,, ahk_id %target%
      }

      MB_ScrollTicks++
      If (MB_Debug)
        ToolTip, % "LVM: dY=" (AbsDistY >= 8 ? scrollPixelsY : 0) "px dX=" (AbsDistX >= 8 ? scrollPixelsX : 0) "px dist=" AbsDistY " curve=" Round(curveValueY, 1)
      ; Log every 5 ticks for debugging
      If (DebugLogEvents && Mod(MB_ScrollTicks, 5) = 0) {
        FileAppend, % A_Now " | MBScroll | LVM | proc=" MB_ProcName " tick=" MB_ScrollTicks " distY=" AbsDistY " curveY=" Round(curveValueY, 1) " pxY=" scrollPixelsY " distX=" AbsDistX " curveX=" Round(curveValueX, 1) " pxX=" scrollPixelsX "`n", %DebugLogPath%
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
            SetTimer, MBScrollTimer, 150
            ; Revert the jump by scrolling opposite direction
            revertDir := (posAfter > posBefore) ? 0 : 1  ; 0=up, 1=down
            PostMessage, 0x115, %revertDir%, 0,, ahk_id %target%  ; WM_VSCROLL
            If (MB_Debug)
              ToolTip, % "WHEEL_CTRL→VSCROLL (jumped " scrolledUnits " units)"
            If (DebugLogEvents)
              FileAppend, % A_Now " | MBScroll | FALLBACK | proc=" MB_ProcName " WHEEL_CTRL->VSCROLL (jumped " scrolledUnits " units)`n", %DebugLogPath%
          }
          MB_FallbackChecked := 1
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
      SetTimer, MBScrollTimer, %timerMs%

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
              FileAppend, % A_Now " | MBScroll | FALLBACK | proc=" MB_ProcName " WHEEL->WHEEL_CTRL (no movement)`n", %DebugLogPath%
          } Else {
            MB_FallbackChecked := 1
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
  SetTimer, MBScrollTimer, Off
  ; Log session summary
  If (DebugLogEvents && MB_Triggered) {
    _duration := A_TickCount - MB_SessionStart
    FileAppend, % A_Now " | MBScroll | END | proc=" MB_ProcName " method=" MB_Method " ticks=" MB_ScrollTicks " duration=" _duration "ms`n", %DebugLogPath%
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
  global MB_ScrollPattern, MB_Element
  SetTimer, MBScrollTimer, Off
  If (MB_ScrollPattern) {
    ObjRelease(MB_ScrollPattern)
    MB_ScrollPattern := 0
  }
  If (MB_Element) {
    ObjRelease(MB_Element)
    MB_Element := 0
  }
}
