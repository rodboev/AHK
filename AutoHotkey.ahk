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
; The hook suppresses the physical key while the main thread evaluates an #If.
; Default is 1000ms; under CPU contention that is how long a click can be held.
; Timing out passes the input through natively instead.
#IfTimeout 50

global Debug
Debug := { Tooltips: {"scroll-accel": 0
  , "mbutton-drag": 0 }
, Log: { Path: A_Temp . "\AHK_Debug.log"
  , "scroll-accel": 0
  , "mbutton-drag": 0
  , "mb-timing": 0
  , "window-spawning": 1
  , "terminal-anywhere": 0
  , "herdr-anywhere": 1
  , "herdr-new-window": 1
  , "tab-search": 0 }}

FileDelete, % Debug.Log.Path

; DisplayFusion handles ordinary application launches. Keep the special window
; routing for Run, Start, and owned #32770 dialogs in this script.
WindowSpawningEnabled := 1
WindowSpawningSpecialOnly := 1
_alacrittyDpiScale := GetAlacrittyDpiScale()
G_AlacrittyMenuLeftWidth := 225 * _alacrittyDpiScale
G_AlacrittyMenuTopHeight := 50 * _alacrittyDpiScale

TS() {
  FormatTime, _t,, HH:mm:ss
  return _t
}


; Disable hotkeys inside remote sessions (RDP, Hyper-V, VMWare)
#If IsRemoteSession()
  If !IsRemoteSession() {
    MB_Init()
    OnExit("MB_Cleanup")
    If (WindowSpawningEnabled)
      WS_Init(WindowSpawningSpecialOnly)
    TerminalInit()
    If (Debug.Log["mb-timing"])
      SetTimer, MainThreadHeartbeat, 100
  }
  Return
#If

; Main-thread starvation probe. #If expressions guarding hotkeys are evaluated on
; this thread while the hook holds the physical input, so lateness here is the
; ceiling on how long a keypress or click can be stalled.
MainThreadHeartbeat:
  global G_HB, Debug
  _hbNow := QPCms()
  If (G_HB) {
    _hbLate := _hbNow - G_HB - 100
    If (_hbLate > 30)
      FileAppend, % TS() " | mb-timing | STARVED | late=" Round(_hbLate, 1) "ms`n", % Debug.Log.Path
  }
  G_HB := _hbNow
Return

; --------------------------------------------------------------------------
; END OF AUTO-EXECUTE
; Startup code below hotkey declarations is ignored, including within
; #Include files
; --------------------------------------------------------------------------

; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === BINDINGS / REMAPS === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; ⇒ AutoHotkey/global
+!p::       ; [ ShIft+Alt+P ] -> Toggle pause script+suspend hotkeys
  Suspend
  Pause,,1
Return
#IfWinNotActive ahk_exe chrome.exe
+!r::Reload ; [ ShIft+Alt+R ] -> Reload script
+!e:: ; [ Shift+Alt+E ] -> Edit AHK scripts in Sublime
  KeyWait, Shift
  SetTitleMatchMode, RegEx
  _sublTitle := "ahk_exe sublime_text.exe"
  If (WinExist("\.ahk.*Sublime Text " _sublTitle)) {
    WinActivate
  } Else {
    UserRun("subl.exe", "-n", A_ScriptDir "\*.ahk")
  }
  SetTitleMatchMode, 1
Return
#IfWinNotActive
#IfWinActive .ahk
  ~^s::Reload ; [ Ctrl+S ] -> Reload script on save (in any editor)
#IfWinActive

; ⇒ Sublime Text
#n::
  If (WinExist("ahk_exe sublime_text.exe")) {
    If (WinActive("ahk_exe sublime_text.exe"))
      UserRun("notepad")
    Else
      WinActivate, ahk_exe sublime_text.exe
  } Else {
    UserRun("notepad")
  }
