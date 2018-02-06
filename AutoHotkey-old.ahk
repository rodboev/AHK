


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
