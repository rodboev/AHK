# Dual-Axis MButton Scroll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add horizontal scrolling to MButton drag-scroll so dragging diagonally scrolls both axes simultaneously.

**Architecture:** Extend existing vertical-only scroll system with horizontal equivalents. Same power curve, same fallback chain (UIA → WHEEL → WHEEL_CTRL → VSCROLL). Each method handles both axes per tick.

**Tech Stack:** AutoHotkey v1.1, UI Automation COM, Win32 messages

**Spec:** `docs/superpowers/specs/2026-05-10-dual-axis-mbutton-scroll-design.md`

---

## Task 1: Foundation — State Variables, Movement Tracking, Power Curve

**Files:**
- Modify: `mbutton-scroll.ahk:28-33` (state variables)
- Modify: `mbutton-scroll.ahk:216-231` (movement tracking and power curve)

### Step 1.1: Add horizontal state variables

At line 30, change:

```autohotkey
; BEFORE (line 30):
global MB_Disabled := 0, MB_DeferredDown := 0, MB_ViewSize := 10.0, MB_AccumPct := -1

; AFTER:
global MB_Disabled := 0, MB_DeferredDown := 0, MB_ViewSize := 10.0, MB_AccumPct := -1
global MB_ViewSizeH := 10.0, MB_AccumPctH := -1
```

### Step 1.2: Update movement tracking to capture both axes

At line 217, change:

```autohotkey
; BEFORE (lines 216-219):
CoordMode, Mouse, Screen
MouseGetPos,, Y2
SignedDist := Y2 - MB_Y1
AbsDist := Abs(SignedDist)

; AFTER:
CoordMode, Mouse, Screen
MouseGetPos, MB_X2, Y2
SignedDistY := Y2 - MB_Y1
SignedDistX := MB_X2 - MB_X1
AbsDistY := Abs(SignedDistY)
AbsDistX := Abs(SignedDistX)
```

### Step 1.3: Update threshold to either-axis

At line 221, change:

```autohotkey
; BEFORE (line 221):
If (AbsDist >= 8) {

; AFTER:
If (AbsDistY >= 8 or AbsDistX >= 8) {
```

### Step 1.4: Replace single power curve with dual-axis curves

At lines 222-231, change:

```autohotkey
; BEFORE (lines 222-231):
MB_Triggered := 1
signDir := (SignedDist > 0) ? 1 : -1
absEffective := AbsDist

; Double curve: responsive up to 100px, soft cap beyond
If (absEffective <= 100) {
  curveValue := absEffective ** 0.8
} Else {
  curveValue := (100 ** 0.8) + ((absEffective - 100) ** 0.6)
}

; AFTER:
MB_Triggered := 1

; Vertical power curve
If (AbsDistY <= 100) {
  curveValueY := AbsDistY ** 0.8
} Else {
  curveValueY := (100 ** 0.8) + ((AbsDistY - 100) ** 0.6)
}

; Horizontal power curve
If (AbsDistX <= 100) {
  curveValueX := AbsDistX ** 0.8
} Else {
  curveValueX := (100 ** 0.8) + ((AbsDistX - 100) ** 0.6)
}
```

### Step 1.5: Commit foundation changes

```bash
git add mbutton-scroll.ahk
git commit -m "feat(mbutton-scroll): add dual-axis foundation

- Add MB_ViewSizeH, MB_AccumPctH state variables
- Track both X and Y movement in timer
- Either-axis threshold (>=8 triggers both)
- Independent power curves per axis"
```

---

## Task 2: UIA Method — Horizontal ScrollPattern Support

**Files:**
- Modify: `mbutton-scroll.ahk:107-111` (UIA setup)
- Modify: `mbutton-scroll.ahk:243-265` (UIA scroll execution)

### Step 2.1: Capture horizontal ViewSize during UIA setup

After line 111 (after vertical ViewSize capture), add:

```autohotkey
; BEFORE (lines 107-112):
If (MB_ScrollPattern) {
  DllCall(NumGet(NumGet(MB_ScrollPattern+0)+8*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_ViewSize)
  If (MB_ViewSize < 1)
    MB_ViewSize := 10.0
}

; AFTER:
If (MB_ScrollPattern) {
  DllCall(NumGet(NumGet(MB_ScrollPattern+0)+8*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_ViewSize)
  If (MB_ViewSize < 1)
    MB_ViewSize := 10.0
  ; Horizontal ViewSize (vtable offset 7)
  DllCall(NumGet(NumGet(MB_ScrollPattern+0)+7*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_ViewSizeH)
  If (MB_ViewSizeH < 1)
    MB_ViewSizeH := 10.0
}
```

