-- ════════════════════════════════════════════════════════════════
-- SözLab — "Sinif Boss'u" (Kollektiv Reyd Rejimi).
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- ÖNCƏ supabase_update_live_quiz.sql-in (və dolayısı ilə onun asılı olduğu
-- bütün əvvəlki skriptlərin) run edildiyini fərz edir — compute_level(),
-- is_admin(), log_xp_gain() buradan istifadə olunur, arxitektur da eynidir.
--
-- Necə işləyir: müəllim öz sinfi üçün bir "Boss döyüşü" sessiyası yaradır
-- (Canlı Yarışma ilə EYNİ kod-ilə-qoşulma mexanizmi). Amma fərdi xal yerinə
-- BÜTÜN sinif ORTAQ bir "Boss HP" zolağını azaldır — kim sualı düzgün
-- cavablandırsa, zərbə vurur. HP sıfıra enəndə boss "məğlub" olur.
--
-- TEXNİKİ QEYD (WebRTC/P2P ƏVƏZİNƏ): bu, ayrı bir infrastruktur (WebSocket/
-- P2P) tələb etmir — Canlı Yarışmadakı eyni sadə "poll" (1-2 saniyəlik
-- sorğu) üsulu ilə işləyir. HP-nin konkurrent (eyni anda 20-30 şagirdin
-- zərbə vurması) düzgün azalması Postgres-in `for update` sətir kilidi ilə
-- TAM TƏHLÜKƏSİZDİR — heç bir zərbə itmir, HP heç vaxt yanlış hesablanmır.
-- ════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 1) CLASS_BOSS_SESSIONS CƏDVƏLİ
-- ─────────────────────────────────────────────
create table if not exists public.class_boss_sessions (
  id bigint generated always as identity primary key,
  code text not null unique,
  teacher_username text not null,
  class_grade text not null,
  boss_name text not null default 'Söz Divi',
  boss_max_hp integer not null default 200,
  boss_hp integer not null default 200,
  damage_per_correct integer not null default 5,
  questions jsonb not null,
  status text not null default 'waiting' check (status in ('waiting','question','reveal','finished')),
  defeated boolean not null default false,
  current_index integer not null default -1,
  question_started_at timestamptz,
  xp_awarded boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists idx_boss_sessions_code on public.class_boss_sessions (code);
create index if not exists idx_boss_sessions_class on public.class_boss_sessions (class_grade, created_at desc);

alter table public.class_boss_sessions enable row level security;

drop policy if exists "boss_sessions_select" on public.class_boss_sessions;
create policy "boss_sessions_select"
  on public.class_boss_sessions for select
  to authenticated
  using (
    public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = class_boss_sessions.teacher_username)
    or exists(select 1 from public.profiles p where p.id = auth.uid() and p.class_grade = class_boss_sessions.class_grade and p.class_grade <> '')
  );

-- QEYD: insert/update/delete siyasəti QƏSDƏN yoxdur — bütün yazma
-- əməliyyatları aşağıdakı SECURITY DEFINER funksiyaları ilə edilir.

-- ─────────────────────────────────────────────
-- 2) CLASS_BOSS_PARTICIPANTS CƏDVƏLİ (zərbə vuranların statistikası)
-- ─────────────────────────────────────────────
create table if not exists public.class_boss_participants (
  id bigint generated always as identity primary key,
  session_id bigint not null references public.class_boss_sessions(id) on delete cascade,
  username text not null,
  display_name text not null default '',
  damage_dealt integer not null default 0,
  hits integer not null default 0,
  last_answered_index integer not null default -1,
  joined_at timestamptz not null default now(),
  unique(session_id, username)
);
create index if not exists idx_boss_participants_session on public.class_boss_participants (session_id);

alter table public.class_boss_participants enable row level security;

drop policy if exists "boss_participants_select" on public.class_boss_participants;
create policy "boss_participants_select"
  on public.class_boss_participants for select
  to authenticated
  using (
    public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or exists(
      select 1 from public.class_boss_sessions s
      join public.profiles p on p.id = auth.uid()
      where s.id = class_boss_participants.session_id
        and (p.username = s.teacher_username or (p.class_grade = s.class_grade and p.class_grade <> ''))
    )
  );

-- ─────────────────────────────────────────────
-- 3) create_boss_session() — müəllim öz sinfi üçün yeni boss döyüşü yaradır.
-- ─────────────────────────────────────────────
create or replace function public.create_boss_session(
  p_questions jsonb, p_boss_name text default 'Söz Divi',
  p_boss_hp integer default 200, p_damage_per_correct integer default 5
)
returns public.class_boss_sessions
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_role text;
  v_class text;
  v_code text;
  v_row public.class_boss_sessions;
  v_chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  i integer;
  v_hp integer := greatest(20, least(2000, coalesce(p_boss_hp, 200)));
  v_dmg integer := greatest(1, least(100, coalesce(p_damage_per_correct, 5)));
