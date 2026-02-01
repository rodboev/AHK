; Global AutoHotKey keys
; #   Windows key
; ^   Ctrl 
; !   Alt
; +   Shift
; +!  Shift+Alt

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

; Disable hotkeys inside remote sessions (RDP, Hyper-V, VMWare)
#If IsRemoteSession()
  If !IsRemoteSession()
    WS_Init() ; Init window spawning
  Return
#If

; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === BINDINGS / REMAPS === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; ⇒ AutoHotkey/global
+!r::Reload ; [ ShIft+Alt+R ] -> Reload script
+!p::       ; [ ShIft+Alt+P ] -> Toggle pause script+suspend hotkeys
  Suspend
  Pause,,1
Return
+!e::Edit ; [ Shift+Alt+E ] -> Edit script (same as tray menu "Edit This Script")
#IfWinActive AutoHotkey.ahk
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
#If (WinActive("ahk_exe code.exe") or WinActive("ahk_exe cursor.exe") or WinActive("ahk_exe antigravity.exe") or WinActive("ahk_exe vscodium.exe"))
  ^w::Send {Alt Down}z{AltUp} ; [ Ctrl+W ] -> Toggle word wrap
#If

; ⇒ Windows Terminal
#IfWinActive ahk_exe WindowsTerminal.exe
  ^n::Send ^+t ; [ Ctrl+N] -> New tab
#IfWinActive

; ⇒ Other global bindings
+!-::Send {U+2014} ; [ ShIft+Alt+Minus ] -> em-dash: —
+!0::Send {U+2022} ; [ ShIft+Alt+0] -> Bullet: •
~RWin::Send {AppsKey} ; [RWin] -> Apps/context menu
~#t::Run explorer shell:::{3080F90E-D7AD-11D9-BD98-0000947B0257} ; Win+T -> Task View
+!x:: ; [ ShIft+Alt+X ] -> Refresh Explorer
^+!x:: ; [ Ctrl+ShIft+Alt+X ] -> Restart Explorer
  If (FindInPath("Rexplorer_x64.exe")) {
    If GetKeyState("Ctrl", "P") {
      UserRun("Rexplorer_x64.exe")
    }
    Else {
      UserRun("taskkill", "/f /im explorer.exe && start explorer.exe")
    }
  }
  Else {
    UserRun("Rexplorer_x64.exe", "/f")
  }
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

; VLC binding to go to next file on mouse middle button press
#IfWinActive ahk_class QWidget
  $*MButton::Send n
#IfWinActive

; Ctrl+ShIft+L: Turn off monitor
+!l::
  UserRun("nircmd", "cmdwait 200 monitor off")
  SendMessage, 0x112, 0xF140, 0,, Program Manager
  Sleep 3000
  VarSetCapacity(screen_saver_active,4,0)
  SPI_GETSCREENSAVERRUNNING = 0x0072
  result := DllCall( "user32.dll\SystemParametersInfo", "uint", SPI_GETSCREENSAVERRUNNING, "uint", 0, "uint*", screen_saver_active, "uint", 0 )
  WinGetActiveTitle, Title
  If (Title = "")
    SendMessage, 0x112, 0xF170, 2,, Program Manager ; Shut off monitor
Return

; Alt+D: Focus address bar in Open dialog
#IfWinActive, Open
  !d::Send {Alt Down}n{Alt Up}
#IfWinActive

; Ctrl+E: Edit selected file (in Explorer or file dialog)
^e::
  selected := ""
  If WinActive("ahk_class #32770") { ; File dialog active
    ControlGetText, selected, Edit1, A ; Selected file's path
  }
  Else If WinActive("ahk_class CabinetWClass") { ; Explorer window active
    For window in ComObjCreate("Shell.Application").Windows {
      If (window.hwnd == WinActive("A")) {
        selected := window.Document.SelectedItems.Item(0).Path
        Break
      }
    }
  }
  If (selected != "") {
    pid := ProcessExistsByCommandLine("sublime_text.exe"" """ . selected)
    If (pid) {
      WinActivate, ahk_pid %pid%
    } Else {
      UserRun("subl", selected)
    }
  }
Return

; Alt+Shift+S = Run or activate Everything
~+!s::
  DetectHiddenWindows, On
  If (!WinExist("ahk_exe Everything.exe")) {
    UserRun("C:\Program Files\Everything 1.5a\Everything.exe")
    WinWait, ahk_exe Everything.exe
    WinActivate
  }
Return

#IfWinActive ahk_exe Everything.exe
Esc::
!F4::
  If WinExist("ahk_class EVERYTHING_DROPDOWNLIST")
    WinClose
  WinHide
Return
#IfWinActive

