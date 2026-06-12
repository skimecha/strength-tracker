const CACHE = 'lockin-strength-v2.10.2';
const ASSETS = ['./'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  // Network-first for page navigations so the latest app shell always loads
  // when online; fall back to the cached shell only when offline. This avoids
  // serving a stale index.html after a deploy.
  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req)
        .then(res => {
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put('./', copy));
          return res;
        })
        .catch(() => caches.match('./').then(r => r || caches.match(req)))
    );
    return;
  }
  // Cache-first for other same-origin assets.
  e.respondWith(caches.match(req).then(cached => cached || fetch(req)));
});
