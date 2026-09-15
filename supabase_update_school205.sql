-- ════════════════════════════════════════════════════════════════
-- SözLab — "205 Smart School" inteqrasiyası üçün əlavə SQL
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR. ÖNCƏ bu skriptlərin run edildiyini fərz edir:
--   1) supabase_update_teacher_and_league.sql   (teacher_class, is_teacher_of())
--   2) supabase_update_director_and_tasks.sql   (is_director())
-- ════════════════════════════════════════════════════════════════

-- 0) Ümumi köməkçi funksiya: admin/direktor/müəllim (istənilən sinif) — "məktəb heyəti"
create or replace function public.is_school_staff(uid uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where id = uid and role in ('admin','director','teacher')
  );
$$;

grant execute on function public.is_school_staff(uuid) to authenticated;

-- ─────────────────────────────────────────────
-- 1) MƏKTƏB HAQQINDA — tək sətirlik "ayarlar" cədvəli (missiya mətni, ünvan və s.)
-- ─────────────────────────────────────────────
create table if not exists public.school_info (
  id smallint primary key default 1 check (id = 1),
  school_name text not null default '',
  about_text text not null default '',
  address text not null default '',
  phone text not null default '',
  email text not null default '',
  cover_image_url text not null default '',
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);
insert into public.school_info (id) values (1) on conflict (id) do nothing;

alter table public.school_info enable row level security;

drop policy if exists "school_info_select_all" on public.school_info;
create policy "school_info_select_all"
  on public.school_info for select
  to anon, authenticated
  using (true);

drop policy if exists "school_info_update_staff" on public.school_info;
create policy "school_info_update_staff"
  on public.school_info for update
  to authenticated
  using (public.is_school_staff(auth.uid()))
  with check (public.is_school_staff(auth.uid()));

