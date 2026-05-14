# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Keep under 30k chars; 40k char max (`wc -c CLAUDE.md`). Compress or remove content when adding.

## AHK v1.1 Language Gotchas (CRITICAL)

**AutoHotkey v1.1.14+** — This codebase uses AHK v1.1 syntax exclusively. Do NOT use v2.0 syntax.

### Syntax Differences from v2.0

- Commands use `Command, Param1, Param2` syntax (not function calls)
- Variables use `%var%` for dereferencing in commands
- Legacy `#IfWinActive` directives (not `#HotIf`)
- `Try/Finally` blocks are available (added in v1.1.14)

### Global Declarations in Pseudo-Threads

Label subroutines (hotkeys, timers) can *read* globals without declaration, but *assignments* create a local that shadows the global. This causes state to reset mid-session.

```autohotkey
; ❌ BROKEN - MB_AccumPct resets to empty on each timer tick
MBDragTimer:
  MB_AccumPct := MB_AccumPct + delta  ; Local variable, not global!
Return

; ✅ CORRECT - Declare ALL shared state at label start
MBDragTimer:
  global MB_AccumPct, MB_Method  ; MUST declare in every label that writes
  MB_AccumPct := MB_AccumPct + delta
Return
```

### Auto-Execute Section Dead Code

The auto-execute section runs from line 1 until the first hotkey label. Code placed between hotkey subroutines is **unreachable**.

**#Include placement**: Since `#Include` directives are at the **bottom** of AutoHotkey.ahk (after all hotkeys), any auto-execute code at the top of included files is dead code. Module files should only contain functions and hotkey labels.

### NumGet Pointer Quirk

When calling COM vtable methods via `DllCall`, **always use `+0` suffix** on pointer variables:

```autohotkey
; ✅ CORRECT - Forces numeric evaluation first
DllCall(NumGet(NumGet(ptr+0)+N*A_PtrSize), ...)

; ❌ BROKEN - AHK v1.1 may misinterpret the variable
DllCall(NumGet(NumGet(ptr)+N*A_PtrSize), ...)
```

### FileDelete/FileAppend with Object Properties

Commands take plain string parameters. Forced expression syntax (`% WS.Property`) is unreliable. Dereference to a local variable first:

```autohotkey
_logFile := WS.LogFile
FileDelete, %_logFile%
```

## Architecture

`AutoHotkey.ahk` is the parent entrypoint. It `#Include`s four module files at the bottom:

| File                    | Purpose                                                              |
| ----------------------- | -------------------------------------------------------------------- |
| `AutoHotkey.ahk`        | Parent: config directives, helpers, bindings, misc hotkeys           |
| `terminal-anywhere.ahk` | Windows Terminal from anywhere (`F10` variants) — user/admin/SYSTEM  |
| `extended-spy.ahk`      | Extended Window Spy (`#w`) — tooltip/dialog with window/control info |
| `mbutton-drag.ahk`      | MButton smooth drag (hotkeys, timer, scroll methods)                 |
| `window-spawning.ahk`   | Shell hook window spawning (WS_Init, hooks, move logic, Alt+Tab)     |

### Core Features

1. **Explorer Smooth Scroll** (`MButton + drag`) — 5-method dual-axis system: LVM, UIA, WHEEL, WHEEL_CTRL, VSCROLL — in `mbutton-drag.ahk`
2. **Window Spawning** — Shell hook + WinEvent hooks move new windows to cursor's monitor — in `window-spawning.ahk`
3. **Extended Window Spy** (`Win+W`) — Persistent tooltip with window/control info — in `extended-spy.ahk`
4. **Terminal/Elevation** (`F10`, `Shift+F10`, `Ctrl+Alt+Shift+F10`, `Ctrl+Shift+Plus`) — Context-aware terminal launching with admin elevation and SYSTEM via ti.exe

## Design Rationale

### Why Raw COM Vtable Calls (No Wrapper Library)

