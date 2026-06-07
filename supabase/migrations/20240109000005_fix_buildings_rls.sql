-- REC-06: Fix buildings: members read RLS policy
-- Removes can_access_property() (N+1 anti-pattern) and denormalizes organization_id onto buildings.
-- See docs/04-rbac.md §6.1 (R-32, R-33)

-- ============================================================
-- Denormalize organization_id onto buildings
-- ============================================================
ALTER TABLE public.buildings
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE RESTRICT;

-- Backfill organization_id from properties
UPDATE public.buildings b
SET organization_id = p.organization_id
FROM public.properties p
WHERE p.id = b.property_id
  AND b.organization_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_buildings_organization_id
  ON public.buildings (organization_id);

-- ============================================================
-- Drop and recreate the offending policy
-- ============================================================
DROP POLICY IF EXISTS "buildings: members read" ON public.buildings;

CREATE POLICY "buildings: members read"
  ON public.buildings FOR SELECT
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = (SELECT auth.uid())
        AND m.property_id = buildings.property_id
        AND m.deactivated_at IS NULL
    )
  );

-- ============================================================
-- Also update manager owner full access to use organization_id directly
-- ============================================================
DROP POLICY IF EXISTS "buildings: manager owner full access" ON public.buildings;

CREATE POLICY "buildings: manager owner full access"
  ON public.buildings FOR ALL
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  )
  WITH CHECK (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  );