; Up one level in Explorer unless renaming or in tree view
#IfWinActive, ahk_class CabinetWClass
  Backspace::
    ControlGet renamestatus,Visible,,Edit1,A
    ControlGetFocus focused, A
    If (renamestatus != 1 and (focused = "DirectUIHWND3" or focused = "SysTreeView321"))
      SendInput {Alt Down}{Up}{Alt Up}
    Else
      Send {Backspace}
  Return
#IfWinActive


; Accelerated scrolling in MPC
; https://autohotkey.com/board/topic/48426-accelerated-scrolling-script/?p=333222
; TODO: Need to merge with scroll control under mouse
; TODO: Alt+WheelUp/Down = Scroll horizontally
; #If (WinActive("ahk_exe explorer.exe") or WinActive("ahk_class PROCMON_WINDOW_CLASS") or WinActive("ahk_class MPC-BE") or WinActive("ahk_class MediaPlayerClassicW"))
#IfWinActive ahk_class MediaPlayerClassicW
  ; WheelUp/Down scroll with acceleraation (10x with ShIft)
  WheelUp::
  WheelDown::
    ; The length of a scrolling session. Keep scrolling within this time to accumulate boost. ; Default: 500. Recommended between 400 and 1000.
    timeout := 500

    ; If you scroll a long distance in one session, apply additional boost factor. The higher the ; value, the longer it takes to activate, and the slower it accumulates. ; Set to zero to disable ; completely. Default: 30.
    boost := 3

    ; Spamming applications with hundreds of individual scroll events can slow them down. This sets ; the maximum number of scrolls sent per click, i.e. max velocity. ; Default: 60.
    limit := 30
    distance := 0
    vmax := 1
    t := A_TimeSincePriorHotkey
    If (A_PriorHotkey = A_ThisHotkey && t < timeout) {
        ; ToolTip, t: %t% timeout: 500
        ; t := A_TimeSincePriorHotkey
        distance++
        v := (t < 80 && t > 1) ? (250.0 / t) - 1 : 1
        If (boost > 1 && distance > boost)
        {
          If (v > vmax)
            vmax := v
          Else
            v := vmax
          v *= distance / boost
        }
        QuickToolTip(v, 500)
        v := (v > 1) ? ((v > limit) ? limit : Floor(v)) : 1
        MouseClick, %A_ThisHotkey%, , , v
      QuickToolTip(text, delay)
      {
        ToolTip, ScrollAccel: %text%
        SetTimer ToolTipOff, %delay%
        Return
        ToolTipOff:
        SetTimer ToolTipOff, Off
        ToolTip
        Return
      }
    }
    Else {
        ; QuickToolTip("normal", 500)
        MouseClick, %A_ThisHotkey%
    }
    ; #If
  Return
  +WheelUp::Send {Click WheelUp 10}
  +WheelDown::Send {Click WheelDown 10}
#IfWinActive


; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === PROCESS MANAGEMENT / PRIVELEGE ESCALATION === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; [ Ctrl+Shift+` ] -> Open System Informer as SYSTEM with TI privileges
^+`::UserRun("elevate", "ti", "c:\Program Files\SystemInformer\SystemInformer.exe")

; [ Win+Shift+E ] -> Alternate Explorer app in case of issues after Windows updates
#+e::
  WinGetClass, ahk_class, A
  path := GetExplorerPath()
  If (ahk_class = "Progman")
    path := A_Desktop
  Else If (ahk_class != "CabinetWClass" || path = "")
    path := A_UserProfile

  ; Activate existing e++ window for this path, or open new
  pid := ProcessExistsByCommandLine("files-stable.exe"" " . path)
  If (pid) {
    WinActivate, ahk_pid %pid%
  } Else {
    UserRun("files-stable", path)
  }
Return

; Win+C: Copy command line of active window to clipboard
#c::
  cmdLine := GetActiveWindowCommandLine()
  If (cmdLine && cmdLine != "") {
    ; Make sure to clear the clipboard first
    Clipboard := ""
    ; Copy the command line to the clipboard
    Clipboard := cmdLine
    ; Wait For the clipboard to contain data
    ClipWait, 1
    If (ErrorLevel) {
      ToolTip, Failed to copy command line to clipboard
    } Else {
      ToolTip, >> %cmdLine%
    }
    SetTimer, RemoveToolTip, -3000
  } Else {
    ToolTip, Could not get command line
    SetTimer, RemoveToolTip, -2000
  }
Return

; Ctrl+Shift+Plus: Relaunch active window with TrustedInstaller (NT AUTHORITY/SYSTEM) privileges
^+=::
  WinGet, activePid, PID, A
  WinGet, activeExe, ProcessName, A
  exe := GetExePath()

  If (exe.path) {
    fullCmd := "ti.exe """ . exe.path . """"
    MsgBox, 4, Command to run, %fullCmd%`n`nClick Yes to run, No to cancel
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

; ⇒ Check if string is a path
isPath(str) {
  If RegExMatch(str, "^[A-Za-z]:\\.*")
    Return true
  Else
    Return false
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

; ⇒ Get current path of active Explorer window
GetExplorerPath() {
  static shell := ComObjCreate("Shell.Application")
  WinGet, hwnd, ID, A
  For window in shell.Windows {
    If (window.hwnd = hwnd) {
      Try {
        Return window.Document.Folder.Self.Path
      }
      Catch {
        Return ""  ; not a filesystem view
      }
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

; ⇒ Get CmdLine for any active window (for elevation)
GetActiveWindowCommandLine() {
  WinGet, pid, PID, A
  WinGet, activeExe, ProcessName, A
  
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
  elevate := (Executable = "elevate")
  If (elevate) {
    Executable := Args[1]
    Args.RemoveAt(1)
  }

  ; Check If any arg needs PowerShell For env var expansion or special handling
  needsPowerShell := false
  Loop % Args.Length() {
    arg := Args[A_Index]
    If (RegExMatch(arg, "%(.*?)%") || InStr(arg, "$env:") || RegExMatch(arg, "(?i)^\s*-d\s")) {
      needsPowerShell := true
      Break
    }
  }

  ; Run from Explorer For cleaner process trees
  If (needsPowerShell) {
    quotedExe := InStr(Executable, " ") ? "'" Executable "'" : Executable
    psCmd := "& " quotedExe
    Loop % Args.Length() {
      arg := Args[A_Index]
      ; Handle "-d <path>" specially (For Windows Terminal)
      If RegExMatch(arg, "(?i)^\s*-d\s+(.+)$", m) {
        rawPath := m1
        expanded := RegExReplace(rawPath, "(?i)%(.*?)%", "$env:$1")
        path := (InStr(expanded, " ") ? "'" expanded "'" : expanded)
        psCmd .= " -d " path
      } Else {
        expanded := RegExReplace(arg, "(?i)%(.*?)%", "$env:$1")
        quotedArg := (InStr(expanded, " ") ? "'" expanded "'" : expanded)
        psCmd .= " " quotedArg
      }
    }
    If (elevate) {
      full := "RunFromProcess-x64 explorer.exe conhost.exe --headless powershell -NoProfile -Command ""Start-Process powershell -ArgumentList '-NoProfile -Command " psCmd "' -Verb RunAs -WindowStyle Hidden"""
    } Else {
      full := "RunFromProcess-x64 explorer.exe conhost.exe --headless powershell -NoProfile -Command """ psCmd """"
    }
  } Else {
    ; Direct execution - no env vars to expand, build simple argument string
    argStr := ""
    Loop % Args.Length() {
      arg := Args[A_Index]
      If (InStr(arg, " "))
        argStr .= " """ arg """"
      Else
        argStr .= " " arg
    }
    If (elevate) {
      ; Use PowerShell Start-Process For elevation
      full := "RunFromProcess-x64 explorer.exe conhost.exe --headless powershell -NoProfile -Command ""Start-Process '" Executable "' -ArgumentList '" argStr "' -Verb RunAs -WindowStyle Hidden"""
    } Else {
      full := "RunFromProcess-x64 explorer.exe " Executable argStr
    }
  }

  Run, %full%, , Hide
  Return !ErrorLevel
}

; Check if a process is running elevated
IsProcessElevated(pid) {
  hProcess := DllCall("OpenProcess", "UInt", 0x0400, "Int", false, "UInt", pid, "Ptr")
  If (!hProcess)
    Return false
  hToken := 0
  DllCall("advapi32\OpenProcessToken", "Ptr", hProcess, "UInt", 0x0008, "Ptr*", hToken)
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

; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ WINDOWS TERMINAL FROM ANYWHERE ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; [ F10 ] -> Open Windows Terminal in current Explorer path
; [ Shift+F10 ] -> Open with admin rights
; [ Ctrl+Alt+Shift+F10 ] -> Open Windows Terminal with SYSTEM rights
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
    UserRun("elevate", "ti", "wt", "-d " . A_Desktop)
  Else If (ahk_class = "CabinetWClass" && path != "")
    UserRun("elevate", "ti", "wt", "-d " . path)
  Else {
    exe := GetExePath()
    UserRun("elevate", "ti", "wt", "-d " . (exe.dir ? exe.dir : A_UserProfile))
  }
Return

; === Module Includes ===
#Include %A_ScriptDir%\extended-spy.ahk
#Include %A_ScriptDir%\mbutton-scroll.ahk
#Include %A_ScriptDir%\window-spawning.ahk
