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
#IfWinActive

#If WinActive("ahk_exe alacritty.exe") || WinActive("ahk_exe noctty.exe")
; ⇒ Herdr prefills the rename prompt with the current name and has no config to disable it.
$F2::
  global HerdrEscapeToHerdr
  HerdrEscapeToHerdr := WinActive("ahk_exe alacritty.exe") != 0
  SendInput, {F2}
  SendInput, ^u
Return
#If

#e::HerdrAnywhereOpenExplorer()

HerdrAnywhereSendEscape() {
  global HerdrEscapeToHerdr
  _hwnd := WinExist("A")
  _client := HerdrAnywhereGetClient(_hwnd)
  If (!WinActive("ahk_id " . _hwnd))
    Return
  If (HerdrEscapeToHerdr) {
    HerdrEscapeToHerdr := 0
    SendEvent, {Blind}{Esc}
    Return
  }
  If (!IsObject(_client) || _client.kind != "local") {
    HerdrAnywhereLog("escape-passthrough", "hwnd=" . WinExist("A"))
    SendEvent, {Blind}{Esc}
    Return
  }
  _pane := HerdrAnywhereGetFocusedPane(_client.session, _cwd)
  If (!WinActive("ahk_id " . _hwnd))
    Return
  If (!_pane) {
    SendEvent, {Blind}{Esc}
    Return
  }
  If (!WinActive("ahk_id " . _client.hwnd))
    Return
  _ok := false
  HerdrApiCall(_ok, _client.session, "pane.send_keys", "{""pane_id"":" . HerdrJsonString(_pane) . ",""keys"":[""esc""]}")
  HerdrAnywhereLog("escape", "hwnd=" . _client.hwnd . " session=" . _client.session . " pane=" . _pane . " ok=" . _ok)
  If (!_ok)
    SendEvent, {Blind}{Esc}
}

HerdrAnywhereLaunch(command := "", session := "") {
  If (session = "" && HerdrAnywhereIsActiveClient()) {
    HerdrAnywhereLaunchInClient(command)
    Return
  }
  HerdrAnywhereOpenWindow(HerdrAnywhereNormalizeDirectory(HerdrAnywhereGetContextDir()), command, session)
}

HerdrAnywhereOpenWindow(dir, command := "", session := "") {
  global Debug, HerdrTerminal
  _python := "C:\Apps\Python313\pythonw.exe"
  If (!FileExist(_python))
    _python := FindInPath("pythonw.exe")
  _helper := A_ScriptDir . "\herdr-new-window.py"
  If (!_python || !FileExist(_helper)) {
    MsgBox, 16, Herdr, The new workspace launcher requires pythonw.exe and herdr-new-window.py.
    Return false
  }
  HerdrAnywhereLog("open-window", "cwd=" . dir . " command=" . command . " session=" . session)
  ; The admin session's server only answers an elevated caller, so the helper has to match it.
  _args := [session = "" ? "gui" : "elevate", _python, _helper, "--terminal", HerdrTerminal, "--cwd", dir]
  If (command != "")
    _args.Push("--command"), _args.Push(command)
  If (session != "")
    _args.Push("--session"), _args.Push(session)
  If (Debug.Log["herdr-new-window"])
    _args.Push("--log"), _args.Push(Debug.Log.Path)
  Return UserRun(_args*)
}

HerdrAnywhereLaunchInClient(command := "", dir := "") {
  ; This path types into the pane, so two overlapping presses would interleave keystrokes.
  static _startedAt := 0
  If (_startedAt && A_TickCount - _startedAt < 3000) {
    HerdrAnywhereLog("launch-reentrant", "command=" . command)
    Return
  }
  _startedAt := A_TickCount
  HerdrAnywhereTypeInClient(command, dir)
  _startedAt := 0
}

