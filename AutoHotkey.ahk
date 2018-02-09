; Global AutoHotKey keys
; #    Windows key
; ^    Ctrl 
; !    Alt
; +    Shift
; +!   Shift+Alt

;
; TODO: 
; Double click from Everything and uTorrent launches from Explorer
; Ctrl+W in sublime toggles word wrap
; Del in MPC deletes file, skips rl    Media_Next
; Esc, Alt+F4 in Everything hide window


#SingleInstance Force
#NoEnv
#Persistent
#UseHook
#MaxHotkeysPerInterval 300

SendMode Input
SetWorkingDir %A_ScriptDir%

; Prevent script proceeding
if (WinActive("ahk_class TscShellContainerClass"))
    Return

; FileGetAttrib, attribs, %A_ScriptFullPath%
; if (attribs="A") {
;        FileSetAttrib, -A, %A_ScriptFullPath%
;        TrayTip, Reloaded script, %A_ScriptFullPath%,, 1
; }
; OnExit, ExitSub
; Return
; ExitSub:
;        if (A_ExitReason="Reload") {
;                FileSetAttrib, +A, %A_ScriptFullPath%
;        }
; ExitApp


; ~LButton:: 
; If (A_TimeSincePriorHotkey<400) and (A_PriorHotkey="~LButton")
;  ToolTip, You double Left clicked on something 
; Return

 
; #Include WindowDraggingResizing.ahk
; #Include TaskbarNavigation-NumPadMapped.ahk
; #Include TaskbarNavigation-AltTabMapped.ahk

;
; Add item to AHK tray
; https://autohotkey.com/docs/commands/Menu.htm
;
; Menu Default Menu, Standard
; Menu, tray, add    ; Creates a separator line.
; Menu, tray, add, Item1, MenuHandler    ; Creates a new menu item.
; return
; MenuHandler:
; MsgBox You selected %A_ThisMenuItem% from menu %A_ThisMenu%.
; return


;
; AHK bindings
;
+!r::Reload
+!p::
    Suspend
    Pause,,1
Return


;
; Sublime Text
;
#IfWinActive ahk_exe sublime_text.exe
    !F4::Send {Alt Down}f{AltUp}x
    ^Tab::Send {Ctrl Down}{PgDn}{Ctrl Up}
    +^Tab::Send {Ctrl Down}{PgUp}{Ctrl Up}
    +!d::Send {Alt Down}f{AltUp}e{Ctrl Down}
    ^w::Send {Alt Down}v{AltUp}w
    ~^s::
        SetTitleMatchMode, RegEx
        #IfWinActive "^AutoHotKey.ahk .*? - Sublime Text"
        SetTitleMatchMode, 1
            Reload
        #IfWinActive
    Return
    ^;::Send ^/
    Return
#IfWinActive
; Alt+Shift+E = Edit current script as normal user
+!e::Run RunFromProcess-x64 explorer.exe notepad %A_ScriptFullPath%
+!t::Run RunFromProcess-x64 explorer.exe notepad "C:\Users\Rod\Desktop\Pip's Island\todo.txt"

; Google Chrome
#IfWinActive ahk_exe chrome.exe
    +!d::
        ; ToolTip, Duplicating tab
        ; SetTitleMatchMode, 2
        ; WinWaitActive, [ WinTitle, WinText, Seconds, ExcludeTitle, ExcludeText]
        SendInput, {Alt Down}d{Alt Up}
        Sleep 200
        ; WinWaitActive, ahk_exe chrome.exe
        ; WinActivate
        ; if (WinActive(""))
        ; WinGetTitle, Title, ahk_id %Window%
        ; WinWaitActive, " "
        ; ToolTip, "%Title%"
        SendInput, {Alt Down}{Enter}{Alt Up}
        ; SendInput !d!{enter}
    Return
;    SetTitleMatchMode, RegEx
;    #IfWinExist ^AutoHotKey(.* - )?Google Chrome
;        ^s::
;        Return
    #IfWinExist
    Return
#IfWinActive


;;
;; Detect Open/Save dialog
;; https://autohotkey.com/board/topic/9362-detect-opensave-dialog/
;; 
; #n::
;    If (DialogWindowActive())
;        MsgBox, Open/Save dialog detected
;    Else
;        MsgBox, Open/Save not detected
; Return
;
; DialogWindowActive()
; { 
;    WinGet, active_hwnd, ID, A
;    {
;        if ( IsDialog( active_hwnd ) )
;            return 1
;        else 
;            return 0
;    } 
;
;    return 0
; }
;
;; ------------------------------------------------------------------------------------------------
;
; IsDialog(dlg)
; {
;
;    local toolbar, edit, combo, button
;
;    toolbar := FindWindowExID(dlg, "ToolbarWindow32", "0x440")        ; windows XP
;    if (toolbar = "0")
;        toolbar := FindWindowExID(dlg, "ToolbarWindow32", "0x001")    ; windows 2k
;
;    edit     := FindWindowExID(dlg, "Edit", "0x480")            ; edit field
;    combo    := FindWindowExID(dlg, "ComboBoxEx32", "0x47C")    ; comboboxex field
;    button := FindWindowExID(dlg, "Button", "0x001")        ; second button
;
;
;    if (toolbar && (combo || edit) && button) 
;        return 1
;    else
;        return 0
; }
;
;
;; ------------------------------------------------------------------------------------------------
;; Iterate through controls with the same class, find the one with ctrlID and return its handle
;; Used for finding a specific control on a dialog
;
; FindWindowExID(dlg, className, ctrlId)
; {
;    local ctrl, id
;
;    ctrl = 0
;    Loop
;    {
;        ctrl := DllCall("FindWindowEx", "uint", dlg, "uint", ctrl, "str", className, "uint", 0 )
;        if (ctrlId = "0")
;        {
;            return ctrl
;        }
;
;        if (ctrl != "0")
;        {
;            id := DllCall( "GetDlgCtrlID", "uint", ctrl )
;            if (id = ctrlId) 
;                return ctrl             
;        }
;        else 
;            return 0
;    }
; }
;
;
;; firefox save
; #IfWinActive, ahk_class MozillaWindowClass
; $RButton::
;    Sleep 150
;    SendInput {RButton}
;    Sleep 50
;    Send v
;    Sleep 100
;    #IfWinActive, Save
;        Sleep 100
;        SendInput {Enter}
;        Sleep 100
;        SendInput {Enter}
;        Sleep 50
;        SendInput {Enter}
;    Return
; #IfWinActive


;; http://www.autohotkey.com/board/topic/95834-using-winwait-effectively-or-how-else-should-i-execute-an-action-when-a-pop-up-window-appears/#entry603588
;; https://autohotkey.com/board/topic/121689-virustotal-uploader-script-to-auto-close-its-dialog-windows/
; TODO:
; μTorrent
; ahk_class #32770
; ahk_exe uTorrent.exe
; Focused control:
; ClassNN: Button1
; Text: &Yes
;
; TODO:
; Dropbox Notification
; ahk_class Qt5QWindowToolSaveBits
; ahk_exe Dropbox.exe


