-- Phase 0: Align subscription tables with approved schema (docs/03 §4.10, docs/04 §3.3)
-- Fixes max_rooms (org-wide), usage_counters PK, seed limits, manager RLS, plan sync trigger

-- ============================================================
-- subscription_plans: max_rooms_per_property → max_rooms (org-wide total)
-- ============================================================
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'subscription_plans'
      AND column_name = 'max_rooms_per_property'
  ) AND NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'subscription_plans'
      AND column_name = 'max_rooms'
  ) THEN
    ALTER TABLE public.subscription_plans
      RENAME COLUMN max_rooms_per_property TO max_rooms;
  END IF;
END $$;

ALTER TABLE public.subscription_plans
  ADD COLUMN IF NOT EXISTS max_rooms integer;

UPDATE public.subscription_plans SET name = 'free' WHERE name = 'free';
UPDATE public.subscription_plans
SET max_properties = 1, max_rooms = 20, features = '{}'::jsonb
WHERE name = 'free';

UPDATE public.subscription_plans
SET max_properties = 3, max_rooms = 50, features = '{}'::jsonb
WHERE name = 'starter';

UPDATE public.subscription_plans
SET max_properties = 10, max_rooms = 200, features = '{}'::jsonb
WHERE name = 'pro';

UPDATE public.subscription_plans
SET max_properties = NULL, max_rooms = NULL, features = '{}'::jsonb
WHERE name = 'enterprise';

-- ============================================================
-- organization_subscriptions: check constraints
-- ============================================================
ALTER TABLE public.organization_subscriptions
  DROP CONSTRAINT IF EXISTS organization_subscriptions_status_check;

ALTER TABLE public.organization_subscriptions
  ADD CONSTRAINT organization_subscriptions_status_check
  CHECK (status IN ('active', 'trialing', 'past_due', 'cancelled'));

ALTER TABLE public.organization_subscriptions
  DROP CONSTRAINT IF EXISTS organization_subscriptions_billing_cycle_check;

ALTER TABLE public.organization_subscriptions
  ADD CONSTRAINT organization_subscriptions_billing_cycle_check
  CHECK (billing_cycle IN ('monthly', 'annual'));

CREATE INDEX IF NOT EXISTS idx_organization_subscriptions_plan
  ON public.organization_subscriptions (plan_id);

-- ============================================================
-- usage_counters: remove period_start; PK (organization_id, metric)
-- ============================================================
CREATE TABLE public.usage_counters_new (
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  metric          text NOT NULL
                  CHECK (metric IN ('active_properties', 'active_rooms', 'active_tenants')),
  count           integer NOT NULL DEFAULT 0 CHECK (count >= 0),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, metric)
);

INSERT INTO public.usage_counters_new (organization_id, metric, count, updated_at)
SELECT
  organization_id,
  metric,
  MAX(count),
  MAX(updated_at)
FROM public.usage_counters
GROUP BY organization_id, metric
ON CONFLICT (organization_id, metric) DO NOTHING;

DROP TABLE public.usage_counters;

ALTER TABLE public.usage_counters_new RENAME TO usage_counters;

ALTER TABLE public.usage_counters ENABLE ROW LEVEL SECURITY;

-- Seed zeroed counters for orgs missing any metric
INSERT INTO public.usage_counters (organization_id, metric, count)
SELECT o.id, m.metric, 0
FROM public.organizations o
CROSS JOIN (
  VALUES
    ('active_properties'),
    ('active_rooms'),
    ('active_tenants')
) AS m(metric)
ON CONFLICT (organization_id, metric) DO NOTHING;

-- ============================================================
-- organizations.plan sync when subscription plan_id changes
-- ============================================================
CREATE OR REPLACE FUNCTION public.sync_organization_plan_from_subscription()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan_name text;
BEGIN
  SELECT sp.name INTO v_plan_name
  FROM public.subscription_plans sp
  WHERE sp.id = NEW.plan_id;

  IF v_plan_name IS NOT NULL THEN
    UPDATE public.organizations
    SET plan = v_plan_name, updated_at = now()
    WHERE id = NEW.organization_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_organization_plan_on_subscription ON public.organization_subscriptions;

CREATE TRIGGER sync_organization_plan_on_subscription
  AFTER INSERT OR UPDATE OF plan_id ON public.organization_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.sync_organization_plan_from_subscription();

REVOKE EXECUTE ON FUNCTION public.sync_organization_plan_from_subscription() FROM PUBLIC, anon, authenticated;

-- Backfill organizations.plan from active subscriptions
UPDATE public.organizations o
SET plan = sp.name
FROM public.organization_subscriptions os
JOIN public.subscription_plans sp ON sp.id = os.plan_id
WHERE os.organization_id = o.id
  AND os.status = 'active';

-- ============================================================
-- is_feature_enabled: align with approved schema (docs/03 §4.10.4)
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_feature_enabled(p_org_id uuid, p_feature_key text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (
      SELECT (sp.features ->> p_feature_key)::boolean
      FROM public.organization_subscriptions os
      JOIN public.subscription_plans sp ON sp.id = os.plan_id
      WHERE os.organization_id = p_org_id
        AND os.status = 'active'
    ),
    false
  );
$$;

REVOKE EXECUTE ON FUNCTION public.is_feature_enabled(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_feature_enabled(uuid, text) TO authenticated;

-- ============================================================
-- RLS: subscription tables per docs/04 §3.3 and §6.2
-- ============================================================
DROP POLICY IF EXISTS "organization_subscriptions: owner read" ON public.organization_subscriptions;
DROP POLICY IF EXISTS "usage_counters: owner read" ON public.usage_counters;

CREATE POLICY "organization_subscriptions: owners and managers read"
  ON public.organization_subscriptions FOR SELECT
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = (SELECT auth.uid())
        AND m.organization_id = organization_subscriptions.organization_id
        AND m.role = 'manager'
        AND m.deactivated_at IS NULL
    )
  );

CREATE POLICY "organization_subscriptions: owners manage"
  ON public.organization_subscriptions FOR ALL
  TO authenticated
  USING (public.is_org_owner(organization_id))
  WITH CHECK (public.is_org_owner(organization_id));

CREATE POLICY "usage_counters: owners and managers read"
  ON public.usage_counters FOR SELECT
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = (SELECT auth.uid())
        AND m.organization_id = usage_counters.organization_id
        AND m.role = 'manager'
        AND m.deactivated_at IS NULL
    )
  );

-- Owners may mutate subscriptions via RLS; plans and counters remain service-action only
REVOKE INSERT, UPDATE, DELETE ON public.subscription_plans FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.usage_counters FROM authenticated;
GRANT INSERT, UPDATE, DELETE ON public.organization_subscriptions TO authenticated;

-- user_identities: allow own update per docs/03 §4.8
DROP POLICY IF EXISTS "user_identities: own update" ON public.user_identities;

CREATE POLICY "user_identities: own update"
  ON public.user_identities FOR UPDATE
  TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));
