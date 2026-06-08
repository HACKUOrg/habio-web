-- pgTAP: subscription foundation (plan seed, RLS, usage_counters guards)
-- Requires seed data from supabase/seed.sql

BEGIN;

SELECT plan(13);

-- ============================================================
-- Plan seed limits (docs/03 §4.10)
-- ============================================================
SELECT ok(
  (SELECT max_properties FROM public.subscription_plans WHERE name = 'free') = 1,
  'free plan max_properties is 1'
);

SELECT ok(
  (SELECT max_rooms FROM public.subscription_plans WHERE name = 'free') = 20,
  'free plan max_rooms is 20'
);

SELECT ok(
  (SELECT max_properties FROM public.subscription_plans WHERE name = 'starter') = 3,
  'starter plan max_properties is 3'
);

SELECT ok(
  (SELECT max_rooms FROM public.subscription_plans WHERE name = 'starter') = 50,
  'starter plan max_rooms is 50'
);

SELECT ok(
  (SELECT max_properties FROM public.subscription_plans WHERE name = 'pro') = 10,
  'pro plan max_properties is 10'
);

SELECT ok(
  (SELECT max_rooms FROM public.subscription_plans WHERE name = 'pro') = 200,
  'pro plan max_rooms is 200'
);

SELECT ok(
  (SELECT max_properties FROM public.subscription_plans WHERE name = 'enterprise') IS NULL
    AND (SELECT max_rooms FROM public.subscription_plans WHERE name = 'enterprise') IS NULL,
  'enterprise plan has unlimited properties and rooms'
);

-- ============================================================
-- usage_counters schema: no period_start column
-- ============================================================
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'usage_counters'
      AND column_name = 'period_start'
  ),
  'usage_counters has no period_start column'
);

-- ============================================================
-- subscription_plans readable by authenticated
-- ============================================================
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claim.sub TO '11111111-1111-1111-1111-111111111102';

SELECT isnt_empty(
  $$SELECT 1 FROM public.subscription_plans$$,
  'tenant can read subscription_plans catalog'
);

-- ============================================================
-- usage_counters: no direct authenticated DML
-- ============================================================
SELECT throws_ok(
  $$INSERT INTO public.usage_counters (organization_id, metric, count)
    VALUES ('55555555-5555-5555-5555-555555555501', 'active_properties', 99)$$,
  '42501',
  NULL,
  'authenticated cannot INSERT usage_counters'
);

SELECT throws_ok(
  $$UPDATE public.usage_counters
    SET count = 99
    WHERE organization_id = '55555555-5555-5555-5555-555555555501'
      AND metric = 'active_properties'$$,
  '42501',
  NULL,
  'authenticated cannot UPDATE usage_counters'
);

SELECT throws_ok(
  $$DELETE FROM public.usage_counters
    WHERE organization_id = '55555555-5555-5555-5555-555555555501'$$,
  '42501',
  NULL,
  'authenticated cannot DELETE usage_counters'
);

-- ============================================================
-- is_feature_enabled returns false on MVP seed plans
-- ============================================================
SELECT ok(
  NOT public.is_feature_enabled('55555555-5555-5555-5555-555555555501', 'advanced_reports'),
  'is_feature_enabled returns false for advanced_reports on free plan'
);

SELECT * FROM finish();
ROLLBACK;
