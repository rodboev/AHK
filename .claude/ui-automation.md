# UI Automation (UIA) Reference

## Three-Layer Scroll Architecture

Windows Terminal exposes scroll information through three UIA layers:

| Layer | Element | Pattern (ID) | Key Properties | Methods |
|-------|---------|--------------|----------------|---------|
| 1. Container | ScrollViewer | Scroll (10004) | VerticalScrollPercent (30055), VerticallyScrollable (30058) | `SetScrollPercent()`, `Scroll()` |
| 2. Children | Items | ScrollItem (10017) | — | `ScrollIntoView()` |
| 3. ScrollBar | ScrollBar.Vertical | RangeValue (10003) | Value (30047), Min (30049), Max (30050) | `SetValue()` |

**WT scroll guard uses Layer 3** — RangeValuePattern on `ScrollBar.Vertical`. Value is in line units; normalize with `(Value - Min) / (Max - Min) * 100`.

## IUIAutomation Vtable Offsets

Source: Descolada UIAutomation library (`/home/rod/projects/UIAutomation/Lib/UIA_Interface.ahk`)

### IUIAutomation (root object)

| Offset | Method |
|--------|--------|
| 6 | `ElementFromHandle(hwnd)` → root element for a window |
| 7 | `ElementFromPoint(x, y)` → deepest visual leaf at coordinates |
| 14 | `get_ControlViewWalker()` → TreeWalker for tree traversal |
| 23 | `CreatePropertyCondition(propId, value)` → condition for FindFirst/FindAll |
| 25 | `CreateAndCondition(cond1, cond2)` → combine conditions |

### IUIAutomationElement

| Offset | Method |
|--------|--------|
| 5 | `FindFirst(scope, condition)` → first matching element |
| 6 | `FindAll(scope, condition)` → all matching elements |
| 10 | `GetCurrentPropertyValue(propId, &variant)` → read any UIA property |
| 16 | `GetCurrentPattern(patternId)` → acquire pattern interface |

### IUIAutomationTreeWalker

| Offset | Method |
|--------|--------|
| 3 | `GetParentElement(el)` → walk up |
| 4 | `GetFirstChildElement(el)` → walk down |
| 5 | `GetLastChildElement(el)` → walk down (reverse) |
| 6 | `GetNextSiblingElement(el)` → walk sideways |
| 7 | `GetPreviousSiblingElement(el)` → walk sideways (reverse) |

### IRangeValuePattern (10003)

| Offset | Method |
|--------|--------|
| 3 | `SetValue(double)` |
| 4 | `get_CurrentValue(double*)` |
| 5 | `get_CurrentIsReadOnly(int*)` |
| 6 | `get_CurrentMaximum(double*)` |
| 7 | `get_CurrentMinimum(double*)` |
| 8 | `get_CurrentLargeChange(double*)` |
| 9 | `get_CurrentSmallChange(double*)` |

### IScrollPattern (10004)

| Offset | Method |
|--------|--------|
| 3 | `Scroll(hAmount, vAmount)` — ScrollAmount enum |
| 4 | `SetScrollPercent(hPct, vPct)` — -1 = NoScroll sentinel |
| 5 | `get_CurrentHorizontalScrollPercent(double*)` |
| 6 | `get_CurrentVerticalScrollPercent(double*)` |
| 7 | `get_CurrentHorizontalViewSize(double*)` |
| 8 | `get_CurrentVerticalViewSize(double*)` |
| 9 | `get_CurrentHorizontallyScrollable(int*)` |
| 10 | `get_CurrentVerticallyScrollable(int*)` |

## UIA Property IDs (Scroll-Related)

| ID | Name | Type |
|----|------|------|
| 30003 | ControlTypePropertyId | VT_I4 |
| 30004 | LocalizedControlTypePropertyId | VT_BSTR |
| 30005 | NamePropertyId | VT_BSTR |
| 30011 | AutomationIdPropertyId | VT_BSTR |
| 30012 | ClassNamePropertyId | VT_BSTR |
| 30047 | RangeValueValuePropertyId | VT_R8 |
| 30048 | RangeValueIsReadOnlyPropertyId | VT_I4 (bool) |
| 30049 | RangeValueMinimumPropertyId | VT_R8 |
| 30050 | RangeValueMaximumPropertyId | VT_R8 |
| 30055 | ScrollVerticalScrollPercentPropertyId | VT_R8 |
| 30058 | ScrollVerticallyScrollablePropertyId | VT_I4 (bool) |

## VARIANT Structure for DllCall

```autohotkey
; VT_I4 (integer property condition)
VarSetCapacity(_var, 16, 0)
NumPut(3, _var, 0, "UShort")     ; vt = VT_I4
NumPut(value, _var, 8, "Int")    ; intVal

; VT_R8 (double, read from GetCurrentPropertyValue)
_val := NumGet(_var, 8, "Double")

; VT_BSTR (string)
_bstr := NumGet(_var, 8, "Ptr")
_str := StrGet(_bstr, "UTF-16")
```

Always call `DllCall("OleAut32\VariantInit", "Ptr", &_var)` before `GetCurrentPropertyValue` and check VT_EMPTY (vt=0).

## WT Element Hierarchy

```
Window (ElementFromHandle)
  └── ScrollViewer (Layer 1 — ScrollPattern 10004)
       ├── Items container (Layer 2 — ScrollItemPattern 10017)
       └── ScrollBar.Vertical (Layer 3 — RangeValuePattern 10003)
            ClassName=ScrollBar, Name="Vertical", AutomationId="ScrollBar"
```

**FindAll approach** (preferred): `CreatePropertyCondition(ControlType=50029)` + `FindAll(Descendants)` → iterate for Name="Vertical". Much faster than recursive TreeWalker.

**TreeWalker approach** (for Layer 1): After finding ScrollBar.Vertical, use `GetParentElement` to walk up to the ScrollViewer container.

## Empirical WT Results

- **Layer 3 (RangeValuePattern)**: Fully functional. `SetValue()` works for scroll position restoration.
- **Layer 1 (ScrollPattern)**: `VerticalScrollPercent` (30055) readable via `GetCurrentPropertyValue`. `VerticallyScrollable` (30058) status TBD — requires testing whether it's writable for scroll lock.
- **ScrollPattern::SetScrollPercent**: Not yet tested on WT. May provide direct percentage-based scroll control.
- **Native detection**: `mbutton-scroll.ahk`'s `GetCurrentPattern(10004)` acquires ScrollPattern on the control element, which works for Explorer but NOT for WT's XAML ScrollBar. WT uses RangeValuePattern (10003) on ScrollBar.Vertical instead.

## Descolada UIAutomation Library

Repository: `/home/rod/projects/UIAutomation/`

| File | Purpose |
|------|---------|
| `Lib/UIA_Interface.ahk` | Core: UIA_Base, 30 pattern classes, element/automation wrappers |
| `Lib/UIA_Constants.ahk` | All property IDs, pattern IDs, control type IDs |
| `Lib/UIA_Browser.ahk` | Browser-specific helpers (Chrome, Firefox, Edge) |
| `Examples/Example11_ScrollPatternScrollItemPattern.ahk` | Scroll pattern usage example |

**Key design**: `UIA_Base.__Vt(n)` calculates COM vtable offsets as `(n + 2) * A_PtrSize` (IUnknown has 3 methods at offsets 0-2). Pattern classes expose properties as AHK properties with getters calling vtable DllCalls.
