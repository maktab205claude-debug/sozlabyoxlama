-- ════════════════════════════════════════════════════════════════
-- SözLab — Söz Kəşf Et (şagirdlərin yeni söz mənası əlavə etməsi).
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- ÖNCƏ supabase_setup.sql və supabase_update_teacher_and_league.sql-in
-- run edildiyini fərz edir (compute_level(), is_admin() buradan istifadə olunur).
-- (Bu skripti əvvəllər bir dəfə run etmisinizsə, təkrar run etmək TAM
--  TƏHLÜKƏSİZDİR — bütün "create/alter" sətirləri idempotentdir və mövcud
--  məlumatları silmir, sadəcə yeni "flagged" statusunu/məntiqini əlavə edir.)
--
-- Necə işləyir: sayta "word_pool.json" faylından (SözLab lüğətində hələ
-- olmayan ~82 000 Azərbaycan sözü) təsadüfi söz göstərilir, şagird onun
-- mənasını (məs. azleks.az saytından və ya bildiyi kimi) yazıb göndərir.
--
-- KEYFİYYƏT NƏZARƏTİ: göndərilən məna serverdə avtomatik yoxlanılır
-- (public.is_low_quality_definition() — klaviatura-mələşdirmə, hərf təkrarı,
-- saitsiz "söz", tək tokenli cavab və s.). Real izah kimi görünürsə → dərhal
-- "pending" olur və şagird DƏRHAL +1 XP alır (əvvəlki kimi). Şübhəli
-- görünürsə → "flagged" statusu ilə admin panelində 🚩 işarəsi ilə göstərilir
-- və şagird XP-ni YALNIZ admin bəyənəndə alır (admin rədd etsə, heç vaxt).
-- Beləliklə heç bir göndəriş itmir/avtomatik silinmir — sadəcə açıq-aşkar
-- uydurma cavablar XP-ni "admin təsdiqinə qədər" gözlədir.
--
-- Admin bəyənəndə söz "community_words" cədvəlinə keçir və HƏMİN AN
-- bütün saytda (lüğət, oyunlar, canlı yarışma və s.) görünməyə başlayır —
-- kodu yenidən deploy etməyə ehtiyac YOXDUR.
-- ════════════════════════════════════════════════════════════════

-- 1) GÖNDƏRİŞLƏR CƏDVƏLİ
create table if not exists public.word_submissions (
  id bigint generated always as identity primary key,
  username text not null,
  display_name text not null default '',
  word text not null,
  definition text not null,
  example text not null default '',
  status text not null default 'pending' check (status in ('pending','flagged','approved','rejected')),
  xp_awarded boolean not null default false,
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by text
);
-- Skript əvvəllər run edilibsə, köhnə "status" check-i "flagged" dəyərini
-- qəbul etməyəcək və sütun yeni olmaya bilər — hər ikisini təhlükəsiz yenilə:
alter table public.word_submissions add column if not exists xp_awarded boolean not null default false;
alter table public.word_submissions drop constraint if exists word_submissions_status_check;
alter table public.word_submissions add constraint word_submissions_status_check
  check (status in ('pending','flagged','approved','rejected'));
-- Əvvəllər "pending" olaraq göndərilib artıq XP almış sətirləri qeyd et (geriyə uyğunluq).
update public.word_submissions set xp_awarded = true where status in ('pending','approved') and xp_awarded = false;

create index if not exists idx_word_sub_username on public.word_submissions (username, submitted_at desc);
create index if not exists idx_word_sub_status on public.word_submissions (status, submitted_at desc);

alter table public.word_submissions enable row level security;

drop policy if exists "word_sub_select" on public.word_submissions;
create policy "word_sub_select"
  on public.word_submissions for select
  to authenticated
  using (
    public.is_admin(auth.uid())
    or exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = word_submissions.username)
  );

-- QEYD: insert/update birbaşa YOXDUR — yalnız aşağıdakı RPC-lər vasitəsilə.

-- 2) TƏSDİQLƏNMİŞ SÖZLƏR CƏDVƏLİ (canlı lüğətə əlavə olunanlar)
create table if not exists public.community_words (
  id bigint generated always as identity primary key,
  en text not null,
  az text not null,
  ex text not null default '',
  ex_az text not null default '',
  tags jsonb not null default '[]'::jsonb,
  difficulty integer not null default 2,
  added_by text not null default '',
  added_at timestamptz not null default now(),
  source_submission_id bigint references public.word_submissions(id) on delete set null
);

alter table public.community_words enable row level security;

