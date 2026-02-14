# WT Scroll Guard — Complete Implementation Plan

**Status: Steps 1-7, 9-10 IMPLEMENTED. Step 8 (scroll lock testing) deferred to manual testing.**

## Context

Scroll guard code exists in `AutoHotkey.ahk` (untested, uncommitted) using Layer 3 RangeValue on ScrollBar.Vertical. This plan covers: fixing/testing the guard, migrating scan output into Extended Spy, investigating Layer 1 scroll properties, and building a test harness — all bundled for minimal user testing.

## UIA Scroll Architecture

| Layer        | Element            | Pattern (ID)       | Key Properties                                                      | Methods                          |
| ------------ | ------------------ | ------------------ | ------------------------------------------------------------------- | -------------------------------- |
| 1. Container | ScrollViewer       | Scroll (10004)     | VerticalScrollPercent (**30055**), VerticallyScrollable (**30058**) | `SetScrollPercent()`, `Scroll()` |
| 2. Children  | Items              | ScrollItem (10017) | —                                                                   | `ScrollIntoView()`               |
| 3. ScrollBar | ScrollBar.Vertical | RangeValue (10003) | Value (30047), Min (30049), Max (30050)                             | `SetValue()`                     |

**Current code**: Layer 3. **Reference**: `/home/rod/projects/UIAutomation/Lib/UIA_Interface.ahk`, `UIA_Constants.ahk`

## Steps

### Step 1: Startup tooltip cleanup ✅

**File**: `AutoHotkey.ahk` (line ~29, auto-execute section)

Add `ToolTip,,,, 2` to clear leftover scroll guard tooltip on script reload. This fixes the tooltip persisting after restarts.

### Step 2: Add VT_R8 to `_GetUIAProp()` ✅

**File**: `extended-spy.ahk`, `_GetUIAProp()` (~line 151)

Add after VT_I4 check:

```autohotkey
} Else If (_vt = 5) {  ; VT_R8 (Double)
  _result := NumGet(_variant, 8, "Double")
```

### Step 3: Integrate scroll data into Extended Spy (`#w`) ✅

**File**: `extended-spy.ahk`

In `ExtendedSpyUpdate` (~line 320), when cursor/active window is WT:

```autohotkey
; WT Scroll section (after UIA element)
If (info.exe.path ~= "i)WindowsTerminal") {
  _wtPct := SG_GetScrollPct()
  _guardMethod := SG_ScrollLocked ? "Locked"
    : SG_ScrollProtected ? "RV-Guard " Ceil((SG_ScrollTimeout - (A_TickCount - SG_ScrollProtectTick)) / 1000) "s"
    : "Off"
  info.wtScroll := {pct: _wtPct, method: _guardMethod}
}
```

In `FormatWindowInfo()` (~line 196, after ScrollPattern line), add:

```autohotkey
If (info.HasKey("wtScroll") && info.wtScroll.pct != -1)
  s .= "WT Scroll: " . Round(info.wtScroll.pct, 1) . "% [" . info.wtScroll.method . "]`n"
Else If (info.HasKey("wtScroll"))
  s .= "WT Scroll: (no scroll) [" . info.wtScroll.method . "]`n"
```

This gives real-time auto-updating scroll position in Extended Spy's tooltip, with the guard method shown.

### Step 4: Remove `#s` binding and `SG_ScanToDialog` ✅

**File**: `AutoHotkey.ahk`

- Remove `#s::` hotkey (line 95-97)
- Remove `SG_ScanToDialog()` function (lines 610-677)
- Remove `SG_ScanGuiEscape/SG_ScanGuiClose` labels (lines 678-681)
- Remove `SG_CollectAll()` function (lines 685-767)

### Step 5: Probe Layer 1 properties (30055, 30058) ✅

**File**: `AutoHotkey.ahk`

Add Layer 1 probing to `SG_GetScrollPattern()`. After finding ScrollBar.Vertical, walk up via TreeWalker to find the parent container, then read:

