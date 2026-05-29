; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === PROCESS MANAGEMENT / PRIVILEGE ESCALATION === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

; ⇒ Search for executable in PATH (PATHEXT-aware for extensionless names)
FindInPath(exe) {
  SplitPath, exe,,, _ext
  if (_ext != "") {
    If FileExist(exe)
      Return exe
    EnvGet, pathVar, PATH
    Loop, Parse, pathVar, `;
    {
      If (A_LoopField = "")
        continue
      fullPath := RTrim(A_LoopField, "\") "\" exe
      If FileExist(fullPath)
        Return fullPath
    }
    Return ""
  }

  EnvGet, pathExt, PATHEXT
  if (pathExt = "")
    pathExt := ".COM;.EXE;.BAT;.CMD"

  Loop, Parse, pathExt, `;
  {
    if (A_LoopField = "")
      continue
    if FileExist(exe . A_LoopField)
      Return exe . A_LoopField
  }

  EnvGet, pathVar, PATH
  Loop, Parse, pathVar, `;
  {
    If (A_LoopField = "")
      continue
    _dir := RTrim(A_LoopField, "\")
    Loop, Parse, pathExt, `;
    {
      if (A_LoopField = "")
        continue
      fullPath := _dir "\" exe . A_LoopField
      If FileExist(fullPath)
        Return fullPath
    }
  }
  Return ""
}

; ⇒ Get exe path and/or directory for a window
; Example: info := GetExePath() or info := GetExePath("ahk_id " hwnd)
; Returns: { path: "C:\...\app.exe", dir: "C:\..." }
GetExePath(winTitle := "A") {
  WinGet, exePath, ProcessPath, %winTitle%
  SplitPath, exePath,, exeDir
  Return {path: exePath, dir: exeDir}
}

; ⇒ Get CmdLine for a window (by PID, or active window if omitted)
GetActiveWindowCommandLine(pid := "") {
  If (pid = "")
    WinGet, pid, PID, A

  If (pid) {
    cmdLine := ""
    For process in ComObjGet("winmgmts:").ExecQuery("Select CommandLine from Win32_Process where ProcessId=" . pid)
      cmdLine := process.CommandLine

    If (cmdLine)
      Return cmdLine
    exe := GetExePath()
    If (exe.path)
      Return exe.path
  }
  Return "."
}

; Check if a process with specific command line exists
ProcessExistsByCommandLine(cmdLine) {
  For process in ComObjGet("winmgmts:").ExecQuery("Select ProcessId, CommandLine from Win32_Process")
    If (InStr(process.CommandLine, cmdLine))
      Return process.ProcessId
  Return 0
}

IsProcessElevated(pid) {
  hProcess := DllCall("OpenProcess", "UInt", 0x0400, "Int", false, "UInt", pid, "Ptr")  ; PROCESS_QUERY_INFORMATION
  If (!hProcess)
    Return false
  hToken := 0
  DllCall("advapi32\OpenProcessToken", "Ptr", hProcess, "UInt", 0x0008, "Ptr*", hToken)  ; TOKEN_QUERY
  DllCall("CloseHandle", "Ptr", hProcess)
  If (!hToken)
    Return false
  elevation := 0
  DllCall("advapi32\GetTokenInformation", "Ptr", hToken, "Int", 20, "UInt*", elevation, "UInt", 4, "UInt*", 0)
  DllCall("CloseHandle", "Ptr", hToken)
  Return elevation
}

; ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
; ┃ === SAFE RUN (as user, admin, SYSTEM) === ┃
; ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
; "elevate" sentinel elevates via PS Start-Process -Verb RunAs
; Spawns from Explorer (via RunFromProcess) for clean process trees
; UserRun("wt", "-d", A_Desktop) | UserRun("elevate", "wt", "-d", path)
UserRun(Executable, Args*) {
    global UserRun_LastError, WS

    UserRun_LastError := ""

    if (IsObject(WS)) {
        if (RegExMatch(Executable, "i)([^\\\/]+\.exe)\s*$", _m))
            WS.RecentExes[_m1] := A_TickCount
        for _i, _a in Args {
            if (RegExMatch(_a, "i)([^\\\/]+\.exe)\s*$", _m))
                WS.RecentExes[_m1] := A_TickCount
        }
    }

    ; "elevate" is a sentinel: elevate the real target in Args[1]
    elevate := (Executable = "elevate")
    if (elevate) {
        if (Args.Length() < 1) {
            MsgBox, 16, UserRun failed, Missing target executable for elevate.
            return false
        }
        Executable := Args[1]
        Args.RemoveAt(1)
    }

    ; Check if any arg needs PowerShell for env var expansion
    needsPowerShell := false
    Loop % Args.Length() {
        arg := Args[A_Index]
        if (RegExMatch(arg, "%(.*?)%") || InStr(arg, "$env:")) {
            needsPowerShell := true
            break
        }
    }

    ; Resolve RunFromProcess once. Empty string means "not available".
    rfp := FindInPath("RunFromProcess-x64.exe")

    ; --------------------------------------------------------------------------
    ; PowerShell-required path
    ; --------------------------------------------------------------------------
    if (needsPowerShell) {
        ; Resolve PowerShell only here, because only this branch requires it.
        psPath := FindInPath("powershell.exe")
        if (psPath = "")
            psPath := FindInPath("pwsh.exe")

        if (psPath = "") {
            MsgBox, 16, UserRun failed, PowerShell is required for this launch path but was not found.
            return false
        }

        ; pwsh-only environment workaround
        psPrefix := ""
        if RegExMatch(psPath, "(?i)\\pwsh\.exe$")
            psPrefix := "set DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 && "

        _safeExe := StrReplace(Executable, "'", "''")
        quotedExe := "'" _safeExe "'"
        psCmd := "& " quotedExe

        Loop % Args.Length() {
            arg := Args[A_Index]

            ; Handle "-d <path>" specially (Windows Terminal)
            if RegExMatch(arg, "(?i)^\s*-d\s+(.+)$", m) {
                rawPath := m1
                expanded := RegExReplace(rawPath, "(?i)%(.*?)%", "$env:$1")
                _safePath := StrReplace(expanded, "'", "''")
                psCmd .= " -d '" _safePath "'"
            } else {
                expanded := RegExReplace(arg, "(?i)%(.*?)%", "$env:$1")
                _safeArg := StrReplace(expanded, "'", "''")
                psCmd .= " '" _safeArg "'"
            }
        }

        if (elevate) {
            ; Elevation in this branch is PowerShell-mediated by design.
            _psCmdEsc := StrReplace(psCmd, "'", "''")
            psExeQ := """" psPath """"
            psArg := "-NoProfile -Command ""Start-Process " psExeQ " -ArgumentList '-NoProfile -Command " _psCmdEsc "' -Verb RunAs -WindowStyle Hidden"""

            if (rfp != "") {
                full := """" rfp """ explorer.exe conhost.exe --headless cmd.exe /C """ psPrefix psExeQ " " psArg """"
                Run, %full%, , UseErrorLevel Hide
                if (ErrorLevel) {
                    MsgBox, 16, UserRun failed, % "Run failed.`nErrorLevel: " ErrorLevel "`n`nCommand:`n" full
                    return false
                }
                return true
            }

            ; Fallback: Explorer shell (may inherit elevation)
            ToolTip, UserRun: PS + elevated + ShellExecute (no RFP)
            SetTimer, RemoveToolTip, -3000
            if !ShellRunUserOrFail("cmd.exe", "/C " Chr(34) psPrefix psExeQ " " psArg Chr(34), "", "open", 0)
                return false

            return true
        }

        ; Non-elevated PowerShell path
        psExeQ := """" psPath """"
        psArg := "-NoProfile -Command " Chr(34) psCmd Chr(34)

        if (Debug.Log["terminal-anywhere"]) {
            FileAppend, % TS() . " | terminal-anywhere | UserRun PS path: psCmd=" . psCmd . "`n", % Debug.Log.Path
        }

        if (rfp != "") {
            full := """" rfp """ explorer.exe conhost.exe --headless cmd.exe /C """ psPrefix psExeQ " " psArg """"
            if (Debug.Log["terminal-anywhere"])
                FileAppend, % TS() . " | terminal-anywhere | UserRun full cmd: " . full . "`n", % Debug.Log.Path
            Run, %full%, , UseErrorLevel Hide
            if (ErrorLevel) {
                MsgBox, 16, UserRun failed, % "Run failed.`nErrorLevel: " ErrorLevel "`n`nCommand:`n" full
                return false
            }
            return true
        }

        ToolTip, UserRun: PS + non-elevated + ShellExecute (no RFP)
        SetTimer, RemoveToolTip, -3000
        if !ShellRunUserOrFail("cmd.exe", "/C " Chr(34) psPrefix psExeQ " " psArg Chr(34), "", "open", 0)
            return false

        return true
    }

    ; --------------------------------------------------------------------------
    ; Direct execution path (no PowerShell semantics required)
    ; --------------------------------------------------------------------------
    argStr := ""
    Loop % Args.Length() {
        arg := Args[A_Index]
        _safeArg := StrReplace(arg, """", """""")
        argStr .= " """ _safeArg """"
    }

    if (elevate) {
        ; If AHK is already elevated, run directly
        if (IsProcessElevated(DllCall("GetCurrentProcessId"))) {
            _safeExeD := StrReplace(Executable, """", """""")
            full := """" _safeExeD """" argStr
            Run, %full%, , UseErrorLevel
            if (ErrorLevel) {
                MsgBox, 16, UserRun failed, % "Run failed.`nErrorLevel: " ErrorLevel "`n`nCommand:`n" full
                return false
            }
            return true
        }

        ; AHK is not elevated - use AHK's *RunAs verb (simpler than PowerShell Start-Process)
        _safeExeD := StrReplace(Executable, """", """""")
        full := "*RunAs """ _safeExeD """" argStr
        Run, %full%, , UseErrorLevel
        if (ErrorLevel) {
            MsgBox, 16, UserRun failed, % "Run failed.`nErrorLevel: " ErrorLevel "`n`nCommand:`n" full
            return false
        }
        return true
    }

    ; Direct non-elevated path
    _safeExeD := StrReplace(Executable, """", """""")
    full := ""

    if (rfp != "") {
        innerCmd := _safeExeD . argStr
        full := """" rfp """ explorer.exe conhost.exe --headless cmd.exe /C " innerCmd
        Run, %full%, , UseErrorLevel Hide
        if (ErrorLevel) {
            MsgBox, 16, UserRun failed, % "Run failed.`nErrorLevel: " ErrorLevel "`n`nCommand:`n" full
            return false
        }
        return true
    }

    ToolTip, UserRun: Direct + non-elevated + ShellExecute (no RFP)
    SetTimer, RemoveToolTip, -3000
    if !ShellRunUserOrFail(Executable, LTrim(argStr), "", "open", 1)
        return false

    return true
}
ShellRunUser(exe, args := "", dir := "", verb := "open", show := 1) {
    global UserRun_LastError
    UserRun_LastError := ""
    try {
        shell := ComObjCreate("Shell.Application")
        shell.ShellExecute(exe, args, dir, verb, show)
        shell := ""
        return true
    } catch e {
        UserRun_LastError := "ShellExecute failed: " e.Message
        return false
    }
}
ShellRunUserOrFail(exe, args := "", dir := "", verb := "open", show := 1) {
    if !ShellRunUser(exe, args, dir, verb, show) {
        MsgBox, 16, UserRun failed, % UserRun_LastError
        return false
    }
    return true
}
