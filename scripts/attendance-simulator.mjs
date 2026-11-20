import {build} from 'esbuild';
import {basename, resolve} from 'node:path';

export async function simulatorWorker() {
  const path = resolve('scripts/attendance-simulator-worker.ts');
  const result = await build({
    entryPoints: [path], bundle: true, write: false, format: 'esm',
    platform: 'neutral', mainFields: ['module', 'main'], target: 'es2022',
    external: ['cloudflare:workers', 'node:*']
  });
  return {type: 'ESModule', path, contents: result.outputFiles[0].text};
}

// The native form is compiled into JACNomina. Bundle JAC's normal web form
// only if a browser actually asks for it.
export async function browserLoginAssets() {
  const result = await build({
    entryPoints: {acceso: 'scripts/attendance-access.tsx', styles: 'app/globals.css'},
    bundle: true, write: false, format: 'esm', platform: 'browser', conditions: ['browser', 'style'], outdir: 'work/local/asistencia',
    target: 'es2022', minify: true, define: {'process.env.NODE_ENV': '"production"'}
  });
  const assets = new Map();
  for (const file of result.outputFiles) {
    const js = basename(file.path) === 'acceso.js';
    assets.set('/_jac/acceso.' + (js ? 'js' : 'css'), {
      contents: file.contents, type: js ? 'text/javascript' : 'text/css'
    });
  }
  return assets;
}
