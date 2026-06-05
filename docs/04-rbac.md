# 04 — RBAC Model

## 1. Overview

Habio uses a **two-layer access control** model:

| Layer | Mechanism | Purpose |
|---|---|---|
| **Layer 1 — Route Guard** | Next.js Middleware | UX-level redirect; prevents wrong-role users from seeing other role's UI |
| **Layer 2 — Data Enforcement** | Supabase RLS (PostgreSQL) | Security guarantee; a compromised or misconfigured frontend cannot leak data |

The role is stored in `profiles.role` and is **never embedded in the JWT**. This means role changes take effect immediately without requiring token re-issuance. Both layers read the role from the database on each request.

---

## 2. Role Definitions

| Role | Value | Description |
|---|---|---|
| Manager | `manager` | Administers one or more properties. Full CRUD within their properties. |
| Tenant | `tenant` | Lives in a room. Read-only on most data; can create maintenance tickets. |
| Technician | `technician` | Handles assigned maintenance tickets. No billing or housekeeping access. |
| Housekeeper | `housekeeper` | Handles assigned housekeeping tasks. No billing or ticket access. |

---

## 3. Feature Permission Matrix

| Feature | Manager | Tenant | Technician | Housekeeper |
|---|:---:|:---:|:---:|:---:|
| **Properties** | | | | |
| View own properties | CRUD | — | — | — |
| **Rooms** | | | | |
| View rooms | CRUD | own room only | assigned ticket rooms | assigned task rooms |
| Archive room | CRUD | — | — | — |
| **Tenants** | | | | |
| View tenant list | R (own property) | — | — | — |
| Manage tenants | CRUD | own profile only | — | — |
| **Billing** | | | | |
| Generate / edit bills | CRUD | — | — | — |
| View bills | R (all in property) | own bills only | — | — |
| Mark bill paid | U | — | — | — |
| **Maintenance Tickets** | | | | |
| Create ticket | CU | C | — | — |
| View tickets | R (all in property) | own tickets only | assigned only | — |
| Assign ticket | U | — | — | — |
| Update status | U | — | U (assigned) | — |
| Add comment | C | C (own tickets) | C (assigned) | — |
| **Housekeeping** | | | | |
| Create / assign task | CRUD | — | — | — |
| View tasks | R (all in property) | — | — | assigned only |
| Update task status | U | — | — | U (assigned) |
| **Notifications** | | | | |
| View own notifications | R | R | R | R |
| Mark read | U | U | U | U |
| **Profiles** | | | | |
| View own profile | RU | RU | RU | RU |
| View other profiles | R (own property) | — | — | — |
| **Property Staff** | | | | |
| Add / remove staff | CRUD | — | — | — |
| View own membership | — | — | R | R |

Legend: **C** = Create, **R** = Read, **U** = Update, **D** = Delete, **—** = No access

---

## 4. Next.js Middleware — Route Guard

### 4.1 Route Namespace Design

Each role owns a dedicated URL prefix under `/(dashboard)`:

| Role | URL Prefix |
|---|---|
| Manager | `/manager/...` |
| Tenant | `/tenant/...` |
| Technician | `/technician/...` |
| Housekeeper | `/housekeeper/...` |

### 4.2 Middleware Logic

```
src/middleware.ts
```

```
1. All requests → updateSession() to refresh Supabase session cookie
2. If no valid session → redirect to /auth/login
3. Read profiles.role for authenticated user (server client)
4. If request path starts with /[role]/ and role does not match → redirect to /[actual-role]/dashboard
5. Pass through to Next.js router
```

### 4.3 Middleware Pseudocode

```typescript
// src/middleware.ts
export async function middleware(request: NextRequest) {
  // Step 1: refresh session
  const response = await updateSession(request)

  // Step 2: validate session
  const supabase = createServerClient(...)
  const { data } = await supabase.auth.getClaims()
  const userId = data?.claims?.sub

  if (!userId) {
    return NextResponse.redirect(new URL('/auth/login', request.url))
  }

  // Step 3: fetch role (server component reads this from profiles)
  const { data: profile } = await supabase
    .from('profiles')
    .select('role')
    .eq('id', userId)
    .single()

  const role = profile?.role
  const path = request.nextUrl.pathname

  // Step 4: role-prefix enforcement
  const roleRoutes = ['manager', 'tenant', 'technician', 'housekeeper']
  const requestedRole = roleRoutes.find(r => path.startsWith(`/${r}`))

  if (requestedRole && requestedRole !== role) {
    return NextResponse.redirect(new URL(`/${role}/dashboard`, request.url))
  }

  // Step 5: root redirect
  if (path === '/') {
    return NextResponse.redirect(new URL(`/${role}/dashboard`, request.url))
  }

  return response
}

export const config = {
  // api/webhooks must be excluded: LINE platform POSTs without a session cookie.
  // Middleware evaluating !userId would redirect it to /auth/login (302),
  // causing LINE to mark every delivery as failed and retry indefinitely.
  matcher: ['/((?!_next/static|_next/image|favicon.ico|auth|api/webhooks).*)'],
}
```

