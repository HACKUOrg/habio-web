-- Phase 0C: Multi-property constraints, denormalization triggers, RLS
-- See docs/09-multi-property.md §10 Phase C and docs/04-rbac.md

-- ============================================================
-- Verify backfill completed before enforcing NOT NULL
-- ============================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.properties WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'Backfill incomplete: properties.organization_id has NULL rows';
  END IF;
  IF EXISTS (SELECT 1 FROM public.rooms WHERE building_id IS NULL) THEN
    RAISE EXCEPTION 'Backfill incomplete: rooms.building_id has NULL rows';
  END IF;
  IF EXISTS (SELECT 1 FROM public.bills WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'Backfill incomplete: bills.organization_id has NULL rows';
  END IF;
  IF EXISTS (SELECT 1 FROM public.maintenance_tickets WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'Backfill incomplete: maintenance_tickets.organization_id has NULL rows';
  END IF;
END $$;

-- ============================================================
-- Enforce NOT NULL constraints
-- ============================================================
ALTER TABLE public.properties
  ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE public.rooms
  ALTER COLUMN building_id SET NOT NULL;

ALTER TABLE public.bills
  ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE public.maintenance_tickets
  ALTER COLUMN organization_id SET NOT NULL;

-- Room numbers unique per building, not per property
ALTER TABLE public.rooms
  DROP CONSTRAINT IF EXISTS rooms_property_id_room_number_key;

ALTER TABLE public.rooms
  ADD CONSTRAINT rooms_building_id_room_number_key UNIQUE (building_id, room_number);

-- ============================================================
-- Denormalization sync triggers
-- ============================================================
CREATE OR REPLACE FUNCTION public.sync_room_property_from_building()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.building_id IS NOT NULL THEN
    SELECT b.property_id INTO NEW.property_id
    FROM public.buildings b
    WHERE b.id = NEW.building_id;
    IF NEW.property_id IS NULL THEN
      RAISE EXCEPTION 'building_id % does not exist', NEW.building_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER sync_room_property_before_insert_update
  BEFORE INSERT OR UPDATE OF building_id ON public.rooms
  FOR EACH ROW EXECUTE FUNCTION public.sync_room_property_from_building();

CREATE OR REPLACE FUNCTION public.sync_bill_organization_id()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp
AS $$
BEGIN
  SELECT p.organization_id INTO NEW.organization_id
  FROM public.properties p
  WHERE p.id = NEW.property_id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER sync_bill_organization_before_insert_update
  BEFORE INSERT OR UPDATE OF property_id ON public.bills
  FOR EACH ROW EXECUTE FUNCTION public.sync_bill_organization_id();

CREATE OR REPLACE FUNCTION public.sync_ticket_organization_id()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp
AS $$
BEGIN
  SELECT p.organization_id INTO NEW.organization_id
  FROM public.properties p
  WHERE p.id = NEW.property_id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER sync_ticket_organization_before_insert_update
  BEFORE INSERT OR UPDATE OF property_id ON public.maintenance_tickets
  FOR EACH ROW EXECUTE FUNCTION public.sync_ticket_organization_id();

CREATE OR REPLACE FUNCTION public.sync_meter_reading_property_id()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp
AS $$
BEGIN
  SELECT bp.property_id INTO NEW.property_id
  FROM public.billing_periods bp
  WHERE bp.id = NEW.billing_period_id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER sync_meter_reading_property_before_insert_update
  BEFORE INSERT OR UPDATE OF billing_period_id ON public.meter_readings
  FOR EACH ROW EXECUTE FUNCTION public.sync_meter_reading_property_id();

-- ============================================================
-- RLS helper functions (extended for multi-property)
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_organization_admin(p_org_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.organization_members
    WHERE organization_id = p_org_id
      AND user_id = (SELECT auth.uid())
      AND scope IN ('owner', 'admin')
  )
$$;

CREATE OR REPLACE FUNCTION public.is_organization_viewer(p_org_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.organization_members
    WHERE organization_id = p_org_id
      AND user_id = (SELECT auth.uid())
      AND scope = 'viewer'
  )
$$;

CREATE OR REPLACE FUNCTION public.is_property_manager(p_property_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.properties p
    WHERE p.id = p_property_id
      AND (
        p.manager_id = (SELECT auth.uid())
        OR public.is_organization_admin(p.organization_id)
      )
  )
$$;

CREATE OR REPLACE FUNCTION public.is_property_staff(p_property_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.property_staff
    WHERE property_id = p_property_id
      AND user_id = (SELECT auth.uid())
  )
$$;

CREATE OR REPLACE FUNCTION public.get_managed_property_ids()
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT p.id FROM public.properties p
  WHERE p.manager_id = (SELECT auth.uid())
     OR p.organization_id IN (
       SELECT organization_id
       FROM public.organization_members
       WHERE user_id = (SELECT auth.uid())
         AND scope IN ('owner', 'admin')
     )
$$;

-- ============================================================
-- Security: revoke helper EXECUTE from anon; tighten anon DML
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.is_organization_admin(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_organization_viewer(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_property_staff(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_managed_property_ids() FROM PUBLIC, anon;

REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM anon;

-- ============================================================
-- Update existing RLS policies
-- ============================================================

-- profiles: manager read property members (include property_staff)
DROP POLICY IF EXISTS "profiles: manager read property members" ON public.profiles;
CREATE POLICY "profiles: manager read property members"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (
    (SELECT public.current_user_role()) = 'manager' AND
    (
      EXISTS (
        SELECT 1 FROM public.properties p
        LEFT JOIN public.tenants t ON t.property_id = p.id
        WHERE public.is_property_manager(p.id)
          AND (t.user_id = profiles.id OR profiles.id = (SELECT auth.uid()))
      ) OR
      EXISTS (
        SELECT 1 FROM public.property_staff ps
        WHERE public.is_property_manager(ps.property_id)
          AND ps.user_id = profiles.id
      )
    )
  );

-- properties: split manager FOR ALL into separate policies
DROP POLICY IF EXISTS "properties: manager full access" ON public.properties;

CREATE POLICY "properties: manager read"
  ON public.properties FOR SELECT
  TO authenticated
  USING (public.is_property_manager(id));

CREATE POLICY "properties: manager update"
  ON public.properties FOR UPDATE
  TO authenticated
  USING (public.is_property_manager(id))
  WITH CHECK (public.is_property_manager(id));

CREATE POLICY "properties: manager delete"
  ON public.properties FOR DELETE
  TO authenticated
  USING (public.is_property_manager(id));

CREATE POLICY "properties: manager insert"
  ON public.properties FOR INSERT
  TO authenticated
  WITH CHECK (
    manager_id = (SELECT auth.uid()) AND
    EXISTS (
      SELECT 1 FROM public.organization_members
      WHERE organization_id = properties.organization_id
        AND user_id = (SELECT auth.uid())
        AND scope IN ('owner', 'admin')
    )
  );

DROP POLICY IF EXISTS "properties: members read" ON public.properties;
CREATE POLICY "properties: members read"
  ON public.properties FOR SELECT
  TO authenticated
  USING (
    public.is_property_tenant(id) OR
    public.is_property_staff(id)
  );

CREATE POLICY "properties: org viewer read"
  ON public.properties FOR SELECT
  TO authenticated
  USING (public.is_organization_viewer(organization_id));

-- rooms: org viewer read
CREATE POLICY "rooms: org viewer read"
  ON public.rooms FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.properties p
      WHERE p.id = rooms.property_id
        AND public.is_organization_viewer(p.organization_id)
    )
  );

-- bills: org viewer read
CREATE POLICY "bills: org viewer read"
  ON public.bills FOR SELECT
  TO authenticated
  USING (public.is_organization_viewer(organization_id));

-- maintenance_tickets: org viewer read + staff-scoped technician policies
CREATE POLICY "tickets: org viewer read"
  ON public.maintenance_tickets FOR SELECT
  TO authenticated
  USING (public.is_organization_viewer(organization_id));

DROP POLICY IF EXISTS "tickets: technician reads and updates assigned" ON public.maintenance_tickets;
CREATE POLICY "tickets: technician reads assigned"
  ON public.maintenance_tickets FOR SELECT
  TO authenticated
  USING (
    assigned_to = (SELECT auth.uid()) AND
    public.is_property_staff(property_id)
  );

DROP POLICY IF EXISTS "tickets: technician updates assigned" ON public.maintenance_tickets;
CREATE POLICY "tickets: technician updates assigned"
  ON public.maintenance_tickets FOR UPDATE
  TO authenticated
  USING (
    assigned_to = (SELECT auth.uid()) AND
    public.is_property_staff(property_id)
  )
  WITH CHECK (
    assigned_to = (SELECT auth.uid()) AND
    public.is_property_staff(property_id)
  );

-- housekeeping_tasks: staff-scoped housekeeper policies
DROP POLICY IF EXISTS "tasks: housekeeper reads assigned" ON public.housekeeping_tasks;
CREATE POLICY "tasks: housekeeper reads assigned"
  ON public.housekeeping_tasks FOR SELECT
  TO authenticated
  USING (
    assigned_to = (SELECT auth.uid()) AND
    public.is_property_staff(property_id)
  );

DROP POLICY IF EXISTS "tasks: housekeeper updates assigned" ON public.housekeeping_tasks;
CREATE POLICY "tasks: housekeeper updates assigned"
  ON public.housekeeping_tasks FOR UPDATE
  TO authenticated
  USING (
    assigned_to = (SELECT auth.uid()) AND
    public.is_property_staff(property_id)
  )
  WITH CHECK (
    assigned_to = (SELECT auth.uid()) AND
    public.is_property_staff(property_id)
  );

-- ============================================================
-- RLS for new tables
-- ============================================================

-- organizations
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "organizations: admin full access"
  ON public.organizations FOR ALL
  TO authenticated
  USING (public.is_organization_admin(id))
  WITH CHECK (public.is_organization_admin(id));

CREATE POLICY "organizations: manager create"
  ON public.organizations FOR INSERT
  TO authenticated
  WITH CHECK ((SELECT public.current_user_role()) = 'manager');

CREATE POLICY "organizations: member read"
  ON public.organizations FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members
      WHERE organization_id = organizations.id
        AND user_id = (SELECT auth.uid())
    )
  );

-- organization_members
ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_members: owner full access"
  ON public.organization_members FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = organization_members.organization_id
        AND om.user_id = (SELECT auth.uid())
        AND om.scope = 'owner'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = organization_members.organization_id
        AND om.user_id = (SELECT auth.uid())
        AND om.scope = 'owner'
    )
  );

