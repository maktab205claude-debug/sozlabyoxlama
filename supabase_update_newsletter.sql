-- ════════════════════════════════════════════════════════════════
-- SözLab — Giriş ekranındakı footer-dəki "Yeniliklərdən xəbərdar olun"
-- bülleten qutusu üçün. Bu skripti Supabase Dashboard → SQL Editor-da
-- açıb "Run" edin.
--
-- Qeyd: bu, HEÇ BİR şəxsi məlumatla (profillə) bağlı deyil — sadəcə
-- giriş etməmiş bir ziyarətçinin könüllü buraxdığı e-poçtu saxlayır.
-- Yalnız admin bu siyahını görə bilər (Supabase Dashboard → Table
-- Editor → newsletter_signups, və ya SQL Editor-da sorğu ilə).
-- ════════════════════════════════════════════════════════════════

create table if not exists public.newsletter_signups (
  id bigint generated always as identity primary key,
  email text not null,
  created_at timestamptz not null default now()
);
create unique index if not exists idx_newsletter_email on public.newsletter_signups (lower(email));

alter table public.newsletter_signups enable row level security;

-- Giriş etməmiş (anon) VƏ giriş etmiş hər kəs öz e-poçtunu əlavə edə bilər —
-- amma yalnız insert, heç kim (admin xaric) siyahını oxuya/silə bilməz.
drop policy if exists "newsletter_insert_public" on public.newsletter_signups;
create policy "newsletter_insert_public"
  on public.newsletter_signups for insert
  to anon, authenticated
  with check (
    email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    and length(email) < 200
  );

drop policy if exists "newsletter_select_admin" on public.newsletter_signups;
create policy "newsletter_select_admin"
  on public.newsletter_signups for select
  to authenticated
  using (public.is_admin(auth.uid()));
