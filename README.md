# AutoHotkey.ahk  [[ ⇨ ]](https://github.com/rodboev/AHK/blob/master/AutoHotkey.ahk)

>
><i>"Get your Windows groove back!"</i>\
>--  @rodboev
<br />

---
<br />

```asciidoc
 ┏━━━━━━━━━━━━━━━━━━━━━━━━┓
 ┃ EXPLORER SMOOTH SCROLL ┃
 ┗━━━━━━━━━━━━━━━━━━━━━━━━┛

 [ MButton + drag ] -> Scroll like a king (or in Chrome)
```
<br />

- Super-smooth fractional scrolling in Explorer (and more) on middle mouse button drag, similar to Chrome
- Robust Scrolling System: A new, 4-layered comprehensive MButton drag-scroll feature provides custom scrolling in any window of your choosing
- Select from one of four methods (UI Automation, WHEEL, WHEEL_CTRL, VSCROLL), each designed to provide the best possible smooth-scroll experience based on application.

### *New in v2.4*
- **Universal app support** — smooth scroll works in ALL apps automatically, no configuration needed
- **Native scroll auto-detection** — apps with built-in MButton drag-scroll (like Chrome) are detected at runtime and left alone
- **Auto-fallback chain** — UIA → WHEEL → WHEEL_CTRL → VSCROLL, probed per app on first drag

<br />

---

<br />

```asciidoc
┏━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ WINDOWS TERMINAL HOTKEY ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━┛

[ F10 ] -> Open Windows Terminal as user (auto de-escalation if running in privileged user context)
[ Shift+F10] -> ... with user admin rights
[ Ctrl+ShiftF10] -> ... with TrustedInstaller (NT AUTHORITY/SYSTEM) privileges (edit any reg key!)
```

<br />

- **Works everywhere**
  - Any Explorer window (including virtual folders) opens current folder open
  - Any application (opens its home folder)
- Highly extensible with robust envvar handling
- Safe fallbacks to user profile or desktop if no path found

<br />

---

<br />

```asciidoc
 ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
 ┃ SPAWN WINDOWS ON CURRENT MONITOR ┃
 ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
 
 New and activated windows appear where your cursor is
```

<br />

- **New windows spawn on your cursor's monitor** — no more hunting for windows that opened on the wrong screen
- **Activated windows follow your cursor** — re-launching an already-running app from Start Menu or taskbar moves it to you
- **Alt+Tab switcher moves too** — the task switching overlay appears on whichever monitor your cursor is on
- **Smart filtering** — dialogs stay with their parent, system overlays are ignored, and clicking directly on a window never triggers a move

### Positive intent detection

Activated windows are **not** moved by default — only when the system detects you intentionally launched something:

| Tier | Signal | Detects |
|------|--------|---------|
| 1 | **Brief-process** | Win32 single-instance re-launch (relay process lives <3s) |
| 2 | **Overlay-launch** | UWP re-launch via Start menu (overlay was recently visible) |

Retained guards: `WS_IsMovable` filter, taskbar cursor check, same-monitor skip.

### Zero-flash window spawning

New windows are hidden via opacity (`WS_EX_LAYERED` + alpha 0) at `EVENT_OBJECT_CREATE` time — 55-77ms before the shell hook fires. After `WS_MoveToMonitor` places the window on the correct monitor, full opacity is restored. No visual flash on the wrong monitor.

<br />

---

<br/>

```asciidoc
 ┏━━━━━━━━━━━━━━━━━━━━━┓
 ┃ EXTENDED WINDOW SPY ┃
 ┗━━━━━━━━━━━━━━━━━━━━━┛

 [ Win+W ] -> Toggle persistent tooltip showing window info (active + under cursor)
```

<br />

- Auto updated info for active window and window under cursor, for both windows and controls
- Manipulate any window with more info than AHK Extended Window Spy at your fingertips
- Pause updates by hovering over the tooltip, click it to convert to a dialog for copying. Close at any time with Win+W or Esc
- Sorts Controls and visibile/invisible Window Text alphabetically, separated by commas for easy browsing
- Sample output:

        Title: Device Manager
        ahk_exe: C:\Windows\System32\mmc.exe
        ahk_class: MMCMainFrame
        ahk_id: 0x90452
        Window handle (hWnd): 0x1a0dae

        Folder: C:\Windows\System32
        Process command line: "C:\Windows\system32\mmc.exe" C:\Windows\system32\devmgmt.msc
        Process ID: 44748 (Elevated)

        Position: (5192, 869)
        Monitor: 2
        Size: 1835 x 1056
        Style: 0x14CF0000
        ExStyle: 0x00000100
        UIAID: 9805520

        Focused Control: SysTreeView321

        Window Text: Device Manager, ActionsPaneView, Device Manager, 0

        Controls: AfxFrameOrView42u1, AfxOleControl42u1, AfxWnd42u1, AMCCustomTab1, AtlAxWinEx1,
          CtrlNotifySink1, CtrlNotifySink2, DirectUIHWND1, Edit1, MDIClient1, MMCChildFrm1,
          MMCOCXViewWindow1, MMCViewWindow1, msctls_progress321, msctls_statusbar321,
          msctls_updown321, NativeHWNDHost1, ReBarWindow321, ScrollBar1, ScrollBar2,
          SizeableRebar1, Static1, Static2, SysHeader321, SysListView321, SysTreeView321,
          SysTreeView322, ToolbarWindow321, ToolbarWindow32

 You can target any combination of these to manipulate any window or control using AutoHotkey.