### Step 2.2: Update UIA scroll to handle both axes

Replace the UIA scroll block (inside `If (MB_Method = "UIA")`). The key changes:
- Rename `signDir` to `signDirY`
- Add horizontal accumulator init
- Compute horizontal delta with same formula
- Send both axes in SetScrollPercent call

```autohotkey
; BEFORE (lines 243-265, inside UIA block):
If (MB_AccumPct < 0) {
  DllCall(NumGet(NumGet(MB_ScrollPattern+0)+6*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_AccumPct)
}

; Capture Win32 scroll position BEFORE UIA scroll (for cross-validation)
If (MB_FallbackChecked = 0) {
  uiaTarget := MB_Ctrl ? MB_Ctrl : MB_Win
  MB_UIAVerifyPos := GetScrollPos(uiaTarget)
}

; Normalize scroll speed based on ViewSize:
; - ViewSize = 100%: only 1 item visible (small list), scroll FAST
; - ViewSize = 1%: 100 items visible (huge list), scroll SLOW
; Formula: mult = ViewSize / 3 (5x amplified from /15)
; Examples: ViewSize=50% → mult=16.7, ViewSize=15% → mult=5, ViewSize=3% → mult=1
viewMultiplier := MB_ViewSize / 3.0
viewMultiplier := Max(0.25, Min(viewMultiplier, 50.0))  ; Clamp 0.25x to 50x
deltaPct := signDir * curveValue * 0.006 * viewMultiplier
MB_AccumPct := MB_AccumPct + deltaPct
MB_AccumPct := (MB_AccumPct < 0) ? 0 : (MB_AccumPct > 100) ? 100 : MB_AccumPct
If (MB_Debug)
  ToolTip, % "UIA: " Round(MB_AccumPct, 1) "%% (view=" Round(MB_ViewSize,1) "%% mult=" Round(viewMultiplier,2) ")"
DllCall(NumGet(NumGet(MB_ScrollPattern+0)+4*A_PtrSize), "Ptr", MB_ScrollPattern, "Double", -1.0, "Double", MB_AccumPct)

; AFTER:
; Initialize vertical accumulator
If (MB_AccumPct < 0) {
  DllCall(NumGet(NumGet(MB_ScrollPattern+0)+6*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_AccumPct)
}
; Initialize horizontal accumulator (vtable offset 5)
If (MB_AccumPctH < 0) {
  DllCall(NumGet(NumGet(MB_ScrollPattern+0)+5*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_AccumPctH)
}

; Capture Win32 scroll position BEFORE UIA scroll (for cross-validation)
If (MB_FallbackChecked = 0) {
  uiaTarget := MB_Ctrl ? MB_Ctrl : MB_Win
  MB_UIAVerifyPos := GetScrollPos(uiaTarget)
}

; Vertical scroll delta
signDirY := (SignedDistY > 0) ? 1 : -1
viewMultiplierY := MB_ViewSize / 3.0
viewMultiplierY := Max(0.25, Min(viewMultiplierY, 50.0))
deltaPctY := signDirY * curveValueY * 0.006 * viewMultiplierY
MB_AccumPct := MB_AccumPct + deltaPctY
MB_AccumPct := (MB_AccumPct < 0) ? 0 : (MB_AccumPct > 100) ? 100 : MB_AccumPct

; Horizontal scroll delta
signDirX := (SignedDistX > 0) ? 1 : -1
viewMultiplierH := MB_ViewSizeH / 3.0
viewMultiplierH := Max(0.25, Min(viewMultiplierH, 50.0))
deltaPctH := signDirX * curveValueX * 0.006 * viewMultiplierH
MB_AccumPctH := MB_AccumPctH + deltaPctH
MB_AccumPctH := (MB_AccumPctH < 0) ? 0 : (MB_AccumPctH > 100) ? 100 : MB_AccumPctH

If (MB_Debug)
  ToolTip, % "UIA: V=" Round(MB_AccumPct, 1) "%% H=" Round(MB_AccumPctH, 1) "%%"
; SetScrollPercent(hPct, vPct) - vtable offset 4
DllCall(NumGet(NumGet(MB_ScrollPattern+0)+4*A_PtrSize), "Ptr", MB_ScrollPattern, "Double", MB_AccumPctH, "Double", MB_AccumPct)
```

