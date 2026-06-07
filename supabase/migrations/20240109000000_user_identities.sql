-- REC-01: user_identities replaces line_connections
-- See docs/02-system-architecture.md §3.1

-- ============================================================
-- user_identities
-- ============================================================
CREATE TABLE public.user_identities (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  provider         text NOT NULL,
  provider_user_id text NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_user_id),
  UNIQUE (user_id, provider)
);

CREATE INDEX idx_user_identities_user_id ON public.user_identities (user_id);

ALTER TABLE public.user_identities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_identities: own select"
  ON public.user_identities FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE POLICY "user_identities: own insert"
  ON public.user_identities FOR INSERT
  TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "user_identities: own delete"
  ON public.user_identities FOR DELETE
  TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- ============================================================
-- Backfill from legacy line_connections before drop
-- ============================================================
INSERT INTO public.user_identities (user_id, provider, provider_user_id, created_at)
SELECT
  lc.user_id,
  'line',
  lc.line_user_id,
  lc.created_at
FROM public.line_connections lc
WHERE lc.is_active = true
ON CONFLICT (provider, provider_user_id) DO NOTHING;

-- ============================================================
-- Drop line_connections
-- ============================================================
DROP TRIGGER IF EXISTS set_updated_at_line_connections ON public.line_connections;
DROP POLICY IF EXISTS "line_connections: own select" ON public.line_connections;
DROP TABLE IF EXISTS public.line_connections;

-- ============================================================
-- handle_new_user: profile + email identity
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email)
  );

  IF NEW.email IS NOT NULL AND trim(NEW.email) <> '' THEN
    INSERT INTO public.user_identities (user_id, provider, provider_user_id)
    VALUES (NEW.id, 'email', lower(trim(NEW.email)))
    ON CONFLICT (user_id, provider) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

-- Backfill email identities for existing users
INSERT INTO public.user_identities (user_id, provider, provider_user_id)
SELECT
  u.id,
  'email',
  lower(trim(u.email))
FROM auth.users u
WHERE u.email IS NOT NULL
  AND trim(u.email) <> ''
ON CONFLICT (provider, provider_user_id) DO NOTHING;