<br />

---

## Release notes (v3.0)

### *Security & Stability Hardening*

- **UserRun() injection fix** — all arguments are now unconditionally quoted (single-quoted for PowerShell, double-quoted for direct execution) with proper internal-quote escaping. Prevents command injection via metacharacters (`&`, `;`, `$`, `|`) regardless of argument content
- **MButton timer race condition fix** — `Critical` sections in both `MBScrollTimer` and `MButton Up` prevent pseudo-thread interruption during COM DllCalls. Null guard for `MB_ScrollPattern` provides belt-and-suspenders protection against Access Violations

### *Architecture Improvements*

- **Positive intent detection** (Phase 11) — activation path inverted from 7-guard default-move to 2-tier default-skip. Brief-process detection (Tier 1) catches Win32 single-instance re-launches; overlay-launch detection (Tier 2) catches UWP re-launches via Start menu. Net result: ~125 lines → ~55 lines, 12+ globals → single `WS` object
- **Zero-flash opacity** (Phase 10) — `EVENT_OBJECT_CREATE` hook hides windows 55-77ms before shell hook fires, eliminating visual flash on wrong monitor
- **File separation** — window spawning code moved to `window-spawning.ahk` (was inline in `AutoHotkey.ahk`)
- **Global encapsulation** — all window spawning state consolidated into single `WS := {}` object

<br />

## Release notes (v2.5)

### *Window Spawning on Current Monitor*

- **Shell hook + WinEvent architecture** — `RegisterShellHookWindow` for creation/activation/destroy + `SetWinEventHook` for SHOW/UNCLOAKED events
- **Event-driven UWP detection** — deferred processing via WinEvent hooks for instant UWP window moves (~62ms)
- **Relative position mapping** — windows maintain their proportional position when moved between monitors of different sizes
- **Maximized window handling** — restore → move → re-maximize to land correctly on the target monitor
- **Smart owner filtering** — owned windows with a visible parent are skipped (real dialogs); owned windows with a hidden owner are allowed (Win+R Run dialog)
- **Alt+Tab passthrough hotkey** — `~!Tab::` with non-blocking WinEvent detection moves the DWM-hosted switcher overlay
- **Activation guards** — overlay dismissal, taskbar click, and same-monitor checks prevent unintended moves

### *New Helper Functions*

- `GetCursorMonitor()` — returns which monitor (1-based) the mouse cursor is on
- `IsRemoteSession()` — detects RDP, Hyper-V, and VMWare sessions to disable the feature

<br />

## Release notes (v2.3)

### *Explorer Smooth Scroll*

- No dependencies, self-contained, all-new code
  - The script is self-contained and does not introduce new external dependencies.
  - This is a complete replacement of any previous MButton scrolling logic.
- Behavioral Changes
  - Users will experience significantly enhanced and more adaptable MButton drag-scrolling across various applications.
  -The fallback logic makes scrolling smoother in applications that normally exhibit jerky behavior with wheel messages.
- Performance Implications: `GetScrollPos` fallback introduces two DllCalls and a brief Sleep on the first scroll event for the WHEEL_CTRL method, which may introduce negligible latency designed to be imperceptible to the user.
- Documentation: Added extensive architectural documentation

### *Extended Window Spy*

- **Controls sorted alphabetically** for easier scanning
- **Items >80 chars filtered out** from Controls and Window Text (reduces noise from long GUIDs/paths)
- **Dialog auto-sizes to workspace** - uses available screen height instead of fixed 40 rows
- **Dialog width increased** from 500px to 700px for better readability
- **Dialog positioned flush** to bottom-right corner (removed 20px offset)
- **Reduced flicker** - Cursor position line commented out, UIA simplified to persistent reference only
- **Faster updates** - 800ms refresh (down from 1500ms)

### *New Helper Functions*

- `FilterLongItems(text, maxLen)` - Removes items exceeding maxLen from comma-separated list
- `SortList(text)` - Sorts comma-separated items alphabetically
- `HasVal(arr, val)` - Simplify condition checks. Check iIf array contains a value (allow partial match)
- `isPath(str)` - Check if string is a path
- `UserRun(str)` - Improved to better handle process execution, elevation, and argument parsing, especially for PowerShell and Windows Terminal.
- `FindInPath(exe)` - Search for executable in PATH

<br />

## Release notes (v2.2)

Extended Window Spy (`#w`) with comprehensive window information display.

### *Extended Window Spy*

