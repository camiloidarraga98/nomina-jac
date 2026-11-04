/** Generate the downloadable press PDF from the published landing's content.
 * Requires Playwright + a local Chromium. Never reads production or private data.
 * node scripts/build-press-pdf.mjs [output.pdf]
 */
import {createServer} from 'node:http';
import {readFile, writeFile, mkdir, access} from 'node:fs/promises';
import {dirname, resolve, extname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import assert from 'node:assert/strict';
import {PDFDocument} from 'pdf-lib';

const {chromium} = createRequire(import.meta.url)('playwright');
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = resolve(process.argv[2] || resolve(root, 'public/cumple-movistar/comunicado-de-prensa.pdf'));
const evidence = resolve(root, 'work/local/cumple-movistar/pdf');
await mkdir(evidence, {recursive: true});
const types = {'.html':'text/html; charset=utf-8', '.css':'text/css', '.js':'text/javascript', '.webp':'image/webp', '.woff2':'font/woff2'};
const server = createServer(async (request, response) => {
  let pathname = new URL(request.url, 'http://localhost').pathname;
  if (pathname === '/cumple-movistar') pathname = '/cumple-movistar/index.html';
  if (!pathname.startsWith('/cumple-movistar/')) { response.writeHead(404).end(); return; }
  const file = resolve(root, 'public', '.' + pathname);
  if (!file.startsWith(resolve(root, 'public/cumple-movistar') + '/')) { response.writeHead(404).end(); return; }
  try {
    const data = await readFile(file);
    response.writeHead(200, {'Content-Type': types[extname(file)] || 'application/octet-stream'}).end(data);
  } catch { response.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const installed = await access('/usr/bin/chromium').then(() => '/usr/bin/chromium', () => undefined);
const browser = await chromium.launch({executablePath: process.env.PRESS_CHROMIUM_PATH || installed, headless: true, args: ['--no-sandbox']});
try {
  const page = await browser.newPage({viewport: {width: 794, height: 1123}, deviceScaleFactor: 1});
  await page.route('**/*', route => new URL(route.request().url()).origin === origin ? route.continue() : route.abort());
  await page.goto(origin + '/cumple-movistar', {waitUntil: 'networkidle'});
  const source = await page.evaluate(() => {
    const html = selector => document.querySelector(selector).outerHTML;
    const hero = document.querySelector('.hero').cloneNode(true);
    hero.querySelectorAll('.hero-baseline,.button,.hero-eyebrow').forEach(element => element.remove());
    hero.querySelector('.portrait').removeAttribute('srcset');
    hero.querySelector('.portrait').removeAttribute('sizes');
    return {
      hero: hero.outerHTML, title: html('#release-title'), intro: html('.release-intro'),
      material: html('.material-link'), body: html('.release-body'), event: html('.event-sheet'),
      about: html('.about-promoter'), end: html('.end-mark'), contactsTitle: html('#contact-title'),
      contacts: html('.contact-grid'), date: document.querySelector('.article-heading .issue').textContent.trim(),
      text: [...document.querySelectorAll('[data-press-copy]')].map(element => element.textContent.replace(/\s+/g, ' ').trim()),
    };
  });
  assert.match(source.date, /^\d{2}\.\d{2}\.\d{4}$/, 'Use the release date shown on the landing');
  const css = await readFile(resolve(root, 'design/press-movistar/pdf.css'), 'utf8');
  const signature = '<img class="brand-signature" src="/cumple-movistar/assets/firma.webp" alt="Jhon Alex Castaño" width="850" height="249">';
  const header = (label, cover = false) => `<header class="running-header${cover ? ' light' : ''}">${signature}<span>${label}</span></header>`;
  const footer = number => `<footer class="running-footer"><a href="https://jhonalexcastano.com/cumple-movistar">jhonalexcastano.com/cumple-movistar</a><span>COMUNICADO DE PRENSA <b>${number} / 3</b></span></footer>`;
  const html = `<!doctype html><html lang="es-CO"><head><meta charset="utf-8"><title>El Cumpleaños del Rey del Chupe · Comunicado de prensa</title><style>${css}</style></head><body>
    <section class="pdf-page cover-page">
      <div class="cover-visual">${header('SALA DE PRENSA', true)}${source.hero}</div>
      <main class="cover-copy"><div class="article-heading"><span>COMUNICADO OFICIAL</span><span>${source.date} · BOGOTÁ, COLOMBIA</span></div>${source.title}${source.intro}${source.material}</main>
      ${footer(1)}
    </section>
    <section class="pdf-page story-page">
      ${header('EL CUMPLEAÑOS DEL REY DEL CHUPE')}
      <main class="story-content"><div class="section-kicker"><span>EL COMUNICADO</span><span>10 ABRIL 2027 · MOVISTAR ARENA</span></div>${source.body}</main>
      ${footer(2)}
    </section>
    <section class="pdf-page details-page">
      ${header('INFORMACIÓN PARA MEDIOS')}
      <main class="details-content">${source.event}${source.about}${source.end}<section class="contacts">${source.contactsTitle}${source.contacts}</section></main>
      ${footer(3)}
    </section>
  </body></html>`;
  await page.setContent(html, {waitUntil: 'networkidle'});
  await page.evaluate(async () => {
    document.querySelectorAll('img').forEach(image => { image.loading = 'eager'; });
    await document.fonts.ready;
    await Promise.all([...document.images].map(image => image.decode()));
  });
  const copied = await page.locator('[data-press-copy]').evaluateAll(elements => elements.map(element => element.textContent.replace(/\s+/g, ' ').trim()));
  assert.deepEqual(copied, source.text, 'The complete release must retain every source block in order');
  const layout = await page.locator('.pdf-page').evaluateAll(pages => pages.map(page => {
    const pageBox = page.getBoundingClientRect(), footerBox = page.querySelector('.running-footer').getBoundingClientRect();
    const content = page.querySelector('main'), contentBox = content.getBoundingClientRect();
    const violations = [...content.querySelectorAll('h1,h2,h3,p,a,dt,dd,[data-press-copy]')].filter(element => element.getBoundingClientRect().height).filter(element => {
      const box = element.getBoundingClientRect();
      return box.left < pageBox.left + 25 || box.right > pageBox.right - 25 || box.bottom > footerBox.top - 12 || box.top < pageBox.top;
    }).map(element => element.textContent);
    return {contentBottom: contentBox.bottom - pageBox.top, footerTop: footerBox.top - pageBox.top, violations};
  }));
  assert.equal(layout.length, 3);
  for (const [index, pageLayout] of layout.entries()) {
    assert.deepEqual(pageLayout.violations, [], `Page ${index + 1}: text must fit inside margins above its footer`);
    assert.ok(pageLayout.contentBottom <= pageLayout.footerTop - 12, `Page ${index + 1}: content must not overlap the footer`);
  }
  await writeFile(resolve(evidence, 'layout.json'), JSON.stringify(layout, null, 2));
  await writeFile(resolve(evidence, 'source-blocks.json'), JSON.stringify(source.text, null, 2));
  await writeFile(resolve(evidence, 'preview.html'), html);
  for (const [index, section] of (await page.locator('.pdf-page').all()).entries()) {
    await section.screenshot({path: resolve(evidence, `page-${index + 1}.png`)});
  }
  const bytes = await page.pdf({format:'A4', preferCSSPageSize:true, printBackground:true, tagged:true, outline:true});
  const pdf = await PDFDocument.load(bytes);
  assert.equal(pdf.getPageCount(), 3, 'The composed document must be exactly three pages');
  pdf.setTitle('Jhon Alex Castaño · El Cumpleaños del Rey del Chupe · Comunicado de prensa');
  pdf.setAuthor('JAC Music · Breakfast Live');
  pdf.setSubject('10 de abril de 2027 · Movistar Arena, Bogotá');
  pdf.setLanguage('es-CO');
  await mkdir(dirname(output), {recursive:true});
  await writeFile(output, await pdf.save());
  console.log(`Press PDF created: ${output} (3 pages; exact source content; margins verified).`);
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