CREATE POLICY "org_members: read own"
  ON public.organization_members FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- buildings
ALTER TABLE public.buildings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "buildings: manager full access"
  ON public.buildings FOR ALL
  TO authenticated
  USING (public.is_property_manager(property_id))
  WITH CHECK (public.is_property_manager(property_id));

CREATE POLICY "buildings: members read"
  ON public.buildings FOR SELECT
  TO authenticated
  USING (
    public.is_property_tenant(property_id) OR
    public.is_property_staff(property_id) OR
    EXISTS (
      SELECT 1 FROM public.maintenance_tickets
      WHERE property_id = buildings.property_id
        AND assigned_to = (SELECT auth.uid())
    )
  );

-- billing_periods
ALTER TABLE public.billing_periods ENABLE ROW LEVEL SECURITY;

CREATE POLICY "billing_periods: manager full access"
  ON public.billing_periods FOR ALL
  TO authenticated
  USING (public.is_property_manager(property_id))
  WITH CHECK (public.is_property_manager(property_id));

CREATE POLICY "billing_periods: housekeeper read"
  ON public.billing_periods FOR SELECT
  TO authenticated
  USING (
    public.is_property_staff(property_id) AND
    status = 'open'
  );

-- meter_readings
ALTER TABLE public.meter_readings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "meter_readings: manager full access"
  ON public.meter_readings FOR ALL
  TO authenticated
  USING (public.is_property_manager(property_id))
  WITH CHECK (
    public.is_property_manager(property_id) AND
    EXISTS (
      SELECT 1 FROM public.billing_periods bp
      WHERE bp.id = meter_readings.billing_period_id
        AND bp.status = 'open'
    )
  );

CREATE POLICY "meter_readings: housekeeper submit"
  ON public.meter_readings FOR INSERT
  TO authenticated
  WITH CHECK (
    submitted_by = (SELECT auth.uid()) AND
    public.is_property_staff(property_id) AND
    EXISTS (
      SELECT 1 FROM public.billing_periods bp
      WHERE bp.id = meter_readings.billing_period_id
        AND bp.status = 'open'
    )
  );

CREATE POLICY "meter_readings: housekeeper update own"
  ON public.meter_readings FOR UPDATE
  TO authenticated
  USING (
    submitted_by = (SELECT auth.uid()) AND
    status IN ('pending', 'submitted', 'rejected')
  )
  WITH CHECK (
    submitted_by = (SELECT auth.uid()) AND
    status IN ('pending', 'submitted') AND
    public.is_property_staff(property_id) AND
    EXISTS (
      SELECT 1 FROM public.billing_periods bp
      WHERE bp.id = meter_readings.billing_period_id
        AND bp.status = 'open'
    )
  );

CREATE POLICY "meter_readings: housekeeper read"
  ON public.meter_readings FOR SELECT
  TO authenticated
  USING (public.is_property_staff(property_id));
