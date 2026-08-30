-- ════════════════════════════════════════════════════════════════
-- SözLab — Dəstək Söhbəti (sayt-daxili mesajlaşma, Tawk.to-ya əlavə)
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- Mövcud cədvəlləri POZMUR, sadəcə yeni cədvəl/funksiya əlavə edir.
-- ════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────
-- 1) SUPPORT_MESSAGES CƏDVƏLİ
--    Hər sətir bir mesajdır. "username" HƏMİŞƏ şagirdin (thread sahibinin)
--    adıdır — admin/direktor cavab yazanda da eyni username-ə yazılır,
--    sender_role kimin yazdığını göstərir. Cədvələ birbaşa insert/update
--    icazəsi YOXDUR — yalnız aşağıdakı iki SECURITY DEFINER funksiyası
--    yazır ki, istifadəçi başqasının adına mesaj yaza və ya "oxunub"
--    bayrağını özü saxtalaşdıra bilməsin.
-- ─────────────────────────────────────────────
create table if not exists public.support_messages (
  id bigint generated always as identity primary key,
  username text not null,
  sender_role text not null check (sender_role in ('user','admin','director')),
  sender_name text not null default '',
  body text not null check (char_length(body) between 1 and 1000),
  read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists idx_support_messages_username on public.support_messages (username, created_at);

alter table public.support_messages enable row level security;

drop policy if exists "support_messages_select" on public.support_messages;
create policy "support_messages_select"
  on public.support_messages for select
  to authenticated
  using (
    exists(select 1 from public.profiles p where p.id = auth.uid() and p.username = support_messages.username)
    or public.is_admin(auth.uid())
    or public.is_director(auth.uid())
  );

-- QEYD: insert/update siyasəti QƏSDƏN yoxdur.

-- ─────────────────────────────────────────────
-- 2) send_support_message() — mesaj göndərmək.
--    Adi istifadəçi YALNIZ öz thread-inə yaza bilər (p_username input-u
--    onun üçün görməzdən gəlinir — özünü başqası kimi göstərə bilməsin
--    deyə). Admin/direktor istənilən şagirdin thread-inə yaza bilər.
-- ─────────────────────────────────────────────
create or replace function public.send_support_message(p_username text, p_body text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_caller_username text;
  v_role text;
  v_is_staff boolean;
  v_body text := trim(coalesce(p_body,''));
begin
  select username, role into v_caller_username, v_role from public.profiles where id = auth.uid();
  if v_caller_username is null then
    raise exception 'Profil tapılmadı';
  end if;
  if char_length(v_body) = 0 or char_length(v_body) > 1000 then
    raise exception 'Mesaj boş və ya çox uzundur';
  end if;

  v_is_staff := (v_role = 'admin' or v_role = 'director');

  if v_is_staff then
    if not exists(select 1 from public.profiles where username = p_username) then
      raise exception 'İstifadəçi tapılmadı';
    end if;
    insert into public.support_messages(username, sender_role, sender_name, body)
    values (p_username, v_role, v_caller_username, v_body);
  else
    insert into public.support_messages(username, sender_role, sender_name, body)
    values (v_caller_username, 'user', v_caller_username, v_body);
  end if;
end;
$$;

grant execute on function public.send_support_message(text, text) to authenticated;

-- ─────────────────────────────────────────────
-- 3) mark_support_read() — söhbət açılanda qarşı tərəfin mesajlarını
--    "oxunub" işarələyir (şagird üçün: admin/direktor mesajlarını;
--    admin/direktor üçün: o şagirdin öz mesajlarını).
-- ─────────────────────────────────────────────
create or replace function public.mark_support_read(p_username text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_caller_username text;
  v_is_staff boolean;
begin
  select username, (role = 'admin' or role = 'director') into v_caller_username, v_is_staff
    from public.profiles where id = auth.uid();

  if v_is_staff then
    update public.support_messages set read = true
      where username = p_username and sender_role = 'user' and read = false;
  elsif v_caller_username = p_username then
    update public.support_messages set read = true
      where username = p_username and sender_role in ('admin','director') and read = false;
  end if;
end;
$$;

grant execute on function public.mark_support_read(text) to authenticated;
