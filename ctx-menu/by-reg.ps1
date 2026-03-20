# Register TerminalContext Explorer context menu (HKCU) via PowerShell registry provider.
# More reliable than .reg import on some locales / encodings. Safe to re-run (overwrites values).
param(
    [string] $RootPath = '',
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'
if (-not $RootPath) {
    $RootPath = Split-Path -Parent $PSScriptRoot
}
$root = Resolve-Path -LiteralPath $RootPath
$invoke = Join-Path $root 'ctx-menu\invoke-terminal.ps1'
if (-not (Test-Path -LiteralPath $invoke)) {
    throw "Missing invoke script: $invoke"
}

function Build-PowerShellLauncher([string]$extraArgs) {
    return "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$invoke`" $extraArgs"
}

function Resolve-TerminalMenuIcon {
    # Console window icon (not wt alias — reads as a clear “terminal” in the menu)
    $win = $env:SystemRoot
    $conhost = Join-Path $win 'System32\conhost.exe'
    if (Test-Path -LiteralPath $conhost) { return $conhost }
    Join-Path $win 'System32\cmd.exe'
}

function Set-ShellVerb {
    param(
        [Parameter(Mandatory = $true)][string] $HivePath,
        [Parameter(Mandatory = $true)][string] $VerbId,
        [Parameter(Mandatory = $true)][string] $Label,
        [Parameter(Mandatory = $true)][string] $CommandLine,
        [string] $Icon = '',
        [switch] $HasLUAShield
    )
    # Subkey literally named "*" (all files): registry provider treats * as wildcard — use .NET API.
    if ($HivePath -eq '*') {
        $cu = [Microsoft.Win32.Registry]::CurrentUser
        $verbRel = "Software\Classes\*\shell\$VerbId"
        $sk = $cu.CreateSubKey($verbRel, $true)
        try {
            $sk.SetValue('', $Label)
            $sk.SetValue('MUIVerb', $Label)
            if ($Icon) { $sk.SetValue('Icon', $Icon) }
            if ($HasLUAShield) {
                $sk.SetValue('HasLUAShield', '')
            } else {
                try { $sk.DeleteValue('HasLUAShield', $false) } catch { }
            }
        } finally {
            $sk.Dispose()
        }
        $ck = $cu.CreateSubKey("$verbRel\command", $true)
        try {
            $ck.SetValue('', $CommandLine)
        } finally {
            $ck.Dispose()
        }
        return
    }

    $shellKey = "HKCU:\Software\Classes\$HivePath\shell\$VerbId"
    $cmdKey = "$shellKey\command"
    if (-not (Test-Path -Path $shellKey)) {
        New-Item -Path $shellKey -Force | Out-Null
    }
    Set-ItemProperty -Path $shellKey -Name '(default)' -Value $Label -Type String
    Set-ItemProperty -Path $shellKey -Name 'MUIVerb' -Value $Label -Type String
    if ($Icon) {
        Set-ItemProperty -Path $shellKey -Name 'Icon' -Value $Icon -Type String
    }
    if ($HasLUAShield) {
        Set-ItemProperty -Path $shellKey -Name 'HasLUAShield' -Value '' -Type String
    } else {
        Remove-ItemProperty -Path $shellKey -Name 'HasLUAShield' -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path -Path $cmdKey)) {
        New-Item -Path $cmdKey -Force | Out-Null
    }
    Set-ItemProperty -Path $cmdKey -Name '(default)' -Value $CommandLine -Type String
}

if (-not $Apply) {
    Write-Host 'Dry run: use -Apply to write registry.'
}

$iconTerminal = Resolve-TerminalMenuIcon

# Short labels; icons: conhost (terminal) + HasLUAShield (Explorer draws UAC shield overlay on Admin)
$openLabel = 'Terminal here'
$openAdmin = 'Terminal (Admin)'
$runLabel = 'Run in TC'
$runAdmin = 'Run in TC (Admin)'

$pairs = @(
    @{ Hive = 'Directory\Background'; Arg = '%V'; Name = 'folder background / empty area' },
    @{ Hive = 'directory\Background'; Arg = '%V'; Name = 'folder background (alt key)' },
    @{ Hive = 'Directory'; Arg = '%1'; Name = 'directory' },
    @{ Hive = 'Folder'; Arg = '%1'; Name = 'folder' },
    @{ Hive = 'DesktopBackground'; Arg = '%V'; Name = 'desktop' },
    @{ Hive = 'Drive'; Arg = '%1'; Name = 'drive' }
)

foreach ($p in $pairs) {
    $arg = $p.Arg
    $hive = $p.Hive
    $cmdOpen = Build-PowerShellLauncher "-Mode Open -LiteralPath `"$arg`""
    $cmdAdm = Build-PowerShellLauncher "-Mode Open -LiteralPath `"$arg`" -Admin"
    if ($Apply) {
        Set-ShellVerb -HivePath $hive -VerbId 'ZZ_TerminalContext_Open' -Label $openLabel -CommandLine $cmdOpen -Icon $iconTerminal
        Set-ShellVerb -HivePath $hive -VerbId 'ZZ_TerminalContext_OpenAdmin' -Label $openAdmin -CommandLine $cmdAdm -Icon $iconTerminal -HasLUAShield
    }
    Write-Host "  [$($p.Name)] $hive -> ZZ_TerminalContext_Open(Admin)"
}

$cmdRun = Build-PowerShellLauncher "-Mode Run -LiteralPath `"%1`""
$cmdRunAd = Build-PowerShellLauncher "-Mode Run -LiteralPath `"%1`" -Admin"
if ($Apply) {
    Set-ShellVerb -HivePath '*' -VerbId 'ZZ_TerminalContext_Run' -Label $runLabel -CommandLine $cmdRun -Icon $iconTerminal
    Set-ShellVerb -HivePath '*' -VerbId 'ZZ_TerminalContext_RunAdmin' -Label $runAdmin -CommandLine $cmdRunAd -Icon $iconTerminal -HasLUAShield
}
Write-Host '  [all files] *\shell -> Run(Admin)'

if ($Apply) {
    Write-Host 'Context menu registered under HKCU\Software\Classes (current user).'
    Write-Host 'Windows 11: use right-click -> Show more options (Shift+F10) to see classic items if they do not appear in the short menu.'
} else {
    Write-Host 'No registry changes (use -Apply).'
}

exit 0
