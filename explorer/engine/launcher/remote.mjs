import { dirname as posixDirname } from 'node:path/posix';

/**
 * Escape a string for use inside single-quoted POSIX shell segments.
 */
export function shellQuotePosix(s) {
  return `'${String(s).replace(/'/g, `'\\''`)}'`;
}

function loginWrapperFromEnv() {
  const w = (process.env.TERMINAL_CONTEXT_SSH_LOGIN_WRAPPER || 'auto').toLowerCase();
  if (w === 'none') return null;
  if (w === 'bash' || w === 'zsh') return w;
  return 'auto';
}

/**
 * @param {string} shell e.g. bash, zsh, sh
 */
function pickExecShell(shell) {
  const s = (shell || 'bash').toLowerCase();
  if (s.includes('zsh')) return 'zsh';
  if (s.includes('bash')) return 'bash';
  return 'bash';
}

/**
 * Remote command: cd and drop into login shell.
 * @param {string} remotePath unix path
 * @param {string} shell from disks.json
 */
export function buildRemoteShellCommand(remotePath, shell) {
  const wrap = loginWrapperFromEnv();
  const exe = pickExecShell(shell);
  const pathQ = shellQuotePosix(remotePath);

  if (wrap === null) {
    return `cd ${pathQ} || exit 1; exec ${exe}`;
  }
  const use = wrap === 'auto' ? exe : wrap;
  return `cd ${pathQ} || exit 1; exec ${use} -l`;
}

/**
 * @param {string} sshTarget user@host
 * @param {string} remoteCmd single remote command string
 * @param {string[]} extraArgs optional extra args between ssh and target
 * @returns {string[]}
 */
export function buildSshArgv(sshTarget, remoteCmd, extraArgs = []) {
  const argv = ['ssh', '-t'];
  for (const a of extraArgs) argv.push(a);
  argv.push(sshTarget, remoteCmd);
  return argv;
}

/**
 * Run a file on the remote host (SSH session, non-interactive script run then exit).
 * @param {string} remotePath unix path to file on remote
 * @param {{ executor?: string }} assoc
 */
export function buildRemoteFileRunCommand(remotePath, assoc) {
  const ex = String(assoc.executor || 'node').toLowerCase();
  const rp = remotePath.replace(/\\/g, '/');
  const dir = posixDirname(rp);
  const f = shellQuotePosix(rp);
  const d = shellQuotePosix(dir);
  if (ex === 'node' || ex === 'cjs' || ex === 'mjs') return `cd ${d} || exit 1; exec node ${f}`;
  if (ex === 'tsx' || ex === 'ts') return `cd ${d} || exit 1; exec npx --yes tsx ${f}`;
  if (ex === 'bash' || ex === 'sh') return `cd ${d} || exit 1; exec bash ${f}`;
  if (ex === 'python3' || ex === 'python') return `cd ${d} || exit 1; exec python3 ${f}`;
  if (ex === 'pwsh' || ex === 'powershell') return `cd ${d} || exit 1; exec pwsh ${f}`;
  return `cd ${d} || exit 1; exec node ${f}`;
}
