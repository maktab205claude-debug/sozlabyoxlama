-- ════════════════════════════════════════════════════════════════
-- SözLab — Direktor rolu + Müəllim Tapşırıqları üçün əlavə SQL
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR. ÖNCƏ bu iki skriptin run edildiyini fərz edir:
--   1) supabase_update_students.sql   (class_grade sütunu)
--   2) supabase_update_teacher_and_league.sql  (teacher_class, is_teacher_of())
-- ════════════════════════════════════════════════════════════════

-- 1) role sütununa 'director' dəyərini əlavə et
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check
  check (role in ('user','admin','teacher','director'));

-- 2) is_director() — RLS siyasətlərində istifadə üçün, SECURITY DEFINER ilə
--    RLS-i bypass edərək sonsuz rekursiyanın qarşısını alır (is_admin() ilə eyni məntiq).
create or replace function public.is_director(uid uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles where id = uid and role = 'director'
  );
$$;

grant execute on function public.is_director(uuid) to authenticated;

-- 3) ÖZ SƏTRİNİ ROL ESKALASİYASINDAN QORUYAN TRİGGER
--    (RLS WITH CHECK əvəzinə trigger istifadə edirik ki, teacher/director öz XP-sini,
--    streak-ini, adını s. dəyişə bilsin — sadəcə ÖZ rolunu/sinfini dəyişə bilməsin.)
create or replace function public.prevent_self_role_escalation()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if auth.uid() = old.id and not public.is_admin(auth.uid()) and not public.is_director(auth.uid()) then
    new.role := old.role;
    new.teacher_class := old.teacher_class;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_self_role_escalation on public.profiles;
create trigger trg_prevent_self_role_escalation
  before update on public.profiles
  for each row execute function public.prevent_self_role_escalation();

-- 4) PROFİLLƏR RLS siyasətlərini yenilə:
--    SELECT — direktor hamını görür (admin daxil).
--    UPDATE/DELETE — direktor admin XARİC hər kəsi dəyişə/silə bilər.
--    (Köhnə "id=auth.uid() and role='user'" WITH CHECK şərti silinir, çünki artıq
--    rol-eskalasiya qorunması yuxarıdakı trigger ilə edilir — əks halda teacher/director
--    öz XP-sini belə yeniləyə bilməzdi.)
drop policy if exists "profiles_select_own_or_admin" on public.profiles;
create policy "profiles_select_own_or_admin"
  on public.profiles for select
  to authenticated
  using (
    id = auth.uid()
    or public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or (class_grade <> '' and public.is_teacher_of(auth.uid(), class_grade))
  );

drop policy if exists "profiles_update_own_or_admin" on public.profiles;
create policy "profiles_update_own_or_admin"
  on public.profiles for update
  to authenticated
  using (
    id = auth.uid()
    or public.is_admin(auth.uid())
    or (public.is_director(auth.uid()) and role <> 'admin')
  )
  with check (
    id = auth.uid()
    or public.is_admin(auth.uid())
    or (public.is_director(auth.uid()) and role <> 'admin')
  );

drop policy if exists "profiles_delete_own_or_admin" on public.profiles;
create policy "profiles_delete_own_or_admin"
  on public.profiles for delete
  to authenticated
  using (
    id = auth.uid()
    or public.is_admin(auth.uid())
    or (public.is_director(auth.uid()) and role <> 'admin')
  );

-- 5) Direktora elan (announcement) və hekayə moderasiyası səlahiyyəti də verilir
--    (məktəb rəhbərliyi bunları idarə edə bilməlidir; söz bankı YOX — bu admin-ə məxsus qalır).
drop policy if exists "announcements_write_admin_only" on public.announcements;
create policy "announcements_write_admin_only"
  on public.announcements for insert
  to authenticated
  with check (public.is_admin(auth.uid()) or public.is_director(auth.uid()));

drop policy if exists "announcements_update_admin_only" on public.announcements;
create policy "announcements_update_admin_only"
  on public.announcements for update
  to authenticated
  using (public.is_admin(auth.uid()) or public.is_director(auth.uid()));

drop policy if exists "announcements_delete_admin_only" on public.announcements;
create policy "announcements_delete_admin_only"
  on public.announcements for delete
  to authenticated
  using (public.is_admin(auth.uid()) or public.is_director(auth.uid()));

