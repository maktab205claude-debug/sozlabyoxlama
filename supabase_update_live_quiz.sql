-- ════════════════════════════════════════════════════════════════
-- SözLab — Canlı Sinif Yarışması (Kahoot-tərzi).
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- ÖNCƏ bütün əvvəlki SQL skriptlərinin (xüsusilə supabase_update_duel.sql
-- və supabase_update_teacher_and_league.sql) run edildiyini fərz edir —
-- compute_level(), is_teacher_of(), is_admin(), is_director() buradan
-- istifadə olunur. Mövcud cədvəlləri POZMUR, sadəcə yeni cədvəl/funksiya
-- əlavə edir.
--
-- Necə işləyir: Müəllim öz sinfi üçün bir "sessiya" yaradır (6 rəqəmli/
-- hərfli kod alır), şagirdlər həmin kodla qoşulur. Müəllim "Növbəti sual"
-- düyməsi ilə sualları bir-bir açır, hamısı EYNİ ANDA eyni sualı görür
-- (Kahoot kimi), sürətli və düzgün cavab daha çox xal qazandırır. Bütün
-- xal/vəziyyət hesablaması server tərəfdə (bu fayldakı funksiyalarda) baş
-- verir ki, şagird öz xalını saxtalaşdıra bilməsin.
-- ════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 1) LIVE_QUIZ_SESSIONS CƏDVƏLİ
-- ─────────────────────────────────────────────
create table if not exists public.live_quiz_sessions (
  id bigint generated always as identity primary key,
  code text not null unique,
  teacher_username text not null,
  class_grade text not null,
  status text not null default 'waiting' check (status in ('waiting','question','reveal','finished')),
  questions jsonb not null,
  current_index integer not null default -1,
  question_started_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists idx_lq_sessions_code on public.live_quiz_sessions (code);
create index if not exists idx_lq_sessions_class on public.live_quiz_sessions (class_grade, created_at desc);

alter table public.live_quiz_sessions enable row level security;

drop policy if exists "lq_sessions_select" on public.live_quiz_sessions;
create policy "lq_sessions_select"
  on public.live_quiz_sessions for select
  to authenticated
  using (
    public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = live_quiz_sessions.teacher_username)
    or exists(select 1 from public.profiles p where p.id = auth.uid() and p.class_grade = live_quiz_sessions.class_grade and p.class_grade <> '')
  );

-- QEYD: insert/update/delete siyasəti QƏSDƏN yoxdur — bütün yazma
-- əməliyyatları aşağıdakı SECURITY DEFINER funksiyaları ilə edilir.

-- ─────────────────────────────────────────────
-- 2) LIVE_QUIZ_PARTICIPANTS CƏDVƏLİ
-- ─────────────────────────────────────────────
create table if not exists public.live_quiz_participants (
  id bigint generated always as identity primary key,
  session_id bigint not null references public.live_quiz_sessions(id) on delete cascade,
  username text not null,
  display_name text not null default '',
  score integer not null default 0,
  last_answered_index integer not null default -1,
  last_correct boolean,
  last_points integer not null default 0,
  joined_at timestamptz not null default now(),
  unique(session_id, username)
);
create index if not exists idx_lq_participants_session on public.live_quiz_participants (session_id);

alter table public.live_quiz_participants enable row level security;

drop policy if exists "lq_participants_select" on public.live_quiz_participants;
create policy "lq_participants_select"
  on public.live_quiz_participants for select
  to authenticated
  using (
    public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or exists(
      select 1 from public.live_quiz_sessions s
      join public.profiles p on p.id = auth.uid()
      where s.id = live_quiz_participants.session_id
        and (p.username = s.teacher_username or (p.class_grade = s.class_grade and p.class_grade <> ''))
    )
  );

-- QEYD: bu cədvələ də birbaşa insert/update icazəsi YOXDUR.

-- ─────────────────────────────────────────────
-- 3) create_live_quiz() — müəllim öz sinfi üçün yeni sessiya yaradır.
-- ─────────────────────────────────────────────
create or replace function public.create_live_quiz(p_questions jsonb)
returns public.live_quiz_sessions
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_role text;
  v_class text;
  v_code text;
  v_row public.live_quiz_sessions;
  v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  i integer;
