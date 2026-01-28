# MButton Scroll Improvements

## Phase 1: GetScrollPos-based Fallback Detection ✅
- [x] Add `GetScrollPos` helper using DllCall
- [x] Modify WHEEL_CTRL to query position before/after sending message
- [x] Detect >1 line jumps (~40 units) and switch to VSCROLL
- [x] Revert position immediately on fallback (invisible to user)

## Phase 2: Configuration Consolidation ✅
- [x] Replace scattered boolean expressions with config arrays
- [x] Create `MB_PassthroughApps`, `MB_EnabledApps`, `MB_ExcludedControls` arrays
- [x] Update condition checks to use array lookups via `HasVal`

## Phase 3: Dead Code Removal ✅
- [x] Remove commented SCROLLBAR method
- [x] Remove unused globals: `MB_ScrollbarHwnd`, `MB_ScrollMax`, `MB_LineAccum`, `MB_LinesScrolled`

## Phase 4: Full Fallback Chain ✅
- [x] Implement UIA → WHEEL fallback detection (two-tick verification)
- [x] Implement WHEEL → WHEEL_CTRL fallback detection (GetScrollPos before/after)
- [x] Remove hardcoded `ForceUIA`, `UseWheel`, `UseWheelCtrl`, `UseVScroll` flags
- [x] Add `HasWin32Scrollbar()` helper function
- [x] Fix MB_Debug placement (moved to auto-execute section, line 19)

## Phase 5: Universal App Support ✅
- [x] Remove `MB_EnabledApps` whitelist and `MB_PassthroughApps` — no hardcoded app lists
- [x] Remove `IsAllowedApp`, `IsAllowedContent`, `HasNativeScroll`, `ShouldScroll` variables
- [x] Always pass through MButton Down — detect native scroll at runtime
- [x] Add multi-signal native scroll probe (HCURSOR handle + GetScrollPos + UIA GetVerticalScrollPercent, 5 ticks/50ms)
- [x] If native scroll detected → stay passive (`MB_Disabled := 1`)
- [x] If no native scroll → engage custom scroll with UIA-first fallback chain
- [x] TreeView → direct VSCROLL (skip probe, never has native MButton scroll)
- [x] Keep `MB_ExcludedControls` for toolbars, edit boxes, headers
- [ ] Test across apps: Explorer, VS Code, SystemInformer, mmc.exe, 7zFM, Chrome, etc.
- [ ] Set `MB_Debug := 0` after verification

## Phase 6: Deferred MButton Down for Explorer ✅
- [x] Defer `SendInput, {Blind}{MButton Down}` for Explorer (`CabinetWClass`)
- [x] Prevents navbar middle-click opening new tab during scroll intent
- [x] Prevents Explorer selection mode from blocking UIA `SetScrollPercent`
- [x] On MButton Up without scroll: synthesize full `{Blind}{MButton}` click
- [x] Non-Explorer apps still get immediate passthrough for native detection
- [x] Restore Win32 cross-validation for UIA verification (deferred down fixes the root cause)

## Phase 7: Native Probe Movement Gate ✅
- [x] Replace 3px + 5-tick countdown with 8px movement gate (matches custom scroll threshold)
- [x] Signals 2 & 3 check after 3px (filters jitter); probe concludes at 8px
- [x] Signal 1 (cursor change) still checks every tick from 0px
- [x] Eliminates sequential bottleneck: custom scroll fires immediately when probe concludes
- [x] Update summary.md native probe description

## Phase 8: Native Scroll Taming (UIA Override)
- [ ] For apps detected as native scroll (hcursor change), check if UIA ScrollPattern is available
- [ ] If UIA available: override native scroll with UIA `SetScrollPercent` for smooth, predictable scrolling
- [ ] Use existing scroll curve (power-curve acceleration) instead of app's native scroll speed
- [ ] Preserve native scroll only for apps without UIA ScrollPattern
- [ ] Consider: suppress native scroll cursor icon when overriding with UIA
