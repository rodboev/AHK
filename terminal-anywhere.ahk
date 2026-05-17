; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ WINDOWS TERMINAL FROM ANYWHERE ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; [ F10 ]                       -> Open current path
; [ Shift + F10 ]               -> Open current path as admin
; [ Ctrl + Alt + Shift + F10 ]  -> Open current path as SYSTEM

F10::OpenTerminal({elevate: false})
+F10::OpenTerminal({elevate: true})
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
  if (Debug.Log["terminal-anywhere"])
    FileAppend, % TS() . " | terminal-anywhere | " . "TerminalInit: WTProfile=" . TA.WTProfile . "`n", % Debug.Log.Path
}

OpenTerminal(opts) {
  ; opts := {elevate: bool}
  ;   elevate  true  = run as Administrator (UAC prompt)

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

  if (Debug.Log["terminal-anywhere"])
    FileAppend, % TS() . " | terminal-anywhere | " . "OpenTerminal: elevate=" . (opts.elevate ? "true" : "false") . " dir=" . _dir . "`n", % Debug.Log.Path

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
    _exe := GetExePath()
    _path := _exe.dir ? _exe.dir : A_MyDocuments
  }
  ; For root paths like C:\, add trailing dot to avoid \" escape issue when quoted
  If (RegExMatch(_path, "^[A-Za-z]:\\$"))
    _path .= "."
  Return _path
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
