# AutoHotkey.ahk  [[⇨]](https://github.com/rodboev/AHK/blob/master/AutoHotkey.ahk)

> A full set of power-user tools not found elsewhere in the AHK community
> <br />

---

<br />

```asciidoc
 ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
 ┃ MIDDLE-BUTTON SMOOTH-SCROLL ┃
 ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

 [ MButton + drag ] -> Invoke smooth scrolling on any app; release to stop.
```

- Universal Smooth, fractional scrolling in Explorer (and other capable apps system-wide) on middle mouse button drag
- Robust four-layered fallback mechanism ensures smooth-scrolling across all apps, mimicking Chrome as closely as possible
- Auto-detects and skips windows that already have native middle-button scroll implementations

---

<br />

```asciidoc
┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ WINDOWS TERMINAL FROM ANYWHERE ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

[ F10 ] -> Open Windows Terminal as user in current active window path
[ Shift + F10] -> Open with admin rights
[ Ctrl + Alt + Shift + F10] -> Open with SYSTEM rights (edit any reg key!)
```

- **Works everywhere**
  - Any Explorer window (including virtual folders like Desktop) opens current folder open
  - Any application (opens its home folder)
- Highly extensible with robust envvar handling
- Safe fallbacks to user profile if no path found

---

<br />

```asciidoc
 ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
 ┃ SPAWN WINDOWS ON CURRENT MONITOR ┃
 ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

 New and activated windows appear where your cursor is.
```

- **New windows spawn on your cursor's monitor** — no more hunting for windows that opened on the wrong screen
- **Activated windows follow your cursor** — re-launching an already-running app from Start Menu or taskbar moves it to you
- **Alt+Tab switcher moves too** — the task switching overlay appears on whichever monitor your cursor is on
- **Cursor-centered popups** — titleless windows (Share dialog, store dialogs) appear at your cursor instead of a default corner
- **Smart filtering** — dialogs stay with their parent, system overlays are ignored, and clicking directly on a window never triggers a move
- **Positive intent detection** - Activated windows moved only when the system detects an intentional launch:

  | Tier | Signal             | Detects                                                     |
  | ---- | ------------------ | ----------------------------------------------------------- |
  | 1    | **Process-start**  | Win32 single-instance re-launch (relay process lives <3s)   |
  | 2    | **Overlay-launch** | UWP re-launch via Start menu (overlay was recently visible) |

---

<br/>

```asciidoc
 ┏━━━━━━━━━━━━━━━━━━━━━┓
 ┃ EXTENDED WINDOW SPY ┃
 ┗━━━━━━━━━━━━━━━━━━━━━┛

 [ Win + W ] -> Toggle tooltip showing window info under cursor
 -> Repeat to freeze as a dialog for copy/paste
 -> Repeat again to close dialog
```

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

---

<br />

## Release notes (v3.1)

### _Peer Review Hardening_

- **UserRun() injection fix** — all arguments are now unconditionally quoted (single-quoted for PowerShell, double-quoted for direct execution) with proper internal-quote escaping. Prevents command injection via metacharacters (`&`, `;`, `$`, `|`) regardless of argument content
- **MButton timer race condition fix** — `Critical` sections in both `MBDragTimer` and `MButton Up` prevent pseudo-thread interruption during COM DllCalls. Null guard for `MB_ScrollPattern` provides belt-and-suspenders protection against Access Violations
- **`#Requires AutoHotkey v1.1.14+`** — minimum version now enforced, enabling `Try/Finally` blocks
- **UserRun() executable quoting** — direct-execution path now quotes the executable, preventing breakage on paths with spaces (e.g., `C:\Program Files\Everything 1.5a\Everything.exe`)
- **Explorer restart via `cmd /c`** — chained `taskkill && start explorer.exe` routed through `cmd` so `&&` is interpreted as a shell operator
- **Elevated PowerShell quoting fix** — `psCmd` single quotes are now escaped (`''`) before embedding in `-ArgumentList '...'`, fixing Shift+F10 and Ctrl+Alt+Shift+F10 broken by unconditional quoting
- **SYSTEM PATH resolution** — `ti.exe` SYSTEM context lacks user PATH entries; executables are now resolved to full absolute paths before launching (via `FindInPath` for `^!+F10` and regex replacement of WMI command lines for `^+=`)
- **UIA element cleanup** — `ObjRelease(_el)` moved to `Finally` block for guaranteed COM pointer release on stale element access violations
- **Window Spy multi-monitor** — dialog now positions on cursor's monitor via `GetCursorMonitor()` instead of inheriting a stale tooltip monitor reference
- **Window Spy hotkey scoping** — `Esc` and `LButton` hotkeys scoped with `#If WindowSpyState` to only activate while spy is running

