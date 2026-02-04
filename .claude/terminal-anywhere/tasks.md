# Terminal Anywhere — Tasks

## Security Fixes (Feb 2026)

- [x] **`_psCmdEsc` quoting fix**: Escape inner single quotes (`'` → `''`) before embedding `psCmd` in `-ArgumentList '...'` — prevents early string termination when `psCmd` contains single-quoted arguments like `'wt'`
- [x] **SYSTEM PATH resolution via `FindInPath`** (`^!+F10`): Resolve `wt.exe` to its full absolute path before passing to `ti.exe`, since the SYSTEM account's PATH lacks user-installed program directories
- [x] **WMI command-line exe replacement** (`^+=`): Use `GetExePath().path` + `RegExReplace` to swap the WMI command line's executable portion with the full resolved path before launching via `ti.exe`

## Module Extraction (Feb 2026)

- [x] **Extract to `terminal-anywhere.ahk`**: Move F10 hotkeys (`F10::`, `+F10::`, `^!+F10::`) from `AutoHotkey.ahk` to dedicated module file
- [x] **Add `#Include`**: Added `#Include %A_ScriptDir%\terminal-anywhere.ahk` to main script includes section
- [x] **Update CLAUDE.md**: Architecture table, key regions (section-name refs replacing line numbers), core features, related documentation
- [x] **Create `.claude/terminal-anywhere/`**: Architecture plan and task tracking documents
