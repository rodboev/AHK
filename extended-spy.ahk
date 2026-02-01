; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === EXTENDED WINDOW SPY === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; Description: Persistent tooltip showing window info (active + under cursor)
; Click tooltip or press #w again to freeze and show dialog for copying
; Forum link: https://autohotkey.com/boards/viewtopic.php?f=6&t=43544
; Author: @rodboev
; Version: 1.0
#w::
  Gui, WindowSpy:Destroy  ; Close dialog if open
  WindowSpyToggle := !WindowSpyToggle
  If (WindowSpyToggle) {
    WindowSpyLastContent := ""  ; Clear cache to force first update
    SetTimer, WindowSpyUpdate, 800
    GoSub, WindowSpyUpdate  ; Immediate first update
  } Else {
    SetTimer, WindowSpyUpdate, Off
    ToolTip
  }
Return

$Esc::
  ; Close WindowSpy dialog if open
  If WinExist("Window Spy (Esc to close)") {
    Gui, WindowSpy:Destroy
    Return
  }
  ; Close WindowSpy tooltip if active
  If (WindowSpyToggle) {
    SetTimer, WindowSpyUpdate, Off
    ToolTip
    WindowSpyToggle := false
    Return
  }
  ; Pass Esc through to active window
  Send {Esc}
Return

~LButton::
  If (WindowSpyToggle) {
    MouseGetPos,,, clickWin
    WinGetClass, clickClass, ahk_id %clickWin%
    If (clickClass = "tooltips_class32") {
      SetTimer, WindowSpyUpdate, Off
      ToolTip
      WindowSpyToggle := false
      WindowSpyShowDialog()
    }
  }
Return

