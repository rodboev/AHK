; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ WINDOWS TERMINAL FROM ANYWHERE ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; [ F10 ]                       -> Open current path
; [ Ctrl + F10 ]                -> Run command 1
; [ Shift + F10 ]               -> Open as admin
; [ Ctrl + Shift + F10 ]        -> Run command 2
; [ Alt + Shift + F10 ]         -> Run command 3
; [ Ctrl + Alt + Shift + F10 ]  -> Open current path as SYSTEM
; [ Win + E ]                   -> Open Explorer at contextual path

TA_GetCommand(slot) {
  static commands := {1: "codex.cmd"
    , 2: "claude.cmd"
    , 3: "mimo.cmd"
    , 4: "hermes"}
  Return commands[slot]
}

#IfWinActive ahk_exe WindowsTerminal.exe
  ^F4::Send ^+w
  +Enter::
    ControlGetFocus, _ctrl, A
    If (InStr(_ctrl, "Windows.UI."))
      Send ^j
    Else
      Send +{Enter}
  Return
  ; Esc::
  ;   ControlGetFocus, _ctrl, A
  ;   If (InStr(_ctrl, "Windows.UI."))
  ;     Send ^[
  ;   Else
  ;     Send {Esc}
  Return
  F10::Send ^+d
  +F10::
    WinGet, _pid, PID, A
    If (IsProcessElevated(_pid)) {
      Send ^+d
      Return
    }
    WinGet, _hwnd, ID, A
    _dir := TA.WindowCwd.HasKey(_hwnd + 0) ? TA.WindowCwd[_hwnd + 0] : ""
    If (!_dir)
      _dir := GetTerminalCwd(_pid, _hwnd)
    If (!_dir)
      _dir := GetTerminalCwdFromContent(_hwnd)
    If (!_dir)
      _dir := GetTerminalCwdViaDup()
    If (!_dir)
      _dir := A_Desktop
    _args := ["elevate", "wt"]
    If (TA.WTProfile) {
      _args.Push("-p")
      _args.Push(TA.WTProfile)
    }
    _args.Push("-d")
    _args.Push(_dir)
    UserRun(_args*)
  Return
  ^F10::
    SendTerminalCommand(1, "Ctrl")
  Return
  ^+F10::
    SendTerminalCommand(2, "Ctrl", "Shift")
  Return
  !F10::
    SendTerminalCommand(4, "Alt")
  Return
  !+F10::
    SendTerminalCommand(3, "Alt", "Shift")
  Return
#IfWinActive

#e::OpenExplorer()

F10::OpenTerminal({})
^F10::OpenTerminal({cmd: TA_GetCommand(1)})
+F10::OpenTerminal({elevate: true})
^+F10::OpenTerminal({cmd: TA_GetCommand(2)})
!F10::OpenTerminal({cmd: TA_GetCommand(4)})
!+F10::OpenTerminal({cmd: TA_GetCommand(3)})
^!+F10:: ; [ Ctrl + Alt + Shift + F10 ] -> Open current path as SYSTEM
  _dir := GetTerminalDir()
  ; Resolve wt.exe to full path — SYSTEM context lacks user PATH entries
  _wtPath := FindInPath("wt.exe")
  If (!_wtPath) {
    MsgBox, 16, TI Elevation, wt.exe not found in PATH
    Return
  }
  ; Build display string and confirm before SYSTEM elevation
  _tiCmd := "ti " . _wtPath
  If (TA.WTProfile)
    _tiCmd .= " -p " . TA.WTProfile
  _tiCmd .= " -d " . _dir
  _displayCmd := StrReplace(_tiCmd, "&", "&&")
  MsgBox, 4, TI Elevation, % "Constructed command:`n`n" . _displayCmd . "`n`nClick Yes to run, No to cancel"
  IfMsgBox No
    Return
  If (TA.WTProfile)
    UserRun("elevate", "ti", _wtPath, "-p " . TA.WTProfile, "-d " . _dir)
  Else
    UserRun("elevate", "ti", _wtPath, "-d " . _dir)
Return

TerminalInit() {
  global TA, Debug
  TA := {}
  TA.WTProfile := GetWTFirstProfile()
  TA.WindowCwd := {}
  TA.PendingCwd := ""
  TA.PendingTime := 0
  if (Debug.Log["terminal-anywhere"])
    FileAppend, % TS() . " | terminal-anywhere | " . "TerminalInit: WTProfile=" . TA.WTProfile . " cmd1=" . TA_GetCommand(1) . " cmd2=" . TA_GetCommand(2) . " cmd3=" . TA_GetCommand(3) . " cmd4=" . TA_GetCommand(4) . "`n", % Debug.Log.Path
}

SendTerminalCommand(slot, heldKeys*) {
  _cmd := TA_GetCommand(slot)
  Send ^+d
  Sleep 10
  For _, _key in heldKeys
    KeyWait, %_key%
  SendInput % _cmd . "{Enter}"
}

OpenTerminal(opts) {
  ; opts := {elevate: bool, cmd: string}

  global TA, Debug

  _dir := GetTerminalDir()
  _args := []
  If (opts.elevate)
    _args.Push("elevate")
  _args.Push("wt")
  If (TA.WTProfile) {
    _args.Push("-p")
    _args.Push(TA.WTProfile)
  }
  _args.Push("-d")
  _args.Push(_dir)
  If (opts.cmd) {
    _args.Push("--")
    _args.Push(opts.cmd)
  }

  if (Debug.Log["terminal-anywhere"])
    FileAppend, % TS() . " | terminal-anywhere | " . "OpenTerminal: elevate=" . (opts.elevate ? "true" : "false") . " cmd=" . (opts.cmd ? opts.cmd : "") . " dir=" . _dir . "`n", % Debug.Log.Path

  ; Store pending CWD so we can map the new window HWND when it appears
  TA.PendingCwd := _dir
  TA.PendingTime := A_TickCount
  TA.ExistingHwnds := _GetWTHwnds()
  UserRun(_args*)
  SetTimer, _TA_CaptureNewWindow, -100
}

_TA_CaptureNewWindow:
  global TA, Debug
  If (A_TickCount - TA.PendingTime > 5000) {
    if (Debug.Log["terminal-anywhere"])
      FileAppend, % TS() . " | terminal-anywhere | " . "CaptureNewWindow: timed out`n", % Debug.Log.Path
    Return
  }
  _newHwnds := _GetWTHwnds()
  For _i, _h in _newHwnds {
    _found := false
    For _j, _existing in TA.ExistingHwnds
      If (_h + 0 = _existing + 0)
        _found := true
    If (!_found) {
      TA.WindowCwd[_h + 0] := TA.PendingCwd
      if (Debug.Log["terminal-anywhere"])
        FileAppend, % TS() . " | terminal-anywhere | " . "CaptureNewWindow: mapped hwnd=" . _h . " -> " . TA.PendingCwd . "`n", % Debug.Log.Path
      TA.PendingCwd := ""
      Return
    }
  }
  ; Window not yet created, retry
  SetTimer, _TA_CaptureNewWindow, -200
Return

_GetWTHwnds() {
  _hwnds := []
  WinGet, _list, List, ahk_class CASCADIA_HOSTING_WINDOW_CLASS
  Loop, %_list% {
    _hwnds.Push(_list%A_Index%)
  }
  Return _hwnds
}

; ⇒ Get terminal CWD by reading visible content via UIA TextPattern
; Matches on %PROMPT% and the folder emoji
GetTerminalCwdFromContent(hwnd) {
  global G_UIA, Debug
  If (!G_UIA) {
    G_UIA := ComObjCreate("{ff48dba4-60ef-4201-aa87-54103eef594e}"
      , "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
    If (!G_UIA)
      Return ""
  }
  ; Find the TermControl element (has TextPattern) via FindFirst with ClassName condition
  ; IUIAutomation::ElementFromHandle (vtable 6)
  _root := 0
  DllCall(NumGet(NumGet(G_UIA+0)+6*A_PtrSize), "Ptr", G_UIA, "Ptr", hwnd, "Ptr*", _root)
  If (!_root) {
    if (Debug.Log["terminal-anywhere"])
      FileAppend, % TS() . " | terminal-anywhere | " . "CwdFromContent: FAILED at ElementFromHandle`n", % Debug.Log.Path
    Return ""
  }
  ; IUIAutomation::CreatePropertyCondition (vtable 23)
  ; UIA_ClassNamePropertyId = 30012, value = "TermControl"
  _cond := 0
  VarSetCapacity(_var, 24, 0)
  NumPut(8, _var, 0, "UShort")  ; VT_BSTR
  _bstrClass := DllCall("OleAut32\SysAllocString", "Str", "TermControl", "Ptr")
  NumPut(_bstrClass, _var, 8, "Ptr")
  DllCall(NumGet(NumGet(G_UIA+0)+23*A_PtrSize), "Ptr", G_UIA, "Int", 30012, "Ptr", &_var, "Ptr*", _cond)
  DllCall("OleAut32\SysFreeString", "Ptr", _bstrClass)
  If (!_cond) {
    ObjRelease(_root)
    if (Debug.Log["terminal-anywhere"])
      FileAppend, % TS() . " | terminal-anywhere | " . "CwdFromContent: FAILED at CreatePropertyCondition`n", % Debug.Log.Path
    Return ""
  }
  ; IUIAutomationElement::FindFirst (vtable 5), scope=Descendants(4)
  _el := 0
  DllCall(NumGet(NumGet(_root+0)+5*A_PtrSize), "Ptr", _root, "Int", 4, "Ptr", _cond, "Ptr*", _el)
  ObjRelease(_cond)
  ObjRelease(_root)
  If (!_el) {
    if (Debug.Log["terminal-anywhere"])
      FileAppend, % TS() . " | terminal-anywhere | " . "CwdFromContent: FAILED FindFirst(TermControl)`n", % Debug.Log.Path
    Return ""
  }
  ; GetCurrentPattern(UIA_TextPatternId = 10014)
  _textPat := 0
  DllCall(NumGet(NumGet(_el+0)+16*A_PtrSize), "Ptr", _el, "Int", 10014, "Ptr*", _textPat)
  ObjRelease(_el)
  If (!_textPat) {
    if (Debug.Log["terminal-anywhere"])
      FileAppend, % TS() . " | terminal-anywhere | " . "CwdFromContent: FAILED GetCurrentPattern on TermControl`n", % Debug.Log.Path
    Return ""
  }
  ; GetVisibleRanges (vtable 6) — only reads on-screen text, much faster than full buffer
  _rangeArray := 0
  DllCall(NumGet(NumGet(_textPat+0)+6*A_PtrSize), "Ptr", _textPat, "Ptr*", _rangeArray)
  ObjRelease(_textPat)
  If (!_rangeArray) {
    if (Debug.Log["terminal-anywhere"])
      FileAppend, % TS() . " | terminal-anywhere | " . "CwdFromContent: FAILED at GetVisibleRanges`n", % Debug.Log.Path
    Return ""
  }
  ; IUIAutomationTextRangeArray::get_Length (vtable 3), GetElement (vtable 4)
  _len := 0
  DllCall(NumGet(NumGet(_rangeArray+0)+3*A_PtrSize), "Ptr", _rangeArray, "Int*", _len)
  _text := ""
  Loop %_len% {
    _range := 0
    DllCall(NumGet(NumGet(_rangeArray+0)+4*A_PtrSize), "Ptr", _rangeArray, "Int", A_Index - 1, "Ptr*", _range)
    If (!_range)
      Continue
    _bstr := 0
    DllCall(NumGet(NumGet(_range+0)+12*A_PtrSize), "Ptr", _range, "Int", -1, "Ptr*", _bstr)
    ObjRelease(_range)
    If (_bstr) {
      _text .= StrGet(_bstr, "UTF-16")
      DllCall("OleAut32\SysFreeString", "Ptr", _bstr)
    }
  }
  ObjRelease(_rangeArray)
  If (_text = "") {
    if (Debug.Log["terminal-anywhere"])
      FileAppend, % TS() . " | terminal-anywhere | " . "CwdFromContent: FAILED empty visible text`n", % Debug.Log.Path
    Return ""
  }
  _folderEmoji := Chr(0xD83D) . Chr(0xDCC1)
  if (Debug.Log["terminal-anywhere"])
    FileAppend, % TS() . " | terminal-anywhere | " . "CwdFromContent: textLen=" . StrLen(_text) . " has📁=" . (InStr(_text, _folderEmoji) ? "yes" : "no") . "`n", % Debug.Log.Path

  ; Match last folder emoji: `📁 <dirName>`
  ; Search via surrogate pair (U+1F4C1 = 0xD83D 0xDCC1) since AHK v1.1 InStr fails on 4-byte emoji
  _folderEmoji := Chr(0xD83D) . Chr(0xDCC1)
  _pos := 1
  _dirName := ""
  While (_pos := InStr(_text, _folderEmoji, false, _pos)) {
    _lineEnd := InStr(_text, "`n", false, _pos)
    _after := SubStr(_text, _pos + 3, _lineEnd ? _lineEnd - _pos - 3 : 200)
    _after := Trim(RegExReplace(_after, "\s+$"))
    ; Extract directory name (everything before " (branch)")
    If RegExMatch(_after, "^(.+?) \(", _m)
      _dirName := _m1
    Else If RegExMatch(_after, "^(\S+)", _m)
      _dirName := _m1
    _pos += 3
  }
  if (Debug.Log["terminal-anywhere"])
    FileAppend, % TS() . " | terminal-anywhere | " . "CwdFromContent: dirName=" . (_dirName ? _dirName : "(none)") . "`n", % Debug.Log.Path
  If (_dirName) {
    ; Search PATH parent directories for this name (non-recursive)
    EnvGet, _pathVar, PATH
    Loop, Parse, _pathVar, `;
    {
      If (A_LoopField = "")
        Continue
      SplitPath, A_LoopField,, _parent
      If (_parent = "")
        _parent := A_LoopField
      _candidate := RTrim(_parent, "\") . "\" . _dirName
      If (InStr(FileExist(_candidate), "D")) {
        if (Debug.Log["terminal-anywhere"])
          FileAppend, % TS() . " | terminal-anywhere | " . "CwdFromContent: dir=" . _dirName . " resolved=" . _candidate . "`n", % Debug.Log.Path
        Return _candidate
      }
    }
  }

  ; Fallback: Match last path in the form of %PROMPT%
  _lastPath := ""
  _pos := 1
  While (_pos := RegExMatch(_text, "m)^([A-Za-z]:\\[^\r\n""<>|*?]+)> ", _m, _pos)) {
    _candidate := RTrim(_m1, " .\t")
    If (InStr(FileExist(_candidate), "D"))
      _lastPath := _candidate
    _pos += StrLen(_m)
  }
  if (Debug.Log["terminal-anywhere"])
    FileAppend, % TS() . " | terminal-anywhere | " . "CwdFromContent: fallback path=" . (_lastPath ? _lastPath : "(none)") . "`n", % Debug.Log.Path
  Return _lastPath
}

