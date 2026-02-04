# Phase 5: Universal App Support — Implementation Plan

## Goal

Replace the whitelist-based app selection with a **default-on model**: MButton scroll works for ALL apps by default, with only a short exclusion list for apps with native smooth scroll.

Currently, `ShouldScroll` requires apps to be in `MB_EnabledApps` OR match content heuristics. Phase 5 inverts this: all apps get custom scroll unless explicitly excluded.

## File Modified
- `mbutton-scroll.ahk` (formerly inline in `AutoHotkey.ahk`)

---

## Changes

### 1. Replace App Lists (now in mbutton-scroll.ahk)

**Before:**
```autohotkey
MB_PassthroughApps := ["chrome.exe", "everything64.exe", "VmConnect.exe"]
MB_EnabledApps := ["mmc.exe", "7zFM.exe", "code.exe", "SystemInFormer.exe"]
MB_ExcludedControls := ["ToolbarWindow", "ReBarWindow", "Edit", "AddressBandRoot", "statusbar", "SysHeader"]
```

**After:**
```autohotkey
MB_ExcludedApps := ["chrome.exe", "everything64.exe", "VmConnect.exe"]
MB_ExcludedControls := ["ToolbarWindow", "ReBarWindow", "Edit", "AddressBandRoot", "statusbar", "SysHeader"]
```

- `MB_PassthroughApps` → renamed to `MB_ExcludedApps` (consistent with `MB_ExcludedControls`)
- `MB_EnabledApps` → **deleted entirely** (no longer needed)

### 2. Simplify ShouldScroll Logic (now in mbutton-scroll.ahk)

**Before:**
```autohotkey
HasNativeScroll := HasVal(MB_PassthroughApps, ahk_exe)
IsAllowedApp := HasVal(MB_EnabledApps, ahk_exe)
IsAllowedContent := InStr(VisibleText, "Tree View") or InStr(VisibleText, "FolderView") or InStr(ControlText, "ScrollBar")
IsExcludedRegion := HasVal(MB_ExcludedControls, MBScroll_CtrlClassNN) or (not MBScroll_CtrlClassNN and not (ahk_class = "Shell_TrayWnd" or ahk_class = "WorkerW"))

ShouldScroll := !HasNativeScroll and (IsAllowedApp or IsAllowedContent) and !IsExcludedRegion
```

**After:**
```autohotkey
IsExcludedApp := HasVal(MB_ExcludedApps, ahk_exe)
IsExcludedRegion := HasVal(MB_ExcludedControls, MBScroll_CtrlClassNN) or (not MBScroll_CtrlClassNN and not (ahk_class = "Shell_TrayWnd" or ahk_class = "WorkerW"))

ShouldScroll := !IsExcludedApp and !IsExcludedRegion
```

**Removed variables:**
- `HasNativeScroll` — replaced by `IsExcludedApp`
- `IsAllowedApp` — no longer needed (all apps allowed by default)
- `IsAllowedContent` — no longer needed (content heuristics were a workaround for the whitelist)

### 3. Method Selection (now in mbutton-scroll.ahk) — NO CHANGES

The existing method selection from Phase 4 is **unchanged**. All non-TreeView apps try UIA first:

```
TreeView → VSCROLL (direct)
Else → Try UIA → fall to WHEEL on failure
```

The UIA probe is cheap (one COM call at MButton-down) and the two-tick verification handles failures gracefully (~20ms cascade). Every app benefits from trying UIA first — apps like mmc.exe get fractional % scrolling, and apps that don't support UIA fall through to WHEEL automatically.

### 4. Remove `WinGetText` and `ControlList` Queries (now in mbutton-scroll.ahk)

```autohotkey
; REMOVE — only needed for IsAllowedContent heuristics
WinGetText, VisibleText, ahk_id %MBScroll_Win%
WinGet, ControlText, ControlList, ahk_id %MBScroll_Win%
```

These are only used by `IsAllowedContent` which is being removed. `WinGetText` and `ControlList` are expensive calls (especially on complex windows), so removing them improves MButton-down responsiveness.

---

## Expected Behavior by App

| App | Old Behavior | New Behavior |
|-----|-------------|--------------|
| Explorer file list | Whitelisted via content heuristic → UIA | Default → UIA (via fallback chain) |
| Explorer TreeView | Whitelisted via content heuristic → VSCROLL | Default → VSCROLL (TreeView check) |
| VS Code | Whitelisted in MB_EnabledApps → UIA → WHEEL | Default → UIA → WHEEL (no change) |
| SystemInformer | Whitelisted in MB_EnabledApps → UIA → WHEEL → WHEEL_CTRL | Default → UIA → WHEEL → WHEEL_CTRL (no change) |
| mmc.exe | Whitelisted in MB_EnabledApps → UIA | Default → UIA (no change) |
| 7zFM | Whitelisted in MB_EnabledApps → UIA → cascades | Default → UIA → cascades (no change) |
| Notepad | **Not whitelisted — no custom scroll** | **Default → UIA → cascades (NEW)** |
| Any new app | **Not whitelisted — no custom scroll** | **Default → UIA → cascades (NEW)** |

All apps follow the same UIA-first fallback chain. The only difference is the entry gate: previously apps needed to be whitelisted; now all apps enter by default.

---

## Fallback Chain (unchanged from Phase 4)

```
MButton Down
    ├── TreeView? ──────────────────→ VSCROLL (direct)
    └── All other apps ─────────────→ UIA probe → WHEEL → WHEEL_CTRL → VSCROLL
```

The method selection logic is identical to Phase 4. The only Phase 5 change is removing the whitelist gate — all apps now enter the fallback chain instead of only whitelisted ones.

---

## Verification (Manual Testing)

1. **Explorer file list**: MButton drag → smooth UIA scroll (unchanged)
2. **Explorer nav tree**: MButton drag → VSCROLL (unchanged)
3. **VS Code**: MButton drag → WHEEL scroll (unchanged)
4. **SystemInformer**: MButton drag → WHEEL → WHEEL_CTRL cascade (unchanged)
5. **mmc.exe Services**: MButton drag → WHEEL → verify it cascades to a working method
6. **Notepad**: MButton drag → **NEW**: should now scroll (WHEEL or cascade)
7. **Any random app**: MButton drag → should scroll via cascade
8. **Chrome**: MButton drag → passthrough (excluded, native scroll)
9. **Excluded controls**: Toolbar, address bar, etc. → passthrough (unchanged)

Enable `MB_Debug := 1` to see method selection and fallback transitions.
After verification, set `MB_Debug := 0`.
