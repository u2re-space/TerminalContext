import assert from 'node:assert/strict';
import { windowsPathToRemote, resolveTarget, getProjectRoot } from '../explorer/engine/launcher/resolve.mjs';
import { buildRemoteShellCommand } from '../explorer/engine/launcher/remote.mjs';

assert.equal(windowsPathToRemote('H:\\a\\b', 'H', '/home/u2re-dev/'), '/home/u2re-dev/a/b');
assert.equal(windowsPathToRemote('H:\\', 'H', '/home/u2re-dev/'), '/home/u2re-dev');

const rc = buildRemoteShellCommand('/home/x', 'bash');
assert.match(rc, /cd/);

const root = getProjectRoot();
assert.ok(root.length > 2);

const local = resolveTarget(root);
assert.equal(local.kind, 'local');

console.log('run-tests: ok');
