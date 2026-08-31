// SözLab — sadə "app shell" service worker.
// Məqsəd: PWA/APK meyarlarını ödəmək və tətbiqin qabığını (HTML/CSS/JS) offline
// keş etmək. Supabase sorğuları (canlı data) HƏMİŞə şəbəkədən gedir — yalnız
// statik qabıq keşlənir ki, məlumatlar köhnəlməsin.
const CACHE_NAME = 'sozlab-shell-v1';
const SHELL_FILES = ['/', '/index.html', '/manifest.json'];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_FILES).catch(() => {}))
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  // Yalnız GET + eyni origin + naviqasiya/statik fayl sorğularını keşlə;
  // Supabase və digər API çağırışlarına toxunma (şəbəkədən keç).
  if (event.request.method !== 'GET' || url.origin !== self.location.origin) return;

  event.respondWith(
    caches.match(event.request).then((cached) => {
      const network = fetch(event.request)
        .then((resp) => {
          if (resp && resp.ok) {
            const copy = resp.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
          }
          return resp;
        })
        .catch(() => cached);
      return cached || network;
    })
  );
});
