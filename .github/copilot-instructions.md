<!-- Auto-generated guidance for AI coding agents working on this repo -->
# Copilot instructions — AutoHotkey.ahk repository

Purpose
- This repo is a single, primary AutoHotkey script (`AutoHotkey.ahk`) that implements advanced multi-method middle-button drag-scrolling. Support libraries and examples live under `includes/` and `includes/Dock/`.
- See the design rationale and architecture summary in `summary.md` for the detailed motivation behind the multi-method approach.

Quick architecture overview
- `AutoHotkey.ahk`: the monolithic entrypoint and orchestration layer (core hotkeys, `UserRun`, multi-method MButton drag-scrolling).
  - Key region: the MButton drag-scroll implementation (uses UI Automation, WM_MOUSEWHEEL, WM_VSCROLL). Example reference: [AutoHotkey.ahk](AutoHotkey.ahk#L843-L1054).
- `includes/`: community-contributed libraries (utilities like `_Struct.ahk`, `Acc.ahk`, `ini.ahk`) and optional modules (e.g., `Dock.ahk`, `HoverScroll.ahk`). These are usually referenced for inspiration rather than being tightly coupled to the core script.

What agents should know before editing
- Preserve the single-script mental model: feature entrypoints are registered as hotkeys inside `AutoHotkey.ahk`. When adding features prefer either:
  - Extending `AutoHotkey.ahk` (for hotkeys and orchestration), or
  - Adding a new module in `includes/` and keeping it self-contained.
- Respect existing naming conventions: leading underscores denote library-like utilities (e.g., `_Struct.ahk`). File names often contain spaces and version markers—do not rename without reason.
- Avoid introducing external non-AHK dependencies. The project relies on Win32 and UIA techniques implemented in AHK; prefer in-script solutions.

Run / debug workflows
- Run locally by launching `AutoHotkey.ahk` with the AutoHotkey interpreter (double-click in Explorer or via PowerShell):
```powershell
start "" "C:\Program Files\AutoHotkey\AutoHotkey.exe" AutoHotkey.ahk
```
- Use the AHK tray icon and `ListLines`, `Pause`, or `Reload` to inspect hotkey behavior. Insert short `ToolTip`/`MsgBox` or `OutputDebug` calls for quick checks.
- To validate MButton drag-scrolling changes, test in Windows Explorer and an Electron-based app (e.g., VS Code), as the README documents differences and fallback behaviors.

Repository conventions & patterns
- Most logic is implemented with timer-based acceleration and message-synthesis (WM_MOUSEWHEEL/WM_VSCROLL). Follow the existing pattern when adding similar features—use timer ticks for smoothing rather than immediate per-event bursts.
- `UserRun` is the canonical helper for process execution and elevation; reuse it for launching elevated utilities to keep behavior consistent.
- Many includes are intentionally left as reference code. If you extract common utilities into `includes/`, keep them backward-compatible and document their API briefly at the top of the file.

Integration points
- UI Automation (UIA/COM) is used where normal mouse messages are insufficient—changes touching UIA usage can affect responsiveness. Check `AutoHotkey.ahk` and `includes/` files that reference UIA before edits.
- Hotkey names and global modifiers are defined centrally in the main script—avoid duplicating top-level hotkey bindings in includes.

Editing guidance & PR expectations
- Keep changes minimal and focused. Provide a short rationale in the PR description referencing affected hotkeys or timers.
- If adding a new include, update `README.md` or `summary.md` with a one-line description of purpose.
- No automated tests exist; include simple manual verification steps in the PR (what to run and what outcome to expect).

If unsure
- Read `summary.md` then inspect the relevant region of `AutoHotkey.ahk` before making edits.
- Ask for clarification and include suggested manual test steps with the change.

---
Please review these instructions and tell me if you'd like any section expanded or more file-specific examples added.
