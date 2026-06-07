-- Security & performance fixes
-- Addresses findings from Supabase advisor:
--   Security: exposed SECURITY DEFINER functions, mutable search_path
--   Performance: auth.uid() re-evaluated per row, missing FK indexes

-- ============================================================
-- SECURITY: Revoke EXECUTE on trigger functions from all roles.
-- handle_new_user and sync_room_status are trigger callbacks;
-- they should never be callable directly via the REST API.
-- Revoke explicitly from anon and authenticated (Supabase default
-- privilege grants can re-add them after a simple FROM PUBLIC revoke).
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sync_room_status() FROM PUBLIC, anon, authenticated;

-- ============================================================
-- SECURITY: Revoke EXECUTE on helper functions from anon.
-- current_user_role, is_property_manager, is_property_tenant
-- are used inside RLS policies (called by the authenticated role)
-- but unauthenticated callers have no business invoking them.
-- ============================================================
REVOKE EXECUTE ON FUNCTION public.current_user_role() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_property_manager(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_property_tenant(uuid) FROM PUBLIC, anon;

-- ============================================================
-- SECURITY: Fix mutable search_path on set_updated_at trigger
-- ============================================================
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ============================================================
-- SECURITY: Document notifications_archive RLS intent
-- RLS is enabled with no policies: only the pg_cron service_role
-- job writes to this table; no client-facing access is intended.
-- ============================================================
COMMENT ON TABLE public.notifications_archive IS
  'Archive of old read notifications. Written exclusively by the pg_cron service_role job. RLS is enabled with no client policies by design — no direct client access is permitted.';

-- ============================================================
-- PERFORMANCE: Rebuild RLS policies to use (SELECT auth.uid())
-- instead of bare auth.uid() so Postgres evaluates the call
-- once per query instead of once per row.
-- Also wraps (SELECT current_user_role()) for the same reason.
-- ============================================================

-- profiles: manager read property members
DROP POLICY IF EXISTS "profiles: manager read property members" ON public.profiles;
CREATE POLICY "profiles: manager read property members"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (
    (SELECT public.current_user_role()) = 'manager' AND
    EXISTS (
      SELECT 1 FROM public.properties p
      LEFT JOIN public.tenants t ON t.property_id = p.id
      WHERE p.manager_id = (SELECT auth.uid())
        AND (t.user_id = profiles.id OR profiles.id = (SELECT auth.uid()))
    )
  );

-- properties: manager full access
DROP POLICY IF EXISTS "properties: manager full access" ON public.properties;
CREATE POLICY "properties: manager full access"
  ON public.properties FOR ALL
  TO authenticated
  USING (manager_id = (SELECT auth.uid()))
  WITH CHECK (manager_id = (SELECT auth.uid()));

-- properties: members read
DROP POLICY IF EXISTS "properties: members read" ON public.properties;
CREATE POLICY "properties: members read"
  ON public.properties FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.tenants
      WHERE property_id = properties.id
        AND user_id = (SELECT auth.uid())
        AND lease_status = 'active'
    ) OR
    EXISTS (
      SELECT 1 FROM public.maintenance_tickets
      WHERE property_id = properties.id
        AND assigned_to = (SELECT auth.uid())
    ) OR
    EXISTS (
      SELECT 1 FROM public.housekeeping_tasks
      WHERE property_id = properties.id
        AND assigned_to = (SELECT auth.uid())
    )
  );

-- rooms: tenant reads own room
DROP POLICY IF EXISTS "rooms: tenant reads own room" ON public.rooms;
CREATE POLICY "rooms: tenant reads own room"
  ON public.rooms FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.tenants
      WHERE room_id = rooms.id
        AND user_id = (SELECT auth.uid())
        AND lease_status = 'active'
    )
  );

-- rooms: technician reads assigned rooms
DROP POLICY IF EXISTS "rooms: technician reads assigned rooms" ON public.rooms;
CREATE POLICY "rooms: technician reads assigned rooms"
  ON public.rooms FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.maintenance_tickets
      WHERE room_id = rooms.id
        AND assigned_to = (SELECT auth.uid())
        AND status NOT IN ('closed')
    )
  );

-- rooms: housekeeper reads assigned rooms
DROP POLICY IF EXISTS "rooms: housekeeper reads assigned rooms" ON public.rooms;
CREATE POLICY "rooms: housekeeper reads assigned rooms"
  ON public.rooms FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.housekeeping_tasks
      WHERE room_id = rooms.id
        AND assigned_to = (SELECT auth.uid())
        AND status IN ('pending', 'in_progress')
    )
  );

-- tenants: read own record
DROP POLICY IF EXISTS "tenants: read own record" ON public.tenants;
CREATE POLICY "tenants: read own record"
  ON public.tenants FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- bills: tenant reads own bills
DROP POLICY IF EXISTS "bills: tenant reads own bills" ON public.bills;
CREATE POLICY "bills: tenant reads own bills"
  ON public.bills FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.tenants
      WHERE id = bills.tenant_id AND user_id = (SELECT auth.uid())
    )
  );

