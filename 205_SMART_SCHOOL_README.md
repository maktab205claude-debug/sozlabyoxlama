# 205 SMART SCHOOL — ekosistem inteqrasiyası

Bakı Şəhəri R. İmanov adına 205 nömrəli tam orta ümumtəhsil məktəbi · Binəqədi

Bu sənəd 205 Smart School ekosisteminin SözLab-a NECƏ inteqrasiya olunduğunu
və hansı memarlıq qərarlarının verildiyini izah edir.

---

## 1. Əsas prinsip: yenidən qurmaq yox, davam etdirmək

SözLab **tək fayllı vanilla-JS** tətbiqidir (`index.html`, ~1.36 MB) — React/Next.js
deyil. Ona görə spesifikasiyadakı `/205-smart-school/world` kimi server marşrutları
və `<SmartSchoolHero />` kimi JSX komponentləri **hərfi şəkildə köçürülməyib**;
onların ekvivalenti mövcud konvensiyalarla qurulub:

| Spesifikasiya | SözLab-dakı ekvivalent |
|---|---|
| `/205-smart-school/world` | `#/205/world` — hash marşrutu (`ssParseHash` / `ssGo`) |
| `/205-smart-school/startup-factory/[id]` | `#/205/startup-factory/12` |
| `<ModuleCard />` | `ssModuleCard(m, stats, status)` — HTML sətri qaytaran funksiya |
| `<EmptyState />` | `ssEmpty(icon, title, text, cta)` |
| Ayrıca backend | Mövcud Supabase layihəsi + yeni `ss_` cədvəlləri |
| Ayrıca auth | Mövcud `profiles.role` (yalnız `mentor` rolu əlavə olundu) |

**Heç bir mövcud funksiya silinməyib.** Bütün 21 oyun, duel, imtahan, lüğət,
studiya, direktor paneli, Böyük Ekran, 205 portalının köhnə səhifələri
(xəbər, tədbir, nailiyyət, portfolio, təsdiq paneli) olduğu kimi işləyir —
186 köhnə test yenidən işlədilib, hamısı keçir.

## 2. Harada yaşayır

Ekosistem mövcud `viewMekteb205` görünüşünün içindədir və eyni örtükdən
(`m205RenderShell`) istifadə edir:

```
viewMekteb205
 ├─ m205-side (yan panel)
 │   ├─ [köhnə səhifələr: Ana səhifə, Layihələr, İdeya bankı, …]
 │   └─ ── EKOSİSTEM ──          ← yeni qrup
 │       ├─ 205 Smart School
 │       ├─ World / Student Bank / Startup Factory /
 │       │   Problem Market / Humanity Lab / Olympics
 │       ├─ Mənim panelim        (yalnız daxil olanlar)
 │       └─ Məktəb analitikası   (yalnız direktor/admin)
 └─ m205-main → m205Page → ssRenderEco() → SS_RENDER[modul]
```

Mobil: `.ss-subnav` üfüqi sürüşən sətir (masaüstündə gizlidir, yan panel onu əvəz edir)
+ mövcud alt tabbar-a «Ekosistem» düyməsi əlavə olunub.

## 3. Dizayn sistemi

Yeni palitra **icad edilməyib**. `.ss` tokenləri 205 modulunun mövcud işıqlı
sistemindən götürülüb:

```
--ss-ink   = var(--m-text)        --ss-line  = var(--m-border)
--ss-dim   = var(--m-text-secondary)  --ss-raised = #FFFFFF
--ss-faint = var(--m-text-muted)  hero = var(--m-navy-950 → --m-navy-700)
```

Modul rəngləri də mövcud tokenlərdəndir (`--m-blue`, `--m-yellow`, `--m-orange`,
`--m-cyan`, `--m-green`, `--m-purple`).

## 4. Qrafik qərarları (ölçülüb, gözlə seçilməyib)

Analitika panelindəki hər qrafik **tək ölçü** göstərir, ona görə kateqorik
palitra lazım deyil:

* **Nominal kateqoriyalar** (problem sahələri) → bütün sütunlar eyni rəngdə
  (`#4F46E5`). Uzunluq onsuz da böyüklüyü kodlayır; rəngi eyni məlumata
  sərf etmək səhvdir.
* **Sıralı boru xətti** (startap mərhələləri) → ordinal indigo ramp.
  Yoxlanılıb: L 0.870 → 0.457, monoton azalan.
* `#4F46E5` ağ fonla **6.29:1** kontrast verir.
* Status rəngləri (`#10B981` 2.54:1, `#F59E0B` 2.15:1) 3:1-dən aşağıdır,
  ona görə **həmişə ikona + mətn etiketi ilə** gəlir — rəng tək başına
  heç vaxt məna daşımır.
