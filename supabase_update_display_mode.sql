-- ════════════════════════════════════════════════════════════════
-- SözLab — "Böyük Ekran" rejimi üçün ictimai (login TƏLƏB ETMƏYƏN) məlumat RPC-si.
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- ÖNCƏ bu skriptlərin run edildiyini fərz edir: supabase_setup.sql,
-- supabase_update_duel.sql, supabase_update_live_quiz.sql.
--
-- Nə üçün: dəhlizdəki/akt zalındakı televizor və ya proyektora qoşulan
-- brauzerdə HEÇ KİM daxil olmadan (login etmədən) canlı lent göstərilir.
-- Ona görə bu RPC anon (login etməmiş) istifadəçiyə də açıqdır — amma
-- YALNIZ artıq digər liderbord funksiyalarında (public_profiles,
-- class_leaderboard) göstərilən səviyyədə ictimai məlumatı (ad, xal,
-- sinif) qaytarır, heç bir yeni həssas sahə (email, sual mətnləri və s.)
-- açmır.
-- ════════════════════════════════════════════════════════════════

create or replace function public.get_display_activity()
returns jsonb
language plpgsql
security definer set search_path = public
stable
as $$
declare
  v_duels jsonb;
  v_quizzes jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
      'p1', p1_username, 'p2', p2_username,
      'p1_score', p1_score, 'p2_score', p2_score,
      'winner', winner_username
    ) order by created_at desc), '[]'::jsonb)
  into v_duels
  from (
    select * from public.duels where status = 'finished' order by created_at desc limit 8
  ) d;

  select coalesce(jsonb_agg(jsonb_build_object(
      'class', class_grade, 'top', top_list
    ) order by created_at desc), '[]'::jsonb)
  into v_quizzes
  from (
    select s.id, s.class_grade, s.created_at,
      (select coalesce(jsonb_agg(jsonb_build_object('name', lp.display_name, 'score', lp.score) order by lp.score desc), '[]'::jsonb)
       from (select * from public.live_quiz_participants where session_id = s.id order by score desc limit 3) lp
      ) as top_list
    from public.live_quiz_sessions s
    where s.status = 'finished'
    order by s.created_at desc
    limit 5
  ) s;

  return jsonb_build_object('duels', v_duels, 'quizzes', v_quizzes);
end;
$$;

grant execute on function public.get_display_activity() to anon, authenticated;
