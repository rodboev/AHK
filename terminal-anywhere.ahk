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
  ; Confirm before SYSTEM elevation — ti.exe needs admin via UserRun("elevate", ...)
  _tiCmd := "ti " . _wtPath . " -d " . _dir
  _displayCmd := StrReplace(_tiCmd, "&", "&&")
  MsgBox, 4, TI Elevation, % "Constructed command:`n`n" . _displayCmd . "`n`nClick Yes to run, No to cancel"
  IfMsgBox No
    Return
  UserRun("elevate", "ti", _wtPath, "-d " . _dir)
Return

; ⇒ Initialize terminal-anywhere config (called from auto-execute section)
TerminalInit() {
  global G_WSLDistro, G_WSLAutoPaths
  G_WSLDistro := "Ubuntu-24.04"
  G_WSLAutoPaths := ["C:\Users\Rod\Projects"] ; "C:\Users\Rod\Documents"
}

; ⇒ Open Windows Terminal with optional WSL profile, elevation, and Claude
OpenTerminal(opts := "") {
  ; OpenTerminal({wsl: "auto|force|off", elevate: bool, claude: bool})
  ;   wsl      "auto"  = WSL for UNC paths + paths under G_WSLAutoPaths (default)
  ;            "force" = WSL for UNC paths + any Windows drive letter
  ;            "off"   = plain Windows Terminal, no WSL
  ;   elevate  true    = run as Administrator (UAC prompt)
  ;   claude   true    = launch Claude CLI in WSL (needs distro)
  ;
  ; Missing keys default to: wsl="auto", elevate=false, claude=false

  global G_WSLDistro, G_WSLAutoPaths
  _dir := GetTerminalDir()
  _distro := ""
  _wslMode := opts.wsl ? opts.wsl : "auto"

  ; Resolve WSL distro name (if any)
  If (_wslMode != "off") {
    ; Check for WSL UNC path first (\\wsl.localhost\distro\... or \\wsl$\distro\...)
    _wsl := ParseWSLPath(_dir)
    If (IsObject(_wsl))
      _distro := _wsl.distro
    Else If (G_WSLDistro) {
      ; "force": any Windows drive letter → WSL profile
      If (_wslMode = "force" && RegExMatch(_dir, "^[A-Za-z]:\\"))
        _distro := G_WSLDistro
      ; "auto": path starts with any configured prefix → WSL profile
      Else If (_wslMode = "auto") {
        For _, _prefix in G_WSLAutoPaths {
          If (InStr(_dir, _prefix) = 1) {
            _distro := G_WSLDistro
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
  If (_distro)
    _args.Push("-p", _distro)
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

; ⇒ Parse WSL UNC path into distro name
; Input:  \\wsl.localhost\Ubuntu-24.04\home\rod  or  \\wsl$\Ubuntu-24.04\home\rod
; Output: {distro: "Ubuntu-24.04"} or "" if not a WSL path
ParseWSLPath(path) {
  If (!RegExMatch(path, "i)^\\\\wsl(?:\.localhost|\$)\\([^\\]+)", m))
    Return ""
  Return {distro: m1}
}
