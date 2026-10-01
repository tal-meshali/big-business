// Rebuilds the rules-engine bundle inlined in big-business.html from
// server/src/engine, so the browser table plays by the same rules and bots
// as the server. Run after changing the engine: node web/build.mjs
// (uses esbuild from server/node_modules; run `npm ci` in server/ once).
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const esbuild = createRequire(join(here, '../server/package.json'))('esbuild');

const result = esbuild.buildSync({
  entryPoints: [join(here, 'engine-entry.ts')],
  bundle: true,
  format: 'iife',
  globalName: 'BB',
  minify: true,
  target: 'es2020',
  write: false,
  logLevel: 'warning',
});
const bundle = result.outputFiles[0].text.trim();

const page = join(here, 'big-business.html');
const html = readFileSync(page, 'utf8');
const start = html.indexOf('<script>var BB=');
if (start < 0) throw new Error('big-business.html has no <script>var BB= block');
const end = html.indexOf('</script>', start);
const next = html.slice(0, start) + '<script>' + bundle + '\n' + html.slice(end);
writeFileSync(page, next);
console.log(next === html ? 'engine bundle already current' : 'engine bundle updated');
