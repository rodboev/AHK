; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ WINDOWS TERMINAL FROM ANYWHERE ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; [ F10 ] -> Open Windows Terminal as user in current active window path
; [ Shift + F10] -> Open with admin rights
; [ Ctrl + Alt + Shift + F10] -> Open with SYSTEM rights (edit any reg key!)
F10::
  WinGetClass, ahk_class, A
  path := GetExplorerPath()

  If (ahk_class = "Progman")
    UserRun("wt", "-d " . A_Desktop)
  Else If (ahk_class = "CabinetWClass" && path != "")
    UserRun("wt", "-d " . path)
  Else {
    exe := GetExePath()
    UserRun("wt", "-d " . (exe.dir ? exe.dir : A_UserProfile))
  }
Return

+F10::
  WinGetClass, ahk_class, A
  path := GetExplorerPath()

  If (ahk_class = "Progman")
    UserRun("elevate", "wt", "-d " . A_Desktop)
  Else If (ahk_class = "CabinetWClass" && path != "")
    UserRun("elevate", "wt", "-d " . path)
  Else {
    exe := GetExePath()
    UserRun("elevate", "wt", "-d " . (exe.dir ? exe.dir : A_UserProfile))
  }
Return

^!+F10::
  WinGetClass, ahk_class, A
  path := GetExplorerPath()

  If (ahk_class = "Progman")
    _tiDir := A_Desktop
  Else If (ahk_class = "CabinetWClass" && path != "")
    _tiDir := path
  Else {
    exe := GetExePath()
    _tiDir := (exe.dir ? exe.dir : A_UserProfile)
  }
  ; Resolve wt.exe to full path — SYSTEM context lacks user PATH entries
  _wtPath := FindInPath("wt.exe")
  If (!_wtPath) {
    MsgBox, 16, TI Elevation, wt.exe not found in PATH
    Return
  }
  ; Confirm before SYSTEM elevation — ti.exe needs admin via UserRun("elevate", ...)
  _tiCmd := "ti " . _wtPath . " -d " . _tiDir
  _displayCmd := StrReplace(_tiCmd, "&", "&&")
  MsgBox, 4, TI Elevation, % "Constructed command:`n`n" . _displayCmd . "`n`nClick Yes to run, No to cancel"
  IfMsgBox No
    Return
  UserRun("elevate", "ti", _wtPath, "-d " . _tiDir)
Return
