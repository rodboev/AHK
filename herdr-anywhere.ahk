; ┏━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ HERDR FROM ANYWHERE ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━┛

#If !WinActive("ahk_exe WindowsTerminal.exe")
F10::HerdrAnywhereLaunch()
^F10::HerdrAnywhereLaunch("codex")
+F10::HerdrAnywhereLaunch("", "admin")
^+F10::HerdrAnywhereLaunch("claude")
#If

#IfWinActive ahk_exe alacritty.exe
$Esc::HerdrAnywhereSendEscape()
$^Tab::
  If (HerdrAnywhereIsActiveClient())
    HerdrAnywhereSendWorkspaceStep("down")
  Else
    SendInput, ^{Tab}
Return
$^+Tab::
  If (HerdrAnywhereIsActiveClient())
    HerdrAnywhereSendWorkspaceStep("up")
  Else
    SendInput, ^+{Tab}
Return
#IfWinActive

#e::HerdrAnywhereOpenExplorer()

HerdrAnywhereSendEscape() {
  _pane := HerdrAnywhereGetFocusedPane("", _cwd)
  If (!_pane) {
    SendEvent, {Blind}{Esc}
    Return
  }
  _exe := FindInPath("herdr.exe")
  If (!_exe) {
    SendEvent, {Blind}{Esc}
    Return
  }
  _command := HerdrAnywhereQuote(_exe) . " pane send-keys " . HerdrAnywhereQuote(_pane) . " esc"
  Run, %_command%,, Hide
}

HerdrAnywhereSendWorkspaceStep(direction) {
  If (direction = "up")
    SendInput, {Shift Up}{Ctrl Down}{Up}{Ctrl Up}{Shift Down}
  Else
    SendInput, {Ctrl Down}{Down}{Ctrl Up}
}

HerdrAnywhereLaunch(command := "", session := "") {
  _dir := HerdrAnywhereNormalizeDirectory(HerdrAnywhereGetContextDir())
  If (session = "") {
    If (HerdrAnywhereIsActiveClient()) {
      HerdrAnywhereLaunchInClient(command)
      Return
    }
    If (HerdrAnywhereActivateClient()) {
      HerdrAnywhereLaunchInClient(command, _dir)
      Return
    }
  }
  _hadServer := false
  _launched := false
  If (!HerdrAnywhereEnsureClient(_dir, session, _hadServer, _launched))
    Return
  If (_launched && !_hadServer) {
    _pane := HerdrAnywhereWaitFocusedPane(session, _paneCwd)
    If (!_pane)
      Return
    If (command != "")
      HerdrAnywhereRun(session, "pane", "run", _pane, command)
    Return
  }
  _out := HerdrAnywhereRun(session, "workspace", "create", "--cwd", _dir, "--focus")
  _workspace := ""
  _pane := ""
  If RegExMatch(_out, "s)""workspace_id""\s*:\s*""([^""]+)""", _workspaceMatch)
    _workspace := _workspaceMatch1
  If RegExMatch(_out, "s)""root_pane""\s*:\s*\{.*?""pane_id""\s*:\s*""([^""]+)""", _paneMatch)
    _pane := _paneMatch1
  If (_workspace)
    HerdrAnywhereRun(session, "workspace", "focus", _workspace)
  If (_pane && command != "")
    HerdrAnywhereRun(session, "pane", "run", _pane, command)
}

HerdrAnywhereLaunchInClient(command := "", dir := "") {
  SendInput, {Ctrl Down}n{Ctrl Up}
  Sleep, 250
  _command := ""
  If (dir != "")
    _command := "cd /d " . Chr(34) . dir . Chr(34)
  If (command != "")
    _command .= (_command != "" ? " && " : "") . command
  If (_command != "")
    SendInput, % "{Raw}" . _command . "{Enter}"
}

HerdrAnywhereActivateClient() {
  WinGet, _list, List, ahk_exe alacritty.exe
  If (!_list)
    Return false
  _target := 0
  Loop, %_list% {
    _candidate := _list%A_Index%
    If (HerdrAnywhereIsClientWindow(_candidate)) {
      _target := _candidate
      Break
    }
  }
  If (!_target)
    Return false
  WinActivate, ahk_id %_target%
  WinWaitActive, ahk_id %_target%,, 2
  Sleep, 100
  Return WinActive("ahk_id " . _target)
}

HerdrAnywhereIsActiveClient() {
  WinGet, _activeHwnd, ID, A
  Return HerdrAnywhereIsClientWindow(_activeHwnd)
}

HerdrAnywhereIsClientWindow(hwnd) {
  WinGet, _exe, ProcessName, ahk_id %hwnd%
  If (_exe != "alacritty.exe")
    Return false
  WinGet, _alacrittyPid, PID, ahk_id %hwnd%
  Try {
    _query := "SELECT ProcessId, ParentProcessId, Name, CommandLine FROM Win32_Process WHERE ParentProcessId=" . _alacrittyPid
    For _proc in ComObjGet("winmgmts:").ExecQuery(_query)
      If (_proc.Name = "herdr.exe")
        Return true
  } Catch _e {
    Return false
  }
  Return false
}

