-- ════════════════════════════════════════════════════════════════
-- SözLab — Canlı Duel (1v1) üçün əlavə SQL.
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR, sadəcə yeni cədvəl/funksiya əlavə edir.
-- ÖNCƏ bütün əvvəlki SQL skriptlərinin run edildiyini fərz edir
-- (xüsusilə supabase_update_features_batch2.sql — compute_level() funksiyası
-- buradan istifadə olunur).
-- ════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 1) DUELS CƏDVƏLİ
--    Hər iki oyunçu EYNİ sual dəstini öz sürəti ilə cavablandırır (yarış
--    rejimi). Bütün vəziyyət dəyişiklikləri YALNIZ aşağıdakı SECURITY
--    DEFINER funksiyaları vasitəsilə edilir — cədvələ birbaşa
--    insert/update icazəsi YOXDUR (yalnız select).
-- ─────────────────────────────────────────────
create table if not exists public.duels (
  id bigint generated always as identity primary key,
  p1_username text not null,
  p2_username text not null,
  status text not null default 'pending' check (status in ('pending','active','declined','finished')),
  questions jsonb not null,
  p1_score integer not null default 0,
  p1_progress integer not null default 0,
  p1_finished_at timestamptz,
  p2_score integer not null default 0,
  p2_progress integer not null default 0,
  p2_finished_at timestamptz,
  winner_username text,
  xp_awarded boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists idx_duels_p1 on public.duels (p1_username, created_at desc);
create index if not exists idx_duels_p2 on public.duels (p2_username, created_at desc);

alter table public.duels enable row level security;

-- SELECT — yalnız duelin iki tərəfi, ya da admin/direktor görə bilər.
drop policy if exists "duels_select" on public.duels;
create policy "duels_select"
  on public.duels for select
  to authenticated
  using (
    exists(select 1 from public.profiles p where p.id = auth.uid() and (p.username = duels.p1_username or p.username = duels.p2_username))
    or public.is_admin(auth.uid())
    or public.is_director(auth.uid())
  );

-- QEYD: insert/update/delete siyasəti QƏSDƏN yoxdur — bütün yazma
-- əməliyyatları aşağıdakı üç SECURITY DEFINER funksiyası ilə edilir ki,
-- oyunçular öz XP-lərini və ya nəticəni birbaşa dəyişə bilməsinlər.

-- ─────────────────────────────────────────────
-- 2) create_duel() — çağırış göndərmək
-- ─────────────────────────────────────────────
create or replace function public.create_duel(p_opponent_username text, p_questions jsonb)
returns bigint
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_opponent text := lower(p_opponent_username);
  v_id bigint;
begin
  select username into v_username from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;
  if v_opponent = v_username then
    raise exception 'Özünüzə duel göndərə bilməzsiniz';
  end if;
  if not exists(select 1 from public.profiles where username = v_opponent) then
    raise exception 'İstifadəçi tapılmadı';
  end if;
  if jsonb_typeof(p_questions) <> 'array' or jsonb_array_length(p_questions) < 1 or jsonb_array_length(p_questions) > 20 then
    raise exception 'Yanlış sual formatı';
  end if;

  insert into public.duels(p1_username, p2_username, questions, status)
  values (v_username, v_opponent, p_questions, 'pending')
  returning id into v_id;

  return v_id;
end;
$$;

grant execute on function public.create_duel(text, jsonb) to authenticated;

-- ─────────────────────────────────────────────
-- 3) respond_duel() — çağırışı qəbul/rədd etmək (yalnız p2 çağıra bilər)
-- ─────────────────────────────────────────────
create or replace function public.respond_duel(p_duel_id bigint, p_accept boolean)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
begin
  select username into v_username from public.profiles where id = auth.uid();
  update public.duels
    set status = case when p_accept then 'active' else 'declined' end
    where id = p_duel_id and p2_username = v_username and status = 'pending';
end;
$$;

grant execute on function public.respond_duel(bigint, boolean) to authenticated;

