-- Phase 0D: Membership-based RLS helpers and policies
-- See docs/04-rbac.md §6

-- ============================================================
-- Helper functions
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_org_owner(p_org_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.memberships m
    WHERE m.user_id = (SELECT auth.uid())
      AND m.organization_id = p_org_id
      AND m.property_id IS NULL
      AND m.role = 'owner'
      AND m.deactivated_at IS NULL
  );
$$;

CREATE OR REPLACE FUNCTION public.has_property_role(
  p_property_id uuid,
  p_role public.membership_role
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.memberships m
    WHERE m.user_id = (SELECT auth.uid())
      AND m.property_id = p_property_id
      AND m.role = p_role
      AND m.deactivated_at IS NULL
  );
$$;

CREATE OR REPLACE FUNCTION public.can_access_property(p_property_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.properties p
    WHERE p.id = p_property_id
      AND (
        public.is_org_owner(p.organization_id)
        OR EXISTS (
          SELECT 1
          FROM public.memberships m
          WHERE m.user_id = (SELECT auth.uid())
            AND m.property_id = p_property_id
            AND m.deactivated_at IS NULL
        )
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_property(p_property_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.properties p
    WHERE p.id = p_property_id
      AND (
        public.is_org_owner(p.organization_id)
        OR public.has_property_role(p_property_id, 'manager')
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.is_staff_role(p_role public.membership_role)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT p_role IN ('owner', 'manager', 'technician', 'housekeeper');
$$;

REVOKE EXECUTE ON FUNCTION public.is_org_owner(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.has_property_role(uuid, public.membership_role) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.can_access_property(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.can_manage_property(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_staff_role(public.membership_role) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.is_org_owner(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_property_role(uuid, public.membership_role) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_property(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_property(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_staff_role(public.membership_role) TO authenticated;

-- ============================================================
-- Drop legacy policies (old role / organization_members model)
-- ============================================================
DROP POLICY IF EXISTS "profiles: manager read property members" ON public.profiles;
DROP POLICY IF EXISTS "properties: manager full access" ON public.properties;
DROP POLICY IF EXISTS "properties: manager read" ON public.properties;
DROP POLICY IF EXISTS "properties: manager update" ON public.properties;
DROP POLICY IF EXISTS "properties: manager delete" ON public.properties;
DROP POLICY IF EXISTS "properties: manager insert" ON public.properties;
DROP POLICY IF EXISTS "properties: members read" ON public.properties;
DROP POLICY IF EXISTS "properties: org viewer read" ON public.properties;
DROP POLICY IF EXISTS "rooms: manager full access" ON public.rooms;
DROP POLICY IF EXISTS "rooms: tenant reads own room" ON public.rooms;
DROP POLICY IF EXISTS "rooms: technician reads assigned rooms" ON public.rooms;
DROP POLICY IF EXISTS "rooms: housekeeper reads assigned rooms" ON public.rooms;
DROP POLICY IF EXISTS "rooms: org viewer read" ON public.rooms;
DROP POLICY IF EXISTS "tenants: manager full access" ON public.tenants;
DROP POLICY IF EXISTS "tenants: read own record" ON public.tenants;
DROP POLICY IF EXISTS "bills: manager full access" ON public.bills;
DROP POLICY IF EXISTS "bills: tenant reads own bills" ON public.bills;
DROP POLICY IF EXISTS "bills: org viewer read" ON public.bills;
DROP POLICY IF EXISTS "bill_line_items: inherit bill access" ON public.bill_line_items;
DROP POLICY IF EXISTS "tickets: manager full access" ON public.maintenance_tickets;
DROP POLICY IF EXISTS "tickets: tenant select own" ON public.maintenance_tickets;
DROP POLICY IF EXISTS "tickets: tenant insert own" ON public.maintenance_tickets;
DROP POLICY IF EXISTS "tickets: technician reads assigned" ON public.maintenance_tickets;
DROP POLICY IF EXISTS "tickets: technician updates assigned" ON public.maintenance_tickets;
DROP POLICY IF EXISTS "tickets: org viewer read" ON public.maintenance_tickets;
DROP POLICY IF EXISTS "comments: readable with ticket" ON public.maintenance_comments;
DROP POLICY IF EXISTS "comments: insert by ticket participants" ON public.maintenance_comments;
DROP POLICY IF EXISTS "attachments: readable with ticket" ON public.maintenance_attachments;
DROP POLICY IF EXISTS "attachments: insert by ticket participants" ON public.maintenance_attachments;
DROP POLICY IF EXISTS "tasks: manager full access" ON public.housekeeping_tasks;
DROP POLICY IF EXISTS "tasks: housekeeper reads assigned" ON public.housekeeping_tasks;
DROP POLICY IF EXISTS "tasks: housekeeper updates assigned" ON public.housekeeping_tasks;
DROP POLICY IF EXISTS "property_staff: manager full access" ON public.property_staff;
DROP POLICY IF EXISTS "property_staff: member select own" ON public.property_staff;
DROP POLICY IF EXISTS "organizations: admin full access" ON public.organizations;
DROP POLICY IF EXISTS "organizations: manager create" ON public.organizations;
DROP POLICY IF EXISTS "organizations: member read" ON public.organizations;
DROP POLICY IF EXISTS "org_members: owner select" ON public.organization_members;
DROP POLICY IF EXISTS "org_members: owner insert" ON public.organization_members;
DROP POLICY IF EXISTS "org_members: owner update" ON public.organization_members;
DROP POLICY IF EXISTS "org_members: owner delete" ON public.organization_members;
DROP POLICY IF EXISTS "org_members: read own" ON public.organization_members;
DROP POLICY IF EXISTS "buildings: manager full access" ON public.buildings;
DROP POLICY IF EXISTS "buildings: members read" ON public.buildings;
DROP POLICY IF EXISTS "billing_periods: manager full access" ON public.billing_periods;
DROP POLICY IF EXISTS "billing_periods: housekeeper read" ON public.billing_periods;
DROP POLICY IF EXISTS "meter_readings: manager full access" ON public.meter_readings;
DROP POLICY IF EXISTS "meter_readings: housekeeper submit" ON public.meter_readings;
DROP POLICY IF EXISTS "meter_readings: housekeeper update own" ON public.meter_readings;
DROP POLICY IF EXISTS "meter_readings: housekeeper read" ON public.meter_readings;

-- ============================================================
-- profiles
-- ============================================================
DROP POLICY IF EXISTS "profiles: manager read property members" ON public.profiles;
CREATE POLICY "profiles: manager read property members"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.tenant_profiles tp
      JOIN public.properties p ON p.id = tp.property_id
      WHERE tp.user_id = profiles.id
        AND public.can_manage_property(p.id)
    )
    OR EXISTS (
      SELECT 1
      FROM public.memberships m
      JOIN public.properties p ON p.id = m.property_id
      WHERE m.user_id = profiles.id
        AND public.can_manage_property(p.id)
    )
    OR profiles.id = (SELECT auth.uid())
  );

-- ============================================================
-- memberships
-- ============================================================
ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;

CREATE POLICY "memberships: view own"
  ON public.memberships FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE POLICY "memberships: owner view org"
  ON public.memberships FOR SELECT
  TO authenticated
  USING (public.is_org_owner(organization_id));

-- ============================================================
-- invitations
-- ============================================================
ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "invitations: owner manager select"
  ON public.invitations FOR SELECT
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  );

CREATE POLICY "invitations: owner manager insert"
  ON public.invitations FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  );

CREATE POLICY "invitations: owner manager update"
  ON public.invitations FOR UPDATE
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  )
  WITH CHECK (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  );

-- ============================================================
-- tenant_profiles
-- ============================================================
ALTER TABLE public.tenant_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenant_profiles: scoped select"
  ON public.tenant_profiles FOR SELECT
  TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  );

CREATE POLICY "tenant_profiles: manager owner insert"
  ON public.tenant_profiles FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  );

CREATE POLICY "tenant_profiles: manager owner update"
  ON public.tenant_profiles FOR UPDATE
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  )
  WITH CHECK (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  );

CREATE POLICY "tenant_profiles: manager owner delete"
  ON public.tenant_profiles FOR DELETE
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  );

-- ============================================================
-- organizations
-- ============================================================
CREATE POLICY "organizations: owner full access"
  ON public.organizations FOR ALL
  TO authenticated
  USING (public.is_org_owner(id))
  WITH CHECK (public.is_org_owner(id));

CREATE POLICY "organizations: member read"
  ON public.organizations FOR SELECT
  TO authenticated
  USING (
    public.is_org_owner(id)
    OR EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.organization_id = organizations.id
        AND m.user_id = (SELECT auth.uid())
        AND m.deactivated_at IS NULL
    )
  );

