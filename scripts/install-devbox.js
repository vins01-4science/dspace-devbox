#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

const INSTALL_DIR = process.env.DEVBOX_INSTALL_DIR || path.join(os.homedir(), '.devbox');
const BIN_DIR = process.env.DEVBOX_BIN_DIR || path.join(os.homedir(), '.local', 'bin');
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'devbox-'));

function human(n) {
  return n < 1024 * 1024 ? `${(n / 1024).toFixed(0)} KiB` : `${(n / (1024 * 1024)).toFixed(1)} MiB`;
}

async function main() {
  const arch = process.arch === 'arm64' ? 'arm64' : process.arch === 'x64' ? 'amd64' : process.arch;
  const rel = await (await fetch('https://api.github.com/repos/jetify-com/devbox/releases/latest', {
    headers: { Accept: 'application/vnd.github+json', 'User-Agent': 'devbox-installer' }
  })).json();
  if (!rel.tag_name) throw new Error('Could not resolve latest devbox release');
  const url = `https://github.com/jetify-com/devbox/releases/download/${rel.tag_name}/devbox_${rel.tag_name}_linux_${arch}.tar.gz`;
  console.log(`Downloading ${url}`);
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) throw new Error(`HTTP ${res.status} fetching ${url}`);
  const buf = Buffer.from(await res.arrayBuffer());
  console.log(`Downloaded ${human(buf.length)}`);
  const tgz = path.join(TMP, 'devbox.tar.gz');
  fs.writeFileSync(tgz, buf);

  fs.mkdirSync(INSTALL_DIR, { recursive: true });
  execFileSync('tar', ['-xzf', tgz, '-C', INSTALL_DIR], { stdio: 'inherit' });
  fs.mkdirSync(BIN_DIR, { recursive: true });
  const src = path.join(INSTALL_DIR, 'devbox');
  const dst = path.join(BIN_DIR, 'devbox');
  try { fs.unlinkSync(dst); } catch {}
  fs.symlinkSync(src, dst);
  console.log(`Installed devbox -> ${src}`);
  console.log(`Symlinked ${dst}`);
  try { fs.rmSync(TMP, { recursive: true, force: true }); } catch {}

  const out = execFileSync(dst, ['--version'], { encoding: 'utf8' });
  console.log(out.trim());
  console.log(`PATH hint: add ${BIN_DIR} to your PATH (already configured if opencode runs it)`);
}

main().catch((e) => { console.error(e.message); process.exit(1); });