-- ════════════════════════════════════════════════════════════════
-- SözLab — Müəllim Paneli + Sinif Liqası üçün əlavə SQL
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR, sadəcə yeni sütun/rol/görünüş əlavə edir.
-- ÖNCƏ supabase_update_students.sql skriptinin run edildiyini fərz edir
-- (class_grade sütunu artıq mövcud olmalıdır).
-- ════════════════════════════════════════════════════════════════

-- 1) role sütununa 'teacher' dəyərini əlavə et (mövcud constraint-i genişləndirir)
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('user','admin','teacher'));

-- 2) Müəllimin hansı sinfə təyin olunduğunu saxlayan sütun (məs. "10B")
alter table public.profiles
  add column if not exists teacher_class text not null default '';

create index if not exists idx_profiles_teacher_class on public.profiles (teacher_class);

-- 3) is_teacher_of() — RLS siyasətində istifadə üçün, SECURITY DEFINER ilə
--    RLS-i bypass edərək sonsuz rekursiyanın qarşısını alır (is_admin() ilə eyni məntiq).
create or replace function public.is_teacher_of(uid uuid, cls text)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = uid and role = 'teacher' and teacher_class = cls and cls <> ''
  );
$$;

grant execute on function public.is_teacher_of(uuid, text) to authenticated;

-- 4) profiles SELECT siyasətini yenilə: indi müəllim öz sinfinin şagirdlərini
--    də görə bilsin (yalnız oxumaq — UPDATE/DELETE hüququ verilmir).
drop policy if exists "profiles_select_own_or_admin" on public.profiles;
create policy "profiles_select_own_or_admin"
  on public.profiles for select
  to authenticated
  using (
    id = auth.uid()
    or public.is_admin(auth.uid())
    or (class_grade <> '' and public.is_teacher_of(auth.uid(), class_grade))
  );

-- 5) SİNİF LİQASI — yalnız toplu/anonimləşdirilmiş rəqəmlər, heç bir şəxsi
--    ad, username və ya digər fərdi məlumat açıqlanmır (məxfilik qorunur).
create or replace view public.class_leaderboard as
  select
    class_grade,
    count(*) as student_count,
    sum(xp) as total_xp,
    round(avg(xp)) as avg_xp,
    max(streak) as top_streak
  from public.profiles
  where class_grade <> ''
  group by class_grade
  order by total_xp desc;

grant select on public.class_leaderboard to anon, authenticated;

-- ════════════════════════════════════════════════════════════════
-- QEYD: Müəllim rolunu təyin etmək üçün Admin Panel → İstifadəçilər
-- bölməsində müvafiq şəxsin yanındakı "👨‍🏫 Müəllim et" düyməsini basıb
-- sinif daxil edin (məs. 10B). Əl ilə etmək istəsəniz:
--
-- update public.profiles set role='teacher', teacher_class='10B'
--   where username='BURAYA_ISTIFADECI_ADINIZI_YAZIN';
-- ════════════════════════════════════════════════════════════════
