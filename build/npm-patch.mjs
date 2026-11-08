// Replace npm packages inside an unpacked Kibana distribution with pinned, integrity-checked releases.
// Usage: node npm-patch.mjs <kibana-root> <manifest.json>
// manifest: { "replace": [{ "path", "name", "version", "integrity" }],
//             "edit": [{ "path", "sha256", "why", "replace": [[find, replacement], ...] }], "remove": ["node_modules/..."] }
// An edit applies only to the exact original file (sha256), and each find string must occur exactly once.
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

const [root, manifestFile] = process.argv.slice(2);
if (!root || !manifestFile) {
  console.error('usage: node npm-patch.mjs <kibana-root> <manifest.json>');
  process.exit(2);
}
const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
const semver = createRequire(path.join(root, 'package.json'))('semver');
const registry = process.env.NPM_REGISTRY || 'https://registry.npmjs.org';
const cache = process.env.NPM_PATCH_CACHE || '/tmp/npm-patch-cache';
fs.mkdirSync(cache, { recursive: true });
// scratch space on the same filesystem as the distribution, so nested node_modules can be moved with rename()
const work = fs.mkdtempSync(path.join(path.dirname(path.resolve(root)), '.npm-patch-'));
process.on('exit', () => fs.rmSync(work, { recursive: true, force: true }));

const pkgCache = new Map();
const readPkg = (dir) => {
  if (pkgCache.has(dir)) return pkgCache.get(dir);
  let pkg = null;
  try {
    pkg = JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8'));
  } catch {
    pkg = null;
  }
  pkgCache.set(dir, pkg);
  return pkg;
};

