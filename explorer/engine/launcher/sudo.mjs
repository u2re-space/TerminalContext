import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { execSync } from 'node:child_process';

function findOnPath(exe) {
  try {
    const out = execSync(`where.exe ${exe}`, { encoding: 'utf8', windowsHide: true });
    const line = out.split(/\r?\n/).map((s) => s.trim()).find(Boolean);
    return line && existsSync(line) ? line : '';
  } catch {
    return '';
  }
}

/**
 * Returns a path to an elevation helper (Windows sudo or gsudo), or empty string.
 */
export function getSudoPath() {
  if (process.env.SUDO_PATH && existsSync(process.env.SUDO_PATH)) {
    return process.env.SUDO_PATH;
  }
  const mode = process.env.TERMINAL_CONTEXT_SUDO || 'auto';
  const sysRoot = process.env.SystemRoot || 'C:\\Windows';
  const winSudo = join(sysRoot, 'System32', 'sudo.exe');
  const gsudo = findOnPath('gsudo.exe') || findOnPath('gsudo');

  if (mode === 'gsudo') return gsudo;
  if (mode === 'windows') return existsSync(winSudo) ? winSudo : gsudo;
  if (mode === 'none') return '';

  if (mode === 'auto') {
    if (existsSync(winSudo)) return winSudo;
    return gsudo;
  }
  return existsSync(winSudo) ? winSudo : gsudo;
}