HerdrAnywhereTypeInClient(command, dir) {
  _client := HerdrAnywhereGetClient(WinExist("A"))
  If (!IsObject(_client) || (dir != "" && _client.kind != "local"))
    Return
  If (!WinActive("ahk_id " . _client.hwnd))
    Return
  HerdrAnywhereLog("herdr-tab", "hwnd=" . _client.hwnd . " kind=" . _client.kind . " session=" . _client.session)
  ; Noctty and Alacritty only carry the keystroke; Herdr handles Ctrl+T as new_tab.
  SendInput, ^t
  If (command != "") {
    KeyWait, Ctrl
  }
  Sleep, 250
  If (!WinActive("ahk_id " . _client.hwnd))
    Return
  _command := ""
  If (dir != "")
    _command := "cd /d " . Chr(34) . dir . Chr(34)
  If (command != "")
    _command .= (_command != "" ? " && " : "") . command
  If (_command != "") {
    SendInput, % "{Raw}" . _command
    SendInput, {Enter}
  }
}

HerdrAnywhereIsActiveClient() {
  WinGet, _activeHwnd, ID, A
  Return HerdrAnywhereIsClientWindow(_activeHwnd)
}

HerdrAnywhereIsClientWindow(hwnd) {
  Return IsObject(HerdrAnywhereGetClient(hwnd))
}

HerdrAnywhereGetClient(hwnd) {
  WinGet, _exe, ProcessName, ahk_id %hwnd%
  If (_exe != "alacritty.exe" && _exe != "noctty.exe")
    Return false
  WinGet, _terminalPid, PID, ahk_id %hwnd%
  _client := false
  For _, _pid in GetChildProcesses(_terminalPid, "herdr.exe") {
    _connection := HerdrAnywhereParseConnection(GetProcessCommandLine(_pid))
    If (!IsObject(_connection))
      Return false
    If (IsObject(_client)) {
      If (_exe != "noctty.exe"
        || _connection.kind != _client.kind
        || _connection.session != _client.session)
        Return false
      Continue
    }
    _client := _connection
    _client.hwnd := hwnd
  }
  Return _client
}

HerdrAnywhereParseConnection(commandLine) {
  If (Trim(commandLine) = "")
    Return false
  _argv := DllCall("shell32\CommandLineToArgvW", "WStr", commandLine, "Int*", _argc, "Ptr")
  If (!_argv)
    Return false
  _args := []
  Try {
    Loop, %_argc%
      _args.Push(StrGet(NumGet(_argv+0, (A_Index - 1) * A_PtrSize, "Ptr"), "UTF-16"))
  } Finally {
    DllCall("LocalFree", "Ptr", _argv)
  }
  _client := {kind: "local", session: "", remote: ""}
  _seen := {}
  _i := 2
  While (_i <= _args.Length()) {
    _arg := _args[_i]
    If (_arg = "--handoff") {
      _i++
      Continue
    }
    If (_arg = "session" && _args[_i + 1] = "attach" && _i + 2 = _args.Length() && !_seen.HasKey("--session") && _args[_i + 2] != "") {
      _client.session := _args[_i + 2]
      Return _client
    }
    If (!RegExMatch(_arg, "^(--session|--remote|--remote-keybindings)(?:=(.*))?$", _option))
      Return false
    _name := _option1
    If (_seen.HasKey(_name))
      Return false
    _seen[_name] := true
    If (InStr(_arg, "="))
      _value := _option2
    Else {
      _i++
      _value := _args[_i]
    }
    If (_value = "" || SubStr(_value, 1, 1) = "-")
      Return false
    If (_name = "--session")
      _client.session := _value
    Else If (_name = "--remote") {
      _client.kind := "remote"
      _client.remote := _value
    } Else If (_value != "local" && _value != "server")
      Return false
    _i++
  }
  Return _client
}

HerdrAnywhereLog(event, details := "") {
  global Debug
  If (Debug.Log["herdr-anywhere"]) {
    _logFile := Debug.Log.Path
    FileAppend, % TS() . " | herdr-anywhere | " . event . " | " . details . "`n", %_logFile%
  }
}