## Release notes (v3.0)

### _Architecture Improvements_

- **Positive intent detection** (Phase 11) — activation path inverted from 7-guard default-move to 2-tier default-skip. Brief-process detection (Tier 1) catches Win32 single-instance re-launches; overlay-launch detection (Tier 2) catches UWP re-launches via Start menu. Net result: ~125 lines → ~55 lines, 12+ globals → single `WS` object
- **Zero-flash opacity** (Phase 10) — `EVENT_OBJECT_CREATE` hook hides windows 55-77ms before shell hook fires, eliminating visual flash on wrong monitor
- **File separation** — window spawning code moved to `window-spawning.ahk` (was inline in `AutoHotkey.ahk`)
- **Global encapsulation** — all window spawning state consolidated into single `WS := {}` object

<br />

## Release notes (v2.4)

### _Window Spawning on Current Monitor_

- **Shell hook + WinEvent architecture** — `RegisterShellHookWindow` for creation/activation/destroy + `SetWinEventHook` for SHOW/UNCLOAKED events
- **Event-driven UWP detection** — deferred processing via WinEvent hooks for instant UWP window moves (~62ms)
- **Relative position mapping** — windows maintain their proportional position when moved between monitors of different sizes
- **Maximized window handling** — restore → move → re-maximize to land correctly on the target monitor
- **Smart owner filtering** — owned windows with a visible parent are skipped (real dialogs); owned windows with a hidden owner are allowed (Win+R Run dialog)
- **Alt+Tab passthrough hotkey** — `~!Tab::` with non-blocking WinEvent detection moves the DWM-hosted switcher overlay
- **Activation guards** — overlay dismissal, taskbar click, and same-monitor checks prevent unintended moves

<br />

## Release notes (v2.3)

### _Explorer Smooth Scroll_

- No dependencies, self-contained, all-new code
  - The script is self-contained and does not introduce new external dependencies.
  - This is a complete replacement of any previous MButton scrolling logic.
- Behavioral Changes
  - Users will experience significantly enhanced and more adaptable MButton drag-scrolling across various applications.
    -The fallback logic makes scrolling smoother in applications that normally exhibit jerky behavior with wheel messages.
- Performance Implications: `GetScrollPos` fallback introduces two DllCalls and a brief Sleep on the first scroll event for the WHEEL_CTRL method, which may introduce negligible latency designed to be imperceptible to the user.
- Documentation: Added extensive architectural documentation

### _Extended Window Spy_

- **Controls sorted alphabetically** for easier scanning
- **Items >80 chars filtered out** from Controls and Window Text (reduces noise from long GUIDs/paths)
- **Dialog auto-sizes to workspace** - uses available screen height instead of fixed 40 rows
- **Dialog width increased** from 500px to 700px for better readability
- **Dialog positioned flush** to bottom-right corner (removed 20px offset)
- **Reduced flicker** - Cursor position line commented out, UIA simplified to persistent reference only
- **Faster updates** - 800ms refresh (down from 1500ms)

<br />

## Release notes (v2.1)

Extended Window Spy (`#w`) with comprehensive window information display.

### _Extended Window Spy_

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

<br />

## Release notes (v2.0)

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
