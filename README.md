### Release notes (v2.1)

Major refactoring of AutoHotkey.ahk with advanced multi-method smooth, trackpad-like, and (where possible) fractional scrolling on middle mouse button down, similar to Chrome's implementation.

The focus is on Windows Explorer but the same ultra-smooth fractional scrolling effect is replicated for Electron apps like VS Code. Fallback methods are used for other apps like MMC and System Informer, which have no native MButton scrolling.

Even without fractional scrolling, the default 3-line per scroll is reduced to at most 1 line, and smoothing is used for all methods so that the end result is unified, both in terms of functionality and visual impact.

## Scroll Methods

| Method | Mechanism | Best For |
|--------|-----------|----------|
| **UIA** | `SetScrollPercent` via UI Automation | Explorer file lists, mmc.exe |
| **WHEEL** | `WM_MOUSEWHEEL` with sub-120 delta to window | VS Code, Electron apps |
| **WHEEL_CTRL** | `WM_MOUSEWHEEL` to control with fallback detection | SystemInformer |
| **VSCROLL** | `WM_VSCROLL` line-by-line with dynamic timer | Tree views, universal fallback |

All methods employ acceleration curves and dynamic timers to minimize the janky default scroll behavior in Windows.

## Configuration

Apps and controls are configured via arrays at the top of the scroll section (`lines 843-846`):

```autohotkey
MB_PassthroughApps := ["chrome.exe", "everything64.exe", "VmConnect.exe"]
MB_EnabledApps := ["mmc.exe", "7zFM.exe", "code.exe", "SystemInformer.exe"]
MB_ExcludedControls := ["ToolbarWindow", "ReBarWindow", "Edit", "SysHeader"]
```

## Changes

- **Core Script (`AutoHotkey.ahk`):**
    - Implemented advanced multi-method MButton drag-scrolling (`lines 837-1117`) with dynamic timer-based acceleration, intelligently selecting between UIA, WHEEL, WHEEL_CTRL, and VSCROLL methods based on the active application and control.
    - Added `GetScrollPos`-based fallback detection: WHEEL_CTRL auto-switches to VSCROLL if the control scrolls >1 line per message, reverting the jump invisibly.
    - Consolidated configuration into arrays (`MB_PassthroughApps`, `MB_EnabledApps`, `MB_ExcludedControls`) with `HasVal` helper for easy customization.
    - Enhanced the `UserRun` function to support flexible process execution, including elevation with `RunFromProcess-x64` and dynamic argument parsing/escaping for PowerShell and Windows Terminal environments.
    - Introduced new hotkeys for launching and elevating Windows Terminal (`F10`, `+F10`, `^!+F10`) and System Informer (`^+`).
    - Added hotkeys for copying the current Explorer path (`#c`) and the active window's full command line (`+#c`) to the clipboard.
    - Refactored and simplified existing hotkeys for Sublime Text, global volume control, Explorer navigation (Backspace to go up), Everything search, and Media Player Classic scrolling.
- **Community contributions:** Added several community-contributed AHK libraries as new `includes/` components: `_Struct.ahk`, `Acc.ahk`, `sizeof.ahk`, `TT.ahk`, `ini.ahk` (utility/frameworks), `Dock.ahk` (window docking), `HoverScroll.ahk` (hover-based scrolling), `FindText.ahk` (screen image OCR), `EitherMouse.ahk` (multi-mouse support), `NiftyWindows.ahk` (advanced window management like AOT and roll-up), and `WindowDraggingResizing.ahk` (advanced window manipulation with snapping). They are not used in the main .ahk, but are some of the best scripts available and a great reference.
- **Documentation:** Technical `.claude/summary.md` document detailing the architecture and rationale behind the drag-scroll features. Designed for context transfer across AI models.

## Impact

- **Behavioral Changes:** Users will experience a significantly enhanced and more adaptable MButton drag-scrolling experience across various applications. Process execution via `UserRun` is more robust and flexible. New hotkeys provide quick access to Windows Terminal, System Informer, and advanced clipboard and window management functions.
- **Performance Implications:** The new multi-method drag-scrolling aims for smoother acceleration through dynamic timer adjustments for VSCROLL. The introduction of complex UIA/COM objects and additional hooks from the new modules could potentially impact overall script responsiveness, although specific performance gains or regressions are not quantified.
- **Codebase Structure:** The adoption of `includes/` and `.claude/` directories provides a more organized structure for third-party libraries and AI context transfer documentation.