HerdrAnywhereEnsureClient(dir, session, ByRef hadServer, ByRef launched) {
  hadServer := HerdrAnywhereServerAvailable(session)
  launched := false
  If (session = "" && WinExist("ahk_exe alacritty.exe"))
    Return true
  _alacritty := FindInPath("alacritty.exe")
  If (!_alacritty)
    _alacritty := "C:\Apps\Alacritty\alacritty.exe"
  If (!FileExist(_alacritty)) {
    MsgBox, 16, Herdr, Alacritty was not found.
    Return false
  }
  _args := [_alacritty, "--working-directory", dir]
  If (session != "")
    _args.Push("--command"), _args.Push("herdr.exe"), _args.Push("--session"), _args.Push(session)
  If (session != "") {
    _elevatedArgs := ["elevate"]
    For _, _arg in _args
      _elevatedArgs.Push(_arg)
    If (!UserRun(_elevatedArgs*))
      Return false
  } Else If (!UserRun(_args*)) {
    Return false
  }
  launched := true
  WinWait, ahk_exe alacritty.exe,, 5
  Sleep, 500
  Return true
}

HerdrAnywhereServerAvailable(session := "") {
  _out := HerdrAnywhereRun(session, "pane", "list")
  Return InStr(_out, """type"":""pane_list""") || InStr(_out, """panes"":[")
}

HerdrAnywhereWaitFocusedPane(session, ByRef cwd) {
  cwd := ""
  Loop, 12 {
    _pane := HerdrAnywhereGetFocusedPane(session, cwd)
    If (_pane)
      Return _pane
    Sleep, 250
  }
  Return ""
}

HerdrAnywhereGetFocusedPane(session := "", ByRef cwd := "") {
  cwd := ""
  _out := HerdrAnywhereRun(session, "pane", "list")
  If RegExMatch(_out, "s)""focused""\s*:\s*true[^}]*?""pane_id""\s*:\s*""([^""]+)""", _m)
    _pane := _m1
  Else If RegExMatch(_out, "s)""pane_id""\s*:\s*""([^""]+)""[^}]*?""focused""\s*:\s*true", _m)
    _pane := _m1
  Else
    Return ""
  If RegExMatch(_out, "s)""foreground_cwd""\s*:\s*""([^""]*)""[^}]*?""focused""\s*:\s*true", _m)
    cwd := _m1
  Else If RegExMatch(_out, "s)""cwd""\s*:\s*""([^""]*)""[^}]*?""focused""\s*:\s*true", _m)
    cwd := _m1
  Else If RegExMatch(_out, "s)""focused""\s*:\s*true[^}]*?""foreground_cwd""\s*:\s*""([^""]*)""", _m)
    cwd := _m1
  Else If RegExMatch(_out, "s)""focused""\s*:\s*true[^}]*?""cwd""\s*:\s*""([^""]*)""", _m)
    cwd := _m1
  cwd := StrReplace(cwd, "\\", "\")
  Return _pane
}

HerdrAnywhereNormalizeDirectory(dir) {
  dir := RTrim(dir, "\")
  If (dir = "")
    Return A_Desktop
  If RegExMatch(dir, "i)^[A-Z]:$")
    Return dir . "\."
  Return dir
}

HerdrAnywhereRun(session, args*) {
  _exe := FindInPath("herdr.exe")
  If (!_exe)
    Return ""
  _outputPath := A_Temp . "\HerdrAnywhere_" . A_TickCount . ".out"
  _batchPath := A_Temp . "\HerdrAnywhere_" . A_TickCount . ".cmd"
  _line := "@echo off`r`n" . HerdrAnywhereQuote(_exe)
  If (session != "")
    _line .= " --session " . HerdrAnywhereQuote(session)
  For _, _arg in args
    _line .= " " . HerdrAnywhereQuote(_arg)
  _line .= " > " . HerdrAnywhereQuote(_outputPath) . " 2>&1`r`n"
  FileDelete, %_outputPath%
  FileDelete, %_batchPath%
  FileAppend, %_line%, %_batchPath%
  _run := ComSpec . " /d /c " . HerdrAnywhereQuote(_batchPath)
  RunWait, %_run%,, Hide
  _output := ""
  FileRead, _output, %_outputPath%
  FileDelete, %_outputPath%
  FileDelete, %_batchPath%
  Return _output
}

HerdrAnywhereQuote(value) {
  _quote := Chr(34)
  Return _quote . StrReplace(value, _quote, _quote . _quote) . _quote
}

HerdrAnywhereGetContextDir() {
  WinGetClass, _class, A
  If (_class = "CabinetWClass") {
    _path := GetExplorerPath()
    If (_path)
      Return _path
  }
  If (_class = "CASCADIA_HOSTING_WINDOW_CLASS") {
    _path := GetTerminalDir()
    If (_path)
      Return _path
  }
  If (WinActive("ahk_exe alacritty.exe")) {
    _pane := HerdrAnywhereGetFocusedPane("", _path)
    If (_path && InStr(FileExist(_path), "D"))
      Return _path
  }
  If (_class = "Progman" || _class = "WorkerW")
    Return A_Desktop
  _path := GetTitleBarPath()
  If (_path && InStr(FileExist(_path), "D"))
    Return _path
  Return A_Desktop
}

HerdrAnywhereOpenExplorer() {
  KeyWait, LWin
  _dir := HerdrAnywhereGetContextDir()
  If (IsFunc("_ActivateExplorerAt") && _dir != A_Desktop && _ActivateExplorerAt(_dir))
    Return
  If (_dir = A_Desktop)
    Run, explorer.exe
  Else
    UserRun("explorer.exe", _dir)
}
