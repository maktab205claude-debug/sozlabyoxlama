-- ════════════════════════════════════════════════════════════════
-- SözLab — Duel-i ləğv etmə (abandon/cancel) imkanı.
-- Bu skripti Supabase Dashboard → SQL Editor-da açıb "Run" edin.
-- ÖNCƏ supabase_update_duel.sql-in run edildiyini fərz edir.
--
-- Nə üçün: bəzən bir duel (şəbəkə problemi, brauzer dondurması və s.
-- səbəbdən) ilişib qalırsa, indiyədək oyunçunun onu siyahıdan silmək
-- imkanı yox idi — "Davam edən Duellər" bölməsində əbədi qalırdı.
-- İndi hər iki tərəf istənilən vaxt (pending və ya active statusunda)
-- öz duelini ləğv edə bilər.
-- ════════════════════════════════════════════════════════════════

-- 1) status sahəsinə 'cancelled' dəyərini əlavə et
alter table public.duels drop constraint if exists duels_status_check;
alter table public.duels add constraint duels_status_check
  check (status in ('pending','active','declined','finished','cancelled'));

-- 2) cancel_duel() — YALNIZ duelin özündəki iki tərəfdən biri çağıra bilər,
--    və YALNIZ hələ bitməmiş (pending/active) duel ləğv edilə bilər —
--    artıq 'finished' olan bir duelin nəticəsini/XP-sini geri ala bilməz.
create or replace function public.cancel_duel(p_duel_id bigint)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
begin
  select username into v_username from public.profiles where id = auth.uid();
  if v_username is null then
    raise exception 'Profil tapılmadı';
  end if;

  update public.duels
    set status = 'cancelled'
    where id = p_duel_id
      and (p1_username = v_username or p2_username = v_username)
      and status in ('pending','active');
end;
$$;

grant execute on function public.cancel_duel(bigint) to authenticated;
