; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === EXTENDED WINDOW SPY === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; Description: Persistent tooltip showing window info under cursor
; Press #w to cycle: tooltip → dialog (frozen snapshot) → close
; Forum link: https://autohotkey.com/boards/viewtopic.php?f=6&t=43544
; Author: @rodboev
; Version: 1.1
#w::
  ; Cycle: Off(0) → Tooltip(1) → Dialog(2) → Off(0)
  If (WindowSpyState = 0) {
    WindowSpyState := 1
    WindowSpyLastContent := ""
    SetTimer, WindowSpyUpdate, 800
    GoSub, WindowSpyUpdate
  } Else If (WindowSpyState = 1) {
    SetTimer, WindowSpyUpdate, Off
    ToolTip
    WindowSpyState := 2
    WindowSpyShowDialog()
  } Else {
    Gui, WindowSpy:Destroy
    WindowSpyState := 0
  }
Return

$Esc::
  If (WindowSpyState = 2) {
    Gui, WindowSpy:Destroy
    WindowSpyState := 0
    Return
  }
  If (WindowSpyState = 1) {
    SetTimer, WindowSpyUpdate, Off
    ToolTip
    WindowSpyState := 0
    Return
  }
  Send {Esc}
Return

~LButton::
  If (WindowSpyState = 1) {
    MouseGetPos,,, clickWin
    WinGetClass, clickClass, ahk_id %clickWin%
    If (clickClass = "tooltips_class32") {
      SetTimer, WindowSpyUpdate, Off
      ToolTip
      WindowSpyState := 2
      WindowSpyShowDialog()
    }
  }
Return

