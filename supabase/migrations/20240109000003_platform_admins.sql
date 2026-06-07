-- REC-04: platform_admins table + is_platform_admin() helper
-- See docs/06-implementation-roadmap.md §2 (Phase 0 exit criteria)

-- ============================================================
-- Add suspended_at to organizations
-- ============================================================
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS suspended_at timestamptz;

-- ============================================================
-- platform_admins (service-role only; no authenticated access)
-- ============================================================
CREATE TABLE public.platform_admins (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  granted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);

-- ============================================================
-- RLS — service-role only; no authenticated policies
-- ============================================================
ALTER TABLE public.platform_admins ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.platform_admins FROM authenticated, anon;

COMMENT ON TABLE public.platform_admins IS
  'Platform administrator grant log. Accessible via service role only; no authenticated RLS policies.';

-- ============================================================
-- Helper function
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.platform_admins pa
    WHERE pa.user_id = (SELECT auth.uid())
      AND pa.revoked_at IS NULL
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_platform_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_platform_admin() TO authenticated;
