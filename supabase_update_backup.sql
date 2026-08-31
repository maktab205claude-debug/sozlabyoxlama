-- ════════════════════════════════════════════════════════════════
-- SözLab — Ehtiyat nüsxə (backup) RPC-si.
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- ÖNCƏ bütün əvvəlki SQL skriptlərinin run edildiyini fərz edir
-- (public.is_admin() funksiyası buradan istifadə olunur).
--
-- Nə üçün: Supabase bulud xidmətidir — nəzəri olaraq xidmət kəsilsə,
-- səhv silinsə və ya plan/hesab problemi yaransa, məlumat itkisi riski
-- var. Bu RPC ilə admin istənilən vaxt BÜTÜN cədvəlləri tək bir JSON
-- faylına köçürüb öz kompüterinə saxlaya bilər — Supabase-in özündəki
-- avtomatik "Backups" funksiyasından (Dashboard → Database → Backups,
-- plana görə fərqlənir) ƏLAVƏ, ikinci bir təhlükəsizlik qatı kimi.
--
-- Təhlükəsizlik: yalnız role='admin' olan istifadəçi çağıra bilər
-- (digər admin-only RPC-lərlə eyni is_admin() yoxlaması). Heç bir
-- yeni "service role" açarı və ya xarici kimlik lazım deyil — admin
-- sadəcə öz mövcud hesabı ilə tətbiqdən bir düyməyə basır.
-- ════════════════════════════════════════════════════════════════

create or replace function public.admin_export_backup()
returns jsonb
language plpgsql
security definer set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Yalnız adminlər ehtiyat nüsxə ala bilər';
  end if;

  select jsonb_build_object(
    'exported_at', now(),
    'profiles', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.profiles t),
    'stories', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.stories t),
    'announcements', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.announcements t),
    'class_tasks', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.class_tasks t),
    'class_task_completions', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.class_task_completions t),
    'duels', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.duels t),
    'xp_log', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.xp_log t),
    'live_quiz_sessions', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.live_quiz_sessions t),
    'live_quiz_participants', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.live_quiz_participants t),
    'support_messages', (select coalesce(jsonb_agg(t), '[]'::jsonb) from public.support_messages t)
  ) into v_result;

  return v_result;
end;
$$;

grant execute on function public.admin_export_backup() to authenticated;
