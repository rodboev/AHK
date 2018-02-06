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

; #Include FindText.ahk

; DllCall("SystemParametersInfo", UInt, 0x69, UInt, 3, UInt, 0, UInt, 0) ; Restore original value

; FileGetAttrib, attribs, %A_ScriptFullPath%
; if (attribs="A") {
;        FileSetAttrib, -A, %A_ScriptFullPath%
;        TrayTip, AutoHotKey, Reloaded script from:`n%A_ScriptFullPath%,, 1
; }
; OnExit, ExitSub
; Return
; ExitSub:
;        if (A_ExitReason="Reload") {
;                FileSetAttrib, +A, %A_ScriptFullPath%
;        }
; ExitApp


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
; MsgBox, %attribs%
+!r::Reload
+!x::Suspend
+!p::
#p::
    Pause
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
        #IfWinActive "^AutoHotKey(.*)? - Sublime Text"
            Reload
        #IfWinActive
    Return
    Return
#IfWinActive


;
; Google Chrome
;
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


; TODO check for title starting with "AutoHotkey.ahk" and ending with " - Sublime Text*"
;    *^s::
        
;        Reload
;        ; Send {CtrlDown}{Alt Down}r{Ctrl Up}{Alt Up}
;    Return

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


;;
;; http://www.autohotkey.com/board/topic/95834-using-winwait-effectively-or-how-else-should-i-execute-an-action-when-a-pop-up-window-appears/#entry603588
;;
;;
; TODO group
;
; μTorrent
; ahk_class #32770
; ahk_exe uTorrent.exe
; Focused control:
; ClassNN: Button1
; Text: &Yes
;
; Dropbox Notification
; ahk_class Qt5QWindowToolSaveBits
; ahk_exe Dropbox.exe
; 
; IfWinExist ahk_exe VirusTotalUploader2.2.exe {
;    winactivate ahk_class Chrome_WidgetWin_1
; else
;    run, "C:\Users\xxx\AppData\Local\Google\Chrome\Application\chrome.exe"
; WinWaitActive ahk_class Chrome_WidgetWin_1
;
;; uTorrent
;; https://autohotkey.com/docs/commands/WinWaitActive.htm
;; https://autohotkey.com/docs/misc/WinTitle.htm#LastFoundWindow
;; https://autohotkey.com/docs/commands/WinActive.htm
; #IfWinActive chrome
; if WinActive("ahk_class Chrome_WidgetWin_1")
; WinWaitActive, ahk_exe uTorrent.exe
; WinClose
; #IfWinActive
;
;; https://autohotkey.com/board/topic/99219-can-i-do-this-close-specific-windows-when-they-open/#entry642311
;
;; Shift+WheelUp/Down = Scroll by 3 lines
;; {Click WheelDown 3}
;; {Click WheelUp 3}
;; #IfWinActive ahk_class MPC-BE
; #IfWinActive ahk_class MediaPlayerClassicW
;; +WheelDown::SendMessage,0x0111,904,,,ahk_class MPC-BE
;; +WheelUp::SendMessage,0x0111,903,,,ahk_class MPC-BE 
;; +WheelDown::SendMessage,0x0111,904,,,ahk_class MediaPlayerClassicW
;; +WheelUp::SendMessage,0x0111,903,,,ahk_class MediaPlayerClassicW 
; $+WheelDown::
;    SendInput, {Shift Down}{Right}{Shift Up}
; Return
; $+WheelUp::
;    SendInput, {Shift Down}{Left}{Shift Up}
; Return
; ToolTip, WheelDown MPC
;; $+WheelDown::SendInput, {Shift Down}{Right}{Shift Up}
;; $+WheelUp::SendInput, {Shift Down}{Left}{Shift Up}
;; $+WheelDown::SendInput, {Click WheelDown 3}
;; $+WheelUp::SendInput, {Click WheelUp 3}
; #IfWinActive


;
; VLC
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
; Restore Win+X key functionality disabled via Group Policy
;
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

;; Win+L: Turn off monitor
#l::
;    if (A_ComputerName = "CORE") {
;        Run RunFromProcess-x64 explorer.exe nircmd cmdwait 200 monitor off
        SendMessage, 0x112, 0xF140, 0,, Program Manager
        Sleep 3000
        VarSetCapacity(screen_saver_active,4,0)
        SPI_GETSCREENSAVERRUNNING = 0x0072
        result := DllCall( "user32.dll\SystemParametersInfo", "uint", SPI_GETSCREENSAVERRUNNING, "uint", 0, "uint*", screen_saver_active, "uint", 0 )
        WinGetActiveTitle, Title
        ; MsgBox, The active window is "%Title%"
        if (Title = "")
            SendMessage, 0x112, 0xF170, 2,, Program Manager ; Shut off monitor
        ; if (ScreenSaverRunning)
            ; {
            ; MsgBox,
;    }
Return

; Win+D = Show desktop
toggle = 0
#d::
    if toggle := !toggle
            WinMinimizeAll
    else
            WinMinimizeAllUndo
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


;
; Win+S = Run or activate Everything
;
; #s::
;;
;; to send original key:
;;
;; SendInput {RWin Down}
;; Send s
;; SendInput {RWin Up}
;; Return
;;
; If (WinActive("ahk_class EVERYTHING")) {
;    Send !d
; }
; Else If (WinExist("ahk_class EVERYTHING")) {
;    WinActivate
; }
; Else {
;        Run RunFromProcess-x64 explorer.exe C:\Program Files\Everything\Everything.exe
; }
; Return

#s::
SetTitleMatchMode, RegEx
IfWinActive ^(.* - )?Everything$
        Return 
IfWinExist ^(.* - )?Everything$
        WinActivate
else
        Run RunFromProcess-x64 explorer.exe C:\Program Files\Everything\Everything.exe
        IfWinNotActive
                WinWait, ^(.* - )?Everything
                WinActivate
Return


;;
;; Shift+WheelUp/Down = Scroll by 30 lines
;; Alt+WheelUp/Down = Scroll horizontally
;;
; +WheelUp::Send {Click WheelUp 30}
; +WheelDown::Send {Click WheelDown 30}
;; #IfWinActive ahk_class PX_WINDOW_CLASS
;; {
;        ; WheelUp::Click WheelUp 3
;        ; WheelDown::Click WheelDown 3
;        ; Return
;; }
;; !WheelUp::Send {Click WheelLeft 2}
;; !WheelDown::Send {Click WheelRight 2}


;
; Run Process Hacker
;
^+`::Run nircmd runassystem "C:\Program Files\Process Hacker 2\ProcessHacker.exe"

;
; Alt+Shift+E = Edit current script (as normal user)
;
+!e::Run RunFromProcess-x64 explorer.exe notepad %A_ScriptFullPath%

;
; http://www.howtogeek.com/howto/8955/make-backspace-in-windows-7-or-vista-explorer-go-up-like-xp-did/
;
#IfWinActive, ahk_exe explorer.exe
Backspace::
     ControlGet renamestatus,Visible,,Edit1,A
     ControlGetFocus focussed, A
     if(renamestatus!=1&&(focussed=”DirectUIHWND3″||focussed=SysTreeView321))
     {
        SendInput {Alt Down}{Up}{Alt Up}
    }else{
            Send {Backspace}
    }
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

; #IfWinExist ahk_class SpotifyMainWindow
~XButton1 & XButton2::
~XButton2 & XButton1::
+!Left:: 
    ; SetTitleMatchMode, 2
    DetectHiddenWindows, On 
    ; Send {Media_Prev}
    ControlSend, ahk_parent, ^{Left}, ahk_class SpotifyMainWindow 
    DetectHiddenWindows, Off 
return 

+!Right::
    ; SetTitleMatchMode, 2
    DetectHiddenWindows, On 
    ; Send {Media_Next}
    ControlSend, ahk_parent, ^{Right}, ahk_class SpotifyMainWindow 
    DetectHiddenWindows, Off 
Return
; #IfWinExist


;;
;; Accelerated Scrolling v2
;; https://autohotkey.com/board/topic/48426-accelerated-scrolling-script/?p=333222
;;
;; ==== Script Initialize ========================================================
;
; If Not A_IsAdmin                                                                    ; need Admin privilege to scroll programs run as Admin
; {
;    DllCall("shell32\ShellExecuteA", uint, 0, str, "RunAs", str, A_AhkPath, str, """" . A_ScriptFullPath . """", str, A_WorkingDir, int, 0)
;    ExitApp
; }
;
; #MaxThreads 2                                                                       ; need two "threads", one to accumulate buffered events and one to send scroll messages
; #MaxThreadsPerHotkey 2
; #MaxHotkeysPerInterval 2000                                                         ; the hyper wheel on a Logitech mouse generates events very quickly when in free spinning mode
;
; Process Priority, , H                                                               ; run in high speed
; SetBatchLines -1                                                                    ; do not interrupt a "thread" after processing a number of script lines
; CoordMode Mouse, Screen                                                             ; use screen coordinates
;
;; ==== WheelUp/Down Initialize ==================================================
;
; ScrollLines := 1                                                                    ; scroll 1 line at once, though 3 is system default
; DllCall("SystemParametersInfo", UInt, 0x69, UInt, ScrollLines, UInt, 0, UInt, 0)    ; 0x69 is SPI_SETWHEELSCROLLLINES
; WheelUnits := 120                                                                   ; most mice report 120 units per detent (WheelUp/Down "click")
; WheelDelta := WheelUnits << 16                                                      ; shift value 2 bytes to the left, as the scroll message expects step size in the most significant 2 bytes
;
; DllCall("QueryPerformanceFrequency",  "Int64 *", Freq)                              ; retrieve the frequency of the high-resolution performance counter
; TickPerMs := Freq / 1000                                                            ; ticks per millisecond
;
; ThresholdCtrl := 200 * TickPerMs                                                    ; threshold to block Ctrl + WheelUp/Down until wheel stops scrolling
; ThresholdSingle := 400 * TickPerMs                                                  ; threshold to determine whether it is an intended continuous scrolling
; ThresholdAccelMin := 140 * TickPerMs                                                ; threshold to begin accelerating the wheel scrolling speed
; ThresholdAccelMax := 20 * TickPerMs                                                 ; threshold of maximum acceleration of the wheel scrolling speed
; BoostPeak := 6                                                                      ; limit on peak boost
; BoostMult := BoostPeak / (ThresholdAccelMin - ThresholdAccelMax)                    ; multiplier for linear acceleration profile, in x / tick (1 / 10 is 1x boost per 10 tick below ThresholdAccelMin)
;
; WheelSteps := 0                                                                     ; wheel steps, used when wheel steps have been buffered or accelerated
; Available := true                                                                   ; lock to allow buffering while only one "thread" sends scroll messages
; PriorTick := 0                                                                      ; previous value of the high-resolution performance counter (tick since boot)
; PriorWin := 0                                                                       ; previously hovered window
; PriorCtl := ""                                                                      ; previously hovered control
; MsgType := 0                                                                        ; type of scroll message to send
;
;; ==== WheelUp/Down Routine =====================================================
;
; WheelUp::
; WheelDown::
;    Critical
;
;    DllCall("QueryPerformanceCounter", "Int64 *", Tick)                             ; retrieves the current value of the high-resolution performance counter (tick since boot)
;    Dur := (Tick - PriorTick) / A_EventInfo                                         ; time since last WheelUp/Down (most mice combine multiple WheelUp/Down within 8ms into one event)
;    If (Dur > ThresholdSingle || A_ThisHotkey != A_PriorHotkey)                     ; this is a single step, as opposed to continuous scrolling
;        WheelSteps := A_EventInfo                                                   ; clear leftover buffered message
;    Else If (Dur <= ThresholdAccelMax)                                              ; fastest continuous wheel scrolling
;        WheelSteps += (BoostPeak + 1) * A_EventInfo                                 ; add peak acceleration boost to wheel steps
;    Else If (Dur < ThresholdAccelMin)                                               ; fast continuous wheel scrolling
;        WheelSteps += ((ThresholdAccelMin - Dur) * BoostMult + 1) * A_EventInfo     ; add linear acceleration boost to wheel steps
;    Else
;        WheelSteps += A_EventInfo                                                   ; add wheel steps
;    PriorTick := Tick
;
;    If (Available)                                                                  ; only enter the send message section if it's not already running in the other "thread"
;    {
;        Available := false                                                          ; lock this send message section to run one single instance
;
;        Loop                                                                        ; loop to continue sending messages as they are accumulated in the other "thread", and also to handle the program that does not handle larger scrolls
;        {
;            Critical Off
;            Sleep -1                                                                ; interrupt this "thread" here to accumulate wheel steps for any buffered WheelUp/Down events
;            Critical
;
;            Step := Round(WheelSteps)                                               ; round to nearest whole wheel step
;            If (Step < 1)                                                           ; wheel steps have reached zero or close to zero
;                Break                                                               ; exit the loop
;
;            MouseGetPos X, Y, Win, Ctl                                              ; get the coordinates, window, and control under the mouse cursor
;            If (PriorWin != Win || PriorCtl != Ctl)                                 ; mouse was moved over a different window or control
;            {
;                If (Dur <= ThresholdCtrl && A_ThisHotkey == A_PriorHotkey)          ; the wheel is still doing a scroll from before mouse was moved over a different window or control
;                {
;                    WheelSteps := 0                                                 ; clear buffered message
;                    Break                                                           ; exit the loop
;                }
;                Else
;                {
;                    PriorWin := Win
;                    PriorCtl := Ctl
;                    If Ctl in TSideBySideFolders1,TXListBox1,TXListBox2             ; program does not handle larger scrolls (Beyond Compare 2.5.3)
;                        MsgType := 1                                                ; type 1 means repeat message for each wheel step instead of sending a single message with size of step
;                    Else If (Ctl == "OPWindowClass2" && Win == WinExist("A"))       ; program does not receive posted scroll messages correctly (Remote Desktop 6.1.7600)
;                        MsgType := 2                                                ; type 2 means use standard way of sending scroll message
;                    Else If (Ctl == "")                                             ; program doesn't expose a control name for the editor panel (Visual Studio 2010 10.0.30319.1)
;                    {
;                        WinGetTitle Title, ahk_id %Win%
;                        If Title contains Microsoft Visual Studio
;                            MouseClick Middle                                       ; activate the hovered control
;                        MsgType := 0                                                ; type 0 means use send message to post scroll message
;                    }
;                    Else                                                            ; assume that other programs correctly receive posted scroll messages
;                        MsgType := 0                                                ; type 0 means use send message to post scroll message
;                }
;            }
;
;            If (MsgType == 1)                                                       ; type 1 means repeat message for each wheel step instead of sending a single message with size of step
;                Step := 1                                                           ; setting step to 1 means it will loop again for each wheel step
;            If (MsgType == 2)                                                       ; type 2 means use standard way of sending scroll message
;                MouseClick %A_ThisHotkey%, , , %Step%                               ; send scroll message in standard way
;            Else                                                                    ; type 0 means use send message to post scroll message
;                SendMessage 0x20A, (A_ThisHotkey == "WheelUp" ? 1 : -1) * Step * WheelDelta, Y << 16 | (X & 0xFFFF), %Ctl%, ahk_id %Win% ; post scroll message to window under cursor, and wait for response
;
;            WheelSteps -= Step                                                      ; subtract whole wheel steps, leaving the remainder buffered for the next post
;            ; Tooltip % Step . SubStr("  ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||", 1 + (Step >= 10) + (Step >= 100), Step + (Step < 10) + (Step < 100)) ; %; display bar graph of wheel acceleration (the commented second '%' is only there to fix syntax highlighting in Notepad++)
;        }
;
;        Available := true                                                           ; unlock this send message section
;    }
;
;    Critical Off
;    Return
;
;; ==== Ctrl + WheelUp/Down Routine ==============================================
;
; *WheelUp::
; *WheelDown::
;    Critical
;    DllCall("QueryPerformanceCounter", "Int64 *", Tick)                             ; retrieves the current value of the high-resolution performance counter (tick since boot)
;    Dur := (Tick - PriorTick) / A_EventInfo                                         ; time since last WheelUp/Down (most mice combine multiple WheelUp/Down within 8ms into one event)
;    If (Dur <= ThresholdCtrl)                                                       ; the wheel is still doing a scroll from before Ctrl was pressed
;    {
;        WheelSteps := 0                                                             ; clear leftover buffered message, so acceleration is not boosted by this
;        PriorTick := Tick                                                           ; continue to block Ctrl + WheelUp/Down until wheel stops scrolling
;    }
;    Else If (A_ThisHotkey == "*WheelUp")
;        MouseClick WheelUp                                                          ; send only a single Ctrl + WheelUp, no acceleration
;    Else
;        MouseClick WheelDown                                                        ; send only a single Ctrl + WheelDown, no acceleration
;    Critical Off
; Return

;;
;; Accelerated scrolling
;;
;;; #If (WinActive("ahk_exe explorer.exe") or WinActive("ahk_class PROCMON_WINDOW_CLASS") or 
; #IfWinNotActive, abcd
;; #If (WinActive("ahk_exe explorer.exe") or WinActive("ahk_class MPC-BE") or WinActive("ahk_class MediaPlayerClassicW"))
;; The length of a scrolling session. Keep scrolling within this time to accumulate boost. ; Default: 500. Recommended between 400 and 1000.
; WheelUp::
; WheelDown::
; timeout := 500
;; If you scroll a long distance in one session, apply additional boost factor. The higher the ; value, the longer it takes to activate, and the slower it accumulates. ; Set to zero to disable ; completely. Default: 30.
; boost := 3
;; Spamming applications with hundreds of individual scroll events can slow them down. This sets ; the maximum number of scrolls sent per click, i.e. max velocity. ; Default: 60.
; limit := 30
; distance := 0
; vmax := 1
; t := A_TimeSincePriorHotkey
;; ToolTip, t %t% timeout 500
;; ToolTip, timeout: %timeout%
; if (A_PriorHotkey = A_ThisHotkey && t < timeout) {
;; if (A_PriorHotkey = A_ThisHotkey) {
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
;
;    QuickToolTip(text, delay)
;    {
;        ToolTip, ScrollAccel: %text%
;        SetTimer ToolTipOff, %delay%
;        Return
;
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
;
;; #If
; Return
;; #If
; #IfWinNotActive


; 
; Scroll window under mouse cursor
; Tags: combined, scroll under cursor, scroll window under cursor
; https://autohotkey.com/board/topic/78284-boldly-scroll-where-no-one-has-scrolled-before/page-2
; https://autohotkey.com/board/topic/48426-accelerated-scrolling-script/?p=333222
;
; #UseHook
WheelUp::
WheelDown::
    ; Critical
    CoordMode, Mouse, Screen
    #MaxThreadsPerHotkey 5
    ; MouseGetPos, CursorX, CursorY, Window ; , Control
    MouseGetPos, CursorX, CursorY, Window, Control
    ; -- Window under mouse cursor --
    WinGetTitle, Title, ahk_id %Window%
    WinGetClass, ahk_class, ahk_id %Window%
    WinGetText, VisibleText, ahk_id %Window%
    WinGet, WindowPID, PID, ahk_id %Window%
    WinGet, ControlText, ControlList, ahk_id %Window%
    WinGetTitle, Title, ahk_id %Window%
    WinGetClass, ahk_class, ahk_id %Window%
    WinGetText, VisibleText, ahk_id %Window%
    ; CursorHwnd := MouseGetPos, , , hwnd
    ; MouseGetPos, , CursorHwnd, ClassNN
    ; WinGetTitle, Title, ahk_pid %CursorHWnd%
    CursorHwnd := DllCall("WindowFromPoint", "int64", CursorX | (CursorY << 32), "Ptr")
    ; WinGetClass, ahk_class, ahk_id %CursorHwnd%
    ; This works:
    ; ToolTip, %CursorHwnd%
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
            . "CursorHwnd: " CursorHwnd "`n"
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

#e::
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


; Description: Get extended attributes of window under mouse cursor
; Tags: Extended info window, 
; Permalink: https://autohotkey.com/boards/viewtopic.php?f=6&t=43544
; Author: aph
; Version: 0.6
; Hotkey: Win+w
; If not WinActive(ahk_class = "AutoHotkeyGUI") {
; #IfWinNotActive ahk_class AutoHotkeyGUI
    #w::
        ;
        ; TODO:
        ; SendInput !{TAB}
        ; https://autohotkey.com/board/topic/60521-how-to-activate-the-window-currently-under-mouse-cursor/
        ;
        Centered = 0 ; Change this to 1 to center the window on the screen, otherwise it will snap near the bottom right
        DetectHiddenText, On
        MouseGetPos, CursorX, CursorY, Window, Control
        Window := HexToDec(Window)
        ; MouseGetPos, , CursorHwnd, ClassNN
        CursorHwnd := DllCall("WindowFromPoint", "int64", CursorX | (CursorY << 32), "Ptr")
        WinGetClass, ahk_class, ahk_id %CursorHwnd%
        WinGetTitle, Title, ahk_id %Window%
        WinGetTitle, CursorPID, ahk_pid %CursorHWnd%
        WinGetTitle = Title: ahk_id %Window%
        WinGetClass, ahk_class, ahk_id %Window%
        WinGetText, WindowText, ahk_id %Window%
        WinGet, WindowPID, PID, ahk_id %Window%
        WinGet, ControlText, ControlList, ahk_id %Window%
        StringReplace, ControlText, ControlText, `n, %A_SPACE%, All
        ; ControlText = %ControlText%
        WinGetTitle, Title, ahk_id %Window%
        WinGetText, WindowText, ahk_id %Window%
        StringReplace, WindowText, WindowText, `n,  , All
        StringReplace, WindowText, WindowText, %A_SPACE%%A_SPACE%, , All
        If not (WindowText = "")
            WindowText = `n%WindowText%
        WinGetTitle, Title, ahk_id %Window% ; retrieves window title from HWND
        ; --- Control ---
        ; https://autohotkey.com/boards/viewtopic.php?t=23987
        WinGetTitle, Title, ahk_id %Window%
        ; ControlGet, OutputVar, Hwnd,, %FocusedClassNN%, %Title%
        ; ControlGetText, ControlText, , ahk_id %ControlHwnd%
        ; ControlGet, ListList, List, Selected, %FocusedClassNN%, %Title%
        Loop, Parse, ListList, `n
        { ; Rows are delimited by linefeeds (`n).
            RowNumber := A_Index
            Loop, Parse, A_LoopField, %A_Tab% ; Fields (columns) in each row are delimited by tabs (A_Tab).
                ListRows := ListRows . Row #%RowNumber% Col #%A_Index% is %A_LoopField%
        }
    ;    Loop Parse, List, `n    ; Rows are delimited by linefeeds (`n).
    ;    {
    ;            RowNumber := A_Index
    ;            Loop Parse, A_LoopField, A_Tab    ; Fields (columns) in each row are delimited by tabs (A_Tab).
    ;                    ; ListRows := ListRows . "Row #" RowNumber " Col #" A_Index " is " A_LoopField
    ;                    ListRows := ListRows . RowNumber ", " A_Index ": " A_LoopField "`n"
    ;    }
        StringReplace, ListRows, List, `t, `n, All
        ; ControlGet, ListList, List,, %FocusedClassNN%, %Title%
        ; Loop, Parse, ListList, `n
        ;     ComboBoxItems = ComboBox Item number %A_Index% is "%A_LoopField%."
        ; ControlGet, ListText, List, , , ahk_id %ControlHwnd% ; "List", retrieves all the text from a ListView, ListBox, or ComboBox controls
        WinGetTitle, Title, ahk_id %Window%
        WinGetClass, ahk_class, ahk_id %Window%
        ; DetectHiddenText, On
        WinGetText, Text, ahk_id %Window%
        ; count := StrSplit(WindowText, "`n")
        ; TrayTip, , % "Number of newlines: "count
        ; Loop, Parse, WindowText, `n
        ; {
            ; Loop, Parse, A_LoopField, `n
                ; WindowText := WindowText . " `n"
        ; }
        ; Loop, Parse, WindowText, \n
            ; StringReplace, WindowText, WindowText, %A_LoopField%
        ;StringReplace, WindowText, WindowText, `n, %A_SPACE%,, All
        WinGet, ahk_exe, ProcessName, ahk_id %Window%
        WinGet, Path, ProcessPath, ahk_id %Window%
        ; List Text: %ListText%
        ; List Rows: %ListRows%
        ; CursorHwnd: %CursorHwnd%
        ; PID: %CursorPID%
        UnderCursor = 
(
%Title%
ahk_id = %Window%
ahk_exe = %ahk_exe%
ahk_class = %ahk_class%
Path: %Path%
PID: %WindowPID%

CursorHwnd: %CursorHwnd%

Visible Text:%WindowText%

Control:
ClassNN: %Control%

Control Visible Text:
%ControlText%
)
        ; TODO:
        ; Add copy to clipboard buttons
        Gui, Destroy
        SysGet, Workspace, MonitorWorkArea
        ; Gui, Show, AutoSize Center
        ; Gui, Add, Edit, vInfo ReadOnly +Wrap w300, %UnderCursor%
        Gui, Add, Text, , Ctrl+C to copy to clipboard. Repeat %A_ThisHotkey% to update.
        ; Style with BG color instead of making editable
        ; Gui, Add, Edit, vInfo ReadOnly +Wrap w400, %UnderCursor%
        Gui, Add, Edit, vInfo +Wrap w400, %UnderCursor%
        ; WinGetPos, ParentX, ParentY,,, ahk_id %ParentHWND%
        ; GuiControl, Move, Info, % "w"WorkSpaceRight/8.5 " h"WorkSpaceBottom/7 ; Height inherits from control. Width too small on Chrome
        ; GuiControl, Delete
        DetectHiddenWindows, On
        Gui, +LastFound +AlwaysOnTop +Resize +Owner
        GuiHwnd := WinExist()
        ; WinGet, scriptPID, PID, %A_ScriptFullPath% - AutoHotkey v
        WinGet, scriptPID, PID, %A_ScriptName%
        ; ControlGet, Edit1Hwnd, %scriptPID%, , Edit1
        ; GuiControlGet,TextVarName
        ; Gui, Add, Edit, vInfo ReadOnly +Wrap w300, %UnderCursor%
        ; Gui, Add, Edit, vInfo w400 +Wrap w400, %UnderCursor%
        ; WinGetPos, ParentX, ParentY,,, ahk_id %ParentHWND%
        ; GuiControl, Delete
        ; Gui, Hide
        ; GuiControl, Move, Info, h500
        ; Gui, Add, Text, , GuiHwnd: %GuiHwnd%`nScriptPID: %scriptPID%
        ; Gui, Show, Hide
        ; Gui, Show, h400 Hide
        ; GuiControl, Move, vInfo, h280
        ; Gui, Show, h%GuiCtrlH% Hide
        Gui, Show, h260 Hide
        GuiControlGet, GuiCtrl, Pos, Info  ; The position/size will be stored in GuiCtrlX, GuiCtrlY, GuiCtrlW, and GuiCtrlH
        ; ToolTip, %GuiCtrlX% %GuiCtrlY% %GuiCtrlW% %GuiCtrlH%
        GuiControl, Move, Info, h220
        ; GuiControl, Move, OK, x100 y200 h500  ; Move the OK button to a new location.
        ; ControlGet, Edit1Hwnd, , , ahk_id %ControlHwnd%
        AspectRatio := WorkspaceRight/WorkSpaceBottom
        ; GuiControl, Move, OK, x100 y200 h500  ; Move the OK button to a new location.
        ; GuiControl, Focus, LastName  ; Set keyboard focus to the control whose variable or text is "LastName".
        ; TextVar:="text second time"
        ; GuiControl,,TextVar,%TextVar%
        If (!Centered) {
            GUI_ID := WinExist()
            WinGetPos, GUIX, GUIY, GUIWidth, GUIHeight, ahk_id %GUI_ID%
            ; ToolTip, GUIX: %GUIX% GUIY: %GUIY% GUIWidth: %GUIWidth% GUIHeight: %GUIHeight%
            ; Gui, Add, Text, , GUIX: %GUIX%, GUIY: %GUIY%, GUIWidth: %GUIWidth%, GUIHeight: %GUIHeight%
            Offset = 30
            ; %GUIX% %GUIY% %GUIWidth% %GUIHeight%
            if not (WorkSpace) {
                ; Gui, Show, +AutoSize % "x"WorkspaceRight-GUIWidth-WorkspaceRight/Offset/AspectRatio " y"WorkspaceBottom-GUIHeight-WorkSpaceBottom/Offset, Cursor info
                ; Gui, Show, AutoSize Center, Cursor info
                ; Gui, Show, h500, Cursor info
                ;  x(WorkspaceRight-GUIWidth-WorkspaceRight/Offset/AspectRatio) y(WorkspaceBottom-GUIHeight-WorkSpaceBottom/Offset)
                ; Gui, Show, % "x"WorkspaceRight-GUIWidth-WorkspaceRight/Offset/AspectRatio " y"WorkspaceBottom-GUIHeight-WorkSpaceBottom/Offset, Window under cursor
                Gui, Show, % "x"WorkspaceRight-GUIWidth-WorkspaceRight/Offset/AspectRatio " y"WorkspaceBottom-GUIHeight-WorkSpaceBottom/Offset, Window under cursor
                ; Gui, Show, "x"WorkspaceRight-GUIWidth-WorkspaceRight/Offset/AspectRatio " y"WorkspaceBottom-GUIHeight-WorkSpaceBottom/Offset " hAuto", Window under cursor
            }
        }
        Else {
            Gui, Show, , Window Extended Info ; Empty param can be AutoSize Center
        }
        WinActivate, %Window%
        ; ~Esc::
            ; KeyWait, Esc, D
            ; if (WinActive("ahk_id " GUI_ID)) {
                ; Gui, Destroy
                ;; Process, Exist, %GUI_ID%
                ;; If (ErrorLevel = 0)
                    ;; Process, Close, %GUI_ID%
            ; }
        Return
    Return
; }

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
; Author: aph
; Version: 0.1
; Hotkey: Middle mouse button down
$*MButton::
    MouseGetPos, CursorX, CursorY, Window, Control
    WinGetTitle, WindowTitle, ahk_id %Window%
    WinGetClass, ahk_class, ahk_id %Window%
    WinGet ahk_exe, ProcessName, ahk_id %Window%
    WinGet PID, PID, ahk_id %Window%
    WinGetText, VisibleText, ahk_id %Window%
    WinActivate, %WindowTitle%
    AllowedKeys := GetKeyState("LWin", "D")
    ; TODO:
    ; AllowedApp := InStr(ahk_exe, "explorer.exe", "explorer.exe" . "sublime_text.exe" . "mmc.exe" . "RegWorkshopX64.exe")
    ; AllowedApp := ahk_exe.HasKey(AllowedApps)
    ; ToolTip, %AllowedApp%
    ;
    AllowedText := InStr(VisibleText, "Tree View") or InStr(VisibleText, "FolderView")
    if (AllowedText >= 1)
        AllowedText = 1
    ; ToolTip, % AllowedText
    ; AllowedApp := "explorer.exe" . "sublime_text.exe" . "mmc.exe" . "RegWorkshopX64.exe" . "systempropertiesadvanced.exe" . "7zFM.exe"
    ; AllowedApp := InStr("explorer.exe", AllowedApp)
     ; if (AllowedApp >= 1)
        ; AllowedApp = 1
    ; ToolTip, AllowedApps %AllowedApps%
    AllowedApp := (ahk_exe = "explorer.exe") or (ahk_exe = "RegWorkshopX64.exe") or (ahk_exe = "sublime_text.exe") or (ahk_exe = "mmc.exe") or (ahk_exe = "systempropertiesadvanced.exe") or (ahk_exe = "7zFM.exe")
    ; AllowedClass := ahk_class = "CabinetWClass" ; add "Shell_TrayWnd"
    TrayTipText = App: %ahk_exe%`nAllowedApp: %AllowedApp%`nAllowedKeys: %AllowedKeys% ; `nAllowedClass: %AllowedClass% ; `nDisallowedClass: %DisallowedClass%
    ; TrayTip, Scroll status, %TrayTipText%
    if (ahk_class = "Shell_TrayWnd") {
    If !AllowedKeys and !AllowedApp and !(WindowTitle = "Change Icon")  {
        If (TrayTipText)
            ToolTip, Not using middle button scroll:`n%TrayTipText%
        ; WinActivate, ahk_class %ahk_class%
        WinActivate, %WindowTitle%
        SendInput {MButton Down}
    }
    }
    Else {
        ; ToolTip, Scrolling wth middle button:`n%TrayTipText%
        ; ControlFocus, OK, Some Window Title  ; Set focus to the OK button
        If (ahk_exe = "sublime_text.exe") and GetKeyState("Alt", "D") or GetKeyState("LWin", "D") or GetKeyState("Ctrl", "D") {
            If (TrayTipText)
                ToolTip, Hothey modifier for Sublime
            Send {MButton Down}
            Return
        }
        MiddleScroll := 1
        SetSystemCursor("SIZEALL")
        Sensitivity = 10 ; How far the middle mouse wheel has to be dragged before scrolling is triggered
        MouseGetPos, X1, Y1, , c, 2
        OrigTimer := 40 ; How quickly the file list scrolls
        SetTimer, MBScroll, %OrigTimer%
        MBScroll:
            MouseGetPos, X2, Y2
            Distance := Abs(Y2-Y1)
            If (Distance >= Sensitivity) {
                Rounded := % Round((Distance / 200)**1.25+1)
                DllCall("SystemParametersInfo", UInt, 0x69, UInt, Round(Ln(Rounded)+1), UInt, 0, UInt, 0) ; Vary lines scrolled by distance of drag
                ; DllCall("SystemParametersInfo", UInt, 0x69, UInt, %OrigTimer%/40, UInt, 0, UInt, 0) ; Vary lines scrolled by distance of drag
                Timer := Round(OrigTimer - (OrigTimer/2*Percent/100))
                SetTimer, MBScroll, %Timer%
                Percent := (A_ScreenHeight - (Max(Y1, Abs(Y1-A_ScreenHeight)) - Distance)) / A_ScreenHeight * 100
                SendInput, % "{Blind}{Wheel" (Y2 > Y1 ? "Down" : "Up") " " Rounded "}"
            }
        Return
        $*MButton Up::
        ; If (MiddleScroll = 1) {
            DllCall("SystemParametersInfo", UInt, 0x69, UInt, 3, UInt, 0, UInt, 0) ; Set back to original 3 lines per scroll event when dragging stops
            SetTimer, MBScroll, off
            SetSystemCursor()
            MiddleScroll := 0
        ; }
        ; Else {
            SendInput {MButton Up}
        ; }
        SetSystemCursor(Cursor="") {
            SystemCursors := "32512IDC_ARROW|32513IDC_IBEAM|32514IDC_WAIT|32515IDC_CROSS|32516IDC_UPARROW|32642IDC_SIZENWSE|32643IDC_SIZENESW|32644IDC_SIZEWE|32645IDC_SIZENS|32646IDC_SIZEALL|32648IDC_NO|32649IDC_HAND|32650IDC_APPSTARTING|32651IDC_HELP"
            If (Cursor = "")
                Return DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "UInt", 0, "UInt", 0) 
            If (StrLen(SystemCursors) = 221)
                Loop, Parse, SystemCursors, |
                    StringReplace, SystemCursors, SystemCursors, %A_LoopField%, % DllCall("LoadCursor", "UInt", 0, "Int", SubStr(A_LoopField, 1, 5)) A_LoopField
            If !(Cursor := SubStr(SystemCursors, InStr(SystemCursors "|", "IDC_" Cursor "|") - 5 - p := (StrLen(SystemCursors) - 221) / 14, 5))
                MsgBox, 262160, %A_ScriptName% - %A_ThisFunc%(): Error, Invalid cursor name!
            Else
                Loop, Parse, SystemCursors, |
                    DllCall("SetSystemCursor", "UInt", DllCall("CopyIcon", "UInt", Cursor), "Int", SubStr(A_LoopField, 6, p))
            }
Return
    }
    
; $*MButton::
;    MouseGetPos, CursorX, CursorY, Window, Control
;    WinGetTitle, WindowTitle, ahk_id %Window%
;    WinGetClass, ahk_class, ahk_id %Window%
;    WinGet ahk_exe, ProcessName, ahk_id %Window%
;    WinGet PID, PID, ahk_id %Window%
;    WinGetText, VisibleText, ahk_id %Window%
;    TreeViewFound = 0
;    IfInString, VisibleText, Tree View
;        TreeViewFound = 1
;    If (not (ahk_exe = "explorer.exe") or (%TreeViewFound%) or (ahk_class = "EVERYTHING")) {
;        Send {MButton Down}
;    }
;    Else {
;        WinActivate, %WindowTitle%
;        Sensitivity = 10 ; how far it takes before the scroll happens
;        MouseGetPos, X1, Y1, , c, 2
;        OrigTimer := 40
;        SetTimer, MBScroll, %OrigTimer%
;        MBScroll:
;            MouseGetPos, X2, Y2
;            Distance := Abs(Y2-Y1)
;            If (Distance >= Sensitivity) {
;                MiddleScroll := 1
;                Rounded := % Round((Distance / 200)**1.25+1)
;                ; DllCall("SystemParametersInfo", UInt, 0x69, UInt, Round(Ln(Rounded)+1), UInt, 0, UInt, 0) ; Set to 1 line per
;                DllCall("SystemParametersInfo", UInt, 0x69, UInt, 1, UInt, 0, UInt, 0) ; Set to 1 line per
;                Timer := Round(OrigTimer - (OrigTimer/2*Percent/100))
;                SetTimer, MBScroll, %Timer%
;                Percent := (A_ScreenHeight - (Max(Y1, Abs(Y1-A_ScreenHeight)) - Distance)) / A_ScreenHeight * 100
;                ; TrayTip, % "Moved " Round(Percent) "%", % "Wheel speed: " Round(Ln(Rounded)+1) "`n Timer: " Timer , 1
;                ; SystemCursor("Off")
;                SetSystemCursor("SIZEALL") 
;                SendInput, % "{Blind}{Wheel" (Y2 > Y1 ? "Down" : "Up") " " Rounded "}"
;                ; MouseMove, 0, % Y1 - Y2, 0, R
;            }
;        Return
;        $*MButton Up::
;        If (MiddleScroll = 1) {
;            DllCall("SystemParametersInfo", UInt, 0x69, UInt, 3, UInt, 0, UInt, 0) ; Restore original value
;            ; DllCall("SystemParametersInfo", UInt, 0x69, UInt, Scroll_Lines, UInt, 0, UInt, 0) ; Restore original value
;            SetTimer, MBScroll, off
;            ; SystemCursor("On")
;            SetSystemCursor()
;            MiddleScroll := 0
;            ; TrayTip
;        }
;        else {
;            SendInput {MButton Up}
;        }
;        SetSystemCursor(Cursor="") {
;                SystemCursors := "32512IDC_ARROW|32513IDC_IBEAM|32514IDC_WAIT|32515IDC_CROSS|32516IDC_UPARROW|32642IDC_SIZENWSE|32643IDC_SIZENESW|32644IDC_SIZEWE|32645IDC_SIZENS|32646IDC_SIZEALL|32648IDC_NO|32649IDC_HAND|32650IDC_APPSTARTING|32651IDC_HELP"
;                If (Cursor = "")
;                        Return DllCall("SystemParametersInfo", "UInt", 0x57, "UInt", 0, "UInt", 0, "UInt", 0) 
;                If (StrLen(SystemCursors) = 221)
;                        Loop, Parse, SystemCursors, |
;                                StringReplace, SystemCursors, SystemCursors, %A_LoopField%, % DllCall("LoadCursor", "UInt", 0, "Int", SubStr(A_LoopField, 1, 5)) A_LoopField
;                If !(Cursor := SubStr(SystemCursors, InStr(SystemCursors "|", "IDC_" Cursor "|") - 5 - p := (StrLen(SystemCursors) - 221) / 14, 5))
;                        MsgBox, 262160, %A_ScriptName% - %A_ThisFunc%(): Error, Invalid cursor name!
;                Else
;                        Loop, Parse, SystemCursors, |
;                                DllCall("SetSystemCursor", "UInt", DllCall("CopyIcon", "UInt", Cursor), "Int", SubStr(A_LoopField, 6, p))
;        }
;    Return
;    }
; Return