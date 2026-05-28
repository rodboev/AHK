; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === EXTENDED WINDOW SPY === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; Description: Toggle tooltip showing window info under cursor
; Press #w to cycle: tooltip → dialog (frozen snapshot) → close
; Forum link: https://autohotkey.com/boards/viewtopic.php?f=6&t=43544
; Author: @rodboev
; Version: 1.1
#w::
  ; Cycle: Off(0) → Tooltip(1) → Dialog(2) → Off(0)
  If (!ExtendedSpyState) {
    ExtendedSpyState := 1
    ExtendedSpyLastContent := ""
    SetTimer, ExtendedSpyUpdate, 800
    GoSub, ExtendedSpyUpdate
  } Else If (ExtendedSpyState = 1) {
    SetTimer, ExtendedSpyUpdate, Off
    ToolTip,,,, 10
    ExtendedSpyState := 2
    ExtendedSpyShowDialog()
  } Else {
    Gui, ExtendedSpy:Destroy
    ExtendedSpyState := 0
  }
Return

#If ExtendedSpyState
$Esc::
  If (ExtendedSpyState = 2) {
    Gui, ExtendedSpy:Destroy
    ExtendedSpyState := 0
    Return
  }
  SetTimer, ExtendedSpyUpdate, Off
  ToolTip,,,, 10
  ExtendedSpyState := 0
Return

~LButton::
  If (ExtendedSpyState = 1) {
    MouseGetPos,,, clickWin
    WinGetClass, clickClass, ahk_id %clickWin%
    If (clickClass = "tooltips_class32") {
      SetTimer, ExtendedSpyUpdate, Off
      ToolTip,,,, 10
      ExtendedSpyState := 2
      ExtendedSpyShowDialog()
    }
  }
Return
#If

