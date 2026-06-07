-- Phase 0 foundation corrective migration
-- Reconciles prototype migrations with approved schema (docs/03, docs/04, docs/06)

-- ============================================================
-- notification_delivery_status: add 'skipped' per approved schema
-- ============================================================
ALTER TYPE public.notification_delivery_status ADD VALUE IF NOT EXISTS 'skipped';

-- ============================================================
-- user_identities: align with approved schema
-- ============================================================
ALTER TABLE public.user_identities
  ADD COLUMN IF NOT EXISTS linked_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_login_at timestamptz,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz;

UPDATE public.user_identities
SET
  linked_at = COALESCE(linked_at, created_at, now()),
  updated_at = COALESCE(updated_at, created_at, now())
WHERE linked_at IS NULL OR updated_at IS NULL;

ALTER TABLE public.user_identities
  ALTER COLUMN linked_at SET NOT NULL,
  ALTER COLUMN linked_at SET DEFAULT now(),
  ALTER COLUMN updated_at SET NOT NULL,
  ALTER COLUMN updated_at SET DEFAULT now();

ALTER TABLE public.user_identities
  DROP COLUMN IF EXISTS created_at;

ALTER TABLE public.user_identities
  DROP CONSTRAINT IF EXISTS user_identities_provider_check;

ALTER TABLE public.user_identities
  ADD CONSTRAINT user_identities_provider_check
  CHECK (provider IN ('email', 'line', 'google', 'apple'));

ALTER TABLE public.user_identities
  DROP CONSTRAINT IF EXISTS user_identities_user_id_fkey;

ALTER TABLE public.user_identities
  ADD CONSTRAINT user_identities_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

DROP TRIGGER IF EXISTS set_updated_at_user_identities ON public.user_identities;

CREATE TRIGGER set_updated_at_user_identities
  BEFORE UPDATE ON public.user_identities
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE POLICY "user_identities: owner read org members"
  ON public.user_identities FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = user_identities.user_id
        AND m.deactivated_at IS NULL
        AND public.is_org_owner(m.organization_id)
    )
  );

-- ============================================================
-- notifications: align with approved schema
-- ============================================================
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id),
  ADD COLUMN IF NOT EXISTS event_type text,
  ADD COLUMN IF NOT EXISTS metadata jsonb;

UPDATE public.notifications
SET
  event_type = COALESCE(event_type, type::text),
  metadata = COALESCE(metadata, data),
  read_at = CASE
    WHEN read_at IS NULL AND is_read = true THEN created_at
    ELSE read_at
  END
WHERE event_type IS NULL OR metadata IS NULL OR (read_at IS NULL AND is_read = true);

UPDATE public.notifications n
SET organization_id = sub.organization_id
FROM (
  SELECT DISTINCT ON (m.user_id)
    m.user_id,
    m.organization_id
  FROM public.memberships m
  WHERE m.deactivated_at IS NULL
  ORDER BY m.user_id, m.created_at
) sub
WHERE n.user_id = sub.user_id
  AND n.organization_id IS NULL;

DELETE FROM public.notifications WHERE organization_id IS NULL;

ALTER TABLE public.notifications
  ALTER COLUMN event_type SET NOT NULL,
  ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE public.notifications
  ALTER COLUMN body DROP NOT NULL;

