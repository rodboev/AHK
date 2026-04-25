# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Language Requirement

**AutoHotkey v1.1.14+** — This codebase uses AHK v1.1 syntax exclusively, with `#Requires AutoHotkey v1.1.14+` enforced. Do NOT use v2.0 syntax. Key differences:

- Commands use `Command, Param1, Param2` syntax (not function calls)
- Variables use `%var%` for dereferencing in commands
- Legacy `#IfWinActive` directives (not `#HotIf`)
- `Try/Finally` blocks are available (added in v1.1.14)

## Architecture

`AutoHotkey.ahk` is the parent entrypoint. It `#Include`s four module files at the bottom:

| File                    | Purpose                                                            |
| ----------------------- | ------------------------------------------------------------------ |
| `AutoHotkey.ahk`        | Parent: config directives, helpers, bindings, misc hotkeys         |
| `terminal-anywhere.ahk` | Windows Terminal from anywhere (`F10` variants) — user/admin/SYSTEM|
| `extended-spy.ahk`      | Extended Window Spy (`#w`) — tooltip/dialog with window/control info |
| `mbutton-scroll.ahk`    | MButton smooth scroll (hotkeys, timer, scroll methods)             |
| `window-spawning.ahk`   | Shell hook window spawning (WS_Init, hooks, move logic, Alt+Tab)   |

The `community-scripts/` directory contains reference libraries (loosely coupled, mostly for inspiration).

### Key Regions in AutoHotkey.ahk

- **Auto-execute section**: Directives, `G_UIA` init, `OnExit` handlers, `WS_Init()`, `TerminalInit()`
- **Bindings / remaps**: Script control, editor-specific, global hotkeys, scroll accel
- **Process management / privilege escalation**: `^+\``, `#+e`, `#c`, `^+=` hotkeys
- **Helper functions**: `GetExePath`, `GetMonitor`, `HasVal`, `FindInPath`, etc.
- **Safe run / elevation**: `UserRun()` + `IsProcessElevated()`
- **Module includes**: `#Include` directives at EOF for the four module files

### Core Features

1. **Explorer Smooth Scroll** (`MButton + drag`) — 4-method system: UIA, WHEEL, WHEEL_CTRL, VSCROLL — in `mbutton-scroll.ahk`
2. **Window Spawning** — Shell hook + WinEvent hooks move new windows to cursor's monitor — in `window-spawning.ahk`
3. **Extended Window Spy** (`Win+W`) — Persistent tooltip with window/control info — in `extended-spy.ahk`
4. **Terminal/Elevation** (`F10`, `Shift+F10`, `Ctrl+Alt+Shift+F10`, `Ctrl+Shift+Plus`) — Context-aware terminal launching with admin elevation and SYSTEM via ti.exe — in `terminal-anywhere.ahk` (F10 variants) and `AutoHotkey.ahk` (`Ctrl+Shift+Plus`)

## Design Rationale

### Why Raw COM Vtable Calls (No Wrapper Library)

This codebase calls COM interfaces via direct `DllCall` to vtable offsets rather than using wrapper libraries like Descolada's UIA-v2:

1. **Performance** — MButton scroll runs on a 10ms timer; wrapper overhead adds latency
2. **Minimal dependencies** — No external files to manage or version
3. **Transparency** — The actual Win32/COM calls are visible in the code, not hidden behind abstractions

The tradeoff is maintainability: vtable offsets are magic numbers. Mitigate by documenting offsets inline (see "UIA Vtable Offsets" section below) with links to the source.

### Why UIA for Explorer Scrolling

Windows Explorer uses DirectUI (an internal Microsoft UI framework), not standard Win32 controls. This means:
- `WM_MOUSEWHEEL` sent to the window doesn't reach the list view
- `WM_VSCROLL` works but only in line increments (jerky)
- `GetScrollPos`/`SetScrollPos` don't work (no Win32 scrollbar)

UIA's `IUIAutomationScrollPattern::SetScrollPercent` talks directly to the DirectUI layer, enabling fractional-percent smooth scrolling.

### Why the Scroll Method Fallback Chain

Different apps expose scrolling differently:

| App Type | UIA ScrollPattern | WM_MOUSEWHEEL | WM_VSCROLL |
|----------|-------------------|---------------|------------|
| Explorer (DirectUI) | Yes | No | Jerky |
| VS Code (Electron) | No | Yes (sub-120 delta) | No |
| Classic Win32 | Sometimes | Usually | Yes |
| Tree views | No | No | Yes |

The fallback chain (UIA → WHEEL → WHEEL_CTRL → VSCROLL) probes each method and uses the first that works, determined empirically per control at runtime.

### Why Window Spawning Has Intent Detection

Moving ALL activated windows to cursor's monitor would be wrong — activating an existing window (Alt+Tab, taskbar click) shouldn't relocate it. The intent detection system distinguishes:

