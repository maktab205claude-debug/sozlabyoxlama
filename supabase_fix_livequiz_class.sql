-- ══════════════════════════════════════════════════════════════════════════
-- DÜZƏLİŞ: Canlı Sinif Yarışmasına heç kim qoşula bilmirdi ("sinif boş")
--
-- PROBLEM:
--   join_live_quiz() şagirdin sinfini sessiyanın sinfi ilə HƏRFİ-HƏRFİNƏ
--   müqayisə edirdi:
--       if v_session.class_grade <> coalesce(v_class,'') then ...
--   Sessiyanın sinfi müəllimin profilindəki `teacher_class`-dan gəlir
--   (məs. "10b" və ya "10 B"), şagirdinki isə qeydiyyatda seçilən
--   `class_grade`-dır (məs. "10B"). Bir hərfin registri və ya bir boşluq
--   fərqli olan kimi müqayisə uğursuz olurdu və HƏR şagird
--   "Bu yarışma sizin sinfiniz üçün deyil" xətası alırdı — nəticədə
--   müəllimin ekranında iştirakçı siyahısı boş qalırdı.
--
-- HƏLL:
--   Hər iki tərəf müqayisədən əvvəl normallaşdırılır: böyük hərflərə salınır,
--   boşluq/defis kimi simvollar silinir. Yəni "10b", "10 B", "10-B" və "10B"
--   artıq eyni sinif sayılır. Xəta mesajı da hansı sinfin gözlənildiyini
--   göstərir ki, uyğunsuzluq olsa müəllim dərhal görsün.
--
-- Supabase → SQL Editor → bu faylı yapışdır → Run.
-- Təkrar işlətmək təhlükəsizdir.
-- ══════════════════════════════════════════════════════════════════════════

-- Sinif adını müqayisə üçün normal hala salan köməkçi funksiya
create or replace function public.norm_class(p text)
returns text
language sql
immutable
as $$
  select upper(regexp_replace(coalesce(p, ''), '[^a-zA-Z0-9]', '', 'g'));
$$;

comment on function public.norm_class(text) is
  'Sinif adını müqayisə üçün normallaşdırır: "10 b" → "10B"';


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

  -- Normallaşdırılmış müqayisə (əsas düzəliş).
  -- Sessiyanın sinfi boşdursa, yarışma bütün siniflərə açıq sayılır.
  if coalesce(v_session.class_grade,'') <> ''
     and public.norm_class(v_session.class_grade) <> public.norm_class(v_class) then
    raise exception 'Bu yarışma % sinfi üçündür, sizin sinfiniz isə %',
      v_session.class_grade, coalesce(nullif(v_class,''), 'təyin edilməyib');
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


-- ─────────────────────────────────────────────────────────────
-- YOXLAMA: müəllimlərin sinfi ilə şagirdlərin sinfi uyğun gəlirmi?
-- Bu sorğu hər müəllim sinfi üçün neçə şagirdin tapıldığını göstərir.
-- Əgər "sagird_sayi" 0-dırsa, həmin müəllimin teacher_class dəyəri
-- şagirdlərin class_grade dəyəri ilə uyğun gəlmir.
-- ─────────────────────────────────────────────────────────────
select
  t.username            as muellim,
  t.teacher_class       as muellim_sinfi,
  count(s.id)           as sagird_sayi
from public.profiles t
left join public.profiles s
  on s.role = 'user'
 and public.norm_class(s.class_grade) = public.norm_class(t.teacher_class)
where t.role = 'teacher' and coalesce(t.teacher_class,'') <> ''
group by t.username, t.teacher_class
order by sagird_sayi asc;