; ⇒ Get terminal CWD via tab duplication trick (flashes a new tab)
GetTerminalCwdViaDup() {
  global Debug
  KeyWait, LWin
  _savedClip := ClipboardAll
  Clipboard := ""
  Send ^+d
  Sleep 10
  SendInput cd.| clip{Enter}
  ClipWait, 1
  Send ^+w
  _cwd := RTrim(Clipboard, "`r`n ")
  Clipboard := _savedClip
  _savedClip := ""
  if (Debug.Log["terminal-anywhere"])
    FileAppend, % TS() . " | terminal-anywhere | " . "GetTerminalCwdViaDup: result=" . _cwd . "`n", % Debug.Log.Path
  Return _cwd
}

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Shell Automation — Programmatic access to Explorer windows/folders      ║
; ║  Docs: https://learn.microsoft.com/en-us/windows/win32/shell/shell-entry ║
; ╚══════════════════════════════════════════════════════════════════════════╝
; COM Interface (from ShObjIdl.h)
;   IID_IShellBrowser = {000214E2-0000-0000-C000-000000000046}
;
; Used in ComObjQuery(window, SID, IID) where SID=IID for direct interface access.
; Needed for tabbed Explorer: IOleWindow::GetWindow (vtable 3) returns tab HWND.

; ⇒ Get current path of active Explorer window (tab-aware for Win11 22H2+)
GetExplorerPath() {
  static shell := ComObjCreate("Shell.Application")
  WinGet, hwnd, ID, A
  ; ShellTabWindowClass1 = active tab (ClassNN 1 = highest z-order)
  activeTab := 0
  Try ControlGet, activeTab, Hwnd,, ShellTabWindowClass1, ahk_id %hwnd%
  For window in shell.Windows {
    If (window.hwnd != hwnd)
      Continue
    If (activeTab) {
      ; IOleWindow::GetWindow (vtable 3) returns each tab's HWND
      shellBrowser := ComObjQuery(window
        , "{000214E2-0000-0000-C000-000000000046}"
        , "{000214E2-0000-0000-C000-000000000046}")
      If (!shellBrowser)
        Continue
      thisTab := 0
      Try {
        DllCall(NumGet(NumGet(shellBrowser+0)+3*A_PtrSize)
          , "Ptr", shellBrowser, "UInt*", thisTab)
      } Finally {
        ObjRelease(shellBrowser)
      }
      If (thisTab != activeTab)
        Continue
    }
    Try {
      _path := window.Document.Folder.Self.Path
      Return RegExMatch(_path, "^[A-Za-z]:\\|^\\\\") && !InStr(_path, "::") ? _path : ""
    }
    Catch {
      Return ""  ; not a filesystem view
    }
  }
  Return ""
}

