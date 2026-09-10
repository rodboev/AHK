# AHK, Alacritty, and Herdr: how the three fit together

Read this before changing any keybinding, mouse binding, or launch path in the terminal stack. Most of the bindings look independent and are not. A change in one file usually silently disables something in another.

## The stack

```
AutoHotkey (Windows-wide keyboard and mouse hooks)
  -> Alacritty (window, font, terminal emulation, its own key/mouse bindings)
    -> Herdr (multiplexer, runs as Alacritty's shell program)
      -> cmd, Codex, Claude Code (pane processes)
```

Every keypress travels down that stack. Each layer can eat the key before the next one sees it. AutoHotkey decides first, Alacritty second, Herdr third, the pane process last. Understanding which layer eats a key is the whole game.

Herdr is a background server plus a client. The client is what runs inside Alacritty. The server owns the panes and keeps them alive when the client dies, the same role tmux plays.

## The five files that control behavior

| File | Owns |
|---|---|
| file:///C:/Dropbox/Projects/AHK/AutoHotkey.ahk | Global hotkeys, paste normalization, right click zones, DPI scale, module includes |
| file:///C:/Dropbox/Projects/AHK/herdr-anywhere.ahk | F10 family, Escape, Ctrl+Tab, Win+E, Herdr client detection |
| file:///C:/Dropbox/Projects/AHK/herdr-new-window.py | Every F10 window: workspace creation, the pipe proxy, running the command |
| file:///C:/Users/Rod/AppData/Roaming/alacritty/alacritty.toml | Alacritty key and mouse bindings, shell program, window size |
| file:///C:/Users/Rod/AppData/Roaming/herdr/config.toml | Herdr direct bindings, prefix commands, theme, default shell |

Two more files participate: file:///C:/Dropbox/Projects/AHK/terminal-anywhere.ahk supplies helper functions that herdr-anywhere calls, and file:///C:/Users/Rod/.codex/config.toml holds the Codex keymap that competes for the same keys.

## Key routing, layer by layer

### Keys AutoHotkey takes first

These never reach Alacritty in their original form.

| Key | Where | What happens |
|---|---|---|
| F10, Ctrl+F10, Shift+F10, Ctrl+Shift+F10 | Everywhere except WindowsTerminal.exe | Launch or extend a Herdr workspace |
| Esc | Alacritty active | Calls `pane.send_keys` on the API socket and suppresses the physical key |
| Ctrl+Tab, Ctrl+Shift+Tab | Alacritty active | Rewritten to Ctrl+Down and Ctrl+Up |
| F2 | Alacritty active | Passed through, then Ctrl+U clears Herdr's prefilled workspace name |
| Win+E | Everywhere | Opens Explorer at the focused pane's directory |
| Ctrl+V | Alacritty active | Clipboard normalized or image converted, then synthetic Ctrl+V |
| Right click, Ctrl+right, Shift+right, Shift+left | Over an Alacritty window | Rewritten, see the mouse section |

### Keys Alacritty converts into byte sequences

Alacritty has no idea what Herdr is. It only emits bytes. These bindings exist purely so Herdr can recognize the key.

| Key | Bytes sent | Why |
|---|---|---|
| Ctrl+Shift+C | `\u001B[99;6u` | CSI-u so Herdr can match `ctrl+shift+c` |
| Ctrl+Shift+D | `\u001B[100;6u` | CSI-u so Herdr can match `ctrl+shift+d` |
| Alt+Shift+= (scancode 13) | `\u0002v` | Herdr prefix, then v |
| Alt+Shift+- (scancode 12) | `\u0002-` | Herdr prefix, then minus |
| Ctrl+Shift+= (scancode 13) | `\u0002c` | Herdr prefix, then c |
| Ctrl+Shift+Backspace | `\u0002X` | Herdr prefix, then Shift+X |
| Shift+F1 through Shift+F9 | `\u001B1` through `\u001B9` | Alt+1 through Alt+9, which Herdr maps to tabs |
| Shift+Enter | `\u001B\r` | Escape then carriage return, the only newline that works everywhere |
| Ctrl+V | Paste action |  |
| F11 | Fullscreen | Alacritty owns this, Herdr never sees it |

