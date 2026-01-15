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

; Prevent script proceeding in RDP, Hyper-V, VMWare windows
#If (WinActive("ahk_class TscShellContainerClass") or WinActive("ahk_exe vmconnect.exe") or WinActive("ahk_exe vmware.exe"))
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
; [ Shift+Alt+E ] -> Edit script in Antigravity (activate if already open)
+!e::
  pid := ProcessExistsByCommandLine("Antigravity.exe"" """ . A_ScriptFullPath) ; Check If Antigravity is already open with this script
  If (pid) {
    WinActivate, ahk_pid %pid%
  } Else {
    UserRun("C:\Users\Rod\AppData\Local\Programs\Antigravity\Antigravity.exe", A_ScriptFullPath)
  }
Return
; [ Ctrl+S ] -> Reload script on save (in any editor)
#IfWinActive AutoHotkey.ahk
  ~^s::Reload
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
      UserRun("nircmd", "execmd taskkill /f /im explorer.exe && start explorer.exe")
    }
  }
  Else {
    UserRun("Rexplorer_x64.exe", "/f")
  }
Return


; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === HELPER FUNCTIONS === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━┛
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

; [ Win + E ] -> Alternate Explorer app in case of issues after Windows updates
; TODO: Swap with Files app
#e::
  WinGetClass, ahk_class, A
  path := GetExplorerPath()
  If (ahk_class = "Progman")
    path := A_Desktop
  Else If (ahk_class != "CabinetWClass" || path = "")
    path := A_UserProfile

  ; Activate existing e++ window for this path, or open new
  pid := ProcessExistsByCommandLine("e++.exe"" " . path)
  If (pid) {
    WinActivate, ahk_pid %pid%
  } Else {
    UserRun("e++", path)
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

MB_Debug := 1  ; Set to 1 to show debug tooltips

; Get vertical scroll position for a control (cross-process safe)
GetScrollPos(hwnd) {
  Return DllCall("GetScrollPos", "Ptr", hwnd, "Int", 1, "Int")
}

$*MButton::
  global MBScroll_X1, MBScroll_Y1, MBScroll_Win, MBScroll_CtrlClassNN, MBScroll_Triggered
  global G_UIA, MB_ScrollPattern := 0, MB_Element := 0, MBScroll_Ctrl
  global MB_Disabled := 0, MB_ViewSize := 10.0, MB_AccumPct := -1
  global MB_Method := "VSCROLL" ; Default fallback
  global MB_FallbackChecked := 0  ; Check fallback once per drag

  MouseGetPos,,, MBScroll_Win, MBScroll_CtrlClassNN
  WinGetClass, ahk_class, ahk_id %MBScroll_Win%
  WinGet, ahk_exe, ProcessName, ahk_id %MBScroll_Win%
  WinGetText, VisibleText, ahk_id %MBScroll_Win%
  WinGet, ControlText, ControlList, ahk_id %MBScroll_Win%

  ; APP LIST (passthrough/allow, excluded controls)
  MB_PassthroughApps := ["chrome.exe", "everything64.exe", "VmConnect.exe"]
  MB_EnabledApps := ["mmc.exe", "7zFM.exe", "code.exe", "SystemInFormer.exe"]
  MB_ExcludedControls := ["ToolbarWindow", "ReBarWindow", "Edit", "AddressBandRoot", "statusbar", "SysHeader"]

  ; SCROLL CONFIG (from app list)
  HasNativeScroll := HasVal(MB_PassthroughApps, ahk_exe)
  IsAllowedApp := HasVal(MB_EnabledApps, ahk_exe)
  IsAllowedContent := InStr(VisibleText, "Tree View") or InStr(VisibleText, "FolderView") or InStr(ControlText, "ScrollBar")
  IsExcludedRegion := HasVal(MB_ExcludedControls, MBScroll_CtrlClassNN) or (not MBScroll_CtrlClassNN and not (ahk_class = "Shell_TrayWnd" or ahk_class = "WorkerW"))

  ; OVERRIDES (Force specific method for certain apps)
  ; - UIA: Smooth fractional % scrolling via SetScrollPercent (Explorer)
  ; - WHEEL: WM_MOUSEWHEEL - sub-40 (Electron apps: VSCode)
  ; - WHEEL_CTRL: WM_MOUSEWHEEL (120, better acceleration than VSCROLL)
  ; - VSCROLL: WM_VSCROLL line-by-line, slower timer (40 -- single line)
  ForceUIA := ((ahk_exe = "mmc.exe") or (ahk_class = "CabinetWClass")) and !InStr(MBScroll_CtrlClassNN, "SysTreeView32")
  UseWheel := (ahk_exe = "code.exe")
  UseWheelCtrl := (ahk_exe = "SystemInFormer.exe")
  UseVScroll := InStr(MBScroll_CtrlClassNN, "SysTreeView32")

  ; DETERMINE If SCROLLING SHOULD OCCUR
  ShouldScroll := !HasNativeScroll and (IsAllowedApp or IsAllowedContent) and !IsExcludedRegion
  If (!ShouldScroll) {
    MB_Disabled := 1
    SendInput, {Blind}{MButton Down}
    Return
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

  ; DETERMINE SCROLL METHOD
  ; UIA for mmc, Explorer file lists (control focused)
  If (ForceUIA) {
    If (!G_UIA) {
      G_UIA := ComObjCreate("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
    }
    ; Always use control if available, fallback to window
    targetForUIA := MBScroll_Ctrl ? MBScroll_Ctrl : MBScroll_Win
    DllCall(NumGet(NumGet(G_UIA+0)+6*A_PtrSize), "Ptr", G_UIA, "Ptr", targetForUIA, "Ptr*", MB_Element)
    If (MB_Element) {
      ; Get ScrollPattern (10004)
      DllCall(NumGet(NumGet(MB_Element+0)+16*A_PtrSize), "Ptr", MB_Element, "Int", 10004, "Ptr*", MB_ScrollPattern)
      ; Get ViewSize for normalization
      DllCall(NumGet(NumGet(MB_ScrollPattern+0)+8*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_ViewSize)
      If (MB_ViewSize < 1)
        MB_ViewSize := 10.0
    }
    MB_Method := "UIA"
  }
  Else If (UseWheel) { ; WM_MOUSEWHEEL for Electron apps (sub-40)
    MB_Method := "WHEEL"
  }
  Else If (UseWheelCtrl) { ; WM_MOUSEWHEEL for CONTROL with GetScrollPos fallback
    MB_Method := "WHEEL_CTRL"
  }
  Else If (UseVScroll) { ; WM_VSCROLL for TreeView / Explorer nav pane
    MB_Method := "VSCROLL"
  }

  ; Start timer (VSCROLL starts slow, adjusts dynamically in timer)
  timerInterval := (MB_Method = "VSCROLL") ? 150 : 10
  SetTimer, MBScrollTimer, %timerInterval%
Return

MBScrollTimer:
  global MB_AccumPct, MB_Method, MB_ViewSize, MBScroll_Ctrl, MB_FallbackChecked
  ; Safety check: if MButton released, stop immediately
  If !GetKeyState("MButton", "P") {
    SetTimer, MBScrollTimer, Off
    If (MB_Debug)
      ToolTip
    Return
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
      ; UIA SCROLLING (mmc, Explorer file lists)
      ; ===========================================
      If (MB_AccumPct < 0) {
        DllCall(NumGet(NumGet(MB_ScrollPattern+0)+6*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_AccumPct)
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
      ; WM_MOUSEWHEEL with sub-120 to WINDOW (Electron apps like VS Code, Antigravity, Cursor -- default)
      ; ===========================================
      lParam := ((MBScroll_Y1 & 0xFFFF) << 16) | (MBScroll_X1 & 0xFFFF)
      ; MUST cap below 120 for smooth scrolling (120 = 1 notch = 3 lines)
      magnitude := Max(1, Min(119, Floor(curveValue / 2)))
      Delta := (SignedDist > 0) ? -magnitude : magnitude
      wParam := Delta << 16
      If (MB_Debug)
        ToolTip, % "WHEEL: d=" Delta " win=" MBScroll_Win
      PostMessage, 0x20A, %wParam%, %lParam%,, ahk_id %MBScroll_Win%
    }
  }
Return

$*MButton Up::
  global MB_Disabled, MBScroll_Triggered, MBScroll_Win, MB_ScrollPattern, MB_Element
  SetTimer, MBScrollTimer, Off
  If (MB_Debug)
    ToolTip

  ; If we passed through MButton Down, also pass through MButton Up
  If (MB_Disabled) {
    SendInput, {Blind}{MButton Up}
    Return
  }

  ; Release UIA objects
  If (MB_ScrollPattern) {
    ObjRelease(MB_ScrollPattern)
    MB_ScrollPattern := 0
  }
  If (MB_Element) {
    ObjRelease(MB_Element)
    MB_Element := 0
  }

  ; If no drag occurred in non-Explorer, send click
  WinGetClass, ahk_class, ahk_id %MBScroll_Win%
  If (!MBScroll_Triggered and ahk_class != "CabinetWClass")
    SendInput, {Blind}{MButton}
Return
