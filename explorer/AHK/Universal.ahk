#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir

global g_LogFile := A_ScriptDir "\TerminalContext.log"

^!t:: {
    RunTerminal(false)
}

^!+t:: {
    RunTerminal(true)
}

RunTerminal(admin := false) {
    path := GetTargetPath()
    path := NormalizeDir(path)

    if !IsUsableFolder(path) {
        Log("Resolved path invalid: [" . path . "], fallback to Desktop", "WARN")
        path := A_Desktop
    }

    Log("Final path: [" . path . "], admin=" . (admin ? "true" : "false"))

    if TryLaunchNode(path, admin)
        return
    if TryLaunchWt(path, admin)
        return
    if TryLaunchPwsh(path, admin)
        return
    if TryLaunchWindowsPowerShell(path, admin)
        return
    if TryLaunchCmd(path, admin)
        return

    Log("All launch methods failed", "ERROR")
    MsgBox(
        "Не удалось открыть терминал.`n`nПуть: " path "`nЛог: " g_LogFile,
        "TerminalContext",
        "Iconx"
    )
}

TryLaunchNode(path, admin) {
    root := A_ScriptDir
    Loop 8 {
        if FileExist(root "\components\exec-terminal.mjs")
            break
        prev := root
        SplitPath root, , &parent
        if (parent = "" || parent = prev)
            return false
        root := parent
    }
    if !FileExist(root "\components\exec-terminal.mjs")
        return false
    nodeExe := FindExecutable("node.exe")
    if (nodeExe = "")
        return false
    try {
        args := "open " . Quote(path)
        if (admin)
            args .= " --admin"
        cmd := (admin ? "*RunAs " : "") . Quote(nodeExe) . " " . Quote(root "\components\exec-terminal.mjs") . " " . args
        Run cmd, root
        Log("Launched node exec-terminal: " . cmd)
        return true
    } catch as e {
        Log("node launch failed: " . e.Message, "WARN")
        return false
    }
}

GetTargetPath() {
    hwnd := WinExist("A")
    if !hwnd {
        Log("No active window, fallback Desktop", "WARN")
        return A_Desktop
    }

    try proc := WinGetProcessName("ahk_id " hwnd)
    catch {
        return A_Desktop
    }

    if IsDesktopContext(hwnd) {
        Log("Desktop context detected")
        return A_Desktop
    }

    if (proc = "explorer.exe") {
        path := GetExplorerPath(hwnd)
        if IsUsableFolder(path) {
            Log("Explorer path resolved: [" . path . "]")
            return path
        }
        Log("Explorer path not resolved, fallback Desktop", "WARN")
    }

    return A_Desktop
}

IsDesktopContext(hwnd) {
    h := hwnd
    Loop 10 {
        if !h
            break

        cls := ""
        try cls := WinGetClass("ahk_id " h)
        catch
            break

        if (cls = "Progman" || cls = "WorkerW" || cls = "SHELLDLL_DefView")
            return true

        parent := DllCall("GetParent", "ptr", h, "ptr")
        if !parent || parent = h
            break
        h := parent
    }
    return false
}

GetExplorerPath(hwnd) {
    try {
        shell := ComObject("Shell.Application")
        for win in shell.Windows {
            try {
                if (win.HWND == hwnd) {
                    path := win.Document.Folder.Self.Path
                    if IsUsableFolder(path)
                        return path
                    
                    ; Фолбэк на LocationURL
                    path := UrlToPath(win.LocationURL)
                    if IsUsableFolder(path)
                        return path
                }
            }
        }
    } catch as e {
        Log("Shell.Application failed: " . e.Message, "ERROR")
    }
    return ""
}

TryLaunchWt(path, admin) {
    wtPath := FindExecutable("wt.exe")
    if (wtPath = "")
        return false

    try {
        cmd := (admin ? "*RunAs " : "") . Quote(wtPath) . " -d " . Quote(path)
        Run(cmd, A_ScriptDir)
        Log("Launched wt: " . cmd)
        return true
    } catch as e {
        Log("wt failed: " . e.Message, "WARN")
        return false
    }
}

