; Global AutoHotKey keys
; #   Windows key
; ^   Ctrl 
; !   Alt
; +   Shift
; +!  Shift+Alt

#Requires AutoHotkey v1.1.14+
#SingleInstance Force
#NoEnv
#Persistent
#UseHook
#MaxHotkeysPerInterval 300
#InstallKeybdHook
#InstallMouseHook

SendMode, Input
SetWorkingDir, %A_ScriptDir%
SetTitleMatchMode, 2

; Debug flags
DebugTooltips := 0
DebugLogEvents := 0
DebugLogPath := A_Temp "\AHK_Debug.log"

; Disable hotkeys inside remote sessions (RDP, Hyper-V, VMWare)
#If IsRemoteSession()
  If !IsRemoteSession() {
    OnExit("MB_Cleanup")
    WS_Init() ; Init window spawning
    TerminalInit()
    ; Clear debug log on reload
    If (DebugLogEvents)
      FileDelete, %DebugLogPath%
  }
  Return
#If

; --------------------------------------------------------------------------
; END OF AUTO-EXECUTE
; Startup code below hotkey declarations is ignored, including within
; #Include files
; --------------------------------------------------------------------------

; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === BINDINGS / REMAPS === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; ⇒ AutoHotkey/global
+!r::Reload ; [ ShIft+Alt+R ] -> Reload script
+!p::       ; [ ShIft+Alt+P ] -> Toggle pause script+suspend hotkeys
  Suspend
  Pause,,1
Return
+!e::Edit ; UserRun("vsc", A_ScriptFullPath) ; [ Shift+Alt+E ] -> Edit script in VS Code
#IfWinActive .ahk
  ~^s::Reload ; [ Ctrl+S ] -> Reload script on save (in any editor)
#IfWinActive

; ⇒ Sublime Text
#IfWinActive ahk_exe sublime_text.exe
  ^Tab::Send {Ctrl Down}{PgDn}{Ctrl Up} ; [ Ctrl+Tab ] -> Next tab
  +^Tab::Send {Ctrl Down}{PgUp}{Ctrl Up} ; [ ShIft+Ctrl+Tab ] -> Previous tab
  ^w::Send {Alt Down}f{AltUp}{Left}{Alt Down}v{AltUp}w ; [ Ctrl+W ] -> Toggle word wrap
  ^;::
  #;::
  !;::
    Send ^/ ; [ Any+; ] -> Toggle comment
  Return
  +!d::Send {Alt Down}f{AltUp}e{Ctrl Down} ; [ Ctrl+Alt+D] -> Duplicate line
#IfWinActive

; ⇒ VSCode + forks
#If (WinActive("ahk_exe code.exe") OR WinActive("ahk_exe vscodium.exe") OR WinActive("ahk_exe cursor.exe"))
  ^w::Send {Alt Down}z{AltUp} ; [ Ctrl+W ] -> Toggle word wrap
  ^Tab::Send {Ctrl Down}{PgDn}{Ctrl Up} ; [ Ctrl+Tab ] -> Next tab
  +^Tab::Send {Ctrl Down}{PgUp}{Ctrl Up} ; [ ShIft+Ctrl+Tab ] -> Previous tab
#If

; ⇒ Other global bindings
+!-::Send {U+2014} ; [ ShIft+Alt+Minus ] -> Em-dash
+!0::Send {U+2022} ; [ ShIft+Alt+0] -> Bullet
~RWin::Send {AppsKey} ; [RWin] -> Apps/context menu
~#t::Run explorer shell:::{3080F90E-D7AD-11D9-BD98-0000947B0257} ; Win+T -> Task View

; ⇒ Windows Explorer
^+!x:: ; -> [ Shift +Alt +X ] -> Restart Explorer
  If (!FindInPath("rexplorer_x64.exe"))
    UserRun("cmd", "/c", "taskkill /f /im explorer.exe && start explorer.exe")
  Else If GetKeyState("Ctrl") ; -> [ Ctrl+Shift+Alt+X ] -> Restart Explorer
    UserRun("rexplorer_x64.exe")
  Else
    UserRun("rexplorer_x64.exe", "/f")
Return

#IfWinActive, ahk_class CabinetWClass
  !d::SendInput {Alt Up}{F4} ; [ Alt+D ] -> Focus address bar
  Backspace:: ; [ Backspace ] -> Go up a folder instead of backwards in history
    ControlGet renamestatus,Visible,,Edit1,A
    ControlGetFocus focused, A
    If (renamestatus != 1 and (focused = "DirectUIHWND3" or focused = "SysTreeView321"))
      SendInput {Alt Down}{Up}{Alt Up}
    Else
      Send {Backspace}
  Return
#IfWinActive

#IfWinActive, Open
  !d::Send {Alt Down}n{Alt Up} ; [ Alt+D ] -> Focus filename field in Open dialog
#IfWinActive