WindowSpyShowDialog() {
  global WindowSpyRawInfo, WindowSpyEdit
  If (WindowSpyRawInfo = "")
    Return
  ToolTip  ; Destroy tooltip when showing dialog
  Gui, WindowSpy:Destroy
  SysGet, Workspace, MonitorWorkArea
  ; Count lines and calculate max dimensions based on workspace
  StringReplace, _, WindowSpyRawInfo, `n, `n, UseErrorLevel
  lineCount := ErrorLevel + 1
  maxHeight := WorkspaceBottom - WorkspaceTop - 50  ; Leave margin for title bar
  rowHeight := 22  ; Consolas 9pt + Edit control internal padding
  maxRows := Floor(maxHeight / rowHeight)
  rowCount := Min(lineCount, maxRows)
  editWidth := Min(700, WorkspaceRight - WorkspaceLeft - 100)
  Gui, WindowSpy:+AlwaysOnTop +Owner
  Gui, WindowSpy:Font, s9, Consolas
  Gui, WindowSpy:Add, Edit, vWindowSpyEdit w%editWidth% r%rowCount% +Multi +ReadOnly, %WindowSpyRawInfo%
  ; Show first to render and get dimensions, then reposition flush to bottom-right
  Gui, WindowSpy:Show,, Window Spy (Esc to close)
  WinGetPos,,, GUIWidth, GUIHeight, A
  xPos := WorkspaceRight - GUIWidth
  yPos := WorkspaceBottom - GUIHeight
  WinMove, A,, %xPos%, %yPos%
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

  ; === ACTIVE WINDOW ===
  WinGet, ActiveWin, ID, A
  WinGetTitle, ActiveTitle, ahk_id %ActiveWin%
  WinGetClass, ActiveClass, ahk_id %ActiveWin%
  WinGet, ActivePID, PID, ahk_id %ActiveWin%
  WinGetPos, ActiveX, ActiveY, ActiveW, ActiveH, ahk_id %ActiveWin%
  WinGet, ActiveStyle, Style, ahk_id %ActiveWin%
  WinGet, ActiveExStyle, ExStyle, ahk_id %ActiveWin%
  ControlGetFocus, ActiveFocusedControl, ahk_id %ActiveWin%
  ActiveFocusedHwnd := ""
  If (ActiveFocusedControl != "")
    ControlGet, ActiveFocusedHwnd, Hwnd,, %ActiveFocusedControl%, ahk_id %ActiveWin%
  activeExe := GetExePath("ahk_id " ActiveWin)
  activeMon := GetMonitor("ahk_id " ActiveWin)
  activeElevated := IsProcessElevated(ActivePID)
  activeCmdLine := ""
  For process in ComObjGet("winmgmts:").ExecQuery("Select CommandLine from Win32_Process where ProcessId=" . ActivePID)
    activeCmdLine := process.CommandLine
  WinGetText, ActiveWinText, ahk_id %ActiveWin%
  WinGet, ActiveControls, ControlList, ahk_id %ActiveWin%

  ; Format controls: comma-separated, filter >80 chars, sort alphabetically
  StringReplace, ActiveControlsRaw, ActiveControls, `r`n, `, , All
  StringReplace, ActiveControlsRaw, ActiveControlsRaw, `n, `, , All
  ActiveControlsRaw := SortList(FilterLongItems(ActiveControlsRaw))
  ActiveControlsDisplay := WrapList(ActiveControlsRaw, ",")
  ; Format window text: comma-separated, clean non-ASCII, filter >80 chars, dedupe if long
  StringReplace, ActiveWinTextRaw, ActiveWinText, `r`n, `, , All
  StringReplace, ActiveWinTextRaw, ActiveWinTextRaw, `n, `, , All
  ActiveWinTextRaw := RTrim(FilterLongItems(CleanWindowText(ActiveWinTextRaw)), ", ")
  ActiveWinTextDisplay := WrapList(ActiveWinTextRaw, ",")

  ; UIA for active window - just show persistent object reference
  ActiveUIA_Info := ""
  Try {
    global G_UIA
    If (!G_UIA)
      G_UIA := ComObjCreate("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
    ActiveUIA_Info := "UIA: " G_UIA
  } catch e {
    ActiveUIA_Info := "UIA: EXCEPTION - " e.Message
  }

  ; Build wrapped version for tooltip
  ActiveInfo := "=== ACTIVE WINDOW ===`n"
  ActiveInfo .= "Title: " ActiveTitle "`n"
  ActiveInfo .= "ahk_id: " ActiveWin " | ahk_class: " ActiveClass "`n"
  ActiveInfo .= "ahk_exe: " activeExe.path "`n"
  ActiveInfo .= "Dir: " activeExe.dir "`n"
  ActiveInfo .= "CmdLine: " WrapList(activeCmdLine, " ") "`n"
  ActiveInfo .= "PID: " ActivePID (activeElevated ? " (Elevated)" : "") " | Monitor: " activeMon "`n"
  ActiveInfo .= "Pos: (" ActiveX ", " ActiveY ") | Size: " ActiveW " x " ActiveH "`n"
  ActiveInfo .= "Style: " ActiveStyle " | ExStyle: " ActiveExStyle "`n"
  ActiveInfo .= "ScrollPattern: " MB_ScrollPattern "`n"
  ActiveInfo .= "Focused Control: " ActiveFocusedControl (ActiveFocusedHwnd ? " | hWnd: " ActiveFocusedHwnd : "") "`n"
  ActiveInfo .= ActiveUIA_Info "`n"
  ActiveInfo .= "Window Text: " ActiveWinTextDisplay "`n"
  ActiveInfo .= "Controls: " ActiveControlsDisplay "`n"

  ; Build raw version for dialog
  ActiveInfoRaw := "=== ACTIVE WINDOW ===`n"
  ActiveInfoRaw .= "Title: " ActiveTitle "`n"
  ActiveInfoRaw .= "ahk_id: " ActiveWin " | ahk_class: " ActiveClass "`n"
  ActiveInfoRaw .= "ahk_exe: " activeExe.path "`n"
  ActiveInfoRaw .= "Dir: " activeExe.dir "`n"
  ActiveInfoRaw .= "CmdLine: " activeCmdLine "`n"
  ActiveInfoRaw .= "PID: " ActivePID (activeElevated ? " (Elevated)" : "") " | Monitor: " activeMon "`n"
  ActiveInfoRaw .= "Pos: (" ActiveX ", " ActiveY ") | Size: " ActiveW " x " ActiveH "`n"
  ActiveInfoRaw .= "Style: " ActiveStyle " | ExStyle: " ActiveExStyle "`n"
  ActiveInfoRaw .= "Focused Control: " ActiveFocusedControl (ActiveFocusedHwnd ? " | hWnd: " ActiveFocusedHwnd : "") "`n"
  ActiveInfoRaw .= ActiveUIA_Info "`n"
  ActiveInfoRaw .= "Window Text: " ActiveWinTextRaw "`n"
  ActiveInfoRaw .= "Controls: " ActiveControlsRaw "`n"

  ; === WINDOW UNDER CURSOR ===
  WinGetTitle, CursorTitle, ahk_id %CursorWin%
  WinGetClass, CursorClass, ahk_id %CursorWin%
  WinGet, CursorPID, PID, ahk_id %CursorWin%
  WinGetPos, CursorWinX, CursorWinY, CursorWinW, CursorWinH, ahk_id %CursorWin%
  WinGet, CursorStyle, Style, ahk_id %CursorWin%
  WinGet, CursorExStyle, ExStyle, ahk_id %CursorWin%
  cursorExe := GetExePath("ahk_id " CursorWin)
  cursorMon := GetMonitor("ahk_id " CursorWin)
  cursorElevated := IsProcessElevated(CursorPID)
  CursorHwnd := DllCall("WindowFromPoint", "int64", CursorX | (CursorY << 32), "Ptr")
  cursorCmdLine := ""
  For process in ComObjGet("winmgmts:").ExecQuery("Select CommandLine from Win32_Process where ProcessId=" . CursorPID)
    cursorCmdLine := process.CommandLine
  WinGetText, CursorWinText, ahk_id %CursorWin%
  WinGet, CursorControls, ControlList, ahk_id %CursorWin%

  ; Format controls: comma-separated, filter >80 chars, sort alphabetically
  StringReplace, CursorControlsRaw, CursorControls, `r`n, `, , All
  StringReplace, CursorControlsRaw, CursorControlsRaw, `n, `, , All
  CursorControlsRaw := SortList(FilterLongItems(CursorControlsRaw))
  CursorControlsDisplay := WrapList(CursorControlsRaw, ",")
  ; Format window text: comma-separated, clean non-ASCII, filter >80 chars, dedupe if long
  StringReplace, CursorWinTextRaw, CursorWinText, `r`n, `, , All
  StringReplace, CursorWinTextRaw, CursorWinTextRaw, `n, `, , All
  CursorWinTextRaw := RTrim(FilterLongItems(CleanWindowText(CursorWinTextRaw)), ", ")
  CursorWinTextDisplay := WrapList(CursorWinTextRaw, ",")

  ; Cursor position relative to window
  CursorRelX := CursorX - CursorWinX
  CursorRelY := CursorY - CursorWinY

  ; UIA Element Info - just show if UIA is available
  UIA_Info := ""
  Try {
    global G_UIA
    If (!G_UIA)
      G_UIA := ComObjCreate("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
    UIA_Info := "UIA: " G_UIA
  } catch e {
    UIA_Info := "UIA: EXCEPTION - " e.Message
  }

  ; Build wrapped version for tooltip
  CursorInfo := "`n=== UNDER CURSOR ===`n"
  CursorInfo .= "Title: " CursorTitle "`n"
  CursorInfo .= "ahk_id: " CursorWin " | ahk_class: " CursorClass "`n"
  CursorInfo .= "ahk_exe: " cursorExe.path "`n"
  CursorInfo .= "Dir: " cursorExe.dir "`n"
  CursorInfo .= "CmdLine: " WrapList(cursorCmdLine, " ") "`n"
  CursorInfo .= "PID: " CursorPID (cursorElevated ? " (Elevated)" : "") " | Monitor: " cursorMon "`n"
  CursorInfo .= "Pos: (" CursorWinX ", " CursorWinY ") | Size: " CursorWinW " x " CursorWinH "`n"
  CursorInfo .= "Style: " CursorStyle " | ExStyle: " CursorExStyle "`n"
  CursorInfo .= "Control: " ClassNN " | hWnd: " CursorHwnd "`n"
  ; CursorInfo .= "Cursor: (" CursorX ", " CursorY ") | CursorRel: (" CursorRelX ", " CursorRelY ")`n"
  CursorInfo .= UIA_Info "`n"
  CursorInfo .= "Window Text: " CursorWinTextDisplay "`n"
  CursorInfo .= "Controls: " CursorControlsDisplay

  ; Build raw version for dialog
  CursorInfoRaw := "`n=== UNDER CURSOR ===`n"
  CursorInfoRaw .= "Title: " CursorTitle "`n"
  CursorInfoRaw .= "ahk_id: " CursorWin " | ahk_class: " CursorClass "`n"
  CursorInfoRaw .= "ahk_exe: " cursorExe.path "`n"
  CursorInfoRaw .= "Dir: " cursorExe.dir "`n"
  CursorInfoRaw .= "CmdLine: " cursorCmdLine "`n"
  CursorInfoRaw .= "PID: " CursorPID (cursorElevated ? " (Elevated)" : "") " | Monitor: " cursorMon "`n"
  CursorInfoRaw .= "Pos: (" CursorWinX ", " CursorWinY ") | Size: " CursorWinW " x " CursorWinH "`n"
  CursorInfoRaw .= "Style: " CursorStyle " | ExStyle: " CursorExStyle "`n"
  CursorInfoRaw .= "Control: " ClassNN " | hWnd: " CursorHwnd "`n"
  ; CursorInfoRaw .= "Cursor: (" CursorX ", " CursorY ") | CursorRel: (" CursorRelX ", " CursorRelY ")`n"
  CursorInfoRaw .= UIA_Info "`n"
  CursorInfoRaw .= "Window Text: " CursorWinTextRaw "`n"
  CursorInfoRaw .= "Controls: " CursorControlsRaw

  ; Store for tooltip and dialog
  global WindowSpyRawInfo, WindowSpyLastContent
  WindowSpyRawInfo := ActiveInfoRaw . CursorInfoRaw

  ; Only update tooltip if content changed (reduces flicker)
  newContent := ActiveInfo . CursorInfo
  If (newContent = WindowSpyLastContent)
    Return
  WindowSpyLastContent := newContent

  ; Position tooltip in bottom-right corner
  SysGet, Workspace, MonitorWorkArea
  tooltipHeader := "Window Spy (Click to copy, Esc or #w to close)`n`n"
  ToolTip, %tooltipHeader%%newContent%, WorkspaceRight - 550, WorkspaceBottom - 620
Return
