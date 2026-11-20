/* Only the neutral interface is cached. Private responses never enter this cache. */
const version = 'jac-attendance-interface-v3';
const files = ['index.html', 'style.css', 'storage.js', 'biometrics.js', 'app.js'];
const paths = files.map(file => new URL(file, self.registration.scope).href);
self.addEventListener('install', event => event.waitUntil(
  caches.open(version).then(cache => cache.addAll(paths.map(path => new Request(path, {
    cache: 'reload', credentials: 'same-origin', redirect: 'error'
  })))).then(() => self.skipWaiting())
));
self.addEventListener('activate', event => event.waitUntil(
  caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('jac-attendance-interface-') && k !== version)
    .map(k => caches.delete(k)))).then(() => self.clients.claim())
));
self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  url.search = '';
  const cached = url.href === self.registration.scope ? paths[0] : paths.find(path => path === url.href);
  if (!cached) return;
  // Honor the server's permission and login responses whenever it can be reached.
  event.respondWith(fetch(event.request).catch(async () => (await caches.match(cached, {cacheName: version})) || Response.error()));
});