HerdrAnywhereGetFocusedPane(session := "", ByRef cwd := "") {
  cwd := ""
  _ok := false
  _out := HerdrApiCall(_ok, session, "pane.list")
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

; ⇒ Herdr's API socket is newline-delimited JSON over a named pipe, so no cmd.exe spawn is needed.
;   Sets HerdrApiLastError to the Win32 code: 2 no server, 5 wrong token, 1460 timed out.
HerdrApiCall(ByRef ok, session, method, params := "{}") {
  global HerdrApiLastError
  static _seq := 0
  ok := false
  HerdrApiLastError := 0
  EnvGet, _appData, APPDATA
  _path := "\\.\pipe\" . _appData . "\herdr"
  If (session != "")
    _path .= "\sessions\" . session
  _path .= "\herdr.sock"
  _handle := DllCall("CreateFileW", "WStr", _path, "UInt", 0xC0000000, "UInt", 0, "Ptr", 0, "UInt", 3, "UInt", 0, "Ptr", 0, "Ptr")
  If (_handle = -1) {
    HerdrApiLastError := A_LastError
    Return ""
  }
  _seq += 1
  _request := "{""id"":""ahk-" . _seq . """,""method"":""" . method . """,""params"":" . params . "}`n"
  VarSetCapacity(_send, StrPut(_request, "UTF-8"))
  _sendLen := StrPut(_request, &_send, "UTF-8") - 1
  If (!DllCall("WriteFile", "Ptr", _handle, "Ptr", &_send, "UInt", _sendLen, "UInt*", _written, "Ptr", 0) || _written != _sendLen) {
    HerdrApiLastError := A_LastError
    DllCall("CloseHandle", "Ptr", _handle)
    Return ""
  }
  _cap := 262144
  VarSetCapacity(_acc, _cap)
  _len := 0
  _deadline := A_TickCount + 5000
  Loop {
    If (!DllCall("PeekNamedPipe", "Ptr", _handle, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt*", _avail, "Ptr", 0)) {
      HerdrApiLastError := A_LastError
      Break
    }
    If (!_avail) {
      If (A_TickCount > _deadline) {
        HerdrApiLastError := 1460
        HerdrAnywhereLog("api-timeout", "session=" . session . " method=" . method)
        Break
      }
      Sleep, 5
      Continue
    }
    If (_avail > _cap - _len)
      _avail := _cap - _len
    If (!_avail)
      Break
    If (!DllCall("ReadFile", "Ptr", _handle, "Ptr", &_acc + _len, "UInt", _avail, "UInt*", _read, "Ptr", 0) || !_read) {
      HerdrApiLastError := A_LastError
      Break
    }
    _done := false
    Loop, %_read%
      If (NumGet(_acc, _len + A_Index - 1, "UChar") = 10) {
        _done := true
        Break
      }
    _len += _read
    If (_done) {
      ok := true
      Break
    }
  }
  DllCall("CloseHandle", "Ptr", _handle)
  If (!ok)
    Return ""
  NumPut(0, _acc, _len, "UChar")
  Return StrGet(&_acc, "UTF-8")
}

HerdrJsonString(value) {
  value := StrReplace(value, "\", "\\")
  value := StrReplace(value, """", "\""")
  value := StrReplace(value, "`r", "\r")
  value := StrReplace(value, "`n", "\n")
  value := StrReplace(value, "`t", "\t")
  Return """" . value . """"
}

HerdrAnywhereGetContextDir() {
  WinGetClass, _class, A
  If (_class = "CabinetWClass") {
    _path := GetExplorerPath()
    If (_path)
      Return _path
  }
  If (_class = "File Pilot") {
    _path := GetFilePilotPath()
    If (_path)
      Return _path
  }
  If (_class = "CASCADIA_HOSTING_WINDOW_CLASS") {
    _path := GetTerminalDir()
    If (_path)
      Return _path
  }
  If (WinActive("ahk_exe alacritty.exe") || WinActive("ahk_exe noctty.exe")) {
    _client := HerdrAnywhereGetClient(WinExist("A"))
    If (!IsObject(_client) || _client.kind != "local")
      Return A_Desktop
    _pane := HerdrAnywhereGetFocusedPane(_client.session, _path)
    If (_path && InStr(FileExist(_path), "D"))
      Return _path
    Return A_Desktop
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
