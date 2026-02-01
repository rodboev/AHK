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

MB_Debug := 0 ; MButton scroll debug tooltips (0=off, 1=on)
WS_Debug := 1 ; Window spawning debug tooltips (0=off, 1=on)

; Disable hotkeys inside remote sessions (RDP, Hyper-V, VMWare)
#If IsRemoteSession()
  If !IsRemoteSession()
    WS_Init() ; Init window spawning
  Return
#If

; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === BINDINGS / REMAPS === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; ⇒ AutoHotkey (global bindings)
+!r::Reload ; [ ShIft+Alt+R ] -> Reload script
+!p::       ; [ ShIft+Alt+P ] -> Toggle pause script+suspend hotkeys
  Suspend
  Pause,,1
Return
+!e::Edit ; [ Shift+Alt+E ] -> Edit script (same as tray menu "Edit This Script")
#IfWinActive AutoHotkey.ahk
  ~^s::Reload ; [ Ctrl+S ] -> Reload script on save (in any editor)
#IfWinActive

; ⇒ Sublime Text (bindings/remaps)
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

; ⇒ VS Code / Cursor / Antigravity
#If (WinActive("ahk_exe code.exe") or WinActive("ahk_exe cursor.exe") or WinActive("ahk_exe antigravity.exe"))
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

; ⇒ Get which monitor the cursor is on (1-based)
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

; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ WINDOWS TERMINAL / ELEVATION ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

F10:: ; Open Windows Terminal in current Explorer path
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

+F10:: ; [ Shift+F10 ] -> Open with admin rights
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

^!+F10:: ; [ Ctrl+Alt+Shift+F10 ] -> Open Windows Terminal with SYSTEM rights
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

RemoveToolTip:
  ToolTip
Return

