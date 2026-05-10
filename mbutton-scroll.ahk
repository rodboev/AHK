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

; -> [ MButton + drag ] -> Invoke smooth scrolling on any app; release to stop.
*MButton::
  global MB_Debug := 1  ; Debug tooltips (0=off, 1=on)
  global MB_X1, MB_Y1, MB_Win, MB_ClassName, MB_Triggered
  global MB_ScrollPattern := 0, MB_Element := 0, MB_Ctrl
  global MB_Disabled := 0, MB_DeferredDown := 0, MB_ViewSize := 10.0, MB_AccumPct := -1
  global MB_ViewSizeH := 10.0, MB_AccumPctH := -1
  global MB_Method := "VSCROLL" ; Default fallback
  global MB_FallbackChecked := 0  ; Check fallback once per drag
  global MB_NativeProbe := 0, MB_InitScrollPos := 0, MB_InitScrollPct := 0.0, MB_InitHCursor := 0

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

  ; Get control window handle (hwnd)
  ControlGet, MB_Ctrl, Hwnd,, %MB_ClassName%, ahk_id %MB_Win%
  MB_Triggered := 0

  ; TreeView controls → direct to VSCROLL (skip native probe, never has native MButton scroll)
  If (InStr(MB_ClassName, "SysTreeView32")) {
    MB_Method := "VSCROLL"
    MB_NativeProbe := 0
    SetTimer, MBScrollTimer, 150
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

    ; Vertical power curve
    If (AbsDistY <= 100) {
      curveValueY := AbsDistY ** 0.8
    } Else {
      curveValueY := (100 ** 0.8) + ((AbsDistY - 100) ** 0.6)
    }

    ; Horizontal power curve
    If (AbsDistX <= 100) {
      curveValueX := AbsDistX ** 0.8
    } Else {
      curveValueX := (100 ** 0.8) + ((AbsDistX - 100) ** 0.6)
    }

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

      ; Capture Win32 scroll position BEFORE UIA scroll (for cross-validation)
      If (MB_FallbackChecked = 0) {
        uiaTarget := MB_Ctrl ? MB_Ctrl : MB_Win
        MB_UIAVerifyPos := GetScrollPos(uiaTarget)
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

      ; Horizontal scroll delta
      signDirX := (SignedDistX > 0) ? 1 : -1
      viewMultiplierH := MB_ViewSizeH / 3.0
      viewMultiplierH := Max(0.25, Min(viewMultiplierH, 50.0))
      deltaPctH := signDirX * curveValueX * 0.006 * viewMultiplierH
      MB_AccumPctH := MB_AccumPctH + deltaPctH
      MB_AccumPctH := (MB_AccumPctH < 0) ? 0 : (MB_AccumPctH > 100) ? 100 : MB_AccumPctH

      If (MB_Debug)
        ToolTip, % "UIA: V=" Round(MB_AccumPct, 1) "%% H=" Round(MB_AccumPctH, 1) "%%"
      ; SetScrollPercent(hPct, vPct) - vtable offset 4
      DllCall(NumGet(NumGet(MB_ScrollPattern+0)+4*A_PtrSize), "Ptr", MB_ScrollPattern, "Double", MB_AccumPctH, "Double", MB_AccumPct)

      ; Verify UIA is actually working (two-tick verification)
      If (MB_FallbackChecked = 0) {
        ; Tick 1: UIA scroll sent, advance to pending verification
        MB_FallbackChecked := -1
      } Else If (MB_FallbackChecked = -1) {
        ; Tick 2: verify UIA actually scrolled
        uiaFailed := false
        DllCall(NumGet(NumGet(MB_ScrollPattern+0)+6*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", verifyPct)
        If (verifyPct < -0.5) {
          uiaFailed := true  ; NoScroll sentinel (-1)
        } Else {
          ; Cross-validate: if control has a Win32 scrollbar, it should have moved
          uiaTarget := MB_Ctrl ? MB_Ctrl : MB_Win
          If (HasWin32Scrollbar(uiaTarget)) {
            posAfter := GetScrollPos(uiaTarget)
            If (posAfter = MB_UIAVerifyPos)
              uiaFailed := true  ; Win32 scrollbar didn't budge
          }
        }

        If (uiaFailed) {
          ; UIA didn't actually scroll — release COM objects, fall to WHEEL
          ObjRelease(MB_ScrollPattern)
          MB_ScrollPattern := 0
          ObjRelease(MB_Element)
          MB_Element := 0
          MB_Method := "WHEEL"
          MB_FallbackChecked := 0
          If (MB_Debug)
            ToolTip, % "UIA->WHEEL (didn't scroll)"
        } Else {
          MB_FallbackChecked := 1
        }
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

      ; Send WHEEL message (vertical)
      lParam := ((MB_Y1 & 0xFFFF) << 16) | (MB_X1 & 0xFFFF)
      magnitudeY := Max(1, Min(119, Floor(curveValueY / 2)))
      DeltaY := (SignedDistY > 0) ? -magnitudeY : magnitudeY
      wParamY := DeltaY << 16
      PostMessage, 0x20A, %wParamY%, %lParam%,, ahk_id %target%  ; WM_MOUSEWHEEL

      ; Check for fallback on first scroll only
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
        }
        MB_FallbackChecked := 1
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
      ; MUST cap below 120 for smooth scrolling (120 = 1 notch = 3 lines)
      magnitudeY := Max(1, Min(119, Floor(curveValueY / 2)))
      DeltaY := (SignedDistY > 0) ? -magnitudeY : magnitudeY
      wParamY := DeltaY << 16

      If (!MB_FallbackChecked) {
        ; Test if window-level WHEEL actually scrolls (first scroll only)
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
        } Else {
          MB_FallbackChecked := 1
        }
      } Else {
        PostMessage, 0x20A, %wParamY%, %lParam%,, ahk_id %MB_Win%
      }

      ; Horizontal: WM_MOUSEHWHEEL (0x20E) — 2x multiplier for perceptual parity with vertical
      If (AbsDistX >= 8) {
        magnitudeX := Max(1, Min(119, Floor(curveValueX)))  ; 2x: removed /2
        DeltaX := (SignedDistX > 0) ? magnitudeX : -magnitudeX
        wParamX := DeltaX << 16
        PostMessage, 0x20E, %wParamX%, %lParam%,, ahk_id %MB_Win%
      }

      If (MB_Debug && MB_Method = "WHEEL")
        ToolTip, % "WHEEL: dY=" DeltaY " dX=" (AbsDistX >= 8 ? DeltaX : 0)
    }
  }
Return

*MButton Up::
  Critical ; Prevent timer from firing during cleanup (race condition safety)
  global MB_Disabled, MB_DeferredDown, MB_Triggered, MB_Win, MB_ScrollPattern, MB_Element
  SetTimer, MBScrollTimer, Off
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
