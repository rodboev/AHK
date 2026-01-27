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

## Phase 5: Universal App Support (planned)
- [ ] Remove `MB_EnabledApps` whitelist — scroll works for ALL apps by default
- [ ] Rename `MB_PassthroughApps` → `MB_ExcludedApps`
- [ ] Simplify `ShouldScroll` to: `!IsExcludedApp and !IsExcludedRegion`
- [ ] Remove `IsAllowedApp`, `IsAllowedContent`, `HasNativeScroll` variables
- [ ] Method selection unchanged: UIA-first fallback chain for all apps, TreeView → VSCROLL
- [ ] No method selection code changes needed — only the ShouldScroll gate changes
- [ ] Test across apps: Explorer, VS Code, SystemInformer, mmc.exe, 7zFM, Notepad, etc.
- [ ] Set `MB_Debug := 0` after verification