The scancodes matter. Alacritty key names `Equals` and `Minus` do not match when Shift is held. Physical scancodes 13 and 12 do. Using the names silently produces a binding that never fires.

### Keys Herdr takes before the pane sees them

Everything in `[keys]` in Herdr's config is a direct binding. The pane process never receives these.

Ctrl+Up, Ctrl+Shift+Tab (previous workspace). Ctrl+Down, Ctrl+Tab (next workspace). Ctrl+Left, Ctrl+Right (previous and next tab). Ctrl+T, Ctrl+Shift+= (new tab). Ctrl+W, Ctrl+F4 (close pane). Ctrl+N (new workspace). F2 (rename workspace). Ctrl+Shift+D, Alt+Shift+= (split vertical). Ctrl+Shift+C, Alt+Shift+- (split horizontal). Ctrl+Shift+arrows (focus pane). Alt+1 through Alt+9 (switch tab).

Plus the prefix, Ctrl+B, which is Herdr's default and is not set in the config. Herdr swallows Ctrl+B and waits for the next key.

Plus one custom command: Esc runs `herdr pane send-keys %HERDR_ACTIVE_PANE_ID% esc`.

## Interdependency chains

Each of these is a real coupling. Changing the left side breaks the right side.

### 1. Herdr's prefix is Ctrl+B, and four Alacritty bindings hardcode it

`\u0002` is the byte for Ctrl+B. Alt+Shift+=, Alt+Shift+-, Ctrl+Shift+=, and Ctrl+Shift+Backspace all send that byte followed by a command letter.

If you change Herdr's prefix, those four bindings stop working and must be rewritten with the new prefix byte. If you want Ctrl+B delivered to Claude Code so it can background a task, you cannot get it without changing Herdr's prefix, because Herdr eats Ctrl+B before any pane sees it. Changing the prefix to Ctrl+A means rewriting the four sequences to `\u0001`.

The pane-facing alternative is to leave the prefix alone and give Claude Code a different key that Herdr does not claim. Claude Code already ships one: `task:background` is bound to both Ctrl+B and the chord Ctrl+X Ctrl+B, and the docs say the chord exists specifically to avoid the tmux prefix collision. Nothing needs configuring. If a single keystroke is wanted instead, add a rebind in `~/.claude/keybindings.json` under the `Task` context rather than touching Herdr.

Other Claude Code defaults this stack intercepts: Ctrl+Shift+C (`selection:copy`) goes to Herdr's split_horizontal, and Ctrl+T (`app:toggleTodos`) to Herdr's new tab. Ctrl+Shift+- (`chat:undo`) is free, because close tab sits on Ctrl+Shift+Backspace.

### 2. Codex and Claude compete with Herdr for the same keys

Codex's config sets `copy = "ctrl-shift-c"`. Herdr claims Ctrl+Shift+C for split_horizontal, so Codex never receives it inside Herdr. Codex's transcript toggle sits on Ctrl+O for the same reason: Herdr owns Ctrl+T.

Before assigning any Ctrl or Ctrl+Shift key to Herdr, check what the agent TUIs already use.

### 3. AutoHotkey's Ctrl+Tab depends on Herdr's Ctrl+Down binding

`HerdrAnywhereSendWorkspaceStep()` in file:///C:/Dropbox/Projects/AHK/herdr-anywhere.ahk rewrites Ctrl+Tab into Ctrl+Down. That only works because Herdr's config maps `next_workspace` to `ctrl+down`. Removing the Ctrl+Down alias from Herdr's config kills Ctrl+Tab as a side effect. The `ctrl+tab` entry in Herdr's config is a second, independent path and does not cover the AutoHotkey route.

### 4. The em dash binding is disabled inside Alacritty on purpose