-- ============================================================
-- properties
-- ============================================================
CREATE POLICY "properties: owner manager insert"
  ON public.properties FOR INSERT
  TO authenticated
  WITH CHECK (public.is_org_owner(organization_id));

CREATE POLICY "properties: owner manager update"
  ON public.properties FOR UPDATE
  TO authenticated
  USING (public.can_manage_property(id))
  WITH CHECK (public.can_manage_property(id));

CREATE POLICY "properties: owner manager delete"
  ON public.properties FOR DELETE
  TO authenticated
  USING (public.can_manage_property(id));

CREATE POLICY "properties: members view accessible"
  ON public.properties FOR SELECT
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR EXISTS (
      SELECT 1
      FROM public.memberships m
      WHERE m.user_id = (SELECT auth.uid())
        AND m.property_id = properties.id
        AND m.deactivated_at IS NULL
    )
  );

-- ============================================================
-- buildings
-- ============================================================
CREATE POLICY "buildings: manager owner full access"
  ON public.buildings FOR ALL
  TO authenticated
  USING (public.can_manage_property(property_id))
  WITH CHECK (public.can_manage_property(property_id));

CREATE POLICY "buildings: members read"
  ON public.buildings FOR SELECT
  TO authenticated
  USING (
    public.can_access_property(property_id)
    OR EXISTS (
      SELECT 1
      FROM public.maintenance_tickets mt
      WHERE mt.property_id = buildings.property_id
        AND mt.assigned_to = (SELECT auth.uid())
    )
  );

