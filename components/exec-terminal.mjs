#!/usr/bin/env node
import { existsSync, lstatSync } from 'node:fs';
import { dirname, extname, resolve as pathResolve } from 'node:path';

import { loadAssociationMap, resolveTarget } from '../explorer/engine/launcher/resolve.mjs';
import {
  buildRemoteFileRunCommand,
  buildRemoteShellCommand,
  buildSshArgv,
} from '../explorer/engine/launcher/remote.mjs';
import { getSudoPath } from '../explorer/engine/launcher/sudo.mjs';
import { openLocalFolder, openWithWtArgv, runLocalFile } from '../explorer/engine/platform/windows.mjs';

function parseArgs(argv) {
  const admin = argv.includes('--admin');
  const rest = argv.filter((a) => a !== '--admin');
  const cmd = rest[0];
  const targetPath = rest.length > 1 ? rest.slice(1).join(' ') : '';
  return { cmd, targetPath, admin };
}

function sudoForSpawn(admin) {
  if (!admin) return '';
  const p = getSudoPath();
  return p || '';
}

function normalizeWindowsOpenPath(raw) {
  if (!raw) return '';
  const t = raw.trim().replace(/^"+|"+$/g, '');
  if (/^[A-Za-z]:$/.test(t)) return `${t}\\`;
  return pathResolve(t);
}

function cmdOpen(rawPath, admin) {
  let cwd = rawPath ? normalizeWindowsOpenPath(rawPath) : process.cwd();
  if (!existsSync(cwd)) {
    console.error(`Path not found: ${cwd}`);
    process.exit(1);
  }
  if (lstatSync(cwd).isFile()) {
    cwd = dirname(cwd);
  }
  const resolved = resolveTarget(cwd);
  const sudoPath = sudoForSpawn(admin);
  if (admin && !sudoPath) {
    console.warn('terminal-context: no elevation helper (sudo/gsudo); opening unelevated.');
  }

  if (resolved.kind === 'local') {
    openLocalFolder(resolved.cwd, { admin: admin && !!sudoPath, sudoPath });
    return;
  }

  const remoteCmd = buildRemoteShellCommand(resolved.remotePath, resolved.shell);
  const wtArgs = buildSshArgv(resolved.sshTarget, remoteCmd, resolved.sshArgs);
  openWithWtArgv(resolved.cwd, wtArgs, { admin: admin && !!sudoPath, sudoPath });
}

function cmdRun(rawPath, admin) {
  const filePath = pathResolve(rawPath || '');
  if (!existsSync(filePath)) {
    console.error(`File not found: ${filePath}`);
    process.exit(1);
  }
  let associations;
  try {
    associations = loadAssociationMap();
  } catch (e) {
    console.error(e.message);
    process.exit(1);
  }
  const ext = extname(filePath).toLowerCase() || '';
  const assoc = associations[ext];
  if (!assoc) {
    console.error(`No association for extension "${ext}" in association.json`);
    process.exit(1);
  }

  const resolved = resolveTarget(filePath);
  const sudoPath = sudoForSpawn(admin);
  if (admin && !sudoPath) {
    console.warn('terminal-context: no elevation helper (sudo/gsudo); running unelevated.');
  }

  if (resolved.kind === 'local') {
    runLocalFile(filePath, assoc, { admin: admin && !!sudoPath, sudoPath });
    return;
  }

  const remoteCmd = buildRemoteFileRunCommand(resolved.remotePath, assoc);
  const wtArgs = buildSshArgv(resolved.sshTarget, remoteCmd, resolved.sshArgs);
  openWithWtArgv(resolved.cwd, wtArgs, { admin: admin && !!sudoPath, sudoPath });
}

function printHelp() {
  console.log(`terminal-context — open terminals from Explorer / SSH-mapped drives

Usage:
  terminal-context open [path] [--admin]   Open terminal in folder (default: cwd)
  terminal-context run  <file> [--admin]   Run script per association.json

Env:
  TERMINAL_CONTEXT_ROOT       Override project root (config path)
  TERMINAL_CONTEXT_USE_WT=0   Prefer PowerShell instead of Windows Terminal
  TERMINAL_CONTEXT_WT_EXTRA   Extra wt args (e.g. -w 0 to reuse first WT window)
  TERMINAL_CONTEXT_SSH_USE_WT=1  Run mapped-drive SSH via Windows Terminal (default: direct ssh.exe)
  TERMINAL_CONTEXT_WT_SSH_USE_D=1  Only with SSH_USE_WT: pass wt -d (often breaks on SSHFS)
  TERMINAL_CONTEXT_SUDO=auto|windows|gsudo|none
  TERMINAL_CONTEXT_SSH_LOGIN_WRAPPER=auto|bash|zsh|none
`);
}

const { cmd, targetPath, admin } = parseArgs(process.argv.slice(2));

if (!cmd || cmd === '-h' || cmd === '--help') {
  printHelp();
  process.exit(cmd ? 0 : 1);
}

try {
  if (cmd === 'open') {
    cmdOpen(targetPath, admin);
  } else if (cmd === 'run') {
    if (!targetPath) {
      console.error('run requires a file path');
      process.exit(1);
    }
    cmdRun(targetPath, admin);
  } else {
    console.error(`Unknown command: ${cmd}`);
    printHelp();
    process.exit(1);
  }
} catch (e) {
  console.error(e.message || e);
  process.exit(1);
}
