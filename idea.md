# Универсальный терминал (TerminalContext)

Гибридный способ открывать терминал в Windows с учётом локальных дисков, SSH/SSHFS (буквы дисков), WSL и контекстного меню Explorer.

## Возможности

| Возможность | Реализация |
|-------------|------------|
| **Ctrl+Alt+T** — терминал в папке активного Explorer или на рабочем столе | AutoHotkey `explorer/AHK/Universal.ahk` или `hotkey/for-ctrl-alt-t.ahk`; fallback: `components/hotkey-listener.ps1` |
| **Ctrl+Alt+Shift+T** — то же с повышением прав (UAC) | AHK `^!+t` → `exec-terminal.mjs open … --admin` |
| **Контекстное меню** — «Terminal here», «Run in TC», варианты **(Admin)** + иконка терминала (`conhost.exe`) и **HasLUAShield** для щита UAC | `ctx-menu/by-reg.ps1` → реестр HKCU → `ctx-menu/invoke-terminal.ps1` → `components/exec-terminal.mjs` |
| **SSH / подписанные диски** | `explorer/config/disks.json`: буква диска → `user@host` и корень на удалённой системе; путь `H:\a\b` → `ssh … "cd '/home/…/a/b' && exec bash -l"` |
| **Запуск скриптов по расширению** | `explorer/config/association.json` + команда `run` |
| **WSL** | Утилита `explorer/engine/platform/linux-wsl.mjs` (`windowsPathToWsl`) для сценариев с `wsl` |

## Установка

Из корня проекта:

```powershell
.\installer.ps1
# или
npm run install
```

Параметры: `-Hotkey Auto|Ahk|Pwsh|None`, `-InstallGsudo`, `-Uninstall`.

## CLI

```text
node components/exec-terminal.mjs open [путь] [--admin]
node components/exec-terminal.mjs run <файл> [--admin]
```

Глобально (после `npm link` или `npm i -g`): `terminal-context`.

## Конфигурация

- `explorer/config/disks.json` — соответствие **буквы диска** → локальный Windows или SSH.
- `explorer/config/association.json` — **расширение** → исполнитель для `run`.

## Если из Explorer ничего не открывается

1. **Windows 11** — пункты из классического меню часто спрятаны: **ПКМ → «Показать дополнительные параметры»** (или **Shift+ПКМ** по папке / пустому месту в папке). Там должны быть «Terminal here» / «Run in TC».
2. **Node не виден из Explorer** — `invoke-terminal.ps1` подмешивает PATH из реестра и ищет `node.exe` в стандартных каталогах. Убедитесь, что Node установлен (или добавьте его в системный PATH).
3. **Лог** — `%TEMP%\terminal-context-invoke.log` (запуск из контекстного меню и ошибки `spawn` из Node).
4. Если в логе есть `DONE exit=0`, но окна нет — цепочка до Node уже отработала; обновите `explorer/engine/platform/windows.mjs` (уже без `windowsHide` и без принудительного `-w 0` у `wt`). При необходимости снова привязать к первому окну WT: `setx TERMINAL_CONTEXT_WT_EXTRA "-w 0"` и перезапустить Explorer.
5. **SSH с дисков из `disks.json` (в т.ч. SSHFS)** — по умолчанию **`ssh.exe`** поднимается через `cmd /c start "" …`, чтобы было **отдельное консольное окно** (простой `spawn` с закрытым stdin даёт мгновенный выход). Без `wt` — из‑за кавычек в удалённой команде (`0x80070002` / `" exec bash -l"`). Через Windows Terminal: `setx TERMINAL_CONTEXT_SSH_USE_WT 1` и перезапуск процессов.

После правок контекстного меню снова выполните `.\installer.ps1` или `.\ctx-menu\by-reg.ps1 -Apply` (регистрация через PowerShell `Set-ItemProperty`, без `.reg`).

Если меню Explorer ведёт себя странно, сначала `.\installer.ps1 -Uninstall` (или `uninstall.ps1`), затем снова установка.

## Тестовые SSH (из вашей сети)

- `ssh U2RE@192.168.0.110` (Windows)
- `ssh u2re-dev@192.168.0.200` (Linux)

Корень проекта: `C:\Users\U2RE\AppData\Local\TerminalContext`
