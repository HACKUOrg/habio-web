-- Phase 0E: Drop legacy role / access tables and columns
-- See docs/03-database-schema.md §8

-- ============================================================
-- Remove legacy tenant_id FKs (replaced by tenant_profile_id)
-- ============================================================
ALTER TABLE public.bills
  DROP CONSTRAINT IF EXISTS bills_tenant_id_fkey;

DROP INDEX IF EXISTS idx_bills_tenant_id;

ALTER TABLE public.bills
  DROP COLUMN IF EXISTS tenant_id;

ALTER TABLE public.maintenance_tickets
  DROP CONSTRAINT IF EXISTS maintenance_tickets_tenant_id_fkey;

DROP INDEX IF EXISTS idx_tickets_tenant_id;

ALTER TABLE public.maintenance_tickets
  DROP COLUMN IF EXISTS tenant_id;

-- ============================================================
-- Drop legacy access tables
-- ============================================================
DROP TRIGGER IF EXISTS sync_room_on_lease_change ON public.tenants;
DROP TRIGGER IF EXISTS set_updated_at_tenants ON public.tenants;
DROP TRIGGER IF EXISTS set_updated_at_property_staff ON public.property_staff;

DROP TABLE IF EXISTS public.tenants CASCADE;
DROP TABLE IF EXISTS public.property_staff CASCADE;
DROP TABLE IF EXISTS public.organization_members CASCADE;

-- ============================================================
-- Remove profiles.role dependencies (must precede DROP COLUMN)
-- ============================================================
DROP POLICY IF EXISTS "profiles: own update" ON public.profiles;
CREATE POLICY "profiles: own update"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (id = (SELECT auth.uid()))
  WITH CHECK (id = (SELECT auth.uid()));

DROP FUNCTION IF EXISTS public.current_user_role();

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
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

-- ============================================================
-- Drop legacy columns
-- ============================================================
ALTER TABLE public.organizations
  DROP CONSTRAINT IF EXISTS organizations_owner_id_fkey;

DROP INDEX IF EXISTS idx_organizations_owner_id;

ALTER TABLE public.organizations
  DROP COLUMN IF EXISTS owner_id;

ALTER TABLE public.properties
  DROP CONSTRAINT IF EXISTS properties_manager_id_fkey;

DROP INDEX IF EXISTS idx_properties_manager_id;

ALTER TABLE public.properties
  DROP COLUMN IF EXISTS manager_id;

DROP INDEX IF EXISTS idx_profiles_role;

ALTER TABLE public.profiles
  DROP COLUMN IF EXISTS role;

-- ============================================================
-- Drop legacy helper functions
-- ============================================================
DROP FUNCTION IF EXISTS public.is_property_tenant(uuid);
DROP FUNCTION IF EXISTS public.is_organization_admin(uuid);
DROP FUNCTION IF EXISTS public.is_organization_viewer(uuid);
DROP FUNCTION IF EXISTS public.is_organization_owner(uuid);
DROP FUNCTION IF EXISTS public.is_organization_member(uuid);
DROP FUNCTION IF EXISTS public.is_property_staff(uuid);
DROP FUNCTION IF EXISTS public.get_managed_property_ids();

-- Replace is_property_manager with membership-based implementation for any remaining references
CREATE OR REPLACE FUNCTION public.is_property_manager(p_property_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.can_manage_property(p_property_id);
$$;

REVOKE EXECUTE ON FUNCTION public.is_property_manager(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_property_manager(uuid) TO authenticated;

-- ============================================================
-- Drop legacy enums (after dependent columns/tables removed)
-- ============================================================
DROP TYPE IF EXISTS public.organization_member_scope;
DROP TYPE IF EXISTS public.user_role;

-- ============================================================
-- Tighten anon DML (re-apply after grants)
-- ============================================================
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM anon;