begin
  select username, role, teacher_class into v_username, v_role, v_class from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;
  if v_role <> 'teacher' or coalesce(v_class,'') = '' then
    raise exception 'Yalnız sinfi olan müəllimlər Boss döyüşü başlada bilər';
  end if;
  if jsonb_typeof(p_questions) <> 'array' or jsonb_array_length(p_questions) < 1 or jsonb_array_length(p_questions) > 60 then
    raise exception 'Yanlış sual formatı';
  end if;

  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_chars, floor(random()*length(v_chars))::int + 1, 1);
    end loop;
    exit when not exists(select 1 from public.class_boss_sessions where code = v_code);
  end loop;

  insert into public.class_boss_sessions(
    code, teacher_username, class_grade, boss_name, boss_max_hp, boss_hp,
    damage_per_correct, questions, status, current_index
  )
  values (
    v_code, v_username, v_class, coalesce(nullif(trim(p_boss_name),''),'Söz Divi'), v_hp, v_hp,
    v_dmg, p_questions, 'waiting', -1
  )
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.create_boss_session(jsonb, text, integer, integer) to authenticated;

-- ─────────────────────────────────────────────
-- 4) join_boss_session() — şagird kodla qoşulur (yalnız öz sinfinin döyüşü).
-- ─────────────────────────────────────────────
create or replace function public.join_boss_session(p_code text)
returns public.class_boss_sessions
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_display text;
  v_role text;
  v_class text;
  v_session public.class_boss_sessions;
begin
  select username, display_name, role, class_grade into v_username, v_display, v_role, v_class
    from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;
  if v_role <> 'user' then
    raise exception 'Yalnız şagirdlər Boss döyüşünə qoşula bilər';
  end if;

  select * into v_session from public.class_boss_sessions where upper(code) = upper(trim(p_code));
  if v_session is null then
    raise exception 'Kod tapılmadı — yenidən yoxlayın';
  end if;
  if v_session.class_grade <> coalesce(v_class,'') then
    raise exception 'Bu döyüş sizin sinfiniz üçün deyil';
  end if;
  if v_session.status = 'finished' then
    raise exception 'Bu döyüş artıq bitib';
  end if;

  insert into public.class_boss_participants(session_id, username, display_name)
  values (v_session.id, v_username, coalesce(v_display, v_username))
  on conflict (session_id, username) do nothing;

  return v_session;
end;
$$;

grant execute on function public.join_boss_session(text) to authenticated;

-- ─────────────────────────────────────────────
-- 5) start_boss_question() — müəllim növbəti suala keçir (və ya bitirir).
--    Boss artıq məğlub olubsa (dəf edilib), yeni sual açmır — birbaşa bitirir.
-- ─────────────────────────────────────────────
create or replace function public.start_boss_question(p_session_id bigint)
returns public.class_boss_sessions
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_session public.class_boss_sessions;
  v_total integer;
  v_next integer;
begin
  select username into v_username from public.profiles where id = auth.uid();
  select * into v_session from public.class_boss_sessions where id = p_session_id for update;
  if v_session is null then
    raise exception 'Sessiya tapılmadı';
  end if;
  if v_session.teacher_username <> v_username then
    raise exception 'Yalnız döyüşü başladan müəllim idarə edə bilər';
  end if;

  if v_session.defeated or v_session.boss_hp <= 0 then
    update public.class_boss_sessions set status = 'finished' where id = p_session_id returning * into v_session;
    return v_session;
  end if;

  v_total := jsonb_array_length(v_session.questions);
  v_next := v_session.current_index + 1;

  if v_next >= v_total then
    update public.class_boss_sessions set status = 'finished' where id = p_session_id returning * into v_session;
  else
    update public.class_boss_sessions
      set current_index = v_next, status = 'question', question_started_at = now()
      where id = p_session_id
      returning * into v_session;
  end if;

  return v_session;
end;
$$;

grant execute on function public.start_boss_question(bigint) to authenticated;

-- ─────────────────────────────────────────────
-- 6) end_boss_session() — müəllim vaxtından əvvəl bitirə bilər.
-- ─────────────────────────────────────────────
create or replace function public.end_boss_session(p_session_id bigint)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
begin
  select username into v_username from public.profiles where id = auth.uid();
  update public.class_boss_sessions set status = 'finished'
    where id = p_session_id and teacher_username = v_username;
end;
$$;