GetTerminalDir() {
  global Debug
  WinGetClass, _class, A
  if (Debug.Log["terminal-anywhere"])
    FileAppend, % TS() . " | terminal-anywhere | " . "GetTerminalDir: class=" . _class . "`n", % Debug.Log.Path
  If (_class = "Progman")
    Return A_Desktop
  If (_class = "CabinetWClass") {
    _path := GetExplorerPath()
    if (Debug.Log["terminal-anywhere"])
      FileAppend, % TS() . " | terminal-anywhere | " . "GetExplorerPath returned: " . _path . "`n", % Debug.Log.Path
    _path := _path ? _path : A_MyDocuments
  } Else {
    ; Try extracting a path from the title bar first
    _path := GetTitleBarPath()
    If (!_path)
      _path := A_Desktop
  }
  ; For root paths like C:\, add trailing dot to avoid \" escape issue when quoted
  If (RegExMatch(_path, "^[A-Za-z]:\\$"))
    _path .= "."
  Return _path
}

; Extract a filesystem path from the active window's title bar.
; Matches patterns like "C:\Users\..." or "\\server\share\..." anywhere in the title,
; then walks back to the longest existing ancestor directory.
GetTitleBarPath() {
  global Debug
  WinGetTitle, _title, A
  If (_title = "")
    Return ""
  ; Match a path (drive letter or UNC) anywhere in the title
  If (!RegExMatch(_title, "([A-Za-z]:\\[^""<>|*?:]+|\\\\[^""<>|*?:]+)", _m))
    Return ""
  _candidate := _m1
  if (Debug.Log["terminal-anywhere"])
    FileAppend, % TS() . " | terminal-anywhere | " . "GetTitleBarPath: candidate=" . _candidate . "`n", % Debug.Log.Path
  ; Trim at " - " separators from right to left (title bar decoration)
  _try := _candidate
  Loop {
    _trimmed := RegExReplace(_try, "[\s\-\.]+$")
    _attr := FileExist(_trimmed)
    If (_attr && !InStr(_attr, "D")) {
      SplitPath, _trimmed,, _dir
      Return _dir
    }
    If (InStr(_attr, "D"))
      Return _trimmed
    ; Trim at the last " - " and retry
    _pos := InStr(_try, " - ",, 0)
    If (!_pos)
      Break
    _try := SubStr(_try, 1, _pos - 1)
  }
  ; Walk up backslashes as fallback
  _check := _candidate
  Loop {
    SplitPath, _check,, _parent
    If (_parent = "" || _parent = _check)
      Break
    _check := _parent
    If (InStr(FileExist(_check), "D"))
      Return _check
  }
  Return ""
}