ExtendedSpyShowDialog() {
  global ExtendedSpyDisplayInfo, ExtendedSpyEdit
  If (ExtendedSpyDisplayInfo = "")
    Return
  ToolTip,,,, 10
  Gui, ExtendedSpy:Destroy
  _curMon := IsFunc("GetCursorMonitor") ? GetCursorMonitor() : 1
  SysGet, Workspace, MonitorWorkArea, %_curMon%
  ; Dimensions from display content (same wrapping as tooltip)
  StringReplace, _, ExtendedSpyDisplayInfo, `n, `n, UseErrorLevel
  lineCount := ErrorLevel + 1
  maxHeight := WorkspaceBottom - WorkspaceTop - 50
  rowHeight := 22  ; Consolas 9pt + Edit control internal padding
  maxRows := Floor(maxHeight / rowHeight)
  rowCount := Min(lineCount, maxRows)
  _maxLineLen := 0
  Loop, Parse, ExtendedSpyDisplayInfo, `n
  {
    If (StrLen(A_LoopField) > _maxLineLen)
      _maxLineLen := StrLen(A_LoopField)
  }
  editWidth := Min(_maxLineLen * 7 + 30, WorkspaceRight - WorkspaceLeft - 100)
  Gui, ExtendedSpy:+AlwaysOnTop +Owner
  Gui, ExtendedSpy:Font, s9, Consolas
  Gui, ExtendedSpy:Add, Edit, vExtendedSpyEdit w%editWidth% r%rowCount% +Multi +ReadOnly, %ExtendedSpyDisplayInfo%
  ; Show first to render and get dimensions, then reposition flush to bottom-right
  Gui, ExtendedSpy:Show,, Extended Spy (#w or Esc to close)
  WinGetPos,,, GUIWidth, GUIHeight, A
  xPos := WorkspaceRight - GUIWidth
  yPos := WorkspaceBottom - GUIHeight
  WinMove, A,, %xPos%, %yPos%
}

; Collect all window info into an object for the given hwnd
CollectWindowInfo(hwnd) {
  _wt := "ahk_id " . hwnd
  info := {}
  info.hwnd := hwnd
  WinGetTitle, _title, %_wt%
  info.title := _title
  WinGetClass, _class, %_wt%
  info.class := _class
  WinGet, _pid, PID, %_wt%
  info.pid := _pid
  WinGetPos, _x, _y, _w, _h, %_wt%
  info.x := _x
  info.y := _y
  info.w := _w
  info.h := _h
  WinGet, _style, Style, %_wt%
  info.style := _style
  WinGet, _exStyle, ExStyle, %_wt%
  info.exStyle := _exStyle
  info.exe := IsFunc("GetExePath") ? GetExePath("ahk_id " . hwnd) : {path: "", dir: ""}
  info.mon := IsFunc("GetMonitor") ? GetMonitor("ahk_id " . hwnd) : 1
  info.elevated := IsFunc("IsProcessElevated") ? IsProcessElevated(_pid) : false
  info.cmdLine := ""
  For _proc in ComObjGet("winmgmts:").ExecQuery("Select CommandLine from Win32_Process where ProcessId=" . _pid)
    info.cmdLine := _proc.CommandLine
  WinGetText, _winText, %_wt%
  WinGet, _ctlList, ControlList, %_wt%
  ; Format controls: comma-separated, filter >80 chars, sort alphabetically
  _ctlRaw := SortList(FilterLongItems(RegExReplace(_ctlList, "\r?\n", ", ")))
  info.controlsDisplay := WrapList(_ctlRaw, ",")
  ; Format window text: comma-separated, clean non-ASCII, filter >80 chars, dedupe if long
  _wtRaw := RTrim(FilterLongItems(CleanWindowText(RegExReplace(_winText, "\r?\n", ", "))), ", ")
  info.winTextDisplay := WrapList(_wtRaw, ",")
  Return info
}

; Get UIA element properties at screen coordinates via ElementFromPoint
; Returns {name, type, autoId, className} for the element under the cursor
GetUIAElementInfo(x, y) {
  result := {name: "", type: "", autoId: "", className: "", pid: 0}
  global G_UIA
  If (!G_UIA)  ; UIA not initialized (MButton scroll not yet used)
    Return result
  Try {
    _el := 0
    ; IUIAutomation::ElementFromPoint (vtable 7)
    DllCall(NumGet(NumGet(G_UIA+0) + 7*A_PtrSize), "Ptr", G_UIA, "Int64", x | (y << 32), "Ptr*", _el)
    If (!_el)
      Return result
    ; Read properties via GetCurrentPropertyValue (vtable 10)
    Try {
      result.name := _GetUIAProp(_el, 30005)        ; UIA_NamePropertyId
      result.type := _GetUIAProp(_el, 30004)         ; UIA_LocalizedControlTypePropertyId
      result.autoId := _GetUIAProp(_el, 30011)       ; UIA_AutomationIdPropertyId
      result.className := _GetUIAProp(_el, 30012)    ; UIA_ClassNamePropertyId
      result.pid := _GetUIAProp(_el, 30002)          ; UIA_ProcessIdPropertyId
    } Finally {
      ObjRelease(_el)
    }
  }
  Return result
}

; Read a property (VT_I4 or VT_BSTR) from a UIA element via GetCurrentPropertyValue (vtable 10)
_GetUIAProp(el, propId) {
  VarSetCapacity(_var, 24, 0)
  DllCall("OleAut32\VariantInit", "Ptr", &_var)
  DllCall(NumGet(NumGet(el+0) + 10*A_PtrSize), "Ptr", el, "Int", propId, "Ptr", &_var)
  _vt := NumGet(_var, 0, "UShort")
  _val := ""
  If (_vt = 0) {  ; VT_EMPTY — property not supported
  } Else If (_vt = 3) {  ; VT_I4
    _val := NumGet(_var, 8, "Int")
  } Else If (_vt = 5) {  ; VT_R8 (Double)
    _val := NumGet(_var, 8, "Double")
  } Else If (_vt = 8) {  ; VT_BSTR
    _bstr := NumGet(_var, 8, "Ptr")
    If (_bstr)
      _val := StrGet(_bstr, "UTF-16")
  }
  DllCall("OleAut32\VariantClear", "Ptr", &_var)
  Return _val
}

; Format info object into display string
FormatWindowInfo(info) {
  s := ""
  ; Identity group
  s .= "Title: " . info.title . "`n"
  s .= "ahk_exe: " . info.exe.path . "`n"
  s .= "ahk_class: " . info.class . "`n"
  s .= "ahk_id: " . info.hwnd . "`n"
  If (info.HasKey("pointHwnd"))
    s .= "hWnd: " . info.pointHwnd . "`n"
  If (info.class = "CabinetWClass" && IsFunc("GetExplorerPath")) {
    _expPath := GetExplorerPath()
    If (_expPath != "")
      s .= "ExplorerPath: " . _expPath . "`n"
  }
  s .= "`n"
  ; Path/Process group
  s .= "Command line: " . WrapList(info.cmdLine, " ") . "`n"
  _pidLine := "Process ID: " . info.pid
  If (info.HasKey("hostPid"))
    _pidLine .= " (host: " . info.hostPid . ")"
  If (info.elevated)
    _pidLine .= " (Elevated)"
  s .= _pidLine . "`n"
  ; WT Scroll position
  If (info.HasKey("wtScroll")) {
    If (info.wtScroll.pct != -1) {
      _tag := info.wtScroll.status != "" ? " [" . info.wtScroll.status . "]" : ""
      s .= "WT Scroll: " . Round(info.wtScroll.pct, 1) . "%" . _tag . "`n"
    } Else
      s .= "WT Scroll: (no scroll)`n"
  }
  If (info.HasKey("wtDiag") && info.wtDiag != "")
    s .= "WT Debug: " . info.wtDiag . "`n"
  ; UIA element at cursor (wrap long names/IDs at spaces, hard-break at 120)
  If (info.HasKey("uia") && (info.uia.type != "" || info.uia.name != "")) {
    _uiaLine := "UIA: "
    If (info.uia.type != "")
      _uiaLine .= info.uia.type
    If (info.uia.name != "")
      _uiaLine .= (info.uia.type != "" ? " " : "") . """" . WrapList(info.uia.name, ",", 90, ", ") . """"
    s .= _uiaLine . "`n"
    If (info.uia.autoId != "")
      s .= "  AutomationId: " . WrapList(info.uia.autoId, ",", 90, ", ") . "`n"
    If (info.uia.className != "")
      s .= "  ClassName: " . info.uia.className . "`n"
    If (info.HasKey("scrollPattern"))
      s .= "  ScrollPattern: " . info.scrollPattern . "`n"
  }
  s .= "`n"
  ; Focus/Control group
  If (info.HasKey("focusedControl"))
    s .= "Focused Control: " . info.focusedControl . (info.focusedHwnd != "" ? "`nControl hWnd: " . info.focusedHwnd : "") . "`n"
  If (info.HasKey("activeFocus"))
    s .= "Active Focus: " . info.activeFocus . (info.activeFocusHwnd != "" ? "`n  Control hWnd: " . info.activeFocusHwnd : "") . "`n"
  If (info.HasKey("control"))
    s .= "Control: " . info.control . "`n"
  s .= "`n"
  ; Window Text
  s .= "Window Text: " . info.winTextDisplay . "`n"
  s .= "`n"
  ; Controls
  s .= "Controls: " . info.controlsDisplay
  Return s
}


