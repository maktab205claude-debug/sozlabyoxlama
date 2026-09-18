# SözLab — Korpus datasetləri (`data/corpus/`)

Bu qovluqdakı fayllar **az_corpus-v1.0** Azərbaycan dili korpusundan
avtomatik çıxarılıb və saytda üç yeni oyunla lüğəti qidalandırır.

## Mənbə haqqında vacib qeyd

Layihəyə əvvəlcə **`azcorpus_v0`** (1,9 milyon sənəd, ~24 GB) verilmişdi.
Həmin qovluqda **yalnız layihənin kodu** var (`README.md`, `azcorpus_v0.ipynb`,
`LICENSE` — Apache 2.0); korpusun özü Hugging Face-də
(`azcorpus/azcorpus_v0`) saxlanılır və access token tələb edir.
Bu iş mühitində huggingface.co təşkilatın şəbəkə siyasəti ilə bağlıdır
(proxy 403), ona görə həmin korpus endirilə bilmədi.

Əvəzində **eyni ailədən olan, yerli olaraq mövcud** dataset istifadə edildi:

| | |
|---|---|
| Dataset | `az_corpus-v1.0` |
| Həcm | 4.983 sənəd (39,6 MB) |
| Mənbələr | `az_books` (1.886), `az_news` (2.095), `az_wiki` (1.002) |
| Lisenziya | **Public Domain** |
| Sahələr | `cleaned_text`, `topic`, `category`, `quality`, `keywords`, `entities`, `structured_response`, `translation` |

`azcorpus_v0` faylları gələcəkdə əlçatan olsa, `scripts/corpus/build-corpus-datasets.js`
faylındakı `AZ_CORPUS` dəyişənini həmin fayla yönəltmək kifayətdir — qalan boru
xətti eynilə işləyir.

## Fayllar

| Fayl | Ölçü | Nə üçün |
|---|---|---|
| `sentences.json` | ~690 KB | **📖 Cümlə Tamamla** oyunu — 3.528 sual |
| `passages.json` | ~605 KB | **🗂️ Mətnin Mövzusu** oyunu — 1.126 mətn parçası, 10 mövzu |
| `words.json` | ~166 KB | **🔎 Söz Mənası Ovu** + lüğətə əlavə olunan 840 söz |
| `meta.json` | <1 KB | statistika və mənbə məlumatı |

Fayllar **lazy** yüklənir: yalnız müvafiq oyun açılanda `fetch` edilir,
səhifənin ilk açılışını yavaşlatmır. `words.json` isə boot zamanı bir dəfə
yüklənib lüğətə qarışdırılır.

## Necə hazırlanır

```bash
# 1) oyun datasetləri (cümlələr, mətn parçaları, lüğət namizədləri)
node scripts/corpus/build-corpus-datasets.js

# 2) namizədlərə əl ilə yazılmış mənaları qoşub words.json yaratmaq
node scripts/corpus/build-words.js
```

`AZ_CORPUS` ətraf dəyişəni ilə korpusun yolunu dəyişmək olar.

## Keyfiyyət süzgəcləri

Korpus xam kitab/xəbər mətnidir, içində OCR səhvləri var. Ona görə:

* sənəd səviyyəsində — yalnız `quality ∈ {yüksək, yaxşı, akademik, normal}`;
* cümlə səviyyəsində — 45–155 simvol, 7–20 söz, rəqəmsiz, balanslı dırnaq və
  mötərizə, qırıq nöqtə naxışları yoxdur;
* **söz səviyyəsində — korpus tezliyi**: düzgün yazılmış Azərbaycan sözü
  korpusda dəfələrlə təkrarlanır, OCR səhvi isə demək olar ki, təkdir.
  Cümlədəki sözlərin 20%-dən çoxu nadirdirsə, cümlə atılır.

> `word_pool.json` (81.932 söz) burada **orfoqrafiya lüğəti kimi işlədilmir** —
> orada "bir", "yol", "ev" kimi çox işlək qısa sözlər yoxdur. O, yalnız
> "bu söz lüğətə dəyər" müsbət siqnalı kimi istifadə olunur.

## Lüğət sözləri — nə avtomatik, nə əl ilə

Bu ayrım prinsipialdır:

* **MƏNA — əl ilə yazılır** (`scripts/corpus/meanings-*.json`).
  Korpus lüğət deyil; ondan avtomatik "söz → məna" cütü çıxarmaq mümkün deyil.
  Uydurma məna yazmaq SözLab-ın öz qaydasını — *"əminlik aşağıdırsa cavab
  uydurma"* — pozardı.
* **NÜMUNƏ CÜMLƏSİ — korpusdan gəlir və dəyişdirilmir.**
  Yəni şagird sözü əsl Azərbaycan mətnində göründüyü kimi görür.

Hazırda 842 söz üçün məna yazılıb; bunlardan 840-ı lüğətə düşüb
(2-si artıq SözLab-da var idi). Namizədlərin tam siyahısı —
`scripts/corpus/candidates.json` (1.701 söz) — **sayta daxil edilmir**,
yalnız növbəti mənaları yazmaq üçün quraşdırma artefaktıdır.

## Təkrarlanmanın qarşısı (üç səviyyə)

1. `build-words.js` — mövcud `WORDS` siyahısı ilə üst-üstə düşən söz atılır.
2. `loadCorpusWords()` — brauzerdə yenidən yoxlanılır; müqayisə
   Azərbaycan dilinə uyğun kiçik hərflə gedir (`toLocaleLowerCase('az')`),
   yəni "İzafi" və "izafi" eyni söz sayılır.
3. `loadCommunityWords()` — icma sözləri də eyni yoxlamadan keçir.

Bundan əlavə, lüğətin özündə aşkarlanan **2 təkrar** (`İqtisadiyyat`/`iqtisadiyyat`,
`İşçi`/`işçi`) silindi və **54 boş yazı** — mənası sözün özü ilə eyni olan
qüsurlu qeydlər (`az === en`, məs. `{en:'Sükut', az:'Sükut'}`) — əsl
təriflərlə əvəz olundu.

## Oyunlar

| Oyun | Data | Mexanika |
|---|---|---|
| 📖 Cümlə Tamamla | `sentences.json` | Əsl mətndən bir söz çıxarılır, 4 variantdan düzgünü seçilir. Variantlar eyni uzunluq zolağından götürülür ki, uzunluğa baxıb təxmin etmək mümkün olmasın. 12 sual, seriya bonusu. |
| 🔎 Söz Mənası Ovu | `words.json` | Söz + onun əsl cümlə konteksti göstərilir, məna seçilir. Düzgün cavab sözü "öyrənilmiş" siyahısına yazır. 12 sual. |
| 🗂️ Mətnin Mövzusu | `passages.json` | Mətn parçası oxunur, 10 sahədən biri seçilir. Mövzunun adı mətndə birbaşa keçən parçalar süzülüb atılıb ki, tapşırıq əsl oxuyub-anlama olsun. 8 sual. |

Korpus sözləri lüğətə qarışdığı üçün **mövcud bütün söz oyunları**
(Mənası Nədir?, Uyğunlaşdır, Flashkart, Hərf Şorbası, Duel, İmtahan və s.)
avtomatik olaraq bu 840 yeni sözdən də istifadə edir.