Return
#IfWinActive ahk_exe sublime_text.exe
  ^Tab::Send {Ctrl Down}{PgDn}{Ctrl Up} ; [ Ctrl+Tab ] -> Next tab
  +^Tab::Send {Ctrl Down}{PgUp}{Ctrl Up} ; [ ShIft+Ctrl+Tab ] -> Previous tab
  ^w:: ; [ Ctrl+W ] -> Toggle word wrap
    SendEvent !v
    Sleep 10
    SendEvent w
  Return
  ^;::
  #;::
  !;::
    Send ^/ ; [ Any+; ] -> Toggle comment
  Return
  +!d::Send {Alt Down}f{AltUp}e{Ctrl Down} ; [ Ctrl+Alt+D] -> Duplicate line
#IfWinActive

; ⇒ VSCode + forks
#If (WinActive("ahk_exe code.exe") OR WinActive("ahk_exe vscodium.exe") OR WinActive("ahk_exe Cursor.app.exe"))
  +^w::Send {Alt Down}z{AltUp} ; [ Shift+Ctrl+W ] -> Toggle word wrap
#If

; ⇒ Superwhisper
#IfWinActive Superwhisper ahk_exe Superwhisper.exe
  *Esc Up::
    SuperwhisperCloseWindow()
  Return
#IfWinActive

; ⇒ Other global bindings
#If !WinActive("ahk_exe alacritty.exe")
+!-::Send {U+2014} ; [ ShIft+Alt+Minus ] -> Em-dash
#If
+!0::Send {U+2022} ; [ ShIft+Alt+0] -> Bullet

#If (WinActive("ahk_exe chrome.exe"))
  ^+l::Send {Raw}https://linkedin.com/in/rodboev
  ^+g::Send {Raw}https://github.com/rodboev
  ^+r::Send {Raw}C:\Dropbox\Projects\basedin.nyc\resume.pdf
  ^+b::Send {Raw}https://basedin.nyc
  ^+p::Send {Raw}347-644-9001
  ^+c::Send {Raw}New York
  ^+e::Send {Raw}rod@basedin.nyc
  ^+s::Send {Raw}Stony Brook University
  ^+d::Send {Raw}Bachelor's Degree
#If

#a::
  _alacrittyConfig := "C:\Users\Rod\AppData\Roaming\alacritty\alacritty.toml"
  _configWindow := WinExist("alacritty.toml")
  If (_configWindow)
    WinActivate, ahk_id %_configWindow%
  Else
    UserRun("explorer.exe", _alacrittyConfig)
Return

#c::SendInput, #a
~RWin::Send {AppsKey} ; [RWin] -> Apps/context menu
~#t::Run explorer shell:::{3080F90E-D7AD-11D9-BD98-0000947B0257} ; Win+T -> Task View
!`::WinSet, AlwaysOnTop, Toggle, A ; [ Alt+` ] -> Toggle always-on-top
!PrintScreen::ScreenshotWindow() ; [ Alt+PrintScreen ] -> Screenshot window (always-on-top)
!+PrintScreen:: ; [ Alt+Shift+PrintScreen ] -> Screenshot window to desktop with shadow
  FormatTime, day,, ddd
  FormatTime, time,, h.mm.ss
  FormatTime, ampm,, tt
  _screenshotPath := A_Desktop . "\" . day . " " . time . " " . ampm . ".png"
  ScreenshotWindow(_screenshotPath, 8)
  UserRun(FindInPath("addshadow.cmd"), _screenshotPath)
Return

; ⇒ Windows Explorer
^+!x:: ; -> [ Shift +Alt +X ] -> Restart Explorer
  If (!FindInPath("rexplorer_x64.exe"))
    UserRun("cmd", "/c", "taskkill /f /im explorer.exe && start explorer.exe")
  Else If GetKeyState("Ctrl") ; -> [ Ctrl+Shift+Alt+X ] -> Restart Explorer
    Run, rexplorer_x64.exe /r
  Else
    Run, rexplorer_x64.exe /f