// Every installed package directory: <x>/node_modules/<name> or <x>/node_modules/@scope/<name>.
function listPackages(base) {
  const out = [];
  const walk = (nm) => {
    let entries;
    try {
      entries = fs.readdirSync(nm, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      if (!e.isDirectory() || e.name.startsWith('.')) continue;
      const dirs = e.name.startsWith('@')
        ? fs.readdirSync(path.join(nm, e.name), { withFileTypes: true }).filter((s) => s.isDirectory()).map((s) => path.join(nm, e.name, s.name))
        : [path.join(nm, e.name)];
      for (const d of dirs) {
        const pkg = readPkg(d);
        if (pkg && pkg.name && pkg.version) out.push(d);
        walk(path.join(d, 'node_modules'));
      }
    }
  };
  walk(path.join(base, 'node_modules'));
  return out;
}

// Node.js resolution: <ancestor>/node_modules/<name> for every ancestor not named node_modules, up to the root.
function resolveFrom(pkgDir, name) {
  const top = path.resolve(root);
  let dir = path.resolve(pkgDir);
  for (;;) {
    if (path.basename(dir) !== 'node_modules') {
      const cand = path.join(dir, 'node_modules', name);
      if (readPkg(cand)) return cand;
    }
    if (dir === top) return null;
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

function parseRange(name, range) {
  if (typeof range !== 'string') return null;
  if (range.startsWith('npm:')) {
    const spec = range.slice(4);
    const at = spec.lastIndexOf('@');
    return at > 0 ? { name: spec.slice(0, at), range: spec.slice(at + 1) } : { name: spec, range: '*' };
  }
  if (/^(file|link|git|git\+|https?|workspace):/.test(range) || range.includes('/')) return null;
  return { name, range };
}

// Problems for one package: missing or out-of-range runtime dependencies.
function problemsOf(dir) {
  const pkg = readPkg(dir);
  const res = [];
  const peerMeta = pkg.peerDependenciesMeta || {};
  const groups = [
    ['dep', pkg.dependencies || {}],
    ['opt', pkg.optionalDependencies || {}],
    ['peer', pkg.peerDependencies || {}],
  ];
  for (const [kind, deps] of groups) {
    for (const [dep, raw] of Object.entries(deps)) {
      if (dep.startsWith('@types/')) continue; // type-only packages carry no runtime code
      const p = parseRange(dep, raw);
      if (!p) continue;
      const found = resolveFrom(dir, dep);
      if (!found) {
        if (kind === 'opt' || (kind === 'peer' && peerMeta[dep]?.optional)) continue;
        res.push({ from: dir, dep, range: raw, got: null, kind });
        continue;
      }
      const got = readPkg(found).version;
      if (semver.validRange(p.range) && !semver.satisfies(got, p.range, { includePrerelease: true })) {
        res.push({ from: dir, dep, range: raw, got, at: found, kind });
      }
    }
  }
  return res;
}

const rel = (p) => path.relative(root, p);
const key = (pr) => `${rel(pr.from)} -> ${pr.dep}@${pr.range} (got ${pr.got ?? 'missing'})`;

function fetchTarball(name, version, integrity) {
  const base = name.startsWith('@') ? name.split('/')[1] : name;
  const file = path.join(cache, `${name.replace('/', '__')}-${version}.tgz`);
  if (!fs.existsSync(file)) {
    const url = `${registry}/${name}/-/${base}-${version}.tgz`;
    execFileSync('curl', ['-fsSL', '--retry', '8', '--retry-all-errors', '--connect-timeout', '30', '--speed-limit', '1024', '--speed-time', '60', '-o', `${file}.part`, url], { stdio: 'inherit' });
    fs.renameSync(`${file}.part`, file);
  }
  const [algo, b64] = integrity.split('-');
  const actual = createHash(algo).update(fs.readFileSync(file)).digest('base64');
  if (actual !== b64) {
    fs.rmSync(file, { force: true });
    throw new Error(`integrity mismatch for ${name}@${version}`);
  }
  return file;
}

const baseline = new Set(listPackages(root).flatMap(problemsOf).map(key));

const replaced = new Set();
for (const r of manifest.replace || []) {
  const dest = path.join(root, r.path);
  const tgz = fetchTarball(r.name, r.version, r.integrity);
  const tmp = fs.mkdtempSync(path.join(work, 'x-'));
  execFileSync('tar', ['-xzf', tgz, '-C', tmp, '--strip-components=1', '--no-same-owner']);
  const pkg = readPkg(tmp);
  if (!pkg || pkg.name !== r.name || pkg.version !== r.version) throw new Error(`unexpected tarball content for ${r.name}@${r.version}`);
  const old = readPkg(dest);
  // Replace the package's files in place. Its nested node_modules stays where it is (no directory renames:
  // overlayfs in image builds refuses to rename directories from lower layers), except for "fresh" entries,
  // whose nested tree is rebuilt by later manifest entries.
  if (fs.existsSync(dest)) {
    for (const e of fs.readdirSync(dest)) {
      if (e === 'node_modules' && !r.fresh) continue;
      fs.rmSync(path.join(dest, e), { recursive: true, force: true });
    }
  } else {
    fs.mkdirSync(dest, { recursive: true });
  }
  for (const e of fs.readdirSync(tmp)) {
    if (e === 'node_modules') continue;
    fs.cpSync(path.join(tmp, e), path.join(dest, e), { recursive: true });
  }
  fs.rmSync(tmp, { recursive: true, force: true });
  replaced.add(path.resolve(dest));
  console.log(`replaced ${r.path}: ${old ? old.version : '(new)'} -> ${r.version}`);
}
for (const e of manifest.edit || []) {
  const file = path.join(root, e.path);
  let text = fs.readFileSync(file, 'utf8');
  const sum = createHash('sha256').update(text).digest('hex');
  if (sum !== e.sha256) throw new Error(`edit ${e.path}: sha256 ${sum}, expected ${e.sha256}`);
  for (const [find, replacement] of e.replace) {
    const n = text.split(find).length - 1;
    if (n !== 1) throw new Error(`edit ${e.path}: ${JSON.stringify(find)} occurs ${n} times, expected once`);
    text = text.replace(find, () => replacement);
  }
  fs.writeFileSync(file, text);
  console.log(`edited ${e.path}: ${e.replace.length} change(s), ${e.why}`);
}
for (const p of manifest.remove || []) {
  fs.rmSync(path.join(root, p), { recursive: true, force: true });
  console.log(`removed ${p}`);
}
pkgCache.clear();

// Strict: packages we installed must have every runtime dependency satisfied.
// Dependents whose declared range a deliberate security upgrade exceeds are reported as overrides.
let failed = false;
for (const pr of listPackages(root).flatMap(problemsOf)) {
  const k = key(pr);
  if (replaced.has(path.resolve(pr.from))) {
    console.error(`UNSATISFIED in patched package: ${k}`);
    failed = true;
  } else if (baseline.has(k)) {
    continue;
  } else if (pr.at && replaced.has(path.resolve(pr.at))) {
    console.log(`override: ${k}`);
  } else {
    console.error(`NEW PROBLEM: ${k}`);
    failed = true;
  }
}
if (failed) process.exit(1);
console.log(`npm-patch: ${replaced.size} packages replaced, dependency check passed`);