drop policy if exists "stories_update_own_or_admin" on public.stories;
create policy "stories_update_own_or_admin"
  on public.stories for update
  to authenticated
  using (user_id = auth.uid() or public.is_admin(auth.uid()) or public.is_director(auth.uid()));

drop policy if exists "stories_delete_own_or_admin" on public.stories;
create policy "stories_delete_own_or_admin"
  on public.stories for delete
  to authenticated
  using (user_id = auth.uid() or public.is_admin(auth.uid()) or public.is_director(auth.uid()));

-- ─────────────────────────────────────────────
-- 6) MÜƏLLİM TAPŞIRIQLARI (class_tasks + class_task_completions)
-- ─────────────────────────────────────────────
create table if not exists public.class_tasks (
  id bigint generated always as identity primary key,
  teacher_username text not null,
  class_grade text not null check (class_grade ~ '^(1[01]|[1-9])[A-D]$'),
  title text not null check (char_length(title) between 1 and 200),
  target_xp integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists idx_class_tasks_class on public.class_tasks (class_grade, created_at desc);

create table if not exists public.class_task_completions (
  task_id bigint not null references public.class_tasks(id) on delete cascade,
  username text not null,
  completed_at timestamptz not null default now(),
  primary key (task_id, username)
);

alter table public.class_tasks enable row level security;
alter table public.class_task_completions enable row level security;

-- class_tasks: görmə hüququ — admin, direktor, tapşırığı yaradan müəllim, və ya
-- həmin sinifdəki şagirdlər. Yazma/silmə — YALNIZ admin, direktor, ya da o sinfin müəllimi.
drop policy if exists "class_tasks_select" on public.class_tasks;
create policy "class_tasks_select"
  on public.class_tasks for select
  to authenticated
  using (
    public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or public.is_teacher_of(auth.uid(), class_grade)
    or exists(select 1 from public.profiles p where p.id = auth.uid() and p.class_grade = class_tasks.class_grade)
  );

drop policy if exists "class_tasks_insert" on public.class_tasks;
create policy "class_tasks_insert"
  on public.class_tasks for insert
  to authenticated
  with check (
    public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or public.is_teacher_of(auth.uid(), class_grade)
  );

drop policy if exists "class_tasks_delete" on public.class_tasks;
create policy "class_tasks_delete"
  on public.class_tasks for delete
  to authenticated
  using (
    public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or public.is_teacher_of(auth.uid(), class_grade)
  );

-- class_task_completions: görmə hüququ eyni qayda ilə (müəllim/admin/direktor,
-- ya da öz tamamlama qeydini görən şagirdin özü). Yazma — YALNIZ öz adına.
drop policy if exists "class_task_completions_select" on public.class_task_completions;
create policy "class_task_completions_select"
  on public.class_task_completions for select
  to authenticated
  using (
    public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = class_task_completions.username)
    or exists(
      select 1 from public.class_tasks t
      where t.id = class_task_completions.task_id
        and public.is_teacher_of(auth.uid(), t.class_grade)
    )
  );

drop policy if exists "class_task_completions_insert" on public.class_task_completions;
create policy "class_task_completions_insert"
  on public.class_task_completions for insert
  to authenticated
  with check (
    exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = class_task_completions.username)
  );

-- ════════════════════════════════════════════════════════════════
-- QEYD 1: Direktor rolunu təyin etmək (bunun üçün UI düyməsi YOXDUR —
-- admin/direktor yaratmaq YALNIZ birbaşa SQL ilə edilir, təhlükəsizlik üçün):
--
-- update public.profiles set role='director'
--   where username='BURAYA_ISTIFADECI_ADINIZI_YAZIN';
--
-- QEYD 2: Direktor "🛠️ Admin" nişanlı istifadəçilərə TOXUNA BİLMİR (RLS server
-- tərəfdə bloklayır, admin panelində "🔒 Admin — redaktə edilə bilməz" göstərilir),
-- amma onları siyahıda GÖRƏ BİLİR. Söz bankı (Sözlər tabı) YALNIZ admin üçündür.
-- ════════════════════════════════════════════════════════════════
