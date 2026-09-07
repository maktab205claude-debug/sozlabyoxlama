-- ════════════════════════════════════════════════════════════════
-- SözLab — "Dərs Materialları" (Müəllim Slaydları) üçün SQL.
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR, sadəcə yeni cədvəl/bucket/funksiya əlavə edir.
--
-- FƏLSƏFƏ: hər müəllim YALNIZ ÖZ yüklədiyi dərsləri görür/idarə edir (sinif
-- yoldaşı müəllim başqasının materialına toxuna bilməz) — bax "teacher_lessons"
-- cədvəlinin RLS siyasəti. Hər dərs bir neçə "slayd"dan ibarətdir (mətn və ya
-- şəkil), bunlar "slides" sütununda JSON massiv kimi saxlanılır. Şəkillər isə
-- Supabase Storage-da ("lesson-images" bucket) saxlanılır ki, cədvəl şişməsin
-- və böyük şəkillər PostgREST sorğularını yavaşlatmasın.
-- ════════════════════════════════════════════════════════════════

-- 1) CƏDVƏL
create table if not exists public.teacher_lessons (
  id bigint generated always as identity primary key,
  teacher_username text not null,
  title text not null,
  slides jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_teacher_lessons_owner on public.teacher_lessons(teacher_username, created_at desc);

alter table public.teacher_lessons enable row level security;

-- Yalnız yükləyən müəllim öz dərslərini görə/dəyişə/silə bilər. Insert/update
-- üçün əlavə olaraq profilin role='teacher' olması tələb olunur ki, şagird
-- öz adına saxta dərs sətri yaza bilməsin (select/delete-də bu şərt yoxdur ki,
-- rolu sonradan dəyişən istifadəçi köhnə materiallarını itirməsin).
drop policy if exists "teacher_lessons_select" on public.teacher_lessons;
create policy "teacher_lessons_select"
  on public.teacher_lessons for select
  to authenticated
  using (exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = teacher_lessons.teacher_username));

drop policy if exists "teacher_lessons_insert" on public.teacher_lessons;
create policy "teacher_lessons_insert"
  on public.teacher_lessons for insert
  to authenticated
  with check (exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = teacher_lessons.teacher_username and p.role = 'teacher'));

drop policy if exists "teacher_lessons_update" on public.teacher_lessons;
create policy "teacher_lessons_update"
  on public.teacher_lessons for update
  to authenticated
  using (exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = teacher_lessons.teacher_username))
  with check (exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = teacher_lessons.teacher_username and p.role = 'teacher'));

drop policy if exists "teacher_lessons_delete" on public.teacher_lessons;
create policy "teacher_lessons_delete"
  on public.teacher_lessons for delete
  to authenticated
  using (exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = teacher_lessons.teacher_username));

-- 2) STORAGE BUCKET — dərs şəkilləri üçün. "public: true" sayəsində şəkillər
-- birbaşa ictimai URL ilə açılır (proyektorda/tələbə cihazında yükləmə üçün
-- ayrıca giriş tələb olunmur), amma YÜKLƏMƏ/SİLMƏ yalnız öz qovluğuna icazəlidir.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('lesson-images', 'lesson-images', true, 8388608, array['image/png','image/jpeg','image/webp','image/gif'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Hər müəllim yalnız öz istifadəçi adı ilə başlayan qovluğa ("username/...")
-- yükləyə/silə bilər — "storage.foldername(name)" faylın yolunu "/" ilə
-- hissələrə bölür, birinci hissə qovluq adıdır.
--
-- QEYD (real Postgres ilə tapılmış incəlik): DELETE-in "WHERE" şərtinə görə
-- sətri tapa bilməsi üçün, DELETE siyasətindən ƏLAVƏ, HƏMİN ROL üçün bir
-- SELECT siyasəti də olmalıdır — əks halda DELETE sətri "görə bilmədiyi"
-- üçün sükutla 0 sətir siləcək (öz faylını belə silə bilməyəcək). Ona görə
-- aşağıda ayrıca SELECT siyasəti də var (ictimai "public" bucket bayrağı
-- ilə qarışdırılmasın — o, YALNIZ ictimai URL endpoint-inə aiddir, storage
-- API-dən (list/remove) sətri görmək üçün bu SELECT siyasəti lazımdır).
drop policy if exists "lesson_images_select" on storage.objects;
create policy "lesson_images_select"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'lesson-images'
    and exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = (storage.foldername(name))[1])
  );

drop policy if exists "lesson_images_insert" on storage.objects;
create policy "lesson_images_insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'lesson-images'
    and exists(select 1 from public.profiles p where p.id = auth.uid() and p.role = 'teacher' and p.username = (storage.foldername(name))[1])
  );

drop policy if exists "lesson_images_delete" on storage.objects;
create policy "lesson_images_delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'lesson-images'
    and exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = (storage.foldername(name))[1])
  );