; Wrap list items at ~100 chars, preserving whole items
; Input: comma-separated string like "item1, item2, item3"
; Output: same items wrapped to fit maxLen, with continuation lines indented
; hardMax: force-break lines exceeding this width (try spaces first, then hard cut)
WrapList(text, delimiter := ",", maxLen := 100, joiner := "", hardMax := 120) {
  If (joiner = "")
    joiner := delimiter = " " ? " " : delimiter . " "
  result := ""
  currentLine := ""
  Loop, Parse, text, %delimiter%
  {
    item := Trim(A_LoopField)
    If (item = "")
      Continue
    testLine := currentLine = "" ? item : currentLine . joiner . item
    If (StrLen(testLine) > maxLen && currentLine != "") {
      result .= (result = "" ? "" : "`n  ") . currentLine
      currentLine := item
    } Else {
      currentLine := testLine
    }
  }
  If (currentLine != "")
    result .= (result = "" ? "" : "`n  ") . currentLine
  ; Hard-wrap: break any lines still exceeding hardMax (try spaces, then force cut)
  If (hardMax > 0) {
    _out := ""
    Loop, Parse, result, `n
    {
      _line := A_LoopField
      While (StrLen(_line) > hardMax) {
        _breakAt := 0
        _pos := hardMax
        While (_pos > 20) {
          If (SubStr(_line, _pos, 1) = " ") {
            _breakAt := _pos
            Break
          }
          _pos--
        }
        If (_breakAt = 0)
          _breakAt := hardMax
        _out .= (_out != "" ? "`n" : "") . SubStr(_line, 1, _breakAt)
        _line := "  " . LTrim(SubStr(_line, _breakAt + 1))
      }
      If (_line != "")
        _out .= (_out != "" ? "`n" : "") . _line
    }
    result := _out
  }
  Return result
}