* İki y-oxu yoxdur · dairəvi diaqram yoxdur · kəsik şəbəkə xətti yoxdur ·
  hər qrafikin **cədvəl görünüşü** var.

## 5. Verilənlər bazası

`supabase_update_205_ecosystem.sql` — **heç nə silmir**, yalnız `ss_` prefiksli
cədvəllər əlavə edir:

```
ss_schools  ss_challenges  ss_teams  ss_submissions
ss_points_ledger (+ ss_wallets görünüşü)  ss_rewards  ss_reward_claims
ss_startups  ss_startup_votes  ss_mentor_feedback
ss_problems  ss_solutions  ss_humanity_projects
ss_olympics_events  ss_olympics_results  ss_hall_of_fame
ss_achievements
```

RPC-lər: `ss_award_points`, `ss_claim_reward`, `ss_vote_startup`,
`ss_mark_problem_solved`, `ss_my_summary`, `ss_school_analytics`.

**Təhlükəsizlik:** `ss_points_ledger` üçün insert/update/delete siyasəti
YARADILMAYIB — yəni heç bir şagird birbaşa özünə xal yaza bilmir. Xal yalnız
`security definer` funksiyası (`ss_award_points`) vasitəsilə yaranır.
Problem həll olunmuş elan etmək, mükafat mağazası, mentor rəyi — hamısı
rol yoxlaması ilə qorunur.

## 6. 205 Points barədə

Bu **real pul deyil**. Köçürülmür, alınmır, satılmır. Yalnız məktəbdaxili
motivasiya vahididir və bütün hərəkəti açıq dəftərdə izlənir. Bu, həm SQL
şərhlərində, həm də istifadəçiyə görünən «Necə qazanılır → Qaydalar»
bölməsində açıq yazılıb.

## 7. Modullar arasındakı əlaqə (ekosistem hissi)

Ana səhifədəki zəncir sadəcə bəzək deyil — hər halqa real keçiddir:

```
Problem Market → Startup Factory → Humanity Lab → World → Olympics → Student Bank
```

Praktikada: problemə həll göndərirsən → müəllim qəbul edir → `ss_mark_problem_solved`
komandanın bütün üzvlərinə **xal + «Problem Solved by 205 Students» nişanı** yazır →
nişan «Mənim panelim»də və Student Bank tarixçəsində görünür → Journey çubuqları hərəkət edir.

## 8. Olimpiada sualları haradan gəlir

Yeni sual bazası **icad edilməyib**. Yarış SözLab-ın mövcud mənbələrini işlədir:

* «Söz ehtiyatı» → `WORDS` lüğəti (3 636 söz)
* «Elm / Coğrafiya / Texnologiya / Məntiq» → mövcud AI bilik bazası (`bilikPool`)
* Mənbəsi olmayan kateqoriya (Dizayn, Natiqlik, …) **dürüst şəkildə**
  «suallar hələ hazır deyil — müəllim sual dəstini əlavə etməlidir» yazır.
  Uydurma sual generasiya edilmir.

## 9. Test əhatəsi

| Dəst | Nə yoxlayır | Nəticə |
|---|---|---|
| `t.mjs` | Studiya alətləri (köhnə) | 86/86 |
| `corpus.mjs` | Korpus oyunları + lüğət (köhnə) | 39/39 |
| `pres.mjs` | Direktor paneli + Böyük Ekran (köhnə) | 50/50 |
| `offline.mjs` | Service worker / oflayn | 11/11 |
| `ss.mjs` | Ekosistem nüvəsi, marşrut, SEO, ana səhifə | 44/44 |
| `ss2.mjs` | World + Student Bank | 35/35 |
| `ss3.mjs` | Startup Factory + Problem Market | 42/42 |
| `ss4.mjs` | Humanity Lab + Olympics | 36/36 |
| `ss5.mjs` | Məktəb analitikası | 25/25 |
| `ssa11y.mjs` | Əlçatanlıq (8 modul) + klaviatura + reduced-motion | 42/42 |
| `audit.mjs` | 12 SözLab bölməsi, masaüstü + mobil | hamısı OK |

**Cəmi: 410 test, 0 xəta.** Konsol xətası yoxdur, 390px-də üfüqi sürüşmə yoxdur.

## 10. Quraşdırma

1. Supabase → SQL Editor → `supabase_update_205_ecosystem.sql` → Run.
2. `index.html` faylını yerinə qoy və push et.
3. Birinci açılışda **Ctrl+Shift+R** (service worker v6-ya keçsin).
4. Mentor təyin etmək üçün:
   `update public.profiles set role='mentor' where username='...';`