### Step 2.3: Commit UIA changes

```bash
git add mbutton-scroll.ahk
git commit -m "feat(mbutton-scroll): add horizontal UIA scrolling

- Capture horizontal ViewSize at setup (vtable offset 7)
- Initialize horizontal scroll percent (vtable offset 5)
- Compute horizontal delta with same power curve formula
- Send both axes via SetScrollPercent(hPct, vPct)"
```

---

## TEST CHECKPOINT: UIA in Explorer

**Manual testing required before proceeding to remaining methods.**

### Test diagonal scroll in Explorer

1. Reload script (double-click `AutoHotkey.ahk` or `Ctrl+S` in editor)
2. Open Windows Explorer to a folder with many files (e.g., `C:\Windows\System32`)
3. Set view to "Details" with columns wide enough to require horizontal scrollbar
4. Hold MButton and drag **diagonally down-right**
5. **Expected:** Window scrolls both down AND right simultaneously
6. Drag **diagonally up-left**
7. **Expected:** Window scrolls both up AND left

### Test pure vertical still works

1. Hold MButton and drag **straight down**
2. **Expected:** Scrolls down only, no horizontal drift

**If tests pass:** Proceed to Task 3.
**If tests fail:** Debug before continuing.

---

## Task 3: WHEEL Methods — Horizontal WM_MOUSEHWHEEL

**Files:**
- Modify: `mbutton-scroll.ahk` — WHEEL block (~line 361-394)
- Modify: `mbutton-scroll.ahk` — WHEEL_CTRL block (~line 302-341)

### Step 3.1: Update WHEEL method (window-level)

In the WHEEL else block (around line 361), update to send both messages:

```autohotkey
; BEFORE (lines 366-393):
lParam := ((MB_Y1 & 0xFFFF) << 16) | (MB_X1 & 0xFFFF)
; MUST cap below 120 for smooth scrolling (120 = 1 notch = 3 lines)
magnitude := Max(1, Min(119, Floor(curveValue / 2)))
Delta := (SignedDist > 0) ? -magnitude : magnitude
wParam := Delta << 16

If (!MB_FallbackChecked) {
  ; Test if window-level WHEEL actually scrolls (first scroll only)
  ctrlTarget := MB_Ctrl ? MB_Ctrl : MB_Win
  posBefore := GetScrollPos(ctrlTarget)
  PostMessage, 0x20A, %wParam%, %lParam%,, ahk_id %MB_Win%
  Sleep, 15
  posAfter := GetScrollPos(ctrlTarget)
  If (posBefore = posAfter) {
    ; No movement detected — try sending to control directly
    MB_Method := "WHEEL_CTRL"
    MB_FallbackChecked := 0
    If (MB_Debug)
      ToolTip, % "WHEEL->WHEEL_CTRL (no movement)"
  } Else {
    MB_FallbackChecked := 1
  }
} Else {
  PostMessage, 0x20A, %wParam%, %lParam%,, ahk_id %MB_Win%
}

If (MB_Debug && MB_Method = "WHEEL")
  ToolTip, % "WHEEL: d=" Delta

; AFTER:
lParam := ((MB_Y1 & 0xFFFF) << 16) | (MB_X1 & 0xFFFF)

; Vertical: WM_MOUSEWHEEL (0x20A)
magnitudeY := Max(1, Min(119, Floor(curveValueY / 2)))
DeltaY := (SignedDistY > 0) ? -magnitudeY : magnitudeY
wParamY := DeltaY << 16

If (!MB_FallbackChecked) {
  ; Test if window-level WHEEL actually scrolls (first scroll only)
  ctrlTarget := MB_Ctrl ? MB_Ctrl : MB_Win
  posBefore := GetScrollPos(ctrlTarget)
  PostMessage, 0x20A, %wParamY%, %lParam%,, ahk_id %MB_Win%
  Sleep, 15
  posAfter := GetScrollPos(ctrlTarget)
  If (posBefore = posAfter) {
    ; No movement detected — try sending to control directly
    MB_Method := "WHEEL_CTRL"
    MB_FallbackChecked := 0
    If (MB_Debug)
      ToolTip, % "WHEEL->WHEEL_CTRL (no movement)"
  } Else {
    MB_FallbackChecked := 1
  }
} Else {
  PostMessage, 0x20A, %wParamY%, %lParam%,, ahk_id %MB_Win%
}

; Horizontal: WM_MOUSEHWHEEL (0x20E)
If (AbsDistX >= 8) {
  magnitudeX := Max(1, Min(119, Floor(curveValueX / 2)))
  DeltaX := (SignedDistX > 0) ? magnitudeX : -magnitudeX
  wParamX := DeltaX << 16
  PostMessage, 0x20E, %wParamX%, %lParam%,, ahk_id %MB_Win%
}

If (MB_Debug && MB_Method = "WHEEL")
  ToolTip, % "WHEEL: dY=" DeltaY " dX=" (AbsDistX >= 8 ? DeltaX : 0)
```

