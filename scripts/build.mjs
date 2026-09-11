import { cp, mkdir, readdir, rm } from 'node:fs/promises';
import { join } from 'node:path';

const root = process.cwd();
const output = join(root, 'dist');
await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
for (const file of ['index.html', 'styles.css', 'app.js', 'logic.mjs']) await cp(join(root, file), join(output, file));
const publicDir = join(root, 'public');
for (const entry of await readdir(publicDir, { withFileTypes: true })) {
  if (entry.name === 'Bendy.zip' || entry.name === 'Hingely.zip') continue;
  if (entry.name === 'Foldly.zip' && process.env.BUILD_EXCLUDE_ZIP === '1') continue;
  await cp(join(publicDir, entry.name), join(output, entry.name), { recursive: true });
}
console.log('Built Foldly into dist/');