This codebase calls COM interfaces via direct `DllCall` to vtable offsets rather than using wrapper libraries like Descolada's UIA-v2:

1. **Performance** — MButton drag runs on a 10ms timer; wrapper overhead adds latency
2. **Minimal dependencies** — No external files to manage or version
3. **Transparency** — The actual Win32/COM calls are visible in the code

The tradeoff is maintainability: vtable offsets are magic numbers. Mitigate by documenting offsets inline (see "UIA Vtable Offsets" section).

### Why the Scroll Method Hierarchy

Different apps expose scrolling differently:

| App Type               | Best Method | Why                                                    |
| ---------------------- | ----------- | ------------------------------------------------------ |
| SysListView32          | LVM         | Pixel-level precision, dual-axis, no UIA jitter        |
| Explorer (DirectUI)    | UIA         | DirectUI layer ignores WM_MOUSEWHEEL                   |
| Electron apps (VSCode) | WHEEL       | Sub-120 delta for smooth scrolling                     |
| Classic Win32          | WHEEL_CTRL  | Window-level messages don't reach controls             |
| Tree views             | VSCROLL     | Line-by-line, most compatible                          |

The fallback chain (LVM → UIA → WHEEL → WHEEL_CTRL → VSCROLL) probes each method and uses the first that works, determined empirically per control at runtime.

### Why Window Spawning Has Intent Detection

Moving ALL activated windows to cursor's monitor would be wrong — activating an existing window (Alt+Tab, taskbar click) shouldn't relocate it. The intent detection system distinguishes:

- **New windows** (shell hook CREATED) — Always move
- **Re-launched single-instance apps** (brief-process heuristic) — Move
- **Z-order fallback activations** (close window → next window activates) — Don't move

## Codebase Patterns

### Module Init Contract

The parent auto-execute section is responsible for:
- Calling module init functions (`WS_Init()`, `TerminalInit()`)
- Registering `OnExit()` handlers (`MB_Cleanup`, `WS_Cleanup`, `G_UIACleanup`)

Modules can lazy-init inside hotkeys (like `G_UIA` in mbutton-drag.ahk) but must register their own `OnExit()` at that point.

### Timer/Hotkey Race Conditions

AHK v1.1 pseudo-threads allow hotkey threads to interrupt timer threads at any command boundary. When a timer uses COM pointers or shared state that a hotkey cleans up, use `Critical` in **both**:

```autohotkey
MyTimer:
  Critical
  If (!sharedPointer)
    Return
  DllCall(NumGet(NumGet(sharedPointer+0)+N*A_PtrSize), ...)
Return

$Key Up::
  Critical
  SetTimer, MyTimer, Off
  ObjRelease(sharedPointer)
  sharedPointer := 0
Return
```

### COM Resource Cleanup (Two Patterns)

**Temporary pointers** (function-scoped, one-shot use): Release in `Finally` block.

```autohotkey
Try {
  result.name := _GetUIAProp(_el, 30005)
} Finally {
  ObjRelease(_el)
}
```

**Session pointers** (persist across timer ticks, like `MB_ScrollPattern`/`MB_Element`): Release explicitly on state transitions (MButton Up, fallback, cleanup). These rely on:
1. `Critical` preventing mid-DllCall interruption
2. Explicit release in the Up hotkey and fallback paths
3. `OnExit` handler (`MB_Cleanup`) as safety net

### Preserve Working Code (CRITICAL)

When asked to **move**, **extract**, or **refactor** code:

- **Source of truth is the actual code in the file**, not plans, design docs, or memory notes
- Copy the existing implementation verbatim — do not rewrite the approach
- If you see an improvement opportunity, mention it separately and ask first

## Constants and Magic Values

### UIA Vtable Offsets (Used in Code)

