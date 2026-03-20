# TerminalContext — install context menu and hotkey (Ctrl+Alt+T)
# Run from project root. Use -Uninstall to remove context menu and hotkey only.
# Usage: .\installer.ps1 [-Uninstall] [-InstallGsudo] [-Hotkey None|Pwsh|Ahk|Auto]

param(
    [switch] $Uninstall,
    [switch] $InstallGsudo,
    [string] $Hotkey = 'Auto'  # Auto = use AHK if found, else Pwsh runner
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$installLog = Join-Path $env:TEMP 'terminal-context-install.log'
function Write-InstallLog([string]$msg) {
    try { Add-Content -Path $installLog -Value "$(Get-Date -Format o) $msg" } catch {}
}

Write-InstallLog "installer.ps1 START (Hotkey=$Hotkey Uninstall=$Uninstall InstallGsudo=$InstallGsudo) root=$root"

function Remove-StartupShortcut {
    $startup = [Environment]::GetFolderPath('Startup')
    $lnkPath = Join-Path $startup "TerminalContext-CtrlAltT.lnk"
    if (Test-Path -LiteralPath $lnkPath) {
        Remove-Item $lnkPath -Force -ErrorAction SilentlyContinue | Out-Null
        Write-InstallLog "Removed AHK startup shortcut: $lnkPath"
    }
}

function Remove-ScheduledTask {
    $taskName = 'TerminalContext-HotkeyListener'
    & schtasks.exe /Delete /F /TN $taskName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-InstallLog "Removed scheduled task: $taskName"
    }
}

if ($Uninstall) {
    Write-InstallLog "Calling uninstall.ps1"
    & "$root\uninstall.ps1"
    Write-InstallLog "uninstall.ps1 finished exit=$LASTEXITCODE"
    exit $LASTEXITCODE
}

# Optional: install gsudo for Admin terminal
if ($InstallGsudo) {
    $gsudo = Get-Command gsudo -ErrorAction SilentlyContinue
    if (-not $gsudo) {
        Write-Host "Installing gsudo (winget)..."
        winget install --id gerardog.gsudo -e --accept-source-agreements --accept-package-agreements
    }
}

# Register context menu via generated .reg
$byReg = Join-Path $root "ctx-menu\by-reg.ps1"
Write-InstallLog "Applying ctx-menu via by-reg.ps1"
& $byReg -RootPath $root -Apply | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Hotkey runner modes:
# - Ahk: create Startup shortcut for hotkey\\for-ctrl-alt-t.ahk
# - Pwsh: create scheduled task (logon) that runs components\\hotkey-listener.ps1
# - Auto: Ahk if installed, otherwise Pwsh
$ahkExe = $null
if ($Hotkey -eq 'Auto' -or $Hotkey -eq 'Ahk') {
    $ahkExe = Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if (-not $ahkExe) {
        $ahkExe = Get-Command AutoHotkey.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    }
    if (-not $ahkExe) {
        $ahkExe = Join-Path ${env:ProgramFiles} "AutoHotkey\v2\AutoHotkey64.exe"
        if (-not (Test-Path $ahkExe)) { $ahkExe = $null }
    }
}

$ahkScript = $null
$ahkScriptCandidates = @(
    (Join-Path $root 'hotkey\for-ctrl-alt-t.ahk'),
    (Join-Path $root 'components\for-ctrl-alt-t.ahk')
)
foreach ($c in $ahkScriptCandidates) {
    if (Test-Path -LiteralPath $c) { $ahkScript = $c; break }
}

$useAhk = ($Hotkey -eq 'Ahk' -or $Hotkey -eq 'Auto') -and $ahkExe -and $ahkScript
$usePwsh = $Hotkey -eq 'Pwsh' -or ($Hotkey -eq 'Auto' -and -not $useAhk)

if ($useAhk) {
    Remove-ScheduledTask
    $startup = [Environment]::GetFolderPath('Startup')
    $lnkPath = Join-Path $startup "TerminalContext-CtrlAltT.lnk"

    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($lnkPath)
    $lnk.TargetPath = $ahkExe
    $lnk.Arguments = "`"$ahkScript`""
    $lnk.WorkingDirectory = $root
    $lnk.Save()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($ws) | Out-Null
    try {
        Start-Process -FilePath $ahkExe -ArgumentList "`"$ahkScript`"" -WorkingDirectory $root -WindowStyle Hidden
        Write-InstallLog "Started AHK hotkey process"
    } catch {
        Write-InstallLog "Start-Process AHK failed: $($_.Exception.Message)"
    }
    Write-Host "Hotkey runner installed (AHK): $lnkPath"
} elseif ($usePwsh) {
    Remove-StartupShortcut
    $taskName = 'TerminalContext-HotkeyListener'
    $listener = Join-Path $root 'components\hotkey-listener.ps1'
    if (-not (Test-Path $listener)) {
        throw "Missing hotkey-listener: $listener"
    }

    $listenerQ = "`"$listener`""
    $pwshCmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
    if ($pwshCmd) {
        $tr = "pwsh.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $listenerQ"
    } else {
        $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $ps)) { $ps = 'powershell.exe' }
        $tr = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $listenerQ"
    }

    # Per-user logon task (no password); cmd/schtasks handles quoting reliably.
    Write-InstallLog "Creating scheduled task: $taskName"
    $out = & schtasks.exe /Create /F /SC ONLOGON /RL LIMITED /TN $taskName /TR $tr 2>&1
    Write-InstallLog "schtasks output: $out"
    if ($LASTEXITCODE -ne 0) {
        throw "schtasks.exe /Create failed exit=$LASTEXITCODE output=$out"
    }
    & schtasks.exe /Run /TN $taskName 2>&1 | Out-Null
    Write-InstallLog "schtasks /Run exit=$LASTEXITCODE"
    Write-Host "Hotkey runner installed (PowerShell task): $taskName"
} else {
    Remove-StartupShortcut
    Remove-ScheduledTask
    Write-Host "Hotkey runner disabled: -Hotkey None"
}

Write-Host "TerminalContext installed. Context menu: ""Terminal here"" / ""Run in TC"" (and Admin variants)."
Write-InstallLog "installer.ps1 END exit=0"