#If WinActive("ahk_class CabinetWClass") || WinActive("ahk_class #32770")
  ^e:: ; [ Ctrl+E ] -> Edit selected file in Notepad
    _selected := _GetSelectedFile()
    If (_selected = "")
      Return
    ; .lnk shortcuts: fix disabled target field, show Properties
    If (SubStr(_selected, -3) = ".lnk") {
      _FixAdvertisedShortcut(_selected)
      _ShowProperties(_selected)
      Return
    }
    ; Check write access and prompt if needed
    If (!_HasWriteAccess(_selected)) {
      MsgBox, 0x31, Edit Protected File, Grant write access to edit this file?`n`n%_selected%
      IfMsgBox Cancel
        Return
      _GrantWriteAccess(_selected)
      SplitPath, _selected, _fileName
      ToolTip, ACL granted: %_fileName%
      SetTimer, RemoveToolTip, -2000
    }
    UserRun("notepad", _selected)
  Return
  ^+e:: ; [ Ctrl+Shift+E ] -> Force edit in Notepad (grant access without prompt)
    _selected := _GetSelectedFile()
    If (_selected = "")
      Return
    If (!_HasWriteAccess(_selected)) {
      _GrantWriteAccess(_selected)
      SplitPath, _selected, _fileName
      ToolTip, ACL granted: %_fileName%
      SetTimer, RemoveToolTip, -2000
    }
    UserRun("notepad", _selected)
  Return
  ^o:: ; [ Ctrl+O ] -> Toggle INTERACTIVE full control on selected file
    _selected := _GetSelectedFile()
    If (_selected = "")
      Return
    SplitPath, _selected, _fileName
    _fp := _selected
    If (_HasWriteAccess(_selected)) {
      RunWait, %ComSpec% /c icacls "%_fp%" /remove INTERACTIVE,, Hide
      ToolTip, ACL revoked: %_fileName%
    } Else {
      RunWait, %ComSpec% /c icacls "%_fp%" /grant INTERACTIVE:F,, Hide
      ToolTip, ACL granted: %_fileName%
    }
    SetTimer, RemoveToolTip, -2000
  Return
#If

; ⇒ Media / hardware
+!l:: ; [ Shift+Alt+L ] -> Turn off monitor
  Sleep 200
  SendMessage, 0x112, 0xF170, 2,, Program Manager  ; WM_SYSCOMMAND, SC_MONITORPOWER, POWEROFF
Return

; Global Volume controls on mouse side buttons
$XButton1::
  While GetKeyState("XButton1","p"){
    Send {Volume_Down}
    Sleep 100
  }
Return
$XButton2::
  While GetKeyState("XButton2","p"){
    Send {Volume_Up}
    Sleep 100
  }
Return

#IfWinActive ahk_exe JPEGView.exe
  Enter::
    WinGet, active_id, ID, A
    Send w
    WinClose, ahk_id %active_id%
  Return
  $MButton::SendInput {F11}
#IfWinActive
#IfWinActive ahk_class QWidget
  *MButton::Send n ; VLC: next file on middle click
#IfWinActive

; Alt+Shift+S = Run or activate Everything
~+!s::
  DetectHiddenWindows, On
  If (!WinExist("ahk_exe Everything.exe")) {
    UserRun("\Apps\Everything\Everything.exe") ; was "Program Files\Everything 1.5a"
    WinWait, ahk_exe Everything.exe
    WinActivate
  }
Return

#IfWinActive ahk_exe Everything.exe
!F4::
  If WinExist("ahk_class EVERYTHING_DROPDOWNLIST")
    WinClose
  WinHide
Return
#IfWinActive

; MPC: Wheel → accelerated arrow keys (track skip), Alt+Wheel → volume (normal wheel)
#If MouseIsOver("ahk_class MediaPlayerClassicW")
  WheelUp::
  WheelDown::
    MouseGetPos,,, _hwnd
    v := GetScrollAccel(250)
    key := (A_ThisHotkey = "WheelUp") ? "Left" : "Right"
    ControlSend,, {%key% %v%}, ahk_id %_hwnd%
  Return
  +WheelUp::
  +WheelDown::
    MouseGetPos,,, _hwnd
    key := (A_ThisHotkey = "+WheelUp") ? "Left" : "Right"
    ControlSend,, {%key% 10}, ahk_id %_hwnd%
  Return
  !WheelUp::
  !WheelDown::
    MouseGetPos,,, _hwnd
    wheel := (A_ThisHotkey = "!WheelUp") ? "WheelUp" : "WheelDown"
    ControlSend,, {%wheel%}, ahk_id %_hwnd%
  Return
#If