```autohotkey
; On container element:
_vScrollPct := _GetUIAProp(containerEl, 30055)  ; VerticalScrollPercent
_vScrollable := _GetUIAProp(containerEl, 30058) ; VerticallyScrollable
```

If property 30055 returns a valid 0-100% value, we can use Layer 1 directly. Results displayed in Extended Spy.

### Step 6: Implement guard method toggle ✅

**File**: `AutoHotkey.ahk`, WT hotkey section

Add `^ScrollLock` (Ctrl+ScrollLock) to cycle guard methods:

```
Off → RangeValue (Layer 3) → Layer1 (if available) → Lock (if 30058 works) → Off
```

Current guard tooltip shows: `[RV-Guard 3s]`, `[L1-Guard 3s]`, `[Locked]`, or `[Off]`

### Step 7: Robust tooltip timer / method-aware guard ✅

**File**: `AutoHotkey.ahk`, `SG_ScrollGuard:` timer

- Make guard timer respect `SG_ScrollMethod` variable
- Countdown reaches 0 → `SG_ScrollTip("")` → clears tooltip exactly once
- Multiple restarts of 5s countdown: reset `SG_ScrollProtectTick := A_TickCount` each time
- Script reload: startup `ToolTip,,,, 2` (Step 1) handles orphaned tooltips

### Step 8: Test scroll lock via property 30058

If Layer 1 container found (Step 5), attempt to set `VerticallyScrollable` to FALSE:

- Try via `SetScrollPercent(-1, -1)` — both axes NoScroll sentinel
- Try via `GetCurrentPattern(10004)` → read/write `CurrentVerticallyScrollable`
- Document what works and what doesn't on WT

### Step 9: Create `ui-automation.md` ✅

**File**: `/home/rod/projects/AHK/ui-automation.md`

Document: three-layer architecture, vtable references, property IDs, Descolada library label→DllCall mappings, empirical WT results.

### Step 10: Store findings to memory databases + Update CLAUDE.md ✅

Commit observations to claude-mem and mcp-memory-service. Update CLAUDE.md to reference `ui-automation.md`.

## Key Files

| File                            | Changes                                                        |
| ------------------------------- | -------------------------------------------------------------- |
| `extended-spy.ahk` (~151)       | `_GetUIAProp()` — add VT_R8                                    |
| `extended-spy.ahk` (~170, ~320) | `FormatWindowInfo()` + `ExtendedSpyUpdate` — WT scroll section |
| `AutoHotkey.ahk` (29)           | Startup tooltip cleanup                                        |
| `AutoHotkey.ahk` (72-98)        | WT hotkeys — remove `#s`, add `^ScrollLock` toggle             |
| `AutoHotkey.ahk` (100-147)      | `SG_ScrollGuard:` — method-aware guard, robust countdown       |
| `AutoHotkey.ahk` (610-767)      | Remove SG_ScanToDialog + SG_CollectAll                         |
| `AutoHotkey.ahk` (772-874)      | SG_Get/SetScrollPct — add Layer 1 if it works                  |
| `ui-automation.md` (new)        | UIA architecture docs                                          |
| `CLAUDE.md`                     | Reference ui-automation.md                                     |

## Test Protocol (batched, user toggles)

All testing done in one session after full build:

1. **Reload script** → Verify no leftover tooltips
2. **`Win+W`** → Extended Spy shows `WT Scroll: XX.X% [Off]` when hovering WT
3. **Scroll up in WT** (wheel or click+drag scrollbar) → Spy updates percentage live
4. **While scrolled up, `Ctrl+ScrollLock`** → Cycles to `[RV-Guard 5s]`. Guard active.
5. **Trigger CC output** (type a command that produces output) → Verify scroll position is restored after jump
6. **Wait 5s** → Guard tooltip disappears, method shows `[Off]`
7. **`ScrollLock`** → Indefinite lock, spy shows `[Locked]`
8. **`Ctrl+ScrollLock`** → Cycles through available methods
9. **`ScrollLock` again** → Unlocks
10. **Close WT, reopen** → No stale tooltips
11. If Layer 1 available: test that method too via toggle

Toggles let user cycle methods without touching code. Extended Spy shows live state.
