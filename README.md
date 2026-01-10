### Release notes (v1.0)

Major refactoring of AutoHotkey.ahk with advanced multi-method smooth, trackpad-like, and (where possible) fractional scrolling on middle mouse button down, similar to Chrome's implementation.

The focus is on Windows Explorer but the same ultra-smooth fractional scrolling effect is replicated for Electron apps like VS Code. Fallback methods are used for other apps like MMC and System Informer, which have no native MButton scrolling.

Even without fractional scrolling, the default 3-line per scroll is reduced to at most 1 line, and smoothing is used for all methods so that the end result is unified, both in terms of functionality and visual impact.

The methods used include UI Automation, WM_MOUSEWHEEL, and WM_VSCROLL Win32 API calls to cover a deliberately broad cross-section of frequently used apps. All methods employ acceleration and minimize the janky default scroll behavior in Windows.

Other features include enhanced core process execution, privilege de/escalation, user context management, and window management.

## Changes

- **Core Script (`AutoHotkey.ahk`):**
    - Implemented advanced multi-method MButton drag-scrolling (`lines 843-1054`) with dynamic timer-based acceleration, intelligently selecting between UIA (UI Automation), WHEEL (WM\_MOUSEWHEEL messages), and VSCROLL (WM\_VSCROLL messages) methods based on the active application and control.
    - Enhanced the `UserRun` function to support flexible process execution, including elevation with `RunFromProcess-x64` and dynamic argument parsing/escaping for PowerShell and Windows Terminal environments.
    - Introduced new hotkeys for launching and elevating Windows Terminal (`F10`, `+F10`, `^!+F10`) and System Informer (`^+`).
    - Added hotkeys for copying the current Explorer path (`#c`) and the active window's full command line (`+#c`) to the clipboard.
    - Refactored and simplified existing hotkeys for Sublime Text, global volume control, Explorer navigation (Backspace to go up), Everything search, and Media Player Classic scrolling.
- **Community contributions:** Added several community-contributed AHK libraries as new `includes/` components: `_Struct.ahk`, `Acc.ahk`, `sizeof.ahk`, `TT.ahk`, `ini.ahk` (utility/frameworks), `Dock.ahk` (window docking), `HoverScroll.ahk` (hover-based scrolling), `FindText.ahk` (screen image OCR), `EitherMouse.ahk` (multi-mouse support), `NiftyWindows.ahk` (advanced window management like AOT and roll-up), and `WindowDraggingResizing.ahk` (advanced window manipulation with snapping). They are not used in the main .ahk, but are some of the best scripts available and a great reference.
- **Documentation:** Technical `summary.md` document (`lines 0-241`) detailing the architecture and rationale behind the new drag-scroll features. Specifically designed for context transfer across AI models.

## Impact

- **Behavioral Changes:** Users will experience a significantly enhanced and more adaptable MButton drag-scrolling experience across various applications. Process execution via `UserRun` is more robust and flexible. New hotkeys provide quick access to Windows Terminal, System Informer, and advanced clipboard and window management functions.
- **Performance Implications:** The new multi-method drag-scrolling aims for smoother acceleration through dynamic timer adjustments for VSCROLL. The introduction of complex UIA/COM objects and additional hooks from the new modules could potentially impact overall script responsiveness, although specific performance gains or regressions are not quantified.
- **Codebase Structure:** The adoption of an `includes/` directory provides a more organized structure for third-party libraries, separating them from the main script's custom logic.