grant execute on function public.end_boss_session(bigint) to authenticated;

-- ─────────────────────────────────────────────
-- 7) submit_boss_answer() — şagird cavab verir. Düzgünlüyü SERVERDƏ yoxlayır
--    (klientə etibar etmir). Düzgündürsə, boss_hp-ni ATOMİK azaldır — "for
--    update" sətir kiliditi sayəsində eyni anda 30 şagird cavab versə belə,
--    HEÇ BİR zərbə itmir və HP həmişə düzgün hesablanır (Postgres bunları
--    növbə ilə, bir-bir tətbiq edir). HP sıfıra enəndə döyüş dərhal bitir.
-- ─────────────────────────────────────────────
create or replace function public.submit_boss_answer(p_session_id bigint, p_question_index integer, p_answer text)
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_session public.class_boss_sessions;
  v_participant public.class_boss_participants;
  v_question jsonb;
  v_correct_answer text;
  v_is_correct boolean;
  v_new_hp integer;
  v_dmg integer := 0;
begin
  select username into v_username from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;

  select * into v_session from public.class_boss_sessions where id = p_session_id for update;
  if v_session is null then
    raise exception 'Sessiya tapılmadı';
  end if;
  if v_session.status <> 'question' or v_session.current_index <> p_question_index then
    raise exception 'Bu sual artıq bağlıdır';
  end if;

  select * into v_participant from public.class_boss_participants
    where session_id = p_session_id and username = v_username for update;
  if v_participant is null then
    raise exception 'Bu döyüşə qoşulmamısınız';
  end if;
  if v_participant.last_answered_index >= p_question_index then
    raise exception 'Bu suala artıq cavab vermisiniz';
  end if;

  v_question := v_session.questions -> p_question_index;
  v_correct_answer := v_question ->> 'correct';
  v_is_correct := (p_answer = v_correct_answer);

  update public.class_boss_participants
    set last_answered_index = p_question_index
    where id = v_participant.id;

  if v_is_correct then
    v_dmg := v_session.damage_per_correct;

    update public.class_boss_participants
      set damage_dealt = damage_dealt + v_dmg, hits = hits + 1
      where id = v_participant.id;

    update public.class_boss_sessions
      set boss_hp = greatest(0, boss_hp - v_dmg)
      where id = p_session_id
      returning boss_hp into v_new_hp;

    update public.profiles set xp = xp + 2, level = public.compute_level(xp + 2) where username = v_username;
    perform public.log_xp_gain(v_username, (now() at time zone 'UTC')::date, 2);

    if v_new_hp <= 0 then
      update public.class_boss_sessions set status = 'finished', defeated = true where id = p_session_id;
    end if;
  else
    select boss_hp into v_new_hp from public.class_boss_sessions where id = p_session_id;
  end if;

  return jsonb_build_object('correct', v_is_correct, 'damage', v_dmg, 'bossHp', v_new_hp, 'correctAnswer', v_correct_answer);
end;
$$;

grant execute on function public.submit_boss_answer(bigint, integer, text) to authenticated;

-- ─────────────────────────────────────────────
-- 8) award_boss_damage_bonus() — döyüş bitəndə (client "finished" statusunu
--    ilk dəfə görəndə çağırır) ən çox zərbə vurana bonus XP. "xp_awarded"
--    sütunu iki dəfə mükafat verilməsinin qarşısını alır. Yalnız BOSS DƏF
--    EDİLİBSƏ bonus verilir (vaxt bitib boss sağ qalıbsa, bonus yoxdur).
-- ─────────────────────────────────────────────
create or replace function public.award_boss_damage_bonus(p_session_id bigint)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_session public.class_boss_sessions;
  v_top record;
  v_rank integer := 0;
  v_bonus integer;
begin
  select * into v_session from public.class_boss_sessions where id = p_session_id for update;
  if v_session is null or v_session.status <> 'finished' or v_session.xp_awarded then
    return;
  end if;

  update public.class_boss_sessions set xp_awarded = true where id = p_session_id;

  if not v_session.defeated then
    return;
  end if;

  for v_top in
    select username from public.class_boss_participants
      where session_id = p_session_id and hits > 0 order by damage_dealt desc, joined_at asc limit 3
  loop
    v_rank := v_rank + 1;
    v_bonus := case v_rank when 1 then 15 when 2 then 10 else 5 end;
    update public.profiles set xp = xp + v_bonus, level = public.compute_level(xp + v_bonus) where username = v_top.username;
    perform public.log_xp_gain(v_top.username, (now() at time zone 'UTC')::date, v_bonus);
  end loop;
end;
$$;

grant execute on function public.award_boss_damage_bonus(bigint) to authenticated;
