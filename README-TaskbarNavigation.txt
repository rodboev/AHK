You can choose from a few pre-made sets of mapped hotkeys.

HOTKEYS for TaskbarNavigation-AltTabMapped.ahk:
Win					Hold down to show tooltips with the Window position numbers on taskbar
Win+[Number]		Go to the window with that number position on the taskbar
Alt+Tab				Go to next window on taskbar
Alt+Shift+Tab		Go to previous window on taskbar
Alt+``				Switch to previous Z-order window

HOTKEYS for TaskbarNavigation-NumPadMapped.ahk:
Win					Hold down to show tooltips with the Window position numbers on taskbar
Win+[Number]		Go to the window with that number position on the taskbar
NumpadDiv			Go to previous window on taskbar
NumpadMult			Go to next window on taskbar
NumpadSub           Close current window (emulates Alt+F4)
NumpadAdd			Switch to previous Z-order window"

---------------------------------------------------------------
For more information visit:
http://www.autohotkey.com/board/topic/91577-taskbarnavigation-switch-windows-in-taskbar-order-alt-tab-replacement/

---------------------------------------------------------------
Information about changing hotkeys and customizing this script.

You may modify these scripts to use any hotkeys you like, but keep in mind Windows has security restrictions about which applications can steal Window focus with each other.

Namely - if a hotkey registers itself with WinAPI RegisterHotkey() - then it is allowed to steal and change window focus between windows not sharing memory processes. However if a hotkey is registered with the Autohotkey keyboard hook (for special hotkeys) - then it will not be allowed to change the focus between windows not sharing memory processes and give you the "window only flashing on taskbar problem and not fully activating" problem.

You can check how AutoHotkey is implementing a hotkey via the system tray right click menu of this application and going to "ListHotkeys Debug". The hotkeys for window switching have to be implemented with the "reg" method.

So if changing hotkeys - go to the ListHotkeys debug window and check and make sure that except for LWin/RWin Down-Up keys (these are fine because these just show tooltips and don't need to change window focus) - that all the other hotkeys that need to change window focus are implemented with the "reg" method.

See post #10 here:
http://www.autohotkey.com/board/topic/91577-taskbarnavigation-switch-windows-in-taskbar-order-alt-tab-replacement/#entry604360

For the Microsoft explanation behind the SetForegroundWindow security restrictions, visit:
http://blogs.msdn.com/b/oldnewthing/archive/2009/02/20/9435239.aspx#9436619
http://blogs.msdn.com/b/oldnewthing/archive/2009/02/26/9445006.aspx
http://msdn.microsoft.com/en-us/library/ms633539(v=vs.85).aspx

---------------------------------------------------------------