CleanWindowText(text) {
  cleaned := RegExReplace(text, "[^\x20-\x7E]", "")
  cleaned := RegExReplace(cleaned, "\s+", " ")
  cleaned := Trim(cleaned)

  ; If > 300 chars, deduplicate items
  If (StrLen(cleaned) > 300) {
    seen := {}
    result := ""
    Loop, Parse, cleaned, `,
    {
      item := Trim(A_LoopField)
      If (item != "" && !seen.HasKey(item)) {
        seen[item] := true
        result .= (result ? ", " : "") . item
      }
    }
    cleaned := result
  }
  Return cleaned
}

; Filter out items exceeding maxLen characters from comma-separated list
FilterLongItems(text, maxItemLen := 80) {
  result := ""
  Loop, Parse, text, `,
  {
    item := Trim(A_LoopField)
    If (item != "" && StrLen(item) <= maxItemLen)
      result .= (result ? ", " : "") . item
  }
  Return result
}

; Sort comma-separated items alphabetically
SortList(text) {
  sorted := ""
  Loop, Parse, text, `,
  {
    item := Trim(A_LoopField)
    If (item != "")
      sorted .= item . "`n"
  }
  Sort, sorted
  result := ""
  Loop, Parse, sorted, `n
  {
    If (A_LoopField != "")
      result .= (result ? ", " : "") . A_LoopField
  }
  Return result
}

ExtendedSpyGuiEscape:
ExtendedSpyGuiClose:
  Gui, ExtendedSpy:Destroy
  ExtendedSpyState := 0
Return

ExtendedSpyUpdate:
  CoordMode, Mouse, Screen
  CoordMode, ToolTip, Screen
  CoordMode, Pixel, Screen
  MouseGetPos, CursorX, CursorY, CursorWin, ClassNN

  ; Pause updates when hovering over our tooltip
  WinGetClass, hoverClass, ahk_id %CursorWin%
  WinGet, hoverExe, ProcessPath, ahk_id %CursorWin%
  If (hoverClass = "tooltips_class32" && hoverExe = A_AhkPath)
    Return

  DetectHiddenText, On

  ; UIA element at cursor position
  _uia := GetUIAElementInfo(CursorX, CursorY)

  WinGet, activeHwnd, ID, A
  sameWindow := (activeHwnd + 0 = CursorWin + 0)

  ; Active-window fields (always from the active window)
  ControlGetFocus, _fc, % "ahk_id " . activeHwnd
  _fh := ""
  If (_fc != "")
    ControlGet, _fh, Hwnd,, %_fc%, % "ahk_id " . activeHwnd

  If (sameWindow) {
    ; Same window — single collection with all fields merged
    info := CollectWindowInfo(CursorWin)
    info.pointHwnd := DllCall("WindowFromPoint", "int64", CursorX | (CursorY << 32), "Ptr")
    info.control := ClassNN
    info.focusedControl := _fc
    info.focusedHwnd := _fh
    info.scrollPattern := MB_ScrollPattern
    info.uia := _uia
  } Else {
    ; Different windows — cursor primary, inline active-only info
    info := CollectWindowInfo(CursorWin)
    info.pointHwnd := DllCall("WindowFromPoint", "int64", CursorX | (CursorY << 32), "Ptr")
    info.control := ClassNN
    info.scrollPattern := MB_ScrollPattern
    info.uia := _uia
    If (_fc != "") {
      info.activeFocus := _fc
      info.activeFocusHwnd := _fh
    }
  }

  ; WT Scroll position (uses cached value from guard timer to avoid COM reentrancy)
  If (info.exe.path ~= "i)WindowsTerminal") {
    info.wtScroll := {pct: SG_ScrollLastPct, status: SG_ScrollStatus}
    info.wtDiag := SG_ScrollDiag
  }

  ; UIA PID override: use content process when it differs from host
  _contentPid := IsFunc("GetUIAProcessId") ? GetUIAProcessId(CursorWin) : 0
  If (_contentPid && _contentPid != info.pid) {
    info.hostPid := info.pid
    info.pid := _contentPid
    info.elevated := IsFunc("IsProcessElevated") ? IsProcessElevated(_contentPid) : false
    info.cmdLine := ""
    For _proc in ComObjGet("winmgmts:").ExecQuery("Select CommandLine from Win32_Process where ProcessId=" . _contentPid)
      info.cmdLine := _proc.CommandLine
  }

  display := FormatWindowInfo(info)

  ; Store for dialog (frozen snapshot)
  global ExtendedSpyDisplayInfo, ExtendedSpyLastContent
  ExtendedSpyDisplayInfo := display

  ; Only update tooltip if content changed (reduces flicker)
  If (display = ExtendedSpyLastContent)
    Return
  ExtendedSpyLastContent := display

  ; Position tooltip in bottom-right corner
  _curMon := IsFunc("GetCursorMonitor") ? GetCursorMonitor() : 1
  SysGet, Workspace, MonitorWorkArea, %_curMon%
  tooltipHeader := "Extended Spy (#w to freeze, Esc to close)`n`n"
  ToolTip, %tooltipHeader%%display%, WorkspaceRight - 550, WorkspaceBottom - 620, 10
Return
