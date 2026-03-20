# Invoked from Explorer context menu. Explorer often passes a stripped PATH — refresh before finding node.
param(
    [ValidateSet('Open', 'Run')]
    [string] $Mode = 'Open',
    [Parameter(Mandatory = $false)]
    [Alias('LiteralPath')]
    [string] $Path = '',
    [switch] $Admin
)

$ErrorActionPreference = 'Stop'

function Write-InvokeLog([string]$msg) {
    try {
        $log = Join-Path $env:TEMP 'terminal-context-invoke.log'
        "$(Get-Date -Format o) $msg" | Add-Content -Path $log -Encoding utf8
    } catch {}
}

function Merge-PathFromRegistry {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @()
    if ($m) { $parts += $m }
    if ($u) { $parts += $u }
    if ($parts.Count -gt 0) {
        $env:Path = ($parts -join ';')
    }
}

function Find-NodeExecutable {
    Merge-PathFromRegistry
    $cmd = Get-Command node -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path -LiteralPath $cmd.Source)) {
        return $cmd.Source
    }
    $pf86 = ${env:ProgramFiles(x86)}
    $candidates = @(
        (Join-Path $env:ProgramFiles 'nodejs\node.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\node\node.exe'),
        (Join-Path $env:APPDATA 'npm\node.exe')
    )
    if ($pf86) {
        $candidates += (Join-Path $pf86 'nodejs\node.exe')
    }
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    }
    try {
        $where = & where.exe node 2>$null | Select-Object -First 1
        if ($where -and (Test-Path -LiteralPath $where.Trim())) { return $where.Trim() }
    } catch {}
    return $null
}

if ($null -eq $Path) { $Path = '' }
$Path = $Path.Trim().Trim('"')
# Folder background / desktop: %V can be empty in some views — fall back to Desktop
if ($Mode -eq 'Open' -and -not $Path) {
    $Path = [Environment]::GetFolderPath('Desktop')
    Write-InvokeLog "WARN empty Path from Explorer; using Desktop: $Path"
}

$root = Split-Path -Parent $PSScriptRoot
$js = Join-Path $root 'components\exec-terminal.mjs'
Write-InvokeLog "START Mode=$Mode Path=[$Path] Admin=$Admin"

if (-not (Test-Path -LiteralPath $js)) {
    Write-InvokeLog "ERROR Missing $js"
    [Console]::Error.WriteLine("Missing $js")
    exit 1
}

$nodeExe = Find-NodeExecutable
if (-not $nodeExe) {
    Write-InvokeLog 'ERROR node.exe not found (PATH refresh + common locations failed)'
    [Console]::Error.WriteLine('node.exe not found. Install Node or add it to PATH.')
    exit 1
}

$argList = [System.Collections.ArrayList]::new()
[void]$argList.Add($js)
if ($Mode -eq 'Run') {
    [void]$argList.Add('run')
} else {
    [void]$argList.Add('open')
}
if ($Path) {
    [void]$argList.Add($Path)
}
if ($Admin) {
    [void]$argList.Add('--admin')
}

try {
    $p = Start-Process -FilePath $nodeExe -ArgumentList @($argList.ToArray()) -WorkingDirectory $root -PassThru -Wait -WindowStyle Hidden
    $code = $p.ExitCode
    Write-InvokeLog "DONE exit=$code"
    exit $code
} catch {
    Write-InvokeLog "ERROR Start-Process: $($_.Exception.Message)"
    throw
}
