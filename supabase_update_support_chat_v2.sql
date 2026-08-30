-- ════════════════════════════════════════════════════════════════
-- SözLab — Dəstək Söhbətinə MÜƏLLİM səlahiyyəti əlavə edir.
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- ÖNCƏ supabase_update_support_chat.sql-in run edildiyini fərz edir.
-- Nə dəyişir: indi müəllim də ÖZ SİNFİNİN şagirdləri ilə dəstək söhbəti
-- apara bilər (admin/direktor kimi bütün şagirdlər YOX, yalnız öz sinfi).
-- ════════════════════════════════════════════════════════════════

-- 1) sender_role-a 'teacher' dəyərini əlavə et
alter table public.support_messages drop constraint if exists support_messages_sender_role_check;
alter table public.support_messages add constraint support_messages_sender_role_check
  check (sender_role in ('user','admin','director','teacher'));

-- 2) SELECT siyasətini yenilə — müəllim öz sinfinin şagirdlərinin söhbətini görə bilsin
drop policy if exists "support_messages_select" on public.support_messages;
create policy "support_messages_select"
  on public.support_messages for select
  to authenticated
  using (
    exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = support_messages.username)
    or public.is_admin(auth.uid())
    or public.is_director(auth.uid())
    or exists(
      select 1 from public.profiles p
      where p.username = support_messages.username
        and p.class_grade <> ''
        and public.is_teacher_of(auth.uid(), p.class_grade)
    )
  );

-- 3) send_support_message() — müəllim YALNIZ öz sinfinin şagirdinə yaza bilər
create or replace function public.send_support_message(p_username text, p_body text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_caller_username text;
  v_role text;
  v_teacher_class text;
  v_body text := trim(coalesce(p_body,''));
begin
  select username, role, teacher_class into v_caller_username, v_role, v_teacher_class
    from public.profiles where id = auth.uid();
  if v_caller_username is null then
    raise exception 'Profil tapılmadı';
  end if;
  if char_length(v_body) = 0 or char_length(v_body) > 1000 then
    raise exception 'Mesaj boş və ya çox uzundur';
  end if;

  if v_role = 'admin' or v_role = 'director' then
    if not exists(select 1 from public.profiles where username = p_username) then
      raise exception 'İstifadəçi tapılmadı';
    end if;
    insert into public.support_messages(username, sender_role, sender_name, body)
    values (p_username, v_role, v_caller_username, v_body);
  elsif v_role = 'teacher' then
    if not exists(select 1 from public.profiles where username = p_username and class_grade = v_teacher_class) then
      raise exception 'Bu şagird sizin sinfinizdə deyil';
    end if;
    insert into public.support_messages(username, sender_role, sender_name, body)
    values (p_username, 'teacher', v_caller_username, v_body);
  else
    insert into public.support_messages(username, sender_role, sender_name, body)
    values (v_caller_username, 'user', v_caller_username, v_body);
  end if;
end;
$$;

grant execute on function public.send_support_message(text, text) to authenticated;

-- 4) mark_support_read() — müəllim öz sinfinin şagird mesajlarını "oxunub" işarələyə bilsin,
--    şagird isə artıq admin/direktor/müəllim mesajlarının hamısını "oxunub" işarələsin.
create or replace function public.mark_support_read(p_username text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_caller_username text;
  v_role text;
  v_teacher_class text;
begin
  select username, role, teacher_class into v_caller_username, v_role, v_teacher_class
    from public.profiles where id = auth.uid();

  if v_role = 'admin' or v_role = 'director' then
    update public.support_messages set read = true
      where username = p_username and sender_role = 'user' and read = false;
  elsif v_role = 'teacher' and exists(select 1 from public.profiles where username = p_username and class_grade = v_teacher_class) then
    update public.support_messages set read = true
      where username = p_username and sender_role = 'user' and read = false;
  elsif v_caller_username = p_username then
    update public.support_messages set read = true
      where username = p_username and sender_role in ('admin','director','teacher') and read = false;
  end if;
end;
$$;

grant execute on function public.mark_support_read(text) to authenticated;