; Accelerated scrolling
; MouseIsOver("ahk_exe sublime_text.exe") || MouseIsOver("ahk_exe WindowsTerminal.exe") || MouseIsOver("ahk_exe Merge.exe")
  WheelUp::
  WheelDown::
    MouseGetPos,,, _hwnd
    WinGet, _exe, ProcessName, ahk_id %_hwnd%
    WinGetClass, _class, ahk_id %_hwnd%
    divisors := [{ahk_class: "Chrome_WidgetWin_1", divisor: 0}
               , {ahk_class: "MediaPlayerClassicW", divisor: 500}
               , {ahk_exe: "Code.exe", divisor: 100}
               , {ahk_exe: "Merge.exe", divisor: 250}]
    divisor := 100 ; default
    for _, entry in divisors
      if (entry.ahk_class && entry.ahk_class == _class)
        divisor := entry.divisor
    for _, entry in divisors
      if (entry.ahk_exe && entry.ahk_exe == _exe)
        divisor := entry.divisor
    v := GetScrollAccel(divisor)
    MouseClick, %A_ThisHotkey%, , , %v%
  Return
  +WheelUp::Send {Click WheelUp 10}
  +WheelDown::Send {Click WheelDown 10}
  !WheelUp::Send {WheelLeft}
  !WheelDown::Send {WheelRight}
  !+WheelUp::Send {WheelLeft 10}
  !+WheelDown::Send {WheelRight 10}
; #If


; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === PROCESS MANAGEMENT / PRIVILEGE ESCALATION === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; [ Ctrl + Shift + ` ] -> Open System Informer as SYSTEM with TI privileges
^+`::UserRun("elevate", "ti", "c:\Program Files\SystemInformer\SystemInformer.exe")

; [ Win + Shift + E ] -> Alternate Explorer app in case of issues after Windows updates
#+e::
  WinGetClass, ahk_class, A
  path := GetExplorerPath()
  If (ahk_class = "Progman")
    path := A_Desktop
  Else If (ahk_class != "CabinetWClass" || path = "")
    path := A_MyDocuments

  ; Activate existing e++ window for this path, or open new
  pid := ProcessExistsByCommandLine("files-stable.exe"" " . path)
  If (pid) {
    WinActivate, ahk_pid %pid%
  } Else {
    UserRun("files-stable", path)
  }
Return

; Win + C: Copy command line of active window to clipboard
#c::
  cmdLine := GetActiveWindowCommandLine()
  explorerPath := GetExplorerPath()
  If (cmdLine && cmdLine != "") {
    Clipboard := ""
    Clipboard := cmdLine
    ClipWait, 1
    If (ErrorLevel) {
      ToolTip, Failed to copy command line to clipboard
    } Else {
      ToolTip, >> %cmdLine%`nPath: %explorerPath%
    }
    SetTimer, RemoveToolTip, -3000
  } Else {
    ToolTip, Could not get command line`nPath: %explorerPath%
    SetTimer, RemoveToolTip, -2000
  }
Return

; Ctrl + Shift + Plus: Relaunch active window with TrustedInstaller (NT AUTHORITY/SYSTEM) privileges
^+=::
  WinGet, activePid, PID, A
  exe := GetExePath()
  cmdLine := GetActiveWindowCommandLine(activePid)

  If (cmdLine && cmdLine != ".") {
    ; Resolve exe to full path — SYSTEM context (ti.exe) lacks user PATH entries
    If (exe.path)
      cmdLine := RegExReplace(cmdLine, "^(""[^""]*""|\S+)", """" . exe.path . """")
    fullCmd := "ti.exe " . cmdLine
    MsgBox, 4, Command to run (PID %activePid%), %fullCmd%`n`nClick Yes to run, No to cancel
    IfMsgBox Yes
    {
      ; Store the original path for comparison
      originalPath := exe.path

      ; Run the elevated command
      Run, %fullCmd%

      ; Wait for new process to appear (up to 250ms)
      startTime := A_TickCount, newProcessFound := false
      While (!newProcessFound && A_TickCount - startTime <= 250) {
        For process in ComObjGet("winmgmts:").ExecQuery("Select ProcessId, ExecutablePath from Win32_Process")
          If (process.ExecutablePath = originalPath && process.ProcessId != activePid && newProcessFound := true)
            Break
        Sleep, 50
      }

      ; If no new process appeared, close the original app and try again
      If (!newProcessFound) {
        WinClose, ahk_pid %activePid%
        startCloseTime := A_TickCount
        While (WinExist("ahk_pid " . activePid) && A_TickCount - startCloseTime <= 500)
          Sleep, 50
        If (WinExist("ahk_pid " . activePid))
          Process, Close, %activePid%
        Run, %fullCmd%
      }
    }
  }
Return

!+t::UserRun("taskschd.msc", "/s")

; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === HELPER FUNCTIONS === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; ⇒ Check if inside a remote desktop session (RDP, Hyper-V, VMWare)
IsRemoteSession() {
  Return WinActive("ahk_class TscShellContainerClass") or WinActive("ahk_exe vmconnect.exe") or WinActive("ahk_exe vmware.exe")
}

; ⇒ Check If array contains a value (allow partial match)
HasVal(arr, val) {
    For i, v in arr
        If (InStr(val, v))
            Return true
    Return false
}

; ⇒ Check if mouse cursor is over a window (by title, ahk_exe, ahk_class, etc.)
; Reference: https://www.autohotkey.com/docs/v1/misc/WinTitle.htm#ahk_
MouseIsOver(winTitle) {
  MouseGetPos,,, hwnd
  Return WinExist(winTitle " ahk_id " hwnd)
}

; ⇒ Calculate scroll acceleration
; Based on https://autohotkey.com/board/topic/48426-accelerated-scrolling-script/?p=333222
; Higher divisor = steeper curve (75 gentle, 250 steep); 0 = disabled
GetScrollAccel(divisor := 100) {
  If (divisor = 0)
    Return 1
  global DebugTooltips, DebugLogEvents, DebugLogPath
  static lastV := 1, lastDirection := "", directionCount := 0
  static lastTickUp := 0, lastTickDn := 0
  timeout := 400
  limit := 7

  now := A_TickCount
  isUp := (A_ThisHotkey = "WheelUp") || (A_ThisHotkey = "+WheelUp")

  ; Debounce direction changes — require 2+ consecutive events to confirm new direction
  If (A_ThisHotkey = lastDirection) {
    directionCount++
  } Else {
    directionCount := 1
  }
  lastDirection := A_ThisHotkey
  directionConfirmed := (directionCount >= 2)

  ; Per-direction timing — spurious opposite events don't break the timing chain
  lastTick := isUp ? lastTickUp : lastTickDn
  t := (lastTick > 0) ? (now - lastTick) : 999

  ; Filter spurious t=0/1ms events (duplicates or event coalescing)
  If (t <= 1) {
    If (DebugLogEvents) {
      FormatTime, _ts,, HH:mm:ss
      FileAppend, %_ts% | ScrollAccel | SKIP t=%t%ms (using lastV=%lastV%)`n, %DebugLogPath%
    }
    Return lastV
  }

  ; Update this direction's tick
  If (isUp) {
    lastTickUp := now
  } Else {
    lastTickDn := now
  }

  If (t > timeout) {
    v := 1
    reason := "timeout"
  } Else If (!directionConfirmed) {
    v := lastV
    reason := "debounce"
  } Else {
    ; UP gets 1.35x boost to compensate for hardware encoder asymmetry
    effectiveDivisor := isUp ? (divisor * 1.35) : divisor
    vRaw := (t < 80) ? (effectiveDivisor / t) : 1
    v := (vRaw > 1) ? ((vRaw > limit) ? limit : Floor(vRaw)) : 1
    reason := (t >= 80) ? "t>=80" : "accel"
  }
  lastV := v

  If (DebugTooltips) {
    MouseGetPos, _mx, _my, _hwnd
    WinGet, _exe, ProcessName, ahk_id %_hwnd%
    WinGetClass, _class, ahk_id %_hwnd%
    _tx := _mx + 50
    _ty := _my + 30
    ToolTip, ScrollAccel: v=%v% t=%t%ms div=%divisor% %reason%`n%_exe% [%_class%], %_tx%, %_ty%
    SetTimer, ScrollAccelTooltipOff, -800
  }
  If (DebugLogEvents) {
    dir := isUp ? "UP" : "DN"
    FormatTime, _ts,, HH:mm:ss
    FileAppend, %_ts% | ScrollAccel | %dir% | v=%v% t=%t%ms div=%divisor% cnt=%directionCount% %reason%`n, %DebugLogPath%
  }
  Return v

  ScrollAccelTooltipOff:
    ToolTip
  Return
}

; ⇒ Search for executable in PATH
FindInPath(exe) {
  ; Check If it's already a full path that exists
  If FileExist(exe)
    Return exe

  ; Search PATH directories
  EnvGet, pathVar, PATH
  Loop, Parse, pathVar, `;
  {
    If (A_LoopField = "")
        continue
    fullPath := RTrim(A_LoopField, "\") "\" exe
    If FileExist(fullPath)
        Return fullPath
  }
  Return ""
}

; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  Shell Automation — Programmatic access to Explorer windows/folders      ║
; ║  Used by: Terminal hotkeys (F10) to get current Explorer directory       ║
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

; ⇒ Get exe path and/or directory for a window
; Example: info := GetExePath() or info := GetExePath("ahk_id " hwnd)
; Returns: { path: "C:\...\app.exe", dir: "C:\..." }
GetExePath(winTitle := "A") {
  WinGet, exePath, ProcessPath, %winTitle%
  SplitPath, exePath,, exeDir
  Return {path: exePath, dir: exeDir}
}

; ⇒ Get which monitor a window is on (1-based)
GetMonitor(winTitle := "A") {
  WinGetPos, x, y, w, h, %winTitle%
  centerX := x + w // 2, centerY := y + h // 2
  SysGet, monCount, MonitorCount
  Loop, %monCount% {
    SysGet, mon, Monitor, %A_Index%
    If (centerX >= monLeft && centerX <= monRight && centerY >= monTop && centerY <= monBottom)
      Return A_Index
  }
  Return 1
}

; Get which monitor the cursor is on (1-based)
GetCursorMonitor() {
  CoordMode, Mouse, Screen
  MouseGetPos, mx, my
  SysGet, monCount, MonitorCount
  Loop, %monCount% {
    SysGet, mon, Monitor, %A_Index%
    If (mx >= monLeft && mx <= monRight && my >= monTop && my <= monBottom)
      Return A_Index
  }
  Return 1
}

G_UIACleanup() {
  If (G_UIA) {
    ObjRelease(G_UIA)
    G_UIA := 0
  }
}

; ⇒ Get the UIA content process PID for a window (resolves host vs content for UWP/Electron)
; Returns content PID if different from window PID, otherwise returns window PID
GetUIAProcessId(hwnd) {
  WinGet, _winPid, PID, ahk_id %hwnd%
  If (!_winPid)
    Return 0
  global G_UIA
  If (!G_UIA)
    Return _winPid ? _winPid : 0
  Try {
    _el := 0
    ; IUIAutomation::ElementFromHandle (vtable 6)
    DllCall(NumGet(NumGet(G_UIA+0) + 6*A_PtrSize), "Ptr", G_UIA, "Ptr", hwnd, "Ptr*", _el)
    If (!_el)
      Return _winPid
    Try {
      VarSetCapacity(_var, 24, 0)
      DllCall("OleAut32\VariantInit", "Ptr", &_var)
      ; IUIAutomationElement::GetCurrentPropertyValue (vtable 10)
      DllCall(NumGet(NumGet(_el+0) + 10*A_PtrSize), "Ptr", _el, "Int", 30002, "Ptr", &_var)
      _vt := NumGet(_var, 0, "UShort")
      If (_vt = 0)  ; VT_EMPTY — property not supported
        _uiaPid := 0
      Else
        _uiaPid := (_vt = 3) ? NumGet(_var, 8, "Int") : 0
      DllCall("OleAut32\VariantClear", "Ptr", &_var)
    } Finally {
      ObjRelease(_el)
    }
    Return _uiaPid ? _uiaPid : _winPid
  }
  Return _winPid
}

; ⇒ Get CmdLine for a window (by PID, or active window if omitted)
GetActiveWindowCommandLine(pid := "") {
  If (pid = "")
    WinGet, pid, PID, A

  If (pid) {
    ; Get command line using WMI
    cmdLine := ""
    For process in ComObjGet("winmgmts:").ExecQuery("Select CommandLine from Win32_Process where ProcessId=" . pid)
      cmdLine := process.CommandLine

    If (cmdLine)
      Return cmdLine
    exe := GetExePath()
    If (exe.path)
      Return exe.path
  }
  Return "."
}

; Check if a process with specific command line exists
ProcessExistsByCommandLine(cmdLine) {
  For process in ComObjGet("winmgmts:").ExecQuery("Select ProcessId, CommandLine from Win32_Process")
    If (InStr(process.CommandLine, cmdLine))
      Return process.ProcessId
  Return 0
}

; ⇒ Check if non-elevated user has write access to a file
; Elevated: creates restricted token (Administrators disabled) to simulate non-elevated check.
; Non-elevated: uses process token directly.
_HasWriteAccess(filePath) {
  _accessOK := false
  _hToken := 0, _hCheckToken := 0, _hImpToken := 0, _pSD := 0

  Try {
    If !DllCall("advapi32\OpenProcessToken"
        , "Ptr", DllCall("GetCurrentProcess", "Ptr")
        , "UInt", 0x000A    ; TOKEN_QUERY | TOKEN_DUPLICATE
        , "Ptr*", _hToken)
      Return false

    ; Check elevation status via TokenElevation (info class 20)
    VarSetCapacity(_elevBuf, 4, 0)
    DllCall("advapi32\GetTokenInformation"
        , "Ptr", _hToken, "Int", 20  ; TokenElevation
        , "Ptr", &_elevBuf, "UInt", 4, "UInt*", 0)
    _isElevated := NumGet(_elevBuf, 0, "UInt")

    If (_isElevated) {
      ; Create restricted token: disable BUILTIN\Administrators SID
      VarSetCapacity(_adminSid, 68, 0)
      _sidSize := 68
      DllCall("advapi32\CreateWellKnownSid"
          , "Int", 26  ; WinBuiltinAdministratorsSid
          , "Ptr", 0, "Ptr", &_adminSid, "UInt*", _sidSize)
      VarSetCapacity(_disableSids, A_PtrSize + 4, 0)
      NumPut(&_adminSid, _disableSids, 0, "Ptr")
      NumPut(0, _disableSids, A_PtrSize, "UInt")
      If !DllCall("advapi32\CreateRestrictedToken"
          , "Ptr", _hToken
          , "UInt", 0          ; flags
          , "UInt", 1          ; DisableSidCount
          , "Ptr", &_disableSids
          , "UInt", 0, "Ptr", 0  ; DeletePrivilegeCount
          , "UInt", 0, "Ptr", 0  ; RestrictedSidCount
          , "Ptr*", _hCheckToken)
        Return false
    } Else {
      _hCheckToken := _hToken
      _hToken := 0  ; prevent double-close in Finally
    }

    ; Duplicate as SecurityImpersonation token (required by AccessCheck)
    If !DllCall("advapi32\DuplicateToken"
        , "Ptr", _hCheckToken, "Int", 2, "Ptr*", _hImpToken)
      Return false

    ; Get file security descriptor (owner + group + DACL)
    If DllCall("advapi32\GetNamedSecurityInfoW"
        , "WStr", filePath, "Int", 1, "UInt", 0x7  ; SE_FILE_OBJECT, OWNER|GROUP|DACL
        , "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0
        , "Ptr*", _pSD)
      Return false

    ; GENERIC_MAPPING for file objects
    VarSetCapacity(_gm, 16, 0)
    NumPut(0x00120089, _gm, 0, "UInt")   ; FILE_GENERIC_READ
    NumPut(0x00120116, _gm, 4, "UInt")   ; FILE_GENERIC_WRITE
    NumPut(0x001200A0, _gm, 8, "UInt")   ; FILE_GENERIC_EXECUTE
    NumPut(0x001F01FF, _gm, 12, "UInt")  ; FILE_ALL_ACCESS

    _desiredAccess := 0x40000000          ; GENERIC_WRITE
    DllCall("advapi32\MapGenericMask", "UInt*", _desiredAccess, "Ptr", &_gm)

    VarSetCapacity(_privSet, 64, 0)
    _privSetLen := 64, _grantedAccess := 0
    DllCall("advapi32\AccessCheck"
        , "Ptr", _pSD, "Ptr", _hImpToken
        , "UInt", _desiredAccess, "Ptr", &_gm
        , "Ptr", &_privSet, "UInt*", _privSetLen
        , "UInt*", _grantedAccess, "Int*", _accessOK)
    _accessOK := _accessOK + 0  ; force numeric
  } Finally {
    If (_hToken)
      DllCall("CloseHandle", "Ptr", _hToken)
    If (_hCheckToken)
      DllCall("CloseHandle", "Ptr", _hCheckToken)
    If (_hImpToken)
      DllCall("CloseHandle", "Ptr", _hImpToken)
    If (_pSD)
      DllCall("kernel32\LocalFree", "Ptr", _pSD)
  }
  Return _accessOK
}

; ⇒ Grant full control to current user via icacls (preserves existing ownership)
_GrantWriteAccess(filePath) {
  _fp := filePath
  RunWait, %ComSpec% /c icacls "%_fp%" /grant "%A_UserName%":F,, Hide
}

; ⇒ Get selected file path in Explorer or file dialog (excludes directories)
_GetSelectedFile() {
  selected := ""
  If WinActive("ahk_class #32770") {
    ControlGetText, selected, Edit1, A
  } Else {
    For window in ComObjCreate("Shell.Application").Windows {
      If (window.hwnd == WinActive("A")) {
        Try selected := window.Document.SelectedItems.Item(0).Path
        Break
      }
    }
  }
  If (selected = "")
    Return ""
  FileGetAttrib, attrs, %selected%
  If (ErrorLevel || InStr(attrs, "D"))
    Return ""
  Return selected
}

; ⇒ Open the Properties dialog for a file via Shell.Application
_ShowProperties(filePath) {
  SplitPath, filePath, fileName, dirPath
  objFolder := ComObjCreate("Shell.Application").NameSpace(dirPath)
  If !objFolder
    Return
  objItem := objFolder.ParseName(fileName)
  If objItem
    objItem.InvokeVerb("properties")
}

; ⇒ Fix advertised/MSI shortcuts so the Target field is editable in Properties
; Advertised shortcuts use a Darwin descriptor instead of a direct path,
; which causes Windows to disable the Target field. Resolving and rewriting
; the shortcut converts it to a regular shortcut with an editable target.
_FixAdvertisedShortcut(lnkPath) {
  ; Try WScript.Shell first — resolves most advertised shortcuts
  Try {
    sc := ComObjCreate("WScript.Shell").CreateShortcut(lnkPath)
    target := sc.TargetPath
    If (target != "") {
      sc.Save()  ; Rewrites with resolved path, stripping Darwin descriptor
      Return true
    }
  }

  ; Fall back to MSI API for unresolvable shortcuts
  VarSetCapacity(prodCode, 78, 0)   ; GUID string: 39 chars * 2 bytes
  VarSetCapacity(featId, 512, 0)
  VarSetCapacity(compCode, 78, 0)
  If DllCall("msi\MsiGetShortcutTargetW"
      , "WStr", lnkPath
      , "Ptr", &prodCode, "Ptr", &featId, "Ptr", &compCode)
    Return false

  ; Resolve component to installed file path
  _prod := StrGet(&prodCode, "UTF-16")
  _comp := StrGet(&compCode, "UTF-16")
  VarSetCapacity(pathBuf, 520, 0)
  pathLen := 260
  state := DllCall("msi\MsiGetComponentPathW"
      , "WStr", _prod, "WStr", _comp
      , "Ptr", &pathBuf, "UInt*", pathLen)
  If (state != 3)  ; INSTALLSTATE_LOCAL
    Return false

  resolvedPath := StrGet(&pathBuf, "UTF-16")
  If (resolvedPath = "" || !FileExist(resolvedPath))
    Return false

  ; Rewrite shortcut with resolved target path
  Try {
    sc := ComObjCreate("WScript.Shell").CreateShortcut(lnkPath)
    sc.TargetPath := resolvedPath
    sc.Save()
    Return true
  }
  Return false
}

; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === SAFE RUN (as user, admin, SYSTEM) === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; ∙ Run executable with argument handling and optional elevation
; ∙ Build PowerShell argument string in comma-separated array Format
; ∙ Support elevation via PowerShell's Start-Process -Verb RunAs
; ∙ Spawn from Explorer For cleaner process trees
; Examples:
; ∙ User: UserRun("wt", "-d %UserProfile%\Desktop"), or UserRun("wt", "-d" . A_Desktop)
; ∙ Admin: UserRun("elevate", exePath, fileArguments)
UserRun(Executable, Args*) {
    global UserRun_LastError

    UserRun_LastError := ""

    ; "elevate" is a sentinel: elevate the real target in Args[1]
    elevate := (Executable = "elevate")
    if (elevate) {
        if (Args.Length() < 1) {
            MsgBox, 16, UserRun failed, Missing target executable for elevate.
            return false
        }
        Executable := Args[1]
        Args.RemoveAt(1)
    }

    ; Check if any arg needs PowerShell for env var expansion
    needsPowerShell := false
    Loop % Args.Length() {
        arg := Args[A_Index]
        if (RegExMatch(arg, "%(.*?)%") || InStr(arg, "$env:")) {
            needsPowerShell := true
            break
        }
    }

    ; Resolve RunFromProcess once. Empty string means "not available".
    rfp := FindInPath("RunFromProcess-x64.exe")

    ; --------------------------------------------------------------------------
    ; PowerShell-required path
    ; --------------------------------------------------------------------------
    if (needsPowerShell) {
        ; Resolve PowerShell only here, because only this branch requires it.
        psPath := FindInPath("powershell.exe")
        if (psPath = "")
            psPath := FindInPath("pwsh.exe")

        if (psPath = "") {
            MsgBox, 16, UserRun failed, PowerShell is required for this launch path but was not found.
            return false
        }

        ; pwsh-only environment workaround
        psPrefix := ""
        if RegExMatch(psPath, "(?i)\\pwsh\.exe$")
            psPrefix := "set DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 && "

        _safeExe := StrReplace(Executable, "'", "''")
        quotedExe := "'" _safeExe "'"
        psCmd := "& " quotedExe

        Loop % Args.Length() {
            arg := Args[A_Index]

            ; Handle "-d <path>" specially (Windows Terminal)
            if RegExMatch(arg, "(?i)^\s*-d\s+(.+)$", m) {
                rawPath := m1
                expanded := RegExReplace(rawPath, "(?i)%(.*?)%", "$env:$1")
                _safePath := StrReplace(expanded, "'", "''")
                psCmd .= " -d '" _safePath "'"
            } else {
                expanded := RegExReplace(arg, "(?i)%(.*?)%", "$env:$1")
                _safeArg := StrReplace(expanded, "'", "''")
                psCmd .= " '" _safeArg "'"
            }
        }

        if (elevate) {
            ; Elevation in this branch is PowerShell-mediated by design.
            _psCmdEsc := StrReplace(psCmd, "'", "''")
            psExeQ := """" psPath """"
            psArg := "-NoProfile -Command ""Start-Process " psExeQ " -ArgumentList '-NoProfile -Command " _psCmdEsc "' -Verb RunAs -WindowStyle Hidden"""

            if (rfp != "") {
                full := """" rfp """ explorer.exe conhost.exe --headless cmd.exe /C """ psPrefix psExeQ " " psArg """"
                Run, %full%, , UseErrorLevel Hide
                if (ErrorLevel) {
                    MsgBox, 16, UserRun failed, % "Run failed.`nErrorLevel: " ErrorLevel "`n`nCommand:`n" full
                    return false
                }
                return true
            }

            ; Fallback: Explorer shell (may inherit elevation)
            ToolTip, UserRun: PS + elevated + ShellExecute (no RFP)
            SetTimer, RemoveToolTip, -3000
            if !ShellRunUserOrFail("cmd.exe", "/C " Chr(34) psPrefix psExeQ " " psArg Chr(34), "", "open", 0)
                return false

            return true
        }

        ; Non-elevated PowerShell path
        psExeQ := """" psPath """"
        psArg := "-NoProfile -Command " Chr(34) psCmd Chr(34)

        ; DEBUG: Log the constructed command
        _logFile := A_Temp . "\TA_Debug.log"
        FileAppend, % A_Now . " | UserRun PS path: psCmd=" . psCmd . "`n", %_logFile%

        if (rfp != "") {
            full := """" rfp """ explorer.exe conhost.exe --headless cmd.exe /C """ psPrefix psExeQ " " psArg """"
            FileAppend, % A_Now . " | UserRun full cmd: " . full . "`n", %_logFile%
            Run, %full%, , UseErrorLevel Hide
            if (ErrorLevel) {
                MsgBox, 16, UserRun failed, % "Run failed.`nErrorLevel: " ErrorLevel "`n`nCommand:`n" full
                return false
            }
            return true
        }

        ToolTip, UserRun: PS + non-elevated + ShellExecute (no RFP)
        SetTimer, RemoveToolTip, -3000
        if !ShellRunUserOrFail("cmd.exe", "/C " Chr(34) psPrefix psExeQ " " psArg Chr(34), "", "open", 0)
            return false

        return true
    }

    ; --------------------------------------------------------------------------
    ; Direct execution path (no PowerShell semantics required)
    ; --------------------------------------------------------------------------
    argStr := ""
    Loop % Args.Length() {
        arg := Args[A_Index]
        _safeArg := StrReplace(arg, """", """""")
        argStr .= " """ _safeArg """"
    }

    if (elevate) {
        ; If AHK is already elevated, run directly
        if (IsProcessElevated(DllCall("GetCurrentProcessId"))) {
            _safeExeD := StrReplace(Executable, """", """""")
            full := """" _safeExeD """" argStr
            Run, %full%, , UseErrorLevel
            if (ErrorLevel) {
                MsgBox, 16, UserRun failed, % "Run failed.`nErrorLevel: " ErrorLevel "`n`nCommand:`n" full
                return false
            }
            return true
        }

        ; AHK is not elevated - use AHK's *RunAs verb (simpler than PowerShell Start-Process)
        _safeExeD := StrReplace(Executable, """", """""")
        full := "*RunAs """ _safeExeD """" argStr
        Run, %full%, , UseErrorLevel
        if (ErrorLevel) {
            MsgBox, 16, UserRun failed, % "Run failed.`nErrorLevel: " ErrorLevel "`n`nCommand:`n" full
            return false
        }
        return true
    }

    ; Direct non-elevated path
    _safeExeD := StrReplace(Executable, """", """""")
    full := ""

    if (rfp != "") {
        innerCmd := _safeExeD . argStr
        full := """" rfp """ explorer.exe conhost.exe --headless cmd.exe /C " innerCmd
        Run, %full%, , UseErrorLevel Hide
        if (ErrorLevel) {
            MsgBox, 16, UserRun failed, % "Run failed.`nErrorLevel: " ErrorLevel "`n`nCommand:`n" full
            return false
        }
        return true
    }

    ToolTip, UserRun: Direct + non-elevated + ShellExecute (no RFP)
    SetTimer, RemoveToolTip, -3000
    if !ShellRunUserOrFail(Executable, LTrim(argStr), "", "open", 1)
        return false

    return true
}
ShellRunUser(exe, args := "", dir := "", verb := "open", show := 1) {
    global UserRun_LastError
    UserRun_LastError := ""
    try {
        shell := ComObjCreate("Shell.Application")
        shell.ShellExecute(exe, args, dir, verb, show)
        shell := ""
        return true
    } catch e {
        UserRun_LastError := "ShellExecute failed: " e.Message
        return false
    }
}
ShellRunUserOrFail(exe, args := "", dir := "", verb := "open", show := 1) {
    if !ShellRunUser(exe, args, dir, verb, show) {
        MsgBox, 16, UserRun failed, % UserRun_LastError
        return false
    }
    return true
}

; Check if a process is running elevated
IsProcessElevated(pid) {
  hProcess := DllCall("OpenProcess", "UInt", 0x0400, "Int", false, "UInt", pid, "Ptr")  ; PROCESS_QUERY_INFORMATION
  If (!hProcess)
    Return false
  hToken := 0
  DllCall("advapi32\OpenProcessToken", "Ptr", hProcess, "UInt", 0x0008, "Ptr*", hToken)  ; TOKEN_QUERY
  DllCall("CloseHandle", "Ptr", hProcess)
  If (!hToken)
    Return false
  elevation := 0
  DllCall("advapi32\GetTokenInformation", "Ptr", hToken, "Int", 20, "UInt*", elevation, "UInt", 4, "UInt*", 0)
  DllCall("CloseHandle", "Ptr", hToken)
  Return elevation
}

RemoveToolTip:
  ToolTip
Return

; === Module Includes ===
#Include %A_ScriptDir%\terminal-anywhere.ahk
#Include %A_ScriptDir%\extended-spy.ahk
#Include %A_ScriptDir%\mbutton-scroll.ahk
#Include %A_ScriptDir%\window-spawning.ahk