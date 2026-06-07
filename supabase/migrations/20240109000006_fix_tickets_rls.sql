-- REC-07: Fix maintenance_tickets RLS policies
-- Removes overly broad "tickets: scoped read" that allows deactivated members to read tickets.
-- Consolidates into separate, tightly-scoped technician and tenant policies.
-- See architecture review RLSGAP-2, RLSGAP-3

-- ============================================================
-- Drop problematic policies
-- ============================================================
DROP POLICY IF EXISTS "tickets: scoped read" ON public.maintenance_tickets;
DROP POLICY IF EXISTS "tickets: technician read assigned" ON public.maintenance_tickets;
DROP POLICY IF EXISTS "tickets: technician update assigned" ON public.maintenance_tickets;

-- ============================================================
-- Technician: read only active-membership assigned tickets
-- ============================================================
CREATE POLICY "tickets: technician read assigned"
  ON public.maintenance_tickets FOR SELECT
  TO authenticated
  USING (
    assigned_to = (SELECT auth.uid())
    AND public.has_property_role(property_id, 'technician')
    AND EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = (SELECT auth.uid())
        AND m.property_id = maintenance_tickets.property_id
        AND m.deactivated_at IS NULL
    )
  );

-- ============================================================
-- Tenant: read own tickets (via tenant_profiles)
-- ============================================================
CREATE POLICY "tickets: tenant read own"
  ON public.maintenance_tickets FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.tenant_profiles tp
      WHERE tp.id = maintenance_tickets.tenant_profile_id
        AND tp.user_id = (SELECT auth.uid())
        AND tp.archived_at IS NULL
    )
  );

-- ============================================================
-- Technician: update only active-membership assigned tickets
-- ============================================================
CREATE POLICY "tickets: technician update assigned"
  ON public.maintenance_tickets FOR UPDATE
  TO authenticated
  USING (
    assigned_to = (SELECT auth.uid())
    AND public.has_property_role(property_id, 'technician')
    AND EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = (SELECT auth.uid())
        AND m.property_id = maintenance_tickets.property_id
        AND m.deactivated_at IS NULL
    )
  )
  WITH CHECK (
    assigned_to = (SELECT auth.uid())
    AND public.has_property_role(property_id, 'technician')
    AND EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = (SELECT auth.uid())
        AND m.property_id = maintenance_tickets.property_id
        AND m.deactivated_at IS NULL
    )
  );