### 4.4 Public Routes (no auth required)

| Path | Description |
|---|---|
| `/auth/login` | Sign-in page |
| `/auth/callback` | Supabase OAuth / magic link callback |
| `/api/webhooks/line` | LINE webhook (validated by signature, not session) |

---

## 5. Row Level Security Policies

### 5.1 Helper Functions

```sql
-- Returns the role of the currently authenticated user
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS user_role LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid()
$$;

-- Returns true if the current user manages the given property
CREATE OR REPLACE FUNCTION public.is_property_manager(p_property_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.properties
    WHERE id = p_property_id AND manager_id = auth.uid()
  )
$$;

-- Returns true if the current user is a tenant of the given property
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
```

### 5.2 `profiles`

```sql
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Users can read their own profile
CREATE POLICY "profiles: own select"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (id = (SELECT auth.uid()));

-- Users can update their own profile, but cannot change their own role.
-- The WITH CHECK subquery re-reads the persisted role and asserts it is
-- unchanged, closing the privilege-escalation path via a direct UPDATE.
CREATE POLICY "profiles: own update"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (id = (SELECT auth.uid()))
  WITH CHECK (
    id = (SELECT auth.uid()) AND
    role = (SELECT role FROM public.profiles WHERE id = (SELECT auth.uid()))
  );

-- Managers can read profiles of users in their properties
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
```

### 5.3 `properties`

```sql
ALTER TABLE public.properties ENABLE ROW LEVEL SECURITY;

-- Managers can CRUD their own properties
CREATE POLICY "properties: manager full access"
  ON public.properties FOR ALL
  USING (manager_id = auth.uid())
  WITH CHECK (manager_id = auth.uid());

-- Tenants, technicians, and housekeepers can read properties they are associated with
CREATE POLICY "properties: members read"
  ON public.properties FOR SELECT
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
```

### 5.4 `rooms`

```sql
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;

-- Managers: full access to rooms in their properties
CREATE POLICY "rooms: manager full access"
  ON public.rooms FOR ALL
  USING (public.is_property_manager(property_id))
  WITH CHECK (public.is_property_manager(property_id));

-- Tenants: read their own room
CREATE POLICY "rooms: tenant reads own room"
  ON public.rooms FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.tenants
      WHERE room_id = rooms.id
        AND user_id = auth.uid()
        AND lease_status = 'active'
    )
  );

-- Technicians: read rooms they have an assigned ticket for
CREATE POLICY "rooms: technician reads assigned rooms"
  ON public.rooms FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.maintenance_tickets
      WHERE room_id = rooms.id
        AND assigned_to = auth.uid()
        AND status NOT IN ('closed')
    )
  );

-- Housekeepers: read rooms they have an assigned task for
CREATE POLICY "rooms: housekeeper reads assigned rooms"
  ON public.rooms FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.housekeeping_tasks
      WHERE room_id = rooms.id
        AND assigned_to = auth.uid()
        AND status IN ('pending', 'in_progress')
    )
  );
```

### 5.5 `tenants`

```sql
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;

-- Managers: full access within their properties
CREATE POLICY "tenants: manager full access"
  ON public.tenants FOR ALL
  USING (public.is_property_manager(property_id))
  WITH CHECK (public.is_property_manager(property_id));

-- Tenants: read own tenant record
CREATE POLICY "tenants: read own record"
  ON public.tenants FOR SELECT
  USING (user_id = auth.uid());
```

### 5.6 `bills`

```sql
ALTER TABLE public.bills ENABLE ROW LEVEL SECURITY;

-- Managers: full access within their properties
CREATE POLICY "bills: manager full access"
  ON public.bills FOR ALL
  USING (public.is_property_manager(property_id))
  WITH CHECK (public.is_property_manager(property_id));

-- Tenants: read own bills
CREATE POLICY "bills: tenant reads own bills"
  ON public.bills FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.tenants
      WHERE id = bills.tenant_id AND user_id = auth.uid()
    )
  );
```

### 5.7 `bill_line_items`

```sql
ALTER TABLE public.bill_line_items ENABLE ROW LEVEL SECURITY;

-- Accessible if the parent bill is accessible
CREATE POLICY "bill_line_items: inherit bill access"
  ON public.bill_line_items FOR ALL
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
```

### 5.8 `maintenance_tickets`