file:///C:/Dropbox/Projects/AHK/AutoHotkey.ahk (line 137) wraps the Alt+Shift+minus em dash hotkey in `#If !WinActive("ahk_exe alacritty.exe")`. Without that guard, AutoHotkey would eat Alt+Shift+minus and Alacritty would never send `\u0002-`, so split horizontal would break. Removing the guard breaks the split. Adding a new global AutoHotkey binding on any key Alacritty needs has the same effect.

### 5. Herdr must be a direct child process of Alacritty

`HerdrAnywhereGetClient()` in file:///C:/Dropbox/Projects/AHK/herdr-anywhere.ahk finds processes whose parent is the Alacritty PID and accepts only a single `herdr.exe` child, then parses that child's command line for `--session` and `--remote`.

It uses `GetChildProcesses()` and `GetProcessCommandLine()` in file:///C:/Dropbox/Projects/AHK/processes.ahk, a Toolhelp snapshot plus a PEB read rather than WMI, at roughly 17ms per lookup against WMI's 112ms. `GetProcessCommandLine()` reads `RTL_USER_PROCESS_PARAMETERS.CommandLine` at offset 0x70 on x64, the same walk `GetProcessCwd()` does at 0x38 for the working directory.

Everything keyed on client detection depends on this: Escape, Ctrl+Tab, F10 inside a client, Win+E, and the admin and remote distinctions. Insert any wrapper between Alacritty and Herdr, a launcher script, a session-name shim, a virtualenv Python stub, and all of it silently falls back to passthrough. Keep cmd and conhost wrappers out of the F10 path for the same reason.

Corollary: `[terminal] shell = { program = "herdr.exe" }` in Alacritty's config is load-bearing. Change it and both the detection and the F10 launch path stop working.

### 6. herdr-anywhere.ahk cannot stand alone

It calls `GetExplorerPath()`, `GetTerminalDir()`, `GetTitleBarPath()`, and `_ActivateExplorerAt()`, all defined in file:///C:/Dropbox/Projects/AHK/terminal-anywhere.ahk. It also calls `FindInPath()` and `UserRun()` from file:///C:/Dropbox/Projects/AHK/processes.ahk. Deleting terminal-anywhere.ahk because Windows Terminal is retired would break F10, Win+E, and the context directory lookup.

The two modules do not fight over F10. terminal-anywhere scopes its F10 family to `#IfWinActive ahk_exe WindowsTerminal.exe` and herdr-anywhere scopes its to `#If !WinActive("ahk_exe WindowsTerminal.exe")`. Widening either context creates a duplicate hotkey, and the earlier `#Include` wins.

### 7. Include order decides which duplicate hotkey wins

file:///C:/Dropbox/Projects/AHK/AutoHotkey.ahk includes modules at lines 1103 to 1108 in this order: processes, terminal-anywhere, extended-spy, mbutton-drag, window-spawning, herdr-anywhere.

Both extended-spy.ahk (line 28) and herdr-anywhere.ahk (line 13) bind `$Esc`. Extended Window Spy is included first, so when the spy is open its Escape wins even in Alacritty. That is the intended behavior. Reordering the includes changes it.

### 8. Escape has two independent implementations

AutoHotkey intercepts Escape in Alacritty and calls Herdr over the API socket, suppressing the physical key. Herdr's config has its own `esc` custom command that does the same thing. Both exist because they cover different cases.

- Local client detected: the AutoHotkey path runs, Herdr's config binding never fires.
- Remote or unidentified client: AutoHotkey sends `{Blind}{Esc}` through, and Herdr's config binding handles it.
- Remote attach: Herdr excludes local custom command bindings from remote sessions, so neither path is guaranteed. Escape over a remote connection is untested.

Removing either one leaves a gap. The AutoHotkey path costs about 15ms per press and spawns no process.

### 9. Right click zones are geometry, not configuration