-- ─────────────────────────────────────────────
-- 2) XƏBƏRLƏR
-- ─────────────────────────────────────────────
create table if not exists public.school_news (
  id bigint generated always as identity primary key,
  title text not null check (char_length(title) between 1 and 200),
  body text not null default '',
  image_url text not null default '',
  published boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_school_news_created on public.school_news (published, created_at desc);

alter table public.school_news enable row level security;

drop policy if exists "school_news_select" on public.school_news;
create policy "school_news_select"
  on public.school_news for select
  to anon, authenticated
  using (published or public.is_school_staff(auth.uid()));

drop policy if exists "school_news_write_staff" on public.school_news;
create policy "school_news_write_staff"
  on public.school_news for insert
  to authenticated
  with check (public.is_school_staff(auth.uid()));

drop policy if exists "school_news_update_staff" on public.school_news;
create policy "school_news_update_staff"
  on public.school_news for update
  to authenticated
  using (public.is_school_staff(auth.uid()));

drop policy if exists "school_news_delete_staff" on public.school_news;
create policy "school_news_delete_staff"
  on public.school_news for delete
  to authenticated
  using (public.is_school_staff(auth.uid()));

-- ─────────────────────────────────────────────
-- 3) TƏDBİRLƏR
-- ─────────────────────────────────────────────
create table if not exists public.school_events (
  id bigint generated always as identity primary key,
  title text not null check (char_length(title) between 1 and 200),
  description text not null default '',
  event_date date,
  location text not null default '',
  image_url text not null default '',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_school_events_date on public.school_events (event_date desc);

alter table public.school_events enable row level security;

drop policy if exists "school_events_select_all" on public.school_events;
create policy "school_events_select_all"
  on public.school_events for select
  to anon, authenticated
  using (true);

drop policy if exists "school_events_write_staff" on public.school_events;
create policy "school_events_write_staff"
  on public.school_events for insert
  to authenticated
  with check (public.is_school_staff(auth.uid()));

drop policy if exists "school_events_update_staff" on public.school_events;
create policy "school_events_update_staff"
  on public.school_events for update
  to authenticated
  using (public.is_school_staff(auth.uid()));

drop policy if exists "school_events_delete_staff" on public.school_events;
create policy "school_events_delete_staff"
  on public.school_events for delete
  to authenticated
  using (public.is_school_staff(auth.uid()));

-- ─────────────────────────────────────────────
-- 4) MÜƏLLİMLƏR (ictimai profil kartları — profiles-dan ayrı, çünki hər müəllimin
--    SözLab hesabı olmaya bilər, sadəcə vizit kartı kimi göstərilir)
-- ─────────────────────────────────────────────
create table if not exists public.school_teachers (
  id bigint generated always as identity primary key,
  full_name text not null check (char_length(full_name) between 1 and 120),
  subject text not null default '',
  photo_url text not null default '',
  bio text not null default '',
  sort_order int not null default 0,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_school_teachers_sort on public.school_teachers (sort_order, full_name);

alter table public.school_teachers enable row level security;

drop policy if exists "school_teachers_select_all" on public.school_teachers;
create policy "school_teachers_select_all"
  on public.school_teachers for select
  to anon, authenticated
  using (true);

drop policy if exists "school_teachers_write_staff" on public.school_teachers;
create policy "school_teachers_write_staff"
  on public.school_teachers for insert
  to authenticated
  with check (public.is_school_staff(auth.uid()));

drop policy if exists "school_teachers_update_staff" on public.school_teachers;
create policy "school_teachers_update_staff"
  on public.school_teachers for update
  to authenticated
  using (public.is_school_staff(auth.uid()));

drop policy if exists "school_teachers_delete_staff" on public.school_teachers;
create policy "school_teachers_delete_staff"
  on public.school_teachers for delete
  to authenticated
  using (public.is_school_staff(auth.uid()));

-- ─────────────────────────────────────────────
-- 5) NAİLİYYƏTLƏR (məktəb səviyyəli, admin/müəllim əlavə edir)
-- ─────────────────────────────────────────────
create table if not exists public.school_achievements (
  id bigint generated always as identity primary key,
  title text not null check (char_length(title) between 1 and 200),
  description text not null default '',
  achieved_on date,
  image_url text not null default '',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists idx_school_achievements_date on public.school_achievements (achieved_on desc);

alter table public.school_achievements enable row level security;

drop policy if exists "school_achievements_select_all" on public.school_achievements;
create policy "school_achievements_select_all"
  on public.school_achievements for select
  to anon, authenticated
  using (true);

drop policy if exists "school_achievements_write_staff" on public.school_achievements;
create policy "school_achievements_write_staff"
  on public.school_achievements for insert
  to authenticated
  with check (public.is_school_staff(auth.uid()));

drop policy if exists "school_achievements_update_staff" on public.school_achievements;
create policy "school_achievements_update_staff"
  on public.school_achievements for update
  to authenticated
  using (public.is_school_staff(auth.uid()));

drop policy if exists "school_achievements_delete_staff" on public.school_achievements;
create policy "school_achievements_delete_staff"
  on public.school_achievements for delete
  to authenticated
  using (public.is_school_staff(auth.uid()));

-- ─────────────────────────────────────────────
-- 6) ŞAGİRD TƏQDİMATLARI — Layihələr / İdeya bankı / Startap (vahid cədvəl,
--    "type" sütunu ilə ayrılır — moderasiya axını üçün ortaq).
-- ─────────────────────────────────────────────
create table if not exists public.school_submissions (
  id bigint generated always as identity primary key,
  student_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in ('project','idea','startup')),
  title text not null check (char_length(title) between 1 and 200),
  description text not null default '',
  file_url text not null default '',
  image_url text not null default '',
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text not null default '',
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists idx_school_submissions_student on public.school_submissions (student_id, created_at desc);
create index if not exists idx_school_submissions_status on public.school_submissions (type, status, created_at desc);

alter table public.school_submissions enable row level security;

-- Görmə: öz təqdimatını hər zaman görür; heyət hamısını görür;
-- "approved" olanlar hamıya açıqdır (portfolio/nailiyyət kimi göstərmək üçün).
drop policy if exists "school_submissions_select" on public.school_submissions;
create policy "school_submissions_select"
  on public.school_submissions for select
  to anon, authenticated
  using (
    status = 'approved'
    or student_id = auth.uid()
    or public.is_school_staff(auth.uid())
  );

