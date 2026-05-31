; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ WINDOWS TERMINAL FROM ANYWHERE ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; [ F10 ]                       -> Open current path
; [ Ctrl + F10 ]                -> Run primary command
; [ Shift + F10 ]               -> Open as admin
; [ Ctrl + Shift + F10 ]        -> Run secondary command
; [ Ctrl + Alt + Shift + F10 ]  -> Open current path as SYSTEM
; [ Win + E ]                   -> Open Explorer at contextual path

#IfWinActive ahk_exe WindowsTerminal.exe
  ^F4::Send ^+w
#IfWinActive

#e::OpenExplorer()

F10::OpenTerminal({})
^F10::OpenTerminal({cmd: TA.PrimaryCmd})
+F10::OpenTerminal({elevate: true})
^+F10::OpenTerminal({cmd: TA.SecondaryCmd})
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
  TA.PrimaryCmd := FindInPath("claude")
  TA.SecondaryCmd := FindInPath("cl")
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

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Shell Automation — Programmatic access to Explorer windows/folders      ║
; ║  Docs: https://learn.microsoft.com/en-us/windows/win32/shell/shell-entry ║
; ╚══════════════════════════════════════════════════════════════════════════╝
; COM Interface (from ShObjIdl.h)
;   IID_IShellBrowser = {000214E2-0000-0000-C000-000000000046}
;
; Used in ComObjQuery(window, SID, IID) where SID=IID for direct interface access.
; Needed for tabbed Explorer: IOleWindow::GetWindow (vtable 3) returns tab HWND.

; ⇒ Get current path of active Explorer window (tab-aware for Win11 22H2+)
GetExplorerPath() {
  static shell := ComObjCreate("Shell.Application")
  WinGet, hwnd, ID, A
  ; ShellTabWindowClass1 = active tab (ClassNN 1 = highest z-order)
  activeTab := 0
  Try ControlGet, activeTab, Hwnd,, ShellTabWindowClass1, ahk_id %hwnd%
  For window in shell.Windows {
    If (window.hwnd != hwnd)
      Continue
    If (activeTab) {
      ; IOleWindow::GetWindow (vtable 3) returns each tab's HWND
      shellBrowser := ComObjQuery(window
        , "{000214E2-0000-0000-C000-000000000046}"
        , "{000214E2-0000-0000-C000-000000000046}")
      If (!shellBrowser)
        Continue
      thisTab := 0
      Try {
        DllCall(NumGet(NumGet(shellBrowser+0)+3*A_PtrSize)
          , "Ptr", shellBrowser, "UInt*", thisTab)
      } Finally {
        ObjRelease(shellBrowser)
      }
      If (thisTab != activeTab)
        Continue
    }
    Try {
      _path := window.Document.Folder.Self.Path
      Return RegExMatch(_path, "^[A-Za-z]:\\|^\\\\") && !InStr(_path, "::") ? _path : ""
    }
    Catch {
      Return ""  ; not a filesystem view
    }
  }
  Return ""
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

; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ EXPLORER FROM ANYWHERE (Win+E contextual) ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

OpenExplorer() {
  global Debug
  WinGetClass, _class, A

  ; Explorer — open desktop namespace root
  If (_class = "CabinetWClass") {
    ComObjCreate("Shell.Application").Explore(0)
    Return
  }

  ; Terminal — get CWD from shell child process
  If (_class = "CASCADIA_HOSTING_WINDOW_CLASS") {
    WinGet, _pid, PID, A
    _path := GetTerminalCwd(_pid)
  } Else {
    ; Other apps — try extracting a path from the title bar
    _path := GetTitleBarPath()
  }

  ; No path found — open desktop namespace root
  If (!_path) {
    ComObjCreate("Shell.Application").Explore(0)
    Return
  }

  ; Activate existing Explorer window at this path instead of opening a new one
  If (_ActivateExplorerAt(_path))
    Return

  Run, explorer "%_path%"
}

_ActivateExplorerAt(targetPath) {
  static shell := ComObjCreate("Shell.Application")
  _target := RTrim(targetPath, "\")
  For window in shell.Windows {
    Try _wPath := window.Document.Folder.Self.Path
    Catch
      Continue
    If (_wPath = "" || InStr(_wPath, "::"))
      Continue
    If (RTrim(_wPath, "\") = _target) {
      _hwnd := window.hwnd
      WinActivate, ahk_id %_hwnd%
      If (IsFunc("WS_MoveToMonitor")) {
        _winMon := GetMonitor("ahk_id " . _hwnd)
        _curMon := GetCursorMonitor()
        If (_winMon != _curMon)
          WS_MoveToMonitor(_hwnd, _winMon, _curMon)
      }
      Return true
    }
  }
  Return false
}
