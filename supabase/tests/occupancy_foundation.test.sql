-- pgTAP: occupancy foundation (schema, RLS isolation, meter_snapshots immutability)
-- Requires seed data from supabase/seed.sql

BEGIN;

SELECT plan(16);

-- ============================================================
-- Schema integrity
-- ============================================================
SELECT has_type('public', 'move_in_transaction_status', 'move_in_transaction_status enum exists');
SELECT has_type('public', 'move_out_transaction_status', 'move_out_transaction_status enum exists');
SELECT has_type('public', 'inspection_item_status', 'inspection_item_status enum exists');
SELECT has_type('public', 'meter_snapshot_type', 'meter_snapshot_type enum exists');

SELECT has_table('public', 'move_in_transactions', 'move_in_transactions table exists');
SELECT has_table('public', 'move_out_transactions', 'move_out_transactions table exists');
SELECT has_table('public', 'meter_snapshots', 'meter_snapshots table exists');
SELECT has_table('public', 'inspection_items', 'inspection_items table exists');

-- ============================================================
-- Fixture: move-in transaction for seed tenant
-- ============================================================
INSERT INTO public.move_in_transactions (
  id,
  organization_id,
  property_id,
  room_id,
  tenant_profile_id,
  move_in_date,
  status,
  created_by
)
VALUES (
  'dddddddd-dddd-dddd-dddd-dddddddddd01',
  '55555555-5555-5555-5555-555555555501',
  '22222222-2222-2222-2222-222222222201',
  '33333333-3333-3333-3333-333333333301',
  '44444444-4444-4444-4444-444444444401',
  CURRENT_DATE,
  'draft',
  '11111111-1111-1111-1111-111111111101'
);

INSERT INTO public.meter_snapshots (
  id,
  organization_id,
  property_id,
  room_id,
  snapshot_type,
  move_in_transaction_id,
  electric_reading,
  water_reading,
  reading_date,
  submitted_by
)
VALUES (
  'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01',
  '55555555-5555-5555-5555-555555555501',
  '22222222-2222-2222-2222-222222222201',
  '33333333-3333-3333-3333-333333333301',
  'move_in',
  'dddddddd-dddd-dddd-dddd-dddddddddd01',
  100.0000,
  50.0000,
  CURRENT_DATE,
  '11111111-1111-1111-1111-111111111101'
);

-- ============================================================
-- Tenant can read own move-in transaction
-- ============================================================
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claim.sub TO '11111111-1111-1111-1111-111111111102';

SELECT isnt_empty(
  $$SELECT 1 FROM public.move_in_transactions
    WHERE id = 'dddddddd-dddd-dddd-dddd-dddddddddd01'$$,
  'tenant can read own move-in transaction'
);

SELECT isnt_empty(
  $$SELECT 1 FROM public.meter_snapshots
    WHERE id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01'$$,
  'tenant can read own meter snapshot'
);

-- ============================================================
-- Technician cannot read occupancy in assigned property (no blanket access)
-- ============================================================
RESET role;
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claim.sub TO '11111111-1111-1111-1111-111111111103';

SELECT is_empty(
  $$SELECT 1 FROM public.move_in_transactions
    WHERE id = 'dddddddd-dddd-dddd-dddd-dddddddddd01'$$,
  'technician cannot read move-in without inspection assignment'
);

SELECT is_empty(
  $$SELECT 1 FROM public.meter_snapshots
    WHERE id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01'$$,
  'technician cannot read meter snapshot without inspection assignment'
);

-- ============================================================
-- Cross-property denial (manager of property A vs other org property)
-- ============================================================
RESET role;

INSERT INTO public.organizations (id, name, slug)
VALUES ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'Other Org', 'other-org-occupancy');

INSERT INTO public.properties (id, organization_id, name, address)
VALUES (
  '12121212-1212-1212-1212-121212121212',
  'ffffffff-ffff-ffff-ffff-ffffffffffff',
  'Other Property',
  '1 Other Road'
);

SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claim.sub TO '11111111-1111-1111-1111-111111111101';

SELECT is_empty(
  $$SELECT 1 FROM public.move_in_transactions
    WHERE organization_id = 'ffffffff-ffff-ffff-ffff-ffffffffffff'$$,
  'owner cannot read other organization move-in transactions'
);

-- ============================================================
-- meter_snapshots immutability for authenticated
-- ============================================================
RESET role;
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claim.sub TO '11111111-1111-1111-1111-111111111101';

SELECT throws_ok(
  $$UPDATE public.meter_snapshots
    SET electric_reading = 999
    WHERE id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01'$$,
  '42501',
  NULL,
  'authenticated cannot UPDATE meter_snapshots'
);

SELECT throws_ok(
  $$DELETE FROM public.meter_snapshots
    WHERE id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeee01'$$,
  '42501',
  NULL,
  'authenticated cannot DELETE meter_snapshots'
);

-- ============================================================
-- Scope trigger rejects mismatched tenant_profile
-- ============================================================
RESET role;

SELECT throws_ok(
  $$INSERT INTO public.move_in_transactions (
      organization_id,
      property_id,
      room_id,
      tenant_profile_id,
      move_in_date,
      created_by
    ) VALUES (
      'ffffffff-ffff-ffff-ffff-ffffffffffff',
      '22222222-2222-2222-2222-222222222201',
      '33333333-3333-3333-3333-333333333301',
      '44444444-4444-4444-4444-444444444401',
      CURRENT_DATE,
      '11111111-1111-1111-1111-111111111101'
    )$$,
  'P0001',
  'move_in_transactions scope does not match tenant_profile',
  'move_in scope trigger rejects cross-org tenant_profile'
);

SELECT * FROM finish();
ROLLBACK;