begin
  select username, role, teacher_class into v_username, v_role, v_class from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;
  if v_role <> 'teacher' or coalesce(v_class,'') = '' then
    raise exception 'Yalnız sinfi olan müəllimlər canlı yarışma başlada bilər';
  end if;
  if jsonb_typeof(p_questions) <> 'array' or jsonb_array_length(p_questions) < 1 or jsonb_array_length(p_questions) > 30 then
    raise exception 'Yanlış sual formatı';
  end if;

  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_chars, floor(random()*length(v_chars))::int + 1, 1);
    end loop;
    exit when not exists(select 1 from public.live_quiz_sessions where code = v_code);
  end loop;

  insert into public.live_quiz_sessions(code, teacher_username, class_grade, questions, status, current_index)
  values (v_code, v_username, v_class, p_questions, 'waiting', -1)
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.create_live_quiz(jsonb) to authenticated;

-- ─────────────────────────────────────────────
-- 4) join_live_quiz() — şagird kodla qoşulur (yalnız öz sinfinin sessiyası).
-- ─────────────────────────────────────────────
create or replace function public.join_live_quiz(p_code text)
returns public.live_quiz_sessions
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_display text;
  v_role text;
  v_class text;
  v_session public.live_quiz_sessions;
begin
  select username, display_name, role, class_grade into v_username, v_display, v_role, v_class
    from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;
  if v_role <> 'user' then
    raise exception 'Yalnız şagirdlər yarışmaya qoşula bilər';
  end if;

  select * into v_session from public.live_quiz_sessions where upper(code) = upper(trim(p_code));
  if v_session is null then
    raise exception 'Kod tapılmadı — yenidən yoxlayın';
  end if;
  if v_session.class_grade <> coalesce(v_class,'') then
    raise exception 'Bu yarışma sizin sinfiniz üçün deyil';
  end if;
  if v_session.status = 'finished' then
    raise exception 'Bu yarışma artıq bitib';
  end if;

  insert into public.live_quiz_participants(session_id, username, display_name)
  values (v_session.id, v_username, coalesce(v_display, v_username))
  on conflict (session_id, username) do nothing;

  return v_session;
end;
$$;

grant execute on function public.join_live_quiz(text) to authenticated;

-- ─────────────────────────────────────────────
-- 5) start_live_quiz_question() — müəllim növbəti suala keçir (və ya bitirir).
-- ─────────────────────────────────────────────
create or replace function public.start_live_quiz_question(p_session_id bigint)
returns public.live_quiz_sessions
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_session public.live_quiz_sessions;
  v_total integer;
  v_next integer;
begin
  select username into v_username from public.profiles where id = auth.uid();
  select * into v_session from public.live_quiz_sessions where id = p_session_id for update;
  if v_session is null then
    raise exception 'Sessiya tapılmadı';
  end if;
  if v_session.teacher_username <> v_username then
    raise exception 'Yalnız yarışmanı başladan müəllim idarə edə bilər';
  end if;

  v_total := jsonb_array_length(v_session.questions);
  v_next := v_session.current_index + 1;

  if v_next >= v_total then
    update public.live_quiz_sessions set status = 'finished' where id = p_session_id returning * into v_session;
  else
    update public.live_quiz_sessions
      set current_index = v_next, status = 'question', question_started_at = now()
      where id = p_session_id
      returning * into v_session;
  end if;

  return v_session;
end;
$$;

grant execute on function public.start_live_quiz_question(bigint) to authenticated;

-- ─────────────────────────────────────────────
-- 6) end_live_quiz() — müəllim yarışmanı vaxtından əvvəl bitirə bilər.
-- ─────────────────────────────────────────────
create or replace function public.end_live_quiz(p_session_id bigint)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
begin
  select username into v_username from public.profiles where id = auth.uid();
  update public.live_quiz_sessions set status = 'finished'
    where id = p_session_id and teacher_username = v_username;
end;
$$;

grant execute on function public.end_live_quiz(bigint) to authenticated;

