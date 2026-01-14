# === EXPLORER SMOOTH SCROLL ===

Implementing 4 improvements to the MButton drag scroll system: GetScrollPos-based fallback detection, configuration consolidation, dead code removal, and full fallback chain.

---

## Proposed Changes

### Phase 1: GetScrollPos-based Fallback Detection

The current WHEEL_CTRL → VSCROLL fallback (lines 1024-1044) doesn't work because it compares two internal counters—we never detect actual scroll position changes.

#### [MODIFY] [AutoHotkey.ahk](file:///c:/Dropbox/Projects/AHK/AutoHotkey.ahk)

**Add GetScrollPos helper function** (before MButton handler):

```autohotkey
; Get vertical scroll position for a control (cross-process safe)
GetScrollPos(hwnd) {
    SB_VERT := 1
    return DllCall("GetScrollPos", "Ptr", hwnd, "Int", SB_VERT, "Int")
}
```

**Modify WHEEL_CTRL section** (lines 1015-1044) to:

1. Query scroll position **before** sending WHEEL message
2. Send WHEEL message
3. Query scroll position **after**
4. If delta > 40 units (jumped >1 line), switch to VSCROLL
5. If detection triggered, send VSCROLL in opposite direction to revert

```diff
 } Else If (MB_Method = "WHEEL_CTRL") {
-    lParam := ((MBScroll_Y1 & 0xFFFF) << 16) | (MBScroll_X1 & 0xFFFF)
-    magnitude := Max(1, Min(119, Floor(curveValue / 2)))
-    ...existing broken detection...
-    PostMessage, 0x20A, %wParam%, %lParam%,, ahk_id %target%

+    target := MBScroll_Ctrl ? MBScroll_Ctrl : MBScroll_Win
+    
+    ; Get position BEFORE scroll
+    posBefore := GetScrollPos(target)
+    
+    ; Send WHEEL message
+    lParam := ((MBScroll_Y1 & 0xFFFF) << 16) | (MBScroll_X1 & 0xFFFF)
+    magnitude := Max(1, Min(119, Floor(curveValue / 2)))
+    Delta := (SignedDist > 0) ? -magnitude : magnitude
+    wParam := Delta << 16
+    PostMessage, 0x20A, %wParam%, %lParam%,, ahk_id %target%
+    Sleep, 5  ; Brief pause for scroll to complete
+    
+    ; Get position AFTER scroll
+    posAfter := GetScrollPos(target)
+    scrolledUnits := Abs(posAfter - posBefore)
+    
+    ; If jumped >40 units (typically >1 line), switch to VSCROLL
+    If (!MB_FallbackChecked && scrolledUnits > 40) {
+        MB_Method := "VSCROLL"
+        SetTimer, MBScrollTimer, 150
+        ; Revert the jump by scrolling opposite direction
+        revertDir := (posAfter > posBefore) ? 0 : 1  ; 0=up, 1=down
+        PostMessage, 0x115, %revertDir%, 0,, ahk_id %target%
+        If (MB_Debug)
+            ToolTip, % "WHEEL_CTRL→VSCROLL (jumped " scrolledUnits " units)"
+    }
+    MB_FallbackChecked := 1
 }
```

**Add initialization** in MButton Down (after line 946):

```autohotkey
MB_FallbackChecked := 0  ; Only check fallback once per drag
```

---

### Phase 2: Configuration Consolidation

#### [MODIFY] [AutoHotkey.ahk](file:///c:/Dropbox/Projects/AHK/AutoHotkey.ahk)

Replace scattered boolean expressions (lines 856-879) with a unified config block:

```autohotkey
; === SCROLL CONFIG ===
MB_PassthroughApps := ["chrome.exe", "everything64.exe", "VmConnect.exe"]
MB_EnabledApps := ["mmc.exe", "7zFM.exe", "code.exe", "SystemInformer.exe"]
MB_ExcludedControls := ["ToolbarWindow", "ReBarWindow", "Edit", "AddressBandRoot", "statusbar", "SysHeader"]
```

Then update checks to use `HasVal()` helper:

```autohotkey
HasVal(arr, val) {
    for i, v in arr
        if (InStr(val, v))
            return true
    return false
}

HasNativeScroll := HasVal(MB_PassthroughApps, ahk_exe)
IsAllowedApp := HasVal(MB_EnabledApps, ahk_exe)
IsExcludedRegion := HasVal(MB_ExcludedControls, MBScroll_CtrlClassNN)
```

---

### Phase 3: Dead Code Removal

#### [MODIFY] [AutoHotkey.ahk](file:///C:/Dropbox/Projects/AHK/AutoHotkey.ahk)

1. **Remove commented SCROLLBAR code** (lines 1010-1013)
2. **Remove unused globals from line 848**:
   - `MB_ScrollbarHwnd`
   - `MB_ScrollMin` (not visible but referenced in summary.md)
   - `MB_ScrollMax`

---

### Phase 4: Full Fallback Chain (Deferred)

> [!NOTE]
> Phase 4 is more complex and should be done after validating Phases 1-3 work correctly. It requires:
>
> - UIA → WHEEL fallback: Detect when SetScrollPercent fails
> - WHEEL → WHEEL_CTRL fallback: Detect when window doesn't respond to wheel
> - Remove all hardcoded method selectors

---

## Verification Plan

### Manual Testing

Since this is an AHK script with UI interaction, manual testing is required:

1. **SystemInformer (WHEEL_CTRL test)**
   - Open SystemInformer
   - Middle-click drag on the process list
   - Should scroll smoothly without fallback (SI scrolls 1 line per message)
   - Check tooltip if `MB_Debug := 1` shows "WHEEL_CTRL"

2. **Explorer navigation tree (VSCROLL fallback test)**
   - Open Explorer with many folders in navigation pane
   - Middle-click drag on nav tree (SysTreeView32)
   - Should directly use VSCROLL via `UseVScroll`
   - Check tooltip if `MB_Debug := 1` shows "VSCROLL"

3. **Test control without smooth scroll (fallback trigger)**
   - Find a control that scrolls 3 lines per wheel message
   - Middle-click drag → should briefly show WHEEL_CTRL then switch to VSCROLL
   - The jump should be imperceptible (reverted immediately)

### Debug Output

Set `MB_Debug := 1` at line 843 to enable tooltips showing:

- Current method being used
- Scroll position deltas
- Fallback transitions
