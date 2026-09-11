import test from 'node:test';
import assert from 'node:assert/strict';
import { get } from 'node:http';
import { createFoldlyServer } from '../scripts/serve.mjs';

async function withServer(run) {
  const server = createFoldlyServer();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  try { await run(server.address().port); } finally { await new Promise((resolve) => server.close(resolve)); }
}

test('server exposes only the web allowlist', () => withServer(async (port) => {
  const index = await fetch(`http://127.0.0.1:${port}/`);
  const privateFile = await fetch(`http://127.0.0.1:${port}/package.json`);
  const traversal = await fetch(`http://127.0.0.1:${port}/native/Package.swift`);
  assert.equal(index.status, 200);
  assert.equal(privateFile.status, 404);
  assert.equal(traversal.status, 404);
}));

test('server rejects malformed URI encoding without crashing', () => withServer(async (port) => {
  const status = await new Promise((resolve, reject) => {
    get({ host: '127.0.0.1', port, path: '/%E0%A4%A' }, (response) => {
      response.resume();
      response.on('end', () => resolve(response.statusCode));
    }).on('error', reject);
  });
  assert.equal(status, 400);
  assert.equal((await fetch(`http://127.0.0.1:${port}/`)).status, 200);
}));
