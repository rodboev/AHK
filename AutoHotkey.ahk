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

; Prevent script proceeding in RDP windows
#IfWinActive, ahk_class TscShellContainerClass
    Return
#IfWinActive


; AHK bindings
+!r::Reload
+!p::
    Suspend
    Pause,,1
Return
+!e::UserRun("C:\Users\Rod\AppData\Local\Programs\Microsoft VS Code\Code.exe", A_ScriptFullPath)

; -------------------------------------------------------------- ;
; Sublime Text bindings

#IfWinActive ahk_exe sublime_text.exe
    ^Tab::Send {Ctrl Down}{PgDn}{Ctrl Up}
    +^Tab::Send {Ctrl Down}{PgUp}{Ctrl Up}
    +!d::Send {Alt Down}f{AltUp}e{Ctrl Down}
    ^w::Send {Alt Down}f{AltUp}{Left}{Alt Down}v{AltUp}w
    ^;::
    #;::
    !;::
        IfWinActive,  - .ahk
        {
            Send ^/
        }
    Return
#IfWinActive

; Reload on save
#IfWinActive AutoHotkey.ahk
    ~^s::Reload
#IfWinActive

; em dash
+^-::Send {ASC 0151}
; bullet
+^0::Send {ASC 0149}


; -------------------------------------------------------------- ;
; Explorer bindings - dealing with processes
; -------------------------------------------------------------- ;
; Terminal and arbitrary command bindings that support limited user mode,
; elevation, SYSTEM and above privileges, process injection, you name it.

; Run as user (optionally elevated)

; BuildPSArgsString and BuildPSArgsArray convert AHK function arguments into PowerShell arrays
; They handle proper escaping of spaces, environment variables, and special characters
; 
; BuildPSArgsString: Creates a simple comma-separated string array format
; BuildPSArgsArray: More complex processing for special argument formats like Windows Terminal's "-d path"
;
; Examples:
; BuildPSArgsString("cmd", "/c", "dir", "%UserProfile%")
;   Returns: @('cmd', '/c', 'dir', '$env:UserProfile')
;
; BuildPSArgsArray("wt", "-d %UserProfile%\Documents", "cmd")
;   Returns: @('-d', '$env:UserProfile\Documents', 'cmd')
;
; Practical uses:
; 1. For UserRun: UserRun("elevate", "wt", "-d %UserProfile%\Desktop")
; 2. Process elevation: UserRun("elevate", exePath, fileArguments)
; 3. Command injection: UserRun("RunFromProcess", "explorer", "powershell", "-Command", "Get-Process")

BuildPSArgsString(Args*) {
    list := ""
    Loop % Args.Length() {
        raw := Args[A_Index]
        if RegExMatch(raw, "(?i)\bcmd\b") {
            elem := "'" raw "'"
        }
        else {
            arg := RegExReplace(raw, "(?i)%(.*?)%", "$env:$1")
            if InStr(arg, " ")
                elem := "'" arg "'"
            else
                elem := "'" arg "'"
        }
        list .= (list ? ", " : "") . elem
    }
    return "@(" list ")"
}