Herdr has no setting for "capture right click only in this region." The zone split lives entirely in AutoHotkey: 225 logical pixels from the left edge and 50 logical pixels from the top, both multiplied by the DPI scale sampled once at script load in `GetAlacrittyDpiScale()`.

Inside those zones the click reaches Herdr and opens its menu. Outside them AutoHotkey converts the click into a normalized paste. Changing Alacritty's font size or padding moves Herdr's sidebar and tab strip, so the pixel constants need to move with it. DPI is read once, so moving Alacritty to a monitor with a different scale requires an AutoHotkey reload.

`AlacrittyWindowAtMouse()` in file:///C:/Dropbox/Projects/AHK/AutoHotkey.ahk (line 942) exists because the window under the cursor sometimes reports as `herdr.exe` rather than `alacritty.exe`. It falls back to a geometric search over all Alacritty windows.

### 10. Paste is three separate paths that must stay consistent

1. Image on clipboard: `ConvertClipboardImageToFile()` writes `%TEMP%\clipboard_paste.png`, pastes the path, deletes the file.
2. Text on clipboard: `PasteNormalizedClipboard()` converts every line ending to a single CR, pastes, then restores the original clipboard including formats.
3. Right click outside the Herdr menu zones: same as above, but activates the Alacritty window under the cursor first, so a right click from Chrome pastes into the terminal instead of opening Herdr's menu.

The CR normalization is not cosmetic. Alacritty forwards bracketed paste text almost unchanged, so CRLF arrives as both characters and produces doubled blank lines. Bare LF and bare CR each fail in a different way: bare CR reads as Enter and submits the message in Codex. Windows Terminal does this conversion internally, which is why the same paste behaves differently there.

Changing the normalization character reintroduces either the doubled lines or the accidental submit.

### 11. F10 has two paths

`HerdrAnywhereLaunch()` in file:///C:/Dropbox/Projects/AHK/herdr-anywhere.ahk branches once.

| Situation | Path |
|---|---|
| Pressed inside a Herdr client | Sends Ctrl+N to that client, waits for Ctrl release, types the command |
| Anywhere else | Launches the Python helper with `--cwd`, and `--command` and `--session` when set |

AutoHotkey works out the context directory and launches the helper. It does not probe for a running server, create workspaces, or run commands in panes. Put that logic in the helper, not here.

The Ctrl release wait exists because sending text while Ctrl is physically down produces literal `codex{Enter}` in the pane. terminal-anywhere.ahk solves the same problem the same way. That path types into the pane, so it holds a 3 second reentrancy guard; two overlapping presses would interleave keystrokes. The guard expires rather than using `Try`/`Finally`, for two reasons: inside a `Try` block AutoHotkey turns every ErrorLevel-setting command into a throw, and a press that dies mid-flight would otherwise wedge F10 for good.

The admin session runs the helper elevated, since the admin server only answers an elevated caller. `UserRun`'s `elevate` sentinel handles that, and AutoHotkey is already admin so no UAC prompt appears. To query that server from a normal shell, use `nircmd elevate herdr.exe --session admin <args>` and approve the prompt.

### 11a. Herdr's API socket

`HerdrApiCall()` talks to `%APPDATA%\herdr\herdr.sock` (or `sessions\<name>\herdr.sock`) directly. The protocol is newline-delimited JSON over a named pipe, one request line in, one response line out:

```
{"id":"ahk-1","method":"pane.list","params":{}}
```

Methods come from `herdr api schema --json`, under `schemas.request`, and use dots: `pane.list`, `pane.send_keys`, `workspace.create`, `workspace.focus`. Reads poll with `PeekNamedPipe` against a 5 second deadline rather than blocking, so a wedged server cannot freeze AutoHotkey.

`HerdrApiLastError` carries the Win32 code: 2 means no server, 5 means the pipe belongs to a different token (an unelevated caller reaching for the admin session), 1460 means timed out. Treat 5 as "unreachable", never as "absent". A denied pipe usually has live windows behind it, and acting as if no server exists is what launches a duplicate client onto a shared session and freezes every other window.