Return

#IfWinActive, ahk_class CabinetWClass
  !d::SendInput {Alt Up}{F4} ; [ Alt+D ] -> Focus address bar
  Backspace:: ; [ Backspace ] -> Go up a folder instead of backwards in history
    ControlGet renamestatus,Visible,,Edit1,A
    ControlGetFocus focused, A
    If (renamestatus != 1 and (focused = "DirectUIHWND2" or focused = "DirectUIHWND3" or focused = "SysTreeView321"))
      SendInput {Alt Down}{Up}{Alt Up}
    Else
      Send {Backspace}
  Return
#IfWinActive

#If ExplorerShouldCloseOnEsc()
  Esc:: ; [ Esc ] -> Close Explorer window unless focus is in a text input
    WinClose, A
  Return
#If

#IfWinActive, Open
  !d::Send {Alt Down}n{Alt Up} ; [ Alt+D ] -> Focus filename field in Open dialog
#IfWinActive

#If (WinActive("ahk_class CabinetWClass") || WinActive("ahk_class #32770")) && !WinActive("ahk_exe Everything.exe")
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

; ⇒ Terminal image paste: convert clipboard image to file for Claude Code
#If (WinActive("ahk_exe WindowsTerminal.exe") || WinActive("ahk_exe alacritty.exe")) && ClipboardHasImage()
  ^v::
    ConvertClipboardImageToFile()
    Send ^v
    Sleep, 100
    FileDelete, %A_Temp%\clipboard_paste.png
  Return
#If (MouseIsOver("ahk_exe WindowsTerminal.exe") || AlacrittySurfaceIsUnderMouse()) && ClipboardHasImage()
  RButton::
    MouseGetPos,,,, ctrl
    If (MouseIsOver("ahk_exe WindowsTerminal.exe") && ctrl != "Windows.UI.Composition.DesktopWindowContentBridge1") {
      Click Right
      Return
    }
    If (AlacrittyMenuRightClick()) {
      ActivateMouseWindow("ahk_exe alacritty.exe")
      Click Right
      Return
    }
    If (AlacrittySurfaceIsUnderMouse())
      ActivateMouseWindow("ahk_exe alacritty.exe")
    ConvertClipboardImageToFile()
    Send ^v
    Sleep, 100
    FileDelete, %A_Temp%\clipboard_paste.png
  Return
#If

#If WinActive("ahk_exe alacritty.exe") && !ClipboardHasImage()
  $^v::PasteNormalizedClipboard()
#If AlacrittySurfaceIsUnderMouse() && !ClipboardHasImage()
  $RButton::
    If (AlacrittyMenuRightClick()) {
      ActivateMouseWindow("ahk_exe alacritty.exe")
      Click Right
      Return
    }
    PasteNormalizedClipboard()
  Return
#If

; Send modified clicks to Herdr as unmodified clicks.
#If AlacrittySurfaceIsUnderMouse()
  $^RButton::SendInput, {RButton}
  $+RButton::SendInput, {RButton}
  $+LButton::SendInput, {LButton}
#If

#If MouseIsOverMB("ahk_exe JPEGView.exe")
  Enter::
    WinGet, active_id, ID, A
    Send w
    WinClose, ahk_id %active_id%
  Return
  $MButton::SendInput {F11}
#If

#If MouseIsOverMB("ahk_class QWidget")
  *MButton::Send n ; VLC: next file on middle click
#If

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

; Accelerated scrolling
; Divisor 0 excludes the app via #If: the hook never suppresses the notch, so
; passthrough apps scroll natively; #IfTimeout also lets notches through when the main thread is blocked
WheelAccelDivisor() {
  global G_WheelDivisor, Debug
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
  G_WheelDivisor := divisor
  If (Debug.Log["scroll-accel"] and divisor = 0)
    FileAppend, % TS() " | scroll-accel | PASSTHROUGH | exe=" _exe " class=" _class "`n", % Debug.Log.Path
  Return divisor
}