; ; Close VirusTotal window
; IfWinExist ahk_exe VirusTotalUploader2.2.exe {
;    winactivate ahk_class Chrome_WidgetWin_1
; else
;    run, "C:\Users\xxx\AppData\Local\Google\Chrome\Application\chrome.exe"
; WinWaitActive ahk_class Chrome_WidgetWin_1

; Loop 
; {
;     WinWait, VirusTotal Uploader
;     IfWinExist, VirusTotal Uploader
;         {
;         ControlGetText, Status, Static1
;         IfInString, Status, Checking, WinHide
;         IfInString, Status, Hash found
;             {
;                 Sleep, 100
;                 WinClose
;             }
;         }
;     Sleep, 500
; }
; Return


; ; MPC Shift+WheelUp/Down = Scroll by 3 lines
; ; If (WinActive("ahk_class QWidget") and (WinActive("ahk_class QWidget")) {
; MPC MClick + WheelUp/Down Scroll by 3 lines
; Tags: fast wheel scroll
; ; #IfWinActive ahk_class MPC-BE
; ; +WheelDown::SendMessage,0x0111,904,,,ahk_class MPC-BE
; ; +WheelUp::SendMessage,0x0111,903,,,ahk_class MPC-BE 
; +WheelDown::SendMessage,0x0111,904,,,ahk_class MediaPlayerClassicW
; +WheelUp::SendMessage,0x0111,903,,,ahk_class MediaPlayerClassicW 
; this enables the hotkey - i.e. "begins waiting for LButton"
; Hotkey, LButton, left_button, On
#IfWinActive ahk_class MediaPlayerClassicW
; #IfWinExist ahk_class MediaPlayerClassicW
; left_button:  ; <-- this is a regular label
    ; MouseGetPos, , , mWin, mCont
    ; WinExist may be used to check that mWin is the correct window.
    ; MouseGetPos, CursorX, CursorY, Window, ClassNN
    ; WinGetClass, ahk_class, ahk_id %Window%
    ; ; check if winexist ahk_class
    ; RButton & WheelDown::SendInput, {Shift Down}{Right}{Shift Up}
    ; ToolTip, RButton+WheelDown MPC
    ; RButton & WheelUp::SendInput, {Shift Down}{Right}{Shift Up}
    ; ToolTip, RButton+WheelUp MPC
+WheelDown::SendInput, {Shift Down}{Right}{Shift Up}
+WheelUp::SendInput, {Shift Down}{Left}{Shift Up}
; return
; RButton & WheelDown::SendInput, {Shift Down}{Right}{Shift Up}
; ;RButton & WheelUp::SendInput, {Shift Down}{Left}{Shift Up}
; #IfWinExist
#IfWinActive
; ~MWheel & RButto::
;  ToolTip, WheelDown MPC
; ; $+WheelDown::SendInput, {Shift Down}{Right}{Shift Up}
; ; $+WheelUp::SendInput, {Shift Down}{Left}{Shift Up}
; ; $+WheelDown::SendInput, {Click WheelDown 3}
; ; $+WheelUp::SendInput, {Click WheelUp 3}
; }


;
; VLC next on mouse middle
;
#IfWinActive ahk_class QWidget
$*MButton::Send n
#IfWinActive


;;
;; Snap windows to edges of screen
;; https://autohotkey.com/board/topic/44474-make-windows-snap-to-the-edges-of-the-screen/
;;
; #if (WinActive("ahk_class QWidget") and (MouseIsOver "ahk_class QWidget"))
; ~LButton::
; CoordMode, Mouse    ; Switch to screen/absolute coordinates.
; MouseGetPos, EWD_MouseStartX, EWD_MouseStartY, EWD_MouseWin
; WinGetPos, EWD_OriginalPosX, EWD_OriginalPosY,,, ahk_id %EWD_MouseWin%
; WinGet, EWD_WinState, MinMax, ahk_id %EWD_MouseWin% 
; if EWD_WinState = 0    ; Only if the window isn't maximized 
;        SetTimer, EWD_WatchMouse, 10 ; Track the mouse as the user drags it.
; Return
; #IfWinActive
;
; EWD_WatchMouse:
; GetKeyState, EWD_LButtonState, LButton, P
; if EWD_LButtonState = U    ; Button has been released, so drag is complete.
; {
;        SetTimer, EWD_WatchMouse, off
;        Return
; }
; GetKeyState, EWD_EscapeState, Escape, P
; if EWD_EscapeState = D    ; Escape has been pressed, so drag is cancelled.
; {
;        SetTimer, EWD_WatchMouse, off
;        WinMove, ahk_id %EWD_MouseWin%,, %EWD_OriginalPosX%, %EWD_OriginalPosY%
;        Return
; }
;; Otherwise, reposition the window to match the change in mouse coordinates
;; caused by the user having dragged the mouse:
; CoordMode, Mouse
; MouseGetPos, EWD_MouseX, EWD_MouseY
; WinGetPos, EWD_WinX, EWD_WinY,,, ahk_id %EWD_MouseWin%
; SetWinDelay, -1     ; Makes the below move faster/smoother.
; WinMove, ahk_id %EWD_MouseWin%,, EWD_WinX + EWD_MouseX - EWD_MouseStartX, EWD_WinY + EWD_MouseY - EWD_MouseStartY
; EWD_MouseStartX := EWD_MouseX    ; Update for the next timer-call to this subroutine.
; EWD_MouseStartY := EWD_MouseY
; Return
;
; snap_prox = 20
; KeyWait, LButton
; SysGet, screen, MonitorWorkArea
; WinGetActiveStats, title_act, w_act, h_act, x_act, y_act ; active window title and dimensions
; If (w_act < screenright-snap_prox) {
;        If (x_act > screenleft-snap_prox AND x_act < screenleft OR x_act < screenleft+snap_prox AND x_act > screenleft)
;                WinMove, %title_act%,, screenLeft
;                        If (x_act + w_act > screenright-snap_prox AND x_act + w_act < screenright OR x_act + w_act < screenright+snap_prox AND x_act + w_act > screenright)
;                                WinMove, %title_act%,, (screenright-w_act)
; }
; If (h_act < screenbottom-snap_prox) {
;        If (y_act > screentop-snap_prox AND y_act < screentop OR y_act < screentop+snap_prox AND y_act > screentop)
;                WinMove, %title_act%,,, screentop
;        If (y_act + h_act > screenbottom-snap_prox AND y_act + h_act    < screenbottom OR y_act + h_act < screenbottom+snap_prox AND y_act + h_act > screenbottom)
;                WinMove, %title_act%,,, (screenbottom-h_act)
; }
; Return


;;
;; Multiply mouse wheel speed in Eclipse main edit control window
;;
; #IfWinActive ahk_class SWT_Window0
; WheelUp::
; WheelDown::
; ControlGetFocus, active
; StringGetPos, pos, active, SWT_Window
;; MsgBox, pos
; Critical
; if (pos = 0) {
;        WheelSteps := A_EventInfo*2
;        SendInput, {%A_ThisHotkey% %WheelSteps%}
; }
; else {
;        WheelSteps := A_EventInfo
;        SendInput, {%A_ThisHotkey%}
; }
; Return
; #IfWinActive


;
; Restore Win+X key functionality disabled via Group Policy on CORE
;
if (A_ComputerName = "CORE") {
    #r::
        SetTitleMatchMode, 3
        IfWinExist, Run
            WinActivate
        else
            Run, shell:::{2559a1f3-21d7-11d4-bdaf-00c04f60b9f0}
        IfWinNotActive
            WinWait, Run
        WinActivate
    Return


    ; Win+D = Show desktop
    toggle = 0
    #d::
        if toggle := !toggle
            WinMinimizeAll
        else
            WinMinimizeAllUndo
    Return
}

;; Win+L: Turn off monitor
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


;; Win+E = Open Explorer window
; #e::
;    IfWinExist Run
;            WinActivate
;    Else
;            Run ::{20D04FE0-3AEA-1069-A2D8-08002B30309D}
;            IfWinNotActive
;                    WinWait, Computer
;                    WinActivate
; Return


; Win+S = Run or activate Everything
; to send original key:
; SendInput {RWin Down}s{RwinUp}


DetectHiddenWindows, On
#s::
;     If WinActive("ahk_class EVERYTHING")
;         Send !d
;     Else If WinExist("ahk_class EVERYTHING")
    If WinExist("ahk_class EVERYTHING") {
        WinShow
        WinActivate
    }
    Else
        Run RunFromProcess-x64 explorer.exe C:\Program Files\Everything\Everything.exe
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

; #s::
; SetTitleMatchMode, RegEx
; IfWinActive ^(.* - )?Everything$
;         Return 
; IfWinExist ^(.* - )?Everything$
;         WinActivate
; Else
;         Run RunFromProcess-x64 explorer.exe C:\Program Files\Everything\Everything.exe
;         IfWinNotActive
;                 WinWait, ^(.* - )?Everything
;                 WinActivate
; Return

; ; Doesn't work
; SetTitleMatchMode, RegEx
; #IfWinActive ^(.* - )?Everything$
;     WinClose
; #IfWinActive
; 
; DetectHiddenWindows, On
; #IfWinNotExist ^(.* - )?Everything$
;     Run RunFromProcess-x64 explorer.exe C:\Program Files\Everything\Everything.exe
; #IfWinExist
; DetectHiddenWindows, Off
; SetTitleMatchMode, 1


; ; Doesn't work
; ; Shift+WheelUp/Down = Scroll by 30 lines
; ; Alt+WheelUp/Down = Scroll horizontally
; +WheelUp::Send {Click WheelUp 30}
; +WheelDown::Send {Click WheelDown 30}
; ; #IfWinActive ahk_class PX_WINDOW_CLASS
; ; {
;         ; WheelUp::Click WheelUp 3
;         ; WheelDown::Click WheelDown 3
;         ; Return
; ; }
; ; !WheelUp::Send {Click WheelLeft 2}
; ; !WheelDown::Send {Click WheelRight 2}


; Run Process Hacker
^+`::Run nircmd runassystem "C:\Program Files\Process Hacker 2\ProcessHacker.exe"

; http://www.howtogeek.com/howto/8955/make-backspace-in-windows-7-or-vista-explorer-go-up-like-xp-did/
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

;
; Volume controls
;
#IfWinNotActive ahk_class TscShellContainerClass
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


; Go to next song in Spotify
; http://stackoverflow.com/questions/28957636/hotkey-for-next-song-in-spotify
; https://autohotkey.com/board/topic/94263-problem-with-using-multiple-mouse-buttons-as-hotkey/
; https://autohotkey.com/board/topic/36239-spotify-global-hotkeys/

DetectHiddenWindows, On 
#IfWinExist ahk_class SpotifyMainWindow
+!Left::
    Send {Media_Prev}
    ; ControlSend, ahk_parent, ^{Left}, ahk_class SpotifyMainWindow 
    ; TrayTip, , Previous track
return 
~XButton1 & XButton2::
~XButton2 & XButton1::
+!Right::
    ; DetectHiddenWindows, On 
    Send {Media_Next}
    ; ControlSend, ahk_parent, ^{Right}, ahk_class SpotifyMainWindow 
    ; DetectHiddenWindows, Off
    ; TrayTip, , Next track
Return

;SetTimer, Toast, 1000
;    ToolTip,
;Return
;Toast:
;    DetectHiddenWindows, On
;    WinGetTitle, text, ahk_class SpotifyMainWindow
;    ToolTip, %text%
;    StringTrimLeft, text2, text, 10
;    IfNotInString, Title, %text2%
;    {
;        Title = %text2%
;        TrayTip, % Title
;    }
;Return
#IfWinExist
DetectHiddenWindows, Off

; ;
; ; Accelerated scrolling
; ; https://autohotkey.com/board/topic/48426-accelerated-scrolling-script/?p=333222
; ;
; ; #If (WinActive("ahk_exe explorer.exe") or WinActive("ahk_class PROCMON_WINDOW_CLASS") or 
; #IfWinNotActive, abcd
; ; #If (WinActive("ahk_exe explorer.exe") or WinActive("ahk_class MPC-BE") or WinActive("ahk_class MediaPlayerClassicW"))
; ; The length of a scrolling session. Keep scrolling within this time to accumulate boost. ; Default: 500. Recommended between 400 and 1000.
; WheelUp::
; WheelDown::
; timeout := 500
; ; If you scroll a long distance in one session, apply additional boost factor. The higher the ; value, the longer it takes to activate, and the slower it accumulates. ; Set to zero to disable ; completely. Default: 30.
; boost := 3
; ; Spamming applications with hundreds of individual scroll events can slow them down. This sets ; the maximum number of scrolls sent per click, i.e. max velocity. ; Default: 60.
; limit := 30
; distance := 0
; vmax := 1
; t := A_TimeSincePriorHotkey
; ; ToolTip, t %t% timeout 500
; ; ToolTip, timeout: %timeout%
; if (A_PriorHotkey = A_ThisHotkey && t < timeout) {
; ; if (A_PriorHotkey = A_ThisHotkey) {
;    ; ToolTip, t: %t% timeout: 500
;    ; t := A_TimeSincePriorHotkey
;        distance++
;        v := (t < 80 && t > 1) ? (250.0 / t) - 1 : 1
;        if (boost > 1 && distance > boost)
;        {
;            if (v > vmax)
;                vmax := v
;            else
;                v := vmax
;            v *= distance / boost
;        }
;        ; QuickToolTip(v, 500)
;        v := (v > 1) ? ((v > limit) ? limit : Floor(v)) : 1
;        MouseClick, %A_ThisHotkey%, , , v
;    QuickToolTip(text, delay)
;    {
;        ToolTip, ScrollAccel: %text%
;        SetTimer ToolTipOff, %delay%
;        Return
;        ToolTipOff:
;        SetTimer ToolTipOff, Off
;        ToolTip
;        Return
;    }
; }
; else {
;        ; QuickToolTip("normal", 500)
;        MouseClick, %A_ThisHotkey%
; }
; ; #If
; Return
; ; #If
; #IfWinNotActive


; 
; Scroll window under mouse cursor
; Tags: combined, scroll under cursor, scroll window under cursor
; https://autohotkey.com/board/topic/78284-boldly-scroll-where-no-one-has-scrolled-before/page-2
; #UseHook
#IfWinNotActive ahk_class #32770
WheelUp::
WheelDown::
    ; Critical
    CoordMode, Mouse, Screen
    ; #MaxThreadsPerHotkey 5
    MouseGetPos, CursorX, CursorY, Window ; , ClassNN
    WinGetClass, ahk_class, ahk_id %Window%
    ; -- Window under mouse cursor --
    WinGetTitle, Title, ahk_id %Window%
    WinGetText, VisibleText, ahk_id %Window%
    WinGet, WindowPID, PID, ahk_id %Window%
    WinGet, ControlText, ControlList, ahk_id %Window%
    CursorHwnd := DllCall("WindowFromPoint", "int64", CursorX | (CursorY << 32), "Ptr")
    If not(ahk_class = "ApplicationFrameWindow" or ahk_class = "Button") { ; DllCall doesn't work on these
        WheelSteps := A_EventInfo
        DllCall("SendMessage", "Ptr", CursorHwnd, "UInt", 0x20A, "Ptr", WheelSteps * (A_ThisHotkey == "WheelUp" ? 1 : -1) * 120 << 16, "Ptr", ( CursorY << 16 )|CursorX)
    }
    Else {
        If (A_ThisHotkey == "WheelUp")
            MouseClick WheelUp
        Else
            MouseClick WheelDown
    }
    ; Critical Off
Return
#IfWinActive

;; Get info from Window Under Mouse without clicking on it
;; https://autohotkey.com/board/topic/80855-get-info-from-window-under-mouse-without-clicking-on-it/?p=513888
;; https://autohotkey.com/board/topic/80855-get-info-from-window-under-mouse-without-clicking-on-it/?p=514092
Pause::
   UnderCursorToggle := ( ! UnderCursorToggle )
   If ( UnderCursorToggle )
      SetTimer ToolTipUnderCursor, 250
   Else
   {
      SetTimer ToolTipUnderCursor, Off
      ToolTip
      Clipboard := GetUnderCursorInfo(X, Y)
   }
Return
HexToDec(HexVal)
{
     Old_A_FormatInteger := A_FormatInteger
     SetFormat IntegerFast, D
     DecVal := HexVal + 0
     SetFormat IntegerFast, %Old_A_FormatInteger%
     Return DecVal
}
GetUnderCursorInfo(ByRef CursorX, ByRef CursorY)
{
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
     WindowUnderCursorInfo := "ahk_id " Window "`n"
            . "ahk_class " Class "`n"
            . "title: " Title "`n"
            . "control: " Control "`n"
            . "PID: " PID "`n"
            . "Cursor`" CursorHwnd "`n"
            . "process name: " PName "`n"
            . "top left (" WindowX ", " WindowY ")`n"
            . "(width x height) (" Width " x " Height ")`n"
            . "cursor's window position (" CursorX-WindowX ", " CursorY-WindowY ")`n"
            . "cursor's screen position (" CursorX ", " CursorY ")`n"
            ; . "BGR color: " BGR_Color " (" HexToDec("0x" SubStr(BGR_Color, 3, 2)) " , 
            ; . HexToDec("0x" SubStr(BGR_Color, 5, 2)) ", "
            ; . HexToDec("0x" SubStr(BGR_Color, 7, 2)) ")`n"
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
        , ( (A_ScreenWidth // 2) + TTXOffset )
        , ( (A_ScreenHeight // 2) + TTYOffset )
Return


; Description: Get extended attributes of window under mouse cursor
; Tags: Extended info window, 
; Permalink: https://autohotkey.com/boards/viewtopic.php?f=6&t=43544
; Author: aph
; Version: 0.6
; Hotkey: Win+w
#w::
    MouseGetPos, CursorX, CursorY, Window, ClassNN
    WinGetTitle, Title, ahk_id %Window%
    WinGetClass, ahk_class, ahk_id %Window%
    DetectHiddenText, On
    WinGetText, WindowText, ahk_id %Window%
    WinGet, WindowPID, PID, ahk_id %Window%
    WinGet, ControlText, ControlList, ahk_id %Window%
    CursorHwnd := DllCall("WindowFromPoint", "int64", CursorX | (CursorY << 32), "Ptr")
    WinGet, ControlText, ControlList, ahk_id %Window%
    StringReplace, ControlText, ControlText, `n, %A_SPACE%, All
    StringReplace, WindowText, WindowText, `n,  , All
    StringReplace, WindowText, WindowText, %A_SPACE%%A_SPACE%, , All
    If not (WindowText = "")
        WindowText = `n%WindowText%
    WinGetText, Text, ahk_id %Window%
    WinGet, ahk_exe, ProcessName, ahk_id %Window%
    WinGet, Path, ProcessPath, ahk_id %Window%
    ; TODO: Rewrite using . syntax
    UnderCursor =
(
Title: %Title%
ahk_id = %Window%
ahk_exe = %ahk_exe%
ahk_class = %ahk_class%
Path: %Path%
Process ID: %WindowPID%
Control ClassNN: %ClassNN%
CursorHwnd: %CursorHwnd%

Window Text:%WindowText%

Control Text:
%ControlText%
)
    Gui, Destroy
    SysGet, Workspace, MonitorWorkArea
    Gui, Add, Text, , Ctrl+C to copy to clipboard. Repeat %A_ThisHotkey% to update.
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
    Return
Return

; ; If not WinActive(ahk_class = "AutoHotkeyGUI") {
; ; #IfWinNotActive ahk_class AutoHotkeyGUI
;     #w::
;         ; TODO:
;         ; SendInput !{TAB}
;         ; https://autohotkey.com/board/topic/60521-how-to-activate-the-window-currently-under-mouse-cursor/
;         Centered = 0 ; Change this to 1 to center the window on the screen, otherwise it will snap near the bottom right
;         DetectHiddenText, On
;         MouseGetPos, CursorX, CursorY, Window, ClassNN
;         ; MouseGetPos, , CursorHwnd, ClassNN
;         ; WinGetClass, ahk_class, ahk_id %CursorHwnd%
;         WinGetTitle, Title, ahk_id %Window%
;         ; WinGetTitle, CursorPID, ahk_pid %CursorHWnd%
;         ; WinGetTitle = Title: ahk_id %Window%
;         WinGetClass, ahk_class, ahk_id %Window%
;         WinGetText, WindowText, ahk_id %Window%
;         WinGet, WindowPID, PID, ahk_id %Window%
;         ; WinGet, CursorHwnd, ID, ahk_pid %PID%
;         CursorHwnd := DllCall("WindowFromPoint", "int64", CursorX | (CursorY << 32), "Ptr")
;         ; WinGetTitle, CursorPID, ahk_pid %WindowPID%
;         WinGet, ControlText, ControlList, ahk_id %Window%
;         StringReplace, ControlText, ControlText, `n, %A_SPACE%, All
;         ; ControlText = %ControlText%
;         WinGetText, WindowText, ahk_id %Window%
;         StringReplace, WindowText, WindowText, `n,  , All
;         StringReplace, WindowText, WindowText, %A_SPACE%%A_SPACE%, , All
;         If not (WindowText = "")
;             WindowText = `n%WindowText%
;         ; WinGetTitle, Title, ahk_id %Window% ; retrieves window title from HWND
;         ; --- Control ---
;         ; https://autohotkey.com/boards/viewtopic.php?t=23987
;         ; ControlGet, OutputVar, Hwnd,, %FocusedClassNN%, %Title%
;         ; ControlGetText, ControlText, , ahk_id %ControlHwnd%
;         ; ControlGet, ListList, List, Selected, %FocusedClassNN%, %Title%
;         Loop, Parse, ListList, `n
;         { ; Rows are delimited by linefeeds (`n).
;             RowNumber := A_Index
;             Loop, Parse, A_LoopField, %A_Tab% ; Fields (columns) in each row are delimited by tabs (A_Tab).
;                 ListRows := ListRows . Row #%RowNumber% Col #%A_Index% is %A_LoopField%
;         }
;     ;    Loop Parse, List, `n    ; Rows are delimited by linefeeds (`n).
;     ;    {
;     ;            RowNumber := A_Index
;     ;            Loop Parse, A_LoopField, A_Tab    ; Fields (columns) in each row are delimited by tabs (A_Tab).
;     ;                    ; ListRows := ListRows . "Row #" RowNumber " Col #" A_Index " is " A_LoopField
;     ;                    ListRows := ListRows . RowNumber ", " A_Index ": " A_LoopField "`n"
;     ;    }
;         StringReplace, ListRows, List, `t, `n, All
;         ; ControlGet, ListList, List,, %FocusedClassNN%, %Title%
;         ; Loop, Parse, ListList, `n
;         ;     ComboBoxItems = ComboBox Item number %A_Index% is "%A_LoopField%."
;         ; ControlGet, ListText, List, , , ahk_id %ControlHwnd% ; "List", retrieves all the text from a ListView, ListBox, or ComboBox controls
;         ; DetectHiddenText, On
;         WinGetText, Text, ahk_id %Window%
;         ; count := StrSplit(WindowText, "`n")
;         ; TrayTip, , % "Number of newlines: "count
;         ; Loop, Parse, WindowText, `n
;         ; {
;             ; Loop, Parse, A_LoopField, `n
;                 ; WindowText := WindowText . " `n"
;         ; }
;         ; Loop, Parse, WindowText, \n
;             ; StringReplace, WindowText, WindowText, %A_LoopField%
;         ;StringReplace, WindowText, WindowText, `n, %A_SPACE%,, All
;         WinGet, ahk_exe, ProcessName, ahk_id %Window%
;         WinGet, Path, ProcessPath, ahk_id %Window%
;         ; List Text: %ListText%
;         ; List Rows: %ListRows%
;         ; CursorHwnd: %CursorHwnd%
;         ; PID: %CursorPID%
;         UnderCursor = 
; (
; Title: %Title%
; ahk_id = %Window%
; ahk_exe = %ahk_exe%
; ahk_class = %ahk_class%
; Path: %Path%
; PID: %WindowPID%
; Control ClassNN: %ClassNN%
; CursorHwnd: %CursorHwnd%

; Window Text:%WindowText%

; Control Text:
; %ControlText%
; )
;         ; TODO:
;         ; Add copy to clipboard buttons
;         Gui, Destroy
;         SysGet, Workspace, MonitorWorkArea
;         ; Gui, Show, AutoSize Center
;         ; Gui, Add, Edit, vInfo ReadOnly +Wrap w300, %UnderCursor%
;         Gui, Add, Text, , Ctrl+C to copy to clipboard. Repeat %A_ThisHotkey% to update.
;         ; Style with BG color instead of making editable
;         ; Gui, Add, Edit, vInfo ReadOnly +Wrap w400, %UnderCursor%
;         Gui, Add, Edit, vInfo +Wrap w400, %UnderCursor%
;         ; WinGetPos, ParentX, ParentY,,, ahk_id %ParentHWND%
;         ; GuiControl, Move, Info, % "w"WorkSpaceRight/8.5 " h"WorkSpaceBottom/7 ; Height inherits from control. Width too small on Chrome
;         ; GuiControl, Delete
;         Gui, +LastFound +AlwaysOnTop +Resize +Owner
;         GuiHwnd := WinExist()
;         ; WinGet, scriptPID, PID, %A_ScriptFullPath% - AutoHotkey v
;         WinGet, scriptPID, PID, %A_ScriptName%
;         ; ControlGet, Edit1Hwnd, %scriptPID%, , Edit1
;         ; GuiControlGet,TextVarName
;         ; Gui, Add, Edit, vInfo ReadOnly +Wrap w300, %UnderCursor%
;         ; Gui, Add, Edit, vInfo w400 +Wrap w400, %UnderCursor%
;         ; WinGetPos, ParentX, ParentY,,, ahk_id %ParentHWND%
;         ; GuiControl, Delete
;         ; Gui, Hide
;         ; GuiControl, Move, Info, h500
;         ; Gui, Add, Text, , GuiHwnd: %GuiHwnd%`nScriptPID: %scriptPID%
;         ; Gui, Show, Hide
;         ; Gui, Show, h400 Hide
;         ; GuiControl, Move, vInfo, h280
;         ; Gui, Show, h%GuiCtrlH% Hide
;         Gui, Show, NoActivate h260 Hide
;         GuiControlGet, GuiCtrl, Pos, Info  ; The position/size will be stored in GuiCtrlX, GuiCtrlY, GuiCtrlW, and GuiCtrlH
;         ; ToolTip, %GuiCtrlX% %GuiCtrlY% %GuiCtrlW% %GuiCtrlH%
;         GuiControl, Move, Info, h220
;         ; GuiControl, Move, OK, x100 y200 h500  ; Move the OK button to a new location.
;         ; ControlGet, Edit1Hwnd, , , ahk_id %ControlHwnd%
;         AspectRatio := WorkspaceRight/WorkSpaceBottom
;         ; GuiControl, Move, OK, x100 y200 h500  ; Move the OK button to a new location.
;         ; GuiControl, Focus, LastName  ; Set keyboard focus to the control whose variable or text is "LastName".
;         ; TextVar:="text second time"
;         ; GuiControl,,TextVar,%TextVar%
;         If (!Centered) {
;             GUI_ID := WinExist()
;             DetectHiddenWindows, On
;             WinGetPos, GUIX, GUIY, GUIWidth, GUIHeight, ahk_id %GUI_ID%
;             DetectHiddenWindows, Off
;             ; ToolTip, GUIX: %GUIX% GUIY: %GUIY% GUIWidth: %GUIWidth% GUIHeight: %GUIHeight%
;             ; Gui, Add, Text, , GUIX: %GUIX%, GUIY: %GUIY%, GUIWidth: %GUIWidth%, GUIHeight: %GUIHeight%
;             Offset = 30
;             ; %GUIX% %GUIY% %GUIWidth% %GUIHeight%
;             if not (WorkSpace) {
;                 ; Gui, Show, +AutoSize % "x"WorkspaceRight-GUIWidth-WorkspaceRight/Offset/AspectRatio " y"WorkspaceBottom-GUIHeight-WorkSpaceBottom/Offset, Cursor info
;                 ; Gui, Show, AutoSize Center, Cursor info
;                 ; Gui, Show, h500, Cursor info
;                 ;  x(WorkspaceRight-GUIWidth-WorkspaceRight/Offset/AspectRatio) y(WorkspaceBottom-GUIHeight-WorkSpaceBottom/Offset)
;                 ; Gui, Show, % "x"WorkspaceRight-GUIWidth-WorkspaceRight/Offset/AspectRatio " y"WorkspaceBottom-GUIHeight-WorkSpaceBottom/Offset, Window under cursor
;                 Gui, Show, % "NoActivate x"WorkspaceRight-GUIWidth-WorkspaceRight/Offset/AspectRatio " y"WorkspaceBottom-GUIHeight-WorkSpaceBottom/Offset, Window under cursor
;                 ; Gui, Show, "x"WorkspaceRight-GUIWidth-WorkspaceRight/Offset/AspectRatio " y"WorkspaceBottom-GUIHeight-WorkSpaceBottom/Offset " hAuto", Window under cursor
;             }
;         }
;         Else {
;             Gui, Show, NoActivate, Window Extended Info ; Empty param can be AutoSize Center
;         }
;         ; WinActivate, %Window%
;         ; ~Esc::
;             ; KeyWait, Esc, D
;             ; if (WinActive("ahk_id " GUI_ID)) {
;                 ; Gui, Destroy
;                 ;; Process, Exist, %GUI_ID%
;                 ;; If (ErrorLevel = 0)
;                     ;; Process, Close, %GUI_ID%
;             ; }
;         Return
;     Return
; ; }

;
; #Include TT.ahk
; #Include AltWindowSpy.ahk
;

;; Get extended attributes of window under mouse cursor
;; https://autohotkey.com/boards/viewtopic.php?f=6&t=43544
;;
;; https://autohotkey.com/board/topic/80855-get-info-from-window-under-mouse-without-clicking-on-it/
;; https://autohotkey.com/board/topic/9380-how-to-find-the-window-title-of-the-window-under-mouse/
;; https://autohotkey.com/board/topic/44150-how-to-properly-getset-gui-size/?p=274594
; #w::
; MouseGetPos, CursorX, CursorY, Window, Control
; WinGetTitle, Title, ahk_id %Window%
; WinGetClass, ahk_class, ahk_id %Window%
; DetectHiddenText, On
; WinGetText, VisibleText, ahk_id %Window%
;; TODO: Check if Visible Text over X characters and replace `n with spaces
; If (VisibleText = "")
;    VisibleText = (No visible text)
; WinGet, ahk_exe, ProcessName, ahk_id %Window%
; WinGet, Path, ProcessPath, ahk_id %Window%
; WinGet, PID, PID, ahk_id %Window%
; WinGet, active_hwnd, ID, A
; dec_hwnd := HexToDec(active_hwnd)
; ToolTip, %dec_hwnd%
;; WinGet, IsOldOpenSaveDialog, ID, %Window%
; IsDialog(active_hwnd) {
;    local toolbar, edit, combo, button
;    toolbar := FindWindowExID(Window, "ToolbarWindow32", "0x440")
;    if (toolbar = "0")
;        toolbar := FindWindowExID(Window, "ToolbarWindow32", "0x001") 
;    edit := FindWindowExID(Window, "Edit", "0x480")
;    combo := FindWindowExID(Window, "ComboBoxEx32", "0x47C")
;    button := FindWindowExID(Window, "Button", "0x001")
;    if (toolbar && (combo || edit) && button) 
;        return Yes
;    else
;        return No
; }
; FindWindowExID(dlg, className, ctrlId) {
;    local ctrl, id
;    ctrl = 0
;    Loop {
;        ctrl := DllCall("FindWindowEx", "uint", dlg, "uint", ctrl, "str", className, "uint", 0 )
;        if (ctrlId = "0")
;            return ctrl
;        if (ctrl != "0")
;        {
;            id := DllCall( "GetDlgCtrlID", "uint", ctrl )
;            if (id = ctrlId) 
;                return ctrl
;        }
;        else 
;            return 0
;    }
; }
; IsOldOpenSaveDialog := active_hwnd
; If (IsDialog(PID))
;    IsOldOpenSaveDialog = Yes
; Info = WinGetTitle %Title%`nahk_class %ahk_class%`nahk_exe %ahk_exe%`n`nProcess Path: %Path%`nProcess ID: %PID%`nOld open/save dialog active? %IsOldOpenSaveDialog%`n`nVisible text:`n%VisibleText%
;; Info := "Window title " Title "`nWindow ahk_class " ahk_class "`nWindow ahk_exe %ahk_exe%" "`nFull path: %Path% `nVisible Text:`n"VisibleText
;; MsgBox, , Press Ctrl+C to copy to clipboard, %Info%
; Gui, Destroy
; Gui, Add, Edit, ReadOnly, %Info%
; Gui, Add, Text, , Ctrl+C to copy selected text to clipboard.`nRepeat hotkey over another window to update.
; Gui, +AlwaysOnTop
; Gui, Show
;; Gui, Add, Button, CopyInfo, Copy to clipboard
;; CopyInfo:
;;        Clipboard := Info
;; Return
;;
;; Gui, Destroy
;; Gui, +Resize
;; Gui, Add, Text, w2000 h500 center, Text
;; Gui, Add, Edit, vVar, Info
;; Gui, Show
;; Loop {
;;    GuiControl, Move, Var, w2000 h1000
;;    GuiControl,,Var, %Info%
;;    Sleep 500
;; }
;;
;; Gui, Add, Tab2,, Window under cursor info
;; Gui, Add, Edit, ReadOnly,%Info%
;; GuiControl,,%Info%,abc
;; Gui, Add, Button, default xm, Copy Tab1
; return

;
; https://autohotkey.com/board/topic/60697-copying-all-entered-text-to-clipboard-resolved/
;
; #e::
; MouseGetPos, CursorX, CursorY, Window, Control
; WinGetTitle, Title, ahk_id %Window%
; WinGetClass, ahk_class, ahk_id %Window%
; WinGetText, VisibleText, ahk_id %Window%
; WinGet ahk_exe, ProcessName, ahk_id %Window%
; WinGet, Path, ProcessPath, ahk_id %Window%
; Info = Title %Title% `nahk_class %ahk_class% `nahk_exe %ahk_exe% `nPath: %Path% `nVisible Text:`n%VisibleText%
; Gui, Add, Tab2,, Window under cursor info
; Gui, Add, Edit, ReadOnly,%Info%
; Gui, Add, Button, default xm, Copy Tab1
; Gui, Show
; return
; ButtonCopyTab1:
; gui,submit,nohide
; clipboard = Name:%Info%
; return
;
; #w::
; MouseGetPos, CursorX, CursorY, Window, Control
; WinGetTitle, Title, ahk_id %Window%
; WinGetClass, ahk_class, ahk_id %Window%
; WinGetText, VisibleText, ahk_id %Window%
; WinGet ahk_exe, ProcessName, ahk_id %Window%
; WinGet, Path, ProcessPath, ahk_id %Window%
; Info = Title %Title% `nahk_class %ahk_class% `nahk_exe %ahk_exe% `nPath: %Path% `nVisible Text:`n%VisibleText%
;; Info := "Window title " Title "`nWindow ahk_class " ahk_class "`nWindow ahk_exe %ahk_exe%" "`nFull path: %Path% `nVisible Text:`n"VisibleText
; MsgBox, , Press Ctrl+C to copy to clipboard, %Info%
;; Gui, Add, Edit, ReadOnly,%Info%
;; Gui, Show
;; Gui, Add, Tab2,, Window under cursor info
;; Gui, Add, Edit, ReadOnly,%Info%
;; Gui, Add, Button, default xm, Copy Tab1
; return


; Description: Scroll Explorer on middle mouse button drag
; Permalink: https://autohotkey.com/boards/viewtopic.php?t=43715
; Tags: Drag Explorer
; Author: aph
; Version: 0.2
; Hotkey: Middle mouse button down
$*MButton::
    MouseGetPos, CursorX, CursorY, Window, ClassNN
    WinGetTitle, Title, ahk_id %Window%
    WinGetClass, ahk_class, ahk_id %Window%
    WinGet ahk_exe, ProcessName, ahk_id %Window%
    WinGet ahk_PID, PID, ahk_id %Window%
    WinGetText, VisibleText, ahk_id %Window%
    MouseGetPos, CursorX_ended, CursorY_ended, Window_ended, ClassNN_ended
    WinGetClass, ahk_class_ended, ahk_id %Window_ended%
    WinGet ahk_exe_ended, ProcessName, ahk_id %Window_ended%
    AllowedApp := ahk_exe = "explorer.exe" or ahk_exe = "mmc.exe" or ahk_exe = "systempropertiesadvanced.exe" or ahk_exe = "filezilla.exe" or ahk_exe = "7zFM.exe" ; or ahk_exe = ; "RegWorkshopX64.exe"
    AllowedText := InStr(VisibleText, "Tree View") or InStr(VisibleText, "FolderView")
    LimitedApp := ahk_exe = "cmd.exe"
    DisabledApp := ahk_class_ended = "Shell_TrayWnd" or ahk_class_ended = "WorkerW"
    ; Toolbars := ClassNN = "ToolbarWindow32" or ClassNN = "ReBarWindow32" or ClassNN = "Edit" ; or ClassNN="SysListView32"
    ; IsToolbar := InStr(Toolars, "Tree View") or InStr(Toolbars, "FolderView")
    ;ToolTip, ClassNN %ClassNN% | isToolbar %IsToolbar%
    ; AllowedKeys := GetKeyState("LWin", "D")
    ; AllowedKeys ? "MButton Up" : "MButton Down"
    ; Sublime := ahk_exe = "sublime_text.exe"
    ; SublimeModifiers := GetKeyState("Alt", "D") or (GetKeyState("LWin", "D")) or (GetKeyState("Ctrl", "D")) or (GetKeyState("Shift", "D"))
    ; TrayTipText = % "AllowedApp: " AllowedApp
    ;     . "`nAllowedKeys: " AllowedKeys
    ;     . "`nSublime: " Sublime
    ;     . "`nModifiers: " SublimeModifiers
    ;     . "`n"
    ;     . "`n" Title
    ;     . "`nahk_exe: " ahk_exe
    ;     . "`nahk_class: " ahk_class
    ;     . "`nClassNN:" ClassNN
    ;     ; . "`nCursorHwnd: " CursorHwnd
    if (AllowedText >= 1)
        AllowedText = 1
    If (DisabledApp) {
        SendInput, {MButton Down}
        Return
    }
    Else If (!AllowedApp and !LimitedApp and !AllowedText) { ; !AllowedKeys
        ; TrayTip, % "Not scrolling with middle button", %TrayTipText%
        SendInput, {MButton Down}
        Return
    }
    ; Else {
    ;     ; #IfWinActive, ahk_exe explorer.exe
    ;     ;      ControlGet renamestatus,Visible,,Edit1,A
    ;     ;      ControlGetFocus focussed, A
    ;     ;      if(renamestatus!=1&&(focussed=”DirectUIHWND3″||focussed=SysTreeView321))
    ;     ;      {
    ;     ;      ToolTip, %focussed%
    ;     ;     }
    ;     ; #IfWinActive
    ;     }
    Else {
        If (AllowedApp) {
            SendInput, {MButton}
            ; ToolTip, %ClassNN% ToolbarFound %Toolbars%
        }
        ; Process, Exist, %Window%
        ; ToolTip, % DllCall("WindowFromPoint", "int64", CursorX | (CursorY << 32), "Ptr")
        ; ControlFocus, CursorHw, WinTitle, WinText, ExcludeTitle, ExcludeText]
        ; TrayTip, % "Scrolling with middle button", %TrayTipText%
        MiddleScroll := 1
        ; SetSystemCursor("SIZEALL")
        Sensitivity = 10 ; How far the middle mouse wheel has to be dragged before scrolling is triggered
        MouseGetPos, X1, Y1, , c, 2
        OrigTimer := 50 ; How quickly the file list scrolls
        SetTimer, MBScroll, %OrigTimer%
        MBScroll:
            MouseGetPos, X2, Y2
            Distance := Abs(Y2-Y1)
            If (Distance >= Sensitivity) {
                Rounded := % Round((Distance / 200)**1.25+1)
                DllCall("SystemParametersInfo", UInt, 0x69, UInt, Round(Ln(Rounded)+1), UInt, 0, UInt, 0) ; Vary lines scrolled by distance of drag 
                Timer := Round(OrigTimer - (OrigTimer/2*Percent/100))
                SetTimer, MBScroll, %Timer%
                Percent := (A_ScreenHeight - (Max(Y1, Abs(Y1-A_ScreenHeight)) - Distance)) / A_ScreenHeight * 100
                SendInput, % "{Blind}{Wheel" (Y2 > Y1 ? "Down" : "Up") " " Rounded "}"
            }
        Return
        $*MButton Up::
            DllCall("SystemParametersInfo", UInt, 0x69, UInt, 3, UInt, 0, UInt, 0) ; Set back to 3 lines scrolled
            SetTimer, MBScroll, off
            ; SetSystemCursor()
            MiddleScroll := 0
            SendInput {MButton Up}
            ; SetSystemCursor(Cursor="") {
            ;     SystemCursors := "32512IDC_ARROW|32513IDC_IBEAM|32514IDC_WAIT|32515IDC_CROSS|32516IDC_UPARROW|32642IDC_SIZENWSE|32643IDC_SIZENESW|32644IDC_SIZEWE|32645IDC_SIZENS|32 646IDC_SIZEALL|32648IDC_NO|32649IDC_HAND|32650IDC_APPSTARTING|32651IDC_HELP"
            ;     If (Cursor = "")
            ;         Return DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "UInt", 0, "UInt", 0) 
            ;     If (StrLen(SystemCursors) = 221)
            ;         Loop, Parse, SystemCursors, |
            ;             StringReplace, SystemCursors, SystemCursors, %A_LoopField%, % DllCall("LoadCursor", "UInt", 0, "Int", SubStr(A_LoopField, 1, 5)) A_LoopField
            ;     If !(Cursor := SubStr(SystemCursors, InStr(SystemCursors "|", "IDC_" Cursor "|") - 5 - p := (StrLen(SystemCursors) - 221) / 14, 5))
            ;         MsgBox, 262160, %A_ScriptName% - %A_ThisFunc%(): Error, Invalid cursor name!
            ;     Else
            ;         Loop, Parse, SystemCursors, |
            ;         {
            ;             ; 
            ;             ; IDC_ARROW := 32512
            ;             ; IDC_IBEAM := 32513
            ;             ; IDC_WAIT := 32514
            ;             ; IDC_CROSS := 32515
            ;             ; IDC_UPARROW := 32516
            ;             ; IDC_SIZE := 32640
            ;             ; IDC_ICON := 32641
            ;             ; IDC_SIZENWSE := 32642
            ;             ; IDC_SIZENESW := 32643
            ;             ; IDC_SIZEWE := 32644
            ;             ; IDC_SIZENS := 32645
            ;             ; IDC_SIZEALL := 32646
            ;             ; IDC_NO := 32648
            ;             ; IDC_HAND := 32649
            ;             ; IDC_APPSTARTING := 32650
            ;             ; IDC_HELP := 32651
            ;             ;
            ;             ; DllCall("SetSystemCursor", "UInt", DllCall("CopyIcon", "UInt", Cursor), "Int", SubStr(A_LoopField, 6, p))
            ;             ToolTip, Original cursor: %Cursor% " Replacement: " SubStr(A_LoopField, 6, p))
            ;         }
                    
            ;     }
        Return
    }