- **New windows** (shell hook CREATED) — Always move
- **Re-launched single-instance apps** (brief-process heuristic) — Move (user explicitly launched)
- **Overlay dismissal activations** (Start menu → app) — Move (user explicitly launched)
- **Z-order fallback activations** (close window → next window activates) — Don't move (system behavior, not user intent)

## Running & Debugging

```powershell
# Launch script
start "" "C:\Program Files\AutoHotkey\AutoHotkey.exe" AutoHotkey.ahk

# Or double-click AutoHotkey.ahk in Explorer
```

**Debug tools**: Use tray icon menu (`ListLines`, `Pause`, `Reload`). Insert `ToolTip`, `MsgBox`, or `OutputDebug` for quick inspection.

**Reload on save**: `Ctrl+S` in the script editor auto-reloads via hotkey.

## Code Patterns

### Timer-based Acceleration

Smooth animations use `SetTimer` with dynamic intervals (10-150ms). Follow this pattern for scroll/animation features:

```autohotkey
SetTimer, MyTimer, %interval%
; ...
MyTimer:
  ; Calculate and apply incremental changes
Return
```

### Timer/Hotkey Race Conditions (CRITICAL)

AHK v1.1 pseudo-threads allow hotkey threads to interrupt timer threads at any command boundary. When a timer uses COM pointers or shared state that a hotkey cleans up, use `Critical` in **both** the timer and the cleanup hotkey:

```autohotkey
; ✅ CORRECT - Timer is uninterruptible, cleanup is atomic
MyTimer:
  Critical
  If (!sharedPointer)  ; null guard (belt-and-suspenders)
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

**Why both:** `Critical` in the timer prevents the hotkey from interrupting mid-DllCall. `Critical` in the hotkey prevents a queued timer tick from firing between `SetTimer, Off` and the `ObjRelease`. The null guard catches the edge case of a timer tick already queued in the message loop.

### COM Resource Cleanup with Try/Finally

When acquiring COM pointers (UIA elements, ScrollPatterns), always release in a `Finally` block to prevent leaks if property reads throw (e.g., stale element from closed window):

```autohotkey
; ✅ CORRECT - Guaranteed cleanup even on access violation
Try {
  result.name := _GetUIAProp(_el, 30005)
  result.type := _GetUIAProp(_el, 30004)
} Finally {
  ObjRelease(_el)
}

; ❌ RISKY - Exception skips ObjRelease, leaking COM reference
Try {
  result.name := _GetUIAProp(_el, 30005)
  result.type := _GetUIAProp(_el, 30004)
}
ObjRelease(_el)
```

**Why:** `_el` may point to a destroyed UI element (e.g., mouse moved over a closing window). Dereferencing a stale vtable pointer causes an access violation, which AHK catches as a thrown exception — skipping any code after the `Try` block.

### UserRun Helper

Use `UserRun(Executable, Args*)` for all process execution — handles elevation, env var expansion, and argument quoting.

**Key behaviors**:
- All arguments are unconditionally quoted (single-quoted in PowerShell, double-quoted in direct paths)
- Shell operators (`&&`, `|`) not interpreted — use `UserRun("cmd", "/c", "cmd1 && cmd2")` to chain
- For elevation, uses AHK's `*RunAs` verb, NOT PowerShell `Start-Process -Verb RunAs`

**Why not PowerShell elevation**: `Start-Process -ArgumentList` joins arrays into a single space-separated string (by design). The target process parses via `CommandLineToArgvW`, not PowerShell rules. This causes quoting bugs. AHK's `*RunAs` passes the command string directly to `ShellExecuteEx`, avoiding this.

**SYSTEM PATH resolution**: `ti.exe` runs as `NT AUTHORITY\SYSTEM` whose PATH lacks user-installed programs. Resolve exe names to full paths via `FindInPath()` before passing to `ti.exe`.

### Message Synthesis

Scroll methods use `PostMessage`/`SendMessage` for WM_MOUSEWHEEL (0x20A), WM_VSCROLL (0x115). UIA uses COM `SetScrollPercent`.

### COM/UIA Pointer Dereferencing (CRITICAL)

When calling COM vtable methods via `DllCall`, **always use `+0` suffix** on pointer variables in the inner `NumGet()`:

```autohotkey
; ✅ CORRECT - Forces numeric evaluation before dereferencing
DllCall(NumGet(NumGet(MB_ScrollPattern+0)+8*A_PtrSize), "Ptr", MB_ScrollPattern, ...)

; ❌ BROKEN - AHK v1.1 may misinterpret the variable
DllCall(NumGet(NumGet(MB_ScrollPattern)+8*A_PtrSize), "Ptr", MB_ScrollPattern, ...)
```

**Why:** In AHK v1.1, `NumGet(var)` can behave differently than `NumGet(var+0)`. The `+0` forces AHK to evaluate `var` as a number first, ensuring proper pointer arithmetic.

**Also avoid:** Capturing return values from COM vtable DllCalls:

```autohotkey
; ❌ BROKEN - Interferes with output parameters
hr := DllCall(NumGet(NumGet(ptr+0)+N*A_PtrSize), ..., "Ptr*", outVar)

