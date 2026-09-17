-- ══════════════════════════════════════════════════════════════════════════
-- DÜZƏLİŞ: Duel "Rəqibin bitirməsini gözləyirik..." ekranında ilişib qalır
--
-- PROBLEM:
--   Duel YALNIZ submit_duel_answer() daxilində yekunlaşır — yəni hər iki
--   oyunçunun p1_finished_at / p2_finished_at dəyəri dolduqda. Cavablar
--   brauzerdən "göndər və unut" şəklində yollanırdı və xəta səssizcə
--   udulurdu. Şəbəkə bir anlıq kəsilsə (mobil internet, səhifə arxa plana
--   keçsə və s.) bir cavab itir → həmin oyunçunun progress-i heç vaxt sual
--   sayına çatmır → finished_at yazılmır → duel ƏBƏDİ 'active' qalır və
--   HƏR İKİ oyunçu "gözləyirik..." ekranında donur.
--
-- HƏLL (iki hissədən ibarətdir):
--   1) index.html tərəfdə: cavablar təkrar cəhdlə göndərilir və bitməzdən
--      əvvəl hamısının serverə çatdığı gözlənilir.
--   2) BU FAYL: ilişib qalmış duelləri yekunlaşdırmaq üçün finalize_duel()
--      funksiyası. Oyunçu gözləmə ekranında "Nəticəni yekunlaşdır" düyməsi
--      ilə çağıra bilər; cavabsız qalan suallar səhv sayılır.
--
-- Supabase → SQL Editor → bu faylı yapışdır → Run.
-- Təkrar işlətmək təhlükəsizdir.
-- ══════════════════════════════════════════════════════════════════════════

create or replace function public.finalize_duel(p_duel_id bigint)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_username text;
  v_duel record;
  v_winner text;
  v_xp_p1 integer;
  v_xp_p2 integer;
begin
  select username into v_username from public.profiles where id = auth.uid();
  if v_username is null then return; end if;

  select * into v_duel from public.duels where id = p_duel_id for update;
  if v_duel is null then return; end if;
  if v_duel.status <> 'active' then return; end if;

  -- Yalnız duelin iştirakçısı yekunlaşdıra bilər
  if v_duel.p1_username <> v_username and v_duel.p2_username <> v_username then
    return;
  end if;

  -- Cavab verməyən tərəfin vaxtı bağlanır (qalan suallar səhv sayılır)
  if v_duel.p1_finished_at is null then
    update public.duels set p1_finished_at = now() where id = p_duel_id;
  end if;
  if v_duel.p2_finished_at is null then
    update public.duels set p2_finished_at = now() where id = p_duel_id;
  end if;

  select * into v_duel from public.duels where id = p_duel_id for update;

  if v_duel.p1_score > v_duel.p2_score then v_winner := v_duel.p1_username;
  elsif v_duel.p2_score > v_duel.p1_score then v_winner := v_duel.p2_username;
  else v_winner := null;
  end if;

  if v_winner is null then
    v_xp_p1 := 20; v_xp_p2 := 20;
  elsif v_winner = v_duel.p1_username then
    v_xp_p1 := 30; v_xp_p2 := 10;
  else
    v_xp_p1 := 10; v_xp_p2 := 30;
  end if;

  update public.profiles set xp = xp + v_xp_p1, level = public.compute_level(xp + v_xp_p1)
    where username = v_duel.p1_username;
  update public.profiles set xp = xp + v_xp_p2, level = public.compute_level(xp + v_xp_p2)
    where username = v_duel.p2_username;

  update public.duels
    set status = 'finished', winner_username = v_winner, finished_at = now()
    where id = p_duel_id;
end;
$$;

grant execute on function public.finalize_duel(bigint) to authenticated;

comment on function public.finalize_duel(bigint) is
  'İlişib qalmış və ya rəqibi tərk etmiş dueli cari xallara görə yekunlaşdırır.';


-- ─────────────────────────────────────────────────────────────
-- İNDİ İLİŞİB QALMIŞ DUELLƏRİ TƏMİZLƏ
-- 30 dəqiqədən çox 'active' qalmış duelləri ləğv edirik ki,
-- oyunçuların "Davam edən Duellər" siyahısı təmizlənsin.
-- (Ləğv olunan duelə görə XP verilmir.)
-- ─────────────────────────────────────────────────────────────
update public.duels
  set status = 'cancelled'
  where status = 'active'
    and created_at < now() - interval '30 minutes';


-- ─────────────────────────────────────────────────────────────
-- YOXLAMA: hazırda ilişib qalan duel qalıbmı?
-- ─────────────────────────────────────────────────────────────
select id, p1_username, p2_username, status,
       p1_progress, p2_progress,
       jsonb_array_length(questions) as sual_sayi,
       p1_finished_at is not null as p1_bitirdi,
       p2_finished_at is not null as p2_bitirdi,
       created_at
from public.duels
where status = 'active'
order by created_at desc;
