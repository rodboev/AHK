; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ WINDOWS TERMINAL FROM ANYWHERE ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; [ F10 ]                       -> Open current path
; [ Ctrl + F10 ]                -> Run command in current path
; [ Shift + F10 ]               -> Open as admin
; [ Ctrl + Shift + F10 ]        -> Run command as admin
; [ Ctrl + Alt + Shift + F10 ]  -> Open current path as SYSTEM

#IfWinActive ahk_exe WindowsTerminal.exe
  ^F4::Send ^+w
#IfWinActive

F10::OpenTerminal({})
^F10::OpenTerminal({cmd: TA.CtrlCmd})
+F10::OpenTerminal({elevate: true})
^+F10::OpenTerminal({elevate: true, cmd: TA.CtrlCmd})
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
  TA.CtrlCmd := "claude"
  TA.WTProfile := GetWTFirstProfile()
  if (Debug.Log["terminal-anywhere"])
    FileAppend, % TS() . " | terminal-anywhere | " . "TerminalInit: WTProfile=" . TA.WTProfile . "`n", % Debug.Log.Path
}

OpenTerminal(opts) {
  ; opts := {elevate: bool, claude: bool}

  global TA, Debug

  ; When active window is Windows Terminal and not launching Claude, duplicate the tab
  WinGetClass, _class, A
  If (_class = "CASCADIA_HOSTING_WINDOW_CLASS" && !opts.cmd) {
    if (Debug.Log["terminal-anywhere"])
      FileAppend, % TS() . " | terminal-anywhere | " . "OpenTerminal: duplicating tab (active window is WT)`n", % Debug.Log.Path
    If (opts.elevate)
      Send ^+t
    Else
      Send ^+d
    Return
  }

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

  UserRun(_args*)
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
