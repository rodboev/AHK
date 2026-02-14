; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ WINDOWS TERMINAL FROM ANYWHERE ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; [ F10 ]                       -> Open current path
; [ Alt + F10 ]                 -> Open Linux (home folder)
; [ Shift + F10 ]               -> Open current path as admin
; [ Alt + Shift + F10 ]         -> Open Linux as admin (home folder)
; [ Ctrl + Alt + Shift + F10 ]  -> Open current path as SYSTEM

F10::OpenTerminal(   {elevate: false})
!F10::OpenTerminal(  {elevate: false, alt: true})
+F10::OpenTerminal(  {elevate: true})
!+F10::OpenTerminal( {elevate: true,  alt: true})
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
    UserRun("elevate", "ti", _wtPath, "-p", TA.WTProfile, "-d " . _dir)
  Else
    UserRun("elevate", "ti", _wtPath, "-d " . _dir)
Return

; ⇒ Initialize terminal-anywhere config (called from auto-execute section)
TerminalInit() {
  global TA
  TA := {}
  TA.WSLDistro := GetDefaultWSLDistro()
  TA.WTProfile := ""
  If (!TA.WTProfile)
    TA.WTProfile := GetWTFirstProfile()
}

; ⇒ Open Windows Terminal with optional elevation
OpenTerminal(opts) {
  ; opts := {elevate: bool, alt: bool}
  ;   elevate  true  = run as Administrator (UAC prompt)
  ;   alt      true  = use WSL profile (home folder)

  global TA
  _args := []
  If (opts.elevate)
    _args.Push("elevate")
  _args.Push("wt")
  If (opts.alt) {
    If (TA.WSLDistro)
      _args.Push("-p", TA.WSLDistro)
  } Else {
    If (TA.WTProfile)
      _args.Push("-p", TA.WTProfile)
    _args.Push("-d " . GetTerminalDir())
  }
  UserRun(_args*)
}

; ⇒ Resolve working directory from active window context
GetTerminalDir() {
  global G_UserProfile
  WinGetClass, _class, A
  If (_class = "Progman")
    Return A_Desktop
  If (_class = "CabinetWClass") {
    _path := GetExplorerPath()
    Return _path ? _path : G_UserProfile
  }
  _exe := GetExePath()
  Return _exe.dir ? _exe.dir : G_UserProfile
}

; ⇒ Read default WSL distro name from registry
GetDefaultWSLDistro() {
  RegRead, _guid, HKCU, Software\Microsoft\Windows\CurrentVersion\Lxss, DefaultDistribution
  If (ErrorLevel || !_guid)
    Return ""
  RegRead, _name, HKCU, Software\Microsoft\Windows\CurrentVersion\Lxss\%_guid%, DistributionName
  Return ErrorLevel ? "" : _name
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