UI Automation COM interfaces are called via `DllCall` to vtable offsets. Source: [Descolada UIA-v2](https://github.com/Descolada/UIA-v2)

**IUIAutomation** — root object from `ComObjCreate(CLSID, IID)`:

| Offset | Method                     | Used In            |
| ------ | -------------------------- | ------------------ |
| 6      | `ElementFromHandle(hwnd)`  | mbutton-drag       |
| 7      | `ElementFromPoint(x, y)`   | extended-spy       |

**IUIAutomationElement**:

| Offset | Method                     | Used In            |
| ------ | -------------------------- | ------------------ |
| 10     | `GetCurrentPropertyValue`  | extended-spy       |
| 16     | `GetCurrentPattern`        | mbutton-drag       |

**IScrollPattern** — returned by `GetCurrentPattern(10004)`:

| Offset | Method                              | Used In       |
| ------ | ----------------------------------- | ------------- |
| 4      | `SetScrollPercent(hPct, vPct)`      | smooth scroll |
| 5      | `get_CurrentHorizontalScrollPercent`| dual-axis     |
| 6      | `get_CurrentVerticalScrollPercent`  | native probe  |
| 7      | `get_CurrentHorizontalViewSize`     | dual-axis     |
| 8      | `get_CurrentVerticalViewSize`       | normalization |

**Property IDs** — first arg to GetCurrentPropertyValue:

| ID    | Name                 | Returns          |
| ----- | -------------------- | ---------------- |
| 30002 | ProcessId            | VT_I4 (int)      |
| 30005 | Name                 | VT_BSTR          |
| 30012 | ClassName            | VT_BSTR          |

## Key Helper Functions

| Function                  | File                    | Purpose                                              |
| ------------------------- | ----------------------- | ---------------------------------------------------- |
| `UserRun(exe, args*)`     | `AutoHotkey.ahk`        | Process execution with elevation and quoting         |
| `GetExplorerPath()`       | `AutoHotkey.ahk`        | Active Explorer window's filesystem path (tab-aware) |
| `GetCursorMonitor()`      | `AutoHotkey.ahk`        | Returns 1-based monitor index for cursor             |
| `IsProcessElevated(pid)`  | `AutoHotkey.ahk`        | Checks admin privileges via token                    |
| `FindInPath(exe)`         | `AutoHotkey.ahk`        | Resolves exe name to full PATH entry                 |
| `HasVal(arr, val)`        | `AutoHotkey.ahk`        | Check if array contains value (partial match)        |
| `GetScrollPos(hwnd)`      | `mbutton-drag.ahk`      | Win32 vertical scroll position                       |
| `ScrollCurve(dist)`       | `mbutton-drag.ahk`      | Power curve: `dist^0.8` up to 100px, slower beyond   |
| `OpenTerminal(opts)`      | `terminal-anywhere.ahk` | Open WT with elevation options                       |

## Conventions

- **Naming**: PascalCase functions, `MB_` prefix for MButton globals, `WS` object for window spawning state, `G_` for persistent globals
- **Debug flags**: `MB_Debug` (tooltips). File-based logging uses `DebugLogEvents`/`DebugLogPath` globals (defined in parent).
- **Process launching**: Always use `UserRun()` for consistent elevation/env handling

---

## Explorer Smooth Scroll (`mbutton-drag.ahk`)

The MButton scroll system intercepts middle-click-drag and converts it to smooth scrolling. It uses a **10ms timer** (`MBDragTimer`) for continuous scrolling while the button is held, with a power-curve acceleration model (`dist^0.8` up to 100px, `+ (excess)^0.6` beyond).

### Scroll Methods

| Method         | Mechanism                                        | Granularity  | Best For                       |
| -------------- | ------------------------------------------------ | ------------ | ------------------------------ |
| **LVM**        | `LVM_SCROLL` (0x1014) pixel-level SendMessage    | Pixel        | SysListView32 controls         |
| **UIA**        | `SetScrollPercent` via IUIAutomationScrollPattern| Fractional % | Explorer file lists, mmc.exe   |
| **WHEEL**      | `WM_MOUSEWHEEL` sub-120 delta to window          | Sub-notch    | Electron apps (VS Code)        |
| **WHEEL_CTRL** | `WM_MOUSEWHEEL` to control (with fallback)       | ~1 line      | SystemInformer                 |
| **VSCROLL**    | `WM_VSCROLL` line-by-line, dynamic timer         | 1 line       | Tree views, universal fallback |

### Automatic Fallback Chain

Methods are **auto-detected at runtime** — no hardcoded per-app flags:

```
MButton Down
    ├── TreeView control? ──────────────────→ VSCROLL (direct)
    ├── SysListView32 control? ─────────────→ LVM (pixel-level)
    └── Try UIA setup
         ├── Element + ScrollPattern found → UIA
         │    └── Verify: NoScroll sentinel (-1)? → fall to WHEEL
         └── Setup failed ──────────────────→ WHEEL
              └── First scroll: GetScrollPos
                   ├── No movement → WHEEL_CTRL
                   │    └── Jumped >40 units? → VSCROLL
                   └── Movement detected → stay WHEEL
```

### Dual-Axis Scrolling

All methods support horizontal scrolling (X-axis drag). Method-specific handling:

- **LVM**: `LVM_SCROLL(dx, dy)` — single message for both axes, 3x horizontal boost for row-quantized
- **UIA**: `SetScrollPercent(hPct, vPct)` — single call, 1.5x horizontal boost
- **WHEEL/WHEEL_CTRL**: `WM_MOUSEWHEEL` (vertical) + `WM_MOUSEHWHEEL` (horizontal)
- **VSCROLL**: `WM_VSCROLL` + `WM_MOUSEHWHEEL` (5x horizontal boost)

### LVM Scrolling (SysListView32)

SysListView32 controls use `LVM_SCROLL` (0x1014) for pixel-level precision instead of UIA. UIA causes jitter on short lists because percentage-based scrolling rounds to discrete row positions.

**Row-quantization detection**: First vertical scroll probes whether the ListView supports pixel-level scrolling or snaps to row boundaries:

- **Pixel-level** (e.g., TortoiseGit): `scrollDelta ≈ sentPixels` (ratio 0.3-1.5x) — dual-axis allowed freely, high-confidence
- **Row-quantized** (e.g., FullEventLogView): Delta jumps by row height — requires EMA axis restriction, high-confidence
- **Uncertain** (delta=0 at boundary): Assumes pixel-level but allows slow-tick upgrade

High-confidence detections (`MB_LVM_DetectConfident := 1`) prevent the slow-tick heuristic from overriding the initial detection.

**EMA axis intent**: For row-quantized views, simultaneous vertical+horizontal scrolling causes UI stutter. An exponential moving average (α=0.2) tracks movement intensity per axis. When one axis dominates (>1.5x the other), the weaker axis is suppressed. This lets users scroll diagonally when intended, but locks to one axis during deliberate vertical/horizontal drags.

**Boundary detection**: Tracks when vertical scrolling hits min/max to avoid sending futile scroll messages. Clears when direction reverses.

**Timing-based fallback**: If a scroll tick takes >50ms (virtualized ListView rendering lag), upgrades to row-quantized mode for axis restriction.

### Native Scroll Probe

A movement-gated probe determines whether the app handles MButton drag-scroll natively using three signals:

1. **Cursor change** (HCURSOR handle + `A_Cursor = "Unknown"`): Custom autoscroll icons (Chrome, Firefox)
2. **Win32 scroll position** (`GetScrollPos`): Classic Win32 apps with native scrollbars
3. **UIA scroll percent**: Modern apps using custom renderers

The probe runs until **8px movement**. If any signal fires → native scroll detected, custom scroll disabled.

### Deferred MButton Down (Explorer)

For Explorer (`CabinetWClass`), MButton Down is **deferred** to prevent click actions before scroll intent is determined. If no scroll occurs, `{Blind}{MButton}` is synthesized on release.

---

## Window Spawning (`window-spawning.ahk`)

Moves newly created windows to the cursor's monitor using shell hooks and WinEvent hooks.

### Architecture

- **Shell hook** (`RegisterShellHookWindow`): `HSHELL_WINDOWCREATED`, `HSHELL_WINDOWACTIVATED`, `HSHELL_WINDOWDESTROYED`
- **WinEvent hooks** (`SetWinEventHook`): `EVENT_OBJECT_SHOW`, `EVENT_OBJECT_UNCLOAKED`, `EVENT_OBJECT_CREATE`
- **State**: Single `WS := {}` object. Every function declares `global WS`.

### Window Creation Paths

| Path                    | Timing             | Mechanism                                             |
| ----------------------- | ------------------ | ----------------------------------------------------- |
| Win32 instant           | Shell hook fires   | Window ready → move immediately                       |
| UWP event-driven        | ~62ms              | Shell hook → pending → SHOW/UNCLOAK → move            |
| CREATE pre-pipeline     | 55-77ms before     | CREATE → hide (opacity 0) → shell hook → move → reveal|

### Intent Detection

**Default-skip**: Activated windows are NOT moved unless positive intent is detected.

**Tier 1 — Brief-process detection**: Single-instance Win32 apps spawn a brief process (100-500ms) that exits after signaling the existing instance. We track window creation → destruction → activation to detect re-launches.

**Tier 2 — Overlay-launch detection**: UWP apps don't create a new process on re-launch. If Start menu overlay was recently visible and a different window activates → move.

**Z-order fallback protection**: When foreground is destroyed, skip intent detection for 200ms (prevents moving the next z-order window).

### Zero-Flash Opacity

At `EVENT_OBJECT_CREATE`, hide windows using `WS_EX_LAYERED` + alpha 0. After move, restore opacity.

**`WS.Hidden[hwnd]` state machine** (important for understanding the pipeline):
- **Absent**: Window not tracked (normal state)
- **Boolean** (`true`/`false`): Opacity-hidden; value = `hadLayered` (whether window already had `WS_EX_LAYERED` before we hid it)
- **`-1` sentinel**: Window processed/moved — prevents duplicate CREATE events from re-hiding

### Key AHK v1.1 Details

- **32-bit masking**: `idObject & 0xFFFFFFFF` — WinEventProc params are 32-bit but AHK reads 64-bit on x64
- **Numeric coercion**: `hwnd + 0` — ensures consistent object key type

---

## Debug Logging

**Enable**: Set `DebugLogEvents := 1` in AutoHotkey.ahk (line ~23). Log file: `%TEMP%\AHK_Debug.log` (cleared on reload).

**Workflow**: When testing changes, enable logging and ask user to "try now" — then grep the log for events rather than asking "how is it now?". This applies to all manual testing.

**Log prefixes** (grep for these):
| Feature        | Prefix        | Coverage                                    |
| -------------- | ------------- | ------------------------------------------- |
| MButton drag   | `MBDrag`      | Session start/end, method detection, fallbacks, LVM mode, boundaries |
| Scroll accel   | `ScrollAccel` | Velocity calc, direction changes, filtered events |
| Window spawn   | `WS`          | Shell hooks, intent detection, opacity hide/reveal, move events |

**Adding logging**: If a feature lacks logging (e.g., terminal-anywhere), add it when testing that functionality. Format: `timestamp | PREFIX | EVENT | key=value pairs`.

## Testing

Manual verification with logging enabled:

1. **MButton drag**: Test in Explorer, VS Code, SysListView32 apps — grep `MBDrag` for method detection, fallbacks, axis values
2. **Scroll accel**: Test rapid scrolling — grep `ScrollAccel` for velocity calc, direction changes
3. **Window spawning**: Open new windows — grep `WS` for intent detection, move events
4. **Terminal hotkeys**: Test `F10` variants — add logging if debugging issues

