-- Phase 0B: Backfill memberships, tenant_profiles, and denormalized organization_id
-- Idempotent: only inserts/fills rows that are still missing.

-- ============================================================
-- B.1: organization owners -> owner memberships
-- ============================================================
INSERT INTO public.memberships (user_id, organization_id, property_id, role, created_at)
SELECT o.owner_id, o.id, NULL, 'owner', o.created_at
FROM public.organizations o
WHERE o.owner_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.memberships m
    WHERE m.user_id = o.owner_id
      AND m.organization_id = o.id
      AND m.role = 'owner'
      AND m.property_id IS NULL
      AND m.deactivated_at IS NULL
  );

INSERT INTO public.memberships (user_id, organization_id, property_id, role, created_at)
SELECT om.user_id, om.organization_id, NULL, 'owner', om.created_at
FROM public.organization_members om
WHERE om.scope = 'owner'
  AND NOT EXISTS (
    SELECT 1
    FROM public.memberships m
    WHERE m.user_id = om.user_id
      AND m.organization_id = om.organization_id
      AND m.role = 'owner'
      AND m.property_id IS NULL
      AND m.deactivated_at IS NULL
  );

-- Org admins become manager on every property in the organization.
INSERT INTO public.memberships (user_id, organization_id, property_id, role, created_at)
SELECT om.user_id, p.organization_id, p.id, 'manager', om.created_at
FROM public.organization_members om
JOIN public.properties p ON p.organization_id = om.organization_id
WHERE om.scope = 'admin'
  AND p.organization_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.memberships m
    WHERE m.user_id = om.user_id
      AND m.organization_id = p.organization_id
      AND m.property_id = p.id
      AND m.role = 'manager'
      AND m.deactivated_at IS NULL
  );

-- ============================================================
-- B.2: property managers -> manager memberships
-- ============================================================
INSERT INTO public.memberships (user_id, organization_id, property_id, role, created_at)
SELECT p.manager_id, p.organization_id, p.id, 'manager', p.created_at
FROM public.properties p
WHERE p.organization_id IS NOT NULL
  AND p.manager_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.memberships m
    WHERE m.user_id = p.manager_id
      AND m.organization_id = p.organization_id
      AND m.property_id = p.id
      AND m.role = 'manager'
      AND m.deactivated_at IS NULL
  );

-- ============================================================
-- B.3: property_staff -> technician/housekeeper memberships
-- ============================================================
INSERT INTO public.memberships (user_id, organization_id, property_id, role, created_at)
SELECT
  ps.user_id,
  p.organization_id,
  ps.property_id,
  ps.role::text::public.membership_role,
  ps.created_at
FROM public.property_staff ps
JOIN public.properties p ON p.id = ps.property_id
WHERE p.organization_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.memberships m
    WHERE m.user_id = ps.user_id
      AND m.organization_id = p.organization_id
      AND m.property_id = ps.property_id
      AND m.role = ps.role::text::public.membership_role
      AND m.deactivated_at IS NULL
  );

-- ============================================================
-- B.4: tenants -> tenant memberships + tenant_profiles
-- Preserve tenants.id as tenant_profiles.id for FK migration.
-- ============================================================
INSERT INTO public.memberships (user_id, organization_id, property_id, role, created_at)
SELECT t.user_id, p.organization_id, t.property_id, 'tenant', t.created_at
FROM public.tenants t
JOIN public.properties p ON p.id = t.property_id
WHERE p.organization_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1
    FROM public.memberships m
    WHERE m.user_id = t.user_id
      AND m.organization_id = p.organization_id
      AND m.property_id = t.property_id
      AND m.role = 'tenant'
      AND m.deactivated_at IS NULL
  );

INSERT INTO public.tenant_profiles (
  id,
  user_id,
  membership_id,
  organization_id,
  property_id,
  room_id,
  lease_start,
  lease_end,
  lease_status,
  emergency_contact_name,
  emergency_contact_phone,
  notes,
  archived_at,
  created_at,
  updated_at
)
SELECT
  t.id,
  t.user_id,
  m.id,
  p.organization_id,
  t.property_id,
  t.room_id,
  t.lease_start,
  t.lease_end,
  t.lease_status,
  t.emergency_contact_name,
  t.emergency_contact_phone,
  t.notes,
  t.archived_at,
  t.created_at,
  t.updated_at
FROM public.tenants t
JOIN public.properties p ON p.id = t.property_id
JOIN public.memberships m
  ON m.user_id = t.user_id
 AND m.organization_id = p.organization_id
 AND m.property_id = t.property_id
 AND m.role = 'tenant'
 AND m.deactivated_at IS NULL
WHERE p.organization_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.tenant_profiles tp WHERE tp.id = t.id
  );

-- ============================================================
-- B.5: Point bills and tickets at tenant_profiles
-- ============================================================
UPDATE public.bills b
SET tenant_profile_id = t.id
FROM public.tenants t
WHERE b.tenant_id = t.id
  AND b.tenant_profile_id IS NULL;

UPDATE public.maintenance_tickets mt
SET tenant_profile_id = t.id
FROM public.tenants t
WHERE mt.tenant_id = t.id
  AND mt.tenant_profile_id IS NULL;

-- ============================================================
-- B.6: Denormalize organization_id on operational tables
-- ============================================================
UPDATE public.billing_periods bp
SET organization_id = p.organization_id
FROM public.properties p
WHERE bp.property_id = p.id
  AND bp.organization_id IS NULL
  AND p.organization_id IS NOT NULL;

UPDATE public.meter_readings mr
SET organization_id = p.organization_id
FROM public.properties p
WHERE mr.property_id = p.id
  AND mr.organization_id IS NULL
  AND p.organization_id IS NOT NULL;

UPDATE public.housekeeping_tasks ht
SET organization_id = p.organization_id
FROM public.properties p
WHERE ht.property_id = p.id
  AND ht.organization_id IS NULL
  AND p.organization_id IS NOT NULL;
