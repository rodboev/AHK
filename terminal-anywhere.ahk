; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ WINDOWS TERMINAL FROM ANYWHERE ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
F10:: ; -> Open in current path, use WSL profile for WSL paths
  _dir := _GetTerminalDir()
  ; WSL UNC path (\\wsl.localhost\distro\...)
  _wsl := _ParseWSLPath(_dir)
  If (IsObject(_wsl)) {
    UserRun("wt", "-p", _wsl.distro, "-d " . _dir)
    Return
  }
  ; Auto-open in WSL profile for configured path prefix
  If (G_WSLDistro && G_WSLAutoPath && InStr(_dir, G_WSLAutoPath) = 1) {
    UserRun("wt", "-p", G_WSLDistro, "-d " . _dir)
    Return
  }
  UserRun("wt", "-d " . _dir)
Return

!F10:: ; [ Alt + F10 ] -> Open WSL profile from any path
  _dir := _GetTerminalDir()
  ; WSL UNC path already has distro info
  _wsl := _ParseWSLPath(_dir)
  If (IsObject(_wsl)) {
    UserRun("wt", "-p", _wsl.distro, "-d " . _dir)
    Return
  }
  ; Any drive letter path → open in WSL profile
  If (G_WSLDistro && RegExMatch(_dir, "^[A-Za-z]:\\")) {
    UserRun("wt", "-p", G_WSLDistro, "-d " . _dir)
    Return
  }
  UserRun("wt", "-d " . _dir)
Return

!+F10:: ; [ Alt + Shift + F10 ] -> Open WSL profile from any path (elevated)
  _dir := _GetTerminalDir()
  _wsl := _ParseWSLPath(_dir)
  If (IsObject(_wsl)) {
    UserRun("elevate", "wt", "-p", _wsl.distro, "-d " . _dir)
    Return
  }
  If (G_WSLDistro && RegExMatch(_dir, "^[A-Za-z]:\\")) {
    UserRun("elevate", "wt", "-p", G_WSLDistro, "-d " . _dir)
    Return
  }
  UserRun("elevate", "wt", "-d " . _dir)
Return

^F10:: ; [ Ctrl + F10 ] -> Open WSL profile + launch claude
  _dir := _GetTerminalDir()
  _distro := ""
  _wsl := _ParseWSLPath(_dir)
  If (IsObject(_wsl))
    _distro := _wsl.distro
  Else If (G_WSLDistro && RegExMatch(_dir, "^[A-Za-z]:\\"))
    _distro := G_WSLDistro
  If (_distro)
    UserRun("wt", "-p", _distro, "-d " . _dir, "--", "bash", "-lic", """claude --dangerously-skip-permissions""")
  Else
    UserRun("wt", "-d " . _dir)
Return

^+F10:: ; [ Ctrl + Shift + F10 ] -> Open WSL profile + launch claude (elevated)
  _dir := _GetTerminalDir()
  _distro := ""
  _wsl := _ParseWSLPath(_dir)
  If (IsObject(_wsl))
    _distro := _wsl.distro
  Else If (G_WSLDistro && RegExMatch(_dir, "^[A-Za-z]:\\"))
    _distro := G_WSLDistro
  If (_distro)
    UserRun("elevate", "wt", "-p", _distro, "-d " . _dir, "--", "bash", "-lic", """claude --dangerously-skip-permissions""")
  Else
    UserRun("elevate", "wt", "-d " . _dir)
Return

+F10:: ; [ Shift + F10 ] -> Open with admin rights
  _dir := _GetTerminalDir()
  UserRun("elevate", "wt", "-d " . _dir)
Return

^!+F10:: ; [ Ctrl + Alt + Shift + F10 ] -> Open as SYSTEM
  _dir := _GetTerminalDir()
  ; Resolve wt.exe to full path — SYSTEM context lacks user PATH entries
  _wtPath := FindInPath("wt.exe")
  If (!_wtPath) {
    MsgBox, 16, TI Elevation, wt.exe not found in PATH
    Return
  }
  ; Confirm before SYSTEM elevation — ti.exe needs admin via UserRun("elevate", ...)
  _tiCmd := "ti " . _wtPath . " -d " . _dir
  _displayCmd := StrReplace(_tiCmd, "&", "&&")
  MsgBox, 4, TI Elevation, % "Constructed command:`n`n" . _displayCmd . "`n`nClick Yes to run, No to cancel"
  IfMsgBox No
    Return
  UserRun("elevate", "ti", _wtPath, "-d " . _dir)
Return

; ⇒ Initialize terminal-anywhere config (called from auto-execute section)
_TerminalInit() {
  global G_WSLDistro, G_WSLAutoPath
  G_WSLDistro := "Ubuntu-24.04"
  G_WSLAutoPath := "C:\Dropbox\Projects"
}

; ⇒ Resolve working directory from active window context
_GetTerminalDir() {
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

; ⇒ Parse WSL UNC path into distro name
; Input:  \\wsl.localhost\Ubuntu-24.04\home\rod  or  \\wsl$\Ubuntu-24.04\home\rod
; Output: {distro: "Ubuntu-24.04"} or "" if not a WSL path
_ParseWSLPath(path) {
  If (!RegExMatch(path, "i)^\\\\wsl(?:\.localhost|\$)\\([^\\]+)", m))
    Return ""
  Return {distro: m1}
}
