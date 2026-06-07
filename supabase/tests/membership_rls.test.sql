-- pgTAP tests for membership-based RBAC schema and RLS
-- Requires seed data from supabase/seed.sql

BEGIN;

SELECT plan(18);

-- ============================================================
-- Schema integrity (post-migration / seed)
-- ============================================================
SELECT ok(
  (SELECT COUNT(*) FROM public.properties WHERE organization_id IS NULL) = 0,
  'all properties have organization_id'
);

SELECT ok(
  (SELECT COUNT(*) FROM public.rooms WHERE building_id IS NULL) = 0,
  'all rooms have building_id'
);

SELECT ok(
  (SELECT COUNT(*) FROM public.buildings WHERE organization_id IS NULL) = 0,
  'all buildings have organization_id'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM public.memberships m
    WHERE m.organization_id = '55555555-5555-5555-5555-555555555501'
      AND m.role = 'owner'
      AND m.property_id IS NULL
      AND m.deactivated_at IS NULL
  ),
  'seed organization has an active owner membership'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.tenant_profiles
    WHERE id = '44444444-4444-4444-4444-444444444401'
  ),
  'seed tenant profile exists'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'memberships'
      AND indexname = 'memberships_owner_unique'
  ),
  'memberships_owner_unique partial index exists'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'invitations'
      AND indexname = 'invitations_pending_unique'
  ),
  'invitations_pending_unique partial index exists'
);

-- ============================================================
-- Helper functions
-- ============================================================
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claim.sub TO '11111111-1111-1111-1111-111111111101';

SELECT ok(
  public.is_org_owner('55555555-5555-5555-5555-555555555501'),
  'owner passes is_org_owner'
);

SELECT ok(
  public.can_manage_property('22222222-2222-2222-2222-222222222201'),
  'owner passes can_manage_property'
);

SET LOCAL request.jwt.claim.sub TO '11111111-1111-1111-1111-111111111102';

SELECT ok(
  NOT public.can_manage_property('22222222-2222-2222-2222-222222222201'),
  'tenant cannot manage property'
);

RESET role;

-- ============================================================
-- Owner RLS
-- ============================================================
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claim.sub TO '11111111-1111-1111-1111-111111111101';

SELECT isnt_empty(
  $$SELECT 1 FROM public.organizations WHERE id = '55555555-5555-5555-5555-555555555501'$$,
  'owner can read own organization'
);

SELECT isnt_empty(
  $$SELECT 1 FROM public.memberships WHERE organization_id = '55555555-5555-5555-5555-555555555501'$$,
  'owner can read org memberships'
);

-- ============================================================
-- Housekeeper RLS
-- ============================================================
RESET role;
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claim.sub TO '11111111-1111-1111-1111-111111111104';

SELECT isnt_empty(
  $$SELECT 1 FROM public.buildings WHERE property_id = '22222222-2222-2222-2222-222222222201'$$,
  'housekeeper can read buildings in assigned property'
);

SELECT is_empty(
  $$SELECT 1 FROM public.organizations$$,
  'housekeeper cannot read organizations'
);

-- ============================================================
-- Meter reading: housekeeper cannot self-approve
-- ============================================================
RESET role;

INSERT INTO public.billing_periods (id, property_id, name, start_date, end_date, created_by)
VALUES (
  '99999999-9999-9999-9999-999999999901',
  '22222222-2222-2222-2222-222222222201',
  'Test Period',
  CURRENT_DATE - 30,
  CURRENT_DATE,
  '11111111-1111-1111-1111-111111111101'
);

INSERT INTO public.meter_readings (
  id, billing_period_id, room_id, property_id, submitted_by, status
)
VALUES (
  '99999999-9999-9999-9999-999999999902',
  '99999999-9999-9999-9999-999999999901',
  '33333333-3333-3333-3333-333333333301',
  '22222222-2222-2222-2222-222222222201',
  '11111111-1111-1111-1111-111111111104',
  'submitted'
);

SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claim.sub TO '11111111-1111-1111-1111-111111111104';

SELECT throws_ok(
  $$UPDATE public.meter_readings
    SET status = 'approved'
    WHERE id = '99999999-9999-9999-9999-999999999902'$$,
  '42501',
  NULL,
  'housekeeper cannot self-approve meter reading'
);

-- ============================================================
-- Technician cross-property guard
-- ============================================================
RESET role;
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claim.sub TO '11111111-1111-1111-1111-111111111103';

SELECT ok(
  NOT public.has_property_role(
    '00000000-0000-0000-0000-000000000099',
    'technician'
  ),
  'has_property_role returns false for unassigned property'
);

-- ============================================================
-- Last owner guard
-- ============================================================
RESET role;

SELECT throws_ok(
  $$UPDATE public.memberships
    SET deactivated_at = now()
    WHERE id = '77777777-7777-7777-7777-777777777701'$$,
  'P0001',
  'cannot deactivate the last owner of an organization',
  'cannot deactivate the last owner of an organization'
);

-- ============================================================
-- Archived property hidden from tenant
-- ============================================================
RESET role;

UPDATE public.properties
SET archived_at = now()
WHERE id = '22222222-2222-2222-2222-222222222201';

SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claim.sub TO '11111111-1111-1111-1111-111111111102';

SELECT is_empty(
  $$SELECT 1 FROM public.properties WHERE id = '22222222-2222-2222-2222-222222222201'$$,
  'tenant cannot read archived property'
);

SELECT * FROM finish();
ROLLBACK;
