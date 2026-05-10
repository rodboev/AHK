# Dual-Axis MButton Scroll Design

## Summary

Add horizontal scrolling to the existing MButton drag-scroll system. Dragging down-right scrolls down and right simultaneously, matching native browser autoscroll behavior.

## Current State

- `mbutton-scroll.ahk` tracks vertical movement only
- UIA `SetScrollPercent` passes `-1.0` for horizontal (no-scroll)
- WHEEL/WHEEL_CTRL use only WM_MOUSEWHEEL (0x20A)
- VSCROLL uses only WM_VSCROLL (0x115)

## Design Decisions

### Threshold: Either-Axis Triggers Both
`max(absDistX, absDistY) >= 8` activates scrolling on both axes. Simpler than diagonal distance calculation, nearly identical feel.

### Unified Method Per Scroll Type
The fallback chain (UIA → WHEEL → WHEEL_CTRL → VSCROLL) determines the method for both axes. No independent per-axis fallback.

### Native Probe: Vertical Only
If vertical scrolls natively, assume horizontal does too. Can revisit after testing.

## Implementation

### State Variables (line 28-33)

Add horizontal equivalents:

```autohotkey
global MB_X1, MB_Y1, MB_X2, MB_Win, MB_ClassName, MB_Triggered
global MB_ViewSize := 10.0, MB_AccumPct := -1
global MB_ViewSizeH := 10.0, MB_AccumPctH := -1
```

- `MB_X2` — horizontal position in timer
- `MB_ViewSizeH` — UIA horizontal view size
- `MB_AccumPctH` — UIA horizontal scroll percentage

### Movement Tracking (line 217-221)

```autohotkey
MouseGetPos, MB_X2, Y2
SignedDistY := Y2 - MB_Y1
SignedDistX := MB_X2 - MB_X1
AbsDistY := Abs(SignedDistY)
AbsDistX := Abs(SignedDistX)
If (AbsDistY >= 8 or AbsDistX >= 8) {
```

### Power Curve (after line 221)

Apply independently to each axis:

```autohotkey
; Vertical
If (AbsDistY <= 100)
  curveValueY := AbsDistY ** 0.8
Else
  curveValueY := (100 ** 0.8) + ((AbsDistY - 100) ** 0.6)

; Horizontal
If (AbsDistX <= 100)
  curveValueX := AbsDistX ** 0.8
Else
  curveValueX := (100 ** 0.8) + ((AbsDistX - 100) ** 0.6)
```

### UIA Method (lines 104-119, 233-265)

**Setup** — capture horizontal ViewSize:
```autohotkey
; Vtable offset 7: get_CurrentHorizontalViewSize
DllCall(NumGet(NumGet(MB_ScrollPattern+0)+7*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_ViewSizeH)
If (MB_ViewSizeH < 1)
  MB_ViewSizeH := 10.0
```

**Scroll** — initialize horizontal accumulator, compute delta, send both axes:
```autohotkey
; Vtable offset 5: get_CurrentHorizontalScrollPercent
If (MB_AccumPctH < 0)
  DllCall(NumGet(NumGet(MB_ScrollPattern+0)+5*A_PtrSize), "Ptr", MB_ScrollPattern, "Double*", MB_AccumPctH)

; Compute horizontal delta
signDirX := (SignedDistX > 0) ? 1 : -1
viewMultiplierH := MB_ViewSizeH / 3.0
viewMultiplierH := Max(0.25, Min(viewMultiplierH, 50.0))
deltaPctH := signDirX * curveValueX * 0.006 * viewMultiplierH
MB_AccumPctH := MB_AccumPctH + deltaPctH
MB_AccumPctH := (MB_AccumPctH < 0) ? 0 : (MB_AccumPctH > 100) ? 100 : MB_AccumPctH

; Vtable offset 4: SetScrollPercent(hPct, vPct)
DllCall(NumGet(NumGet(MB_ScrollPattern+0)+4*A_PtrSize), "Ptr", MB_ScrollPattern, "Double", MB_AccumPctH, "Double", MB_AccumPct)
```

### WHEEL / WHEEL_CTRL Methods (lines 302-394)

Add WM_MOUSEHWHEEL (0x20E) for horizontal:

```autohotkey
; Vertical (existing)
magnitudeY := Max(1, Min(119, Floor(curveValueY / 2)))
DeltaY := (SignedDistY > 0) ? -magnitudeY : magnitudeY
wParamY := DeltaY << 16
PostMessage, 0x20A, %wParamY%, %lParam%,, ahk_id %target%

; Horizontal (new)
If (AbsDistX >= 8) {
  magnitudeX := Max(1, Min(119, Floor(curveValueX / 2)))
  DeltaX := (SignedDistX > 0) ? magnitudeX : -magnitudeX
  wParamX := DeltaX << 16
  PostMessage, 0x20E, %wParamX%, %lParam%,, ahk_id %target%
}
```

### VSCROLL Method (lines 343-359)

Add WM_HSCROLL (0x114) for horizontal:

```autohotkey
; Vertical (existing)
scrollDirY := (SignedDistY > 0) ? 1 : 0
PostMessage, 0x115, %scrollDirY%, 0,, ahk_id %target%

; Horizontal (new)
If (AbsDistX >= 8) {
  scrollDirX := (SignedDistX > 0) ? 1 : 0
  PostMessage, 0x114, %scrollDirX%, 0,, ahk_id %target%
}
```

## UIA Vtable Reference

| Offset | Method |
|--------|--------|
| 4 | `SetScrollPercent(hPct, vPct)` |
| 5 | `get_CurrentHorizontalScrollPercent` |
| 6 | `get_CurrentVerticalScrollPercent` |
| 7 | `get_CurrentHorizontalViewSize` |
| 8 | `get_CurrentVerticalViewSize` |

## Message Reference

| Message | Hex | Direction |
|---------|-----|-----------|
| WM_MOUSEWHEEL | 0x20A | Vertical |
| WM_MOUSEHWHEEL | 0x20E | Horizontal |
| WM_VSCROLL | 0x115 | Vertical |
| WM_HSCROLL | 0x114 | Horizontal |

## Testing

1. **Explorer file list** — UIA method, drag diagonally in wide folder view
2. **VS Code** — WHEEL method, horizontal scroll in wide files
3. **Tree views** — VSCROLL method, verify HSCROLL works or gracefully no-ops
4. **Native scroll apps** — Chrome/Firefox should still be detected and bypassed

## Staged Rollout

1. UIA first — test in Explorer
2. WHEEL/WHEEL_CTRL — test in Electron apps
3. VSCROLL — test in classic Win32 apps