#F12::
MsgBox, F12 pressed 
    MouseGetPos, CursorX, CursorY, Window, ClassNN
    WinGetTitle, Title, ahk_id %Window%
    WinGetClass, ahk_class, ahk_id %Window%
    DetectHiddenText, On
    WinGetText, WindowText, ahk_id %Window%
    WinGet, WindowPID, PID, ahk_id %Window%
    WinGet, ControlText, ControlList, ahk_id %Window%
    CursorHwnd := DllCall("WindowFromPoint", "int64", CursorX | (CursorY << 32), "Ptr")

    ; UIA Element Info - with persistent global and error tracking
    UIA_Info := ""
    try {
        global G_UIA
        If (!G_UIA)
            G_UIA := ComObjCreate("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
        UIA_Info := "`nG_UIA: " G_UIA " (persistent)"

        ; ElementFromPoint (vtable index 7)
        uiaElement := 0
        hr := DllCall(NumGet(NumGet(G_UIA+0)+7*A_PtrSize), "Ptr", G_UIA, "Int64", CursorX | (CursorY << 32), "Ptr*", uiaElement)
        UIA_Info .= "`n  ElementFromPoint: hr=" hr " element=" uiaElement

        if (uiaElement) {
            ; CurrentControlType (vtable index 23)
            ctrlType := 0
            hr := DllCall(NumGet(NumGet(uiaElement+0)+23*A_PtrSize), "Ptr", uiaElement, "Int*", ctrlType)
            UIA_Info .= "`n  ControlType: " ctrlType " (hr=" hr ")"

            ; CurrentName (vtable index 24)
            pName := 0
            hr := DllCall(NumGet(NumGet(uiaElement+0)+24*A_PtrSize), "Ptr", uiaElement, "Ptr*", pName)
            elName := pName ? StrGet(pName, "UTF-16") : ""
            UIA_Info .= "`n  Name: " elName " (hr=" hr ")"

            ; GetCurrentPattern for ScrollPattern (ID 10004, vtable index 16)
            scrollPat := 0
            hr := DllCall(NumGet(NumGet(uiaElement+0)+16*A_PtrSize), "Ptr", uiaElement, "Int", 10004, "Ptr*", scrollPat)
            UIA_Info .= "`n  ScrollPattern: " (scrollPat ? "YES (" scrollPat ")" : "NO") " (hr=" hr ")"

            if (scrollPat) {
                ; CurrentVerticalScrollPercent (vtable index 6)
                vPct := 0.0
                hr := DllCall(NumGet(NumGet(scrollPat+0)+6*A_PtrSize), "Ptr", scrollPat, "Double*", vPct)
                UIA_Info .= "`n  VerticalScroll%%: " Round(vPct, 1) " (hr=" hr ")"
            }
        }
    } catch e {
        UIA_Info := "`nUIA: EXCEPTION - " e.Message
    }

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
%UIA_Info%
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

; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === EXTENDED WINDOW SPY === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; Description: Persistent tooltip showing window info (active + under cursor)
; Click tooltip or press #w again to freeze and show dialog for copying
; Forum link: https://autohotkey.com/boards/viewtopic.php?f=6&t=43544
; Author: @rodboev
; Version: 1.0
#w::
  Gui, WindowSpy:Destroy  ; Close dialog if open
  WindowSpyToggle := !WindowSpyToggle
  If (WindowSpyToggle) {
    WindowSpyLastContent := ""  ; Clear cache to force first update
    SetTimer, WindowSpyUpdate, 800
    GoSub, WindowSpyUpdate  ; Immediate first update
  } Else {
    SetTimer, WindowSpyUpdate, Off
    ToolTip
  }
Return

$Esc::
  ; Close WindowSpy dialog if open
  If WinExist("Window Spy (Esc to close)") {
    Gui, WindowSpy:Destroy
    Return
  }
  ; Close WindowSpy tooltip if active
  If (WindowSpyToggle) {
    SetTimer, WindowSpyUpdate, Off
    ToolTip
    WindowSpyToggle := false
    Return
  }
  ; Pass Esc through to active window
  Send {Esc}
Return

~LButton::
  If (WindowSpyToggle) {
    MouseGetPos,,, clickWin
    WinGetClass, clickClass, ahk_id %clickWin%
    If (clickClass = "tooltips_class32") {
      SetTimer, WindowSpyUpdate, Off
      ToolTip
      WindowSpyToggle := false
      WindowSpyShowDialog()
    }
  }
Return

WindowSpyShowDialog() {
  global WindowSpyRawInfo, WindowSpyEdit
  If (WindowSpyRawInfo = "")
    Return
  ToolTip  ; Destroy tooltip when showing dialog
  Gui, WindowSpy:Destroy
  SysGet, Workspace, MonitorWorkArea
  ; Count lines and calculate max dimensions based on workspace
  StringReplace, _, WindowSpyRawInfo, `n, `n, UseErrorLevel
  lineCount := ErrorLevel + 1
  maxHeight := WorkspaceBottom - WorkspaceTop - 50  ; Leave margin for title bar
  rowHeight := 22  ; Consolas 9pt + Edit control internal padding
  maxRows := Floor(maxHeight / rowHeight)
  rowCount := Min(lineCount, maxRows)
  editWidth := Min(700, WorkspaceRight - WorkspaceLeft - 100)
  Gui, WindowSpy:+AlwaysOnTop +Owner
  Gui, WindowSpy:Font, s9, Consolas
  Gui, WindowSpy:Add, Edit, vWindowSpyEdit w%editWidth% r%rowCount% +Multi +ReadOnly, %WindowSpyRawInfo%
  ; Show first to render and get dimensions, then reposition flush to bottom-right
  Gui, WindowSpy:Show,, Window Spy (Esc to close)
  WinGetPos,,, GUIWidth, GUIHeight, A
  xPos := WorkspaceRight - GUIWidth
  yPos := WorkspaceBottom - GUIHeight
  WinMove, A,, %xPos%, %yPos%
}

; Wrap list items at ~100 chars, preserving whole items
; Input: comma-separated string like "item1, item2, item3"
; Output: same items wrapped to fit maxLen, with continuation lines indented
WrapList(text, delimiter := ",", maxLen := 100) {
  result := ""
  currentLine := ""
  Loop, Parse, text, %delimiter%
  {
    item := Trim(A_LoopField)
    If (item = "")
      Continue
    ; Calculate what this line would look like with the new item
    testLine := currentLine = "" ? item : currentLine . ", " . item
    If (StrLen(testLine) > maxLen && currentLine != "") {
      ; Line would be too long, start a new line
      result .= (result = "" ? "" : "`n  ") . currentLine
      currentLine := item
    } Else {
      currentLine := testLine
    }
  }
  ; Add final line
  If (currentLine != "")
    result .= (result = "" ? "" : "`n  ") . currentLine
  Return result
}

; Clean window text: remove non-ASCII chars, deduplicate if long
CleanWindowText(text) {
  ; Remove non-ASCII characters (keep only printable ASCII 0x20-0x7E)
  cleaned := RegExReplace(text, "[^\x20-\x7E]", "")
  ; Collapse multiple spaces
  cleaned := RegExReplace(cleaned, "\s+", " ")
  cleaned := Trim(cleaned)

  ; If > 300 chars, deduplicate items
  If (StrLen(cleaned) > 300) {
    seen := {}
    result := ""
    Loop, Parse, cleaned, `,
    {
      item := Trim(A_LoopField)
      If (item != "" && !seen.HasKey(item)) {
        seen[item] := true
        result .= (result ? ", " : "") . item
      }
    }
    cleaned := result
  }
  Return cleaned
}

; Filter out items exceeding maxLen characters from comma-separated list
FilterLongItems(text, maxItemLen := 80) {
  result := ""
  Loop, Parse, text, `,
  {
    item := Trim(A_LoopField)
    If (item != "" && StrLen(item) <= maxItemLen)
      result .= (result ? ", " : "") . item
  }
  Return result
}

; Sort comma-separated items alphabetically
SortList(text) {
  sorted := ""
  Loop, Parse, text, `,
  {
    item := Trim(A_LoopField)
    If (item != "")
      sorted .= item . "`n"
  }
  Sort, sorted
  result := ""
  Loop, Parse, sorted, `n
  {
    If (A_LoopField != "")
      result .= (result ? ", " : "") . A_LoopField
  }
  Return result
}

WindowSpyGuiEscape:
WindowSpyGuiClose:
  Gui, WindowSpy:Destroy
Return

WindowSpyUpdate:
  CoordMode, Mouse, Screen
  CoordMode, ToolTip, Screen
  CoordMode, Pixel, Screen
  MouseGetPos, CursorX, CursorY, CursorWin, ClassNN

  ; Pause updates when hovering over our tooltip
  WinGetClass, hoverClass, ahk_id %CursorWin%
  WinGet, hoverExe, ProcessPath, ahk_id %CursorWin%
  If (hoverClass = "tooltips_class32" && hoverExe = A_AhkPath)
    Return

  DetectHiddenText, On

  ; === ACTIVE WINDOW ===
  WinGet, ActiveWin, ID, A
  WinGetTitle, ActiveTitle, ahk_id %ActiveWin%
  WinGetClass, ActiveClass, ahk_id %ActiveWin%
  WinGet, ActivePID, PID, ahk_id %ActiveWin%
  WinGetPos, ActiveX, ActiveY, ActiveW, ActiveH, ahk_id %ActiveWin%
  WinGet, ActiveStyle, Style, ahk_id %ActiveWin%
  WinGet, ActiveExStyle, ExStyle, ahk_id %ActiveWin%
  ControlGetFocus, ActiveFocusedControl, ahk_id %ActiveWin%
  ActiveFocusedHwnd := ""
  If (ActiveFocusedControl != "")
    ControlGet, ActiveFocusedHwnd, Hwnd,, %ActiveFocusedControl%, ahk_id %ActiveWin%
  activeExe := GetExePath("ahk_id " ActiveWin)
  activeMon := GetMonitor("ahk_id " ActiveWin)
  activeElevated := IsProcessElevated(ActivePID)
  activeCmdLine := ""
  For process in ComObjGet("winmgmts:").ExecQuery("Select CommandLine from Win32_Process where ProcessId=" . ActivePID)
    activeCmdLine := process.CommandLine
  WinGetText, ActiveWinText, ahk_id %ActiveWin%
  WinGet, ActiveControls, ControlList, ahk_id %ActiveWin%

  ; Format controls: comma-separated, filter >80 chars, sort alphabetically
  StringReplace, ActiveControlsRaw, ActiveControls, `r`n, `, , All
  StringReplace, ActiveControlsRaw, ActiveControlsRaw, `n, `, , All
  ActiveControlsRaw := SortList(FilterLongItems(ActiveControlsRaw))
  ActiveControlsDisplay := WrapList(ActiveControlsRaw, ",")
  ; Format window text: comma-separated, clean non-ASCII, filter >80 chars, dedupe if long
  StringReplace, ActiveWinTextRaw, ActiveWinText, `r`n, `, , All
  StringReplace, ActiveWinTextRaw, ActiveWinTextRaw, `n, `, , All
  ActiveWinTextRaw := RTrim(FilterLongItems(CleanWindowText(ActiveWinTextRaw)), ", ")
  ActiveWinTextDisplay := WrapList(ActiveWinTextRaw, ",")

  ; UIA for active window - just show persistent object reference
  ActiveUIA_Info := ""
  Try {
    global G_UIA
    If (!G_UIA)
      G_UIA := ComObjCreate("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
    ActiveUIA_Info := "UIA: " G_UIA
  } catch e {
    ActiveUIA_Info := "UIA: EXCEPTION - " e.Message
  }

  ; Build wrapped version for tooltip
  ActiveInfo := "=== ACTIVE WINDOW ===`n"
  ActiveInfo .= "Title: " ActiveTitle "`n"
  ActiveInfo .= "ahk_id: " ActiveWin " | ahk_class: " ActiveClass "`n"
  ActiveInfo .= "ahk_exe: " activeExe.path "`n"
  ActiveInfo .= "Dir: " activeExe.dir "`n"
  ActiveInfo .= "CmdLine: " WrapList(activeCmdLine, " ") "`n"
  ActiveInfo .= "PID: " ActivePID (activeElevated ? " (Elevated)" : "") " | Monitor: " activeMon "`n"
  ActiveInfo .= "Pos: (" ActiveX ", " ActiveY ") | Size: " ActiveW " x " ActiveH "`n"
  ActiveInfo .= "Style: " ActiveStyle " | ExStyle: " ActiveExStyle "`n"
  ActiveInfo .= "ScrollPattern: " MB_ScrollPattern "`n"
  ActiveInfo .= "Focused Control: " ActiveFocusedControl (ActiveFocusedHwnd ? " | hWnd: " ActiveFocusedHwnd : "") "`n"
  ActiveInfo .= ActiveUIA_Info "`n"
  ActiveInfo .= "Window Text: " ActiveWinTextDisplay "`n"
  ActiveInfo .= "Controls: " ActiveControlsDisplay "`n"

  ; Build raw version for dialog
  ActiveInfoRaw := "=== ACTIVE WINDOW ===`n"
  ActiveInfoRaw .= "Title: " ActiveTitle "`n"
  ActiveInfoRaw .= "ahk_id: " ActiveWin " | ahk_class: " ActiveClass "`n"
  ActiveInfoRaw .= "ahk_exe: " activeExe.path "`n"
  ActiveInfoRaw .= "Dir: " activeExe.dir "`n"
  ActiveInfoRaw .= "CmdLine: " activeCmdLine "`n"
  ActiveInfoRaw .= "PID: " ActivePID (activeElevated ? " (Elevated)" : "") " | Monitor: " activeMon "`n"
  ActiveInfoRaw .= "Pos: (" ActiveX ", " ActiveY ") | Size: " ActiveW " x " ActiveH "`n"
  ActiveInfoRaw .= "Style: " ActiveStyle " | ExStyle: " ActiveExStyle "`n"
  ActiveInfoRaw .= "Focused Control: " ActiveFocusedControl (ActiveFocusedHwnd ? " | hWnd: " ActiveFocusedHwnd : "") "`n"
  ActiveInfoRaw .= ActiveUIA_Info "`n"
  ActiveInfoRaw .= "Window Text: " ActiveWinTextRaw "`n"
  ActiveInfoRaw .= "Controls: " ActiveControlsRaw "`n"

  ; === WINDOW UNDER CURSOR ===
  WinGetTitle, CursorTitle, ahk_id %CursorWin%
  WinGetClass, CursorClass, ahk_id %CursorWin%
  WinGet, CursorPID, PID, ahk_id %CursorWin%
  WinGetPos, CursorWinX, CursorWinY, CursorWinW, CursorWinH, ahk_id %CursorWin%
  WinGet, CursorStyle, Style, ahk_id %CursorWin%
  WinGet, CursorExStyle, ExStyle, ahk_id %CursorWin%
  cursorExe := GetExePath("ahk_id " CursorWin)
  cursorMon := GetMonitor("ahk_id " CursorWin)
  cursorElevated := IsProcessElevated(CursorPID)
  CursorHwnd := DllCall("WindowFromPoint", "int64", CursorX | (CursorY << 32), "Ptr")
  cursorCmdLine := ""
  For process in ComObjGet("winmgmts:").ExecQuery("Select CommandLine from Win32_Process where ProcessId=" . CursorPID)
    cursorCmdLine := process.CommandLine
  WinGetText, CursorWinText, ahk_id %CursorWin%
  WinGet, CursorControls, ControlList, ahk_id %CursorWin%

  ; Format controls: comma-separated, filter >80 chars, sort alphabetically
  StringReplace, CursorControlsRaw, CursorControls, `r`n, `, , All
  StringReplace, CursorControlsRaw, CursorControlsRaw, `n, `, , All
  CursorControlsRaw := SortList(FilterLongItems(CursorControlsRaw))
  CursorControlsDisplay := WrapList(CursorControlsRaw, ",")
  ; Format window text: comma-separated, clean non-ASCII, filter >80 chars, dedupe if long
  StringReplace, CursorWinTextRaw, CursorWinText, `r`n, `, , All
  StringReplace, CursorWinTextRaw, CursorWinTextRaw, `n, `, , All
  CursorWinTextRaw := RTrim(FilterLongItems(CleanWindowText(CursorWinTextRaw)), ", ")
  CursorWinTextDisplay := WrapList(CursorWinTextRaw, ",")

  ; Cursor position relative to window
  CursorRelX := CursorX - CursorWinX
  CursorRelY := CursorY - CursorWinY

  ; UIA Element Info - just show if UIA is available
  UIA_Info := ""
  Try {
    global G_UIA
    If (!G_UIA)
      G_UIA := ComObjCreate("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
    UIA_Info := "UIA: " G_UIA
  } catch e {
    UIA_Info := "UIA: EXCEPTION - " e.Message
  }

  ; Build wrapped version for tooltip
  CursorInfo := "`n=== UNDER CURSOR ===`n"
  CursorInfo .= "Title: " CursorTitle "`n"
  CursorInfo .= "ahk_id: " CursorWin " | ahk_class: " CursorClass "`n"
  CursorInfo .= "ahk_exe: " cursorExe.path "`n"
  CursorInfo .= "Dir: " cursorExe.dir "`n"
  CursorInfo .= "CmdLine: " WrapList(cursorCmdLine, " ") "`n"
  CursorInfo .= "PID: " CursorPID (cursorElevated ? " (Elevated)" : "") " | Monitor: " cursorMon "`n"
  CursorInfo .= "Pos: (" CursorWinX ", " CursorWinY ") | Size: " CursorWinW " x " CursorWinH "`n"
  CursorInfo .= "Style: " CursorStyle " | ExStyle: " CursorExStyle "`n"
  CursorInfo .= "Control: " ClassNN " | hWnd: " CursorHwnd "`n"
  ; CursorInfo .= "Cursor: (" CursorX ", " CursorY ") | CursorRel: (" CursorRelX ", " CursorRelY ")`n"
  CursorInfo .= UIA_Info "`n"
  CursorInfo .= "Window Text: " CursorWinTextDisplay "`n"
  CursorInfo .= "Controls: " CursorControlsDisplay

  ; Build raw version for dialog
  CursorInfoRaw := "`n=== UNDER CURSOR ===`n"
  CursorInfoRaw .= "Title: " CursorTitle "`n"
  CursorInfoRaw .= "ahk_id: " CursorWin " | ahk_class: " CursorClass "`n"
  CursorInfoRaw .= "ahk_exe: " cursorExe.path "`n"
  CursorInfoRaw .= "Dir: " cursorExe.dir "`n"
  CursorInfoRaw .= "CmdLine: " cursorCmdLine "`n"
  CursorInfoRaw .= "PID: " CursorPID (cursorElevated ? " (Elevated)" : "") " | Monitor: " cursorMon "`n"
  CursorInfoRaw .= "Pos: (" CursorWinX ", " CursorWinY ") | Size: " CursorWinW " x " CursorWinH "`n"
  CursorInfoRaw .= "Style: " CursorStyle " | ExStyle: " CursorExStyle "`n"
  CursorInfoRaw .= "Control: " ClassNN " | hWnd: " CursorHwnd "`n"
  ; CursorInfoRaw .= "Cursor: (" CursorX ", " CursorY ") | CursorRel: (" CursorRelX ", " CursorRelY ")`n"
  CursorInfoRaw .= UIA_Info "`n"
  CursorInfoRaw .= "Window Text: " CursorWinTextRaw "`n"
  CursorInfoRaw .= "Controls: " CursorControlsRaw

  ; Store for tooltip and dialog
  global WindowSpyRawInfo, WindowSpyLastContent
  WindowSpyRawInfo := ActiveInfoRaw . CursorInfoRaw

  ; Only update tooltip if content changed (reduces flicker)
  newContent := ActiveInfo . CursorInfo
  If (newContent = WindowSpyLastContent)
    Return
  WindowSpyLastContent := newContent

  ; Position tooltip in bottom-right corner
  SysGet, Workspace, MonitorWorkArea
  tooltipHeader := "Window Spy (Click to copy, Esc or #w to close)`n`n"
  ToolTip, %tooltipHeader%%newContent%, WorkspaceRight - 550, WorkspaceBottom - 620
Return

; ==============================================================================================================

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

; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === EXPLORER SMOOTH SCROLL === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; Description: Super-smoooth, fractional scrolling in Explorer (and more) on middle mouse button drag, similar to Chrome
; Permalink (latest): https://github.com/rodboev/AHK/
; Forum thread: https://autohotkey.com/boards/viewtopic.php?t=43715
; Author: @rodboev
; Version: 2.2

; Get vertical scroll position for a control (cross-process safe)
GetScrollPos(hwnd) {
  Return DllCall("GetScrollPos", "Ptr", hwnd, "Int", 1, "Int")
}

; Check if a control has a Win32 vertical scrollbar (for fallback detection)
HasWin32Scrollbar(hwnd) {
  DllCall("GetScrollRange", "Ptr", hwnd, "Int", 1, "Int*", scrollMin, "Int*", scrollMax)
  Return (scrollMax > scrollMin)
}

$*MButton::
  global MBScroll_X1, MBScroll_Y1, MBScroll_Win, MBScroll_CtrlClassNN, MBScroll_Triggered
  global G_UIA, MB_ScrollPattern := 0, MB_Element := 0, MBScroll_Ctrl
  global MB_Disabled := 0, MB_DeferredDown := 0, MB_ViewSize := 10.0, MB_AccumPct := -1
  global MB_Method := "VSCROLL" ; Default fallback
  global MB_FallbackChecked := 0  ; Check fallback once per drag
  global MB_NativeProbe := 0, MB_InitScrollPos := 0, MB_InitScrollPct := 0.0, MB_InitHCursor := 0

  MouseGetPos,,, MBScroll_Win, MBScroll_CtrlClassNN
  WinGetClass, ahk_class, ahk_id %MBScroll_Win%

  ; EXCLUDED CONTROLS (toolbars, edit boxes, headers — never scroll these)
  MB_ExcludedControls := ["ToolbarWindow", "ReBarWindow", "Edit", "AddressBandRoot", "statusbar", "SysHeader", "Shell_TrayWnd", "Shell_SecondaryTrayWnd"]
  IsExcludedRegion := HasVal(MB_ExcludedControls, MBScroll_CtrlClassNN) or (not MBScroll_CtrlClassNN and not (ahk_class = "Shell_TrayWnd" or ahk_class = "WorkerW"))
  If (IsExcludedRegion) {
    MB_Disabled := 1
    SendInput, {Blind}{MButton Down}
    Return
  }

  ; Capture cursor handle before passing MButton to app (Chrome changes cursor immediately)
  ; Uses HCURSOR handle (not A_Cursor name) to detect custom cursor changes
  VarSetCapacity(ci, 16 + A_PtrSize, 0)
  NumPut(16 + A_PtrSize, ci, 0, "UInt")
  DllCall("GetCursorInfo", "Ptr", &ci)
  MB_InitHCursor := NumGet(ci, 8, "UPtr")

  ; Defer MButton Down for Explorer to prevent click actions during scroll
  ; (e.g., middle-clicking a navbar item opens a new tab before scroll starts)
  ; Non-Explorer apps get immediate passthrough for native scroll detection
  If (ahk_class = "CabinetWClass") {
    MB_DeferredDown := 1
  } Else {
    SendInput, {Blind}{MButton Down}
  }
  MB_Disabled := 0

  ; Activate Explorer window if clicking on inactive one
  If (ahk_class = "CabinetWClass") {
    WinGet, activeWin, ID, A
    If (MBScroll_Win != activeWin) {
      WinActivate, ahk_id %MBScroll_Win%
    }
  }

  ; Capture initial mouse coords
  CoordMode, Mouse, Screen
  MouseGetPos, MBScroll_X1, MBScroll_Y1

  ; Get control window handle (hwnd)
  ControlGet, MBScroll_Ctrl, Hwnd,, %MBScroll_CtrlClassNN%, ahk_id %MBScroll_Win%
  MBScroll_Triggered := 0

  ; TreeView controls → direct to VSCROLL (skip native probe, never has native MButton scroll)
  If (InStr(MBScroll_CtrlClassNN, "SysTreeView32")) {
    MB_Method := "VSCROLL"
    MB_NativeProbe := 0
    SetTimer, MBScrollTimer, 150
    Return
  }

  ; SET UP UIA (for both native scroll detection and potential custom scroll)
  If (!G_UIA)
    G_UIA := ComObjCreate("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
  targetForUIA := MBScroll_Ctrl ? MBScroll_Ctrl : MBScroll_Win
  DllCall(NumGet(NumGet(G_UIA+0)+6*A_PtrSize), "Ptr", G_UIA, "Ptr", targetForUIA, "Ptr*", MB_Element)
  If (MB_Element) {
    DllCall(NumGet(NumGet(MB_Element+0)+16*A_PtrSize), "Ptr", MB_Element, "Int", 10004, "Ptr*", MB_ScrollPattern)
    If (MB_ScrollPattern) {
      DllCall(NumGet(NumGet(MB_ScrollPattern+0)+8*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_ViewSize)
      If (MB_ViewSize < 1)
        MB_ViewSize := 10.0
    }
  }

  ; Capture initial scroll state for native detection
  probeTarget := MBScroll_Ctrl ? MBScroll_Ctrl : MBScroll_Win
  MB_InitScrollPos := GetScrollPos(probeTarget)
  MB_InitScrollPct := -1.0
  If (MB_ScrollPattern)
    DllCall(NumGet(NumGet(MB_ScrollPattern+0)+6*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_InitScrollPct)

  ; Start timer in native probe mode
  MB_NativeProbe := 1
  SetTimer, MBScrollTimer, 10
Return

MBScrollTimer:
  global MB_AccumPct, MB_Method, MB_ViewSize, MBScroll_Ctrl, MB_FallbackChecked
  global MB_NativeProbe, MB_InitScrollPos, MB_InitScrollPct, MB_InitHCursor
  ; Safety check: if MButton released, stop immediately
  If !GetKeyState("MButton", "P") {
    SetTimer, MBScrollTimer, Off
    If (MB_Debug)
      ToolTip
    Return
  }

  ; ===== NATIVE SCROLL PROBE PHASE =====
  ; Detect if the app handles MButton drag-scroll natively.
  ; Three signals: cursor change, Win32 scroll pos, UIA scroll percent.
  ; Movement-gated: cursor checked every tick; scroll pos checked after 3px; concludes at 8px.
  If (MB_NativeProbe > 0) {
    nativeDetected := false

    ; Signal 1: Cursor changed to a custom bitmap (e.g., Chrome/Firefox autoscroll icon)
    ; Requires A_Cursor = "Unknown" to ignore standard cursor changes (Explorer selection, etc.)
    VarSetCapacity(ci, 16 + A_PtrSize, 0)
    NumPut(16 + A_PtrSize, ci, 0, "UInt")
    DllCall("GetCursorInfo", "Ptr", &ci)
    If (NumGet(ci, 8, "UPtr") != MB_InitHCursor and A_Cursor = "Unknown")
      nativeDetected := true

    If (!nativeDetected) {
      CoordMode, Mouse, Screen
      MouseGetPos,, probeY
      probeDrag := Abs(probeY - MBScroll_Y1)

      ; Signals 2 & 3: check after 3px (filters cursor jitter)
      If (probeDrag >= 3) {
        ; Signal 2: Win32 scroll position changed
        probeTarget := MBScroll_Ctrl ? MBScroll_Ctrl : MBScroll_Win
        currentScrollPos := GetScrollPos(probeTarget)
        If (currentScrollPos != MB_InitScrollPos)
          nativeDetected := true

        ; Signal 3: UIA scroll percent changed
        If (!nativeDetected and MB_ScrollPattern) {
          DllCall(NumGet(NumGet(MB_ScrollPattern+0)+6*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", currentPct)
          If (currentPct != MB_InitScrollPct)
            nativeDetected := true
        }
      }

      ; Keep probing until 8px movement gate (matches custom scroll threshold)
      If (!nativeDetected and probeDrag < 8)
        Return
    }

    If (nativeDetected) {
      ; App handles MButton scroll natively — stay passive
      MB_Disabled := 1
      If (MB_ScrollPattern) {
        ObjRelease(MB_ScrollPattern)
        MB_ScrollPattern := 0
      }
      If (MB_Element) {
        ObjRelease(MB_Element)
        MB_Element := 0
      }
      SetTimer, MBScrollTimer, Off
      If (MB_Debug) {
        VarSetCapacity(ci2, 16 + A_PtrSize, 0)
        NumPut(16 + A_PtrSize, ci2, 0, "UInt")
        DllCall("GetCursorInfo", "Ptr", &ci2)
        ToolTip, % "Native scroll detected (hCursor=" NumGet(ci2, 8, "UPtr") " was=" MB_InitHCursor ")"
      }
      Return
    }

    ; No native scroll — engage custom scroll
    MB_NativeProbe := 0
    If (MB_ScrollPattern) {
      MB_Method := "UIA"
    } Else {
      If (MB_Element) {
        ObjRelease(MB_Element)
        MB_Element := 0
      }
      MB_Method := "WHEEL"
    }
    If (MB_Debug)
      ToolTip, % "No native scroll — using " MB_Method
    ; Fall through to custom scroll logic below
  }

  CoordMode, Mouse, Screen
  MouseGetPos,, Y2
  SignedDist := Y2 - MBScroll_Y1
  AbsDist := Abs(SignedDist)

  If (AbsDist >= 8) {
    MBScroll_Triggered := 1
    signDir := (SignedDist > 0) ? 1 : -1
    absEffective := AbsDist

    ; Double curve: responsive up to 100px, soft cap beyond
    If (absEffective <= 100) {
      curveValue := absEffective ** 0.8
    } Else {
      curveValue := (100 ** 0.8) + ((absEffective - 100) ** 0.6)
    }

    If (MB_Method = "UIA") {
      ; ===========================================
      ; UIA SCROLLING (auto-detected, fractional % via SetScrollPercent)
      ; Fallback: UIA → WHEEL if scroll is non-functional
      ; Two-tick verification: tick 1 captures before-state, tick 2 cross-validates
      ; ===========================================
      If (MB_AccumPct < 0) {
        DllCall(NumGet(NumGet(MB_ScrollPattern+0)+6*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_AccumPct)
      }

      ; Capture Win32 scroll position BEFORE UIA scroll (for cross-validation)
      If (MB_FallbackChecked = 0) {
        uiaTarget := MBScroll_Ctrl ? MBScroll_Ctrl : MBScroll_Win
        MB_UIAVerifyPos := GetScrollPos(uiaTarget)
      }

      ; Normalize scroll speed based on ViewSize:
      ; - ViewSize = 100%: only 1 item visible (small list), scroll FAST
      ; - ViewSize = 1%: 100 items visible (huge list), scroll SLOW
      ; Formula: mult = ViewSize / 3 (5x amplified from /15)
      ; Examples: ViewSize=50% → mult=16.7, ViewSize=15% → mult=5, ViewSize=3% → mult=1
      viewMultiplier := MB_ViewSize / 3.0
      viewMultiplier := Max(0.25, Min(viewMultiplier, 50.0))  ; Clamp 0.25x to 50x
      deltaPct := signDir * curveValue * 0.006 * viewMultiplier
      MB_AccumPct := MB_AccumPct + deltaPct
      MB_AccumPct := (MB_AccumPct < 0) ? 0 : (MB_AccumPct > 100) ? 100 : MB_AccumPct
      If (MB_Debug)
        ToolTip, % "UIA: " Round(MB_AccumPct, 1) "%% (view=" Round(MB_ViewSize,1) "%% mult=" Round(viewMultiplier,2) ")"
      DllCall(NumGet(NumGet(MB_ScrollPattern+0)+4*A_PtrSize), "Ptr", MB_ScrollPattern, "Double", -1.0, "Double", MB_AccumPct)

      ; Verify UIA is actually working (two-tick verification)
      If (MB_FallbackChecked = 0) {
        ; Tick 1: UIA scroll sent, advance to pending verification
        MB_FallbackChecked := -1
      } Else If (MB_FallbackChecked = -1) {
        ; Tick 2: verify UIA actually scrolled
        uiaFailed := false
        DllCall(NumGet(NumGet(MB_ScrollPattern+0)+6*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", verifyPct)
        If (verifyPct < -0.5) {
          uiaFailed := true  ; NoScroll sentinel (-1)
        } Else {
          ; Cross-validate: if control has a Win32 scrollbar, it should have moved
          uiaTarget := MBScroll_Ctrl ? MBScroll_Ctrl : MBScroll_Win
          If (HasWin32Scrollbar(uiaTarget)) {
            posAfter := GetScrollPos(uiaTarget)
            If (posAfter = MB_UIAVerifyPos)
              uiaFailed := true  ; Win32 scrollbar didn't budge
          }
        }

        If (uiaFailed) {
          ; UIA didn't actually scroll — release COM objects, fall to WHEEL
          ObjRelease(MB_ScrollPattern)
          MB_ScrollPattern := 0
          ObjRelease(MB_Element)
          MB_Element := 0
          MB_Method := "WHEEL"
          MB_FallbackChecked := 0
          If (MB_Debug)
            ToolTip, % "UIA->WHEEL (didn't scroll)"
        } Else {
          MB_FallbackChecked := 1
        }
      }

    } Else If (MB_Method = "WHEEL_CTRL") {
      ; ===========================================
      ; WM_MOUSEWHEEL to CONTROL with GetScrollPos fallback
      ; No fractional scrolling, better acceleration than WM_VSCROLL
      ; ===========================================
      target := MBScroll_Ctrl ? MBScroll_Ctrl : MBScroll_Win

      ; Get position BEFORE scroll (only on first check)
      If (!MB_FallbackChecked) {
        posBefore := GetScrollPos(target)
      }

      ; Send WHEEL message
      lParam := ((MBScroll_Y1 & 0xFFFF) << 16) | (MBScroll_X1 & 0xFFFF)
      magnitude := Max(1, Min(119, Floor(curveValue / 2)))
      Delta := (SignedDist > 0) ? -magnitude : magnitude
      wParam := Delta << 16
      PostMessage, 0x20A, %wParam%, %lParam%,, ahk_id %target%

      ; Check for fallback on first scroll only
      If (!MB_FallbackChecked) {
        Sleep, 10  ; Brief pause for scroll to complete
        posAfter := GetScrollPos(target)
        scrolledUnits := Abs(posAfter - posBefore)

        ; If jumped >40 units (typically >1 line), switch to VSCROLL
        If (scrolledUnits > 40) {
          MB_Method := "VSCROLL"
          SetTimer, MBScrollTimer, 150
          ; Revert the jump by scrolling opposite direction
          revertDir := (posAfter > posBefore) ? 0 : 1  ; 0=up, 1=down
          PostMessage, 0x115, %revertDir%, 0,, ahk_id %target%
          If (MB_Debug)
            ToolTip, % "WHEEL_CTRL→VSCROLL (jumped " scrolledUnits " units)"
        }
        MB_FallbackChecked := 1
      }

      If (MB_Debug && MB_Method = "WHEEL_CTRL")
        ToolTip, % "WHEEL_CTRL: d=" Delta

    } Else If (MB_Method = "VSCROLL") {
      ; ===========================================
      ; WM_VSCROLL LINE - dynamic timer based on drag distance
      ; No fractional scrolling, most compatible
      ; ===========================================
      scrollDir := (SignedDist > 0) ? 1 : 0
      target := MBScroll_Ctrl ? MBScroll_Ctrl : MBScroll_Win

      ; Dynamic timer: 300ms at 8px (slow), 20ms at 300px+ (fast)
      ; Map AbsDist 8-200 to timer 20-300
      timerMs := 300 - Floor((Min(AbsDist, 300) - 8) * (100 / 192))
      timerMs := Max(20, Min(300, timerMs / 2))
      SetTimer, MBScrollTimer, %timerMs%

      If (MB_Debug)
        ToolTip, % "VSCROLL: dir=" scrollDir " timer=" timerMs "ms"
      PostMessage, 0x115, %scrollDir%, 0,, ahk_id %target%

    } Else {
      ; ===========================================
      ; WM_MOUSEWHEEL to WINDOW (Electron apps, auto-detected default)
      ; Fallback: WHEEL → WHEEL_CTRL if window-level message doesn't scroll
      ; ===========================================
      lParam := ((MBScroll_Y1 & 0xFFFF) << 16) | (MBScroll_X1 & 0xFFFF)
      ; MUST cap below 120 for smooth scrolling (120 = 1 notch = 3 lines)
      magnitude := Max(1, Min(119, Floor(curveValue / 2)))
      Delta := (SignedDist > 0) ? -magnitude : magnitude
      wParam := Delta << 16

      If (!MB_FallbackChecked) {
        ; Test if window-level WHEEL actually scrolls (first scroll only)
        ctrlTarget := MBScroll_Ctrl ? MBScroll_Ctrl : MBScroll_Win
        posBefore := GetScrollPos(ctrlTarget)
        PostMessage, 0x20A, %wParam%, %lParam%,, ahk_id %MBScroll_Win%
        Sleep, 15
        posAfter := GetScrollPos(ctrlTarget)
        If (posBefore = posAfter) {
          ; No movement detected — try sending to control directly
          MB_Method := "WHEEL_CTRL"
          MB_FallbackChecked := 0
          If (MB_Debug)
            ToolTip, % "WHEEL->WHEEL_CTRL (no movement)"
        } Else {
          MB_FallbackChecked := 1
        }
      } Else {
        PostMessage, 0x20A, %wParam%, %lParam%,, ahk_id %MBScroll_Win%
      }

      If (MB_Debug && MB_Method = "WHEEL")
        ToolTip, % "WHEEL: d=" Delta
    }
  }
Return

$*MButton Up::
  global MB_Disabled, MB_DeferredDown, MBScroll_Triggered, MBScroll_Win, MB_ScrollPattern, MB_Element
  SetTimer, MBScrollTimer, Off
  If (MB_Debug)
    ToolTip

  ; Release UIA objects
  If (MB_ScrollPattern) {
    ObjRelease(MB_ScrollPattern)
    MB_ScrollPattern := 0
  }
  If (MB_Element) {
    ObjRelease(MB_Element)
    MB_Element := 0
  }

  ; Release MButton to app
  If (MB_DeferredDown) {
    ; Explorer: MButton Down was deferred — only send click if no scroll occurred
    If (!MBScroll_Triggered) {
      SendInput, {Blind}{MButton}
    }
  } Else {
    ; Non-Explorer: MButton Down was already sent, send Up to complete
    SendInput, {Blind}{MButton Up}
  }
Return

; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === SPAWN WINDOWS ON CURRENT MONITOR === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; Shell hook intercepts new window creation and moves the window
; to whichever monitor the cursor is on. WinEvent hooks (EVENT_OBJECT_SHOW,
; EVENT_OBJECT_UNCLOAKED) detect when deferred windows become visible,
; replacing timer-based polling with event-driven detection.

WS_Init() {
  global
  WS_LastDestroyTick := 0
  WS_LastForegroundHwnd := 0
  WS_OverlayTick := 0             ; A_TickCount when non-movable overlay activated (0 = none)
  WS_Pending := {}            ; Deferred windows: hwnd -> {mon, tick}
  WS_PendingAltTab := ""      ; Alt+Tab: {mon, tick} or ""
  WS_PrePending := {}         ; Phase 10: CREATE pre-registration: hwnd -> {mon, tick, qpc}
  WS_Hidden := {}             ; Phase 10: opacity-hidden windows: hwnd -> hadLayered (bool)
  WS_OwnerSentinel := {}      ; Phase 10: owner hwnd -> A_TickCount (sibling CREATE suppression)
  DllCall("QueryPerformanceFrequency", "Int64*", WS_QPCFreq)
  WS_LogFile := A_Temp . "\WS_Debug.log"
  WS_ExcludedClasses := ["tooltips_class32", "NotifyIconOverflowWindow"
    , "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "Progman", "WorkerW"
    , "MultitaskingViewFrame", "Windows.UI.Core.CoreWindow", "ForegroundStaging"]
  ; Shell hook for window creation/activation detection
  Gui, ShellHook:+LastFound
  Gui, ShellHook:Show, Hide
  WS_HookHwnd := WinExist()
  WS_HookOK := DllCall("RegisterShellHookWindow", "Ptr", WS_HookHwnd)
  WS_HookMsg := DllCall("RegisterWindowMessage", "Str", "SHELLHOOK")
  if (WS_HookOK && WS_HookMsg > 0)
    OnMessage(WS_HookMsg, "WS_OnShellHook")
  else
    WS_Log("ERROR: Shell hook failed — Hook=" . WS_HookOK . " Msg=" . WS_HookMsg)
  ; WinEvent hooks for instant visibility/uncloak detection (UWP apps)
  DllCall("ole32\CoInitialize", "Ptr", 0)
  WS_WinEventCB := RegisterCallback("WS_OnWinEvent", "", 7)
  WS_EventHookShow := DllCall("SetWinEventHook"
    , "UInt", 0x8002, "UInt", 0x8002   ; EVENT_OBJECT_SHOW
    , "Ptr", 0, "Ptr", WS_WinEventCB
    , "UInt", 0, "UInt", 0, "UInt", 0x0002, "Ptr")
  WS_EventHookUncloak := DllCall("SetWinEventHook"
    , "UInt", 0x8018, "UInt", 0x8018   ; EVENT_OBJECT_UNCLOAKED
    , "Ptr", 0, "Ptr", WS_WinEventCB
    , "UInt", 0, "UInt", 0, "UInt", 0x0002, "Ptr")
  ; Phase 10: Hook CREATE for pre-visibility positioning
  WS_EventHookCreate := DllCall("SetWinEventHook"
    , "UInt", 0x8000, "UInt", 0x8000   ; EVENT_OBJECT_CREATE
    , "Ptr", 0, "Ptr", WS_WinEventCB
    , "UInt", 0, "UInt", 0, "UInt", 0x0002, "Ptr")
  if (WS_Debug) {
    FileDelete, %WS_LogFile%
    WS_Log("INIT: SHOW=" . (WS_EventHookShow ? "OK" : "FAIL")
      . " UNCLOAK=" . (WS_EventHookUncloak ? "OK" : "FAIL")
      . " CREATE=" . (WS_EventHookCreate ? "OK" : "FAIL"))
  }
  ; Phase 10: Periodic cleanup of stale PrePending entries (every 5s)
  SetTimer, WS_CleanPrePending, 1000
  OnExit("WS_Cleanup")
}

WS_OnShellHook(wParam, lParam, msg, hwnd) {
  ; HSHELL_WINDOWCREATED=1, HSHELL_WINDOWACTIVATED=4, HSHELL_RUDEAPPACTIVATED=0x8004
  isCreated := (wParam == 1)
  isActivated := (wParam == 4 || wParam == 0x8004)
  isDestroyed := (wParam == 2)
  if (!isCreated && !isActivated && !isDestroyed)
    return
  SetWinDelay, -1  ; No delay between window commands (AHK default is 100ms)
  global WS_Debug, WS_LastDestroyTick, WS_LastForegroundHwnd, WS_OverlayTick, WS_Pending, WS_PrePending, WS_QPCFreq, WS_Hidden, WS_OwnerSentinel

  ; Track foreground window destruction to suppress Z-order fallback activation.
  ; Only the foreground window's close triggers Z-order fallback — background/transient
  ; windows (e.g., single-instance app second process) don't cause fallback activation.
  if (isDestroyed) {
    if (lParam == WS_LastForegroundHwnd)
      WS_LastDestroyTick := A_TickCount
    if (WS_Debug && lParam == WS_LastForegroundHwnd) {
      WinGetTitle, dbgTitle, ahk_id %lParam%
      WS_Log("DESTROYED (fg): hwnd=" . lParam . " """ . dbgTitle . """")
    }
    WS_Pending.Delete(lParam + 0)
    WS_PrePending.Delete(lParam + 0)
    WS_Hidden.Delete(lParam + 0)  ; No reveal needed — window is gone
    return
  }

  cursorMon := GetCursorMonitor()

  ; --- Activation path: move existing window to cursor's monitor ---
  if (isActivated) {
    _actMovable := WS_IsMovable(lParam)
    if (WS_Debug) {
      WinGetClass, _dbgActClass, ahk_id %lParam%
      WinGet, _dbgActExe, ProcessName, ahk_id %lParam%
      WS_Log("ACTIVATE: hwnd=" . lParam . " class=" . _dbgActClass . " exe=" . _dbgActExe
        . " movable=" . _actMovable)
    }
    ; Ignore system windows (Start menu, tool windows, excluded classes).
    ; Record overlay timestamp for guard #2 bounce-back detection.
    ; Empty-class infrastructure windows fire before every activation — they signal
    ; that something briefly took focus (Start menu, overlays, UWP cascades).
    ; Guard #2 uses lParam == WS_LastForegroundHwnd to distinguish bounce-back from
    ; genuine switches, so setting WS_OverlayTick broadly is safe.
    if (!_actMovable) {
      WinGetClass, _nmClass, ahk_id %lParam%
      ; Infrastructure windows with no class fire before every activation sequence.
      ; Set overlay tick so Guard #2 can detect same-window bounce-back.
      if (_nmClass == "") {
        WS_OverlayTick := A_TickCount
        if (WS_Debug)
          WS_Log("OVERLAY (infra): hwnd=" . lParam)
        return
      }
      ; Taskbar activation: set overlay tick for Start button / taskbar interaction bounce-back.
      ; Safe: different-window clicks don't match Guard #2 (lParam != WS_LastForegroundHwnd);
      ; same-window taskbar clicks are caught by Guard #6 (cursor over taskbar).
      if (_nmClass == "Shell_TrayWnd" || _nmClass == "Shell_SecondaryTrayWnd") {
        WS_OverlayTick := A_TickCount
        if (WS_Debug)
          WS_Log("OVERLAY (taskbar): class=" . _nmClass . " hwnd=" . lParam)
        return
      }
      ; UWP apps activate their own CoreWindow internally — only count as overlay
      ; if it belongs to explorer.exe (Action Center) or StartMenuExperienceHost.exe.
      ; UWP apps use split-process (ApplicationFrameHost.exe + app.exe), so PID check won't work.
      if (_nmClass == "Windows.UI.Core.CoreWindow") {
        WinGet, _nmExe, ProcessName, ahk_id %lParam%
        if (_nmExe != "explorer.exe" && _nmExe != "StartMenuExperienceHost.exe")
          return
      }
      WS_OverlayTick := A_TickCount
      if (WS_Debug) {
        if (!_nmExe) {
          WinGet, _nmExe, ProcessName, ahk_id %lParam%
        }
        WS_Log("OVERLAY: class=" . _nmClass . " exe=" . _nmExe . " hwnd=" . lParam)
      }
      return
    }
    ; Guard #2: Skip re-activation of the same window after overlay or Start menu.
    if (lParam == WS_LastForegroundHwnd) {
      ; Check A: Recent overlay signal (empty-class infrastructure, taskbar, CoreWindow).
      ; Two timing bands: 0-2000ms = bounce-back → block; >2000ms = user launched → allow.
      if (WS_OverlayTick) {
        _overlayElapsed := A_TickCount - WS_OverlayTick
        if (_overlayElapsed < 2000) {
          WS_OverlayTick := 0
          if (WS_Debug) {
            WinGetTitle, dbgTitle, ahk_id %lParam%
            WS_Log("SKIP (overlay-bounce): """ . dbgTitle . """ overlay " . _overlayElapsed . "ms ago")
          }
          return
        }
      }
      ; Check B: Start menu currently visible — direct detection via DWM cloaked state.
      ; The Start menu doesn't fire HSHELL_WINDOWACTIVATED, but it must still be visible
      ; when the bounce-back activation fires (the activation is caused by its dismissal).
      _smHwnd := WinExist("ahk_exe StartMenuExperienceHost.exe")
      if (_smHwnd) {
        VarSetCapacity(_cloaked, 4, 0)
        DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", _smHwnd, "UInt", 14, "Ptr", &_cloaked, "UInt", 4)
        if (!NumGet(_cloaked, 0, "UInt")) {
          WS_OverlayTick := 0
          if (WS_Debug) {
            WinGetTitle, dbgTitle, ahk_id %lParam%
            WS_Log("SKIP (startmenu-open): """ . dbgTitle . """")
          }
          return
        }
      }
    }
    WS_OverlayTick := 0
    ; Save previous foreground before updating tracker
    prevHwnd := WS_LastForegroundHwnd
    WS_LastForegroundHwnd := lParam
    ; Skip auto-activation after window close (system Z-order fallback, not user action)
    if (A_TickCount - WS_LastDestroyTick < 500) {
      if (WS_Debug) {
        WinGetTitle, dbgTitle, ahk_id %lParam%
        WS_Log("SKIP (activate-destroy): """ . dbgTitle . """ within " . (A_TickCount - WS_LastDestroyTick) . "ms of close")
      }
      return
    }
    ; Skip auto-activation after window minimize (system Z-order fallback, not user action)
    if (prevHwnd) {
      WinGet, prevMinMax, MinMax, ahk_id %prevHwnd%
      if (prevMinMax == -1) {
        if (WS_Debug) {
          WinGetTitle, dbgTitle, ahk_id %lParam%
          WS_Log("SKIP (activate-minimize): """ . dbgTitle . """ prev window minimized")
        }
        return
      }
    }
    ; Skip if cursor is over the taskbar (user clicked a taskbar button)
    MouseGetPos,,, mouseWin
    WinGetClass, mouseClass, ahk_id %mouseWin%
    if (mouseClass == "Shell_TrayWnd" || mouseClass == "Shell_SecondaryTrayWnd") {
      if (WS_Debug) {
        WinGetTitle, dbgTitle, ahk_id %lParam%
        WS_Log("SKIP (activate-taskbar): """ . dbgTitle . """ cursor over taskbar")
      }
      return
    }
    windowMon := GetMonitor("ahk_id " . lParam)
    if (windowMon == cursorMon)
      return  ; Already on correct monitor — silent, no tooltip
    WS_MoveToMonitor(lParam, windowMon, cursorMon)
    if (WS_Debug) {
      WinGetTitle, dbgTitle, ahk_id %lParam%
      WS_Log("MOVED (activate): """ . dbgTitle . """ mon " . windowMon . " -> " . cursorMon)
    }
    return
  }

  ; --- Creation path: new window ---

  ; Phase 10: Use pre-registered target from CREATE event if available
  if (WS_PrePending.HasKey(lParam + 0)) {
    ppEntry := WS_PrePending.Delete(lParam + 0)
    if (WS_Debug) {
      ctDeltaUs := Round((WS_QPC() - ppEntry.qpc) * 1000000 / WS_QPCFreq)
      WS_Log("SHELL: hwnd=" . lParam . " create-to-shell=" . ctDeltaUs . "µs")
    }
    targetMon := ppEntry.mon
    ; Try to move immediately using pre-registered target
    if (WS_IsReady(lParam)) {
      if (WS_IsMovable(lParam)) {
        windowMon := GetMonitor("ahk_id " . lParam)
        if (windowMon != targetMon) {
          WS_MoveToMonitor(lParam, windowMon, targetMon)
          if (WS_Debug) {
            WinGetTitle, dbgTitle, ahk_id %lParam%
            WS_Log("MOVED (create-shell): """ . dbgTitle . """ mon " . windowMon . " -> " . targetMon . " +" . (A_TickCount - ppEntry.tick) . "ms")
          }
        } else if (WS_Debug) {
          WinGetTitle, dbgTitle, ahk_id %lParam%
          WS_Log("OK (create-shell): """ . dbgTitle . """ already on mon " . windowMon)
        }
        WS_Reveal(lParam)
        if (WS_Debug) {
          WS_Log("SHELL-DONE: hwnd=" . lParam . " hex=" . Format("0x{:08X}", lParam + 0)
            . " HasKey=" . WS_Hidden.HasKey(lParam + 0)
            . " val=" . (WS_Hidden.HasKey(lParam + 0) ? WS_Hidden[lParam + 0] : "N/A"))
        }
        return
      }
      WinGetTitle, chkTitle, ahk_id %lParam%
      if (chkTitle != "") {
        WS_Reveal(lParam)  ; Permanently excluded — still reveal
        return
      }
    }
    ; Not ready — defer with pre-registered target
    WS_Pending[lParam + 0] := {mon: targetMon, tick: ppEntry.tick}
    fn := Func("WS_BackupPoll").Bind(lParam + 0)
    SetTimer, %fn%, -200
    fn2 := Func("WS_TimeoutPending").Bind(lParam + 0)
    SetTimer, %fn2%, -2000
    if (WS_Debug) {
      WinGetTitle, dbgTitle, ahk_id %lParam%
      WinGetClass, dbgClass, ahk_id %lParam%
      WS_Log("DEFERRED (create-path): hwnd=" . lParam . " """ . dbgTitle . """ class=" . dbgClass)
    }
    return
  }

  ; Fallback: no CREATE pre-registration (window missed by CREATE hook)
  if (WS_IsReady(lParam)) {
    if (WS_IsMovable(lParam)) {
      windowMon := GetMonitor("ahk_id " . lParam)
      if (windowMon != cursorMon) {
        WS_MoveToMonitor(lParam, windowMon, cursorMon)
        if (WS_Debug) {
          WinGetTitle, dbgTitle, ahk_id %lParam%
          WS_Log("MOVED (instant): """ . dbgTitle . """ mon " . windowMon . " -> " . cursorMon)
        }
      } else if (WS_Debug) {
        WinGetTitle, dbgTitle, ahk_id %lParam%
        WS_Log("OK (instant): """ . dbgTitle . """ already on mon " . windowMon)
      }
      WS_Reveal(lParam)  ; Safety net for CREATE-hidden windows consumed by SHOW before shell hook
      return
    }
    WinGetTitle, chkTitle, ahk_id %lParam%
    if (chkTitle != "") {
      WS_Reveal(lParam)  ; Permanently excluded but might be hidden
      return
    }
  }
  WS_Pending[lParam + 0] := {mon: cursorMon, tick: A_TickCount}
  fn := Func("WS_BackupPoll").Bind(lParam + 0)
  SetTimer, %fn%, -200
  fn2 := Func("WS_TimeoutPending").Bind(lParam + 0)
  SetTimer, %fn2%, -2000
  if (WS_Debug) {
    WinGetTitle, dbgTitle, ahk_id %lParam%
    WinGetClass, dbgClass, ahk_id %lParam%
    WS_Log("DEFERRED: hwnd=" . lParam . " """ . dbgTitle . """ class=" . dbgClass)
  }
}

; WinEvent callback — fires when any window becomes visible (SHOW) or uncloaked (UNCLOAK)
WS_OnWinEvent(hHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) {
  global WS_Pending, WS_PendingAltTab, WS_Debug, WS_PrePending, WS_QPCFreq, WS_Hidden, WS_OwnerSentinel
  ; WinEventProc uses 32-bit LONG params, but AHK reads 64-bit register slots on x64.
  ; Upper 32 bits may contain junk — mask to lower 32 before comparing.
  idObject := idObject & 0xFFFFFFFF
  idChild := idChild & 0xFFFFFFFF
  if (idObject != 0 || idChild != 0 || !hwnd)  ; OBJID_WINDOW = 0
    return
  SetWinDelay, -1
  hwnd := hwnd + 0  ; Ensure numeric type for consistent object key lookup

  ; --- Phase 10: CREATE pre-registration + early positioning ---
  if (event == 0x8000) {  ; EVENT_OBJECT_CREATE
    ; Filter to top-level root windows only (CREATE fires for all objects)
    if (DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr") != hwnd)  ; GA_ROOT=2
      return
    ; Skip transient windows with no class (message-only, DDE, internal Win32 objects)
    WinGetClass, _createClass, ahk_id %hwnd%
    if (_createClass == "")
      return
    if (WS_Debug) {
      WinGetClass, _dbgCls, ahk_id %hwnd%
      if (_dbgCls == "#32770") {
        _dbgKeys := ""
        for _k, _v in WS_Hidden
          _dbgKeys .= Format("{}({}) ", _k, _v)
        _dbgOwner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")
        WS_Log("CREATE-DIAG: hwnd=" . hwnd . " hex=" . Format("0x{:08X}", hwnd)
          . " class=" . _dbgCls . " owner=" . Format("0x{:08X}", _dbgOwner)
          . " HasKey=" . WS_Hidden.HasKey(hwnd) . " keys=[" . _dbgKeys . "]")
      }
    }
    if (WS_Hidden.HasKey(hwnd)) {
      if (WS_Debug) {
        WinGetClass, dbgClass, ahk_id %hwnd%
        WS_Log("CREATE-SKIP: hwnd=" . hwnd . " class=" . dbgClass . " (sentinel)")
      }
      return
    }
    ; Phase 10: Owner sentinel — if this window's owner was recently moved, skip (sibling protection)
    ppOwner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")  ; GW_OWNER=4
    if (ppOwner && WS_OwnerSentinel.HasKey(ppOwner + 0)) {
      if (A_TickCount - WS_OwnerSentinel[ppOwner + 0] < 200) {
        WS_Hidden[hwnd] := -1
        if (WS_Debug) {
          WinGetClass, dbgClass, ahk_id %hwnd%
          WS_Log("CREATE-SKIP-OWNER: hwnd=" . hwnd . " class=" . dbgClass
            . " owner=" . Format("0x{:08X}", ppOwner) . " (sibling sentinel)")
        }
        return
      }
    }
    if (ppOwner) {
      ; Owner already processed by us (sentinel) → skip child windows (e.g., WTL tab controls)
      if (WS_Hidden.HasKey(ppOwner + 0) && WS_Hidden[ppOwner + 0] == -1) {
        if (WS_Debug) {
          WinGetClass, dbgClass, ahk_id %hwnd%
          WS_Log("CREATE-SKIP-CHILD: hwnd=" . hwnd . " class=" . dbgClass
            . " owner=" . Format("0x{:08X}", ppOwner) . " (owner sentinel)")
        }
        return
      }
      WinGet, ppOwnerStyle, Style, ahk_id %ppOwner%
      if (ppOwnerStyle & 0x10000000)  ; Owner is WS_VISIBLE → real dialog, skip
        return
      ; Owner is hidden → treat as top-level (e.g., Win+R Run dialog)
    }
    cursorMon := GetCursorMonitor()
    windowMon := GetMonitor("ahk_id " . hwnd)
    WS_PrePending[hwnd] := {mon: cursorMon, tick: A_TickCount, qpc: WS_QPC()}
    ; Suppress visibility until shell hook does proper relative-position move then reveals.
    ; Window stays at its natural position — no pre-positioning, so WinGetPos is accurate later.
    ; Skip UWP/cloaked windows — they use DirectComposition, not GDI. DWM cloaking already hides them.
    ppDidHide := false
    if (windowMon && windowMon != cursorMon) {
      VarSetCapacity(ppCloaked, 4, 0)
      DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Ptr", &ppCloaked, "UInt", 4)
      if (!NumGet(ppCloaked, 0, "UInt")) {
        ppExStyle := DllCall("GetWindowLong", "Ptr", hwnd, "Int", -20)  ; GWL_EXSTYLE
        hadLayered := !!(ppExStyle & 0x80000)  ; WS_EX_LAYERED
        if (!hadLayered)
          DllCall("SetWindowLong", "Ptr", hwnd, "Int", -20, "Ptr", ppExStyle | 0x80000)
        DllCall("SetLayeredWindowAttributes", "Ptr", hwnd, "UInt", 0
          , "UChar", WS_Debug ? 128 : 0, "UInt", 0x2)  ; LWA_ALPHA: 50% debug, 0% normal
        WS_Hidden[hwnd] := hadLayered
        ppDidHide := true
      }
    }
    if (WS_Debug) {
      WinGetClass, dbgClass, ahk_id %hwnd%
      hideLabel := ppDidHide ? " hide" : ""
      WS_Log("CREATE: hwnd=" . hwnd . " class=" . dbgClass . hideLabel . " mon " . cursorMon
        . (windowMon && windowMon != cursorMon ? " (from " . windowMon . ")" : ""))
    }
    return
  }

  ; --- Phase 10: PrePending SHOW/UNCLOAK fast path ---
  if (WS_PrePending.HasKey(hwnd)) {
    ppEntry := WS_PrePending.Delete(hwnd)
    if (WS_Debug) {
      deltaTick := A_TickCount - ppEntry.tick
      deltaUs := Round((WS_QPC() - ppEntry.qpc) * 1000000 / WS_QPCFreq)
      evName := (event == 0x8002) ? "SHOW" : "UNCLOAK"
      WinGetTitle, dbgTitle, ahk_id %hwnd%
      WinGetClass, dbgClass, ahk_id %hwnd%
      WS_Log(evName . ": hwnd=" . hwnd . " """ . dbgTitle . """ class=" . dbgClass
        . " create-to-" . evName . "=" . deltaTick . "ms (" . deltaUs . "µs)")
    }
    ; Move to target using current (real) position — window was never pre-positioned
    if (WS_IsReady(hwnd) && WS_IsMovable(hwnd)) {
      windowMon := GetMonitor("ahk_id " . hwnd)
      if (windowMon != ppEntry.mon) {
        WS_MoveToMonitor(hwnd, windowMon, ppEntry.mon)
        if (WS_Debug) {
          elapsed := A_TickCount - ppEntry.tick
          WinGetTitle, dbgTitle, ahk_id %hwnd%
          WS_Log("MOVED (create-show): """ . dbgTitle . """ mon " . windowMon . " -> " . ppEntry.mon . " +" . elapsed . "ms")
        }
      } else if (WS_Debug) {
        WinGetTitle, dbgTitle, ahk_id %hwnd%
        WS_Log("OK (create-show): """ . dbgTitle . """ already on mon " . windowMon)
      }
      WS_Reveal(hwnd)
      ; Successfully processed — clean up any shell hook deferral too
      WS_Pending.Delete(hwnd)
      return
    }
    ; Not ready or not movable yet — fall through to WS_Pending handler
    ; (shell hook may have deferred this window; let existing logic handle it)
  }

  ; --- Pending creation moves ---
  if (WS_Pending.HasKey(hwnd)) {
    if (WS_IsReady(hwnd)) {
      if (WS_IsMovable(hwnd)) {
        entry := WS_Pending.Delete(hwnd)
        evName := (event == 0x8002) ? "show" : "uncloak"
        WS_ProcessPending(hwnd, entry.mon, evName, entry.tick)
      } else {
        ; Ready but not movable — discard if permanently excluded (has title)
        WinGetTitle, chkTitle, ahk_id %hwnd%
        if (chkTitle != "")
          WS_Pending.Delete(hwnd)
        ; else: no title yet — leave in pending for backup poll
      }
    }
    ; Not ready at all — leave in pending for UNCLOAK or backup poll
    return
  }

  ; --- Pending Alt+Tab ---
  if (WS_PendingAltTab != "") {
    WinGetClass, cls, ahk_id %hwnd%
    if (cls == "XamlExplorerHostIslandWindow") {
      entry := WS_PendingAltTab
      WS_PendingAltTab := ""
      windowMon := GetMonitor("ahk_id " . hwnd)
      if (windowMon != entry.mon)
        WS_MoveToMonitor(hwnd, windowMon, entry.mon)
    }
  }
}

; Process a deferred window that is now ready
WS_ProcessPending(hwnd, targetMon, source:="event", tick:=0) {
  global WS_Debug
  if (!WS_IsMovable(hwnd)) {
    WS_Reveal(hwnd)
    return
  }
  windowMon := GetMonitor("ahk_id " . hwnd)
  if (windowMon != targetMon) {
    WS_MoveToMonitor(hwnd, windowMon, targetMon)
    if (WS_Debug) {
      elapsed := tick ? A_TickCount - tick : 0
      WinGetTitle, dbgTitle, ahk_id %hwnd%
      WS_Log("MOVED (" . source . "): """ . dbgTitle . """ mon " . windowMon . " -> " . targetMon . " +" . elapsed . "ms")
    }
  }
  WS_Reveal(hwnd)
}

; Single backup poll — catches windows where WinEvent arrived but wasn't ready/movable yet
WS_BackupPoll(hwnd) {
  global WS_Pending, WS_Debug
  if (!WS_Pending.HasKey(hwnd))
    return
  SetWinDelay, -1
  if (WS_IsReady(hwnd)) {
    if (WS_IsMovable(hwnd)) {
      entry := WS_Pending.Delete(hwnd)
      WS_ProcessPending(hwnd, entry.mon, "poll", entry.tick)
      return
    }
    ; Ready but not movable — discard if permanently excluded (has title)
    WinGetTitle, chkTitle, ahk_id %hwnd%
    if (chkTitle != "") {
      WS_Pending.Delete(hwnd)
      WS_Reveal(hwnd)
    }
  }
}

; 2s safety net — last-ditch attempt, then discard
WS_TimeoutPending(hwnd) {
  global WS_Pending
  if (!WS_Pending.HasKey(hwnd))
    return
  entry := WS_Pending.Delete(hwnd)
  SetWinDelay, -1
  if (WS_IsReady(hwnd))
    WS_ProcessPending(hwnd, entry.mon, "timeout", entry.tick)
  else
    WS_Reveal(hwnd)  ; Safety net: reveal even if window never became ready
}

; Phase 10: Purge stale PrePending entries (windows created but never shown/hooked)
; Sentinel cleanup handled by HSHELL_WINDOWDESTROYED (line 1508)
WS_CleanPrePending:
  WS_staleKeys := []
  WS_now := A_TickCount
  for h, entry in WS_PrePending {
    if (WS_now - entry.tick > 500)
      WS_staleKeys.Push(h)
  }
  for i, k in WS_staleKeys {
    WS_PrePending.Delete(k)
    WS_Reveal(k)  ; Reveal windows that were hidden but never processed
  }
  ; Purge stale owner sentinels (200ms active window + 2s safety margin)
  WS_staleOwners := []
  for h, tick in WS_OwnerSentinel {
    if (WS_now - tick > 2000)
      WS_staleOwners.Push(h)
  }
  for i, k in WS_staleOwners
    WS_OwnerSentinel.Delete(k)
  ; Orphan sweep: reveal windows stuck in WS_Hidden that aren't tracked by PrePending/Pending
  WS_orphanKeys := []
  for h, val in WS_Hidden {
    if (val == -1)
      continue  ; Sentinel — already processed, cleaned by DESTROYED
    if (!WinExist("ahk_id " . h)) {
      WS_orphanKeys.Push(h)  ; Window gone — just remove
      continue
    }
    if (!WS_PrePending.HasKey(h) && !WS_Pending.HasKey(h)) {
      WS_orphanKeys.Push(h)
      if (WS_Debug)
        WS_Log("ORPHAN-REVEAL: hwnd=" . h)
      DllCall("SetLayeredWindowAttributes", "Ptr", h, "UInt", 0, "UChar", 255, "UInt", 0x2)
      if (!val)
        WinSet, ExStyle, -0x80000, ahk_id %h%
    }
  }
  for i, k in WS_orphanKeys
    WS_Hidden.Delete(k)
return

WS_IsReady(hwnd) {
  ; Window must still exist
  if !WinExist("ahk_id " . hwnd)
    return false
  ; Must be visible
  WinGet, style, Style, ahk_id %hwnd%
  if !(style & 0x10000000)  ; WS_VISIBLE
    return false
  ; Must not be cloaked (UWP pre-show transition)
  VarSetCapacity(cloaked, 4, 0)
  DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", hwnd, "UInt", 14, "Ptr", &cloaked, "UInt", 4)
  if (NumGet(cloaked, 0, "UInt"))
    return false
  ; Must have non-zero size
  WinGetPos,,, w, h, ahk_id %hwnd%
  if (w <= 0 || h <= 0)
    return false
  return true
}

WS_IsMovable(hwnd) {
  global WS_ExcludedClasses
  ; Must have a title (transient/system windows often don't)
  WinGetTitle, title, ahk_id %hwnd%
  if (title == "")
    return false
  ; Skip owned windows whose owner is visible (dialogs should follow their parent)
  ; But allow owned windows with hidden owners (e.g., Win+R Run dialog owned by hidden shell)
  owner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")  ; GW_OWNER=4
  if (owner) {
    WinGet, ownerStyle, Style, ahk_id %owner%
    if (ownerStyle & 0x10000000)  ; Owner is WS_VISIBLE → real parent dialog
      return false
  }
  ; Skip tool windows (tooltips, floating toolbars)
  WinGet, exStyle, ExStyle, ahk_id %hwnd%
  if (exStyle & 0x80)  ; WS_EX_TOOLWINDOW
    return false
  ; Skip excluded window classes
  WinGetClass, cls, ahk_id %hwnd%
  if HasVal(WS_ExcludedClasses, cls)
    return false
  return true
}

WS_MoveToMonitor(hwnd, srcMon, tgtMon) {
  global WS_Hidden, WS_OwnerSentinel, WS_Debug
  ; Phase 10: Pre-set sentinel BEFORE any WinMove calls. WinMove triggers SetWindowPos
  ; which dispatches WinEvent callbacks synchronously — a duplicate CREATE event during the
  ; move would re-hide the window. Setting the sentinel first prevents this race condition.
  hwnd := hwnd + 0
  _wasHidden := false
  _hadLayered := 0
  if (WS_Hidden.HasKey(hwnd)) {
    _hadLayered := WS_Hidden[hwnd]
    if (_hadLayered != -1) {
      _wasHidden := true
    }
  }
  ; Always mark as processed — prevents late CREATE events from re-hiding this window.
  ; Covers windows that were never opacity-hidden (same monitor, cloaked, no monitor at CREATE time).
  WS_Hidden[hwnd] := -1
  if (WS_Debug) {
    _dbgKeys := ""
    for _k, _v in WS_Hidden
      _dbgKeys .= Format("{}({}) ", _k, _v)
    WS_Log("SENTINEL-SET: hwnd=" . hwnd . " hex=" . Format("0x{:08X}", hwnd)
      . " HasKey=" . WS_Hidden.HasKey(hwnd) . " keys=[" . _dbgKeys . "]")
  }
  ; Phase 10: Owner sentinel — protect sibling #32770 windows from re-hiding
  _moveOwner := DllCall("GetWindow", "Ptr", hwnd, "UInt", 4, "Ptr")  ; GW_OWNER=4
  if (_moveOwner)
    WS_OwnerSentinel[_moveOwner + 0] := A_TickCount

  ; Get work areas (taskbar-aware) for both monitors
  SysGet, src, MonitorWorkArea, %srcMon%
  SysGet, tgt, MonitorWorkArea, %tgtMon%
  srcW := srcRight - srcLeft, srcH := srcBottom - srcTop
  tgtW := tgtRight - tgtLeft, tgtH := tgtBottom - tgtTop

  ; Get current window geometry (Phase 10: position is reliable — opacity approach preserves natural position)
  WinGetPos, winX, winY, winW, winH, ahk_id %hwnd%
  WinGet, minMax, MinMax, ahk_id %hwnd%
  if (WS_Debug)
    WS_Log("MOVE-START: hwnd=" . hwnd . " pos=" . winX . "," . winY . " size=" . winW . "x" . winH . " minMax=" . minMax)

  ; Minimized window: use GetWindowPlacement for real restored dimensions (WinGetPos returns ~160x28 at -32000,-32000)
  if (minMax == -1) {
    VarSetCapacity(_wp, 44, 0)
    NumPut(44, _wp, 0, "UInt")  ; cbSize
    DllCall("GetWindowPlacement", "Ptr", hwnd, "Ptr", &_wp)
    winW := NumGet(_wp, 36, "Int") - NumGet(_wp, 28, "Int")  ; rcNormalPosition width
    winH := NumGet(_wp, 40, "Int") - NumGet(_wp, 32, "Int")  ; rcNormalPosition height
    if (winW > tgtW)
      winW := tgtW
    if (winH > tgtH)
      winH := tgtH
    ; Center on target (no meaningful source-relative position for minimized windows)
    newX := tgtLeft + (tgtW - winW) // 2
    newY := tgtTop + (tgtH - winH) // 2
    WinRestore, ahk_id %hwnd%
    WinMove, ahk_id %hwnd%,, %newX%, %newY%, %winW%, %winH%
  } else if (minMax == 1) {
    ; Maximized window: restore, move to target, re-maximize
    WinRestore, ahk_id %hwnd%
    centerX := tgtLeft + (tgtW - winW) // 2
    centerY := tgtTop + (tgtH - winH) // 2
    WinMove, ahk_id %hwnd%,, %centerX%, %centerY%
    WinMaximize, ahk_id %hwnd%
  } else {
    ; Clamp window size to target work area
    if (winW > tgtW)
      winW := tgtW
    if (winH > tgtH)
      winH := tgtH

    ; Map relative position: source monitor -> target monitor
    relX := (winX - srcLeft) / srcW
    relY := (winY - srcTop) / srcH
    newX := Round(tgtLeft + relX * tgtW)
    newY := Round(tgtTop + relY * tgtH)

    ; Clamp to target bounds
    if (newX < tgtLeft)
      newX := tgtLeft
    if (newY < tgtTop)
      newY := tgtTop
    if (newX + winW > tgtRight)
      newX := tgtRight - winW
    if (newY + winH > tgtBottom)
      newY := tgtBottom - winH

    WinMove, ahk_id %hwnd%,, %newX%, %newY%, %winW%, %winH%
  }

  ; Phase 10: Restore opacity after move (window is now on correct monitor)
  if (_wasHidden) {
    DllCall("SetLayeredWindowAttributes", "Ptr", hwnd, "UInt", 0, "UChar", 255, "UInt", 0x2)
    if (!_hadLayered)
      WinSet, ExStyle, -0x80000, ahk_id %hwnd%
  }
}

; Phase 10: Restore opacity for a window hidden at CREATE time (idempotent — safe to call anytime)
WS_Reveal(hwnd) {
  global WS_Hidden
  hwnd := hwnd + 0  ; Ensure numeric key matches CREATE handler's storage
  if (!WS_Hidden.HasKey(hwnd)) {
    WS_Hidden[hwnd] := -1  ; Mark as processed even if never hidden
    return
  }
  hadLayered := WS_Hidden[hwnd]
  if (hadLayered == -1)
    return  ; Already revealed — sentinel prevents duplicate work
  WS_Hidden[hwnd] := -1  ; Mark as revealed (sentinel: CREATE handler checks this to avoid re-hiding)
  DllCall("SetLayeredWindowAttributes", "Ptr", hwnd, "UInt", 0, "UChar", 255, "UInt", 0x2)  ; LWA_ALPHA=2
  if (!hadLayered)
    WinSet, ExStyle, -0x80000, ahk_id %hwnd%  ; Remove WS_EX_LAYERED only if we added it
}

; Alt+Tab switcher doesn't trigger shell hooks (DWM overlay), so use WinEvent hook
~!Tab::
  targetMon := GetCursorMonitor()
  hwnd := WinExist("Task Switching ahk_class XamlExplorerHostIslandWindow")
  if (hwnd) {
    ; Already visible (fast re-press)
    windowMon := GetMonitor("ahk_id " . hwnd)
    if (windowMon != targetMon)
      WS_MoveToMonitor(hwnd, windowMon, targetMon)
  } else {
    ; Defer — WS_OnWinEvent catches the SHOW event
    WS_PendingAltTab := {mon: targetMon, tick: A_TickCount}
    SetTimer, WS_TimeoutAltTab, -500
  }
Return

WS_TimeoutAltTab:
  WS_PendingAltTab := ""
Return


WS_Cleanup() {
  global WS_HookHwnd, WS_EventHookShow, WS_EventHookUncloak, WS_EventHookCreate, WS_Hidden, WS_OwnerSentinel
  ; Reveal all hidden windows before shutting down (skip sentinels: -1 = already revealed)
  for h, hadLayered in WS_Hidden {
    if (hadLayered == -1)
      continue  ; Already revealed, nothing to restore
    DllCall("SetLayeredWindowAttributes", "Ptr", h, "UInt", 0, "UChar", 255, "UInt", 0x2)
    if (!hadLayered)
      WinSet, ExStyle, -0x80000, ahk_id %h%
  }
  WS_Hidden := {}
  WS_OwnerSentinel := {}
  DllCall("DeregisterShellHookWindow", "Ptr", WS_HookHwnd)
  Gui, ShellHook:Destroy
  if (WS_EventHookShow)
    DllCall("UnhookWinEvent", "Ptr", WS_EventHookShow)
  if (WS_EventHookUncloak)
    DllCall("UnhookWinEvent", "Ptr", WS_EventHookUncloak)
  if (WS_EventHookCreate)
    DllCall("UnhookWinEvent", "Ptr", WS_EventHookCreate)
  DllCall("ole32\CoUninitialize")
}

WS_QPC() {
  DllCall("QueryPerformanceCounter", "Int64*", count)
  return count
}

WS_Log(msg) {
  global WS_LogFile
  FileAppend, %A_Hour%:%A_Min%:%A_Sec% [%A_TickCount%] %msg%`n, %WS_LogFile%
}
