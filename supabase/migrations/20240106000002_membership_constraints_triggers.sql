-- Phase 0C: Membership constraints, integrity triggers, denormalization sync
-- See docs/03-database-schema.md §4.4, §7

-- ============================================================
-- Verify backfill before enforcing NOT NULL
-- ============================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.billing_periods WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'Backfill incomplete: billing_periods.organization_id has NULL rows';
  END IF;
  IF EXISTS (SELECT 1 FROM public.meter_readings WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'Backfill incomplete: meter_readings.organization_id has NULL rows';
  END IF;
  IF EXISTS (SELECT 1 FROM public.housekeeping_tasks WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'Backfill incomplete: housekeeping_tasks.organization_id has NULL rows';
  END IF;
  IF EXISTS (SELECT 1 FROM public.bills)
     AND EXISTS (SELECT 1 FROM public.bills WHERE tenant_profile_id IS NULL) THEN
    RAISE EXCEPTION 'Backfill incomplete: bills.tenant_profile_id has NULL rows';
  END IF;
END $$;

-- ============================================================
-- Partial unique indexes on memberships (C-1)
-- ============================================================
CREATE UNIQUE INDEX memberships_owner_unique
  ON public.memberships (user_id, organization_id)
  WHERE role = 'owner' AND property_id IS NULL AND deactivated_at IS NULL;

CREATE UNIQUE INDEX memberships_property_role_unique
  ON public.memberships (user_id, organization_id, property_id, role)
  WHERE property_id IS NOT NULL AND deactivated_at IS NULL;

-- ============================================================
-- Enforce NOT NULL on denormalized columns
-- ============================================================
ALTER TABLE public.billing_periods
  ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE public.meter_readings
  ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE public.housekeeping_tasks
  ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE public.bills
  ALTER COLUMN tenant_profile_id SET NOT NULL;

-- ============================================================
-- Membership integrity triggers (C-2, C-3)
-- ============================================================
CREATE OR REPLACE FUNCTION public.validate_membership_org_consistency()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.property_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.properties p
      WHERE p.id = NEW.property_id
        AND p.organization_id = NEW.organization_id
    ) THEN
      RAISE EXCEPTION 'property_id does not belong to organization_id';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER memberships_org_consistency
  BEFORE INSERT OR UPDATE ON public.memberships
  FOR EACH ROW EXECUTE FUNCTION public.validate_membership_org_consistency();

CREATE OR REPLACE FUNCTION public.prevent_owner_orphan()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.deactivated_at IS NOT NULL AND NEW.role = 'owner' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.memberships
      WHERE organization_id = NEW.organization_id
        AND role = 'owner'
        AND property_id IS NULL
        AND deactivated_at IS NULL
        AND id <> NEW.id
    ) THEN
      RAISE EXCEPTION 'cannot deactivate the last owner of an organization';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER memberships_prevent_owner_orphan
  BEFORE UPDATE OF deactivated_at ON public.memberships
  FOR EACH ROW EXECUTE FUNCTION public.prevent_owner_orphan();

CREATE OR REPLACE FUNCTION public.validate_invitation_org_consistency()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.property_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1
      FROM public.properties p
      WHERE p.id = NEW.property_id
        AND p.organization_id = NEW.organization_id
    ) THEN
      RAISE EXCEPTION 'invitation property_id does not belong to organization_id';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER invitations_org_consistency
  BEFORE INSERT OR UPDATE ON public.invitations
  FOR EACH ROW EXECUTE FUNCTION public.validate_invitation_org_consistency();

REVOKE EXECUTE ON FUNCTION public.validate_membership_org_consistency() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.prevent_owner_orphan() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.validate_invitation_org_consistency() FROM PUBLIC, anon, authenticated;

-- ============================================================
-- Denormalization sync triggers for organization_id
-- ============================================================
CREATE OR REPLACE FUNCTION public.sync_billing_period_organization_id()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  SELECT p.organization_id INTO NEW.organization_id
  FROM public.properties p
  WHERE p.id = NEW.property_id;
  IF NEW.organization_id IS NULL THEN
    RAISE EXCEPTION 'property_id % does not exist', NEW.property_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER sync_billing_period_organization_before_insert_update
  BEFORE INSERT OR UPDATE OF property_id ON public.billing_periods
  FOR EACH ROW EXECUTE FUNCTION public.sync_billing_period_organization_id();

CREATE OR REPLACE FUNCTION public.sync_meter_reading_organization_id()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  SELECT p.organization_id INTO NEW.organization_id
  FROM public.properties p
  WHERE p.id = NEW.property_id;
  IF NEW.organization_id IS NULL THEN
    RAISE EXCEPTION 'property_id % does not exist', NEW.property_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER sync_meter_reading_organization_before_insert_update
  BEFORE INSERT OR UPDATE OF property_id ON public.meter_readings
  FOR EACH ROW EXECUTE FUNCTION public.sync_meter_reading_organization_id();

CREATE OR REPLACE FUNCTION public.sync_housekeeping_task_organization_id()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  SELECT p.organization_id INTO NEW.organization_id
  FROM public.properties p
  WHERE p.id = NEW.property_id;
  IF NEW.organization_id IS NULL THEN
    RAISE EXCEPTION 'property_id % does not exist', NEW.property_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER sync_housekeeping_task_organization_before_insert_update
  BEFORE INSERT OR UPDATE OF property_id ON public.housekeeping_tasks
  FOR EACH ROW EXECUTE FUNCTION public.sync_housekeeping_task_organization_id();

CREATE OR REPLACE FUNCTION public.sync_tenant_profile_organization_id()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  SELECT p.organization_id INTO NEW.organization_id
  FROM public.properties p
  WHERE p.id = NEW.property_id;
  IF NEW.organization_id IS NULL THEN
    RAISE EXCEPTION 'property_id % does not exist', NEW.property_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER sync_tenant_profile_organization_before_insert_update
  BEFORE INSERT OR UPDATE OF property_id ON public.tenant_profiles
  FOR EACH ROW EXECUTE FUNCTION public.sync_tenant_profile_organization_id();

REVOKE EXECUTE ON FUNCTION public.sync_billing_period_organization_id() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sync_meter_reading_organization_id() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sync_housekeeping_task_organization_id() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sync_tenant_profile_organization_id() FROM PUBLIC, anon, authenticated;

-- ============================================================
-- Room status sync from tenant_profiles (replaces tenants trigger later)
-- ============================================================
CREATE TRIGGER sync_room_on_tenant_profile_lease_change
  AFTER INSERT OR UPDATE OF lease_status ON public.tenant_profiles
  FOR EACH ROW EXECUTE FUNCTION public.sync_room_status();

-- ============================================================
-- pg_cron: archive old invitations (weekly Sunday 03:00 UTC)
-- ============================================================
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'archive-old-invitations';

SELECT cron.schedule(
  'archive-old-invitations',
  '0 3 * * 0',
  $$
    WITH moved AS (
      DELETE FROM public.invitations
      WHERE status IN ('accepted', 'expired')
        AND created_at < now() - interval '90 days'
      RETURNING *
    )
    INSERT INTO public.invitations_archive
    SELECT * FROM moved;
  $$
);