### Step 3.2: Update WHEEL_CTRL method (control-level)

In the WHEEL_CTRL block (around line 302), update similarly:

```autohotkey
; BEFORE (lines 307-341):
target := MB_Ctrl ? MB_Ctrl : MB_Win

; Get position BEFORE scroll (only on first check)
If (!MB_FallbackChecked) {
  posBefore := GetScrollPos(target)
}

; Send WHEEL message
lParam := ((MB_Y1 & 0xFFFF) << 16) | (MB_X1 & 0xFFFF)
magnitude := Max(1, Min(119, Floor(curveValue / 2)))
Delta := (SignedDist > 0) ? -magnitude : magnitude
wParam := Delta << 16
PostMessage, 0x20A, %wParam%, %lParam%,, ahk_id %target%  ; WM_MOUSEWHEEL

; Check for fallback on first scroll only
If (!MB_FallbackChecked) {
  Sleep, 10  ; Brief pause for scroll to complete
  posAfter := GetScrollPos(target)
  scrolledUnits := Abs(posAfter - posBefore)

  ; If jumped >40 units (typically >1 line), switch to VSCROLL
  If (scrolledUnits > 40) {
    MB_Method := "VSCROLL"
    SetTimer, MBScrollTimer, 150
    ; Revert the jump by scrolling opposite direction
    revertDir := (posAfter > posBefore) ? 0 : 1  ; 0=up, 1=down
    PostMessage, 0x115, %revertDir%, 0,, ahk_id %target%  ; WM_VSCROLL
    If (MB_Debug)
      ToolTip, % "WHEEL_CTRL→VSCROLL (jumped " scrolledUnits " units)"
  }
  MB_FallbackChecked := 1
}

If (MB_Debug && MB_Method = "WHEEL_CTRL")
  ToolTip, % "WHEEL_CTRL: d=" Delta

; AFTER:
target := MB_Ctrl ? MB_Ctrl : MB_Win

; Get position BEFORE scroll (only on first check)
If (!MB_FallbackChecked) {
  posBefore := GetScrollPos(target)
}

; Vertical: WM_MOUSEWHEEL (0x20A)
lParam := ((MB_Y1 & 0xFFFF) << 16) | (MB_X1 & 0xFFFF)
magnitudeY := Max(1, Min(119, Floor(curveValueY / 2)))
DeltaY := (SignedDistY > 0) ? -magnitudeY : magnitudeY
wParamY := DeltaY << 16
PostMessage, 0x20A, %wParamY%, %lParam%,, ahk_id %target%

; Check for fallback on first scroll only
If (!MB_FallbackChecked) {
  Sleep, 10  ; Brief pause for scroll to complete
  posAfter := GetScrollPos(target)
  scrolledUnits := Abs(posAfter - posBefore)

  ; If jumped >40 units (typically >1 line), switch to VSCROLL
  If (scrolledUnits > 40) {
    MB_Method := "VSCROLL"
    SetTimer, MBScrollTimer, 150
    ; Revert the jump by scrolling opposite direction
    revertDir := (posAfter > posBefore) ? 0 : 1
    PostMessage, 0x115, %revertDir%, 0,, ahk_id %target%
    If (MB_Debug)
      ToolTip, % "WHEEL_CTRL→VSCROLL (jumped " scrolledUnits " units)"
  }
  MB_FallbackChecked := 1
}

; Horizontal: WM_MOUSEHWHEEL (0x20E)
If (AbsDistX >= 8) {
  magnitudeX := Max(1, Min(119, Floor(curveValueX / 2)))
  DeltaX := (SignedDistX > 0) ? magnitudeX : -magnitudeX
  wParamX := DeltaX << 16
  PostMessage, 0x20E, %wParamX%, %lParam%,, ahk_id %target%
}

If (MB_Debug && MB_Method = "WHEEL_CTRL")
  ToolTip, % "WHEEL_CTRL: dY=" DeltaY " dX=" (AbsDistX >= 8 ? DeltaX : 0)
```

