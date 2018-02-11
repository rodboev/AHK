;  #  Windows key
;  ^  Ctrl
;  +  Shift
;  !  Alt
; +!  Shift+Alt
; 
; All timers have to be above all hotkeys

#SingleInstance Force
#NoEnv
#Persistent

FileGetAttrib, attribs, %A_ScriptFullPath%
if (attribs="A") {
    FileSetAttrib, -A, %A_ScriptFullPath%
    TrayTip, AutoHotKey, Reloaded script from:`n%A_ScriptFullPath%,, 1
}
OnExit, ExitSub
return
ExitSub:
    if (A_ExitReason="Reload") {
        FileSetAttrib, +A, %A_ScriptFullPath%
    }
ExitApp

;
; Prevent script proceeding if conditions are met
;
;#if (!WinActive("ahk_exe bfh.exe"))
;#if (!WinActive("ahk_class R6Game"))
if (WinActive("ahk_class TscShellContainerClass"))
    Return

SendMode Input
SetWorkingDir %A_ScriptDir%

;
; Shift+Alt+R
;
MsgBox, %attribs%
+!r::
FileSetAttrib, +A, %A_ScriptFullPath%
Reload
return

;
; https://autohotkey.com/board/topic/44474-make-windows-snap-to-the-edges-of-the-screen/
;
snap_prox = 40 ;in px
~LButton::
KeyWait, LButton
SysGet, screen, MonitorWorkArea
WinGetActiveStats, title_act, w_act, h_act, x_act, y_act ;active window title and dimensions
If (w_act < screenright-snap_prox) {
    If (x_act > screenleft-snap_prox AND x_act < screenleft OR x_act < screenleft+snap_prox AND x_act > screenleft)
        WinMove, %title_act%,, screenLeft
            If (x_act + w_act > screenright-snap_prox AND x_act + w_act < screenright OR x_act + w_act < screenright+snap_prox AND x_act + w_act > screenright)
                WinMove, %title_act%,, (screenright-w_act)
}
If (h_act < screenbottom-snap_prox) {
    If (y_act > screentop-snap_prox AND y_act < screentop OR y_act < screentop+snap_prox AND y_act > screentop)
        WinMove, %title_act%,,, screentop
    If (y_act + h_act > screenbottom-snap_prox AND y_act + h_act  < screenbottom OR y_act + h_act < screenbottom+snap_prox AND y_act + h_act > screenbottom)
        WinMove, %title_act%,,, (screenbottom-h_act)
}
Return

;
; http://www.autohotkey.com/board/topic/95834-using-winwait-effectively-or-how-else-should-i-execute-an-action-when-a-pop-up-window-appears/#entry603588
;
SetTimer, CloseVT, 1000
Return
CloseVT:
IfWinExist, VirusTotal Uploader
    ControlGetText, Status, Static1 
    IfInString, Status, Checking, WinHide
    IfInString, Status, Hash found
    {
        Sleep 100
        WinClose
    }
Return

;
; Multiply mouse wheel speed in Eclipse main edit control window
;
#IfWinActive ahk_class SWT_Window0
WheelUp::
WheelDown::
ControlGetFocus, active
StringGetPos, pos, active, SWT_Window
;MsgBox, pos
Critical
if (pos = 0) {
    WheelSteps := A_EventInfo*2
    SendInput, {%A_ThisHotkey% %WheelSteps%}
}
else {
    WheelSteps := A_EventInfo
    SendInput, {%A_ThisHotkey%}
}
Return
#IfWinActive

;;
;; Shift+Alt+T = Show the current process path
;;
;+!t::
;WinGet, Path, ProcessPath, A
;Gui, Add,Edit,vdata ReadOnly, %path%
;Gui, Add, Button, gGuiDefault, Close
;Gui, Show,, Current process
;return
;GuiDefault:
;Gui, Destroy
;Return

;
; Restore Win+X key functionality disabled via Group Policy
;
if (A_ComputerName = "CORE") {
; Win+R = Run
#r::
SetTitleMatchMode, 3
IfWinExist, Run
    WinActivate
else
    Run, shell:::{2559a1f3-21d7-11d4-bdaf-00c04f60b9f0}
    IfWinNotActive
        WinWait, Run
        WinActivate
return
; Win+L: Turn off monitor
#l::Run RunFromProcess-x64 explorer.exe nircmd cmdwait 200 monitor off
; Win+D = Show desktop
toggle = 0
#d::
if toggle := !toggle
    WinMinimizeAll
else
    WinMinimizeAllUndo
Return
; Win+E = Open Explorer window
#e::
IfWinExist Run
    WinActivate
Else
    Run ::{20D04FE0-3AEA-1069-A2D8-08002B30309D}
    IfWinNotActive
        WinWait, Computer
        WinActivate
Return
}

;
; Win+S = Run or activate Everything
;
#s::
SetTitleMatchMode, RegEx
IfWinExist ^(.* - )?Everything
    WinActivate
else
    Run RunFromProcess-x64 explorer.exe C:\Program Files\Everything\Everything.exe
    IfWinNotActive
        WinWait, ^(.* - )?Everything
        WinActivate
return


;
; Win+N = Run or activate Sublime Text/Notepad
;
#n::
SetTitleMatchMode, RegEx
IfWinExist ^(.* - )?Sublime Text
    {
    WinActivate
    SendInput !s
    }
else
    {
    Run RunFromProcess-x64 explorer.exe C:\Windows\notepad.exe
    IfWinNotActive
        WinWait, ^(.* - )?Sublime Text
        WinActivate
    }
return

;;
;; Win+G = Run or activate Google Chrome
;;
;#g::
;SetTitleMatchMode, RegEx
;IfWinExist ^(.* - )?Google Chrome
;    WinActivate
;else
;    Run RunFromProcess-x64 explorer.exe C:\Program Files (x86)\Google\Chrome\Application\chrome.exe
;    IfWinNotActive
;        WinWait, ^(.* - )?Google Chrome
;        WinActivate
;return


;;
;; Win+B = Prep mouse for BFH
;;
;#B::
;SetTitleMatchMode, 3
;IfWinExist, Mouse Properties
;{
;    WinActivate
;    Send !e
;    Send, {Enter}
;}
;Else
;{
;    Run RunFromProcess-x64 explorer.exe %A_WinDir%\system32\control.exe main.cpl`,`,2
;    IfWinNotActive
;        WinWait, Mouse Properties
;        WinActivate
;        Send !e
;        Send, {Enter}
;}
;; http://www.autohotkey.com/board/topic/98317-if-process-exist-command/
;Process, Exist, sakasa.exe
;If (ErrorLevel = 0)
;{
;    Run RunFromProcess-x64 explorer.exe J:\FPL\sakasa.exe
;}
;Else
;{
;    Process, Close, %ErrorLevel%
;    ; http://www.autohotkey.com/board/topic/39844-taskbar-delete-icon-refresh-icons/
;    ControlGetPos,,,w,h,ToolbarWindow321, AHK_class Shell_TrayWnd
;    width:=w, hight:=h
;    While % ((h:=h-5)>0 and w:=width){
;        While % ((w:=w-5)>0){
;            PostMessage, 0x200,0,% ((hight-h) >> 16)+width-w,ToolbarWindow321, AHK_class Shell_TrayWnd
;        }
;    }
;}
;Return

;;
;; Shift+WheelUp/Down = Scroll by 30 lines
;; Alt+WheelUp/Down = Scroll horizontally
;;
;+WheelUp::Send {Click WheelUp 30}
;+WheelDown::Send {Click WheelDown 30}
;;#IfWinActive ahk_class PX_WINDOW_CLASS
;;{
;    ;WheelUp::Click WheelUp 3
;    ;WheelDown::Click WheelDown 3
;    ;return
;;}
;;!WheelUp::Send {Click WheelLeft 2}
;;!WheelDown::Send {Click WheelRight 2}

;
; Run Process Hacker
;
^+`::Run nircmd runassystem "C:\Program Files\Process Hacker 2\ProcessHacker.exe"
^+1::Run nircmd runassystem "C:\WINDOWS\system32\cmd.exe"
;
; Alt+Shift+E = Edit current script (as normal user)
;
+!e::Run RunFromProcess-x64 explorer.exe notepad %A_ScriptFullPath%

;;
;; Win+Shift+Up = Maximize across all monitors
;; Source: http://stackoverflow.com/questions/9828808/how-can-i-maximize-a-window-across-multiple-monitors
;;
;+!Up::
;  WinGetActiveTitle, Title
;  WinRestore, %Title%
;  SysGet, X1, 76
;  SysGet, Y1, 77
;  SysGet, Width, 78
;  SysGet, MonitorCount, MonitorCount
;  SysGet, MonitorWorkArea, MonitorWorkArea, %MonitorCount%
;  WinMove, %Title%,, X1, Y1, Width, %MonitorWorkAreaBottom%
;return
;
;+!Down::
;  WinGetActiveTitle, Title
;  WinMove, %Title%,, 0, 0
;  WinMaximize, %Title%
;return

; ;
; ; 
; ; http://www.autohotkey.com/board/topic/119457-autohotkey-conflicting-with-altdrag-; altmove-etc/?p=681353
; ;
; +!LButton::
; CoordMode, Mouse  ; Switch to screen/absolute coordinates.
; MouseGetPos, SWM_MouseStartX, SWM_MouseStartY, SWM_MouseWin
; SetTimer, SWM_WatchMouse_Move, 0 ; Track the mouse as the user drags it.
; ; Gui,MoveWindow: -caption +AlwaysOnTop +ToolWindow
; ; Gui,MoveWindow: font, s12 w700 Cffffff, arial
; ; Gui,MoveWindow: Add, Text,, move window
; ; Gui,MoveWindow: Color, 800080
; ; Gui,MoveWindow: Show
; ; KeyWait, LButton, R
; ; Sleep, 300
; ; Gui,MoveWindow: destroy
; return
; 
; 
; +!RButton::
; CoordMode, Mouse  ; Switch to screen/absolute coordinates.
; MouseGetPos, SWM_MouseStartX, SWM_MouseStartY, SWM_MouseWin
; WinGetPos, SWM_WinX, SWM_WinY, SWM_WinW, SWM_WinH, ahk_id %SWM_MouseWin%
; SWM_ResizeTypeX=0
; SWM_ResizeTypeY=0
; if (SWM_MouseStartX < SWM_WinX+SWM_WinW/2)
;    SWM_ResizeTypeX=1
; if (SWM_MouseStartY < SWM_WinY+SWM_WinH/2)
;    SWM_ResizeTypeY=1
; SetTimer, SWM_WatchMouse_Resize, 10 ; Track the mouse as the user drags it.
; ; Gui,ResizeWindow: -caption +AlwaysOnTop +ToolWindow
; ; Gui,ResizeWindow: font, s12 w700 Cffffff, arial
; ; Gui,ResizeWindow: Add, Text,, resize window
; ; Gui,ResizeWindow: Color, 800080
; ; Gui,ResizeWindow: Show
; ; KeyWait, RButton, R
; ; Gui,ResizeWindow: destroy
; return
; 
; SWM_WatchMouse_Move:
; GetKeyState, SMW_LButtonState, LButton, P
; if SMW_LButtonState = U ; Button has been released, so drag is complete.
; {
;    SetTimer, SWM_WatchMouse_Move, off
;    return
; }
;   GoSub SWM_GetMouseAndWindowPos
; SWM_WinX += %SWM_DeltaX%
; SWM_WinY += %SWM_DeltaY%
; SetWinDelay, -1   ; Makes the below move faster/smoother.
; WinMove, ahk_id %SWM_MouseWin%,, %SWM_WinX%, %SWM_WinY%
; return
; SWM_WatchMouse_Resize:
; GetKeyState, SMW_RButtonState, RButton, P
; if SMW_RButtonState = U ; Button has been released, so drag is complete.
; {
;    SetTimer, SWM_WatchMouse_Resize, off
;    return
; }
;    GoSub SWM_GetMouseAndWindowPos
; if SWM_ResizeTypeX
; {
;    SWM_WinX += %SWM_DeltaX%
;    SWM_WinW -= %SWM_DeltaX%
; }
; else
;    SWM_WinW += %SWM_DeltaX%
; if SWM_ResizeTypeY
; {
;    SWM_WinY += %SWM_DeltaY%
;    SWM_WinH -= %SWM_DeltaY%
; }
; else
;    SWM_WinH += %SWM_DeltaY%
; SetWinDelay, -1   ; Makes the below move faster/smoother.
; WinMove, ahk_id %SWM_MouseWin%,, %SWM_WinX%, %SWM_WinY%, %SWM_WinW%, %SWM_WinH%
; return
; SWM_GetMouseAndWindowPos:
; CoordMode, Mouse
; MouseGetPos, SWM_MouseX, SWM_MouseY
; SWM_DeltaX = %SWM_MouseX%
; SWM_DeltaX -= %SWM_MouseStartX%
; SWM_DeltaY = %SWM_MouseY%
; SWM_DeltaY -= %SWM_MouseStartY%
; SWM_MouseStartX = %SWM_MouseX%  ; Update for the next timer call to this subroutine.
; SWM_MouseStartY = %SWM_MouseY%
; WinGetPos, SWM_WinX, SWM_WinY, SWM_WinW, SWM_WinH, ahk_id %SWM_MouseWin%
; return
; 
; 
; ;
; ; http://www.howtogeek.com/howto/27080/how-to-scroll-the-command-prompt-window-with-the; -keyboard/
; ;
; #IfWinActive ahk_class ConsoleWindowClass
; PgUp::
;     ControlClick, , ahk_class ConsoleWindowClass, , WheelUp
; Return
; 
; PgDn::
;     SendInput {WheelDown}
; Return
; 
; ^Up:: 
;     SendInput {WheelUp}
; Return
; 
; ^Down:: 
;     SendInput {WheelDown} 
; Return
; 
; ^V::
;     SendInput {Raw}%clipboard%
; return
; 
; #IfWinActive
; 
; 
; ;
; ; Toggle Always on top
; ; Source: http://www.howtogeek.com/howto/13784/keep-a-window-on-top-with-a-handy-; autohotkey-script/
; ;
; +!A::  Winset, Alwaysontop, , A


;
; Context sensitive AHK help
;
;+F1::
;SetWinDelay 10
;SetKeyDelay 0
;AutoTrim, On
;
;if A_OSType = WIN32_WINDOWS  ; Windows 9x
;    Sleep, 500  ; Give time for the user to release the key.
;
;C_ClipboardPrev = %clipboard%
;clipboard =
;; Use the highlighted word if there is one (since sometimes the user might
;; intentionally highlight something that isn't a command):
;Send, ^c
;ClipWait, 0.1
;if ErrorLevel <> 0
;{
;    ; Get the entire line because editors treat cursor navigation keys differently:
;    Send, {home}+{end}^c
;    ClipWait, 0.2
;    if ErrorLevel <> 0  ; Rare, so no error is reported.
;    {
;        clipboard = %C_ClipboardPrev%
;        return
;    }
;}
;C_Cmd = %clipboard%  ; This will trim leading and trailing tabs & spaces.
;clipboard = %C_ClipboardPrev%  ; Restore the original clipboard for the user.
;Loop, parse, C_Cmd, %A_Space%`,  ; The first space or comma is the end of the command.
;{
;    C_Cmd = %A_LoopField%
;    break ; i.e. we only need one interation.
;}
;IfWinNotExist, AutoHotkey Help
;{
;    ; Determine AutoHotkey's location:
;    RegRead, ahk_dir, HKEY_LOCAL_MACHINE, SOFTWARE\AutoHotkey, InstallDir
;    if ErrorLevel  ; Not found, so look for it in some other common locations.
;    {
;        if A_AhkPath
;            SplitPath, A_AhkPath,, ahk_dir
;        else IfExist ..\..\AutoHotkey.chm
;            ahk_dir = ..\..
;        else IfExist %A_ProgramFiles%\AutoHotkey\AutoHotkey.chm
;            ahk_dir = %A_ProgramFiles%\AutoHotkey
;        else
;        {
;            MsgBox Could not find the AutoHotkey folder.
;            return
;        }
;    }
;    Run RunFromProcess-x64 explorer.exe %ahk_dir%\AutoHotkey.chm
;    WinWait AutoHotkey Help
;}
;; The above has set the "last found" window which we use below:
;WinActivate
;WinWaitActive
;StringReplace, C_Cmd, C_Cmd, #, {#}
;send, !n{home}+{end}%C_Cmd%{enter}
;return

;
; http://www.howtogeek.com/howto/8955/make-backspace-in-windows-7-or-vista-explorer-go-up-like-xp-did/
;
#IfWinActive, ahk_class CabinetWClass
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
return

$XButton2::
 While GetKeyState("XButton2","p"){
  Send {Volume_Up}
  Sleep 100
 }
return

;
; Scroll Explorer on middle button drag
; https://autohotkey.com/board/topic/39768-is-it-possible-to-scroll-with-middle-mouse-button-drag/
;
Toggle = 0
Toggle2 = 0
#MaxThreadsPerHotkey 2
#IfWinActive, ahk_class CabinetWClass
$*MButton Up::
SetTimer, MBScroll, off
SystemCursor("On")
return
$*MButton::
  Sensitivity = 10 ; how far it takes before the scroll happens
  MouseGetPos, X1, Y1, , c, 2
  SetTimer, MBScroll, 20
  MBScroll:
  MouseGetPos, X2, Y2
  If Abs(Y2-Y1) >= Sensitivity
  {
    SystemCursor("Off")
    ;SendMessage, 0x115, % (Y2 > Y1), 0, , Ahk_ID %c%
    SendInput, % "{Blind}{Wheel" (Y2 > Y1 ? "Down}" : "Up}")"{Blind}{Wheel" (Y2 > Y1 ? "Down}" : "Up}")"{Blind}{Wheel" (Y2 > Y1 ? "Down}" : "Up}")
    MouseMove, 0, % Y1 - Y2, 0, R
  }

  return
; Handle hiding of the cursor:
SystemCursor(OnOff=1)   ; INIT = "I","Init"; OFF = 0,"Off"; TOGGLE = -1,"T","Toggle"; ON = others
{
    static AndMask, XorMask, $, h_cursor
        ,c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13 ; system cursors
        , b1,b2,b3,b4,b5,b6,b7,b8,b9,b10,b11,b12,b13   ; blank cursors
        , h1,h2,h3,h4,h5,h6,h7,h8,h9,h10,h11,h12,h13   ; handles of default cursors
    if (OnOff = "Init" or OnOff = "I" or $ = "")       ; init when requested or at first call
    {
        $ = h                                          ; active default cursors
        VarSetCapacity( h_cursor,4444, 1 )
        VarSetCapacity( AndMask, 32*4, 0xFF )
        VarSetCapacity( XorMask, 32*4, 0 )
        system_cursors = 32512,32513,32514,32515,32516,32642,32643,32644,32645,32646,32648,32649,32650
        StringSplit c, system_cursors, `,
        Loop %c0%
        {
            h_cursor   := DllCall( "LoadCursor", "uint",0, "uint",c%A_Index% )
            h%A_Index% := DllCall( "CopyImage",  "uint",h_cursor, "uint",2, "int",0, "int",0, "uint",0 )
            b%A_Index% := DllCall("CreateCursor","uint",0, "int",0, "int",0
                , "int",32, "int",32, "uint",&AndMask, "uint",&XorMask )
        }
    }
    if (OnOff = 0 or OnOff = "Off" or $ = "h" and (OnOff < 0 or OnOff = "Toggle" or OnOff = "T"))
        $ = b  ; use blank cursors
    else
        $ = h  ; use the saved cursors

    Loop %c0%
    {
        h_cursor := DllCall( "CopyImage", "uint",%$%%A_Index%, "uint",2, "int",0, "int",0, "uint",0 )
        DllCall( "SetSystemCursor", "uint",h_cursor, "uint",c%A_Index% )
    }
}
#IfWinActive

;
; https://autohotkey.com/board/topic/78284-boldly-scroll-where-no-one-has-scrolled-before/page-2
;
#IfWinNotActive ahk_class ACDViewer or ahk_class SpotifyMainWindow
WheelUp::
WheelDown::
CoordMode, Mouse, Screen
Critical
MouseGetPos, m_x, m_y
hw_m_target := DllCall( "WindowFromPoint", "int64", m_x | (m_y << 32), "Ptr")
WinGetClass, MyClass, ahk_id %hw_m_target%
WheelSteps := A_EventInfo
DllCall( "SendMessage", "Ptr", hw_m_target, "UInt", 0x20A, "Ptr", WheelSteps * (A_ThisHotkey == "WheelUp" ? 1 : -1) * 120 << 16, "Ptr", ( m_y << 16 )|m_x )
Return
#IfWinNotActive

; http://stackoverflow.com/questions/28957636/hotkey-for-next-song-in-spotify
; https://autohotkey.com/board/topic/94263-problem-with-using-multiple-mouse-buttons-as-hotkey/
~XButton1 & XButton2::Send {Media_Next}
~XButton2 & XButton1::Send {Media_Next}
