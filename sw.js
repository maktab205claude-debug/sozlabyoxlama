// SözLab — sadə "app shell" service worker.
// Məqsəd: PWA/APK meyarlarını ödəmək və İNTERNET OLMAYANDA tətbiqin qabığını
// (HTML/CSS/JS) göstərə bilmək. Sayt tez-tez yenilənən aktiv layihə olduğu
// üçün strategiya "network-first"dir: HƏMİŞə əvvəlcə şəbəkədən ən yeni
// versiyanı çəkməyə çalışır, yalnız şəbəkə tamamilə əlçatmaz olanda (offline)
// köhnə keşlənmiş nüsxəni göstərir. Supabase sorğularına heç toxunmur.
const CACHE_NAME = 'sozlab-shell-v2';
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
    fetch(event.request)
      .then((resp) => {
        if (resp && resp.ok) {
          const copy = resp.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
        }
        return resp;
      })
      .catch(() => caches.match(event.request))
  );
});
