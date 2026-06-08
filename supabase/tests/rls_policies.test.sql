-- pgTAP Phase 0 foundation tests
-- Schema integrity, cross-org/property isolation, audit/platform admin guards

BEGIN;

SELECT plan(44);

-- ============================================================
-- Schema integrity: enums
-- ============================================================
SELECT has_type('public', 'membership_role', 'membership_role enum exists');
SELECT has_type('public', 'invitation_status', 'invitation_status enum exists');
SELECT has_type('public', 'property_status', 'property_status enum exists');
SELECT has_type('public', 'room_status', 'room_status enum exists');
SELECT has_type('public', 'lease_status', 'lease_status enum exists');
SELECT has_type('public', 'notification_channel', 'notification_channel enum exists');
SELECT has_type('public', 'notification_delivery_status', 'notification_delivery_status enum exists');

-- ============================================================
-- Schema integrity: core tables
-- ============================================================
SELECT has_table('public', 'profiles', 'profiles table exists');
SELECT has_table('public', 'organizations', 'organizations table exists');
SELECT has_table('public', 'properties', 'properties table exists');
SELECT has_table('public', 'memberships', 'memberships table exists');
SELECT has_table('public', 'invitations', 'invitations table exists');
SELECT has_table('public', 'tenant_profiles', 'tenant_profiles table exists');
SELECT has_table('public', 'buildings', 'buildings table exists');
SELECT has_table('public', 'rooms', 'rooms table exists');

-- ============================================================
-- Schema integrity: foundation tables
-- ============================================================
SELECT has_table('public', 'user_identities', 'user_identities table exists');
SELECT has_table('public', 'platform_admins', 'platform_admins table exists');
SELECT has_table('public', 'audit_logs', 'audit_logs table exists');
SELECT has_table('public', 'subscription_plans', 'subscription_plans table exists');
SELECT has_table('public', 'organization_subscriptions', 'organization_subscriptions table exists');
SELECT has_table('public', 'usage_counters', 'usage_counters table exists');
SELECT has_table('public', 'notifications', 'notifications table exists');
SELECT has_table('public', 'notification_deliveries', 'notification_deliveries table exists');
SELECT has_table('public', 'move_in_transactions', 'move_in_transactions table exists');
SELECT has_table('public', 'move_out_transactions', 'move_out_transactions table exists');
SELECT has_table('public', 'meter_snapshots', 'meter_snapshots table exists');
SELECT has_table('public', 'inspection_items', 'inspection_items table exists');

-- ============================================================
-- Schema integrity: archive tables + RPCs
-- ============================================================
SELECT has_table('public', 'invitations_archive', 'invitations_archive table exists');
SELECT has_table('public', 'notifications_archive', 'notifications_archive table exists');
SELECT has_table('public', 'audit_logs_archive', 'audit_logs_archive table exists');
SELECT has_function('public', 'record_audit_event', ARRAY['uuid', 'uuid', 'text', 'jsonb']);
SELECT has_function('public', 'check_property_limit', ARRAY['uuid']);
SELECT has_function('public', 'is_feature_enabled', ARRAY['uuid', 'text']);

-- ============================================================
-- Legacy removal
-- ============================================================
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'profiles'
      AND column_name = 'role'
  ),
  'profiles.role column removed'
);

SELECT ok(
  to_regclass('public.organization_members') IS NULL,
  'organization_members table removed'
);

SELECT ok(
  to_regclass('public.property_staff') IS NULL,
  'property_staff table removed'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'properties'
      AND column_name = 'manager_id'
  ),
  'properties.manager_id column removed'
);

-- ============================================================
-- Second org for cross-org isolation tests
-- ============================================================
INSERT INTO public.organizations (id, name, slug)
VALUES (
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'Other Organization',
  'other-org'
);

INSERT INTO public.properties (id, organization_id, name, address)
VALUES (
  'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
  'Other Property',
  '999 Other Street'
);

-- ============================================================
-- Cross-organization SELECT denied (tenant)
-- ============================================================
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claim.sub TO '11111111-1111-1111-1111-111111111102';

SELECT is_empty(
  $$SELECT 1 FROM public.properties WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'$$,
  'tenant cannot read other organization property'
);

SELECT is_empty(
  $$SELECT 1 FROM public.organizations WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$$,
  'tenant cannot read other organization'
);

-- ============================================================
-- Cross-property SELECT denied (technician)
-- ============================================================
RESET role;
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claim.sub TO '11111111-1111-1111-1111-111111111103';

SELECT ok(
  NOT public.has_property_role(
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
    'technician'
  ),
  'technician has no role on other property'
);

SELECT is_empty(
  $$SELECT 1 FROM public.rooms WHERE property_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'$$,
  'technician cannot read rooms in unassigned property'
);

-- ============================================================
-- audit_logs UPDATE/DELETE denied for authenticated
-- ============================================================
RESET role;

INSERT INTO public.audit_logs (
  id,
  actor_id,
  organization_id,
  property_id,
  event_type,
  metadata
)
VALUES (
  'cccccccc-cccc-cccc-cccc-cccccccccccc',
  '11111111-1111-1111-1111-111111111101',
  '55555555-5555-5555-5555-555555555501',
  '22222222-2222-2222-2222-222222222201',
  'tenant_created',
  '{}'::jsonb
);

SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claim.sub TO '11111111-1111-1111-1111-111111111101';

SELECT throws_ok(
  $$UPDATE public.audit_logs
    SET event_type = 'tampered'
    WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'$$,
  '42501',
  NULL,
  'authenticated cannot UPDATE audit_logs'
);

SELECT throws_ok(
  $$DELETE FROM public.audit_logs
    WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'$$,
  '42501',
  NULL,
  'authenticated cannot DELETE audit_logs'
);

-- ============================================================
-- platform_admins not readable by authenticated
-- ============================================================
RESET role;

INSERT INTO public.platform_admins (user_id)
VALUES ('11111111-1111-1111-1111-111111111101')
ON CONFLICT (user_id) DO NOTHING;

SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claim.sub TO '11111111-1111-1111-1111-111111111101';

SELECT throws_ok(
  $$SELECT 1 FROM public.platform_admins$$,
  '42501',
  NULL,
  'authenticated cannot read platform_admins'
);

SELECT * FROM finish();
ROLLBACK;