BuildPSArgsArray(Args*) {
    list := ""
    Loop % Args.Length() {
        raw := Args[A_Index]

        ; Split WT's "-d <path>"
        if RegExMatch(raw, "(?i)^\s*-d\s+(.+)$", m) {
            path := RegExReplace(m1, "(?i)%(.*?)%", "$env:$1")
            ; Expand $env: via double'-quotes, literal paths via single'-quotes
            elem := "'-d', " (InStr(path, "$env:") ? """" path """" : "'" path "'")
        }
        else if RegExMatch(raw, "(?i)\bcmd\b") {
            elem := "'" raw "'"  ; literal cmd chains
        }
        else {
            arg := RegExReplace(raw, "(?i)%(.*?)%", "$env:$1")
            elem := InStr(arg, "$env:") ? """" arg """" : "'" arg "'"
        }

        list .= (list ? ", " : "") . elem
    }
    return "@(" . list . ")"
}

UserRun(Executable, Args*) {
    elevate := (Executable = "elevate")
    if (elevate) {
        Executable := Args[1]
        Args.RemoveAt(1)
    }

    ; Check if any arg needs PowerShell for env var expansion or special handling
    needsPowerShell := false
    Loop % Args.Length() {
        arg := Args[A_Index]
        if (RegExMatch(arg, "%(.*?)%") || InStr(arg, "$env:") || RegExMatch(arg, "(?i)^\s*-d\s")) {
            needsPowerShell := true
            break
        }
    }

    ; Always run from explorer.exe for cleaner process trees
    if (needsPowerShell) {
        quotedExe := InStr(Executable, " ") ? "'" Executable "'" : Executable
        psCmd := "& " quotedExe
        Loop % Args.Length() {
            arg := Args[A_Index]
            ; Handle "-d <path>" specially (for Windows Terminal)
            if RegExMatch(arg, "(?i)^\s*-d\s+(.+)$", m) {
                rawPath := m1
                expanded := RegExReplace(rawPath, "(?i)%(.*?)%", "$env:$1")
                path := (InStr(expanded, " ") ? "'" expanded "'" : expanded)
                psCmd .= " -d " path
            } else {
                expanded := RegExReplace(arg, "(?i)%(.*?)%", "$env:$1")
                quotedArg := (InStr(expanded, " ") ? "'" expanded "'" : expanded)
                psCmd .= " " quotedArg
            }
        }
        if (elevate) {
            full := "RunFromProcess-x64 explorer.exe conhost.exe --headless powershell -NoProfile -Command ""Start-Process powershell -ArgumentList '-NoProfile -Command " psCmd "' -Verb RunAs -WindowStyle Hidden"""
        } else {
            full := "RunFromProcess-x64 explorer.exe conhost.exe --headless powershell -NoProfile -Command """ psCmd """"
        }
    } else {
        ; Direct execution - no env vars to expand
        argStr := ""
        Loop % Args.Length() {
            arg := Args[A_Index]
            if (InStr(arg, " "))
                argStr .= " """ arg """"
            else
                argStr .= " " arg
        }
        if (elevate) {
            full := "RunFromProcess-x64 explorer.exe conhost.exe --headless powershell -NoProfile -Command ""Start-Process '" Executable "' -ArgumentList '" argStr "' -Verb RunAs -WindowStyle Hidden"""
        } else {
            full := "RunFromProcess-x64 explorer.exe " Executable argStr
        }
    }

    Run, %full%, , Hide
    return !ErrorLevel
}

; +F3::UserRun("nircmd", "execmd start cmd /k pushd %UserProfile% && cmd /c")

isPath(str) {
    if RegExMatch(str, "^[A-Za-z]:\\.*")
        return true
    else
        return false
}

GetExplorerPath() {
    static shell := ComObjCreate("Shell.Application")
    WinGet, hwnd, ID, A
    for window in shell.Windows {
        if (window.hwnd = hwnd) {
            try {
                return window.Document.Folder.Self.Path
            } catch {
                return ""  ; not a filesystem view
            }
        }
    }
    return ""
}

; Open Windows Terminal in the current directory
F10::
    WinGetClass, winClass, A
    path := GetExplorerPath()

    if (winClass = "Progman") {
        UserRun("wt", "-d $env:UserProfile\Desktop")
    }
    else if (winClass = "CabinetWClass" && path != "") {
        UserRun("wt", "-d " . path)
    }
    else {
        UserRun("wt", "-d $env:UserProfile")
    }
Return

; Elevation
+F10::
    WinGetClass, winClass, A
    path := GetExplorerPath()

    if (winClass = "Progman") {
       UserRun("elevate", "wt", "-d $env:UserProfile\Desktop")
    }
    else if (winClass = "CabinetWClass" && path != "") {
        UserRun("elevate", "wt", "-d " . path)
    }
    else {
        UserRun("elevate", "wt", "-d $env:UserProfile")
    }
Return



; SYSTEM elevation
^!+F10::
    WinGetClass, winClass, A
    path := GetExplorerPath()
    if (winClass = "Progman") {
        Run, psexec -d -i -s wt -d "%UserProfile%\Desktop", , Hide
    }
    else if (winClass = "CabinetWClass" && path != "") {
        Run, psexec -d -i -s wt -d "%path%", , Hide
    }
    else {
        Run, psexec -d -i -s wt -d "%UserProfile%", , Hide
    }
Return

#e::
    WinGetClass, winClass, A
    path := GetExplorerPath()
    if (winClass = "Progman" || winClass = "CabinetWClass") {
        Run, e++ "%path%"
    }
    else {
        Run, e++ "%path%"
    }
    Run, "C:\Dropbox\Tools\exe\e++.exe"
    WinWait ahk_exe e++.exe
    WinActivate
Return

; Similar elevation for System Informer
^+`::Run, ti "c:\Program Files\SystemInformer\SystemInformer.exe"

; -------------------------------------------------------------- ;
; Elevate any active window

; getPath() {
;     WinGet, pid, PID, A
;     WinGetClass, winClass, A

;     if (winClass = "Progman" || winClass = "CabinetWClass") {
;         ; For Explorer windows, get the current directory
;         firstLine := getFirstLine()
;         if (firstLine && firstLine != "") {
;             ; If it's already a path, return it directly
;             if (isPath(firstLine))
;                 return firstLine
                
;             ; Otherwise, try to construct a path with the user profile
;             EnvGet, UserProfile, UserProfile
;             possiblePath := UserProfile . "\" . firstLine
;             if (FileExist(possiblePath))
;                 return possiblePath
;         }
;     }
    
;     if (pid) {
;         ; For other windows, get the process path
;         WinGet, exePath, ProcessPath, A
;         if (exePath && exePath != "") {
;             return exePath
;         }
;     }

;     ; Default fallback
;     return "."
; }

GetActiveWindowCommandLine() {
    WinGet, pid, PID, A
    WinGet, activeExe, ProcessName, A
    
    if (pid) {
        ; Get command line using WMI
        cmdLine := ""
        for process in ComObjGet("winmgmts:").ExecQuery("Select CommandLine from Win32_Process where ProcessId=" . pid)
            cmdLine := process.CommandLine
        
        if (cmdLine) {
            return cmdLine
        } else {
            ; Fallback to process path if command line not available
            WinGet, exePath, ProcessPath, A
            if (exePath) {
                return exePath
            }
        }
    }
    return "."
}

#c::
    path := GetExplorerPath()
    if (path && path != "") {
        ; Make sure to clear the clipboard first
        Clipboard := ""
        ; Copy the path to the clipboard
        Clipboard := path
        ; Wait for the clipboard to contain data
        ClipWait, 1
        if (ErrorLevel) {
            ToolTip, Failed to copy path to clipboard
        } else {
            ToolTip, >> "%path%"`nCopied to clipboard
        }
        SetTimer, RemoveToolTip, -3000
    } else {
        ToolTip, Could not get path
        SetTimer, RemoveToolTip, -2000
    }