; ⇒ Read first non-hidden profile name from Windows Terminal settings.json
GetWTFirstProfile() {
  EnvGet, _localAppData, LocalAppData
  _paths := [_localAppData . "\Microsoft\Windows Terminal\settings.json"
    , _localAppData . "\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
    , _localAppData . "\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"]
  For _, _path in _paths {
    If (!FileExist(_path))
      Continue
    FileRead, _json, %_path%
    If (ErrorLevel)
      Continue
    ; Find "list" array in profiles section
    _listPos := InStr(_json, """list""")
    If (!_listPos)
      Continue
    _afterList := SubStr(_json, _listPos)
    ; Scan consecutive "name" entries; check text before each for "hidden": true
    ; Works because WT sorts keys alphabetically → "hidden" always precedes "name"
    _pos := 1
    _lastPos := 1
    While (_matchPos := RegExMatch(_afterList, """name""\s*:\s*""([^""]+)""", _m, _pos)) {
      _segment := SubStr(_afterList, _lastPos, _matchPos - _lastPos)
      If (!RegExMatch(_segment, """hidden""\s*:\s*true"))
        Return _m1
      _lastPos := _matchPos
      _pos := _matchPos + StrLen(_m)
    }
  }
  Return ""
}

; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ EXPLORER FROM ANYWHERE (Win+E contextual) ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

OpenExplorer() {
  global TA, Debug
  KeyWait, LWin
  WinGetClass, _class, A

  ; Explorer — open new Explorer window
  If (_class = "CabinetWClass") {
    if (Debug.Log["terminal-anywhere"])
      FileAppend, % TS() . " | terminal-anywhere | " . "OpenExplorer: from Explorer, opening new window`n", % Debug.Log.Path
    Run explorer
    Return
  }

  ; Terminal — stored mapping → process CWD → visible content → dup trick
  If (_class = "CASCADIA_HOSTING_WINDOW_CLASS") {
    WinGet, _hwnd, ID, A
    WinGet, _wtPid, PID, A
    _path := TA.WindowCwd.HasKey(_hwnd + 0) ? TA.WindowCwd[_hwnd + 0] : ""
    _source := "stored"
    if (Debug.Log["terminal-anywhere"] && _path)
      FileAppend, % TS() . " | terminal-anywhere | " . "OpenExplorer: stored=" . _path . "`n", % Debug.Log.Path
    If (!_path) {
      _path := GetTerminalCwd(_wtPid, _hwnd)
      _source := "process"
      if (Debug.Log["terminal-anywhere"])
        FileAppend, % TS() . " | terminal-anywhere | " . "OpenExplorer: GetTerminalCwd=" . (_path ? _path : "(none)") . "`n", % Debug.Log.Path
    }
    If (!_path) {
      _path := GetTerminalCwdFromContent(_hwnd)
      _source := "content"
      if (Debug.Log["terminal-anywhere"])
        FileAppend, % TS() . " | terminal-anywhere | " . "OpenExplorer: GetTerminalCwdFromContent=" . (_path ? _path : "(none)") . "`n", % Debug.Log.Path
    }
    If (!_path) {
      _path := GetTerminalCwdViaDup()
      _source := "dup"
      if (Debug.Log["terminal-anywhere"])
        FileAppend, % TS() . " | terminal-anywhere | " . "OpenExplorer: GetTerminalCwdViaDup=" . (_path ? _path : "(none)") . "`n", % Debug.Log.Path
    }
    If (_path)
      TA.WindowCwd[_hwnd + 0] := _path
    if (Debug.Log["terminal-anywhere"])
      FileAppend, % TS() . " | terminal-anywhere | " . "OpenExplorer: result path=" . (_path ? _path : "(none)") . " source=" . _source . "`n", % Debug.Log.Path
    If (!_path) {
      if (Debug.Log["terminal-anywhere"])
        FileAppend, % TS() . " | terminal-anywhere | " . "OpenExplorer: no terminal CWD, falling through to namespace root`n", % Debug.Log.Path
    }
  } Else {
    ; Other apps — try extracting a path from the title bar
    _path := GetTitleBarPath()
    if (Debug.Log["terminal-anywhere"])
      FileAppend, % TS() . " | terminal-anywhere | " . "OpenExplorer: titlebar=" . (_path ? _path : "(none)") . "`n", % Debug.Log.Path
  }

  ; No path found or path is Desktop — open Explorer home
  If (!_path || _path = A_Desktop) {
    if (Debug.Log["terminal-anywhere"])
      FileAppend, % TS() . " | terminal-anywhere | " . "OpenExplorer: opening Explorer home (path=" . (_path ? _path : "none") . ")`n", % Debug.Log.Path
    Run explorer
    Return
  }

  ; Activate existing Explorer window at this path instead of opening a new one
  If (_ActivateExplorerAt(_path)) {
    if (Debug.Log["terminal-anywhere"])
      FileAppend, % TS() . " | terminal-anywhere | " . "OpenExplorer: activated existing at " . _path . "`n", % Debug.Log.Path
    Return
  }

  if (Debug.Log["terminal-anywhere"])
    FileAppend, % TS() . " | terminal-anywhere | " . "OpenExplorer: opening new via UserRun(explorer, " . _path . ")`n", % Debug.Log.Path
  UserRun("explorer", _path)
}

_ActivateExplorerAt(targetPath) {
  static shell := ComObjCreate("Shell.Application")
  _target := RTrim(targetPath, "\")
  For window in shell.Windows {
    Try _wPath := window.Document.Folder.Self.Path
    Catch
      Continue
    If (_wPath = "" || InStr(_wPath, "::"))
      Continue
    If (RTrim(_wPath, "\") = _target) {
      _hwnd := window.hwnd
      WinActivate, ahk_id %_hwnd%
      If (IsFunc("WS_MoveToMonitor")) {
        _winMon := GetMonitor("ahk_id " . _hwnd)
        _curMon := GetCursorMonitor()
        If (_winMon != _curMon)
          WS_MoveToMonitor(_hwnd, _winMon, _curMon)
      }
      Return true
    }
  }
  Return false
}
