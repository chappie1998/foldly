import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = resolve(process.cwd());
const args = process.argv.slice(2);
const getArg = (name, fallback) => {
  const index = args.indexOf(name);
  return index >= 0 && args[index + 1] ? args[index + 1] : fallback;
};
const host = getArg('--host', '127.0.0.1');
const port = Number(getArg('--port', '5173'));
const mime = { '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8', '.svg': 'image/svg+xml', '.zip': 'application/zip' };
const pageFiles = new Map([['/', 'index.html'], ['/index.html', 'index.html'], ['/styles.css', 'styles.css'], ['/app.js', 'app.js'], ['/logic.mjs', 'logic.mjs']]);
const publicFiles = new Map([['/favicon.svg', 'favicon.svg'], ['/Foldly.zip', 'Foldly.zip']]);

export function createFoldlyServer(baseRoot = root) {
  return createServer((request, response) => {
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      response.writeHead(405, { Allow: 'GET, HEAD', 'Content-Type': 'text/plain; charset=utf-8' });
      response.end('Method not allowed');
      return;
    }
    let pathname;
    try {
      pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    } catch {
      response.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8' });
      response.end('Bad request');
      return;
    }
    const pageFile = pageFiles.get(pathname);
    const publicFile = publicFiles.get(pathname);
    const filePath = pageFile ? join(baseRoot, pageFile) : publicFile ? join(baseRoot, 'public', publicFile) : null;
    if (!filePath || !existsSync(filePath) || !statSync(filePath).isFile()) {
      response.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      response.end('Not found');
      return;
    }
    response.writeHead(200, { 'Content-Type': mime[extname(filePath)] || 'application/octet-stream', 'Cache-Control': 'no-cache', 'Content-Length': statSync(filePath).size });
    if (request.method === 'HEAD') { response.end(); return; }
    const stream = createReadStream(filePath);
    stream.on('error', () => {
      if (!response.headersSent) response.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
      response.end('Unable to read file');
    });
    stream.pipe(response);
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  createFoldlyServer().listen(port, host, () => console.log(`Foldly is running at http://${host}:${port}`));
}
