# SözLab Offline AI Bilik Bazası (data/ai/)

Bu qovluqdakı `qa.json` SözLab-ın 🤖 AI köməkçisinin (həm ümumi sayt köməkçisi,
həm də 205 Smart School-un "AI köməkçi" bölməsi) istifadə etdiyi, tamamilə
**oflayn** işləyən ümumi bilik sual-cavab bazasıdır. Heç bir API çağırışı
etmir — brauzer `qa.json`-u bir dəfə yükləyir və bütün axtarış yaddaşda gedir.

## Mənbələr

| Mənbə | Sətir sayı (xam) | Lisenziya | Qeyd |
|---|---|---|---|
| [LocalDoc/LDQuAd](https://huggingface.co/datasets/LocalDoc/LDQuAd) | 154,198 | CC BY-NC-ND 4.0 | SQuAD-tərzi, qısa mətn-parçası cavablar. **Defolt olaraq DAXİL EDİLMİR** (aşağıya bax) |
| [LocalDoc/LDQuAd_v2](https://huggingface.co/datasets/LocalDoc/LDQuAd_v2) | 351,000 | CC BY-NC 4.0 | Tam cümlə cavablar (AI-assisted) |
| az_corpus-v1.0 | 4,983 mətn → 9,956 struktur Q&A | Public Domain | Ən keyfiyyətli mənbə — hər mətnin öz `structured_response.questions_and_answers` sahəsi var |

## Niyə LDQuAd (v1) defolt olaraq daxil edilmir?

1. **Keyfiyyət**: cavabları SQuAD-tərzi qısa mətn-parçalarıdır (məs. "Şərqi
   Avropa və Qərbi Asiyanın"), tam cümlə deyil — çat-tərzi AI köməkçi üçün
   LDQuAd_v2-nin tam cümlə cavabları daha yaxşı işləyir.
2. **Örtük təkrarı**: hər iki dataset də oxşar Vikipediya-tərzi mövzuları
   əhatə edir, LDQuAd_v2 artıq kifayət qədər geniş əhatə verir.
3. **Lisenziya**: LDQuAd, LDQuAd_v2-dən fərqli olaraq **"No-Derivatives"**
   şərti daşıyır (CC BY-NC-**ND** 4.0) — yəni məlumatı emal edib (normalize,
   deduplication, format dəyişikliyi) yenidən paylaşmaq lisenziyaya görə
   qeyri-müəyyəndir. Məktəb layihəsi kimi qeyri-kommersiya istifadəsi üçün
   risk aşağıdır, amma buna baxmayaraq ehtiyat siyasəti kimi defolt olaraq
   söndürülüb. `scripts/ai/build-ai-db.js` içində `INCLUDE_LDQUAD_V1 = true`
   edərək istənilən vaxt aktivləşdirmək mümkündür.

LDQuAd_v2 (CC BY-NC 4.0) və az_corpus (Public Domain) qeyri-kommersiya bir
məktəb layihəsi üçün istifadəyə açıqdır, amma CC BY-NC 4.0 mətni "əgər
materialı remix/transform/build-upon edərsinizsə, dəyişdirilmiş materialı
paylaya bilməzsiniz" kimi əlavə bir qeyd daşıyır — SözLab bunu YALNIZ öz
daxili sual-cavab funksiyası üçün emal edib istifadə edir, ayrıca dataset
kimi yenidən paylaşmır.

## Niyə "aliases" sahəsi yoxdur (əvəzinə nə var)

İlkin dizaynda hər sual üçün əl ilə yazılmış alternativ ifadələr
("aliases": ["azerbaycan paytaxti nedir", "az paytaxtı?", ...]) nəzərdə
tutulmuşdu. ~32,000 sual üçün bunu əl ilə etmək mümkün deyil (və 460,000+
xam sətir üçün heç mümkün deyil). Əvəzinə **normalizasiya + fuzzy axtarış**
sistemi qurulub ki, eyni işi runtime-da avtomatik görür:

- `normalizeAz()` — Azərbaycan hərflərini fold edir (ə→e, ı→i, ş→s, çə→c,
  ö→o, ü→u, ğ→g), kiçik hərfə salır, punktuasiyanı silir. Beləliklə
  "Azərbaycanın paytaxtı nədir?" və "azerbaycanin paytaxti nedir" EYNİ
  normalized string-ə düşür.
- `tokenizeAz()` + TF-IDF çəkili keyword-overlap axtarışı — istifadəçi
  sualını tam fərqli söz sırası ilə yazsa belə (məs. "harasıdır Bakı" vs
  "Bakı haradadır") uyğun sənədi tapır.
- **Mövzu qapısı (`tt` sahəsi)** — iki fərqli sənəd eyni ümumi sual
  şablonunu paylaşırsa (məs. "X hansı ölkələrlə həmsərhəddir?" LDQuAd_v2-də
  ~4,700 fərqli yerə aid verilir), sistem sənədin öz mövzu adının
  (ən azı ən "unikal" sözünün) sualda keçdiyini tələb edir — əks halda
  səhv ölkə/şəxs haqqında cavab qaytarma riski yaranır (bunu test zamanı
  tapıb düzəltdik: "Azərbaycanın paytaxtı" sualı səhvən "ABŞ-ın paytaxtı"
  cavabını qaytarırdı, indi bu halda sistem sadəcə "tapmadım" deyir).
- Confidence həddi (0.55) ötülməyəndə sistem **heç nə uydurmur** — sadəcə
  "dəqiq tapmadım" mesajına keçir (`index.html`-dəki `getOfflineAIResponse`
  içindəki ümumi fallback mesajı).

## Necə yenidən qurmaq olar (build-ai-db.js)

1. Xam datasetləri əldə et (artıq sənin kompüterində
   `Desktop/github ai/{LDQuAd,LDQuAd_v2,az_corpus-v1.0}` altında var):
   - `LDQuAd/data/train-00000-of-00001.parquet` → `data/ai/raw/LDQuAd.parquet`
   - `LDQuAd_v2/data/train-00000-of-00001.parquet` → `data/ai/raw/LDQuAd_v2.parquet`
   - `az_corpus-v1.0/data.json` → `data/ai/raw/az_corpus-v1.0.json`
2. `node scripts/ai/build-ai-db.js`
3. Nəticə: `data/ai/qa.json` (~31.9k sənəd, ~13.5MB, gzip-lə ~2.8MB) və
   `data/ai/topics.json`.

Parquet oxumaq üçün `scripts/ai/vendor/hyparquet` vendored edilib (MIT,
sıfır asılılıqlı JS parser) — çünki bu inkişaf mühitində npm/pip
registry-lərinə çıxış yox idi (pyarrow/parquetjs quraşdırıla bilmədi).
Öz kompüterində normal internetlə işlədiyi üçün istəsən
`npm install parquetjs` ilə də əvəz edə bilərsən, amma hazırkı vendored
versiya tam işləkdir və heç bir əlavə quraşdırma tələb etmir.

## az_corpus-v1.0 xam JSON-dakı naməlum bug

Mənbə fayldakı bəzi sətirlər arasında (~1 dəfə rast gəlindi) təsadüfi bir
rəqəm-vergül cütlüyü sıxışdırılıb (`"...}\n2,\n    {..."`), JSON-u pozur.
`build-ai-db.js` bunu avtomatik regex ilə düzəldir (`loadAzCorpus`
funksiyasında) — əl ilə düzəliş tələb olunmur.