; ✅ CORRECT - Just call, don't capture HRESULT
DllCall(NumGet(NumGet(ptr+0)+N*A_PtrSize), ..., "Ptr*", outVar)
```

### UIA ElementFromHandle vs ElementFromPoint (CRITICAL)

`ElementFromHandle` (vtable 6) and `ElementFromPoint` (vtable 7) return **different UIA elements** for the same window:

- **`ElementFromHandle(hwnd)`**: Returns the UIA element associated with the window handle — typically the top-level XAML host. Use this as the root for `FindFirst`/`FindAll` searches.
- **`ElementFromPoint(x, y)`**: Returns the **deepest** hit-testable leaf element at screen coordinates. Walking up the tree from this leaf traverses the visual tree, which may NOT include host-level elements. Use for Extended Spy (identifying what's under cursor), not for pattern searches.

### FileDelete/FileAppend with Object Properties

AHK v1.1 commands take plain string parameters. Forced expression syntax (`% WS.Property`) is unreliable for `FileDelete`/`FileAppend`. Always dereference to a local variable first:

```autohotkey
; ❌ BROKEN — unreliable with object property access
FileDelete, % WS.LogFile

; ✅ CORRECT — local variable + traditional dereferencing
_logFile := WS.LogFile
FileDelete, %_logFile%
```

### Auto-Execute Section (CRITICAL)

In AHK v1.1, the auto-execute section runs from line 1 until the first hotkey label. Code placed between hotkey subroutines is **unreachable dead code**. Global config must be in the auto-execute section.

**#Include placement matters**: Since `#Include` directives are at the **bottom** of AutoHotkey.ahk (after all hotkeys), any auto-execute code at the top of included files is dead code. Only functions and hotkey labels in included files are reachable. For this reason:
- `OnExit()` handlers for startup-critical cleanup must be registered in AutoHotkey.ahk's auto-execute section
- Module files should only contain functions and hotkey labels, not top-level executable code
- Lazy initialization (like `G_UIA` in mbutton-scroll.ahk) can register `OnExit()` on first use inside a hotkey

### Remote Session Guard Pattern

The auto-execute section uses a dual-purpose `#If` pattern:

```autohotkey
#If IsRemoteSession()
  If !IsRemoteSession() {
    ; ... initialization code ...
  }
  Return
#If
```

**What this does**:
1. **`#If IsRemoteSession()`** — Context directive that disables all subsequent hotkeys when inside RDP/Hyper-V/VMware (prevents conflicts with host machine hotkeys)
2. **`If !IsRemoteSession()`** — Runtime guard that skips initialization when in a remote session (the auto-execute code runs regardless of `#If` context)
3. **`#If`** (bare) — Clears the context so hotkeys after this point are always active

**Why both**: The `#If` directive only affects hotkey activation, not auto-execute flow. The inner `If` prevents initializing hooks and timers that would be useless (and potentially problematic) in remote sessions.

### Configuration Arrays

Control exclusions and native scroll detection:

```autohotkey
MB_ExcludedControls := ["ToolbarWindow", "Edit"]          ; Skip these controls
; App exclusion is automatic — native MButton drag-scroll is detected at runtime
; via HCURSOR handle change (custom cursors only), GetScrollPos, and UIA GetVerticalScrollPercent
```

### Preserve Working Code (CRITICAL)

When asked to **move**, **extract**, or **refactor** code:

- **Source of truth is the actual code in the file**, not plans, design docs, or memory notes
- Copy the existing implementation verbatim — do not rewrite the approach
- If you see an improvement opportunity, mention it separately and ask first
- Never silently replace one working API/pattern with a different one
- "Move to a new file" means copy+delete, not redesign

## Constants and Magic Values

### Subsystem Separation Principle

Windows exposes functionality through multiple independent COM/Win32 subsystems. **Document constants alongside their owning subsystem, not in a single global block.** Mixing unrelated APIs (e.g., UI Automation GUIDs next to Shell IShellBrowser) creates false associations and obscures provenance.

| Subsystem | Owner File | Scope |
|-----------|------------|-------|
| UI Automation | `mbutton-scroll.ahk` | UIA COM object, pattern IDs, property IDs, vtable offsets |
| Shell Automation | `AutoHotkey.ahk` (near GetExplorerPath) | IShellBrowser, Shell.Application |
| Window Spawning | `window-spawning.ahk` | WinEvent IDs, window styles, shell hook constants |
| Win32 General | Inline at usage site | One-off constants (WM_SYSCOMMAND, token flags, etc.) |

### Documentation Requirements

When introducing a GUID, hex constant, or numeric ID:

1. **Name it** — Use the official SDK constant name (e.g., `WS_EX_LAYERED`, not just `0x80000`). This enables grep verification against Microsoft docs.