drop policy if exists "school_submissions_insert_own" on public.school_submissions;
create policy "school_submissions_insert_own"
  on public.school_submissions for insert
  to authenticated
  with check (student_id = auth.uid());

-- Yeniləmə: şagird YALNIZ "pending" vəziyyətdə öz mətnini redaktə edə bilər
-- (status/admin_note/reviewed_* sahələrini dəyişə bilməz — bunu trigger qoruyur).
-- Heyət isə status/qeyd təyin edə bilər.
drop policy if exists "school_submissions_update" on public.school_submissions;
create policy "school_submissions_update"
  on public.school_submissions for update
  to authenticated
  using (
    (student_id = auth.uid() and status = 'pending')
    or public.is_school_staff(auth.uid())
  )
  with check (
    (student_id = auth.uid())
    or public.is_school_staff(auth.uid())
  );

create or replace function public.prevent_submission_self_review()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if auth.uid() = old.student_id and not public.is_school_staff(auth.uid()) then
    new.status := old.status;
    new.admin_note := old.admin_note;
    new.reviewed_by := old.reviewed_by;
    new.reviewed_at := old.reviewed_at;
  end if;
  if public.is_school_staff(auth.uid()) and new.status is distinct from old.status then
    new.reviewed_by := auth.uid();
    new.reviewed_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_submission_self_review on public.school_submissions;
create trigger trg_prevent_submission_self_review
  before update on public.school_submissions
  for each row execute function public.prevent_submission_self_review();

drop policy if exists "school_submissions_delete" on public.school_submissions;
create policy "school_submissions_delete"
  on public.school_submissions for delete
  to authenticated
  using (
    (student_id = auth.uid() and status = 'pending')
    or public.is_school_staff(auth.uid())
  );

-- ─────────────────────────────────────────────
-- 7) ŞAGİRD PORTFOLİOSU — approved təqdimatlar + profil məlumatı birləşdirilmiş görünüş
-- ─────────────────────────────────────────────
create or replace view public.school_portfolio as
  select
    s.id, s.type, s.title, s.description, s.image_url, s.created_at,
    p.username, p.display_name, p.class_grade, p.equipped_frame
  from public.school_submissions s
  join public.profiles p on p.id = s.student_id
  where s.status = 'approved';

grant select on public.school_portfolio to anon, authenticated;

-- ─────────────────────────────────────────────
-- 8) STORAGE — "school-uploads" bucket (şəkil/fayl üçün)
--    QEYD: bucket-i Supabase Dashboard → Storage bölməsindən "New bucket" ilə
--    "school-uploads" adıyla, Public = ON olaraq YARADIN (bu skript onu yaratmır,
--    yalnız access policy-lərini qurur).
-- ─────────────────────────────────────────────
drop policy if exists "school_uploads_read_all" on storage.objects;
create policy "school_uploads_read_all"
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'school-uploads');

drop policy if exists "school_uploads_insert_own" on storage.objects;
create policy "school_uploads_insert_own"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'school-uploads'
    and (owner = auth.uid() or public.is_school_staff(auth.uid()))
  );

drop policy if exists "school_uploads_delete_own" on storage.objects;
create policy "school_uploads_delete_own"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'school-uploads'
    and (owner = auth.uid() or public.is_school_staff(auth.uid()))
  );

-- ════════════════════════════════════════════════════════════════
-- QEYD: "school_info" cədvəlinin ilk sətrini doldurmaq üçün (Məktəb haqqında
-- mətni, ünvan, telefon və s.) — məlumatlar hazır olanda bunu run edin:
--
-- update public.school_info set
--   school_name = 'Rövşən İmanov adına 205 nömrəli tam orta məktəb',
--   address     = 'Mətbuat 107, Binəqədi, Bakı, AZ1053',
--   phone       = '(+994 12) 411-19-98',
--   email       = '205mekteb@bakuedu.gov.az',
--   about_text  = 'BURAYA MƏKTƏBİN HAQQINDA MƏTNİ YAZILACAQ'
-- where id = 1;
-- ════════════════════════════════════════════════════════════════