-- ============================================================
-- rooms
-- ============================================================
CREATE POLICY "rooms: manager owner full access"
  ON public.rooms FOR ALL
  TO authenticated
  USING (public.can_manage_property(property_id))
  WITH CHECK (public.can_manage_property(property_id));

CREATE POLICY "rooms: members view scoped"
  ON public.rooms FOR SELECT
  TO authenticated
  USING (
    public.is_org_owner(
      (SELECT p.organization_id FROM public.properties p WHERE p.id = property_id)
    )
    OR EXISTS (
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
    )
    OR EXISTS (
      SELECT 1
      FROM public.housekeeping_tasks ht
      WHERE ht.room_id = rooms.id
        AND ht.assigned_to = (SELECT auth.uid())
        AND ht.status IN ('pending', 'in_progress')
    )
  );

-- ============================================================
-- bills
-- ============================================================
CREATE POLICY "bills: manager owner full access"
  ON public.bills FOR ALL
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  )
  WITH CHECK (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  );

CREATE POLICY "bills: tenant read own"
  ON public.bills FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.tenant_profiles tp
      WHERE tp.id = bills.tenant_profile_id
        AND tp.user_id = (SELECT auth.uid())
    )
  );

-- ============================================================
-- bill_line_items
-- ============================================================
CREATE POLICY "bill_line_items: inherit bill access"
  ON public.bill_line_items FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.bills b
      WHERE b.id = bill_line_items.bill_id
        AND (
          public.is_org_owner(b.organization_id)
          OR public.has_property_role(b.property_id, 'manager')
          OR EXISTS (
            SELECT 1
            FROM public.tenant_profiles tp
            WHERE tp.id = b.tenant_profile_id
              AND tp.user_id = (SELECT auth.uid())
          )
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.bills b
      WHERE b.id = bill_line_items.bill_id
        AND (
          public.is_org_owner(b.organization_id)
          OR public.has_property_role(b.property_id, 'manager')
        )
    )
  );

-- ============================================================
-- maintenance_tickets
-- ============================================================
CREATE POLICY "tickets: manager owner full access"
  ON public.maintenance_tickets FOR ALL
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  )
  WITH CHECK (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  );

CREATE POLICY "tickets: scoped read"
  ON public.maintenance_tickets FOR SELECT
  TO authenticated
  USING (
    assigned_to = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1
      FROM public.tenant_profiles tp
      WHERE tp.id = maintenance_tickets.tenant_profile_id
        AND tp.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "tickets: tenant insert own"
  ON public.maintenance_tickets FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.tenant_profiles tp
      WHERE tp.id = maintenance_tickets.tenant_profile_id
        AND tp.user_id = (SELECT auth.uid())
        AND tp.lease_status = 'active'
        AND tp.archived_at IS NULL
    )
  );

CREATE POLICY "tickets: technician read assigned"
  ON public.maintenance_tickets FOR SELECT
  TO authenticated
  USING (
    assigned_to = (SELECT auth.uid())
    AND public.has_property_role(property_id, 'technician')
  );

CREATE POLICY "tickets: technician update assigned"
  ON public.maintenance_tickets FOR UPDATE
  TO authenticated
  USING (
    assigned_to = (SELECT auth.uid())
    AND public.has_property_role(property_id, 'technician')
  )
  WITH CHECK (
    assigned_to = (SELECT auth.uid())
    AND public.has_property_role(property_id, 'technician')
  );

-- ============================================================
-- maintenance_comments / attachments
-- ============================================================
CREATE POLICY "comments: readable with ticket"
  ON public.maintenance_comments FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.maintenance_tickets t
      WHERE t.id = maintenance_comments.ticket_id
        AND (
          public.is_org_owner(t.organization_id)
          OR public.has_property_role(t.property_id, 'manager')
          OR t.assigned_to = (SELECT auth.uid())
          OR EXISTS (
            SELECT 1
            FROM public.tenant_profiles tp
            WHERE tp.id = t.tenant_profile_id
              AND tp.user_id = (SELECT auth.uid())
          )
        )
    )
  );