2. **Source it** — Note the SDK header file (e.g., `UIAutomationClient.h`, `ShObjIdl.h`, `WinUser.h`).

3. **Scope it** — Place documentation near the code that owns the concept, not at file top or in a distant reference file.

4. **Link it** — For complex subsystems (UIA, Shell), include the MS Learn documentation URL.

### Format for COM Subsystems

Use a box header when initializing a COM object or introducing a subsystem:

```autohotkey
; ╔══════════════════════════════════════════════════════════════════════════╗
; ║  [Subsystem Name] — [One-line purpose]                                   ║
; ║  Docs: [MS Learn URL]                                                    ║
; ╚══════════════════════════════════════════════════════════════════════════╝
; COM Class/Interface (from [Header].h)
;   CLSID_Name = {guid}
;   IID_Name   = {guid}
```

### Format for Inline Constants

For one-off Win32 values, inline comment with SDK name suffices:

```autohotkey
; ✅ GOOD
DllCall("SetWindowLong", ..., "Ptr", style | 0x80000)  ; WS_EX_LAYERED
SendMessage, 0x112, 0xF170, 2,, Program Manager  ; WM_SYSCOMMAND, SC_MONITORPOWER

; ❌ BAD — No SDK name, unverifiable
DllCall("SetWindowLong", ..., "Ptr", style | 0x80000)
```

### Anti-Patterns

- **Mixed subsystems**: Don't put UI Automation and Shell constants in the same documentation block
- **Orphaned constants**: Don't define constants at file top if they're only used in one function — document at usage site
- **Vtable-only docs**: If documenting vtable offsets, also document the interface they belong to (see "UIA Vtable Offsets" section)
- **Magic without provenance**: Never introduce a GUID or hex value without noting which Windows API it comes from

### UIA Vtable Offsets (Used in Code)