```sql
ALTER TABLE public.maintenance_tickets ENABLE ROW LEVEL SECURITY;

-- Managers: full access within their properties
CREATE POLICY "tickets: manager full access"
  ON public.maintenance_tickets FOR ALL
  USING (public.is_property_manager(property_id))
  WITH CHECK (public.is_property_manager(property_id));

-- Tenants: read own tickets
-- Separated from INSERT/UPDATE so that FOR ALL does not implicitly grant DELETE.
CREATE POLICY "tickets: tenant select own"
  ON public.maintenance_tickets FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.tenants
      WHERE id = maintenance_tickets.tenant_id AND user_id = (SELECT auth.uid())
    )
  );

-- Tenants: create tickets for rooms they are actively leasing
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

-- Tenants cannot update tickets (status changes belong to manager/technician).
-- No UPDATE policy for tenants is intentional.

-- Technicians: read and update assigned tickets
CREATE POLICY "tickets: technician reads and updates assigned"
  ON public.maintenance_tickets FOR SELECT
  USING (assigned_to = auth.uid());

CREATE POLICY "tickets: technician updates assigned"
  ON public.maintenance_tickets FOR UPDATE
  USING (assigned_to = auth.uid())
  WITH CHECK (assigned_to = auth.uid());
```

### 5.9 `maintenance_comments`

```sql
ALTER TABLE public.maintenance_comments ENABLE ROW LEVEL SECURITY;

-- Readable if the user can read the parent ticket
CREATE POLICY "comments: readable with ticket"
  ON public.maintenance_comments FOR SELECT
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

-- Insertable by anyone who can read the ticket
CREATE POLICY "comments: insert by ticket participants"
  ON public.maintenance_comments FOR INSERT
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
```

### 5.10 `housekeeping_tasks`

```sql
ALTER TABLE public.housekeeping_tasks ENABLE ROW LEVEL SECURITY;

-- Managers: full access within their properties
CREATE POLICY "tasks: manager full access"
  ON public.housekeeping_tasks FOR ALL
  USING (public.is_property_manager(property_id))
  WITH CHECK (public.is_property_manager(property_id));

-- Housekeepers: read and update assigned tasks
CREATE POLICY "tasks: housekeeper reads assigned"
  ON public.housekeeping_tasks FOR SELECT
  USING (assigned_to = auth.uid());

CREATE POLICY "tasks: housekeeper updates assigned"
  ON public.housekeeping_tasks FOR UPDATE
  USING (assigned_to = auth.uid())
  WITH CHECK (assigned_to = auth.uid());
```

### 5.11 `notifications`

```sql
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Users can read their own notifications
CREATE POLICY "notifications: own select"
  ON public.notifications FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- Users can mark their own notifications as read (UPDATE only).
-- INSERT is intentionally omitted: notifications must be created server-side
-- via the service role key to prevent users from injecting fake alerts.
-- DELETE is intentionally omitted: notification history is immutable from
-- the client; archival is handled by a server-side pg_cron job.
CREATE POLICY "notifications: own update"
  ON public.notifications FOR UPDATE
  TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));
```

### 5.12 `line_connections`

```sql
ALTER TABLE public.line_connections ENABLE ROW LEVEL SECURITY;

-- Users can read their own LINE connection status (e.g., to show "connected" in UI)
CREATE POLICY "line_connections: own select"
  ON public.line_connections FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- INSERT, UPDATE, and DELETE are intentionally omitted.
-- All writes go through the LINE webhook route handler using the service role key:
-- - INSERT/UPDATE on 'follow' event (links line_user_id to profiles.id)
-- - UPDATE is_active = false on 'unfollow' event
-- Allowing client-side INSERT would let a user claim an arbitrary line_user_id
-- before the real owner connects, hijacking that user's LINE notifications.
```

### 5.13 `property_staff`

```sql
ALTER TABLE public.property_staff ENABLE ROW LEVEL SECURITY;

-- Managers: full CRUD for staff in their own properties.
-- This allows managers to add/remove technicians and housekeepers.
CREATE POLICY "property_staff: manager full access"
  ON public.property_staff FOR ALL
  TO authenticated
  USING (public.is_property_manager(property_id))
  WITH CHECK (public.is_property_manager(property_id));

-- Staff: read their own membership rows (e.g., to know which properties they are assigned to)
CREATE POLICY "property_staff: member select own"
  ON public.property_staff FOR SELECT
  TO authenticated
  USING (user_id = (SELECT auth.uid()));
```

**Impact on existing technician/housekeeper RLS policies:**
The `rooms`, `maintenance_tickets`, and `housekeeping_tasks` policies already rely on `assigned_to = auth.uid()`. The `property_staff` table does not replace those policies — it is enforced at the **application layer** (Server Actions) to prevent a manager from assigning work to staff who do not belong to their property. The RLS policies remain the security backstop.

---

## 6. Service Role Usage

Certain operations require bypassing RLS using the Supabase **service role key**:

| Operation | Reason |
|---|---|
| LINE webhook handler — link `line_user_id` to `user_id` | No authenticated session in webhook context |
| Trigger-based `sync_room_status` | Runs as `SECURITY DEFINER` |
| Background bill overdue detection (cron) | Not user-initiated |

The service role key is **only used in server-side code** (Route Handlers, Supabase Edge Functions) and is never exposed to the client.

---

## 7. RLS Testing Strategy

- Every table policy has a corresponding test in `supabase/tests/` using `pgTAP`
- Tests run in CI via `supabase test db`
- Each test instantiates a mock user for each role and verifies allowed/denied operations