-- Bütün daxil olmuş istifadəçilər oxuya bilir — çünki hər cihaz açılışda
-- bunları öz lüğətinə (WORDS massivinə) əlavə edir.
drop policy if exists "community_words_select" on public.community_words;
create policy "community_words_select"
  on public.community_words for select
  to authenticated
  using (true);

-- QEYD: insert/update birbaşa YOXDUR — yalnız admin RPC-si vasitəsilə.

-- 3) is_low_quality_definition() — sadə, sürətli "uydurma cavab" filtri.
--    Real söz/cümlədə həmişə olan xüsusiyyətlərin YOXLUĞUNU axtarır:
--    klaviatura-mələşdirmə, 4+ ardıcıl eyni hərf, saitsiz mətn, çox aşağı
--    hərf müxtəlifliyi, tək tokenli (2-dən az sözlü) cavab. Heç biri 100%
--    dəqiq deyil — ona görə HEÇ NƏYİ avtomatik RƏDD ETMİR, sadəcə admin
--    təsdiqinə qədər XP-ni gecikdirir ("flagged").
create or replace function public.is_low_quality_definition(p_def text)
returns boolean
language plpgsql
immutable
as $$
declare
  v_def text := lower(trim(p_def));
  v_letters text;
  v_unique_count integer;
  v_tokens text[];
  v_has_vowel boolean;
begin
  if v_def ~ '(.)\1{3,}' then return true; end if;
  if v_def ~ '(asdf|asdas|qwer|zxcv|qwerty|jkl;|hjkl|lkjh)' then return true; end if;

  v_has_vowel := v_def ~ '[aeəiıoöuü]';
  if not v_has_vowel then return true; end if;

  v_letters := regexp_replace(v_def, '[^a-zəiıöüşçğ]', '', 'gi');
  if length(v_letters) >= 6 then
    select count(distinct x) into v_unique_count from unnest(string_to_array(v_letters, null)) as x;
    if v_unique_count < 4 then return true; end if;
  end if;

  v_tokens := array_remove(
    regexp_split_to_array(trim(regexp_replace(v_def, '[^[:alnum:]əiıöüşçğ]', ' ', 'gi')), '\s+'),
    ''
  );
  if array_length(v_tokens, 1) is null or array_length(v_tokens, 1) < 2 then return true; end if;

  return false;
end;
$$;

-- 4) submit_word_definition() — şagird yeni söz mənası göndərir.
--    Gündə maksimum 100 göndəriş (bax "flagged" olanlar da limitə daxildir —
--    əks halda zibil göndərişlə admin növbəsi sonsuz doldurula bilər).
--    Keyfiyyətli görünən cavaba DƏRHAL +1 XP, şübhəli olana admin bəyənəndə.
create or replace function public.submit_word_definition(p_word text, p_definition text, p_example text default '')
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_display text;
  v_role text;
  v_today_count integer;
  v_word text := trim(p_word);
  v_def text := trim(p_definition);
  v_ex text := trim(coalesce(p_example, ''));
  v_new_xp integer;
  v_flagged boolean;
  v_status text;
begin
  select username, display_name, role into v_username, v_display, v_role from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;
  if v_role <> 'user' then
    raise exception 'Yalnız şagirdlər söz göndərə bilər';
  end if;
  if v_word = '' or length(v_word) < 2 then
    raise exception 'Söz düzgün deyil';
  end if;
  if v_def = '' or length(v_def) < 5 then
    raise exception 'Məna ən azı 5 hərf olmalıdır';
  end if;
  if lower(v_def) = lower(v_word) then
    raise exception 'Məna sözün özü ola bilməz';
  end if;

  if exists(select 1 from public.word_submissions where username = v_username and lower(word) = lower(v_word)) then
    raise exception 'Bu sözü artıq göndərmisiniz';
  end if;

  select count(*) into v_today_count
    from public.word_submissions
    where username = v_username and submitted_at::date = (now() at time zone 'UTC')::date;
  if v_today_count >= 100 then
    raise exception 'Bugünlük limitə çatdınız (100/100) — sabah davam edin';
  end if;

  v_flagged := public.is_low_quality_definition(v_def);
  v_status := case when v_flagged then 'flagged' else 'pending' end;

  insert into public.word_submissions(username, display_name, word, definition, example, status, xp_awarded)
  values (v_username, coalesce(v_display, v_username), v_word, v_def, v_ex, v_status, not v_flagged);

  if v_flagged then
    select xp into v_new_xp from public.profiles where username = v_username;
  else
    update public.profiles set xp = xp + 1, level = public.compute_level(xp + 1) where username = v_username
      returning xp into v_new_xp;
    perform public.log_xp_gain(v_username, (now() at time zone 'UTC')::date, 1);
  end if;

  return jsonb_build_object('today_count', v_today_count + 1, 'xp', v_new_xp, 'flagged', v_flagged);
