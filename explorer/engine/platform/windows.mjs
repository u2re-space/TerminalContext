import { spawn, execSync } from 'node:child_process';
import { appendFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';

function logSpawnError(msg) {
  try {
    const p = join(process.env.TEMP || '', 'terminal-context-invoke.log');
    appendFileSync(p, `${new Date().toISOString()} [spawn] ${msg}\n`);
  } catch {
    /* ignore */
  }
}

function whereExe(name) {
  try {
    const out = execSync(`where.exe ${name}`, { encoding: 'utf8', windowsHide: true });
    const line = out.split(/\r?\n/).map((s) => s.trim()).find(Boolean);
    return line && existsSync(line) ? line : '';
  } catch {
    return '';
  }
}

/** Prefer System32 so Explorer/Node never rely on a stripped PATH. */
export function resolveSystemExe(fileName) {
  const win = process.env.SystemRoot || 'C:\\Windows';
  const sys32 = join(win, 'System32', fileName);
  if (existsSync(sys32)) return sys32;
  const sysnative = join(win, 'Sysnative', fileName);
  if (existsSync(sysnative)) return sysnative;
  return whereExe(fileName) || '';
}

export function findWindowsTerminal() {
  const local = join(process.env.LocalAppData || '', 'Microsoft', 'WindowsApps', 'wt.exe');
  if (existsSync(local)) return local;
  const fromWhere = whereExe('wt.exe');
  return fromWhere || '';
}

/** OpenSSH ships under System32\OpenSSH; stripped PATH breaks bare `ssh`. */
export function resolveOpenSshExe() {
  const win = process.env.SystemRoot || 'C:\\Windows';
  const candidates = [
    join(win, 'System32', 'OpenSSH', 'ssh.exe'),
    join(win, 'Sysnative', 'OpenSSH', 'ssh.exe'),
  ];
  for (const c of candidates) {
    if (existsSync(c)) return c;
  }
  const w = whereExe('ssh.exe');
  return w || 'ssh';
}

function isSshWtTail(tail) {
  if (!tail?.length) return false;
  const p = String(tail[0] || '')
    .toLowerCase()
    .replace(/\//g, '\\');
  if (p === 'ssh' || p === 'ssh.exe') return true;
  return p.endsWith('\\ssh.exe');
}

/**
 * Interactive SSH needs a real console; bare spawn + stdio:ignore closes stdin and exits immediately.
 * `cmd /c start "" ssh.exe …` attaches ssh to a new visible console (works when Node was started hidden).
 */
function spawnSshInteractiveWindows({ sshExe, sshArgs, prefix }) {
  const com = process.env.ComSpec || join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'cmd.exe');
  const afterStart = prefix.length ? [...prefix, sshExe, ...sshArgs] : [sshExe, ...sshArgs];
  const argv = ['/c', 'start', '', ...afterStart];
  const child = spawn(com, argv, {
    detached: true,
    windowsHide: false,
    stdio: 'ignore',
  });
  child.on('error', (e) => logSpawnError(`${com} ${e.message}`));
  child.unref();
}

/**
 * @param {string} cwd
 * @param {string[]} prefix optional e.g. ['sudo.exe', '/path']
 * @param {string[]} wtArgs extra args after wt.exe (e.g. ssh ...)
 */
export function spawnWindowsTerminal({ cwd, prefix = [], wtArgs = [] }) {
  const wt = findWindowsTerminal();
  const useWt = process.env.TERMINAL_CONTEXT_USE_WT !== '0' && process.env.TERMINAL_CONTEXT_USE_WT !== 'false';
  if (useWt && wt) {
    // `wt new-tab -d <dir>` is the supported form; bare `-d` without new-tab is unreliable for visibility.
    let tail = wtArgs || [];
    if (tail.length) {
      const head = String(tail[0] || '').toLowerCase();
      if (head === 'ssh' || head === 'ssh.exe') {
        tail = [resolveOpenSshExe(), ...tail.slice(1)];
      }
    }
    // `wt -d` on SSHFS / some network drives breaks command-line parsing; remote `cd` is in the ssh argv.
    let effectiveCwd = cwd;
    if (effectiveCwd && isSshWtTail(tail) && process.env.TERMINAL_CONTEXT_WT_SSH_USE_D !== '1') {
      effectiveCwd = '';
    }
    const args = ['new-tab'];
    const extra = (process.env.TERMINAL_CONTEXT_WT_EXTRA || '').trim();
    if (extra) {
      args.push(...extra.split(/\s+/).filter(Boolean));
    }
    if (effectiveCwd) {
      args.push('-d', effectiveCwd);
    }
    args.push(...tail);
    const cmd = prefix.length ? [...prefix, wt, ...args] : [wt, ...args];
    const exe = cmd[0];
    const rest = cmd.slice(1);
    const child = spawn(exe, rest, { stdio: 'ignore', detached: true, windowsHide: false });
    child.on('error', (e) => logSpawnError(`${exe} ${e.message}`));
    return child;
  }

  const winRoot = process.env.SystemRoot || 'C:\\Windows';
  const psBundled = join(winRoot, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
  const pwsh =
    whereExe('pwsh.exe') ||
    resolveSystemExe('pwsh.exe') ||
    (existsSync(psBundled) ? psBundled : '') ||
    whereExe('powershell.exe');
  if (!pwsh) {
    throw new Error('No wt.exe or PowerShell found');
  }
  const lit = `'${(cwd || '').replace(/'/g, "''")}'`;
  const psArgs = ['-NoLogo', '-NoExit', '-Command', `Set-Location -LiteralPath ${lit}`];
  const cmd = prefix.length ? [...prefix, pwsh, ...psArgs] : [pwsh, ...psArgs];
  const child = spawn(cmd[0], cmd.slice(1), { stdio: 'ignore', detached: true, windowsHide: false, cwd: cwd || undefined });
  child.on('error', (e) => logSpawnError(`${cmd[0]} ${e.message}`));
  return child;
}

/**
 * Local folder: open wt -d cwd (or pwsh fallback).
 */
export function openLocalFolder(cwd, { admin = false, sudoPath = '' } = {}) {
  const prefix = admin && sudoPath ? [sudoPath] : [];
  const child = spawnWindowsTerminal({ cwd, prefix });
  child.unref();
}

/**
 * SSH sessions from disks.json: default is **direct** `ssh.exe` spawn (reliable argv; no `wt` mangling).
 * Set `TERMINAL_CONTEXT_SSH_USE_WT=1` to route through Windows Terminal instead.
 *
 * @param {string} cwd unused for direct ssh (remote `cd` is in the ssh command); used when SSH_USE_WT=1
 * @param {string[]} wtArgv from buildSshArgv: ssh, -t, …, user@host, remoteCmd
 */
export function openWithWtArgv(cwd, wtArgv, { admin = false, sudoPath = '' } = {}) {
  const prefix = admin && sudoPath ? [sudoPath] : [];
  let tail = [...(wtArgv || [])];
  if (tail.length) {
    const head = String(tail[0] || '').toLowerCase();
    if (head === 'ssh' || head === 'ssh.exe') {
      tail = [resolveOpenSshExe(), ...tail.slice(1)];
    }
  }
  if (!isSshWtTail(tail)) {
    const child = spawnWindowsTerminal({ cwd, prefix, wtArgs: wtArgv });
    child.unref();
    return;
  }
  const useWt =
    process.env.TERMINAL_CONTEXT_SSH_USE_WT === '1' ||
    process.env.TERMINAL_CONTEXT_SSH_USE_WT === 'true';
  if (useWt) {
    const child = spawnWindowsTerminal({ cwd, prefix, wtArgs: wtArgv });
    child.unref();
    return;
  }
  const sshExe = tail[0];
  const sshArgs = tail.slice(1);
  spawnSshInteractiveWindows({ sshExe, sshArgs, prefix });
}

/**
 * @param {string} filePath
 * @param {{ executor: string, os?: string }} assoc
 */
export function buildRunCommand(filePath, assoc) {
  const dir = dirname(filePath);
  const file = filePath;
  const ex = (assoc.executor || 'node').toLowerCase();

  if (ex === 'pwsh' || ex === 'powershell') {
    return { exe: 'pwsh.exe', args: ['-NoLogo', '-NoExit', '-File', file], cwd: dir, fallbackExe: 'powershell.exe' };
  }
  if (ex === 'cmd') {
    const com = process.env.ComSpec || resolveSystemExe('cmd.exe') || 'cmd.exe';
    return { exe: com, args: ['/K', 'call', file], cwd: dir };
  }
  if (ex === 'node') {
    return { exe: 'node.exe', args: [file], cwd: dir };
  }
  if (ex === 'tsx') {
    return { exe: 'tsx.cmd', args: [file], cwd: dir };
  }
  if (ex === 'bash' || ex === 'sh') {
    const bash = whereExe('bash.exe');
    if (bash) return { exe: bash, args: [file], cwd: dir };
    return { exe: 'wsl.exe', args: ['bash', file], cwd: dir };
  }
  if (ex === 'python3' || ex === 'python') {
    return { exe: 'python.exe', args: [file], cwd: dir };
  }
  if (ex === 'php') {
    return { exe: 'php.exe', args: [file], cwd: dir };
  }
  if (ex === 'ruby') {
    return { exe: 'ruby.exe', args: [file], cwd: dir };
  }
  if (ex === 'perl') {
    return { exe: 'perl.exe', args: [file], cwd: dir };
  }
  return { exe: 'node.exe', args: [file], cwd: dir };
}

/**
 * @param {string} filePath
 * @param {{ executor: string }} assoc
 */
export function runLocalFile(filePath, assoc, { admin = false, sudoPath = '' } = {}) {
  const spec = buildRunCommand(filePath, assoc);
  let exe = spec.exe;
  const exeIsAbsolute = exe && (exe.includes('\\') || exe.includes('/'));
  if (
    !exeIsAbsolute &&
    !whereExe(exe) &&
    spec.fallbackExe &&
    whereExe(spec.fallbackExe)
  ) {
    exe = spec.fallbackExe;
  }

  let exePath = '';
  const base = (exe || '').split(/[/\\]/).pop()?.toLowerCase() || '';
  if (base === 'cmd.exe') {
    exePath = resolveSystemExe('cmd.exe') || process.env.ComSpec || '';
  } else if (base === 'powershell.exe') {
    const wr = process.env.SystemRoot || 'C:\\Windows';
    const psBundled = join(wr, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');
    exePath = (existsSync(psBundled) ? psBundled : '') || whereExe('powershell.exe') || '';
  } else if (base === 'pwsh.exe') {
    exePath = whereExe('pwsh.exe') || '';
  } else if (exeIsAbsolute && existsSync(exe)) {
    exePath = exe;
  } else {
    exePath = whereExe(exe) || '';
  }
  if (!exePath || !existsSync(exePath)) {
    exePath = exeIsAbsolute && existsSync(exe) ? exe : whereExe(exe) || '';
  }
  if (!exePath) {
    throw new Error(`Executable not found: ${exe}`);
  }

  const prefix = admin && sudoPath ? [sudoPath] : [];
  const wt = findWindowsTerminal();
  const useWt = process.env.TERMINAL_CONTEXT_USE_WT !== '0' && wt;

  const spawnViaWt = () => {
    const args = ['new-tab', '-d', spec.cwd, exePath, ...spec.args];
    const cmd = prefix.length ? [...prefix, wt, ...args] : [wt, ...args];
    const child = spawn(cmd[0], cmd.slice(1), { stdio: 'ignore', detached: true, windowsHide: false });
    child.on('error', (e) => logSpawnError(`${cmd[0]} ${e.message}`));
    child.unref();
  };

  const spawnDirect = () => {
    const cmd = prefix.length ? [...prefix, exePath, ...spec.args] : [exePath, ...spec.args];
    const child = spawn(cmd[0], cmd.slice(1), { cwd: spec.cwd, stdio: 'ignore', detached: true, windowsHide: false });
    child.on('error', (e) => logSpawnError(`${cmd[0]} ${e.message}`));
    child.unref();
  };

  if (useWt) {
    spawnViaWt();
    return;
  }
  // No wt: spawn the target executable directly (avoids Explorer "no app associated" for .cmd when misconfigured).
  spawnDirect();
}