Return

; Function to check if a process with specific command line exists
ProcessExistsByCommandLine(cmdLine) {
    for process in ComObjGet("winmgmts:").ExecQuery("Select ProcessId, CommandLine from Win32_Process")
        if (InStr(process.CommandLine, cmdLine))
            return process.ProcessId
    return 0
}

; Shift+Win+C: Copy command line of active window to clipboard
+#c::
    cmdLine := GetActiveWindowCommandLine()
    if (cmdLine && cmdLine != "") {
        ; Make sure to clear the clipboard first
        Clipboard := ""
        ; Copy the command line to the clipboard
        Clipboard := cmdLine
        ; Wait for the clipboard to contain data
        ClipWait, 1
        if (ErrorLevel) {
            ToolTip, Failed to copy command line to clipboard
        } else {
            ToolTip, >> %cmdLine%
        }
        SetTimer, RemoveToolTip, -3000
    } else {
        ToolTip, Could not get command line
        SetTimer, RemoveToolTip, -2000
    }
Return

; Ctrl+Shift+Plus: Get current window exe path and run ti.exe with it
^+=::
    WinGet, activePid, PID, A
    WinGet, activeExe, ProcessName, A
    WinGet, exePath, ProcessPath, A
    
    if (exePath) {
        fullCmd := "ti.exe """ . exePath . """"
        MsgBox, 4, Command to run, %fullCmd%`n`nClick Yes to run, No to cancel
        IfMsgBox Yes
        {
            ; Store the original path for comparison
            originalPath := exePath
            
            ; Run the elevated command
            Run, %fullCmd%
            
            ; Wait for the new process to appear (up to 250ms)
            startTime := A_TickCount
            newProcessFound := false
            
            Loop {
                ; Check if a new process with this path exists
                for process in ComObjGet("winmgmts:").ExecQuery("Select ProcessId, ExecutablePath from Win32_Process")
                    if (process.ExecutablePath = originalPath && process.ProcessId != activePid) {
                        newProcessFound := true
                        break
                    }
                
                if (newProcessFound)
                    break
                
                ; Check if we've waited long enough
                if (A_TickCount - startTime > 250)
                    break
                
                Sleep, 50
            }
            
            ; If no new process appeared, close the original app and try again
            if (!newProcessFound) {
                ; Try to close the original application gracefully
                WinClose, ahk_pid %activePid%
                
                ; Wait for the app to close (up to 500ms)
                startCloseTime := A_TickCount
                appClosed := false
                
                Loop {
                    if (!WinExist("ahk_pid " . activePid)) {
                        appClosed := true
                        break
                    }
                    
                    if (A_TickCount - startCloseTime > 500) {
                        ; Force kill if it didn't close gracefully
                        Process, Close, %activePid%
                        Sleep, 100
                        break
                    }
                    
                    Sleep, 50
                }
                
                ; Try running the command again
                Run, %fullCmd%
            }
        }
    }
Return

RemoveToolTip:
    ToolTip
Return

; -------------------------------------------------------------- ;
; Mouse and key re-bindings

; Context menu key
; Used for fluent search
~RWin::Send {AppsKey}

; ; Task View
~#t::Run explorer shell:::{3080F90E-D7AD-11D9-BD98-0000947B0257}


; Get info from Window Under Mouse without clicking on it
; https://autohotkey.com/board/topic/80855-get-info-from-window-under-mouse-without-clicking-on-it/?p=513888
; https://autohotkey.com/board/topic/80855-get-info-from-window-under-mouse-without-clicking-on-it/?p=514092
F12::
    UnderCursorToggle := !UnderCursorToggle
    If (UnderCursorToggle) {
        SetTimer ToolTipUnderCursor, 250
    }
    Else {
        SetTimer ToolTipUnderCursor, Off
        ToolTip
        Clipboard := GetUnderCursorInfo(X, Y)
    }
Return
HexToDec(HexVal) {
     Old_A_FormatInteger := A_FormatInteger
     SetFormat IntegerFast, D
     DecVal := HexVal + 0
     SetFormat IntegerFast, %Old_A_FormatInteger%
     Return DecVal
}
GetUnderCursorInfo(ByRef CursorX, ByRef CursorY) {
     CoordMode Mouse, Screen
     CoordMode Pixel, Screen
     MouseGetPos, CursorX, CursorY, Window, Control
     WinGetTitle Title, ahk_id %Window%
     WinGetClass Class, ahk_id %Window%
     WinGetPos WindowX, WindowY, Width, Height, ahk_id %Window%
     WinGet PName, ProcessName, ahk_id %Window%
     WinGet PID, PID, ahk_id %Window%
     PixelGetColor BGR_Color, CursorX, CursorY
     CursorHwnd := DllCall("WindowFromPoint", "int64", CursorX | (CursorY << 32), "Ptr")
     If !(Class = "tooltips_class32" and PName = "AutoHotkey.exe") {
         WindowUnderCursorInfo := "ahk_id: " Window "`n"
            . "ahk_class: " Class "`n"
            . "title: " Title "`n"
            . "control: " Control "`n"
            . "PID: " PID "`n"
            . "Cursor hWnd: `" CursorHwnd "`n"
            . "ahk_exe: " PName "`n"
            . "top left (" WindowX ", " WindowY ")`n"
            . "(width x height) (" Width " x " Height ")`n"
            . "cursor's window position (" CursorX-WindowX ", " CursorY-WindowY ")`n"
            . "cursor's screen position (" CursorX ", " CursorY ")`n"
            ; . "BGR color: " BGR_Color " (" HexToDec("0x" SubStr(BGR_Color, 3, 2)) " , 
            ; . HexToDec("0x" SubStr(BGR_Color, 5, 2)) ", "
            ; . HexToDec("0x" SubStr(BGR_Color, 7, 2)) ")`n"
    }
    Return WindowUnderCursorInfo
}
ToolTipUnderCursor:
     WindowUnderCursorInfo := GetUnderCursorInfo(CursorX, CursorY)
     CoordMode ToolTip, Screen
     ; place tooltip in quadrant opposite of cursor
     If (CursorX < (A_ScreenWidth // 2))
        TTXOffset = 150
     Else
        TTXOffset = -150
     If (CursorY < (A_ScreenHeight // 2))
        TTYOffset = 150
     Else
        TTYOffset = -150
     ToolTip %WindowUnderCursorInfo%
        , ((A_ScreenWidth // 2) + TTXOffset)
        , ((A_ScreenHeight // 2) + TTYOffset)
Return


; Description: Get extended attributes of window under mouse cursor
; Tags: Extended info window, 
; Permalink: https://autohotkey.com/boards/viewtopic.php?f=6&t=43544
; Author: aph
; Version: 0.6
; Hotkey: Win+W
#w::
    MouseGetPos, CursorX, CursorY, Window, ClassNN
    WinGetTitle, Title, ahk_id %Window%
    WinGetClass, ahk_class, ahk_id %Window%
    DetectHiddenText, On
    WinGetText, WindowText, ahk_id %Window%
    WinGet, WindowPID, PID, ahk_id %Window%
    WinGet, ControlText, ControlList, ahk_id %Window%
    CursorHwnd := DllCall("WindowFromPoint", "int64", CursorX | (CursorY << 32), "Ptr")
    StringReplace, ControlText, ControlText, `n, %A_SPACE%, All
    StringReplace, WindowText, WindowText, `n,  , All
    StringReplace, WindowText, WindowText, %A_SPACE%%A_SPACE%, , All
    If !(WindowText = "")
        WindowText = `n%WindowText%
    WinGetText, Text, ahk_id %Window%
    WinGet, ahk_exe, ProcessName, ahk_id %Window%
    WinGet, Path, ProcessPath, ahk_id %Window%
    ; TODO: Rewrite using . syntax
    ; if ahk_exe != AutoHotkey.exe and ahk_class != AutoHotkeyGUI
    UnderCursor =
(
Title: %Title%
ahk_id = %Window%
ahk_exe = %ahk_exe%
ahk_class = %ahk_class%
Path: %Path%
Process ID: %WindowPID%
Control ClassNN: %ClassNN%
hWnd under cursor: %CursorHwnd%

Window Text:%WindowText%

Control Text:
%ControlText%
)
    Gui, Destroy
    SysGet, Workspace, MonitorWorkArea
    Gui, Add, Text, , Select text and Ctrl+C to copy it to to clipboard. Repeat %A_ThisHotkey% to update.
    Gui, Add, Edit, vInfo +Wrap w380, %UnderCursor%
    DetectHiddenWindows, On
    Gui, +LastFound +AlwaysOnTop +Owner
    Gui, Show, NoActivate h255 Hide
    GuiControl, Move, Info, h220
    AspectRatio := WorkspaceRight/WorkSpaceBottom
    GUI_ID := WinExist()
    WinGetPos, GUIX, GUIY, GUIWidth, GUIHeight, ahk_id %GUI_ID%
    Offset = 30
    Gui, Show, % "NoActivate x"WorkspaceRight-GUIWidth-WorkspaceRight/Offset/AspectRatio " y"WorkspaceBottom-GUIHeight-WorkSpaceBottom/Offset, Window under cursor
;         ; ~Esc::
;             ; KeyWait, Esc, D
;             ; if (WinActive("ahk_id " GUI_ID)) {
;                 ; Gui, Destroy
;                 ; ; Process, Exist, %GUI_ID%
;                 ; ; If (ErrorLevel = 0)
;                     ; ; Process, Close, %GUI_ID%
;             ; }
;         Return
    Return
Return

; ==============================================================================================================

; VLC binding to go to next file on mouse middle button press
#IfWinActive ahk_class QWidget
$*MButton::Send n
#IfWinActive

; Win+L: Turn off monitor
; TODO: Limit to local network. https://autohotkey.com/board/topic/25456-which-string-use-workgroup/?p=165074
#l::
    Run RunFromProcess-x64 explorer.exe nircmd cmdwait 200 monitor off
    SendMessage, 0x112, 0xF140, 0,, Program Manager
    Sleep 3000
    VarSetCapacity(screen_saver_active,4,0)
    SPI_GETSCREENSAVERRUNNING = 0x0072
    result := DllCall( "user32.dll\SystemParametersInfo", "uint", SPI_GETSCREENSAVERRUNNING, "uint", 0, "uint*", screen_saver_active, "uint", 0 )
    WinGetActiveTitle, Title
    if (Title = "")
        SendMessage, 0x112, 0xF170, 2,, Program Manager ; Shut off monitor
Return

#IfWinActive, Open
    !d::Send {Alt Down}n{Alt Up}
#IfWinActive

; ; ; Win+L: Turn off monitor
; ; ; TODO: Limit to local network. https://autohotkey.com/board/topic/25456-which-string-use-workgroup/?p=165074

^!l::
    Run, psexec -l nircmd cmdwait 200 monitor off
    SendMessage, 0x112, 0xF140, 0,, Program Manager
    Sleep 5000
    VarSetCapacity(screen_saver_active,4,0)
    SPI_GETSCREENSAVERRUNNING = 0x0072
    result := DllCall( "user32.dll\SystemParametersInfo", "uint", SPI_GETSCREENSAVERRUNNING, "uint", 0, "uint*", screen_saver_active, "uint", 0 )
    WinGetActiveTitle, Title
    if (Title = "")
        SendMessage, 0x112, 0xF170, 2,, Program Manager ; Shut off monitor
Return

; Edit the currently selected file
#IfWinActive ahk_class CabinetWClass ; Only run if Explorer window is active
^e:: ; Ctrl+E hotkey
    ; Get the path of the selected file
    for window in ComObjCreate("Shell.Application").Windows
    {
        if (window.hwnd == WinActive("A"))
        {
            selected := window.Document.SelectedItems.Item(0).Path
            break
        }
    }
    ; Open the selected file with Notepad
    Run, deelevate64 "C:\Program Files\Sublime Text\subl.exe" "\"%selected%\""
return
#IfWinActive

#IfWinActive ahk_class #32770 ; Only run if a file dialog is active
^e:: ; Ctrl+E hotkey
    ; Get the path of the selected file
    ControlGetText, selected, Edit1, A
    ; Open the selected file with Notepad
    Run, "C:\Program Files\Sublime Text\subl.exe" "%selected%"
return
#IfWinActive

; Alt+Shift+S = Run or activate Everything
; to send original key:
; SendInput {RWin Down}s{RwinUp}
DetectHiddenWindows, On
+!s::
    If WinExist("ahk_class EVERYTHING") {
        WinShow
        WinActivate
    }
    Else {
        Run, DeElevate "C:\Program Files\Everything 1.5a\Everything64.exe"
        WinWait ahk_exe Everything64.exe
        WinActivate
    }
Return
DetectHiddenWindows, Off

#IfWinActive ahk_class EVERYTHING
Esc::
!F4::
    If WinExist("ahk_class EVERYTHING_DROPDOWNLIST")
        WinClose
    WinHide
Return
#IfWinActive


; From http://www.howtogeek.com/howto/8955/make-backspace-in-windows-7-or-vista-explorer-go-up-like-xp-did/
; Fixed quotes
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


; Accelerated scrolling in MPC
; Shift+WheelUp/Down = Scroll by 10x
; https://autohotkey.com/board/topic/48426-accelerated-scrolling-script/?p=333222
; TODO: Need to merge with scroll control under mouse
; TODO: Alt+WheelUp/Down = Scroll horizontally
; #If (WinActive("ahk_exe explorer.exe") or WinActive("ahk_class PROCMON_WINDOW_CLASS") or WinActive("ahk_class MPC-BE") or WinActive("ahk_class MediaPlayerClassicW"))
#IfWinActive ahk_class MediaPlayerClassicW
; The length of a scrolling session. Keep scrolling within this time to accumulate boost. ; Default: 500. Recommended between 400 and 1000.
WheelUp::
WheelDown::
    timeout := 500
    ; If you scroll a long distance in one session, apply additional boost factor. The higher the ; value, the longer it takes to activate, and the slower it accumulates. ; Set to zero to disable ; completely. Default: 30.
    boost := 3
    ; Spamming applications with hundreds of individual scroll events can slow them down. This sets ; the maximum number of scrolls sent per click, i.e. max velocity. ; Default: 60.
    limit := 30
    distance := 0
    vmax := 1
    t := A_TimeSincePriorHotkey
    ; ToolTip, t %t% timeout 500
    ; ToolTip, timeout: %timeout%
    if (A_PriorHotkey = A_ThisHotkey && t < timeout) {
    ; if (A_PriorHotkey = A_ThisHotkey) {
       ; ToolTip, t: %t% timeout: 500
       ; t := A_TimeSincePriorHotkey
           distance++
           v := (t < 80 && t > 1) ? (250.0 / t) - 1 : 1
           if (boost > 1 && distance > boost)
           {
               if (v > vmax)
                   vmax := v
               else
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
    else {
           ; QuickToolTip("normal", 500)
           MouseClick, %A_ThisHotkey%
    }
    ; #If
Return
; +WheelDown::SendMessage,0x0111,904,,,ahk_class MediaPlayerClassicW
; +WheelUp::SendMessage,0x0111,903,,,ahk_class MediaPlayerClassicW 
; ~MWheel & RButton::
+WheelUp::Send {Click WheelUp 10}
+WheelDown::Send {Click WheelDown 10}
    ; ToolTip, WheelDown MPC
#IfWinActive