CREATE POLICY "comments: insert by ticket participants"
  ON public.maintenance_comments FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1
      FROM public.maintenance_tickets t
      WHERE t.id = maintenance_comments.ticket_id
        AND (
          public.is_org_owner(t.organization_id)
          OR public.has_property_role(t.property_id, 'manager')
          OR t.assigned_to = (SELECT auth.uid())
          OR EXISTS (
            SELECT 1
            FROM public.tenant_profiles tp
            WHERE tp.id = t.tenant_profile_id
              AND tp.user_id = (SELECT auth.uid())
          )
        )
    )
  );

CREATE POLICY "attachments: readable with ticket"
  ON public.maintenance_attachments FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.maintenance_tickets t
      WHERE t.id = maintenance_attachments.ticket_id
        AND (
          public.is_org_owner(t.organization_id)
          OR public.has_property_role(t.property_id, 'manager')
          OR t.assigned_to = (SELECT auth.uid())
          OR EXISTS (
            SELECT 1
            FROM public.tenant_profiles tp
            WHERE tp.id = t.tenant_profile_id
              AND tp.user_id = (SELECT auth.uid())
          )
        )
    )
  );

CREATE POLICY "attachments: insert by ticket participants"
  ON public.maintenance_attachments FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.maintenance_tickets t
      WHERE t.id = maintenance_attachments.ticket_id
        AND (
          public.is_org_owner(t.organization_id)
          OR public.has_property_role(t.property_id, 'manager')
          OR t.assigned_to = (SELECT auth.uid())
          OR EXISTS (
            SELECT 1
            FROM public.tenant_profiles tp
            WHERE tp.id = t.tenant_profile_id
              AND tp.user_id = (SELECT auth.uid())
          )
        )
    )
  );

-- ============================================================
-- housekeeping_tasks
-- ============================================================
CREATE POLICY "tasks: manager owner full access"
  ON public.housekeeping_tasks FOR ALL
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  )
  WITH CHECK (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  );

CREATE POLICY "tasks: housekeeper read assigned"
  ON public.housekeeping_tasks FOR SELECT
  TO authenticated
  USING (
    assigned_to = (SELECT auth.uid())
    AND public.has_property_role(property_id, 'housekeeper')
  );

CREATE POLICY "tasks: housekeeper update assigned"
  ON public.housekeeping_tasks FOR UPDATE
  TO authenticated
  USING (
    assigned_to = (SELECT auth.uid())
    AND public.has_property_role(property_id, 'housekeeper')
  )
  WITH CHECK (
    assigned_to = (SELECT auth.uid())
    AND public.has_property_role(property_id, 'housekeeper')
  );

-- ============================================================
-- billing_periods
-- ============================================================
CREATE POLICY "billing_periods: manager owner full access"
  ON public.billing_periods FOR ALL
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  )
  WITH CHECK (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  );

CREATE POLICY "billing_periods: housekeeper read open"
  ON public.billing_periods FOR SELECT
  TO authenticated
  USING (
    public.has_property_role(property_id, 'housekeeper')
    AND status = 'open'
  );

-- ============================================================
-- meter_readings
-- ============================================================
CREATE POLICY "meter_readings: manager owner full access"
  ON public.meter_readings FOR ALL
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  )
  WITH CHECK (
    (
      public.is_org_owner(organization_id)
      OR public.has_property_role(property_id, 'manager')
    )
    AND EXISTS (
      SELECT 1
      FROM public.billing_periods bp
      WHERE bp.id = meter_readings.billing_period_id
        AND bp.status = 'open'
    )
  );

CREATE POLICY "meter_readings: housekeeper submit"
  ON public.meter_readings FOR INSERT
  TO authenticated
  WITH CHECK (
    submitted_by = (SELECT auth.uid())
    AND public.has_property_role(property_id, 'housekeeper')
    AND EXISTS (
      SELECT 1
      FROM public.billing_periods bp
      WHERE bp.id = meter_readings.billing_period_id
        AND bp.status = 'open'
    )
  );

CREATE POLICY "meter_readings: housekeeper update own"
  ON public.meter_readings FOR UPDATE
  TO authenticated
  USING (
    submitted_by = (SELECT auth.uid())
    AND status IN ('pending', 'submitted', 'rejected')
  )
  WITH CHECK (
    submitted_by = (SELECT auth.uid())
    AND status IN ('pending', 'submitted')
    AND public.has_property_role(property_id, 'housekeeper')
    AND EXISTS (
      SELECT 1
      FROM public.billing_periods bp
      WHERE bp.id = meter_readings.billing_period_id
        AND bp.status = 'open'
    )
  );

CREATE POLICY "meter_readings: housekeeper read"
  ON public.meter_readings FOR SELECT
  TO authenticated
  USING (public.has_property_role(property_id, 'housekeeper'));
