# Config

## `association.json`

Maps **file extension** → executor for “Run in TC” on a file.

- **Schema:** `".ext"` → `{ "executor": "node"|"pwsh"|"cmd"|"bash"|"tsx", "os": "Windows"|"Local" }`
- **Windows:** run in Windows terminal (pwsh/cmd).
- **Local:** run with local runtime (node/tsx/bash from PATH or WSL).

Unknown extensions are not run; folder “Terminal here” is independent.

## `disks.json`

Each **drive letter** maps to how TerminalContext opens a terminal for paths on that drive.

Array format:

`[ "shell", "OS label", "user@host", "remoteOrRootPath", "sshArgs?" ]`

| Index | Meaning |
|-------|--------|
| 0 | Remote shell over SSH (e.g. `bash`). Local Windows drives typically use `pwsh`. |
| 1 | `Windows` → **local** pwsh in the folder. Anything else → **SSH** using index 2–3. |
| 2 | SSH target `user@host` (ignored for local Windows). |
| 3 | Remote base path (e.g. `/home/u2re`) or local root like `C:/` for **open-all**. |
| 4 | Optional SSH args (tokens) to add after `ssh` (for Linux/SSH disks only). Examples: `"-p 22 -i ~/.ssh/id_ecdsa"` or `[ "-p", "22", "-i", "C:/path/key" ]` |

Example: path `H:\project` on a drive `H` mapped to Linux home → SSH session with `cd /home/u2re/project`.

**SSH / PATH:** `launcher/remote.mjs` wraps the remote command in a **login** shell (`bash -lc` or `zsh -lic` by default) so `~/.profile`, `~/.bash_profile`, nvm/fnm, etc. apply before `cd` and `node`/`bash`. Override with `TERMINAL_CONTEXT_SSH_LOGIN_WRAPPER`: `auto` (default), `bash`, `zsh`, or `none` (old behavior, minimal env).

**Run in TC** (on files) runs by extension: **.js/.mjs/.cjs** (node), **.ts/.tsx** (tsx), **.cmd/.bat** (cmd), **.ps1** (pwsh), **.sh/.bash** (Git Bash / PATH **bash**/**sh**, else **WSL** `bash`).

After install you get **two** context menu lines where relevant: normal and **(Admin)** (UAC via **Windows sudo** or **gsudo** — see below).

**Reinstall:** run `installer.ps1` again — full uninstall is optional.

**Opening the terminal (wt.exe / start):** When you use “Terminal here” from Explorer (no console), the launcher uses **Windows Terminal** (`wt.exe`) if found so a window always opens; otherwise it uses `cmd /c start ... pwsh` to force a new console. Set `TERMINAL_CONTEXT_USE_WT=0` to disable wt and always use the start fallback.

**Context menu (after `ctx-menu\by-reg.ps1 -Apply`):** Commands call **`ctx-menu\invoke-terminal.ps1`** with **`-WindowStyle Hidden`** so **`node.exe` is not started directly from the registry** (that flashes a console that closes when Node exits). Short labels: **Terminal here** / **Terminal (Admin)** (icons: `conhost.exe` terminal glyph; Admin adds **`HasLUAShield`** so Explorer draws the standard UAC shield overlay). Registered for **folder empty area** (`%V`), **folder / directory** (`%1`), **desktop background** (`%V`), **drives** (`%1`). **Run in TC** on **all files** (`%1`). Re-run the script after moving the install path.

**Ctrl+Alt+T** (`hotkey\for-ctrl-alt-t.ahk`): Uses the same idea as `%V` — active Explorer folder (any focused control inside the window), **Desktop** when focus is on the desktop shell, otherwise your user **Desktop** folder.

**Uninstall delete fails** if your terminal’s current folder is inside `TerminalContext` or a program has files open: `cd $env:USERPROFILE`, then delete the folder (or reboot).

### Ctrl+Alt+T

- **AutoHotkey** (`hotkey\for-ctrl-alt-t.ahk`): requires **[AutoHotkey v2](https://www.autohotkey.com/)** (`AutoHotkey64.exe`). v1 scripts won’t run. Then run `installer.ps1` — **Hotkey Auto** adds a Startup shortcut.
- **Without AHK**: use `-Hotkey Pwsh` (default when AutoHotkey.exe is not found) — installs a logon Scheduled Task that runs `components\hotkey-listener.ps1`.
- **Force**: `-Hotkey Ahk` | `-Hotkey Pwsh` | `-Hotkey None`

## Elevation (Admin terminal)

`launcher/sudo.mjs` picks an elevation helper in this order (unless overridden):

1. **`SUDO_PATH`** — full path to any compatible `sudo`-style tool.
2. **`TERMINAL_CONTEXT_SUDO=auto`** (default) — use **Windows native** `%SystemRoot%\System32\sudo.exe` if it exists (enable in **Settings → System → For developers → Enable sudo**, Windows 11 24H2+), otherwise **gsudo**.
3. **`TERMINAL_CONTEXT_SUDO=windows`** — native `sudo.exe` only; falls back to gsudo if the file is missing.
4. **`TERMINAL_CONTEXT_SUDO=gsudo`** — **gsudo** only (`GSUDO_PATH` or `gsudo` on PATH).

From an already-open terminal:

```powershell
$env:TERMINAL_CONTEXT_ELEVATE = "1"
node "$env:LOCALAPPDATA\TerminalContext\components\exec-terminal.mjs" open .
```

Or wrap the whole command: `sudo node ... exec-terminal.mjs open .` (native) or `gsudo node ...` (gsudo).

Install **gsudo** (optional if you use Windows sudo): `winget install gerardog.gsudo` (installer can use `-InstallGsudo`).