TryLaunchPwsh(path, admin) {
    pwshPath := FindExecutable("pwsh.exe")
    if (pwshPath = "")
        return false

    try {
        psPath := EscapeForPS(path)
        psCmd := "Set-Location -LiteralPath '" . psPath . "'"
        cmd := (admin ? "*RunAs " : "") . Quote(pwshPath) . " -NoLogo -NoExit -Command " . Quote(psCmd)
        Run(cmd, A_ScriptDir)
        Log("Launched pwsh: " . cmd)
        return true
    } catch as e {
        Log("pwsh failed: " . e.Message, "WARN")
        return false
    }
}

TryLaunchWindowsPowerShell(path, admin) {
    psExe := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    if !FileExist(psExe)
        return false

    try {
        psPath := EscapeForPS(path)
        psCmd := "Set-Location -LiteralPath '" . psPath . "'"
        cmd := (admin ? "*RunAs " : "") . Quote(psExe) . " -NoLogo -NoExit -ExecutionPolicy Bypass -Command " . Quote(psCmd)
        Run(cmd, A_ScriptDir)
        Log("Launched powershell: " . cmd)
        return true
    } catch as e {
        Log("powershell failed: " . e.Message, "WARN")
        return false
    }
}

TryLaunchCmd(path, admin) {
    cmdExe := A_ComSpec
    if !FileExist(cmdExe)
        return false

    try {
        cmd := (admin ? "*RunAs " : "") . Quote(cmdExe) . " /K cd /d " . Quote(path)
        Run(cmd, A_ScriptDir)
        Log("Launched cmd: " . cmd)
        return true
    } catch as e {
        Log("cmd failed: " . e.Message, "WARN")
        return false
    }
}

FindExecutable(exeName) {
    if (exeName = "wt.exe") {
        candidates := [
            EnvGet("LocalAppData") "\Microsoft\WindowsApps\wt.exe",
            EnvGet("ProgramFiles") "\WindowsApps\Microsoft.WindowsTerminal_*\wt.exe"
        ]
        for p in candidates {
            Loop Files, p 
                return A_LoopFilePath
        }
    }

    try {
        shell := ComObject("WScript.Shell")
        exec := shell.Exec(A_ComSpec . " /C where " . exeName)
        result := exec.StdOut.ReadAll()
        if (exec.ExitCode = 0) {
            for line in StrSplit(result, "`n", "`r") {
                line := Trim(line)
                if (line != "" && FileExist(line))
                    return line
            }
        }
    }
    return ""
}

NormalizeDir(path) {
    path := Trim(path)
    while (StrLen(path) >= 2 && SubStr(path, 1, 1) = '"' && SubStr(path, -1) = '"')
        path := SubStr(path, 2, StrLen(path) - 2)
    return path
}

IsUsableFolder(path) {
    return (path != "" && DirExist(path))
}

EscapeForPS(s) {
    return StrReplace(s, "'", "''")
}

Quote(s) {
    ; ИСПРАВЛЕНИЕ: Если путь заканчивается на слеш (например, C:\), 
    ; удваиваем его, чтобы закрывающая кавычка не экранировалась
    if SubStr(s, -1) == "\"
        s .= "\"
    return '"' . s . '"'
}

UrlToPath(url) {
    if (url = "")
        return ""
    if RegExMatch(url, "^file:///(.*)$", &m) {
        p := StrReplace(m[1], "/", "\")
        return UriDecode(p)
    }
    return url
}

UriDecode(str) {
    pos := 1
    out := ""
    while pos <= StrLen(str) {
        ch := SubStr(str, pos, 1)
        if (ch = "%" && pos + 2 <= StrLen(str)) {
            hex := SubStr(str, pos + 1, 2)
            if RegExMatch(hex, "^[0-9A-Fa-f]{2}$") {
                out .= Chr("0x" . hex)
                pos += 3
                continue
            }
        }
        out .= ch
        pos += 1
    }
    return out
}

Log(msg, level := "INFO") {
    global g_LogFile
    try {
        ts := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        FileAppend(ts . " [" . level . "] " . msg . "`n", g_LogFile, "UTF-8")
    }
}