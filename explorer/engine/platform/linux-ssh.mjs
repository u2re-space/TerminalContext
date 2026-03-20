/**
 * Interactive SSH is handled by {@link ../launcher/remote.mjs} and the OpenSSH client.
 * Use `ssh2` from this project only for programmatic sessions (tests/automation).
 */
export { buildSshArgv, buildRemoteShellCommand, shellQuotePosix } from '../launcher/remote.mjs';
