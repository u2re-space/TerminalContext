# Fallback hotkey when AutoHotkey is not installed: Ctrl+Alt+T opens terminal via Node launcher.
# Logon tasks often have a minimal PATH — merge User/Machine like Explorer context menu.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$js = Join-Path $root 'components\exec-terminal.mjs'

function Merge-PathFromRegistry {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @()
    if ($m) { $parts += $m }
    if ($u) { $parts += $u }
    if ($parts.Count -gt 0) { $env:Path = ($parts -join ';') }
}

function Find-NodeExecutable {
    Merge-PathFromRegistry
    $cmd = Get-Command node -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path -LiteralPath $cmd.Source)) { return $cmd.Source }
    $pf86 = ${env:ProgramFiles(x86)}
    $candidates = @(
        (Join-Path $env:ProgramFiles 'nodejs\node.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\node\node.exe'),
        (Join-Path $env:APPDATA 'npm\node.exe')
    )
    if ($pf86) { $candidates += (Join-Path $pf86 'nodejs\node.exe') }
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    try {
        $where = & where.exe node 2>$null | Select-Object -First 1
        if ($where -and (Test-Path -LiteralPath $where.Trim())) { return $where.Trim() }
    } catch {}
    return $null
}

$nodeExe = Find-NodeExecutable
if (-not $nodeExe -or -not (Test-Path -LiteralPath $js)) {
    [Console]::Error.WriteLine('terminal-context: node or exec-terminal.mjs missing.')
    exit 1
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Kbd {
  [DllImport("user32.dll")]
  public static extern short GetAsyncKeyState(int vKey);
}
"@

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();
}
"@

function Get-ExplorerFolderPath {
    try {
        $shell = New-Object -ComObject Shell.Application
        $fw = [Win32]::GetForegroundWindow()
        foreach ($w in $shell.Windows()) {
            try {
                if ($w.HWND -eq $fw) {
                    $p = $w.Document.Folder.Self.Path
                    if ($p -and (Test-Path -LiteralPath $p)) { return $p }
                }
            } catch {}
        }
    } catch {}
    return [Environment]::GetFolderPath('Desktop')
}

$VK_CONTROL = 0x11
$VK_MENU = 0x12
$VK_T = 0x54
$last = [DateTime]::UtcNow

while ($true) {
    Start-Sleep -Milliseconds 120
    $down = ([Kbd]::GetAsyncKeyState($VK_T) -band 0x8000) -ne 0
    $ctrl = ([Kbd]::GetAsyncKeyState($VK_CONTROL) -band 0x8000) -ne 0
    $alt = ([Kbd]::GetAsyncKeyState($VK_MENU) -band 0x8000) -ne 0
    if (-not ($down -and $ctrl -and $alt)) { continue }
    $now = [DateTime]::UtcNow
    if (($now - $last).TotalMilliseconds -lt 600) { continue }
    $last = $now

    $path = Get-ExplorerFolderPath
    & $nodeExe @($js, 'open', $path)
}