UI Automation COM interfaces are called via `DllCall` to vtable offsets. The offset number is the method's position in the interface's vtable (after IUnknown's 3 methods).

**How to read**: `DllCall(NumGet(NumGet(ptr+0)+OFFSET*A_PtrSize), "Ptr", ptr, ...params...)`

Source: [Descolada UIA-v2](https://github.com/Descolada/UIA-v2)

**IUIAutomation** — root object from `ComObjCreate(CLSID, IID)`:

| Offset | Method | Used In |
|--------|--------|---------|
| 6 | `ElementFromHandle(hwnd)` → element | mbutton-scroll, GetUIAProcessId |
| 7 | `ElementFromPoint(x, y)` → element | extended-spy |

**IUIAutomationElement** — returned by ElementFrom*:

| Offset | Method | Used In |
|--------|--------|---------|
| 10 | `GetCurrentPropertyValue(propId, &variant)` | extended-spy, GetUIAProcessId |
| 16 | `GetCurrentPattern(patternId)` → pattern | mbutton-scroll |

**IScrollPattern** — returned by `GetCurrentPattern(10004)`:

| Offset | Method | Used In |
|--------|--------|---------|
| 4 | `SetScrollPercent(hPct, vPct)` | mbutton-scroll (smooth scroll) |
| 6 | `get_CurrentVerticalScrollPercent(double*)` | native scroll probe |
| 8 | `get_CurrentVerticalViewSize(double*)` | scroll normalization |

**Property IDs** — first arg to GetCurrentPropertyValue:

| ID | Name | Returns |
|----|------|---------|
| 30002 | ProcessId | VT_I4 (int) |
| 30004 | LocalizedControlType | VT_BSTR (string) |
| 30005 | Name | VT_BSTR |
| 30011 | AutomationId | VT_BSTR |
| 30012 | ClassName | VT_BSTR |

## Testing

No automated tests. Manual verification required:

1. **MButton scroll**: Test in Windows Explorer (file lists + nav tree) and VS Code
2. **Window spawning**: Open a new window — should appear on cursor's monitor
3. **Window Spy**: Press `Win+W`, hover different windows, click tooltip to copy
4. **Terminal hotkeys**: Test `F10` from Explorer, Desktop, and applications
5. **TI elevation**: `Ctrl+Alt+Shift+F10` → Terminal opens as SYSTEM
6. **TI relaunch**: Focus any app → `Ctrl+Shift+Plus` → relaunches as SYSTEM
7. **Alt+Tab**: Press `Alt+Tab` — switcher should appear on cursor's monitor

## Key Helper Functions

| Function                              | File                    | Purpose                                                                            |
| ------------------------------------- | ----------------------- | ---------------------------------------------------------------------------------- |
| `GetExePath(winTitle)`                | `AutoHotkey.ahk`        | Returns `{path, dir}` for process                                                  |
| `GetMonitor(winTitle)`                | `AutoHotkey.ahk`        | Returns 1-based monitor number                                                     |
| `GetCursorMonitor()`                  | `AutoHotkey.ahk`        | Returns 1-based monitor index for cursor                                           |
| `IsProcessElevated(pid)`              | `AutoHotkey.ahk`        | Checks admin privileges via token                                                  |
| `UserRun(exe, args*)`                 | `AutoHotkey.ahk`        | Smart process execution with elevation and quoting                                 |
| `HasVal(arr, val)`                    | `AutoHotkey.ahk`        | Check if array contains value (partial match)                                      |
| `IsRemoteSession()`                   | `AutoHotkey.ahk`        | Returns true if inside RDP/Hyper-V/VMware (checks window class)                    |
| `FindInPath(exe)`                     | `AutoHotkey.ahk`        | Resolves exe name (e.g., `"wt.exe"`) to full PATH entry, or `""` if not found      |
| `GetExplorerPath()`                   | `AutoHotkey.ahk`        | Active Explorer window's filesystem path (tab-aware); `""` if not filesystem       |
| `ProcessExistsByCommandLine(cmdLine)` | `AutoHotkey.ahk`        | Find PID by command line match via WMI                                             |
| `GetUIAProcessId(hwnd)`               | `AutoHotkey.ahk`        | UIA content process PID (resolves UWP/Electron host)                               |
| `GetUIAElementInfo(x, y)`             | `extended-spy.ahk`      | UIA element properties at screen coordinates                                       |
| `GetScrollPos(hwnd)`                  | `mbutton-scroll.ahk`    | Win32 vertical scroll position                                                     |
| `HasWin32Scrollbar(hwnd)`             | `mbutton-scroll.ahk`    | Checks if Win32 scrollbar exists                                                   |
| `WrapList(text, delim, maxLen)`       | `extended-spy.ahk`      | Wraps delimited text preserving items                                              |
| `CleanWindowText(text)`               | `extended-spy.ahk`      | Removes non-ASCII, dedupes long text                                               |
| `FilterLongItems(text, maxLen)`       | `extended-spy.ahk`      | Removes items >maxLen from list                                                    |
| `SortList(text)`                      | `extended-spy.ahk`      | Sorts comma-separated items alphabetically                                         |
| `OpenTerminal(opts)`                  | `terminal-anywhere.ahk` | Open WT with elevation options                                                     |
| `GetTerminalDir()`                    | `terminal-anywhere.ahk` | Working directory from active window context                                       |

## Conventions

- **Naming**: PascalCase functions, `MB_` prefix for MButton globals, `WS` object for window spawning state, `WS_` prefix for window spawning functions, `G_` for persistent globals
- **Sections**: Use ASCII box dividers for major sections
- **Dependencies**: Avoid external non-AHK dependencies; prefer Win32/UIA in-script
- **Process launching**: Always use `UserRun()` for consistent elevation/env handling
- **Debug flags**: `MB_Debug` for MButton scroll, `WS.Debug` for window spawning
- **PRs**: Reference affected hotkeys/timers, include manual test steps

---

## Explorer Smooth Scroll (`mbutton-scroll.ahk`)

The MButton scroll system intercepts middle-click-drag and converts it to smooth scrolling. It uses a **10ms timer** (`MBScrollTimer`) for continuous scrolling while the button is held, with a power-curve acceleration model (`absEffective^0.8` up to 100px, `+ (excess)^0.6` beyond).

### Scroll Methods

| Method         | Mechanism                                             | Granularity  | Best For                       |
| -------------- | ----------------------------------------------------- | ------------ | ------------------------------ |
| **UIA**        | `SetScrollPercent` via IUIAutomationScrollPattern     | Fractional % | Explorer file lists, mmc.exe   |
| **WHEEL**      | `WM_MOUSEWHEEL` sub-120 delta to window               | Sub-notch    | Electron apps (VS Code)        |
| **WHEEL_CTRL** | `WM_MOUSEWHEEL` to control (with fallback detection)  | 1 line\*     | SystemInformer                 |
| **VSCROLL**    | `WM_VSCROLL` line-by-line, dynamic timer (300ms→20ms) | 1 line       | Tree views, universal fallback |

### Automatic Fallback Chain

Methods are **auto-detected at runtime** — no hardcoded per-app flags. The chain probes each method starting from highest quality and cascades on failure:

```
MButton Down
    ├── TreeView control? ──────────────────→ VSCROLL (direct)
    └── Try UIA setup
         ├── Element + ScrollPattern found → UIA
         │    └── Two-tick verification:
         │         Tick 1: capture GetScrollPos before
         │         Tick 2: check NoScroll sentinel OR Win32 scrollbar didn't move
         │         → fail → WHEEL
         └── Setup failed ──────────────────→ WHEEL
              └── First scroll: GetScrollPos before/after
                   ├── No movement → WHEEL_CTRL
                   │    └── First scroll: GetScrollPos → jumped >40 units → VSCROLL
                   └── Movement detected → stay WHEEL
```

Each fallback resets `MB_FallbackChecked := 0`, enabling the next method's first-scroll check. Worst-case cascade latency: ~30ms (happens once per drag session).

### UIA Two-Tick Verification

The UIA fallback uses a two-tick approach to avoid Sleep() in the 10ms timer:

- **Tick 1** (`MB_FallbackChecked = 0`): Captures `GetScrollPos` of control, sends UIA scroll, sets `MB_FallbackChecked := -1`
- **Tick 2** (`MB_FallbackChecked = -1`): Checks if UIA reports NoScroll sentinel (-1), OR cross-validates that Win32 scrollbar actually moved via `HasWin32Scrollbar()` + `GetScrollPos` comparison. Falls to WHEEL on failure.

This catches apps like SystemInformer that expose a ScrollPattern but ignore `SetScrollPercent`.

### Deferred MButton Down (Explorer)

For Explorer (`CabinetWClass`), MButton Down is **deferred** — not passed through to the app on press. This prevents Explorer from triggering click actions (e.g., opening a new tab when middle-clicking a navbar item) or entering selection mode (which blocks UIA scrolling) before the user's intent (scroll vs click) is determined.

- **If scroll occurs** (drag ≥8px): MButton Down is never sent to Explorer. Custom scroll handles everything.
- **If no scroll** (release without drag): `{Blind}{MButton}` (full click) is synthesized on MButton Up, preserving normal middle-click behavior.

For non-Explorer apps, MButton Down is **passed through immediately** to enable native scroll detection.

### Native Scroll Probe

A movement-gated **native scroll probe** determines whether the app handles MButton drag-scroll natively using three signals:

1. **Cursor change** (HCURSOR handle via `GetCursorInfo` + `A_Cursor = "Unknown"`): Checked every tick. The initial HCURSOR is captured _before_ any MButton event is sent. A change is only detected when the handle differs AND `A_Cursor` reports `"Unknown"` (custom bitmap cursor). This dual check prevents false positives from standard cursor changes while reliably catching custom autoscroll icons (Chrome, Firefox).
2. **Win32 scroll position** (`GetScrollPos`): Checked after drag threshold (≥3px). Catches classic Win32 apps with native scrollbars.
3. **UIA scroll percent** (`GetVerticalScrollPercent`): Checked after drag threshold. Catches modern apps using custom renderers.

The probe runs continuously until **8px of vertical movement** (the same threshold used for custom scroll activation). Signal 1 is checked every tick from 0px; signals 2/3 start after 3px (filters cursor jitter). If any signal fires → **native scroll detected**. If none fire by 8px → engage custom scroll (UIA → WHEEL → WHEEL_CTRL → VSCROLL fallback chain).

No hardcoded app exclusion list is needed. Only excluded **controls** (toolbars, edit boxes, headers) are skipped via `MB_ExcludedControls`.

---

## Extended Window Spy (`extended-spy.ahk`)

Persistent tooltip showing Active Window + Window Under Cursor info. Toggled with `Win+W`.

- `#w` is always global (unconditional toggle); `Esc` and `LButton` are scoped with `#If WindowSpyState` (only active while spy is running)
- 800ms update interval with content-change detection (reduces flicker)
- Hover-to-pause: hovering over tooltip pauses updates
- Click tooltip to open dialog for copying text
- Dialog auto-sizes to fit content, positions flush to bottom-right of cursor's monitor (uses `GetCursorMonitor()`)
- UIA element info retrieved via `ElementFromPoint` with `Try/Finally` for guaranteed `ObjRelease` on stale pointers
- Controls sorted alphabetically, items >80 chars filtered out
- Comprehensive info: title, ahk_id, ahk_class, ahk_exe, dir, cmdline, PID (elevated indicator), monitor, pos, size, style, exstyle, focused control with hWnd, UIA element (type, name, AutomationId, ClassName), window text, controls

---

## Window Spawning (`window-spawning.ahk`)

### Key Functions

| Function/Label       | Purpose                                                                                                                                            |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `WS_Init()`          | Initialize `WS` object, register shell hook, SetWinEventHook (SHOW, UNCLOAKED, CREATE), CoInitialize, cleanup timer                                |
| `WS_OnShellHook()`   | Handle DESTROYED (brief-process detection + cleanup), ACTIVATED (positive intent detection), CREATED (exe recording + pre-pending + deferred move) |
| `WS_OnWinEvent()`    | Handle EVENT_OBJECT_SHOW, UNCLOAKED, CREATE (opacity hiding, deferred window processing)                                                           |
| `WS_IsReady()`       | Timing gate: visible, sized, uncloaked                                                                                                             |
| `WS_IsMovable()`     | Policy gate: skip tool windows, excluded classes, no-title (except `ApplicationFrameWindow`), visible-owner                                        |
| `WS_MoveToMonitor()` | Position mapping across monitors (relative or cursor-centered), taskbar-aware clamping, maximized/minimized handling, inline opacity reveal        |
| `WS_Reveal()`        | Idempotent opacity restore + sentinel set                                                                                                          |
| `WS_Log()`           | Debug logging to `%TEMP%\WS_Debug.log`                                                                                                             |
| `WS_SweepTracking`   | Timer (1s): expires stale entries in PrePending, Hidden, OwnerSentinel, RecentCreated, RecentExes                                                  |
| `WS_Cleanup()`       | OnExit: unhook WinEvents, reveal hidden windows, CoUninitialize                                                                                    |
| `~!Tab::`            | Alt+Tab passthrough hotkey with non-blocking WinEvent detection                                                                                    |

### Architecture

Shell hook (`RegisterShellHookWindow`) intercepts `HSHELL_WINDOWCREATED`, `HSHELL_WINDOWACTIVATED`, and `HSHELL_WINDOWDESTROYED`. WinEvent hooks (`SetWinEventHook`) listen for `EVENT_OBJECT_SHOW` (0x8002), `EVENT_OBJECT_UNCLOAKED` (0x8018), and `EVENT_OBJECT_CREATE` (0x8000).

All state is stored in a single `WS := {}` object. Every function declares only `global WS`.

### New Window Creation Paths

- **Win32 instant**: Shell hook fires → window already ready → move immediately
- **UWP event-driven**: Shell hook fires → not ready → `WS.Pending[hwnd]` → SHOW/UNCLOAK event → move (~62ms)
- **CREATE pre-pipeline (zero-flash)**: CREATE event fires 55-77ms before shell hook → register target in `WS.PrePending` → hide via opacity (`WS_EX_LAYERED` + alpha 0) → shell hook moves → restore opacity

### Activation Path: Positive Intent Detection

**Architecture**: Default-skip — activated windows are NOT moved unless positive intent is detected.

**Tier 1 — Brief-process detection** (Win32 single-instance re-launch):
When a single-instance Win32 app is re-launched, a new process briefly exists (100-500ms). It detects the existing instance via mutex/named pipe, sends a message, then exits. We detect this pattern:

1. `HSHELL_WINDOWCREATED` → record `{exe, tick}` in `WS.RecentCreated`
2. `HSHELL_WINDOWDESTROYED` → if window died within 3s, record exe in `WS.RecentExes`
3. `HSHELL_WINDOWACTIVATED` → if exe matches a `WS.RecentExes` entry (<5s) → **move**

**Tier 2 — Overlay-launch detection** (UWP single-instance re-launch):
UWP apps don't create a new process on re-launch (shell uses `IApplicationActivationManager`).
If overlay (Start menu) was recently visible (`WS.OverlayTick` < 2s) AND a **different** window activates (`lParam != prevHwnd`) → **move**.

**Z-order fallback protection**: When the foreground window is destroyed, `WS.ZOrderFallbackTick` is set and all intent detection (Tier 1 and Tier 2) is skipped for the next 200ms — the subsequent activation is Windows selecting the next z-order window, not user intent. Additionally, `WS.OverlayTick` is cleared on foreground destruction and when the previous window was minimized (belt-and-suspenders for Tier 2).

*Note: Z-order fallback protection was added based on observed false positives where closing a window caused the bottom-most WT to move. If similar issues recur, enable `WS.Debug := 1` and check `%TEMP%\WS_Debug.log` for the event sequence.*

**Retained guards** (not intent-based):

- Taskbar cursor check: cursor over `Shell_TrayWnd`/`Shell_SecondaryTrayWnd` → skip
- Same-monitor optimization: `windowMon == cursorMon` → skip

### Zero-Flash Opacity Approach

**Goal**: Eliminate the visual flash where windows briefly appear on the wrong monitor before being moved.

**Mechanism**: At `EVENT_OBJECT_CREATE` time, hide windows using `WS_EX_LAYERED` + `SetLayeredWindowAttributes` (alpha 0 in production, 128 in debug mode for 50% visibility). After `WS_MoveToMonitor` places the window on the correct monitor, restore full opacity.

**Key data structures:**

- `WS.PrePending` dict: `hwnd → {mon, tick, qpc}` — tracks CREATE-to-ShellHook/SHOW pipeline
- `WS.Hidden` dict: `hwnd → hadLayered` (bool if opacity-hidden, `-1` sentinel if "processed")

**Sentinel mechanism**: `WS.Hidden[hwnd] := -1` marks a window as "processed" so duplicate CREATE events don't re-hide an already-moved window.

**Owner-based sentinel** (`WS.OwnerSentinel`): When `WS_MoveToMonitor` processes a window, it records the window's owner hwnd with a timestamp. The CREATE handler checks if a new window's owner has a recent sentinel (<200ms) and skips hiding. This protects sibling `#32770` windows (e.g., Run dialog).

### Window Positioning Modes

`WS_MoveToMonitor` uses two positioning strategies depending on the window type:

| Mode                 | Condition           | Behavior                                                                                                     |
| -------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------ |
| **Relative mapping** | Window has a title  | Maps relative position from source to target monitor (window at 25% across monitor A → 25% across monitor B) |
| **Cursor-centered**  | Window has no title | Centers window on cursor position, clamped to work area                                                      |

**Why two modes**: Application windows (titled) have meaningful positions — the user or app placed them intentionally, so preserving relative position across monitors makes sense. Titleless windows (popups, dialogs, share sheets) spawn at system-default positions (often 0,0) with no user intent. Centering on the cursor places them where the user is looking and interacting.

**Example**: Explorer's Share dialog (`ApplicationFrameWindow` with empty title) spawns at (0,0) on whatever monitor Windows chooses. Relative mapping would place it at (0,0) on the cursor's monitor. Cursor-centering places it directly under the cursor where the user right-clicked.

**`ApplicationFrameWindow` exception**: `WS_IsMovable()` normally rejects titleless windows (infrastructure/phantom windows). `ApplicationFrameWindow` is exempted because it's always a real UWP frame, even when the title bar text is empty (e.g., Share popup, Windows Store dialogs).

**`RAIL_WINDOW` exclusion**: WSLg GUI apps (`msrdc.exe` RAIL windows) are excluded from window spawning entirely. Their RDP-based cursor rendering is disrupted by `WS_EX_LAYERED` opacity manipulation.

### WS Object Properties

| Property                | Purpose                                                           |
| ----------------------- | ----------------------------------------------------------------- |
| `WS.Debug`              | Debug log toggle. Logs to `%TEMP%\WS_Debug.log`                   |
| `WS.LogFile`            | Path to debug log file                                            |
| `WS.HookHwnd`           | Hidden GUI window for shell hook                                  |
| `WS.Pending`            | Deferred hwnd → `{mon, tick}`                                     |
| `WS.PendingAltTab`      | Alt+Tab state: `{mon, tick}` or `""`                              |
| `WS.ExcludedClasses`    | Array of window classes to skip (includes `RAIL_WINDOW` for WSLg) |
| `WS.PrePending`         | CREATE-registered hwnd → `{mon, tick, qpc}`                       |
| `WS.Hidden`             | Opacity-hidden hwnd → `hadLayered` (bool), or `-1` (sentinel)     |
| `WS.OwnerSentinel`      | Owner hwnd → `A_TickCount` (sibling CREATE suppression, 200ms)    |
| `WS.RecentCreated`      | hwnd → `{exe, tick}` — window lifespan tracking for Tier 1        |
| `WS.RecentExes`         | exe name → `A_TickCount` — brief-process signal for Tier 1        |
| `WS.LastForegroundHwnd` | Last movable foreground hwnd (Tier 2 overlay detection)           |
| `WS.OverlayTick`        | `A_TickCount` when overlay/infrastructure detected (Tier 2)       |
| `WS.ZOrderFallbackTick` | `A_TickCount` when foreground destroyed (skips intent detection)  |
| `WS.EventHookShow`      | Handle from `SetWinEventHook` (EVENT_OBJECT_SHOW)                 |
| `WS.EventHookUncloak`   | Handle from `SetWinEventHook` (EVENT_OBJECT_UNCLOAKED)            |
| `WS.EventHookCreate`    | Handle from `SetWinEventHook` (EVENT_OBJECT_CREATE)               |
| `WS.WinEventCB`         | `RegisterCallback` pointer for WinEventProc                       |
| `WS.QPCFreq`            | QPC frequency for µs-precision timing                             |

### Critical AHK v1.1 Details (Window Spawning)

- **32-bit masking**: `idObject & 0xFFFFFFFF` — WinEventProc uses 32-bit params but AHK reads 64-bit register slots on x64
- **Numeric coercion**: `hwnd + 0` — ensures consistent object key type in `WS.Pending` etc.
- **Global discipline**: Every function declares `global WS` (single object replaces 12+ individual globals)
- **No Fast flag**: `RegisterCallback("WS_OnWinEvent", "", 7)` — isolated pseudo-thread per callback

---

## UWP Split-Process Architecture (Reference)

```
ApplicationFrameHost.exe          SystemSettings.exe (or other UWP app)
  └── ApplicationFrameWindow        └── Windows.UI.Core.CoreWindow
       (visible frame, movable)          (render surface, non-movable)
       PID = X                           PID = Y  ← different!

explorer.exe
  └── Windows.UI.Core.CoreWindow
       (Start menu overlay — does NOT fire HSHELL_WINDOWACTIVATED)
       PID = Z
```

This architecture is relevant to:

- **WS_IsMovable()**: ApplicationFrameWindow is movable, CoreWindow is not
- **Tier 2 overlay detection**: Start menu CoreWindow doesn't fire shell hooks, so overlay detection relies on empty-class infrastructure events and `WS.OverlayTick`
- **Brief-process detection**: UWP re-launch doesn't create a new process (Tier 1 misses), hence Tier 2 exists

## Housekeeping

**CLAUDE.md size limit**: Keep under ~40KB (`wc -c CLAUDE.md`). Compress or remove content when adding.

**Temp file cleanup**: `*.tmp.*` files from atomic writes can orphan. Clean between turns and at session end: `rm *.tmp.*`
