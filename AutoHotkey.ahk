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
EnvGet, G_UserProfile, USERPROFILE

; Disable hotkeys inside remote sessions (RDP, Hyper-V, VMWare)
#If IsRemoteSession()
  If !IsRemoteSession()
    WS_Init() ; Init window spawning
    TerminalInit()
    WTScrollInit()
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
+!e::UserRun("vsc", A_ScriptFullPath) ; [ Shift+Alt+E ] -> Edit script in VS Code
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
  ^e:: ; [ Ctrl+E ] -> Edit selected file with default edit handler (Explorer or file dialog)
    selected := _GetSelectedFile()
    If (selected = "")
      Return
    ; .lnk shortcuts: fix disabled target field, show Properties
    If (SubStr(selected, -3) = ".lnk") {
      _FixAdvertisedShortcut(selected)
      _ShowProperties(selected)
      Return
    }
    ; WSL paths: edit directly (permissions managed by Linux)
    If (SubStr(selected, 1, 6) = "\\wsl$" || SubStr(selected, 1, 15) = "\\wsl.localhost") {
      Try
        Run *edit "%selected%"
      Catch
        Run "%selected%"
      Return
    }
    ; Check write access; behavior varies by path type
    If !_HasWriteAccess(selected) {
      If (SubStr(selected, 1, 2) = "\\") {
        ; Network UNC: warn about slowness, Cancel skips grant but still edits
        MsgBox, 0x31, Edit Network File, Write access is needed to edit this file. Note that network paths can slow down access changes. Do you wish to change permissions?`n`n%selected%
        IfMsgBox Cancel
        {
          Try
            Run *edit "%selected%"
          Catch
            Run "%selected%"
          Return
        }
      } Else {
        ; Local: standard confirmation, Cancel aborts entirely
        MsgBox, 0x31, Edit Protected File, Full write access must be granted to edit this file.`n`n%selected%
        IfMsgBox Cancel
          Return
      }
      _GrantWriteAccess(selected)
    }
    Try
      Run *edit "%selected%"
    Catch
      Run "%selected%"
  Return
  ^+e:: ; [ Ctrl+Shift+E ] -> Remove user's granted ACL entry from selected file
    selected := _GetSelectedFile()
    If (selected != "")
      _RevokeWriteAccess(selected)
  Return
#If

; ⇒ Media / hardware
+!l:: ; [ Shift+Alt+L ] -> Turn off monitor
  Sleep 200
  SendMessage, 0x112, 0xF170, 2,, Program Manager
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
  $*MButton::Send n ; VLC: next file on middle click
#IfWinActive

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
    path := G_UserProfile

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

