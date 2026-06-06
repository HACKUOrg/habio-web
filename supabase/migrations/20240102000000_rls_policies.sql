-- Habio RLS policies
-- See docs/04-rbac.md

-- Helper functions
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS public.user_role LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid()
$$;

CREATE OR REPLACE FUNCTION public.is_property_manager(p_property_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.properties
    WHERE id = p_property_id AND manager_id = auth.uid()
  )
$$;

CREATE OR REPLACE FUNCTION public.is_property_tenant(p_property_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tenants
    WHERE property_id = p_property_id
      AND user_id = auth.uid()
      AND lease_status = 'active'
      AND archived_at IS NULL
  )
$$;

-- profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles: own select"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (id = (SELECT auth.uid()));

CREATE POLICY "profiles: own update"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (id = (SELECT auth.uid()))
  WITH CHECK (
    id = (SELECT auth.uid()) AND
    role = (SELECT role FROM public.profiles WHERE id = (SELECT auth.uid()))
  );

CREATE POLICY "profiles: manager read property members"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (
    public.current_user_role() = 'manager' AND
    EXISTS (
      SELECT 1 FROM public.properties p
      LEFT JOIN public.tenants t ON t.property_id = p.id
      WHERE p.manager_id = (SELECT auth.uid())
        AND (t.user_id = profiles.id OR profiles.id = (SELECT auth.uid()))
    )
  );

-- properties
ALTER TABLE public.properties ENABLE ROW LEVEL SECURITY;

CREATE POLICY "properties: manager full access"
  ON public.properties FOR ALL
  TO authenticated
  USING (manager_id = auth.uid())
  WITH CHECK (manager_id = auth.uid());

CREATE POLICY "properties: members read"
  ON public.properties FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.tenants
      WHERE property_id = properties.id
        AND user_id = auth.uid()
        AND lease_status = 'active'
    ) OR
    EXISTS (
      SELECT 1 FROM public.maintenance_tickets
      WHERE property_id = properties.id
        AND assigned_to = auth.uid()
    ) OR
    EXISTS (
      SELECT 1 FROM public.housekeeping_tasks
      WHERE property_id = properties.id
        AND assigned_to = auth.uid()
    )
  );

-- rooms
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rooms: manager full access"
  ON public.rooms FOR ALL
  TO authenticated
  USING (public.is_property_manager(property_id))
  WITH CHECK (public.is_property_manager(property_id));

CREATE POLICY "rooms: tenant reads own room"
  ON public.rooms FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.tenants
      WHERE room_id = rooms.id
        AND user_id = auth.uid()
        AND lease_status = 'active'
    )
  );

CREATE POLICY "rooms: technician reads assigned rooms"
  ON public.rooms FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.maintenance_tickets
      WHERE room_id = rooms.id
        AND assigned_to = auth.uid()
        AND status NOT IN ('closed')
    )
  );

CREATE POLICY "rooms: housekeeper reads assigned rooms"
  ON public.rooms FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.housekeeping_tasks
      WHERE room_id = rooms.id
        AND assigned_to = auth.uid()
        AND status IN ('pending', 'in_progress')
    )
  );

-- tenants
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenants: manager full access"
  ON public.tenants FOR ALL
  TO authenticated
  USING (public.is_property_manager(property_id))
  WITH CHECK (public.is_property_manager(property_id));

CREATE POLICY "tenants: read own record"
  ON public.tenants FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- bills
ALTER TABLE public.bills ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bills: manager full access"
  ON public.bills FOR ALL
  TO authenticated
  USING (public.is_property_manager(property_id))
  WITH CHECK (public.is_property_manager(property_id));

CREATE POLICY "bills: tenant reads own bills"
  ON public.bills FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.tenants
      WHERE id = bills.tenant_id AND user_id = auth.uid()
    )
  );

-- bill_line_items
ALTER TABLE public.bill_line_items ENABLE ROW LEVEL SECURITY;

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
            WHERE t.id = b.tenant_id AND t.user_id = auth.uid()
          )
        )
    )
  );

-- maintenance_tickets
ALTER TABLE public.maintenance_tickets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tickets: manager full access"
  ON public.maintenance_tickets FOR ALL
  TO authenticated
  USING (public.is_property_manager(property_id))
  WITH CHECK (public.is_property_manager(property_id));