- **Persistent tooltip** showing real-time info for both Active Window and Window Under Cursor
- **Hover-to-freeze**: Hover over tooltip to freeze or press `#w` again to close
- **Click-to-select**: Click tooltip to convert it to a dialog which allows selecting the relevant info to copy.
- **Information displayed**:
  - Title, ahk_id, ahk_class, ahk_exe, directory, command line
  - PID (with elevation indicator), monitor number
  - Position, size, style, ex-style
  - Focused control (active) / control under cursor with hWnd
  - Cursor position (screen and relative to window)
  - UIA element info (type, name) via UI Automation
  - Window text, controls (comma-separated, wrapped at 100 chars)
- **Dialog features**: auto-sized, bottom-right positioned

### *New Helper Functions*

- `GetExePath(winTitle)` - Returns `{path, dir}` for window's process
- `GetMonitor(winTitle)` - Returns which monitor (1-based) a window is on
- `IsProcessElevated(pid)` - Checks if process is running elevated
- `WrapList(text, delimiter, maxLen)` - Wraps text at delimiter boundaries

### *Other Changes*

- `ProcessExistsByCommandLine(cmdLine)` - Find process by command line substring
- Activate-or-launch pattern for `#e` (e++), `+!e` (VS Code), `^e` (Sublime Text)
- F10 hotkeys now use `A_Desktop`/`A_UserProfile` instead of env vars
- Standardized on `GetExePath()` helper across codebase

<br />

## Release notes (v2.1)

Major refactoring of AutoHotkey.ahk with advanced multi-method smooth, trackpad-like, and (where possible) fractional scrolling on middle mouse button down, similar to Chrome's implementation.

The focus is on Windows Explorer but the same ultra-smooth fractional scrolling effect is replicated for Electron apps like VS Code. Fallback methods are used for other apps like MMC and System Informer, which have no native MButton scrolling.

Even without fractional scrolling, the default 3-line per scroll is reduced to at most 1 line, and smoothing is used for all methods so that the end result is unified, both in terms of functionality and visual impact.

- ### Scroll Methods
        +------------+----------------------------------------------------+----------------------------------+
        | Method     | Mechanism                                          | Best For                         |
        +------------+----------------------------------------------------+----------------------------------+
        | UIA        | `SetScrollPercent` super-smooth via UI Automation  | Windows Explorer, mmc.exe        |
        | WHEEL      | `WM_MOUSEWHEEL` super-smooth for Electron apps     | VSCode, Cursor, Antigravity      |
        | WHEEL_CTRL | `WM_MOUSEWHEEL` by-line with smooth acceleration   | SystemInformer                   |
        | VSCROLL    | `WM_VSCROLL` by-line, universal fallback           | Explorer nav and all other app   |
        +------------+----------------------------------------------------+----------------------------------+

All methods employ acceleration curves and dynamic timers to minimize the janky default scroll behavior in Windows.

- ### App Configuration
    For now, apps and controls are configured via arrays at the top of the scroll section:

        MB_PassthroughApps := ["chrome.exe", "everything64.exe", "VmConnect.exe"]
        MB_EnabledApps := ["mmc.exe", "7zFM.exe", "code.exe", "SystemInformer.exe"]
        MB_ExcludedControls := ["ToolbarWindow", "ReBarWindow", "Edit", "SysHeader"]

### *Changes*

- Implemented advanced multi-method MButton drag-scrolling (`lines 837-1117`) with dynamic timer-based acceleration, intelligently selecting between UIA, WHEEL, WHEEL_CTRL, and VSCROLL methods based on the active application and control.
- Added `GetScrollPos`-based fallback detection: WHEEL_CTRL auto-switches to VSCROLL if the control scrolls >1 line per message, reverting the jump invisibly.
- Consolidated configuration into arrays (`MB_PassthroughApps`, `MB_EnabledApps`, `MB_ExcludedControls`) with `HasVal` helper for easy customization.
- Extended the `UserRun` function to support flexible process execution, including elevation with `RunFromProcess-x64` and dynamic argument parsing/escaping for PowerShell and Windows Terminal environments.
- Introduced new hotkeys for launching and elevating Windows Terminal (`F10`, `+F10`, `^!+F10`) and System Informer (`^+`).
- Added hotkeys for copying the current Explorer path (`#c`) and the active window's full command line (`+#c`) to the clipboard.
- Refactored and simplified existing hotkeys for Sublime Text, global volume control, Explorer navigation (Backspace to go up), Everything search, and Media Player Classic scrolling.
- Added several community AHK libraries in `includes/` for reference:
            
            `_Struct.ahk`, `Acc.ahk`, `sizeof.ahk`, `TT.ahk`
            `ini.ahk` (utility/frameworks), `Dock.ahk` (window docking)
            `HoverScroll.ahk` (hover-based scrolling)
            `FindText.ahk` (screen image OCR)
            `EitherMouse.ahk` (multi-mouse support)
            `NiftyWindows.ahk` (advanced window management like AOT and roll-up)
            `WindowDraggingResizing.ahk` (advanced window manipulation with snapping)

- Technical `.claude/summary.md` document detailing the architecture and rationale.\
  Designed for context transfer across AI models.