-- ─────────────────────────────────────────────
-- 4) submit_duel_answer() — sual cavablandırıldıqda çağırılır.
--    Xalı/irəliləyişi atomik yeniləyir; hər iki tərəf bitirəndə qalibi
--    müəyyən edir və XP-ni birbaşa hər iki profilə (server tərəfdə,
--    referral bonusundakı kimi) yazır. "for update" sətir kilidi eyni
--    duelə iki paralel sorğunun toqquşmasının qarşısını alır.
-- ─────────────────────────────────────────────
create or replace function public.submit_duel_answer(p_duel_id bigint, p_correct boolean)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_duel record;
  v_is_p1 boolean;
  v_total_q integer;
  v_winner text;
  v_xp_p1 integer;
  v_xp_p2 integer;
begin
  select username into v_username from public.profiles where id = auth.uid();
  select * into v_duel from public.duels where id = p_duel_id for update;
  if v_duel is null then return; end if;
  if v_duel.status <> 'active' then return; end if;

  if v_duel.p1_username = v_username then v_is_p1 := true;
  elsif v_duel.p2_username = v_username then v_is_p1 := false;
  else return; end if;

  v_total_q := jsonb_array_length(v_duel.questions);

  if v_is_p1 then
    if v_duel.p1_finished_at is not null then return; end if;
    update public.duels set
      p1_score = p1_score + (case when p_correct then 1 else 0 end),
      p1_progress = p1_progress + 1
    where id = p_duel_id;
  else
    if v_duel.p2_finished_at is not null then return; end if;
    update public.duels set
      p2_score = p2_score + (case when p_correct then 1 else 0 end),
      p2_progress = p2_progress + 1
    where id = p_duel_id;
  end if;

  select * into v_duel from public.duels where id = p_duel_id for update;

  if v_is_p1 and v_duel.p1_progress >= v_total_q and v_duel.p1_finished_at is null then
    update public.duels set p1_finished_at = now() where id = p_duel_id;
  elsif not v_is_p1 and v_duel.p2_progress >= v_total_q and v_duel.p2_finished_at is null then
    update public.duels set p2_finished_at = now() where id = p_duel_id;
  end if;

  select * into v_duel from public.duels where id = p_duel_id for update;

  if v_duel.p1_finished_at is not null and v_duel.p2_finished_at is not null and v_duel.status = 'active' then
    if v_duel.p1_score > v_duel.p2_score then v_winner := v_duel.p1_username;
    elsif v_duel.p2_score > v_duel.p1_score then v_winner := v_duel.p2_username;
    else v_winner := null;
    end if;

    if v_winner is null then
      v_xp_p1 := 20; v_xp_p2 := 20;
    elsif v_winner = v_duel.p1_username then
      v_xp_p1 := 30; v_xp_p2 := 10;
    else
      v_xp_p1 := 10; v_xp_p2 := 30;
    end if;

    update public.profiles set xp = xp + v_xp_p1, level = public.compute_level(xp + v_xp_p1) where username = v_duel.p1_username;
    update public.profiles set xp = xp + v_xp_p2, level = public.compute_level(xp + v_xp_p2) where username = v_duel.p2_username;
    -- xp_log-a da yazırıq ki, "Ayın Söz Ustası" sertifikatı və şəxsi 14-günlük
    -- qrafik duel qazanclarını da düzgün hesablasın (əvvəllər YALNIZ client-trusted
    -- addXP() yolları buraya yazırdı, RPC-əsaslı qazanclar hesaba düşmürdü).
    perform public.log_xp_gain(v_duel.p1_username, (now() at time zone 'UTC')::date, v_xp_p1);
    perform public.log_xp_gain(v_duel.p2_username, (now() at time zone 'UTC')::date, v_xp_p2);

    update public.duels set status = 'finished', winner_username = v_winner, xp_awarded = true where id = p_duel_id;
  end if;
end;
$$;

grant execute on function public.submit_duel_answer(bigint, boolean) to authenticated;

-- ════════════════════════════════════════════════════════════════
-- QEYD: Direktor üçün "🏫 Məktəb Hesabatı" paneli YENİ SQL TƏLƏB ETMİR —
-- mövcud class_leaderboard görünüşündən (supabase_update_teacher_and_league.sql-də
-- yaradılıb) və profiles cədvəlindən (role='teacher' filtri ilə) istifadə edir.
-- Əgər həmin skripti əvvəllər run etməmisinizsə, əvvəlcə onu run edin.
-- ════════════════════════════════════════════════════════════════
