import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, normalize, relative, resolve as pathResolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

/** @returns {string} */
export function getProjectRoot() {
  if (process.env.TERMINAL_CONTEXT_ROOT && existsSync(process.env.TERMINAL_CONTEXT_ROOT)) {
    return process.env.TERMINAL_CONTEXT_ROOT;
  }
  return pathResolve(__dirname, '..', '..', '..');
}

/** @returns {Record<string, unknown>} */
export function loadDisksMap() {
  const p = join(getProjectRoot(), 'explorer', 'config', 'disks.json');
  const raw = readFileSync(p, 'utf8');
  return JSON.parse(raw);
}

/** @returns {Record<string, unknown>} */
export function loadAssociationMap() {
  const p = join(getProjectRoot(), 'explorer', 'config', 'association.json');
  const raw = readFileSync(p, 'utf8');
  return JSON.parse(raw);
}

/**
 * @param {string} driveLetter upper case A-Z
 * @param {unknown} raw
 */
function parseDiskEntry(driveLetter, raw) {
  if (!Array.isArray(raw) || raw.length < 4) {
    throw new Error(`Invalid disks.json entry for "${driveLetter}"`);
  }
  const shell = String(raw[0] ?? 'bash');
  const osLabel = String(raw[1] ?? '');
  const sshTarget = String(raw[2] ?? '');
  const remoteRoot = String(raw[3] ?? '/').replace(/\\/g, '/');
  let sshArgs = raw[4];
  if (typeof sshArgs === 'string') {
    sshArgs = sshArgs.trim() ? sshArgs.split(/\s+/).filter(Boolean) : [];
  } else if (!Array.isArray(sshArgs)) {
    sshArgs = [];
  }
  return { shell, osLabel, sshTarget, remoteRoot, sshArgs };
}

function isWindowsLocal(osLabel) {
  return /^windows$/i.test(osLabel.trim());
}

/** `H:` → `H:\` so pathResolve/relative behave on all Node/Windows versions. */
function normalizeDriveRootInput(inputPath) {
  const t = String(inputPath || '').trim();
  if (/^[A-Za-z]:$/.test(t)) return `${t}\\`;
  return inputPath;
}

/**
 * @param {string} absWinPath absolute path with drive letter
 * @param {string} letter upper case drive letter
 * @param {string} remoteRoot unix-style base e.g. /home/u2re-dev/
 */
export function windowsPathToRemote(absWinPath, letter, remoteRoot) {
  const rootWin = `${letter}:\\`;
  let rel = relative(rootWin, absWinPath);
  if (rel === '') rel = '.';
  rel = rel.replace(/\\/g, '/');
  const base = remoteRoot.endsWith('/') ? remoteRoot.slice(0, -1) : remoteRoot;
  if (rel === '.') return base || '/';
  const combined = `${base}/${rel}`.replace(/\/+/g, '/');
  return combined;
}

/**
 * @param {string} inputPath
 * @returns {{ kind: 'local', cwd: string, shell?: string } | { kind: 'ssh', cwd: string, shell: string, sshTarget: string, remotePath: string, sshArgs: string[] }}
 */
export function resolveTarget(inputPath) {
  const cwd = normalize(pathResolve(normalizeDriveRootInput(inputPath)));
  const m = /^([A-Za-z]):/.exec(cwd);
  if (!m) {
    return { kind: 'local', cwd };
  }
  const letter = m[1].toUpperCase();
  let disks;
  try {
    disks = loadDisksMap();
  } catch {
    return { kind: 'local', cwd };
  }
  const raw = disks[letter];
  if (raw == null) {
    return { kind: 'local', cwd };
  }
  const { shell, osLabel, sshTarget, remoteRoot, sshArgs } = parseDiskEntry(letter, raw);
  if (isWindowsLocal(osLabel)) {
    return { kind: 'local', cwd, shell: shell || 'pwsh' };
  }
  const remotePath = windowsPathToRemote(cwd, letter, remoteRoot);
  return {
    kind: 'ssh',
    cwd,
    shell,
    sshTarget,
    remotePath,
    sshArgs,
  };
}

/**
 * @param {string} filePath
 */
export function resolveFileTarget(filePath) {
  const dir = dirname(pathResolve(filePath));
  const base = resolveTarget(dir);
  return { ...base, filePath: pathResolve(filePath), fileDir: dir };
}
