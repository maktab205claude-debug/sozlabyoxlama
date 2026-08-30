-- ════════════════════════════════════════════════════════════════
-- SözLab — Dəvət Sistemi + Şəxsi Analitika + Zəif Sözlər + İmtahan
-- Simulyasiyası üçün əlavə SQL.
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR, sadəcə yeni sütun/cədvəl/funksiya əlavə edir.
-- ÖNCƏ bütün əvvəlki SQL skriptlərinin (titles, students, teacher_and_league,
-- director_and_tasks) run edildiyini fərz edir.
-- ════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 1) YENİ SÜTUNLAR (profiles)
-- ─────────────────────────────────────────────
alter table public.profiles add column if not exists weak_words jsonb not null default '{}'::jsonb;
alter table public.profiles add column if not exists games_played jsonb not null default '{}'::jsonb;
alter table public.profiles add column if not exists longest_streak integer not null default 0;
alter table public.profiles add column if not exists referred_by text not null default '';

-- Mövcud istifadəçilər üçün ən uzun seriyanın geriyə doğru təxmini backfill-i
-- (heç kimin "ən uzun seriya" göstəricisi indiki seriyasından az görünməsin deyə)
update public.profiles set longest_streak = streak where longest_streak < streak;

-- ─────────────────────────────────────────────
-- 2) SƏVİYYƏ HESABLAMA KÖMƏKÇİSİ (yalnız serverdə, dəvət bonusu üçün lazımdır)
--    Client tərəfdəki levelFromXP(xp) funksiyası ilə EYNİ məntiq: hər səviyyə
--    l*100 XP tələb edir, kumulyativ şəkildə.
-- ─────────────────────────────────────────────
create or replace function public.compute_level(p_xp integer)
returns integer
language plpgsql
immutable
as $$
declare
  l integer := 1;
  remaining integer := greatest(p_xp,0);
begin
  while remaining >= l*100 loop
    remaining := remaining - l*100;
    l := l + 1;
  end loop;
  return l;
end;
$$;

-- ─────────────────────────────────────────────
-- 3) handle_new_user() TRIGGER-İNİ YENİLƏ — indi referral bonusunu da idarə edir.
--    Yeni istifadəçi düzgün mövcud username-i "dəvət kodu" kimi yazıbsa (özü
--    deyil), hər ikisinə +20 XP verilir. Dəvət kodu YANLIŞ/BOŞ olsa, sakitcə
--    0 bonusla davam edir (qeydiyyat pozulmur).
-- ─────────────────────────────────────────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_display_name text;
  v_first_name text;
  v_last_name text;
  v_class_grade text;
  v_referred_by text;
  v_bonus_xp integer := 0;
begin
  v_username := lower(coalesce(new.raw_user_meta_data->>'username', 'user_' || substr(new.id::text, 1, 8)));
  v_display_name := coalesce(new.raw_user_meta_data->>'display_name', v_username);
  v_first_name := coalesce(new.raw_user_meta_data->>'first_name', '');
  v_last_name := coalesce(new.raw_user_meta_data->>'last_name', '');
  v_class_grade := coalesce(new.raw_user_meta_data->>'class_grade', '');
  v_referred_by := lower(coalesce(new.raw_user_meta_data->>'referred_by', ''));

  if v_username !~ '^[a-z0-9_]{3,20}$' or exists (select 1 from public.profiles p where p.username = v_username) then
    v_username := 'user_' || substr(new.id::text, 1, 8);
  end if;

  if v_class_grade !~ '^(1[01]|[1-9])[A-D]$' then
    v_class_grade := '';
  end if;

  -- Dəvət kodu = dəvət edənin username-i. Özünə istinad və mövcud olmayan
  -- kodlar sakitcə görməzdən gəlinir (constraint pozulmasın, xəta çıxmasın deyə).
  if v_referred_by <> '' and v_referred_by <> v_username and exists(select 1 from public.profiles p where p.username = v_referred_by) then
    v_bonus_xp := 20;
    update public.profiles
      set xp = xp + 20, level = public.compute_level(xp + 20)
      where username = v_referred_by;
  else
    v_referred_by := '';
  end if;

  insert into public.profiles (id, username, display_name, first_name, last_name, class_grade, xp, level, streak, learned, badges, role, last_visit, referred_by)
  values (new.id, v_username, v_display_name, v_first_name, v_last_name, v_class_grade, v_bonus_xp, public.compute_level(v_bonus_xp), 0, '{}', '{}', 'user', null, v_referred_by)
  on conflict (id) do nothing;

  return new;
end;
$$;

-- ─────────────────────────────────────────────
-- 4) GÜNDƏLİK XP JURNALI (Şəxsi Analitikadakı "son 14 gün" qrafiki üçün)
-- ─────────────────────────────────────────────
create table if not exists public.xp_log (
  username text not null,
  log_date date not null,
  xp_gained integer not null default 0,
  primary key (username, log_date)
);

alter table public.xp_log enable row level security;

drop policy if exists "xp_log_select" on public.xp_log;
create policy "xp_log_select"
  on public.xp_log for select
  to authenticated
  using (
    exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = xp_log.username)
    or public.is_admin(auth.uid())
    or public.is_director(auth.uid())
  );
-- QEYD: insert/update siyasəti YOXDUR — yeganə yazma yolu aşağıdakı
-- log_xp_gain() SECURITY DEFINER funksiyasıdır, o RLS-i bypass edir.

create or replace function public.log_xp_gain(p_username text, p_date date, p_amount integer)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if p_amount is null or p_amount <= 0 then return; end if;
  insert into public.xp_log(username, log_date, xp_gained)
  values (p_username, p_date, p_amount)
  on conflict (username, log_date) do update set xp_gained = xp_log.xp_gained + excluded.xp_gained;
end;
$$;

grant execute on function public.log_xp_gain(text,date,integer) to authenticated;

-- ════════════════════════════════════════════════════════════════
-- QEYD: Zəif Sözlərin Təkrarlanması (weak_words) və İmtahan Simulyasiyası
-- heç bir yeni cədvəl/RLS tələb etmir — ikisi də mövcud profiles.weak_words
-- sütunundan və mövcud söz banklarından (WORDS/AZ_WORDS) işləyir, yalnız
-- frontend məntiqidir.
-- ════════════════════════════════════════════════════════════════