-- bill_line_items: inherit bill access
DROP POLICY IF EXISTS "bill_line_items: inherit bill access" ON public.bill_line_items;
CREATE POLICY "bill_line_items: inherit bill access"
  ON public.bill_line_items FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.bills b
      WHERE b.id = bill_line_items.bill_id
        AND (
          public.is_property_manager(b.property_id) OR
          EXISTS (
            SELECT 1 FROM public.tenants t
            WHERE t.id = b.tenant_id AND t.user_id = (SELECT auth.uid())
          )
        )
    )
  );

-- tickets: technician reads and updates assigned
DROP POLICY IF EXISTS "tickets: technician reads and updates assigned" ON public.maintenance_tickets;
CREATE POLICY "tickets: technician reads and updates assigned"
  ON public.maintenance_tickets FOR SELECT
  TO authenticated
  USING (assigned_to = (SELECT auth.uid()));

-- tickets: technician updates assigned
DROP POLICY IF EXISTS "tickets: technician updates assigned" ON public.maintenance_tickets;
CREATE POLICY "tickets: technician updates assigned"
  ON public.maintenance_tickets FOR UPDATE
  TO authenticated
  USING (assigned_to = (SELECT auth.uid()))
  WITH CHECK (assigned_to = (SELECT auth.uid()));

-- comments: readable with ticket
DROP POLICY IF EXISTS "comments: readable with ticket" ON public.maintenance_comments;
CREATE POLICY "comments: readable with ticket"
  ON public.maintenance_comments FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.maintenance_tickets t
      WHERE t.id = maintenance_comments.ticket_id
        AND (
          public.is_property_manager(t.property_id) OR
          t.assigned_to = (SELECT auth.uid()) OR
          EXISTS (
            SELECT 1 FROM public.tenants tn
            WHERE tn.id = t.tenant_id AND tn.user_id = (SELECT auth.uid())
          )
        )
    )
  );

-- comments: insert by ticket participants
DROP POLICY IF EXISTS "comments: insert by ticket participants" ON public.maintenance_comments;
CREATE POLICY "comments: insert by ticket participants"
  ON public.maintenance_comments FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid()) AND
    EXISTS (
      SELECT 1 FROM public.maintenance_tickets t
      WHERE t.id = maintenance_comments.ticket_id
        AND (
          public.is_property_manager(t.property_id) OR
          t.assigned_to = (SELECT auth.uid()) OR
          EXISTS (
            SELECT 1 FROM public.tenants tn
            WHERE tn.id = t.tenant_id AND tn.user_id = (SELECT auth.uid())
          )
        )
    )
  );

-- attachments: readable with ticket
DROP POLICY IF EXISTS "attachments: readable with ticket" ON public.maintenance_attachments;
CREATE POLICY "attachments: readable with ticket"
  ON public.maintenance_attachments FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.maintenance_tickets t
      WHERE t.id = maintenance_attachments.ticket_id
        AND (
          public.is_property_manager(t.property_id) OR
          t.assigned_to = (SELECT auth.uid()) OR
          EXISTS (
            SELECT 1 FROM public.tenants tn
            WHERE tn.id = t.tenant_id AND tn.user_id = (SELECT auth.uid())
          )
        )
    )
  );

-- attachments: insert by ticket participants
DROP POLICY IF EXISTS "attachments: insert by ticket participants" ON public.maintenance_attachments;
CREATE POLICY "attachments: insert by ticket participants"
  ON public.maintenance_attachments FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.maintenance_tickets t
      WHERE t.id = maintenance_attachments.ticket_id
        AND (
          public.is_property_manager(t.property_id) OR
          t.assigned_to = (SELECT auth.uid()) OR
          EXISTS (
            SELECT 1 FROM public.tenants tn
            WHERE tn.id = t.tenant_id AND tn.user_id = (SELECT auth.uid())
          )
        )
    )
  );

-- housekeeping_tasks: housekeeper reads assigned
DROP POLICY IF EXISTS "tasks: housekeeper reads assigned" ON public.housekeeping_tasks;
CREATE POLICY "tasks: housekeeper reads assigned"
  ON public.housekeeping_tasks FOR SELECT
  TO authenticated
  USING (assigned_to = (SELECT auth.uid()));

-- housekeeping_tasks: housekeeper updates assigned
DROP POLICY IF EXISTS "tasks: housekeeper updates assigned" ON public.housekeeping_tasks;
CREATE POLICY "tasks: housekeeper updates assigned"
  ON public.housekeeping_tasks FOR UPDATE
  TO authenticated
  USING (assigned_to = (SELECT auth.uid()))
  WITH CHECK (assigned_to = (SELECT auth.uid()));

-- ============================================================
-- PERFORMANCE: Add indexes for unindexed foreign keys
-- These FK columns are used in JOINs and had no covering index.
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_bills_room_id
  ON public.bills (room_id);

CREATE INDEX IF NOT EXISTS idx_housekeeping_tasks_created_by
  ON public.housekeeping_tasks (created_by);

CREATE INDEX IF NOT EXISTS idx_housekeeping_tasks_room_id
  ON public.housekeeping_tasks (room_id);

CREATE INDEX IF NOT EXISTS idx_maintenance_attachments_ticket_id
  ON public.maintenance_attachments (ticket_id);

CREATE INDEX IF NOT EXISTS idx_maintenance_comments_user_id
  ON public.maintenance_comments (user_id);

CREATE INDEX IF NOT EXISTS idx_maintenance_tickets_room_id
  ON public.maintenance_tickets (room_id);
