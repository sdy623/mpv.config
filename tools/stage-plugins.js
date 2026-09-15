const fs = require('fs-extra');
const path = require('path');
const { execFileSync } = require('child_process');
const root = path.resolve(__dirname, '..');

async function stagePlugins(destination) {
  const manifest = {};
  for (const name of ['mpv-anime-xray', 'mpv-bluray']) {
    const source = path.join(root, 'plugins', name);
    if (!fs.existsSync(path.join(source, 'main.lua'))) {
      throw new Error(`Missing ${name}; run git submodule update --init --recursive`);
    }
    const git = (...args) => execFileSync('git', ['-C', source, ...args], {encoding: 'utf8'});
    if (git('status', '--porcelain', '--untracked-files=no').trim()) {
      throw new Error(`${name} has uncommitted changes; commit and pin the submodule first`);
    }
    const commit = git('rev-parse', 'HEAD').trim();
    const entry = execFileSync('git', ['-C', root, 'ls-files', '--stage', '--', `plugins/${name}`], {encoding: 'utf8'});
    const pinned = /^160000 ([a-f0-9]{40,64}) 0\t/.exec(entry);
    if (!pinned || pinned[1] !== commit) {
      throw new Error(`${name} does not match the staged gitlink; pin its commit before building`);
    }
    const files = git('ls-tree', '-rz', '--name-only', 'HEAD').split('\0').filter(Boolean);
    const output = path.resolve(destination, 'scripts', name);
    for (const file of files) {
      if (file.split('/').some(p => ['.git', '.venv', 'cache', 'data', '__pycache__'].includes(p)) || /KEYDB|\.(?:key|pem|pfx|p12|sqlite3?|log)$/i.test(file)) {
        throw new Error(`Runtime/private file committed in ${name}: ${file}`);
      }
      const target = path.resolve(output, file);
      if (!target.startsWith(output + path.sep) || fs.lstatSync(path.join(source, file)).isSymbolicLink()) {
        throw new Error(`Unsafe plugin file: ${name}/${file}`);
      }
      await fs.ensureDir(path.dirname(target));
      const content = execFileSync('git', ['-C', source, 'show', `${commit}:${file}`]);
      await fs.writeFile(target, content);
    }
    for (const file of files.filter(f => f.startsWith('script-opts/') && f.endsWith('.conf'))) {
      const target = path.join(destination, file);
      if (!fs.existsSync(target)) await fs.copy(path.join(output, file), target);
    }
    manifest[name] = {repository: `https://github.com/sdy623/${name}`, commit};
  }
  await fs.writeJson(path.join(destination, 'plugin-versions.json'), manifest, {spaces: 2});
}
module.exports = {stagePlugins};