end;
$$;

grant execute on function public.submit_word_definition(text, text, text) to authenticated;

-- 5) admin_review_word_submission() — admin göndərişi bəyənir/rədd edir.
--    "pending" VƏ "flagged" hər ikisi baxıla bilər. Bəyənilsə, söz dərhal
--    community_words-a keçir (canlı görünür). Əgər bu göndəriş "flagged" idisə
--    və hələ XP alınmayıbsa, MƏHZ İNDİ (bəyənilmə anında) +1 XP verilir.
create or replace function public.admin_review_word_submission(
  p_submission_id bigint, p_approve boolean, p_difficulty integer default 2, p_tags jsonb default '["Community"]'::jsonb
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_admin text;
  v_row public.word_submissions;
begin
  select username into v_admin from public.profiles where id = auth.uid();
  if not public.is_admin(auth.uid()) then
    raise exception 'Yalnız adminlər baxa bilər';
  end if;

  select * into v_row from public.word_submissions where id = p_submission_id for update;
  if v_row is null then
    raise exception 'Göndəriş tapılmadı';
  end if;
  if v_row.status not in ('pending','flagged') then
    raise exception 'Bu göndəriş artıq baxılıb';
  end if;

  update public.word_submissions
    set status = case when p_approve then 'approved' else 'rejected' end,
        reviewed_at = now(), reviewed_by = v_admin
    where id = p_submission_id;

  if p_approve and not v_row.xp_awarded then
    update public.profiles set xp = xp + 1, level = public.compute_level(xp + 1) where username = v_row.username;
    update public.word_submissions set xp_awarded = true where id = p_submission_id;
    perform public.log_xp_gain(v_row.username, (now() at time zone 'UTC')::date, 1);
  end if;

  if p_approve then
    insert into public.community_words(en, az, ex, ex_az, tags, difficulty, added_by, source_submission_id)
    values (v_row.word, v_row.definition, coalesce(nullif(v_row.example,''), v_row.word || '.'), v_row.example,
            p_tags, p_difficulty, v_row.username, v_row.id);
  end if;
end;
$$;

grant execute on function public.admin_review_word_submission(bigint, boolean, integer, jsonb) to authenticated;

-- 6) admin_export_community_words() — admin üçün JSON ixracı (istəsə xarici
--    ehtiyat nüsxə/sənəd kimi saxlasın).
create or replace function public.admin_export_community_words()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Yalnız adminlər ixrac edə bilər';
  end if;

  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'en', en, 'az', az, 'ex', ex, 'exAz', ex_az, 'tags', tags, 'difficulty', difficulty
    ) order by added_at), '[]'::jsonb)
    from public.community_words
  );
end;
$$;

grant execute on function public.admin_export_community_words() to authenticated;

-- 7) admin_add_word_direct() — admin panelindəki "➕ Yeni Söz Əlavə Et"
--    formasından SÖZÜ BİRBAŞA lüğətə əlavə edir (Söz Kəşf Et göndərişindən
--    fərqli olaraq — bura heç bir şagird göndərişi yoxdur, admin özü yazır).
--    ƏVVƏLLƏR bu, YALNIZ brauzer yaddaşına (WORDS.push) yazılırdı və səhifə
--    yenilənəndə/başqa cihazda itirdi. İndi community_words cədvəlinə yazılır
--    və digər söz mənbələri kimi bütün saytda/cihazlarda dərhal görünür.
create or replace function public.admin_add_word_direct(
  p_en text, p_az text, p_ex text default '', p_ex_az text default '',
  p_tags jsonb default '["B2"]'::jsonb, p_difficulty integer default 2
)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_en text := trim(p_en);
  v_az text := trim(p_az);
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Yalnız adminlər söz əlavə edə bilər';
  end if;
  if v_en = '' or v_az = '' then
    raise exception 'Söz və məna mütləqdir';
  end if;
  if exists(select 1 from public.community_words where lower(en) = lower(v_en)) then
    raise exception 'Bu söz artıq lüğətdədir';
  end if;

  insert into public.community_words(en, az, ex, ex_az, tags, difficulty, added_by, source_submission_id)
  values (
    v_en, v_az,
    coalesce(nullif(trim(p_ex), ''), v_en || '.'),
    trim(coalesce(p_ex_az, '')),
    coalesce(p_tags, '["B2"]'::jsonb),
    coalesce(p_difficulty, 2),
    coalesce((select username from public.profiles where id = auth.uid()), ''),
    null
  );
end;
$$;

grant execute on function public.admin_add_word_direct(text, text, text, text, jsonb, integer) to authenticated;