-- ─────────────────────────────────────────────
-- 7) submit_live_quiz_answer() — şagird cavab verir. Düzgünlüyü server
--    tərəfdə yoxlayır (client-in göndərdiyi "düzgündür" bayrağına ETİBAR
--    ETMİR), sürətə görə xal verir (Kahoot-vari: nə qədər tez, o qədər
--    çox xal) və dərhal profilə XP əlavə edir. Eyni suala iki dəfə cavab
--    vermək (last_answered_index yoxlaması ilə) və sessiya sualından fərqli
--    indeksə cavab vermək (köhnə sual üçün gec gələn sorğu) qarşısı alınır.
-- ─────────────────────────────────────────────
create or replace function public.submit_live_quiz_answer(p_session_id bigint, p_question_index integer, p_answer text)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_session public.live_quiz_sessions;
  v_participant public.live_quiz_participants;
  v_question jsonb;
  v_correct_answer text;
  v_is_correct boolean;
  v_elapsed_ms integer;
  v_points integer;
begin
  select username into v_username from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;

  select * into v_session from public.live_quiz_sessions where id = p_session_id for update;
  if v_session is null then
    raise exception 'Sessiya tapılmadı';
  end if;
  if v_session.status <> 'question' or v_session.current_index <> p_question_index then
    raise exception 'Bu sual artıq bağlıdır';
  end if;

  select * into v_participant from public.live_quiz_participants
    where session_id = p_session_id and username = v_username for update;
  if v_participant is null then
    raise exception 'Bu yarışmaya qoşulmamısınız';
  end if;
  if v_participant.last_answered_index >= p_question_index then
    raise exception 'Bu suala artıq cavab vermisiniz';
  end if;

  v_question := v_session.questions -> p_question_index;
  v_correct_answer := v_question ->> 'correct';
  v_is_correct := (p_answer = v_correct_answer);

  v_elapsed_ms := greatest(0, extract(epoch from (now() - coalesce(v_session.question_started_at, now()))) * 1000)::integer;
  v_points := case when v_is_correct then greatest(20, 100 - floor(v_elapsed_ms / 150.0)::integer) else 0 end;

  update public.live_quiz_participants
    set last_answered_index = p_question_index,
        last_correct = v_is_correct,
        last_points = v_points,
        score = score + v_points
    where id = v_participant.id;

  if v_points > 0 then
    update public.profiles set xp = xp + 2, level = public.compute_level(xp + 2) where username = v_username;
  end if;

  return jsonb_build_object('correct', v_is_correct, 'points', v_points, 'correctAnswer', v_correct_answer);
end;
$$;

grant execute on function public.submit_live_quiz_answer(bigint, integer, text) to authenticated;

-- ─────────────────────────────────────────────
-- 8) award_live_quiz_podium() — yarışma bitəndə (client "finished" statusunu
--    ilk dəfə görəndə çağırır) ilk 3 yerə bonus XP verir. "xp_awarded"
--    sütunu iki dəfə mükafat verilməsinin qarşısını alır.
-- ─────────────────────────────────────────────
alter table public.live_quiz_sessions add column if not exists xp_awarded boolean not null default false;

create or replace function public.award_live_quiz_podium(p_session_id bigint)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_session public.live_quiz_sessions;
  v_top record;
  v_rank integer := 0;
  v_bonus integer;
begin
  select * into v_session from public.live_quiz_sessions where id = p_session_id for update;
  if v_session is null or v_session.status <> 'finished' or v_session.xp_awarded then
    return;
  end if;

  update public.live_quiz_sessions set xp_awarded = true where id = p_session_id;

  for v_top in
    select username from public.live_quiz_participants
      where session_id = p_session_id order by score desc, joined_at asc limit 3
  loop
    v_rank := v_rank + 1;
    v_bonus := case v_rank when 1 then 15 when 2 then 10 else 5 end;
    update public.profiles set xp = xp + v_bonus, level = public.compute_level(xp + v_bonus) where username = v_top.username;
  end loop;
end;
$$;

grant execute on function public.award_live_quiz_podium(bigint) to authenticated;