; ⇒ Get the UIA content process PID for a window (resolves host vs content for UWP/Electron)
; Returns content PID if different from window PID, otherwise returns window PID
GetUIAProcessId(hwnd) {
  global G_UIA
  WinGet, _winPid, PID, ahk_id %hwnd%
  If (!_winPid)
    Return 0
  Try {
    If (!G_UIA)
      G_UIA := ComObjCreate("{ff48dba4-60ef-4201-aa87-54103eef594e}", "{30cbe57d-d9d0-452a-ab13-7ac5ac4825ee}")
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
; Uses the linked (non-elevated) token with AccessCheck
_HasWriteAccess(filePath) {
  hToken := 0
  If !DllCall("advapi32\OpenProcessToken"
      , "Ptr", DllCall("GetCurrentProcess", "Ptr")
      , "UInt", 0x0008    ; TOKEN_QUERY
      , "Ptr*", hToken)
    Return true

  ; Get linked (non-elevated) token — only exists when running elevated
  VarSetCapacity(linkedBuf, A_PtrSize, 0)
  hLinked := 0
  If DllCall("advapi32\GetTokenInformation"
      , "Ptr", hToken, "Int", 19  ; TokenLinkedToken
      , "Ptr", &linkedBuf, "UInt", A_PtrSize, "UInt*", 0)
    hLinked := NumGet(linkedBuf, 0, "Ptr")
  DllCall("CloseHandle", "Ptr", hToken)

  If !hLinked
    Return true  ; Not elevated — current user IS the non-elevated user

  ; Linked token has TOKEN_QUERY only; upgrade via DuplicateHandle for TOKEN_DUPLICATE
  hLinkedDup := 0
  _hProc := DllCall("GetCurrentProcess", "Ptr")
  DllCall("DuplicateHandle"
      , "Ptr", _hProc, "Ptr", hLinked
      , "Ptr", _hProc, "Ptr*", hLinkedDup
      , "UInt", 0x000A  ; TOKEN_QUERY | TOKEN_DUPLICATE
      , "Int", 0, "UInt", 0)
  DllCall("CloseHandle", "Ptr", hLinked)
  If !hLinkedDup
    Return true

  ; Duplicate as SecurityImpersonation token (required by AccessCheck)
  hImpToken := 0
  DllCall("advapi32\DuplicateToken"
      , "Ptr", hLinkedDup, "Int", 2, "Ptr*", hImpToken)  ; SecurityImpersonation
  DllCall("CloseHandle", "Ptr", hLinkedDup)
  If !hImpToken
    Return true

  ; Get file security descriptor (owner + group + DACL)
  pSD := 0
  If DllCall("advapi32\GetNamedSecurityInfoW"
      , "WStr", filePath, "Int", 1, "UInt", 0x7  ; SE_FILE_OBJECT, OWNER|GROUP|DACL
      , "Ptr", 0, "Ptr", 0, "Ptr", 0, "Ptr", 0
      , "Ptr*", pSD) || !pSD {
    DllCall("CloseHandle", "Ptr", hImpToken)
    Return true
  }

  ; GENERIC_MAPPING for file objects
  VarSetCapacity(gm, 16, 0)
  NumPut(0x00120089, gm, 0, "UInt")   ; FILE_GENERIC_READ
  NumPut(0x00120116, gm, 4, "UInt")   ; FILE_GENERIC_WRITE
  NumPut(0x001200A0, gm, 8, "UInt")   ; FILE_GENERIC_EXECUTE
  NumPut(0x001F01FF, gm, 12, "UInt")  ; FILE_ALL_ACCESS

  desiredAccess := 0x40000000          ; GENERIC_WRITE
  DllCall("advapi32\MapGenericMask", "UInt*", desiredAccess, "Ptr", &gm)

  VarSetCapacity(privSet, 64, 0)
  privSetLen := 64, grantedAccess := 0, accessOK := false
  DllCall("advapi32\AccessCheck"
      , "Ptr", pSD, "Ptr", hImpToken
      , "UInt", desiredAccess, "Ptr", &gm
      , "Ptr", &privSet, "UInt*", privSetLen
      , "UInt*", grantedAccess, "Int*", accessOK)

  DllCall("CloseHandle", "Ptr", hImpToken)
  DllCall("kernel32\LocalFree", "Ptr", pSD)
  Return accessOK
}

; ⇒ Grant write access: save owner → take ownership → grant access → restore owner
; Uses SetEntriesInAcl + SetNamedSecurityInfo (pure API, no external processes)
_GrantWriteAccess(filePath) {
  ; 1. Save current owner SID
  pSD := 0, pOwner := 0
  If DllCall("advapi32\GetNamedSecurityInfoW"
      , "WStr", filePath, "Int", 1, "UInt", 0x1  ; SE_FILE_OBJECT, OWNER
      , "Ptr*", pOwner, "Ptr", 0, "Ptr", 0, "Ptr", 0
      , "Ptr*", pSD) || !pSD
    Return

  sidLen := DllCall("advapi32\GetLengthSid", "Ptr", pOwner, "UInt")
  VarSetCapacity(savedOwner, sidLen, 0)
  DllCall("advapi32\CopySid", "UInt", sidLen, "Ptr", &savedOwner, "Ptr", pOwner)
  DllCall("kernel32\LocalFree", "Ptr", pSD)

  ; 2. Enable required privileges
  _EnablePrivilege("SeTakeOwnershipPrivilege")
  _EnablePrivilege("SeRestorePrivilege")

  ; 3. Get current user's SID for taking ownership
  hToken := 0
  DllCall("advapi32\OpenProcessToken"
      , "Ptr", DllCall("GetCurrentProcess", "Ptr")
      , "UInt", 0x0008, "Ptr*", hToken)  ; TOKEN_QUERY
  VarSetCapacity(tuBuf, 256, 0)
  DllCall("advapi32\GetTokenInformation"
      , "Ptr", hToken, "Int", 1  ; TokenUser
      , "Ptr", &tuBuf, "UInt", 256, "UInt*", 0)
  DllCall("CloseHandle", "Ptr", hToken)
  pUserSid := NumGet(tuBuf, 0, "Ptr")

  ; 4. Build EXPLICIT_ACCESS: grant Full Control to current user
  eaSize := (A_PtrSize = 8) ? 48 : 32
  VarSetCapacity(ea, eaSize, 0)
  VarSetCapacity(uName, StrLen(A_UserName) * 2 + 2, 0)
  StrPut(A_UserName, &uName, "UTF-16")
  DllCall("advapi32\BuildExplicitAccessWithNameW"
      , "Ptr", &ea, "Ptr", &uName
      , "UInt", 0x1F01FF   ; FILE_ALL_ACCESS
      , "UInt", 2          ; GRANT_ACCESS
      , "UInt", 0)         ; NO_INHERITANCE

  ; 5. Critical section: take ownership → modify DACL → restore owner
  Critical
  DllCall("advapi32\SetNamedSecurityInfoW"
      , "WStr", filePath, "Int", 1, "UInt", 0x1  ; OWNER
      , "Ptr", pUserSid, "Ptr", 0, "Ptr", 0, "Ptr", 0)

  pDacl := 0, pSD2 := 0
  DllCall("advapi32\GetNamedSecurityInfoW"
      , "WStr", filePath, "Int", 1, "UInt", 0x4  ; DACL
      , "Ptr", 0, "Ptr", 0, "Ptr*", pDacl, "Ptr", 0, "Ptr*", pSD2)

  pNewDacl := 0
  If (pSD2)
    DllCall("advapi32\SetEntriesInAclW"
        , "UInt", 1, "Ptr", &ea, "Ptr", pDacl, "Ptr*", pNewDacl)
  If (pNewDacl)
    DllCall("advapi32\SetNamedSecurityInfoW"
        , "WStr", filePath, "Int", 1, "UInt", 0x4  ; DACL
        , "Ptr", 0, "Ptr", 0, "Ptr", pNewDacl, "Ptr", 0)

  DllCall("advapi32\SetNamedSecurityInfoW"
      , "WStr", filePath, "Int", 1, "UInt", 0x1  ; OWNER (restore)
      , "Ptr", &savedOwner, "Ptr", 0, "Ptr", 0, "Ptr", 0)
  Critical Off

  If (pNewDacl)
    DllCall("kernel32\LocalFree", "Ptr", pNewDacl)
  If (pSD2)
    DllCall("kernel32\LocalFree", "Ptr", pSD2)
}

; ⇒ Enable a named privilege on the current process token
_EnablePrivilege(privName) {
  hToken := 0
  If !DllCall("advapi32\OpenProcessToken"
      , "Ptr", DllCall("GetCurrentProcess", "Ptr")
      , "UInt", 0x0028  ; TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY
      , "Ptr*", hToken)
    Return

  VarSetCapacity(luid, 8, 0)
  DllCall("advapi32\LookupPrivilegeValueW", "Ptr", 0, "WStr", privName, "Ptr", &luid)

  VarSetCapacity(tp, 16, 0)
  NumPut(1, tp, 0, "UInt")                         ; PrivilegeCount = 1
  NumPut(NumGet(luid, 0, "Int64"), tp, 4, "Int64")  ; LUID
  NumPut(2, tp, 12, "UInt")                         ; SE_PRIVILEGE_ENABLED

  DllCall("advapi32\AdjustTokenPrivileges"
      , "Ptr", hToken, "Int", 0
      , "Ptr", &tp, "UInt", 0, "Ptr", 0, "Ptr", 0)
  DllCall("CloseHandle", "Ptr", hToken)
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

; ⇒ Remove user's explicit allow ACEs from a file (undo _GrantWriteAccess)
_RevokeWriteAccess(filePath) {
  eaSize := (A_PtrSize = 8) ? 48 : 32
  VarSetCapacity(ea, eaSize, 0)
  VarSetCapacity(uName, StrLen(A_UserName) * 2 + 2, 0)
  StrPut(A_UserName, &uName, "UTF-16")
  DllCall("advapi32\BuildExplicitAccessWithNameW"
      , "Ptr", &ea, "Ptr", &uName
      , "UInt", 0           ; ignored for REVOKE_ACCESS
      , "UInt", 4           ; REVOKE_ACCESS
      , "UInt", 0)          ; NO_INHERITANCE

  pDacl := 0, pSD := 0
  If DllCall("advapi32\GetNamedSecurityInfoW"
      , "WStr", filePath, "Int", 1, "UInt", 0x4  ; DACL
      , "Ptr", 0, "Ptr", 0, "Ptr*", pDacl, "Ptr", 0, "Ptr*", pSD) || !pSD {
    SplitPath, filePath, fileName
    ToolTip, Failed to read ACL: %fileName%
    SetTimer, RemoveToolTip, -2000
    Return
  }

  pNewDacl := 0
  DllCall("advapi32\SetEntriesInAclW"
      , "UInt", 1, "Ptr", &ea, "Ptr", pDacl, "Ptr*", pNewDacl)
  If (pNewDacl) {
    DllCall("advapi32\SetNamedSecurityInfoW"
        , "WStr", filePath, "Int", 1, "UInt", 0x4  ; DACL
        , "Ptr", 0, "Ptr", 0, "Ptr", pNewDacl, "Ptr", 0)
    DllCall("kernel32\LocalFree", "Ptr", pNewDacl)
  }
  DllCall("kernel32\LocalFree", "Ptr", pSD)

  SplitPath, filePath, fileName
  ToolTip, ACL revoked: %fileName%
  SetTimer, RemoveToolTip, -2000
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
    _safeExe := StrReplace(Executable, "'", "''")
    quotedExe := "'" _safeExe "'"
    psCmd := "& " quotedExe
    Loop % Args.Length() {
      arg := Args[A_Index]
      ; Handle "-d <path>" specially (For Windows Terminal)
      If RegExMatch(arg, "(?i)^\s*-d\s+(.+)$", m) {
        rawPath := m1
        expanded := RegExReplace(rawPath, "(?i)%(.*?)%", "$env:$1")
        _safePath := StrReplace(expanded, "'", "''")
        path := "'" _safePath "'"
        psCmd .= " -d " path
      } Else {
        expanded := RegExReplace(arg, "(?i)%(.*?)%", "$env:$1")
        _safeArg := StrReplace(expanded, "'", "''")
        quotedArg := "'" _safeArg "'"
        psCmd .= " " quotedArg
      }
    }
    If (elevate) {
      ; Escape single quotes for embedding psCmd inside -ArgumentList '...'
      _psCmdEsc := StrReplace(psCmd, "'", "''")
      full := "RunFromProcess-x64 explorer.exe conhost.exe --headless powershell -NoProfile -Command ""Start-Process powershell -ArgumentList '-NoProfile -Command " _psCmdEsc "' -Verb RunAs -WindowStyle Hidden"""
    } Else {
      full := "RunFromProcess-x64 explorer.exe conhost.exe --headless powershell -NoProfile -Command """ psCmd """"
    }
  } Else {
    ; Direct execution - no env vars to expand, build simple argument string
    argStr := ""
    Loop % Args.Length() {
      arg := Args[A_Index]
      _safeArg := StrReplace(arg, """", """""")
      argStr .= " """ _safeArg """"
    }
    If (elevate) {
      ; Use PowerShell Start-Process For elevation
      _safeExe2 := StrReplace(Executable, "'", "''")
      _safeArgs2 := StrReplace(argStr, "'", "''")
      full := "RunFromProcess-x64 explorer.exe conhost.exe --headless powershell -NoProfile -Command ""Start-Process '" _safeExe2 "' -ArgumentList '" _safeArgs2 "' -Verb RunAs -WindowStyle Hidden"""
    } Else {
      _safeExeD := StrReplace(Executable, """", """""")
      full := "RunFromProcess-x64 explorer.exe """ _safeExeD """" argStr
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

; === Module Includes ===
#Include %A_ScriptDir%\windows-terminal.ahk
#Include %A_ScriptDir%\terminal-anywhere.ahk
#Include %A_ScriptDir%\extended-spy.ahk
#Include %A_ScriptDir%\mbutton-scroll.ahk
#Include %A_ScriptDir%\window-spawning.ahk
