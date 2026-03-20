/**
 * Convert a Windows path (e.g. C:\foo\bar) to a WSL path (/mnt/c/foo/bar).
 * @param {string} winPath
 */
export function windowsPathToWsl(winPath) {
  const m = /^([A-Za-z]):\\(.*)$/.exec(winPath.replace(/\//g, '\\'));
  if (!m) return winPath.replace(/\\/g, '/');
  const letter = m[1].toLowerCase();
  const rest = m[2].replace(/\\/g, '/');
  return `/mnt/${letter}/${rest}`;
}
