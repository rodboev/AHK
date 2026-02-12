; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ WINDOWS TERMINAL FROM ANYWHERE ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; [ F10 ]                       -> Open current path (auto-detect WSL)
; [ Alt + F10 ]                 -> Open current path, force WSL
; [ Shift + F10 ]               -> Open current path as admin
; [ Alt + Shift + F10 ]         -> Open current path as admin, force WSL
; [ Ctrl + F10 ]                -> Open claude in current path
; [ Ctrl + Shift + F10 ]        -> Open claude in current path as admin
; [ Ctrl + Alt + Shift + F10 ]  -> Open current path as SYSTEM

F10::OpenTerminal(   {elevate: false, claude: false})
!F10::OpenTerminal(  {elevate: false, claude: false, wsl: true})
+F10::OpenTerminal(  {elevate: true,  claude: false})
!+F10::OpenTerminal( {elevate: true,  claude: false, wsl: true})
^F10::OpenTerminal(  {elevate: false, claude: true})
^+F10::OpenTerminal( {elevate: true,  claude: true})
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

; ⇒ Open Windows Terminal with optional WSL profile, elevation, and Claude
OpenTerminal(opts) {
  ; opts := {elevate: bool, claude: bool, wsl: bool}
  ;   elevate  true  = run as Administrator (UAC prompt)
  ;   claude   true  = launch Claude CLI in WSL
  ;   wsl      true  = force WSL even from Windows paths (Alt variants)
  ;   Missing wsl key = auto-detect from path only

  global TA
  _winDir := GetTerminalDir()
  _wsl := ParseWSLPath(_winDir)

  If (IsObject(_wsl)) {
    ; UNC path — WSL detected from path
    _profile := _wsl.distro
  } Else If (opts.wsl && TA.WSLDistro) {
    ; Force WSL — Windows path stays as-is, WT translates to /mnt/ internally
    _profile := TA.WSLDistro
  } Else {
    ; Windows path — use configured WT profile
    _profile := TA.WTProfile
  }

  ; Build wt command — always pass original Windows/UNC path to -d
  ; WT handles path translation for WSL profiles internally
  _args := []
  If (opts.elevate)
    _args.Push("elevate")
  _args.Push("wt")
  If (_profile)
    _args.Push("-p", _profile)
  _args.Push("-d " . _winDir)
  _isWSL := IsObject(_wsl) || (opts.wsl && TA.WSLDistro)
  If (opts.claude && _isWSL)
    _args.Push("--", "bash", "-lic", "claude")

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

; ⇒ Parse WSL UNC path into distro name and Linux directory
; Input:  \\wsl.localhost\Ubuntu-24.04\home\rod\chats  or  \\wsl$\Ubuntu-24.04\home\rod
; Output: {distro: "Ubuntu-24.04", dir: "/home/rod/chats"} or "" if not a WSL path
ParseWSLPath(path) {
  If (!RegExMatch(path, "i)^\\\\wsl(?:\.localhost|\$)\\([^\\]+)\\?(.*)", m))
    Return ""
  _dir := m2 ? ("/" . StrReplace(m2, "\", "/")) : "/"
  Return {distro: m1, dir: _dir}
}

; ⇒ Convert Windows drive path to WSL /mnt/ path
; Input:  C:\Users\Rod\AppData
; Output: /mnt/c/Users/Rod/AppData
WinToWSLPath(path) {
  If (!RegExMatch(path, "^([A-Za-z]):\\(.*)", m))
    Return path
  _drive := Format("{:L}", m1)
  Return "/mnt/" . _drive . "/" . StrReplace(m2, "\", "/")
}