A call costs about 15ms and spawns nothing. AutoHotkey spawns no processes for Herdr except the helper itself.

### 12. The Python helper owns window creation

Herdr sizes a tab to whatever client last focused it. When a new small Alacritty window attaches to the shared session and lands on the current workspace, every other window displaying that workspace reflows to the small size for a second or two. Avoiding that is why the helper exists.

file:///C:/Dropbox/Projects/AHK/herdr-new-window.py connects to `%APPDATA%\herdr\herdr-client.sock` as a client, creates the workspace with `--no-focus`, holds the old tab's exact dimensions during setup, focuses the new workspace on its own connection only, then launches Alacritty with `HERDR_CLIENT_SOCKET_PATH` pointed at a private proxy pipe. It relays bytes both ways for the life of that window and exits when the window closes.

`cold_start()` handles the case where that socket does not exist. With no server there is no other window to protect, so it launches Alacritty plainly, waits for a focused pane, runs the command and exits. No proxy, no lingering process. A socket that exists but cannot be opened, denied or busy, is not a cold start: the helper raises rather than launching a duplicate onto a session that may have live windows.

Costs and constraints:

- One background `pythonw.exe` per F10 window, and none at all for a cold start.
- Reads and writes must use independent overlapped operations. Share one and a blocking read starves the writes, which freezes typing, paste and `workspace.focus`.
- `pipe_io()` confirms every zero-byte transfer with `GetOverlappedResult`, because an overlapped handle can complete a read synchronously and leave `lpNumberOfBytesRead` unset. `relay()` retries a bare zero three times, since a closed peer raises `ERROR_BROKEN_PIPE` instead. Drop either guard and the relay dies while the window stays open, leaving a window that renders nothing and accepts nothing. Tests in file:///C:/Dropbox/Projects/AHK/tests/test_herdr_new_window.py
- It strips `HERDR_*` from the inherited environment so only that Alacritty child gets the override.
- It requires Herdr to advertise `workspace.focus` and `client_shell.surface.set` on its endpoint protocol. A Herdr update that changes the protocol version, the socket path, or the frame format breaks it.
- It logs to `%TEMP%\AHK_Debug.log` as `herdr-new-window`, gated by `Debug.Log["herdr-new-window"]` and passed down as `--log <path>`. Each line is appended and the file closed again, because AutoHotkey truncates that log at startup and a held handle would block it. A fatal launch failure writes regardless of the toggle.

All of this becomes unnecessary if Herdr gains a way to attach a new client directly to a chosen workspace without focusing existing clients. The installed build has no such option.

### 13. Window spawning is mostly delegated to DisplayFusion

`WindowSpawningEnabled := 1` with `WindowSpawningSpecialOnly := 1` in file:///C:/Dropbox/Projects/AHK/AutoHotkey.ahk (lines 39 and 40) limits the AutoHotkey module to Run dialogs, the Start and Search overlay, and owned `#32770` dialogs. New Alacritty windows are positioned by DisplayFusion, not by this script. If an F10 window lands on the wrong monitor, look at DisplayFusion first.

## Facts established by testing, worth not rediscovering

**Newlines.** Of thirteen encodings tested, only two work in both Codex and Claude Code: `\u001B\r` (Escape then CR) and `\u001B[13;2u` (CSI-u Shift+Enter). CSI-u submits rather than inserting in Claude Code, so Shift+Enter uses `\u001B\r`. Raw `\n` queues in the console input buffer and flushes all at once on Enter, which looks like the newline was ignored until it suddenly is not. Ctrl+J works in Windows Terminal because Windows Terminal preserves it as a Win32 key event with the virtual key and modifier intact. Alacritty sends only byte `0x0A`, so the receiving program sees an LF with no Ctrl+J identity.

