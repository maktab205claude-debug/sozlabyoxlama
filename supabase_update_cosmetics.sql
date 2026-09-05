-- ════════════════════════════════════════════════════════════════
-- SözLab — "Döyüş Bileti" (Battle Pass) — DAİMİ, itməyən kosmetik
-- çərçivə/tema sistemi. Bu skripti Supabase Dashboard → SQL Editor-da
-- açıb "Run" edin. Mövcud cədvəlləri POZMUR.
--
-- QƏSDƏN "mövsümlük"/vaxt-təzyiqli DEYİL: real oyunlardakı Battle Pass-lar
-- adətən mövsüm bitəndə əldə edilməyən mükafatı həmişəlik itirir (FOMO
-- yaradır) — məktəb kontekstində bu, zəif/yavaş öyrənən şagirdi
-- demotivasiya edə bilər. Ona görə burda hər kosmetik element sadəcə
-- ÜMUMİ XP həddinə görə açılır və BİR DƏFƏ açılandan sonra HEÇ VAXT
-- itmir — "Ünvan" (TITLES) sistemi ilə eyni fəlsəfə.
-- ════════════════════════════════════════════════════════════════

-- 1) KATALOQ CƏDVƏLİ — həm frontend, həm backend RPC eyni mənbədən oxuyur
--    ki, "neçə XP-də nə açılır" məlumatı İKİ yerdə (JS + SQL) təkrarlanıb
--    bir-birindən aralı düşməsin.
create table if not exists public.cosmetics_catalog (
  id text primary key,
  type text not null check (type in ('frame','theme')),
  name text not null,
  icon text not null default '',
  min_xp integer not null default 0,
  sort_order integer not null default 0
);

insert into public.cosmetics_catalog(id,type,name,icon,min_xp,sort_order) values
  ('frame_none','frame','Sadə','',0,0),
  ('frame_bronze','frame','Bürünc Çərçivə','🥉',200,1),
  ('frame_silver','frame','Gümüş Çərçivə','🥈',800,2),
  ('frame_gold','frame','Qızıl Çərçivə','🥇',2000,3),
  ('frame_diamond','frame','Almaz Çərçivə','💎',5000,4),
  ('theme_default','theme','Standart Tema','',0,0),
  ('theme_sunset','theme','Gün Batımı','🌇',500,1),
  ('theme_ocean','theme','Okean','🌊',1500,2),
  ('theme_neon','theme','Neon','⚡',3500,3)
on conflict (id) do nothing;

alter table public.cosmetics_catalog enable row level security;

drop policy if exists "cosmetics_catalog_select" on public.cosmetics_catalog;
create policy "cosmetics_catalog_select"
  on public.cosmetics_catalog for select
  to anon, authenticated
  using (true);

-- QEYD: insert/update/delete siyasəti YOXDUR — kataloqu genişləndirmək
-- lazım gələrsə, Supabase Dashboard → Table Editor-dan admin əl ilə əlavə edir.

-- 2) PROFİLƏ İKİ YENİ SÜTUN — hazırda taxılmış çərçivə/tema.
alter table public.profiles add column if not exists equipped_frame text not null default 'frame_none';
alter table public.profiles add column if not exists equipped_theme text not null default 'theme_default';

-- 3) equip_cosmetic() — YALNIZ XP həddinə çatmış istifadəçi bir elementi
--    taxa bilər. Bunu RPC ilə (birbaşa profiles update yerinə) etməyimizin
--    səbəbi: əks halda bir şagird brauzer konsolundan `equipped_frame`
--    sahəsini birbaşa dəyişib hələ açmadığı bir çərçivəni "saxta" taxa bilərdi.
create or replace function public.equip_cosmetic(p_cosmetic_id text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_xp integer;
  v_cat record;
begin
  select xp into v_xp from public.profiles where id = auth.uid();
  if v_xp is null then
    raise exception 'Profil tapılmadı';
  end if;

  select * into v_cat from public.cosmetics_catalog where id = p_cosmetic_id;
  if v_cat is null then
    raise exception 'Naməlum kosmetik element';
  end if;
  if v_xp < v_cat.min_xp then
    raise exception 'Bu elementi hələ açmamısınız (lazımi XP: %)', v_cat.min_xp;
  end if;

  if v_cat.type = 'frame' then
    update public.profiles set equipped_frame = p_cosmetic_id where id = auth.uid();
  else
    update public.profiles set equipped_theme = p_cosmetic_id where id = auth.uid();
  end if;
end;
$$;

grant execute on function public.equip_cosmetic(text) to authenticated;
grant select on public.cosmetics_catalog to anon, authenticated;

-- 4) public_profiles görünüşünə çərçivə/tema sütunlarını əlavə edirik ki,
--    liderbordda da (gələcəkdə istəsək) başqalarının çərçivəsi görünə bilsin.
create or replace view public.public_profiles as
  select username, display_name, xp, level, streak, days_active, equipped_frame, equipped_theme
  from public.profiles;

grant select on public.public_profiles to anon, authenticated;