ALTER TABLE public.notifications
  DROP COLUMN IF EXISTS is_read,
  DROP COLUMN IF EXISTS type,
  DROP COLUMN IF EXISTS data;

ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_user_id_fkey;

ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_notifications_user_created
  ON public.notifications (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_organization_id
  ON public.notifications (organization_id);

-- notifications_archive: match live notifications shape
DROP TABLE IF EXISTS public.notifications_archive;

CREATE TABLE public.notifications_archive (
  LIKE public.notifications INCLUDING ALL
);

ALTER TABLE public.notifications_archive
  ADD COLUMN archived_at timestamptz NOT NULL DEFAULT now();

CREATE INDEX idx_notifications_archive_user_id
  ON public.notifications_archive (user_id, created_at DESC);

ALTER TABLE public.notifications_archive ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.notifications_archive IS
  'Archive of old notifications. Written by pg_cron; no client policies.';

-- notification_deliveries: add error column per schema
ALTER TABLE public.notification_deliveries
  ADD COLUMN IF NOT EXISTS error text;

-- ============================================================
-- buildings.organization_id: enforce NOT NULL + sync trigger
-- ============================================================
UPDATE public.buildings b
SET organization_id = p.organization_id
FROM public.properties p
WHERE p.id = b.property_id
  AND b.organization_id IS NULL;

ALTER TABLE public.buildings
  ALTER COLUMN organization_id SET NOT NULL;

CREATE OR REPLACE FUNCTION public.sync_building_organization_id()
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

DROP TRIGGER IF EXISTS sync_building_organization_before_insert_update ON public.buildings;

CREATE TRIGGER sync_building_organization_before_insert_update
  BEFORE INSERT OR UPDATE OF property_id ON public.buildings
  FOR EACH ROW EXECUTE FUNCTION public.sync_building_organization_id();

REVOKE EXECUTE ON FUNCTION public.sync_building_organization_id() FROM PUBLIC, anon, authenticated;

-- ============================================================
-- Partial unique index on pending invitations
-- ============================================================
CREATE UNIQUE INDEX IF NOT EXISTS invitations_pending_unique
  ON public.invitations (
    organization_id,
    lower(email::text),
    role,
    COALESCE(property_id, '00000000-0000-0000-0000-000000000000'::uuid)
  )
  WHERE status = 'pending';

-- ============================================================
-- organizations RLS: only owners and managers may read org profile
-- ============================================================
DROP POLICY IF EXISTS "organizations: member read" ON public.organizations;

CREATE POLICY "organizations: owner manager read"
  ON public.organizations FOR SELECT
  TO authenticated
  USING (
    public.is_org_owner(id)
    OR EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.organization_id = organizations.id
        AND m.user_id = (SELECT auth.uid())
        AND m.role = 'manager'
        AND m.deactivated_at IS NULL
    )
  );

-- ============================================================
-- profiles: owners may read org member profiles
-- ============================================================
CREATE POLICY "profiles: owner read org members"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = profiles.id
        AND m.deactivated_at IS NULL
        AND public.is_org_owner(m.organization_id)
    )
  );

-- ============================================================
-- archived_at: non-owner/manager reads exclude archived rows
-- ============================================================
DROP POLICY IF EXISTS "properties: members view accessible" ON public.properties;

CREATE POLICY "properties: members view accessible"
  ON public.properties FOR SELECT
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR public.has_property_role(id, 'manager')
    OR (
      archived_at IS NULL
      AND status <> 'archived'
      AND EXISTS (
        SELECT 1
        FROM public.memberships m
        WHERE m.user_id = (SELECT auth.uid())
          AND m.property_id = properties.id
          AND m.deactivated_at IS NULL
      )
    )
  );

DROP POLICY IF EXISTS "buildings: members read" ON public.buildings;

CREATE POLICY "buildings: members read"
  ON public.buildings FOR SELECT
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
    OR (
      archived_at IS NULL
      AND EXISTS (
        SELECT 1
        FROM public.memberships m
        WHERE m.user_id = (SELECT auth.uid())
          AND m.property_id = buildings.property_id
          AND m.deactivated_at IS NULL
      )
    )
  );

DROP POLICY IF EXISTS "rooms: members view scoped" ON public.rooms;

CREATE POLICY "rooms: members view scoped"
  ON public.rooms FOR SELECT
  TO authenticated
  USING (
    public.is_org_owner(
      (SELECT p.organization_id FROM public.properties p WHERE p.id = property_id)
    )
    OR public.has_property_role(property_id, 'manager')
    OR (
      archived_at IS NULL
      AND (
        EXISTS (
          SELECT 1
          FROM public.memberships m
          WHERE m.user_id = (SELECT auth.uid())
            AND m.property_id = rooms.property_id
            AND m.deactivated_at IS NULL
        )
        OR EXISTS (
          SELECT 1
          FROM public.tenant_profiles tp
          WHERE tp.user_id = (SELECT auth.uid())
            AND tp.room_id = rooms.id
            AND tp.lease_status = 'active'
            AND tp.archived_at IS NULL
        )
        OR EXISTS (
          SELECT 1
          FROM public.maintenance_tickets mt
          WHERE mt.room_id = rooms.id
            AND mt.assigned_to = (SELECT auth.uid())
            AND mt.status NOT IN ('closed')
            AND mt.archived_at IS NULL
        )
        OR EXISTS (
          SELECT 1
          FROM public.housekeeping_tasks ht
          WHERE ht.room_id = rooms.id
            AND ht.assigned_to = (SELECT auth.uid())
            AND ht.status IN ('pending', 'in_progress')
            AND ht.archived_at IS NULL
        )
      )
    )
  );