#If (WheelAccelDivisor() != 0)
  WheelUp::
  WheelDown::
    global G_WheelDivisor
    v := GetScrollAccel(G_WheelDivisor)
    MouseClick, %A_ThisHotkey%, , , %v%
  Return
#If
  +WheelUp::Send {Click WheelUp 10}
  +WheelDown::Send {Click WheelDown 10}
  !WheelUp::Send {WheelLeft}
  !WheelDown::Send {WheelRight}
  !+WheelUp::Send {WheelLeft 10}
  !+WheelDown::Send {WheelRight 10}


; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === PROCESS MANAGEMENT / PRIVILEGE ESCALATION === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; [ Ctrl + Shift + ` ] -> Open System Informer as SYSTEM with TI privileges
^+`::UserRun("elevate", "ti", "c:\Program Files\SystemInformer\SystemInformer.exe")

; [ Win + Shift + E ] -> Alternate Explorer app in case of issues after Windows updates
#+e::
  WinGetClass, ahk_class, A
  path := IsFunc("GetExplorerPath") ? GetExplorerPath() : ""
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

; ⇒ Whether MButton drag-scroll should claim the button at all.
; Same idea as WheelAccelDivisor returning 0: a false result means the hook never
; suppresses the button, so the app gets it straight from the hardware. Handling
; it in the hotkey body instead is too late, because suppress-then-SendInput puts
; the replay on a main thread that CPU contention can stall for seconds.
; Browsers scroll MButton drag natively, so they never need us.
MButtonHandled() {
  MouseGetPos,,, _hwnd
  WinGet, _exe, ProcessName, ahk_id %_hwnd%
  Return !HasVal(["chrome.exe", "msedge.exe", "brave.exe", "vivaldi.exe", "opera.exe"], _exe)
}

; ⇒ MouseIsOver for #If contexts guarding MButton variants.
; The mouse hook suppresses the physical button until the main thread evaluates
; these, so their cost is added input latency in every app, even ones we pass
; through. Accumulates per press for the mb-timing log; MButton reads G_MBIf.
MouseIsOverMB(winTitle) {
  global G_MBIf
  _t0 := QPCms()
  If (!IsObject(G_MBIf) or (_t0 - G_MBIf.End) > 250)
    G_MBIf := {Ms: 0, N: 0}
  _r := MouseIsOver(winTitle)
  G_MBIf.End := QPCms()
  G_MBIf.Ms += G_MBIf.End - _t0
  G_MBIf.N++
  Return _r
}

; ⇒ Calculate scroll acceleration
; Based on https://autohotkey.com/board/topic/48426-accelerated-scrolling-script/?p=333222
; Higher divisor = steeper curve (75 gentle, 250 steep); 0 = disabled
GetScrollAccel(divisor := 100) {
  If (divisor = 0)
    Return 1
  global Debug
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
    If (Debug.Log["scroll-accel"]) {
      FileAppend, % TS() " | scroll-accel | SKIP t=" t "ms (using lastV=" lastV ")`n", % Debug.Log.Path
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

  If (Debug.Tooltips["scroll-accel"]) {
    MouseGetPos, _mx, _my, _hwnd
    WinGet, _exe, ProcessName, ahk_id %_hwnd%
    WinGetClass, _class, ahk_id %_hwnd%
    _tx := _mx + 50
    _ty := _my + 30
    ToolTip, ScrollAccel: v=%v% t=%t%ms div=%divisor% %reason%`n%_exe% [%_class%], %_tx%, %_ty%
    SetTimer, ScrollAccelTooltipOff, -800
  }
  If (Debug.Log["scroll-accel"]) {
    dir := isUp ? "UP" : "DN"
    FileAppend, % TS() " | scroll-accel | " dir " | v=" v " t=" t "ms div=" divisor " cnt=" directionCount " " reason "`n", % Debug.Log.Path
  }
  Return v

  ScrollAccelTooltipOff:
    ToolTip
  Return
}

G_UIACleanup() {
  If (G_UIA) {
    ObjRelease(G_UIA)
    G_UIA := 0
  }
}

ExplorerShouldCloseOnEsc() {
  If !WinActive("ahk_class CabinetWClass")
    Return false
  If WinExist("ahk_class #32768")
    Return false
  Return !ExplorerFocusedOnTextInput()
}

ExplorerFocusedOnTextInput() {
  ; Inline rename box
  ControlGet, _renameVisible, Visible,, Edit1, A
  If (_renameVisible = 1)
    Return true

  ControlGetFocus, _focused, A
  If (_focused = "")
    Return false

  ; Address bar, search box, editable combos, and similar text-entry hosts
  Return (InStr(_focused, "Edit") = 1
    || InStr(_focused, "RichEdit") = 1
    || InStr(_focused, "ComboBox") = 1
    || InStr(_focused, "SearchEditBox") = 1
    || InStr(_focused, "InputSiteWindowClass") = 1)
}

SuperwhisperCloseWindow(hwnd:=0) {
  if (hwnd)
    WinActivate, ahk_id %hwnd%
  SendInput, !+{Pause}
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

ClipboardHasImage() {
  Return DllCall("IsClipboardFormatAvailable", "UInt", 2) && !DllCall("IsClipboardFormatAvailable", "UInt", 15)
}

PasteNormalizedClipboard() {
  ActivateMouseWindow("ahk_exe alacritty.exe")
  _savedClipboard := ClipboardAll
  _text := Clipboard
  _text := StrReplace(_text, "`r`n", "`r")
  _text := StrReplace(_text, "`n", "`r")
  If (!ClipboardSetRawText(_text))
    Clipboard := _text
  ClipWait, 0.2
  SendInput, ^v
  Sleep, 100
  Clipboard := _savedClipboard
}

ActivateMouseWindow(winTitle) {
  MouseGetPos,,, _hwnd
  If (!WinExist(winTitle " ahk_id " _hwnd)) {
    If (winTitle = "ahk_exe alacritty.exe")
      _hwnd := AlacrittyWindowAtMouse()
    If (!_hwnd || !WinExist(winTitle " ahk_id " _hwnd))
      Return false
  }
  WinActivate, ahk_id %_hwnd%
  WinWaitActive, ahk_id %_hwnd%,, 0.2
  Return true
}

GetAlacrittyDpiScale() {
  WinGet, _hwnd, ID, ahk_exe alacritty.exe
  If (_hwnd)
    _dpi := DllCall("User32.dll\GetDpiForWindow", "Ptr", _hwnd, "UInt")
  If (!_dpi)
    _dpi := DllCall("User32.dll\GetDpiForSystem", "UInt")
  If (!_dpi)
    _dpi := 96
  Return _dpi / 96
}

AlacrittyMenuRightClick() {
  global G_AlacrittyMenuLeftWidth, G_AlacrittyMenuTopHeight
  CoordMode, Mouse, Screen
  MouseGetPos, _x, _y
  _hwnd := AlacrittyWindowAtMouse()
  If (!_hwnd)
    Return false
  WinGetPos, _left, _top, _width, _height, ahk_id %_hwnd%
  If (_x < _left || _x >= _left + _width || _y < _top || _y >= _top + _height)
    Return false
  Return ((_x < _left + G_AlacrittyMenuLeftWidth)
    || (_y < _top + G_AlacrittyMenuTopHeight))
}

AlacrittySurfaceIsUnderMouse() {
  Return AlacrittyWindowAtMouse() != 0
}

AlacrittyWindowAtMouse() {
  CoordMode, Mouse, Screen
  MouseGetPos, _x, _y, _under
  WinGet, _exe, ProcessName, ahk_id %_under%
  If (_exe = "alacritty.exe")
    Return _under
  If (_exe != "herdr.exe")
    Return 0
  WinGet, _list, List, ahk_exe alacritty.exe
  Loop, %_list% {
    _hwnd := _list%A_Index%
    WinGetPos, _left, _top, _width, _height, ahk_id %_hwnd%
    If (_x >= _left && _x < _left + _width && _y >= _top && _y < _top + _height)
      Return _hwnd
  }
  Return 0
}


ClipboardSetRawText(text) {
  _length := StrLen(text)
  _hText := DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", (_length + 1) * 2, "Ptr")
  If (!_hText)
    Return false
  _pText := DllCall("GlobalLock", "Ptr", _hText, "Ptr")
  If (!_pText) {
    DllCall("GlobalFree", "Ptr", _hText)
    Return false
  }
  StrPut(text, _pText, _length + 1, "UTF-16")
  DllCall("GlobalUnlock", "Ptr", _hText)
  If (!DllCall("OpenClipboard", "Ptr", 0)) {
    DllCall("GlobalFree", "Ptr", _hText)
    Return false
  }
  DllCall("EmptyClipboard")
  If (!DllCall("SetClipboardData", "UInt", 13, "Ptr", _hText)) {
    DllCall("CloseClipboard")
    DllCall("GlobalFree", "Ptr", _hText)
    Return false
  }
  DllCall("CloseClipboard")
  Return true
}

ConvertClipboardImageToFile() {
  If (!DllCall("IsClipboardFormatAvailable", "UInt", 2) || DllCall("IsClipboardFormatAvailable", "UInt", 15))
    Return false
  clipFile := A_Temp . "\clipboard_paste.png"
  SaveClipboardImage(clipFile)
  If !FileExist(clipFile)
    Return false
  ClipboardSetFile(clipFile)
  Return true
}

ScreenshotWindow(savePath := "", cornerRadius := 0) {
  WinGet, hwnd, ID, A
  WinGet, exStyle, ExStyle, ahk_id %hwnd%
  wasOnTop := (exStyle & 0x8)
  If (!wasOnTop)
    WinSet, AlwaysOnTop, On, ahk_id %hwnd%
  Sleep, 100
  Send !{PrintScreen}
  Sleep, 50
  If (!wasOnTop)
    WinSet, AlwaysOnTop, Off, ahk_id %hwnd%
  If (savePath != "")
    SaveClipboardImage(savePath, cornerRadius)
}

SaveClipboardImage(filePath, cornerRadius := 0) {
  SplitPath, filePath,,, ext
  encoderCLSID := (ext = "png") ? "{557CF406-1A04-11D3-9A73-0000F81EF32E}"
    : "{557CF401-1A04-11D3-9A73-0000F81EF32E}"
  hGdi := DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
  VarSetCapacity(si, A_PtrSize = 8 ? 24 : 16, 0)
  NumPut(1, si, 0, "UInt")
  pToken := 0
  DllCall("gdiplus\GdiplusStartup", "Ptr*", pToken, "Ptr", &si, "Ptr", 0)
  pBitmap := 0
  pDest := 0
  Try {
    If (!DllCall("OpenClipboard", "Ptr", 0))
      Return
    hBmp := DllCall("GetClipboardData", "UInt", 2, "Ptr")
    If (!hBmp) {
      DllCall("CloseClipboard")
      Return
    }
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hBmp, "Ptr", 0, "Ptr*", pBitmap)
    DllCall("CloseClipboard")
    If (!pBitmap)
      Return

    If (cornerRadius > 0) {
      DllCall("gdiplus\GdipGetImageWidth", "Ptr", pBitmap, "UInt*", imgW)
      DllCall("gdiplus\GdipGetImageHeight", "Ptr", pBitmap, "UInt*", imgH)
      DllCall("gdiplus\GdipCreateBitmapFromScan0"
        , "Int", imgW, "Int", imgH, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", pDest)
      pGraphics := 0
      DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pDest, "Ptr*", pGraphics)
      DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", 4)  ; AntiAlias
      DllCall("gdiplus\GdipSetPixelOffsetMode", "Ptr", pGraphics, "Int", 2)  ; HighQuality
      pBrush := 0
      DllCall("gdiplus\GdipCreateTexture", "Ptr", pBitmap, "Int", 0, "Ptr*", pBrush)
      pPath := 0
      DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", pPath)
      _dpi := DllCall("GetDpiForSystem", "UInt")
      r := cornerRadius * _dpi / 96.0, d := r * 2.0, w := imgW + 0.0, h := imgH + 0.0
      DllCall("gdiplus\GdipAddPathArc", "Ptr", pPath
        , "Float", 0.0, "Float", 0.0, "Float", d, "Float", d, "Float", 180.0, "Float", 90.0)
      DllCall("gdiplus\GdipAddPathArc", "Ptr", pPath
        , "Float", w-d, "Float", 0.0, "Float", d, "Float", d, "Float", 270.0, "Float", 90.0)
      DllCall("gdiplus\GdipAddPathArc", "Ptr", pPath
        , "Float", w-d, "Float", h-d, "Float", d, "Float", d, "Float", 0.0, "Float", 90.0)
      DllCall("gdiplus\GdipAddPathArc", "Ptr", pPath
        , "Float", 0.0, "Float", h-d, "Float", d, "Float", d, "Float", 90.0, "Float", 90.0)
      DllCall("gdiplus\GdipClosePathFigure", "Ptr", pPath)
      DllCall("gdiplus\GdipFillPath", "Ptr", pGraphics, "Ptr", pBrush, "Ptr", pPath)
      DllCall("gdiplus\GdipDeletePath", "Ptr", pPath)
      DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
      DllCall("gdiplus\GdipDeleteGraphics", "Ptr", pGraphics)
      DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
      pBitmap := pDest
      pDest := 0
    }

    VarSetCapacity(clsid, 16, 0)
    DllCall("ole32\CLSIDFromString", "WStr", encoderCLSID, "Ptr", &clsid)
    DllCall("gdiplus\GdipSaveImageToFile", "Ptr", pBitmap, "WStr", filePath, "Ptr", &clsid, "Ptr", 0)
  } Finally {
    If (pDest)
      DllCall("gdiplus\GdipDisposeImage", "Ptr", pDest)
    If (pBitmap)
      DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
    DllCall("gdiplus\GdiplusShutdown", "Ptr", pToken)
    DllCall("FreeLibrary", "Ptr", hGdi)
  }
}

ClipboardSetFile(filePath) {
  pathLen := StrLen(filePath)
  dropSize := 20 + (pathLen + 2) * 2
  hDrop := DllCall("GlobalAlloc", "UInt", 0x42, "UPtr", dropSize, "Ptr")
  pDrop := DllCall("GlobalLock", "Ptr", hDrop, "Ptr")
  NumPut(20, pDrop + 0, "UInt")
  NumPut(1, pDrop + 16, "Int")
  StrPut(filePath, pDrop + 20, pathLen + 1, "UTF-16")
  DllCall("GlobalUnlock", "Ptr", hDrop)
  DllCall("OpenClipboard", "Ptr", 0)
  DllCall("EmptyClipboard")
  DllCall("SetClipboardData", "UInt", 15, "Ptr", hDrop)
  DllCall("CloseClipboard")
}

RemoveToolTip:
  ToolTip
Return

; === Module Includes ===
#Include %A_ScriptDir%\processes.ahk
#Include %A_ScriptDir%\terminal-anywhere.ahk
#Include %A_ScriptDir%\extended-spy.ahk
#Include %A_ScriptDir%\mbutton-drag.ahk
#Include %A_ScriptDir%\window-spawning.ahk
#Include %A_ScriptDir%\herdr-anywhere.ahk
