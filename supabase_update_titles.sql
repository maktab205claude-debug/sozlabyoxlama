-- ════════════════════════════════════════════════════════════════
-- SözLab — Oyunçu Ünvanları (Player Titles) üçün əlavə SQL
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR, sadəcə yeni sütun əlavə edir.
-- ════════════════════════════════════════════════════════════════

-- 1) Yeni sütun: fərqli fəal günlərin sayı (streak-dən fərqli olaraq
--    bir gün buraxılsa belə sıfırlanmır — ünvan sistemi bunun üzərində qurulub)
alter table public.profiles
  add column if not exists days_active integer not null default 0;

-- 2) Mövcud istifadəçilər üçün başlanğıc dəyər (streak-ə əsasən təxmini backfill,
--    heç kimin ünvanı geriyə getməsin deyə)
update public.profiles
  set days_active = greatest(streak, 0)
  where days_active = 0;

-- 3) Liderbordda ünvanların düzgün görünməsi üçün public_profiles görünüşünü yenilə
create or replace view public.public_profiles as
  select username, display_name, xp, level, streak, days_active
  from public.profiles;

grant select on public.public_profiles to anon, authenticated;

-- ════════════════════════════════════════════════════════════════
-- Bundan sonra "Peşəkar" və "Əfsanə" kimi ən yüksək ünvanlar YALNIZ
-- kifayət qədər XP TOPLAYIB, eyni zamanda günlərlə davamlı oynayan
-- istifadəçilərə açılacaq — tək sessiyada (1-2 saat) mümkün deyil.
-- ════════════════════════════════════════════════════════════════
