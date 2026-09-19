// SözLab — "app shell" service worker.
//
// MƏQSƏD: məktəbin Wi-Fi-ı bir an ilişsə belə sayt açıq qalsın. Sinifdə və
// sunumda ən pis ssenari ağ ekrandır — bu fayl məhz onun qarşısını alır.
//
// STRATEGİYA (v6-dan etibarən dəyişdirilib):
//   • Qabıq (HTML/manifest)  → stale-while-revalidate
//       Keşdəki nüsxə DƏRHAL göstərilir (offline da, zəif şəbəkədə də),
//       paralel olaraq arxa planda ən yeni versiya çəkilib keşə yazılır.
//       Yəni istifadəçi heç vaxt gözləmir, növbəti açılışda yeni versiya gəlir.
//   • Data faylları (/data/…) → cache-first
//       Korpus və AI datası böyükdür və nadir dəyişir; bir dəfə endirilib
//       saxlanılır, sonrakı açılışlarda şəbəkəyə heç toxunmur.
//   • Şəkillər (/school205/, /icons/) → cache-first
//   • Supabase və digər xarici sorğular → HEÇ TOXUNULMUR (həmişə canlı).
//
// Köhnə "network-first" strategiyası internet yavaş olanda səhifəni
// gözlədirdi; offline rejimdə isə yalnız fetch tam uğursuz olandan sonra
// keşə düşürdü. İndi keş birinci, şəbəkə arxa plandadır.
const CACHE_NAME = 'sozlab-shell-v6';
const SHELL_FILES = ['/', '/index.html', '/manifest.json'];

// Bu yollar üçün "əvvəlcə keş" işləyir (böyük, nadir dəyişən fayllar)
const CACHE_FIRST = [/^\/data\//, /^\/school205\//, /^\/icons\//];

const isCacheFirst = (path) => CACHE_FIRST.some((re) => re.test(path));

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_FILES).catch(() => {}))
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((names) => Promise.all(names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n))))
      .then(() => self.clients.claim())
  );
});

// Səhifə "yeni versiya var" mesajı ala bilsin deyə
async function broadcast(msg) {
  const clients = await self.clients.matchAll({ type: 'window' });
  clients.forEach((c) => c.postMessage(msg));
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  let url;
  try { url = new URL(req.url); } catch (e) { return; }
  if (url.origin !== self.location.origin) return;   // Supabase və s. — toxunma

  // ── 1) Böyük, nadir dəyişən fayllar: əvvəlcə keş ──
  if (isCacheFirst(url.pathname)) {
    event.respondWith(
      caches.match(req).then((hit) => {
        if (hit) return hit;
        return fetch(req).then((resp) => {
          if (resp && resp.ok) {
            const copy = resp.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(req, copy));
          }
          return resp;
        });
      }).catch(() => fetch(req))
    );
    return;
  }

  // ── 2) Qabıq və qalan statik fayllar: stale-while-revalidate ──
  event.respondWith(
    caches.open(CACHE_NAME).then(async (cache) => {
      const cached = await cache.match(req);

      const network = fetch(req)
        .then((resp) => {
          if (resp && resp.ok) {
            const copy = resp.clone();
            cache.put(req, copy);
            // Naviqasiya sorğusunda məzmun dəyişibsə səhifəyə xəbər ver
            if (req.mode === 'navigate' && cached) {
              Promise.all([cached.clone().text(), resp.clone().text()])
                .then(([a, b]) => { if (a.length !== b.length) broadcast({ type: 'sozlab-update' }); })
                .catch(() => {});
            }
          }
          return resp;
        })
        .catch(() => null);

      // Keşdə varsa dərhal onu qaytar, şəbəkə arxa planda işləsin
      if (cached) { event.waitUntil(network); return cached; }

      const fresh = await network;
      if (fresh) return fresh;

      // Nə keş, nə şəbəkə — naviqasiyada heç olmasa qabığı göstər
      if (req.mode === 'navigate') {
        const shell = (await cache.match('/index.html')) || (await cache.match('/'));
        if (shell) return shell;
      }
      return new Response('Oflayn', { status: 503, statusText: 'Oflayn' });
    })
  );
});
