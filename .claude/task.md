# MButton Scroll Improvements

## Phase 1: GetScrollPos-based Fallback Detection
- [x] Add `GetScrollPos` helper using DllCall
- [x] Modify WHEEL_CTRL to query position before/after sending message
- [x] Detect >1 line jumps (~40 units) and switch to VSCROLL
- [x] Revert position immediately on fallback (invisible to user)

## Phase 2: Configuration Consolidation
- [x] Replace scattered boolean expressions with config arrays
- [x] Create `MB_PassthroughApps`, `MB_EnabledApps`, `MB_ExcludedControls` arrays
- [x] Update condition checks to use array lookups via `HasVal`

## Phase 3: Dead Code Removal
- [x] Remove commented SCROLLBAR method
- [x] Remove unused globals: `MB_ScrollbarHwnd`, `MB_ScrollMax`, `MB_LineAccum`, `MB_LinesScrolled`

## Phase 4: Full Fallback Chain (Future)
- [ ] Implement UIA → WHEEL fallback detection
- [ ] Implement WHEEL → WHEEL_CTRL fallback detection
- [ ] Remove hardcoded `ForceUIA`, `UseWheel`, `UseWheelCtrl` flags
