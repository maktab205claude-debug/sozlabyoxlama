#!/usr/bin/env node
/**
 * SözLab — az_corpus → strukturlaşdırılmış oyun datasetləri
 * ─────────────────────────────────────────────────────────
 * Giriş : az_corpus-v1.0/data.json  (4.983 sənəd, Public Domain)
 *         word_pool.json            (81.932 doğru Azərbaycan sözü — orfoqrafiya lüğəti)
 *         scripts/corpus/existing-words.json (SözLab lüğətində olan sözlər — təkrarın qarşısını alır)
 *
 * Çıxış : data/corpus/sentences.json  — “Cümlə Tamamla” oyunu
 *         data/corpus/passages.json   — “Mövzu Tap” oyunu
 *         data/corpus/candidates.json — lüğətə namizəd sözlər (məna ƏL İLƏ yazılır)
 *         data/corpus/meta.json       — statistika və mənbə məlumatı
 *
 * QAYDA: bu skript HEÇ BİR söz mənası uydurmur. Korpusdan yalnız KORPUSDA
 * ƏSLİNDƏ OLAN şeylər çıxarılır — cümlələr, mətn parçaları, mövzular,
 * tezliklər. Lüğət mənaları ayrıca, əl ilə yazılır (words-meanings.json).
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '../..');
const CORPUS = process.env.AZ_CORPUS ||
  '/mnt/user-data/uploads/github ai/az_corpus-v1.0/data.json';
const OUT = path.join(ROOT, 'data/corpus');

// ── Azərbaycan dilinə uyğun kiçik/böyük hərf ───────────────────────────
const AZ_LOWER = { 'İ': 'i', 'I': 'ı', 'Ə': 'ə', 'Ö': 'ö', 'Ü': 'ü', 'Ş': 'ş', 'Ç': 'ç', 'Ğ': 'ğ' };
function azLower(s) {
  return s.replace(/[İIƏÖÜŞÇĞ]/g, c => AZ_LOWER[c]).toLowerCase();
}
function azUpperFirst(s) {
  const c = s.charAt(0);
  const up = { 'i': 'İ', 'ı': 'I', 'ə': 'Ə', 'ö': 'Ö', 'ü': 'Ü', 'ş': 'Ş', 'ç': 'Ç', 'ğ': 'Ğ' }[c];
  return (up || c.toUpperCase()) + s.slice(1);
}

const AZ_LETTERS = 'a-zçəğıöşüA-ZÇƏĞIİÖŞÜ';
const WORD_RE = new RegExp(`[${AZ_LETTERS}]+(?:-[${AZ_LETTERS}]+)?`, 'g');

// Oyunda hədəf ola bilməyən köməkçi sözlər
const STOP = new Set(`və ki də da bu o bir çox az heç hər kimi üçün ilə görə sonra əvvəl
ancaq amma lakin çünki əgər ya yaxud nə necə niyə harada haçan kim hansı belə elə
var yox idi imiş olub olan olaraq olub olmuş edir etdi etmək etmə etmiş olmaq olur
mən sən biz siz onlar özü özünü bizim sizin onun mənim sənim onların
artıq daha yenə hələ indi bəli xeyr deyil isə ilk son digər bütün bəzi bəli ən
gün il ay saat dəfə kimi qədər kimi üzrə haqqında arasında içində üstündə altında
şey iş yer vaxt zaman hal söz adam insan xalq ölkə dövlət şəhər kənd ev yol əl göz baş
dedi deyir söylədi bildirib bildirir qeyd etdi görə görə əsasən habelə yəni məsələn`
  .split(/\s+/).filter(Boolean));

// ── Yükləmə ───────────────────────────────────────────────────────────
function loadCorpus() {
  let raw = fs.readFileSync(CORPUS, 'utf8');
  // Upstream faylda bir yerdə qırıq JSON var: "}\n2,\n{" → "},\n{"
  raw = raw.replace(/\}\s*\n\d+,\s*\n\s*\{/g, '},\n    {');
  return JSON.parse(raw);
}
// word_pool.json = SözLab-ın süzülmüş "mənalı söz" hovuzu (81.932 söz).
// DİQQƏT: bu TAM orfoqrafiya lüğəti DEYİL — "bir", "yol", "ev" kimi çox
// işlək qısa sözlər orada yoxdur. Ona görə iki ayrı ölçüdən istifadə edirik:
//   POOL      → sözün "lüğətə dəyər" olduğunu göstərən MÜSBƏT siqnal
//   corpusFreq→ sözün ümumiyyətlə düzgün yazıldığını göstərən (OCR zibilini kəsən) ölçü
const POOL = new Set(JSON.parse(fs.readFileSync(path.join(ROOT, 'word_pool.json'), 'utf8')).map(azLower));
let CF = new Map();                       // korpus tezliyi (1-ci keçiddə doldurulur)
const cf = w => CF.get(azLower(w)) || 0;
const EXISTING = new Set(
  JSON.parse(fs.readFileSync(path.join(__dirname, 'existing-words.json'), 'utf8')).map(azLower)
);

// ── Mövzu taksonomiyası (korpusun sərbəst etiketləri → 10 sabit sinif) ──
const TOPIC_MAP = [
  [/tarix|qədim|orta əsr|müharibə|xanlıq|imperiya|sovet|inqilab/i, 'Tarix'],
  [/ədəbiyyat|şeir|poeziya|roman|hekayə|nağıl|dastan|yazıçı|şair/i, 'Ədəbiyyat'],
  [/siyasət|diplomat|beynəlxalq|hökumət|parlament|seçki|qanun/i, 'Siyasət'],
  [/iqtisad|maliyyə|bank|biznes|ticarət|neft|investisiya|büdcə/i, 'İqtisadiyyat'],
  [/idman|futbol|olimpiya|çempion|güləş|şahmat|voleybol|basketbol/i, 'İdman'],
  [/elm|fizika|kimya|riyaziyyat|biologiya|texnologiya|tədqiqat|kəşf|tibb|səhiyyə/i, 'Elm'],
  [/mədəniyyət|incəsənət|musiqi|teatr|kino|rəssam|muzey|festival/i, 'Mədəniyyət'],
  [/coğrafiya|iqlim|hava|ərazi|relyef|çay|dağ|göl|dəniz|ekologiya|təbiət/i, 'Coğrafiya'],
  [/təhsil|məktəb|universitet|tələbə|şagird|müəllim|tədris|imtahan/i, 'Təhsil'],
  [/cəmiyyət|sosial|ailə|münasibət|insan|əhali|gənclər|sağlamlıq|həyat/i, 'Cəmiyyət']
];
const TOPICS = [...new Set(TOPIC_MAP.map(t => t[1]))];
function mapTopic(rec) {
  const s = `${rec.topic || ''} ${rec.category || ''}`;
  for (const [re, name] of TOPIC_MAP) if (re.test(s)) return name;
  return null;
}

// ── Mətn keyfiyyət süzgəcləri ─────────────────────────────────────────
const GOOD_QUALITY = new Set(['yüksək', 'yaxşı', 'akademik', 'normal']);
function qualityOk(rec) {
  return GOOD_QUALITY.has(azLower(String(rec.quality || '')));
}

function splitSentences(text) {
  return String(text || '')
    .replace(/\s+/g, ' ')
    .split(/(?<=[.!?…])\s+(?=[A-ZÇƏĞIİÖŞÜ"“])/)
    .map(s => s.trim())
    .filter(Boolean);
}

/** Cümlə oyun üçün yararlıdırmı? */
function sentenceOk(s) {
  if (s.length < 45 || s.length > 155) return false;
  if (!/[.!?…]$/.test(s)) return false;
  if (/\d/.test(s)) return false;                       // rəqəm → korpus səs-küyü
  if (/[<>{}\[\]|@#$%^*_=+~`\/\\]/.test(s)) return false;
  if ((s.match(/"/g) || []).length % 2) return false;    // qoşa dırnaq balanssız
  if ((s.match(/\(/g) || []).length !== (s.match(/\)/g) || []).length) return false;
  if (/\.\s*\.|\s\.\s/.test(s)) return false;            // "söz . söz" kimi qırıqlar
  if (/\b[bcdfghjklmnpqrstvxz]{4,}\b/i.test(s)) return false;
  const words = s.match(WORD_RE) || [];
  if (words.length < 7 || words.length > 20) return false;
  // OCR zibilini kəsmək üçün korpus tezliyindən istifadə edilir:
  // düzgün yazılmış Azərbaycan sözü korpusda dəfələrlə təkrarlanır,
  // OCR səhvi isə (məs. "atasıgildən", "toyuqxoruz") demək olar ki, təkdir.
  let rare = 0;
  for (const w of words) {
    if (cf(w) < 4) rare++;
    if (cf(w) < 2 && azLower(w).length > 6) return false; // tam təkdir → şübhəli
  }
  if (rare / words.length > 0.2) return false;
  return true;
}

/** Sözü cümlədə "___" ilə əvəz edir; söz tam söz kimi tapılmasa null qaytarır */
function blankOut(sentence, word) {
  const isLetter = ch => ch && new RegExp(`[${AZ_LETTERS}]`).test(ch);
  let from = 0;
  for (;;) {
    const i = sentence.indexOf(word, from);
    if (i < 0) return null;
    const before = sentence[i - 1], after = sentence[i + word.length];
    if (!isLetter(before) && !isLetter(after)) {
      return sentence.slice(0, i) + '___' + sentence.slice(i + word.length);
    }
    from = i + 1;
  }
}

/** Cümlədə boşluq üçün ən uyğun sözü seç */
function pickTarget(s) {
  const words = s.match(WORD_RE) || [];
  const cands = [];
  for (const w of words) {
    const lw = azLower(w);
    if (lw.length < 5 || lw.length > 14) continue;
    if (STOP.has(lw)) continue;
    if (cf(w) < 6) continue;                             // tanınmış, təkrarlanan söz
    if (!POOL.has(lw)) continue;                         // YALNIZ lüğət forması — "sözləri",
                                                         // "yaşlarından" kimi hallanmış
                                                         // formalar boşluğa hədəf olmur
    if (w[0] !== lw[0]) continue;                        // xüsusi ad deyil
    // cümlədə yalnız bir dəfə keçsin ki, boşluq birmənalı olsun
    const occ = words.filter(x => azLower(x) === lw).length;
    if (occ !== 1) continue;
    cands.push({ w, lw });
  }
  if (!cands.length) return null;
  cands.sort((a, b) => b.lw.length - a.lw.length);       // ən mənalı (uzun) söz
  return cands[0];
}

// ── Əsas ──────────────────────────────────────────────────────────────
function main() {
  console.log('→ Korpus yüklənir:', CORPUS);
  const data = loadCorpus();
  console.log('  ', data.length, 'sənəd');

  // ── 1-ci keçid: korpus tezlik lüğəti ──
  for (const rec of data) {
    const t = rec.cleaned_text || rec.text || '';
    for (const w of (t.match(WORD_RE) || [])) {
      const lw = azLower(w);
      CF.set(lw, (CF.get(lw) || 0) + 1);
    }
  }
  console.log('   tezlik lüğəti:', CF.size, 'fərqli söz forması');

  const sentences = [];
  const passages = [];
  const freq = new Map();          // lüğət namizədləri: söz → {n, ex:[], src:Set}
  const seenSent = new Set();
  const stats = { docs: 0, skippedQuality: 0, noTopic: 0 };

  for (const rec of data) {
    const clean = rec.cleaned_text || rec.text || '';
    if (!clean || clean.length < 120) continue;
    if (!qualityOk(rec)) { stats.skippedQuality++; continue; }
    stats.docs++;

    const topic = mapTopic(rec);
    const sents = splitSentences(clean);

    // ── A) Cümlə Tamamla ──
    for (const s of sents) {
      if (!sentenceOk(s)) continue;
      const key = azLower(s).replace(/[^a-zçəğıöşü ]/g, '').slice(0, 60);
      if (seenSent.has(key)) continue;
      const t = pickTarget(s);
      if (!t) continue;
      // DİQQƏT: JS-də \b yalnız ASCII söz simvolları ilə işləyir, ona görə
      // "istifadəyə" kimi 'ə' ilə bitən sözdə \b...\b HEÇ NƏ əvəz etmir.
      // Buna görə boşluq indeks üzrə, əl ilə qoyulur.
      const blanked = blankOut(s, t.w);
      if (!blanked) continue;
      seenSent.add(key);
      sentences.push({ s: blanked, a: t.w, topic: topic || 'Cəmiyyət', src: rec.source });
    }

    // ── B) Mövzu Tap ──
    if (topic) {
      let p = sents.filter(x => x.length > 40).slice(0, 4).join(' ');
      if (p.length > 460) p = p.slice(0, 450).replace(/\s\S*$/, '') + '…';
      // Mövzunun adı mətndə birbaşa keçirsə — tapşırıq çox asan olur, atırıq
      const tooEasy = new RegExp(azLower(topic).slice(0, 6), 'i').test(azLower(p));
      if (p.length >= 150 && !tooEasy) {
        passages.push({ p, t: topic, src: rec.source, kw: (rec.keywords || []).slice(0, 4) });
      }
    } else stats.noTopic++;

    // ── C) Lüğət namizədləri ──
    for (const s of sents) {
      if (!sentenceOk(s)) continue;
      for (const w of (s.match(WORD_RE) || [])) {
        const lw = azLower(w);
        if (lw.length < 5 || lw.length > 13) continue;
        if (STOP.has(lw)) continue;
        if (!POOL.has(lw)) continue;                     // "lüğətə dəyər" müsbət siqnalı
        if (EXISTING.has(lw)) continue;                  // artıq SözLab lüğətindədir
        if (w[0] !== lw[0]) continue;
        let e = freq.get(lw);
        if (!e) freq.set(lw, e = { n: 0, ex: [], src: new Set() });
        e.n++;
        e.src.add(rec.source);
        if (e.ex.length < 3 && s.length < 150 && !e.ex.includes(s)) e.ex.push(s);
      }
    }
  }

  // Namizədləri süz və sırala.
  // Məqsəd: ŞAGİRD ÜÇÜN DƏYƏRLİ söz — yəni korpusda təsdiqlənmiş, amma
  // gündəlik xəbər dilində hər addımda rast gəlinməyən ədəbi/nadir söz.
  //   • qlobal korpus tezliyi 6..400 → nə OCR zibili, nə də "həmin/daxil" kimi işlək söz
  //   • word_pool üzvlüyü          → mənalı, lüğətə dəyər söz
  //   • az_books mənbəyi           → ədəbi dil bonusu
  const candidates = [...freq.entries()]
    .filter(([w, e]) => e.n >= 2 && e.ex.length >= 1)
    .map(([w, e]) => {
      const g = CF.get(w) || 0;
      const lit = e.src.has('az_books') ? 1 : 0;
      // nadirlik balı: 6..400 aralığının aşağı hissəsi daha yüksək bal alır
      const rarity = g <= 0 ? 0 : Math.max(0, 1 - Math.log10(g) / Math.log10(400));
      return { w: azUpperFirst(w), n: e.n, g, lit, ex: e.ex, score: rarity + lit * 0.45 };
    })
    .filter(c => c.g >= 6 && c.g <= 400)
    .sort((a, b) => b.score - a.score)
    .map(({ score, ...rest }) => rest);

  // Balanslaşdırma: hər mövzudan bərabər sayda parça
  const byTopic = new Map();
  for (const p of passages) {
    if (!byTopic.has(p.t)) byTopic.set(p.t, []);
    byTopic.get(p.t).push(p);
  }
  const balanced = [];
  const perTopic = 120;
  for (const [t, arr] of byTopic) balanced.push(...arr.slice(0, perTopic));

  fs.mkdirSync(OUT, { recursive: true });
  const write = (f, obj) => {
    const p = path.join(OUT, f);
    fs.writeFileSync(p, JSON.stringify(obj));
    console.log('  ✓', f, (fs.statSync(p).size / 1024).toFixed(0) + ' KB');
  };

  // ── Qarışdırıcı variantlar (distraktorlar) ──
  // Hər sual üçün eyni uzunluq zolağından 3 YANLIŞ söz seçilir; belə variantlar
  // uzunluğa baxıb təxmin etməyə imkan vermir. Variant heç vaxt cümlədə
  // onsuz da mövcud olan söz olmur.
  const answerPool = [...new Set(sentences.map(x => x.a))];
  const byLen = new Map();
  for (const w of answerPool) {
    const L = w.length;
    if (!byLen.has(L)) byLen.set(L, []);
    byLen.get(L).push(w);
  }
  const nearLen = L => {
    const out = [];
    for (let d = 0; d <= 3 && out.length < 40; d++) {
      for (const L2 of [L - d, L + d]) (byLen.get(L2) || []).forEach(w => out.push(w));
    }
    return out;
  };
  let dropped = 0;
  const withOpts = [];
  for (const item of sentences) {
    const bag = nearLen(item.a.length).filter(w =>
      azLower(w) !== azLower(item.a) && !item.s.includes(w));
    const picks = [];
    for (let i = 0; i < 400 && picks.length < 3; i++) {
      const w = bag[Math.floor(Math.random() * bag.length)];
      if (w && !picks.includes(w)) picks.push(w);
    }
    if (picks.length < 3) { dropped++; continue; }
    withOpts.push({ s: item.s, a: item.a, o: picks, topic: item.topic, src: item.src });
  }
  console.log('   variantsız atılan sual:', dropped);

  // Mobil üçün ölçü nəzarəti: mövzular üzrə balanslı 4.000 sual saxlanılır
  // (tam siyahı 8.900+-dır, amma bir oyun sessiyasında 10-15 sual işlənir).
  const PER_TOPIC = 400;
  const cnt = new Map();
  const trimmed = [];
  for (const x of withOpts.sort(() => Math.random() - 0.5)) {
    const n = cnt.get(x.topic) || 0;
    if (n >= PER_TOPIC) continue;
    cnt.set(x.topic, n + 1);
    trimmed.push(x);
  }
  console.log('   saxlanılan sual:', trimmed.length, 'of', withOpts.length);

  write('sentences.json', trimmed);
  write('passages.json', { topics: TOPICS, items: balanced });
  // Namizədlər yalnız QURAŞDIRMA artefaktıdır (məna yazmaq üçün), sayta getmir
  fs.writeFileSync(path.join(__dirname, 'candidates.json'), JSON.stringify(candidates));
  console.log('  ✓ scripts/corpus/candidates.json (sayta daxil edilmir)');
  write('meta.json', {
    source: 'az_corpus-v1.0 (az_books / az_wiki / az_news) — Public Domain',
    generated: new Date().toISOString().slice(0, 10),
    docsTotal: data.length,
    docsUsed: stats.docs,
    sentences: trimmed.length,
    passages: balanced.length,
    passagesByTopic: Object.fromEntries([...byTopic].map(([t, a]) => [t, Math.min(a.length, perTopic)])),
    candidates: candidates.length
  });

  console.log('\n── XÜLASƏ ──');
  console.log('istifadə olunan sənəd :', stats.docs, '/', data.length);
  console.log('cümlə (Tamamla)       :', trimmed.length);
  console.log('mətn parçası (Mövzu)  :', balanced.length, JSON.stringify(Object.fromEntries([...byTopic].map(([t, a]) => [t, Math.min(a.length, perTopic)]))));
  console.log('lüğət namizədi        :', candidates.length);
  console.log('\nİlk 25 namizəd:', candidates.slice(0, 25).map(c => `${c.w}(${c.n})`).join(', '));
}

main();