CREATE POLICY "tickets: tenant select own"
  ON public.maintenance_tickets FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.tenants
      WHERE id = maintenance_tickets.tenant_id AND user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "tickets: tenant insert own"
  ON public.maintenance_tickets FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.tenants
      WHERE id = maintenance_tickets.tenant_id
        AND user_id = (SELECT auth.uid())
        AND lease_status = 'active'
        AND archived_at IS NULL
    )
  );

CREATE POLICY "tickets: technician reads and updates assigned"
  ON public.maintenance_tickets FOR SELECT
  TO authenticated
  USING (assigned_to = auth.uid());

CREATE POLICY "tickets: technician updates assigned"
  ON public.maintenance_tickets FOR UPDATE
  TO authenticated
  USING (assigned_to = auth.uid())
  WITH CHECK (assigned_to = auth.uid());

-- maintenance_comments
ALTER TABLE public.maintenance_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "comments: readable with ticket"
  ON public.maintenance_comments FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.maintenance_tickets t
      WHERE t.id = maintenance_comments.ticket_id
        AND (
          public.is_property_manager(t.property_id) OR
          t.assigned_to = auth.uid() OR
          EXISTS (
            SELECT 1 FROM public.tenants tn
            WHERE tn.id = t.tenant_id AND tn.user_id = auth.uid()
          )
        )
    )
  );

CREATE POLICY "comments: insert by ticket participants"
  ON public.maintenance_comments FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.maintenance_tickets t
      WHERE t.id = maintenance_comments.ticket_id
        AND (
          public.is_property_manager(t.property_id) OR
          t.assigned_to = auth.uid() OR
          EXISTS (
            SELECT 1 FROM public.tenants tn
            WHERE tn.id = t.tenant_id AND tn.user_id = auth.uid()
          )
        )
    )
  );

-- maintenance_attachments
ALTER TABLE public.maintenance_attachments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "attachments: readable with ticket"
  ON public.maintenance_attachments FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.maintenance_tickets t
      WHERE t.id = maintenance_attachments.ticket_id
        AND (
          public.is_property_manager(t.property_id) OR
          t.assigned_to = auth.uid() OR
          EXISTS (
            SELECT 1 FROM public.tenants tn
            WHERE tn.id = t.tenant_id AND tn.user_id = auth.uid()
          )
        )
    )
  );

CREATE POLICY "attachments: insert by ticket participants"
  ON public.maintenance_attachments FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.maintenance_tickets t
      WHERE t.id = maintenance_attachments.ticket_id
        AND (
          public.is_property_manager(t.property_id) OR
          t.assigned_to = auth.uid() OR
          EXISTS (
            SELECT 1 FROM public.tenants tn
            WHERE tn.id = t.tenant_id AND tn.user_id = auth.uid()
          )
        )
    )
  );

-- housekeeping_tasks
ALTER TABLE public.housekeeping_tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tasks: manager full access"
  ON public.housekeeping_tasks FOR ALL
  TO authenticated
  USING (public.is_property_manager(property_id))
  WITH CHECK (public.is_property_manager(property_id));

CREATE POLICY "tasks: housekeeper reads assigned"
  ON public.housekeeping_tasks FOR SELECT
  TO authenticated
  USING (assigned_to = auth.uid());

CREATE POLICY "tasks: housekeeper updates assigned"
  ON public.housekeeping_tasks FOR UPDATE
  TO authenticated
  USING (assigned_to = auth.uid())
  WITH CHECK (assigned_to = auth.uid());

-- notifications
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notifications: own select"
  ON public.notifications FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE POLICY "notifications: own update"
  ON public.notifications FOR UPDATE
  TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

-- notifications_archive (RLS enabled, no client policies — cron/service role only)
ALTER TABLE public.notifications_archive ENABLE ROW LEVEL SECURITY;

-- line_connections
ALTER TABLE public.line_connections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "line_connections: own select"
  ON public.line_connections FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- property_staff
ALTER TABLE public.property_staff ENABLE ROW LEVEL SECURITY;

CREATE POLICY "property_staff: manager full access"
  ON public.property_staff FOR ALL
  TO authenticated
  USING (public.is_property_manager(property_id))
  WITH CHECK (public.is_property_manager(property_id));

CREATE POLICY "property_staff: member select own"
  ON public.property_staff FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid()));