DROP POLICY IF EXISTS "tenant_profiles: scoped select" ON public.tenant_profiles;

CREATE POLICY "tenant_profiles: scoped select"
  ON public.tenant_profiles FOR SELECT
  TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  );

DROP POLICY IF EXISTS "bills: tenant read own" ON public.bills;

CREATE POLICY "bills: tenant read own"
  ON public.bills FOR SELECT
  TO authenticated
  USING (
    archived_at IS NULL
    AND EXISTS (
      SELECT 1
      FROM public.tenant_profiles tp
      WHERE tp.id = bills.tenant_profile_id
        AND tp.user_id = (SELECT auth.uid())
        AND tp.archived_at IS NULL
    )
  );

DROP POLICY IF EXISTS "tasks: housekeeper read assigned" ON public.housekeeping_tasks;
DROP POLICY IF EXISTS "tasks: housekeeper update assigned" ON public.housekeeping_tasks;

CREATE POLICY "tasks: housekeeper read assigned"
  ON public.housekeeping_tasks FOR SELECT
  TO authenticated
  USING (
    archived_at IS NULL
    AND assigned_to = (SELECT auth.uid())
    AND public.has_property_role(property_id, 'housekeeper')
  );

CREATE POLICY "tasks: housekeeper update assigned"
  ON public.housekeeping_tasks FOR UPDATE
  TO authenticated
  USING (
    archived_at IS NULL
    AND assigned_to = (SELECT auth.uid())
    AND public.has_property_role(property_id, 'housekeeper')
  )
  WITH CHECK (
    archived_at IS NULL
    AND assigned_to = (SELECT auth.uid())
    AND public.has_property_role(property_id, 'housekeeper')
  );

-- audit_logs: revoke direct authenticated INSERT (use record_audit_event only)
REVOKE INSERT ON public.audit_logs FROM authenticated;

-- ============================================================
-- pg_cron: dedupe and align archival jobs with approved schema
-- ============================================================
SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname IN (
  'archive-old-invitations',
  'archive-old-notifications',
  'archive-old-notifications-weekly',
  'archive-old-audit-logs'
);

SELECT cron.schedule(
  'archive-old-invitations',
  '0 3 * * 0',
  $$
    WITH moved AS (
      DELETE FROM public.invitations
      WHERE status IN ('accepted', 'expired', 'revoked')
        AND created_at < now() - interval '90 days'
      RETURNING *
    )
    INSERT INTO public.invitations_archive
    SELECT * FROM moved
    ON CONFLICT (id) DO NOTHING;
  $$
);

SELECT cron.schedule(
  'archive-old-notifications',
  '0 4 * * 0',
  $$
    WITH moved AS (
      DELETE FROM public.notifications
      WHERE read_at IS NOT NULL
        AND created_at < now() - interval '90 days'
      RETURNING *
    )
    INSERT INTO public.notifications_archive (
      id,
      organization_id,
      user_id,
      event_type,
      title,
      body,
      metadata,
      read_at,
      created_at,
      archived_at
    )
    SELECT
      id,
      organization_id,
      user_id,
      event_type,
      title,
      body,
      metadata,
      read_at,
      created_at,
      now()
    FROM moved
    ON CONFLICT (id) DO NOTHING;
  $$
);

SELECT cron.schedule(
  'archive-old-audit-logs',
  '0 5 * * 0',
  $$
    WITH moved AS (
      DELETE FROM public.audit_logs
      WHERE created_at < now() - interval '180 days'
      RETURNING *
    )
    INSERT INTO public.audit_logs_archive
      (id, actor_id, organization_id, property_id, event_type, metadata, created_at)
    SELECT id, actor_id, organization_id, property_id, event_type, metadata, created_at
    FROM moved
    ON CONFLICT (id) DO NOTHING;
  $$
);