WindowSpyShowDialog() {
  global WindowSpyDisplayInfo, WindowSpyEdit
  If (WindowSpyDisplayInfo = "")
    Return
  ToolTip
  Gui, WindowSpy:Destroy
  SysGet, Workspace, MonitorWorkArea
  ; Dimensions from display content (same wrapping as tooltip)
  StringReplace, _, WindowSpyDisplayInfo, `n, `n, UseErrorLevel
  lineCount := ErrorLevel + 1
  maxHeight := WorkspaceBottom - WorkspaceTop - 50
  rowHeight := 22  ; Consolas 9pt + Edit control internal padding
  maxRows := Floor(maxHeight / rowHeight)
  rowCount := Min(lineCount, maxRows)
  _maxLineLen := 0
  Loop, Parse, WindowSpyDisplayInfo, `n
  {
    If (StrLen(A_LoopField) > _maxLineLen)
      _maxLineLen := StrLen(A_LoopField)
  }
  editWidth := Min(_maxLineLen * 7 + 30, WorkspaceRight - WorkspaceLeft - 100)
  Gui, WindowSpy:+AlwaysOnTop +Owner
  Gui, WindowSpy:Font, s9, Consolas
  Gui, WindowSpy:Add, Edit, vWindowSpyEdit w%editWidth% r%rowCount% +Multi +ReadOnly, %WindowSpyDisplayInfo%
  ; Show first to render and get dimensions, then reposition flush to bottom-right
  Gui, WindowSpy:Show,, Window Spy (#w or Esc to close)
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
  info.exe := GetExePath("ahk_id " . hwnd)
  info.mon := GetMonitor("ahk_id " . hwnd)
  info.elevated := IsProcessElevated(_pid)
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
  global G_UIA
  result := {name: "", type: "", autoId: "", className: ""}
  Try {
    If (!G_UIA)
      G_UIA := ComObjCreate("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
    _el := 0
    ; IUIAutomation::ElementFromPoint (vtable 7)
    DllCall(NumGet(NumGet(G_UIA+0) + 7*A_PtrSize), "Ptr", G_UIA, "Int64", x | (y << 32), "Ptr*", _el)
    If (!_el)
      Return result
    ; Read properties via GetCurrentPropertyValue (vtable 10)
    result.name := _GetUIAProp(_el, 30005)          ; UIA_NamePropertyId
    result.type := _GetUIAProp(_el, 30004)           ; UIA_LocalizedControlTypePropertyId
    result.autoId := _GetUIAProp(_el, 30011)         ; UIA_AutomationIdPropertyId
    result.className := _GetUIAProp(_el, 30012)      ; UIA_ClassNamePropertyId
    ObjRelease(_el)
  }
  Return result
}

; Read a BSTR property from a UIA element via GetCurrentPropertyValue (vtable 10)
_GetUIAProp(el, propId) {
  VarSetCapacity(_var, 24, 0)
  DllCall(NumGet(NumGet(el+0) + 10*A_PtrSize), "Ptr", el, "Int", propId, "Ptr", &_var)
  _vt := NumGet(_var, 0, "UShort")
  _val := ""
  If (_vt = 8) {  ; VT_BSTR
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
    s .= "Window handle (hWnd): " . info.pointHwnd . "`n"
  s .= "`n"
  ; Path/Process group
  s .= "Folder: " . info.exe.dir . "`n"
  s .= "Process command line: " . WrapList(info.cmdLine, " ") . "`n"
  s .= "Process ID: " . info.pid . (info.elevated ? " (Elevated)" : "") . "`n"
  s .= "`n"
  ; Geometry group
  s .= "Position: (" . info.x . ", " . info.y . ")`n"
  s .= "Monitor: " . info.mon . "`n"
  s .= "Size: " . info.w . " x " . info.h . "`n"
  s .= "Style: " . info.style . "`n"
  s .= "ExStyle: " . info.exStyle . "`n"
  If (info.HasKey("scrollPattern"))
    s .= "ScrollPattern: " . info.scrollPattern . "`n"
  ; UIA element at cursor
  If (info.HasKey("uia") && (info.uia.type != "" || info.uia.name != "")) {
    _uiaLine := "UIA: "
    If (info.uia.type != "")
      _uiaLine .= info.uia.type
    If (info.uia.name != "")
      _uiaLine .= (info.uia.type != "" ? " " : "") . """" . info.uia.name . """"
    s .= _uiaLine . "`n"
    If (info.uia.autoId != "")
      s .= "  AutomationId: " . info.uia.autoId . "`n"
    If (info.uia.className != "")
      s .= "  ClassName: " . info.uia.className . "`n"
  }
  s .= "`n"
  ; Focus/Control group
  If (info.HasKey("focusedControl"))
    s .= "Focused Control: " . info.focusedControl . (info.focusedHwnd != "" ? "`nhWnd: " . info.focusedHwnd : "") . "`n"
  If (info.HasKey("activeFocus"))
    s .= "Active Focus: " . info.activeFocus . (info.activeFocusHwnd != "" ? "`n  hWnd: " . info.activeFocusHwnd : "") . "`n"
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
WrapList(text, delimiter := ",", maxLen := 100) {
  result := ""
  currentLine := ""
  Loop, Parse, text, %delimiter%
  {
    item := Trim(A_LoopField)
    If (item = "")
      Continue
    ; Calculate what this line would look like with the new item
    testLine := currentLine = "" ? item : currentLine . ", " . item
    If (StrLen(testLine) > maxLen && currentLine != "") {
      ; Line would be too long, start a new line
      result .= (result = "" ? "" : "`n  ") . currentLine
      currentLine := item
    } Else {
      currentLine := testLine
    }
  }
  ; Add final line
  If (currentLine != "")
    result .= (result = "" ? "" : "`n  ") . currentLine
  Return result
}

; Clean window text: remove non-ASCII chars, deduplicate if long
CleanWindowText(text) {
  ; Remove non-ASCII characters (keep only printable ASCII 0x20-0x7E)
  cleaned := RegExReplace(text, "[^\x20-\x7E]", "")
  ; Collapse multiple spaces
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

WindowSpyGuiEscape:
WindowSpyGuiClose:
  Gui, WindowSpy:Destroy
  WindowSpyState := 0
Return

WindowSpyUpdate:
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
    display := FormatWindowInfo(info)
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
    display := FormatWindowInfo(info)
  }

  ; Store for dialog (frozen snapshot)
  global WindowSpyDisplayInfo, WindowSpyLastContent
  WindowSpyDisplayInfo := display

  ; Only update tooltip if content changed (reduces flicker)
  If (display = WindowSpyLastContent)
    Return
  WindowSpyLastContent := display

  ; Position tooltip in bottom-right corner
  SysGet, Workspace, MonitorWorkArea
  tooltipHeader := "Window Spy (#w to freeze, Esc to close)`n`n"
  ToolTip, %tooltipHeader%%display%, WorkspaceRight - 550, WorkspaceBottom - 620
Return