Return

; $*MButton::
;     MouseGetPos, CursorX, CursorY, Window, ClassNN
;     WinGetTitle, Title, ahk_id %Window%
;     WinGetClass, ahk_class, ahk_id %Window%
;     WinGet ahk_exe, ProcessName, ahk_id %Window%
;     WinGet ahk_PID, PID, ahk_id %Window%
;     WinGetText, VisibleText, ahk_id %Window%
;     MouseGetPos, CursorX_ended, CursorY_ended, Window_ended, ClassNN_ended
;     WinGetClass, ahk_class_ended, ahk_id %Window_ended%
;     WinGet ahk_exe_ended, ProcessName, ahk_id %Window_ended%
;     ; MouseGetPos, vMouseX, vMouseY,, hCtl, 3
;     ;; OR:
;     ; WinGet ahk_class, ProcessName, ahk_class %Window%
;     ; WinGetClass, vCtlClass, % "ahk_id " hCtl
;     ; WinGetClass, CursorHwnd, ahk_pid %ahk_PID% 
;     ; WinGet, CursorHwnd, IDLast, ahk_id %Window%
;     ; CursorHwnd += CursorHwnd
;     ; CursorHwnd := DllCall("WindowFromPoint", "int64", CursorX | (CursorY << 32), "Ptr")
;     ; ControlFocus, , ahk_title, WinText, ExcludeTitle, ExcludeText]
;     ; ControlFocus, %ClassNN%
;     ; ControlClick, %ClassNN%
;     ; ControlGetFocus, %ClassNN%
;     ; ControlGetFocus, ControlWithFocus, %ClassNN%
;     ; ToolTip, %ControlWithFocus%
;     ;IfWinExist, [ WinTitle, WinText, ExcludeTitle, ExcludeText]
;     ; WinActivate, %Window%
;     WinActivate, %Title%
;     ; CursorHwnd := DllCall("WindowFromPoint", "int64", CursorX | (CursorY << 32), "Ptr")
;     ; ControlClick, %ClassNN%, %Title% ; , WinText, WhichButton, ClickCount, Options, ExcludeTitle, ExcludeText]
;     ;; TODO:
;     ; AllowedApp := InStr(ahk_exe, "explorer.exe", "explorer.exe" . "sublime_text.exe" . "mmc.exe" . "RegWorkshopX64.exe")
;     ; AllowedApp := ahk_exe.HasKey(AllowedApps)
;     ; AllowedApp := "explorer.exe" . "sublime_text.exe" . "mmc.exe" . "RegWorkshopX64.exe" . "systempropertiesadvanced.exe" . "7zFM.exe"
;     ; AllowedApp := InStr("explorer.exe", AllowedApp)
;     AllowedApp := ahk_exe = "explorer.exe" or ahk_exe = "mmc.exe" or ahk_exe = "systempropertiesadvanced.exe" ahk_exe = "RegWorkshopX64.exe" or ahk_exe = "7zFM.exe"
;     AllowedText := InStr(VisibleText, "Tree View") or InStr(VisibleText, "FolderView")
;     LimitedApp := ahk_exe = "cmd.exe"
;     DisabledApp := ahk_class_ended = "Shell_TrayWnd" or ahk_class_ended = "WorkerW"
;     AllowedKeys := GetKeyState("LWin", "D")
;     AllowedKeys ? "MButton Up" : "MButton Down"
;     Sublime := ahk_exe = "sublime_text.exe"
;     SublimeModifiers := GetKeyState("Alt", "D") or (GetKeyState("LWin", "D")) or (GetKeyState("Ctrl", "D")) or (GetKeyState("Shift", "D"))
;     ; TrayTipText = % "AllowedApp: " AllowedApp
;     ;     . "`nAllowedKeys: " AllowedKeys
;     ;     . "`nSublime: " Sublime
;     ;     . "`nModifiers: " SublimeModifiers
;     ;     . "`n"
;     ;     . "`n" Title
;     ;     . "`nahk_exe: " ahk_exe
;     ;     . "`nahk_class: " ahk_class
;     ;     . "`nClassNN:" ClassNN
;     ;     ; . "`nCursorHwnd: " CursorHwnd
;     if (AllowedText >= 1)
;         AllowedText = 1
;     If (DisabledApp) {
;         SendInput, {MButton Down}
;         Return
;     }
;     Else If (!AllowedKeys and !AllowedApp and !LimitedApp and !AllowedText) { ; and !(Sublime and SublimeModifiers)
;         ; TrayTip, % "Not scrolling with middle button", %TrayTipText%
;         SendInput, {MButton Down}
;         Return
;     }
;     Else {
;         If (AllowedApp) {
;             SendInput, {MButton}
;             ; ControlFocus, %ClassNN%
;             ; ControlClick, %ClassNN%
;             ; MouseGetPos, ClickX, ClickY, , ctrlUnderMouse
;             ; ;ToolTip, % ctrlUnderMouse
;             ; IfInString, ctrlUnderMouse, %ClassNN%
;             ;     ControlGetPos, ctrlUnderMouseX, ctrlUnderMouseY, , , %ctrlUnderMouse%, ahk_class CabinetWClass
;             ; ;Sleep, 250
;             ; ControlGetFocus, ClassNN
;             ;     ToolTip, % ClassNN
;         }
;         ; Process, Exist, %Window%
;         ; ToolTip, % DllCall("WindowFromPoint", "int64", CursorX | (CursorY << 32), "Ptr")
;         ; ControlFocus, CursorHw, WinTitle, WinText, ExcludeTitle, ExcludeText]
;         ; TrayTip, % "Scrolling with middle button", %TrayTipText%
;         MiddleScroll := 1
;         ; SetSystemCursor("SIZEALL")
;         Sensitivity = 10 ; How far the middle mouse wheel has to be dragged before scrolling is triggered
;         MouseGetPos, X1, Y1, , c, 2
;         OrigTimer := 40 ; How quickly the file list scrolls
;         SetTimer, MBScroll, %OrigTimer%
;         MBScroll:
;             MouseGetPos, X2, Y2
;             Distance := Abs(Y2-Y1)
;             If (Distance >= Sensitivity) {
;                 Rounded := % Round((Distance / 200)**1.25+1)
;                 ;; TODO: Try
;                 ; %OrigTimer%/40
;                 DllCall("SystemParametersInfo", UInt, 0x69, UInt, Round(Ln(Rounded)+1), UInt, 0, UInt, 0) ; Vary lines scrolled by distance of drag 
;                 Timer := Round(OrigTimer - (OrigTimer/2*Percent/100))
;                 SetTimer, MBScroll, %Timer%
;                 Percent := (A_ScreenHeight - (Max(Y1, Abs(Y1-A_ScreenHeight)) - Distance)) / A_ScreenHeight * 100
;                 SendInput, % "{Blind}{Wheel" (Y2 > Y1 ? "Down" : "Up") " " Rounded "}"
;             }
;         Return ; MBScroll
;         $*MButton Up::
;             ; Set back to original 3 lines per scroll event when dragging stops
;             DllCall("SystemParametersInfo", UInt, 0x69, UInt, 3, UInt, 0, UInt, 0)
;             SetTimer, MBScroll, off
;             ; SetSystemCursor()
;             MiddleScroll := 0
;             SendInput {MButton Up}
;             ; SetSystemCursor(Cursor="") {
;             ;     SystemCursors := "32512IDC_ARROW|32513IDC_IBEAM|32514IDC_WAIT|32515IDC_CROSS|32516IDC_UPARROW|32642IDC_SIZENWSE|32643IDC_SIZENESW|32644IDC_SIZEWE|32645IDC_SIZENS|32646IDC_SIZEALL|32648IDC_NO|32649IDC_HAND|32650IDC_APPSTARTING|32651IDC_HELP"
;             ;     If (Cursor = "")
;             ;         Return DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "UInt", 0, "UInt", 0) 
;             ;     If (StrLen(SystemCursors) = 221)
;             ;         Loop, Parse, SystemCursors, |
;             ;             StringReplace, SystemCursors, SystemCursors, %A_LoopField%, % DllCall("LoadCursor", "UInt", 0, "Int", SubStr(A_LoopField, 1, 5)) A_LoopField
;             ;     If !(Cursor := SubStr(SystemCursors, InStr(SystemCursors "|", "IDC_" Cursor "|") - 5 - p := (StrLen(SystemCursors) - 221) / 14, 5))
;             ;         MsgBox, 262160, %A_ScriptName% - %A_ThisFunc%(): Error, Invalid cursor name!
;             ;     Else
;             ;         Loop, Parse, SystemCursors, |
;             ;             DllCall("SetSystemCursor", "UInt", DllCall("CopyIcon", "UInt", Cursor), "Int", SubStr(A_LoopField, 6, p))
;             ;     }
;         Return
;     }
; Return