### Step 3.3: Commit WHEEL changes

```bash
git add mbutton-scroll.ahk
git commit -m "feat(mbutton-scroll): add horizontal WHEEL scrolling

- WHEEL: send WM_MOUSEHWHEEL (0x20E) for horizontal
- WHEEL_CTRL: same, to control handle
- Only send horizontal if AbsDistX >= 8"
```

---

## Task 4: VSCROLL Method — Horizontal WM_HSCROLL

**Files:**
- Modify: `mbutton-scroll.ahk` — VSCROLL block (~line 343-359)

### Step 4.1: Update VSCROLL method

In the VSCROLL block (around line 343):

```autohotkey
; BEFORE (lines 343-359):
} Else If (MB_Method = "VSCROLL") {
  ; ===========================================
  ; WM_VSCROLL LINE - dynamic timer based on drag distance
  ; No fractional scrolling, most compatible
  ; ===========================================
  scrollDir := (SignedDist > 0) ? 1 : 0
  target := MB_Ctrl ? MB_Ctrl : MB_Win

  ; Dynamic timer: 300ms at 8px (slow), 20ms at 300px+ (fast)
  ; Map AbsDist 8-200 to timer 20-300
  timerMs := 300 - Floor((Min(AbsDist, 300) - 8) * (100 / 192))
  timerMs := Max(20, Min(300, timerMs / 2))
  SetTimer, MBScrollTimer, %timerMs%

  If (MB_Debug)
    ToolTip, % "VSCROLL: dir=" scrollDir " timer=" timerMs "ms"
  PostMessage, 0x115, %scrollDir%, 0,, ahk_id %target%

; AFTER:
} Else If (MB_Method = "VSCROLL") {
  ; ===========================================
  ; WM_VSCROLL/HSCROLL LINE - dynamic timer based on drag distance
  ; No fractional scrolling, most compatible
  ; ===========================================
  target := MB_Ctrl ? MB_Ctrl : MB_Win

  ; Dynamic timer: use max of both axes for speed calculation
  maxDist := (AbsDistY > AbsDistX) ? AbsDistY : AbsDistX
  timerMs := 300 - Floor((Min(maxDist, 300) - 8) * (100 / 192))
  timerMs := Max(20, Min(300, timerMs / 2))
  SetTimer, MBScrollTimer, %timerMs%

  ; Vertical: WM_VSCROLL (0x115)
  scrollDirY := (SignedDistY > 0) ? 1 : 0
  PostMessage, 0x115, %scrollDirY%, 0,, ahk_id %target%

  ; Horizontal: WM_HSCROLL (0x114)
  If (AbsDistX >= 8) {
    scrollDirX := (SignedDistX > 0) ? 1 : 0
    PostMessage, 0x114, %scrollDirX%, 0,, ahk_id %target%
  }

  If (MB_Debug)
    ToolTip, % "VSCROLL: dirY=" scrollDirY " dirX=" (AbsDistX >= 8 ? scrollDirX : "-") " timer=" timerMs "ms"
```

### Step 4.2: Commit VSCROLL changes

```bash
git add mbutton-scroll.ahk
git commit -m "feat(mbutton-scroll): add horizontal VSCROLL scrolling

- Send WM_HSCROLL (0x114) for horizontal
- Dynamic timer uses max of both axes
- Only send horizontal if AbsDistX >= 8"
```

---

## TEST CHECKPOINT: Full Test Matrix

**Manual testing for all methods.**

### Reload and test

1. Reload script

### Test matrix

| App | Method | Test | Expected |
|-----|--------|------|----------|
| Explorer file list | UIA | Diagonal drag | Both axes scroll |
| VS Code | WHEEL | Diagonal drag | Vertical works, horizontal may vary |
| Notepad | WHEEL_CTRL | Vertical drag | Vertical works |
| Regedit tree | VSCROLL | Diagonal drag | Vertical works, horizontal may vary |
| Chrome | Native | MButton drag | Native scroll icon, bypassed |

### Verify native bypass

1. Open Chrome or Firefox
2. Hold MButton and drag
3. **Expected:** Browser's native autoscroll activates, custom scroll does NOT engage

**If all tests pass:** Implementation complete.
