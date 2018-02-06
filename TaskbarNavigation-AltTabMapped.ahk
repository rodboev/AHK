;---------------------------------------------------------------
; TaskbarNavigation - switch windows sequentially in order of taskbar left right.
; http://www.autohotkey.com/board/topic/91577-taskbarnavigation-switch-windows-in-taskbar-order-alt-tab-replacement/
; This script uses code from ActivateByNum (http://code.google.com/p/activatebynum/)
;---------------------------------------------------------------
#NoEnv ;adding the line #NoEnv anywhere in the script improves DllCall's performance when unquoted parameter types are used (e.g. int vs. "int").
#SingleInstance Force
#WinActivateForce
#UseHook Off
SetBatchLines -1
ListLines Off

If( !A_IsCompiled && FileExist(A_ScriptDir . "\TaskbarNavigation.ico")) {
	Menu, Tray, Icon, %A_ScriptDir%\TaskbarNavigation.ico
}

Menu, Tray, NoStandard
Menu, Tray, Add, &Show Hotkeys, KeyListGUI
Menu, Tray, Add, &Disable Hotkeys, DisableHotkeys
Menu, tray, add ; separator
Menu, tray, add, &Reload This Script, MyReload
Menu, tray, add, ListHotkeys Debug, MyListHotkeys
;Menu, tray, add, &Edit This Script, MyEdit
Menu, tray, add ; separator
Menu, Tray, Add, E&xit, QuitScript

Disabled := 0

;Register Win+Num hotkeys
Loop 10 {
	n := A_Index-1
	Hotkey, #%n%, ActivateTaskbarItem%n%
	Hotkey, #Numpad%n%, ActivateTaskbarItem%n%
}

KeyListText=
KeyListText .= "Win		Hold down to show tooltips with the Window position numbers on taskbar.`n"
KeyListText .= "Win+[Number]	Go to the window with that number position on the taskbar.`n"
KeyListText .= "Alt+Tab		Go to next window on taskbar`n"
KeyListText .= "Alt+Shift+Tab	Go to previous window on taskbar`n"
KeyListText .= "Alt+``		Switch to previous Z-order window"
KeyListText .= "`n`nThese keys can be changed by modifying the script at:"

Gui, Margin, 6, 6
Gui, Font, s11, Lucida Console
Gui, Add, Text, , %KeyListText%
Gui, Add, Edit, w780 -Wrap r1 ReadOnly, www.autohotkey.com/board/topic/91577-taskbarnavigation-ordered-left-right-cycle-through-task-bar-alt-tab-replacement/
Gui, Add, Button, w200 Center Default vOKButton gCloseKeyListGUI, OK

Return ;end of auto-execute
;---------------------------------------------------------------
; Tray custom right click menu functions
;---------------------------------------------------------------

KeyListGUI:
	Gui, Show, , TaskBarNavigation Show Hotkeys
	GuiControl, Focus, OKButton
Return

DisableHotkeys:
	If(Disabled) {
		Suspend, Off
		Disabled := 0
		Menu, Tray, Uncheck, &Disable Hotkeys
	} Else {
		Suspend, On
		Disabled := 1
		Menu, Tray, Check, &Disable Hotkeys
	}
Return

CloseKeyListGUI:
Gui, Hide
Return

QuitScript:
	ExitApp
Return

;---------------------------------------------------------------
; Close current window
;---------------------------------------------------------------
; #w::SendInput, !{F4}

;---------------------------------------------------------------
; Switch to previous Z-order window
;---------------------------------------------------------------
; !`::SendInput, {ALTDOWN}{TAB}{ALTUP}

!`::
curActiveHwnd := DllCall("GetForegroundWindow")
hwnd := curActiveHwnd
Loop {
	hwnd := DllCall("GetWindow", UInt, hwnd, UInt, 2) ; 2 = GW_HWNDNEXT
	If(DllCall("IsWindowVisible", UInt, hwnd)) {
		Break
	;} Else {
	;	Tooltip, Next window wasn't visible
	}
}
DllCall("SetForegroundWindow", UInt, hwnd) ;METHOD 2c
If(DllCall("IsIconic", UInt, hwnd)) { ;METHOD 2c, check if minimized
	DllCall("ShowWindow", UInt, hwnd, UInt, 9) ;METHOD 2b, 9=SW_RESTORE
}
Return

;---------------------------------------------------------------
; Begin Main TaskBarNavigation
;---------------------------------------------------------------

;Holding down LWin or RWin will show tooltips
~LWin::
~RWin::
Gosub, ShowToolTips
Return

LWin Up::
RWin Up::
	Gosub, RemoveToolTips
Return

; Go to previous item on task bar
+!Tab::
	Gosub, ReadWindowsOnTaskbar
	If(ActiveTaskbarItem) {
		ItemPrev := ActiveTaskbarItem - 1
		If(ItemPrev < 1) {
			ItemPrev := TaskbarItemCount
		}
	} Else {	;If currently on a window without a taskbar entry - go to first item
		ItemPrev := 1
	}
	ActivateTaskbarItem(ItemPrev)
Return

; Go to next item on task bar
!Tab::
	Gosub, ReadWindowsOnTaskbar
	If(ActiveTaskbarItem) {
		ItemNext := ActiveTaskbarItem+1
		If(ItemNext > TaskbarItemCount) {
			ItemNext := 1
		}
	} Else {	;If currently on a window without a taskbar entry - go to first item
		ItemNext := 1
	}
	ActivateTaskbarItem(ItemNext)
Return

;---------------------------------------------------------------
ShowToolTips:
Gosub, ReadWindowsOnTaskbarForToolTip
CoordMode, ToolTip, Screen

Loop, %TaskbarItemCount%
{
	If(A_Index > 10)
		Break
	x := g_xs%A_Index%
	y := g_ys%A_Index%
	If A_Index = 10
		text = 0
	Else
		text = %A_Index%

	ToolTip, %text%, %x%, %y%, %A_Index%
}
Return

RemoveToolTips:
	Loop, 10
		ToolTip,,,,%A_Index%
Return

;---------------------------------------------------------------
ActivateTaskbarItem(n) {
	hwnd := TaskbarItem%n%
	If(hwnd) {
		If(DllCall("IsIconic", UInt, hwnd)) { ;METHOD 1a, check if minimized
			DllCall("ShowWindow", UInt, hwnd, UInt, 9) ;METHOD 1b, 9=SW_RESTORE
		}
		DllCall("SetForegroundWindow", UInt, hwnd) ;METHOD 1c
	}
}

;---------------------------------------------------------------
ReadWindowsOnTaskbar:
	ActiveTaskbarItem=
	if(!pidTaskbar) {
		WinGet,	pidTaskbar, PID, ahk_class Shell_TrayWnd
	}
	hProc := DllCall("OpenProcess", UInt, 0x38, Int, 0, UInt, pidTaskbar)
	pProc := DllCall("VirtualAllocEx", UInt, hProc, UInt, 0, UInt, 32, UInt, 0x1000, UInt, 0x4)
	if(!idxTB) {
		idxTB := GetTaskSwBar()
	}
	SendMessage, 0x418, 0, 0, ToolbarWindow32%idxTB%, ahk_class Shell_TrayWnd ; TB_BUTTONCOUNT
	buttonCount := ErrorLevel

	TaskbarItemCount := 1
	Loop, %buttonCount%	{
		SendMessage, 0x417, A_Index-1, pProc, ToolbarWindow32%idxTB%, ahk_class Shell_TrayWnd ; TB_GETBUTTON
		VarSetCapacity(btn, 32, 0)
		DllCall("ReadProcessMemory", UInt, hProc, UInt, pProc, UInt, &btn, UInt, 20, UInt, 0)
		idn	:= NumGet(btn, 4)
		fsState := NumGet(btn, 8, "uchar")
		;fsStyle := NumGet(btn, 9, "uchar")
		dwData := NumGet(btn, 12)
		DllCall("ReadProcessMemory", UInt, hProc, UInt, dwData, Int64P, hWnd:=0, UInt, dwData ? 4:8, UInt, 0)
		If(hWnd) {
			If(fsState&1) { ; Checks for TBSTATE_CHECKED in fsState in TB_GETBUTTON
				ActiveTaskbarItem := TaskbarItemCount
			}
			TaskbarItem%TaskbarItemCount% := hWnd
			GetTaskbarButtonTopLeft(idn, x, y)
			SetButtonTopLeftLoc(TaskbarItemCount, x, y)
			TaskbarItemCount++
		}
	}
	TaskbarItemCount--
Return

;---------------------------------------------------------------
ReadWindowsOnTaskbarForToolTip:
	if(!pidTaskbar) {
		WinGet,	pidTaskbar, PID, ahk_class Shell_TrayWnd
	}
	hProc := DllCall("OpenProcess", UInt, 0x38, int, 0, UInt, pidTaskbar)
	pProc := DllCall("VirtualAllocEx", UInt, hProc, UInt, 0, UInt, 32, UInt, 0x1000, UInt, 0x4)
	if(!idxTB) {
		idxTB := GetTaskSwBar()
	}
	SendMessage, 0x418, 0, 0, ToolbarWindow32%idxTB%, ahk_class Shell_TrayWnd ; TB_BUTTONCOUNT
	buttonCount := ErrorLevel

	TaskbarItemCount := 1
	Loop, %buttonCount%	{
		SendMessage, 0x417, A_Index-1, pProc, ToolbarWindow32%idxTB%, ahk_class Shell_TrayWnd ; TB_GETBUTTON
		VarSetCapacity(btn, 32, 0)
		DllCall("ReadProcessMemory", UInt, hProc, UInt, pProc, UInt, &btn, UInt, 20, UInt, 0)
		idn	:= NumGet(btn, 4)
		dwData := NumGet(btn, 12)
		DllCall("ReadProcessMemory", UInt, hProc, UInt, dwData, int64P, hWnd:=0, UInt, dwData ? 4:8, UInt, 0)
		If(hWnd) {
			GetTaskbarButtonTopLeft(idn, x, y)
			SetButtonTopLeftLoc(TaskbarItemCount, x, y)
			TaskbarItemCount++
		}
	}
	TaskbarItemCount--
Return

;---------------------------------------------------------------
GetTaskSwBar()
{
	ControlGet, hParent, hWnd,, MSTaskSwWClass1 , ahk_class Shell_TrayWnd
	ControlGet, hChild , hWnd,, ToolbarWindow321, ahk_id %hParent%
	Loop
	{
		ControlGet, hWnd, hWnd,, ToolbarWindow32%A_Index%, ahk_class Shell_TrayWnd
		If Not hWnd
			Break
		Else If hWnd = %hChild%
		{
			idxTB := A_Index
			Break
		}
	}
	Return idxTB
}

;---------------------------------------------------------------
GetTaskbarButtonTopLeft(id, ByRef x, ByRef y)
{
	global idxTB, pidTaskbar
	if(!idxTB) {
		idxTB := GetTaskSwBar()
	}
	if(!pidTaskbar) {
		WinGet,	pidTaskbar, PID, ahk_class Shell_TrayWnd
	}
	hProc := DllCall("OpenProcess", UInt, 0x38, Int, 0, UInt, pidTaskbar)
	pProc := DllCall("VirtualAllocEx", UInt, hProc, UInt, 0, UInt, 32, UInt, 0x1000, UInt, 0x4)
	;idxTB := GetTaskSwBar()	; dont think this is needed again

    SendMessage, 0x433, id, pProc, ToolbarWindow32%idxTB%, ahk_class Shell_TrayWnd ; TB_GETRECT
	;IfEqual, ErrorLevel, 0, return "Err: can't get rect"

	VarSetCapacity(rect, 32, 0)
	DllCall("ReadProcessMemory", UInt, hProc, UInt, pProc, UInt, &rect, UInt, 32, UInt, 0)

	DllCall("VirtualFreeEx", UInt, hProc, UInt, pProc, UInt, 0, UInt, 0x8000)
	DllCall("CloseHandle", UInt, hProc)

	ControlGet, hWnd, hWnd,, ToolbarWindow32%idxTB%, ahk_class Shell_TrayWnd
	WinGetPos, x, y, w, h, ahk_id %hWnd%

	left := NumGet(rect, 0)
	top := NumGet(rect, 4)
	right := NumGet(rect, 8)
	bottom := NumGet(rect, 12)

	x := x + left
	y := y + top
}

;---------------------------------------------------------------
SetButtonTopLeftLoc(gi, x, y)
{
	global
	g_xs%gi% := x
	g_ys%gi% := y
}

;---------------------------------------------------------------
ActivateTaskbarItem1:
	Gosub, ReadWindowsOnTaskbar
	ActivateTaskbarItem(1)
return
ActivateTaskbarItem2:
	Gosub, ReadWindowsOnTaskbar
	ActivateTaskbarItem(2)
return
ActivateTaskbarItem3:
	Gosub, ReadWindowsOnTaskbar
	ActivateTaskbarItem(3)
return
ActivateTaskbarItem4:
	Gosub, ReadWindowsOnTaskbar
	ActivateTaskbarItem(4)
return
ActivateTaskbarItem5:
	Gosub, ReadWindowsOnTaskbar
	ActivateTaskbarItem(5)
return
ActivateTaskbarItem6:
	Gosub, ReadWindowsOnTaskbar
	ActivateTaskbarItem(6)
return
ActivateTaskbarItem7:
	Gosub, ReadWindowsOnTaskbar
	ActivateTaskbarItem(7)
return
ActivateTaskbarItem8:
	Gosub, ReadWindowsOnTaskbar
	ActivateTaskbarItem(8)
return
ActivateTaskbarItem9:
	Gosub, ReadWindowsOnTaskbar
	ActivateTaskbarItem(9)
return
ActivateTaskbarItem0:
	Gosub, ReadWindowsOnTaskbar
	ActivateTaskbarItem(10)
return

;---------------------------------------------------------------
MyReload:
    Reload
Return

MyListHotkeys:
	ListHotkeys
Return

;MyEdit:
;    Edit
;Return

