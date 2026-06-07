-- REC-14: Subscription plans and usage enforcement helpers
-- See docs/06-implementation-roadmap.md §5

CREATE TABLE public.subscription_plans (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name                    text NOT NULL UNIQUE,
  max_properties          integer,
  max_rooms_per_property  integer,
  features                jsonb NOT NULL DEFAULT '{}',
  created_at              timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.organization_subscriptions (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id       uuid NOT NULL UNIQUE REFERENCES public.organizations(id) ON DELETE CASCADE,
  plan_id               uuid NOT NULL REFERENCES public.subscription_plans(id),
  status                text NOT NULL DEFAULT 'active',
  billing_cycle         text NOT NULL DEFAULT 'monthly',
  current_period_start  date NOT NULL,
  current_period_end    date NOT NULL,
  trial_ends_at         timestamptz,
  cancelled_at          timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER set_updated_at_organization_subscriptions
  BEFORE UPDATE ON public.organization_subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE public.usage_counters (
  organization_id  uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  metric           text NOT NULL,
  count            integer NOT NULL DEFAULT 0,
  period_start     date NOT NULL,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, metric, period_start)
);

-- Seed plans
INSERT INTO public.subscription_plans (name, max_properties, max_rooms_per_property, features)
VALUES
  ('free', 1, 10, '{}'::jsonb),
  ('starter', 5, 50, '{}'::jsonb),
  ('pro', NULL, NULL, '{}'::jsonb),
  ('enterprise', NULL, NULL, '{"custom_limits": true}'::jsonb);

-- Backfill existing organizations onto free plan
INSERT INTO public.organization_subscriptions (
  organization_id,
  plan_id,
  current_period_start,
  current_period_end
)
SELECT
  o.id,
  (SELECT id FROM public.subscription_plans WHERE name = 'free'),
  date_trunc('month', CURRENT_DATE)::date,
  (date_trunc('month', CURRENT_DATE) + interval '1 month' - interval '1 day')::date
FROM public.organizations o
ON CONFLICT (organization_id) DO NOTHING;

ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usage_counters ENABLE ROW LEVEL SECURITY;

CREATE POLICY "subscription_plans: authenticated read"
  ON public.subscription_plans FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "organization_subscriptions: owner read"
  ON public.organization_subscriptions FOR SELECT
  TO authenticated
  USING (public.is_org_owner(organization_id));

CREATE POLICY "usage_counters: owner read"
  ON public.usage_counters FOR SELECT
  TO authenticated
  USING (public.is_org_owner(organization_id));

REVOKE INSERT, UPDATE, DELETE ON public.subscription_plans FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.organization_subscriptions FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.usage_counters FROM authenticated;

-- ============================================================
-- Helpers (enforced in Server Actions, not RLS)
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_feature_enabled(
  p_org_id uuid,
  p_feature_key text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_features jsonb;
BEGIN
  SELECT sp.features
  INTO v_features
  FROM public.organization_subscriptions os
  JOIN public.subscription_plans sp ON sp.id = os.plan_id
  WHERE os.organization_id = p_org_id
    AND os.status = 'active'
    AND (os.cancelled_at IS NULL OR os.cancelled_at > now());

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  RETURN COALESCE((v_features ->> p_feature_key)::boolean, false);
END;
$$;

CREATE OR REPLACE FUNCTION public.check_property_limit(p_org_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max_properties integer;
  v_current_count integer;
BEGIN
  SELECT sp.max_properties
  INTO v_max_properties
  FROM public.organization_subscriptions os
  JOIN public.subscription_plans sp ON sp.id = os.plan_id
  WHERE os.organization_id = p_org_id
    AND os.status = 'active'
    AND (os.cancelled_at IS NULL OR os.cancelled_at > now());

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  IF v_max_properties IS NULL THEN
    RETURN true;
  END IF;

  SELECT count(*)::integer
  INTO v_current_count
  FROM public.properties p
  WHERE p.organization_id = p_org_id
    AND p.archived_at IS NULL
    AND p.status <> 'archived';

  RETURN v_current_count < v_max_properties;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.is_feature_enabled(uuid, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.check_property_limit(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_feature_enabled(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_property_limit(uuid) TO authenticated;
