; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ WINDOWS TERMINAL FROM ANYWHERE ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; [ F10 ]                       -> Open current path (auto-detect WSL)
; [ Alt + F10 ]                 -> Open current path (force WSL)
; [ Shift + F10 ]               -> Open current path as admin (auto-detect WSL)
; [ Alt + Shift + F10 ]         -> Open current path as admin (force WSL)
; [ Ctrl + F10 ]                -> Open claude in current path (force WSL)
; [ Ctrl + Shift + F10 ]        -> Open claude in current path as admin (force WSL)
; [ Ctrl + Alt + Shift + F10 ]  -> Open current path as SYSTEM

; #  Win            ^
; +  Shift          ! Alt
; !  Alt
; +  Shift
; +  Shift+Alt

F10::OpenTerminal()
!F10::OpenTerminal({wsl: "force"})
+F10::OpenTerminal({elevate: true})
!+F10::OpenTerminal({wsl: "force", elevate: true})
^F10::OpenTerminal({wsl: "force", claude: true})
^+F10::OpenTerminal({wsl: "force", elevate: true, claude: true})
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
  TA.WSLDistro := "Ubuntu-24.04"
  TA.WSLAutoPaths := ["C:\Users\Rod\Projects"] ; "C:\Users\Rod\Documents"
  TA.WTProfile := "" ; Profile name for non-WSL launches. Blank = first non-hidden profile from settings.json
  If (!TA.WTProfile)
    TA.WTProfile := GetWTFirstProfile()
}

; ⇒ Open Windows Terminal with optional WSL profile, elevation, and Claude
OpenTerminal(opts := "") {
  ; OpenTerminal({wsl: "auto|force|off", elevate: bool, claude: bool})
  ;   wsl      "auto"  = WSL for UNC paths + paths under TA.WSLAutoPaths (default)
  ;            "force" = WSL for UNC paths + any Windows drive letter
  ;            "off"   = plain Windows Terminal, no WSL
  ;   elevate  true    = run as Administrator (UAC prompt)
  ;   claude   true    = launch Claude CLI in WSL (needs distro)
  ;
  ; Missing keys default to: wsl="auto", elevate=false, claude=false

  global TA
  _dir := GetTerminalDir()
  _distro := ""
  _wslMode := opts.wsl ? opts.wsl : "auto"

  ; Resolve WSL distro name (if any)
  If (_wslMode != "off") {
    ; Check for WSL UNC path first (\\wsl.localhost\distro\... or \\wsl$\distro\...)
    _wsl := ParseWSLPath(_dir)
    If (IsObject(_wsl))
      _distro := _wsl.distro
    Else If (TA.WSLDistro) {
      ; "force": any Windows drive letter → WSL profile
      If (_wslMode = "force" && RegExMatch(_dir, "^[A-Za-z]:\\"))
        _distro := TA.WSLDistro
      ; "auto": path starts with any configured prefix → WSL profile
      Else If (_wslMode = "auto") {
        For _, _prefix in TA.WSLAutoPaths {
          If (InStr(_dir, _prefix) = 1) {
            _distro := TA.WSLDistro
            Break
          }
        }
      }
    }
  }

  ; --- Build UserRun arguments ---
  _args := []
  If (opts.elevate)
    _args.Push("elevate")
  _args.Push("wt")
  _profile := _distro ? _distro : TA.WTProfile
  If (_profile)
    _args.Push("-p", _profile)
  _args.Push("-d " . _dir)
  If (opts.claude && _distro)
    _args.Push("--", "bash", "-lic", """claude --dangerously-skip-permissions""")

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

; ⇒ Parse WSL UNC path into distro name
; Input:  \\wsl.localhost\Ubuntu-24.04\home\rod  or  \\wsl$\Ubuntu-24.04\home\rod
; Output: {distro: "Ubuntu-24.04"} or "" if not a WSL path
ParseWSLPath(path) {
  If (!RegExMatch(path, "i)^\\\\wsl(?:\.localhost|\$)\\([^\\]+)", m))
    Return ""
  Return {distro: m1}
}
