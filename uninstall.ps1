# TerminalContext — remove context menu and hotkey; do not delete folder
# Run from project root. For full removal, user deletes the folder after closing any terminals using it.

$ErrorActionPreference = 'SilentlyContinue'
$root = $PSScriptRoot

Write-Host "Uninstall: start"

function RegDelete([string]$regKey) {
    # reg.exe delete is typically faster/less likely to hang than Remove-Item on HKCU: providers.
    # reg delete only needs the registry path in the form: HKCU\Software\...
    try {
        $cmd = "reg.exe delete `"$regKey`" /f"
        & cmd.exe /c $cmd | Out-Null
    } catch {
        # ignore missing/non-fatal errors
    }
}

# Remove context menu entries (keys as in by-reg.ps1)
$keys = @(
    'HKCU\Software\Classes\Directory\Background\shell\ZZ_TerminalContext_Open',
    'HKCU\Software\Classes\Directory\Background\shell\ZZ_TerminalContext_OpenAdmin',
    'HKCU\Software\Classes\directory\Background\shell\ZZ_TerminalContext_Open',
    'HKCU\Software\Classes\directory\Background\shell\ZZ_TerminalContext_OpenAdmin',
    'HKCU\Software\Classes\Folder\shell\ZZ_TerminalContext_Open',
    'HKCU\Software\Classes\Folder\shell\ZZ_TerminalContext_OpenAdmin',
    'HKCU\Software\Classes\Directory\shell\ZZ_TerminalContext_Open',
    'HKCU\Software\Classes\Directory\shell\ZZ_TerminalContext_OpenAdmin',
    'HKCU\Software\Classes\DesktopBackground\shell\ZZ_TerminalContext_Open',
    'HKCU\Software\Classes\DesktopBackground\shell\ZZ_TerminalContext_OpenAdmin',
    'HKCU\Software\Classes\Drive\shell\ZZ_TerminalContext_Open',
    'HKCU\Software\Classes\Drive\shell\ZZ_TerminalContext_OpenAdmin',
    'HKCU\Software\Classes\*\shell\ZZ_TerminalContext_Run',
    'HKCU\Software\Classes\*\shell\ZZ_TerminalContext_RunAdmin'
    ,
    # Back-compat: older key names
    'HKCU\Software\Classes\directory\Background\shell\TerminalContextOpen',
    'HKCU\Software\Classes\directory\Background\shell\TerminalContextOpenAdmin',
    'HKCU\Software\Classes\Folder\shell\TerminalContextOpen',
    'HKCU\Software\Classes\Folder\shell\TerminalContextOpenAdmin',
    'HKCU\Software\Classes\Directory\shell\TerminalContextOpen',
    'HKCU\Software\Classes\Directory\shell\TerminalContextOpenAdmin',
    'HKCU\Software\Classes\DesktopBackground\shell\TerminalContextOpen',
    'HKCU\Software\Classes\DesktopBackground\shell\TerminalContextOpenAdmin',
    'HKCU\Software\Classes\Drive\shell\TerminalContextOpen',
    'HKCU\Software\Classes\Drive\shell\TerminalContextOpenAdmin',
    'HKCU\Software\Classes\*\shell\TerminalContextRun',
    'HKCU\Software\Classes\*\shell\TerminalContextRunAdmin'
)

foreach ($key in $keys) {
    Write-Host "Uninstall: reg delete $key"
    RegDelete $key
}

Write-Host "Uninstall: remove AHK Startup shortcut (best-effort)"
$startup = [Environment]::GetFolderPath('Startup')
$ahkLnk = Join-Path $startup 'TerminalContext-CtrlAltT.lnk'
if (Test-Path $ahkLnk) {
    Remove-Item $ahkLnk -Force -ErrorAction SilentlyContinue | Out-Null
}

Write-Host "Uninstall: remove scheduled task (best-effort)"
$taskName = 'TerminalContext-HotkeyListener'
& schtasks.exe /Delete /F /TN $taskName 2>$null | Out-Null

Write-Host "Uninstall complete."
Write-Host "Close any terminals using $root then delete it if you want full removal."