**Unicode.** Bullets and box drawing characters paste correctly into plain Alacritty and disappear in Herdr. The AutoHotkey wrapper is not at fault; it writes UTF-16 `CF_UNICODETEXT` and only touches line endings. This is a Herdr Windows input path problem with open reports upstream. `herdr pane send-text` bypasses the interactive key path if faithful transfer matters.

**Right click.** Herdr enables terminal mouse reporting, so Alacritty forwards clicks as escape sequences instead of running its own `action = "Paste"`. That is why plain Alacritty pastes on right click and Herdr shows a menu. Herdr's documented escape hatch is Shift+right click, but AutoHotkey intercepts that first and sends an unmodified click, so both Ctrl+right and Shift+right open the menu.

**Multi-window sizing.** One shared session across several windows means shared tab sizes. Herdr documents last-focus-wins; in practice the smallest window tends to win. Separate named sessions give independent sizing at the cost of losing a single unified workspace list. This setup keeps one shared session. Upstream discussion 651 tracks the request.

**Config reload behavior.** Herdr reloads its config live, and touching the file is often enough to fix keybindings that went stale after a restart. Bindings can therefore stop and start working with no code change at all. When something Herdr-side stops responding, touch its config or run `herdr server reload-config` before debugging anything else.

## Before changing a binding

1. Name the layer that should receive the key. AutoHotkey, Alacritty, Herdr, or the pane process.
2. Check whether a layer above it already claims the key. AutoHotkey guards in `#If` blocks, Alacritty's `[keyboard] bindings`, Herdr's `[keys]`, the Codex or Claude keymap.
3. If the key must reach a pane process, confirm Herdr does not claim it and that no Alacritty binding rewrites it.
4. If the key must reach Herdr, confirm Alacritty encodes it in a form Herdr recognizes. Modified keys usually need CSI-u or a prefix sequence.
5. If it involves the Ctrl+B prefix, list the four Alacritty sequences that hardcode `\u0002` and update them together.
6. Reload the right things. AutoHotkey with Shift+Alt+R. Herdr reloads its own config, and `herdr config check` then `herdr server reload-config` confirms it. Alacritty live reloads most settings but keyboard bindings usually need a restart.

`herdr --default-config` prints every action name with its default binding. Use it instead of guessing or reading the website. Function keys and ctrl+letter are the direct-binding forms Herdr calls most reliable; alt and punctuation with modifiers depend on the terminal.
7. Enable `Debug.Log["herdr-anywhere"]` and `Debug.Log["herdr-new-window"]` in file:///C:/Dropbox/Projects/AHK/AutoHotkey.ahk (lines 30 and 31). Both write to `%TEMP%\AHK_Debug.log`, tagged by module name.

`herdr-anywhere` events: `open-window`, `launch-reentrant`, `api-timeout`, `escape`, `escape-passthrough`, `workspace`.

`herdr-new-window` events: `no-server`, `cold-start`, `cold-start-no-pane`, `prepared`, `attached`, `relay-stopped`, `relay-cancel-failed`, `alacritty-exited`, `attach-timeout`, `local-reconnect`, `local-reconnect-failed`, `launch-failed`. Every line carries `pid=` to separate concurrent helpers.

## Remote connections

The installed Herdr supports `--remote`. Connecting a Windows client to a Linux Herdr server would work for the keyboard shortcuts that send keys to the visible client. It breaks anything that invokes the local Herdr CLI or assumes Windows paths.

Already handled: `HerdrAnywhereParseConnection()` sets `kind` to remote when it sees `--remote`, and Escape, F10 from Explorer, and Win+E all fall back to safe behavior for remote clients.

Still unverified: Escape over remote (Herdr excludes local custom command bindings from remote attach), Shift+Enter against Linux agents, multiline paste, and image paste, where Herdr has its own remote transfer that should replace the local temp file conversion.

A WSL Herdr server reached over SSH on localhost is the cheapest way to test all of this before a real remote machine is available. Use a project under the Linux home directory so path assumptions fail loudly instead of being masked by `/mnt/c`.
