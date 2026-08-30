-- ══════════════════════════════════════════════════════════════
-- SözLab – Supabase Cədvəlləri (Email-siz versiya)
-- Supabase → SQL Editor-də işlət
-- ══════════════════════════════════════════════════════════════

-- 1. PROFILES cədvəli (Supabase Auth YOX, birbaşa username)
CREATE TABLE IF NOT EXISTS public.profiles (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  username    text UNIQUE NOT NULL,
  display_name text,
  xp          integer DEFAULT 0,
  level       integer DEFAULT 1,
  streak      integer DEFAULT 0,
  learned     text[] DEFAULT '{}',
  last_visit  text,
  created_at  timestamp with time zone DEFAULT now()
);

-- 2. STORIES cədvəli
CREATE TABLE IF NOT EXISTS public.stories (
  id           uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  username     text NOT NULL,
  display_name text,
  text         text NOT NULL,
  likes        integer DEFAULT 0,
  created_at   timestamp with time zone DEFAULT now()
);

-- 3. ANNOUNCEMENTS cədvəli
CREATE TABLE IF NOT EXISTS public.announcements (
  id         uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  title      text NOT NULL,
  content    text NOT NULL,
  type       text DEFAULT 'info',
  created_at timestamp with time zone DEFAULT now()
);

-- ══════════════════════════════════════════════════════════════
-- RLS – Hamıya oxumaq icazəsi, yazmaq hər kəsə açıq
-- (Email/auth olmadığı üçün sadə politika)
-- ══════════════════════════════════════════════════════════════

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

-- Profiles: hamı oxuya bilir, hamı yaza bilir
CREATE POLICY "profiles_select" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "profiles_insert" ON public.profiles FOR INSERT WITH CHECK (true);
CREATE POLICY "profiles_update" ON public.profiles FOR UPDATE USING (true);
CREATE POLICY "profiles_delete" ON public.profiles FOR DELETE USING (true);

-- Stories: hamı oxuya bilir, hamı yaza bilir
CREATE POLICY "stories_select"  ON public.stories FOR SELECT USING (true);
CREATE POLICY "stories_insert"  ON public.stories FOR INSERT WITH CHECK (true);
CREATE POLICY "stories_delete"  ON public.stories FOR DELETE USING (true);

-- Announcements: hamı oxuya bilir, hamı yaza bilir
CREATE POLICY "announce_select" ON public.announcements FOR SELECT USING (true);
CREATE POLICY "announce_insert" ON public.announcements FOR INSERT WITH CHECK (true);

-- ══════════════════════════════════════════════════════════════
-- QEYD: Bu versiyada Supabase Auth işlədilmir.
-- İstifadəçilər yalnız username ilə qeydiyyatdan keçir.
-- Email rate limit problemi tamamilə yoxdur.
-- Authentication → Settings-də heç nə dəyişdirməyə ehtiyac yoxdur.
-- ══════════════════════════════════════════════════════════════