; ;
; ; Drag mouse middle button to scroll 
; ; Tags, drag explorer, scroll right, scroll down,
; ; https://autohotkey.com/board/topic/42020-using-right-click-and-mouse-movement-as-a-scroll-wheel/?p=270247
; ;
; wheelingSensitivity := 10 ; sensitivity to mouse movement (higher is more sensitive)
; wheelingPeriod := 100 ; timer period


; ; https://autohotkey.com/board/topic/42020-using-right-click-and-mouse-movement-as-a-scroll-wheel/?p=269308
; ; $*MButton::
; RButton & LButton:: GoSub StartWheeling
; ~*LButton Up::      GoSub StopWheeling
; ~*RButton Up::      GoSub StopWheeling
; WatchCursor:
;     MouseGetPos, wheelingNewMouseX, wheelingNewMouseY
;     taps := Round((wheelingNewMouseX - wheelingMouseX)/wheelingSensitivity)
;     clicks := Round((wheelingNewMouseY - wheelingMouseY)/wheelingSensitivity)
;     MouseMove wheelingMouseX, wheelingMouseY
;     if clicks > 0
;         MouseClick WheelDown,,,abs(clicks)
;     else if clicks < 0
;         MouseClick WheelUp,,,abs(clicks)
;     if taps > 0
;         SendInput % "{Right "abs(taps)"}"
;     else if taps < 0
;         SendInput % "{Left "abs(taps)"}"
; return
; StartWheeling:
;     SystemCursor("OFF")
;     MouseGetPos, wheelingMouseX, wheelingMouseY
;     SetTimer WatchCursor, %wheelingPeriod%
; return
; StopWheeling:
;     SetTimer WatchCursor, Off
;     SystemCursor("ON")
; return
; ;===============================================================================================================================================================
; ; from the AHK documentation...
; SystemCursor(OnOff=1)   ; INIT = "I","Init"; OFF = 0,"Off"; TOGGLE = -1,"T","Toggle"; ON = others
; {
;     static AndMask, XorMask, $, h_cursor
;         ,c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13 ; system cursors
;         , b1,b2,b3,b4,b5,b6,b7,b8,b9,b10,b11,b12,b13   ; blank cursors
;         , h1,h2,h3,h4,h5,h6,h7,h8,h9,h10,h11,h12,h13   ; handles of default cursors
;     if (OnOff = "Init" or OnOff = "I" or $ = "")       ; init when requested or at first call
;     {
;         $ = h                                          ; active default cursors
;         VarSetCapacity( h_cursor,4444, 1 )
;         VarSetCapacity( AndMask, 32*4, 0xFF )
;         VarSetCapacity( XorMask, 32*4, 0 )
;         system_cursors = 32512,32513,32514,32515,32516,32642,32643,32644,32645,32646,32648,32649,32650
;         StringSplit c, system_cursors, `,
;         Loop %c0%
;         {
;             h_cursor   := DllCall( "LoadCursor", "uint",0, "uint",c%A_Index% )
;             h%A_Index% := DllCall( "CopyImage",  "uint",h_cursor, "uint",2, "int",0, "int",0, "uint",0 )
;             b%A_Index% := DllCall("CreateCursor","uint",0, "int",0, "int",0
;                 , "int",32, "int",32, "uint",&AndMask, "uint",&XorMask )
;         }
;     }
;     if (OnOff = 0 or OnOff = "Off" or $ = "h" and (OnOff < 0 or OnOff = "Toggle" or OnOff = "T"))
;         $ = b  ; use blank cursors
;     else
;         $ = h  ; use the saved cursors

;     Loop %c0%
;     {
;         h_cursor := DllCall( "CopyImage", "uint",%$%%A_Index%, "uint",2, "int",0, "int",0, "uint",0 )
;         DllCall( "SetSystemCursor", "uint",h_cursor, "uint",c%A_Index% )
;     }
; }
; ;===============================================================================================================================================================


; Find word in string
; https://stackoverflow.com/questions/9348326/regex-find-word-in-the-string
; ^(.*?(\bGoogle Chrome\b)[^$]*)$
; RegEx line break
; https://stackoverflow.com/questions/15161892/regular-expression-select-up-to-line-break
; /.*\s*:\s*.*/g