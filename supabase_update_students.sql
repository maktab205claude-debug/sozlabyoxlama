-- ════════════════════════════════════════════════════════════════
-- SözLab — Şagird Sinif Sistemi üçün əlavə SQL
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR, sadəcə yeni sütunlar əlavə edir və
-- handle_new_user() trigger-ini yeniləyir ki, qeydiyyatda daxil edilən
-- Ad/Soyad/Sinif məlumatları avtomatik profilə yazılsın.
-- ════════════════════════════════════════════════════════════════

-- 1) Yeni sütunlar: Ad, Soyad, Sinif (məs. "5B")
alter table public.profiles
  add column if not exists first_name text not null default '';
alter table public.profiles
  add column if not exists last_name text not null default '';
alter table public.profiles
  add column if not exists class_grade text not null default '';

-- Sinif formatını yoxlayan constraint (1-11 rəqəm + A/B/C/D hərfi, və ya boş —
-- mövcud istifadəçilər üçün geriyə uyğunluq saxlanılsın deyə boş qiymətə icazə verilir)
alter table public.profiles drop constraint if exists class_grade_format;
alter table public.profiles add constraint class_grade_format
  check (class_grade = '' or class_grade ~ '^(1[01]|[1-9])[A-D]$');

create index if not exists idx_profiles_class_grade on public.profiles (class_grade);

-- 2) handle_new_user() trigger-ini yenilə: indi first_name/last_name/class_grade də yazsın
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
begin
  v_username := lower(coalesce(new.raw_user_meta_data->>'username', 'user_' || substr(new.id::text, 1, 8)));
  v_display_name := coalesce(new.raw_user_meta_data->>'display_name', v_username);
  v_first_name := coalesce(new.raw_user_meta_data->>'first_name', '');
  v_last_name := coalesce(new.raw_user_meta_data->>'last_name', '');
  v_class_grade := coalesce(new.raw_user_meta_data->>'class_grade', '');

  -- əgər username formatı yanlışdırsa və ya artıq tutulubsa, unikal fallback yarat
  if v_username !~ '^[a-z0-9_]{3,20}$' or exists (select 1 from public.profiles p where p.username = v_username) then
    v_username := 'user_' || substr(new.id::text, 1, 8);
  end if;

  -- sinif formatı yanlışdırsa sakitcə boş buraxılır (constraint pozulmasın deyə)
  if v_class_grade !~ '^(1[01]|[1-9])[A-D]$' then
    v_class_grade := '';
  end if;

  insert into public.profiles (id, username, display_name, first_name, last_name, class_grade, xp, level, streak, learned, badges, role, last_visit)
  values (new.id, v_username, v_display_name, v_first_name, v_last_name, v_class_grade, 0, 1, 0, '{}', '{}', 'user', null)
  on conflict (id) do nothing;

  return new;
end;
$$;

-- ════════════════════════════════════════════════════════════════
-- QEYD: first_name/last_name/class_grade QƏSDƏN public_profiles
-- görünüşünə (liderbord üçün istifadə olunur) ƏLAVƏ EDİLMİR — real
-- ad/soyad və sinif məlumatı bütün saytda hamıya açıq olmamalıdır,
-- yalnız admin panelində (birbaşa profiles cədvəlindən, mövcud RLS
-- "own row or admin" qaydası ilə) görünəcək.
-- ════════════════════════════════════════════════════════════════
