# 04 - RBAC Model

## 1. Overview

Habio uses membership-based RBAC. Identity is a Supabase Auth user; authorization is one or more rows in `memberships`.

| Layer | Mechanism | Purpose |
|---|---|---|
| Route guard | Next.js middleware | UX-level redirect and active membership validation |
| Server actions | Explicit permission checks | Transactional business rules and invitation acceptance |
| Data enforcement | Supabase RLS | Authoritative row-level isolation |

Roles are not stored in `profiles`, JWT claims, or user metadata. Middleware and server actions read active memberships from the database or from a short-lived, signed active-membership cookie that is always revalidated against the database before sensitive mutations.

## 2. Roles and Scope

| Role | Scope | Who creates it | Description |
|---|---|---|---|
| `owner` | Organization | Self-registration first user flow | Full access to an organization and all properties |
| `manager` | Property | Owner invitation | Manages assigned properties, rooms, tenants, billing, occupancy transactions, tasks, and maintenance |
| `technician` | Property | Owner or manager invitation | Handles assigned maintenance jobs in assigned properties |
| `housekeeper` | Property | Owner or manager invitation | Handles assigned cleaning tasks and meter readings |
| `tenant` | Property and room | Manager activation flow | Views own room, bills, and requests maintenance |

### 2.2 Platform Admin

Platform admins are stored in `platform_admins` (outside `memberships`). They are not a membership role and do not receive org-scoped RLS grants. Admin dashboards query through service-role endpoints guarded by `is_platform_admin()`. Operational tables — including occupancy transactions — have no authenticated `SELECT` policy for platform admins.

A user may have multiple memberships. Examples:

- User A: manager of Property A, technician of Property B.
- User B: housekeeper of Property A and Property B.
- User C: tenant of Room A101.

## 2.1 Identity vs Authorization

Habio separates identity from authorization. They are stored in different tables and are fully independent.

| Concern | Table | Managed by |
|---|---|---|
| Who the user is | `user_identities` | Auth provider linkage |
| What the user can access | `memberships` | Owner/manager invitation flow |

A user may link any number of identity providers (email, LINE, Google, Apple). Each link is a row in `user_identities(provider, provider_user_id)`.

**Rules:**
- LINE identity identifies the user. Membership authorizes the user.
- Linking a LINE account does not create or modify any membership.
- Deactivating a membership (`deactivated_at`) does not remove identity rows.
- Removing a LINE identity does not deactivate any membership.
- A user with a LINE identity but no active membership has no access.

```
User
├─ Email Identity   (user_identities, provider='email')
└─ LINE Identity    (user_identities, provider='line')
     ↓
  Membership → Organization → Property → Role
```

Authorization always resolves through `memberships`. Never authorize based on identity provider or identity metadata.

## 3. Permission Matrix

| Feature | Owner | Manager | Technician | Housekeeper | Tenant |
|---|:---:|:---:|:---:|:---:|:---:|
| Organization profile | CRUD | R | - | - | - |
| Billing plan | CRUD | - | - | - | - |
| Subscription plan (read) | R | R | - | - | - |
| Organization subscription | CRUD | R | - | - | - |
| Usage counters | R | R | - | - | - |
| Properties | CRUD all org | R assigned | R assigned | R assigned | R own |
| Property membership list | CRUD | R assigned | R own | R own | R own |
| Invite manager | C | - | - | - | - |
| Invite technician | C | C assigned | - | - | - |
| Invite housekeeper | C | C assigned | - | - | - |
| Create tenant activation | C | C assigned | - | - | - |
| Buildings and rooms | CRUD all org | CRUD assigned | R job rooms | R task rooms | R own room |
| Tenant profiles | CRUD all org | CRUD assigned | - | - | R own |
| Billing periods | CRUD all org | CRUD assigned | - | R assigned | - |
| Meter readings | R/U all org | R/U assigned | - | C/U assigned | - |
| Bills | CRUD all org | CRUD assigned | - | - | R own |
| Maintenance tickets | R/U all org | R/U assigned | R/U assigned jobs | - | C/R own |
| Housekeeping tasks | CRUD all org | CRUD assigned | - | R/U assigned | - |
| Move-in transactions | CRUD all org | CRUD assigned | R† assigned | R† assigned | R own |
| Move-out transactions | CRUD all org | CRUD assigned | R† assigned | R† assigned | R own |
| Inspection items | CRUD all org | CRUD assigned | R† assigned | R† assigned | R own |
| Meter snapshots | R all org | R/C assigned | R† assigned | R† assigned | R own |
| Notifications | R/U own | R/U own | R/U own | R/U own | R/U own |
| Profiles | R org users | R assigned-property users | R own | R own | R own |

Legend: C = create, R = read, U = update, D = delete, - = no access.

†Read only when assigned to the parent inspection (see §3.2).

Platform Admin is omitted from this matrix. Operational data is visible to platform admins only through service-role admin endpoints, not through authenticated RLS policies.

### 3.1 Occupancy Transaction RLS Matrix

Row-level grants for Phase 3.5 tables — implementation phase: [06-implementation-roadmap.md](./06-implementation-roadmap.md) §7. Schema: [03-database-schema.md](./03-database-schema.md) §4.9. `✓` = allowed, `—` = denied, `✓*` = allowed only when the predicate in the footnote is true. Hard deletes on `move_in_transactions` and `move_out_transactions` are forbidden for all roles; use `status = 'voided'` instead. `meter_snapshots` are immutable — no `UPDATE` or `DELETE` for any authenticated role.

#### `move_in_transactions`

| Role | SELECT | INSERT | UPDATE | DELETE |
|---|---|:---:|:---:|:---:|
| Platform Admin | — | — | — | — |
| Owner | ✓ | ✓ | ✓ | — |
| Manager | ✓‡ | ✓‡ | ✓‡ | — |
| Technician | ✓* | — | — | — |
| Housekeeper | ✓* | — | — | — |
| Tenant | ✓§ | — | — | — |

#### `move_out_transactions`

| Role | SELECT | INSERT | UPDATE | DELETE |
|---|---|:---:|:---:|:---:|
| Platform Admin | — | — | — | — |
| Owner | ✓ | ✓ | ✓ | — |
| Manager | ✓‡ | ✓‡ | ✓‡ | — |
| Technician | ✓* | — | — | — |
| Housekeeper | ✓* | — | — | — |
| Tenant | ✓§ | — | — | — |

#### `inspection_items`

| Role | SELECT | INSERT | UPDATE | DELETE |
|---|---|:---:|:---:|:---:|
| Platform Admin | — | — | — | — |
| Owner | ✓ | ✓ | ✓ | ✓ |
| Manager | ✓‡ | ✓‡ | ✓‡ | ✓‡ |
| Technician | ✓* | — | — | — |
| Housekeeper | ✓* | — | — | — |
| Tenant | ✓§ | — | — | — |

#### `meter_snapshots`

| Role | SELECT | INSERT | UPDATE | DELETE |
|---|---|:---:|:---:|:---:|
| Platform Admin | — | — | — | — |
| Owner | ✓ | ✓ | — | — |
| Manager | ✓‡ | ✓‡ | — | — |
| Technician | ✓* | — | — | — |
| Housekeeper | ✓* | — | — | — |
| Tenant | ✓§ | — | — | — |

Footnotes:

- ‡Manager predicates use `has_property_role(property_id, 'manager')` against the row's denormalized `property_id`.
- §Tenant predicates join `tenant_profiles` where `tenant_profiles.id = row.tenant_profile_id` (or parent transaction's `tenant_profile_id` for child rows) and `tenant_profiles.user_id = auth.uid()`.
- *Technician and housekeeper `SELECT` is conditional on assignment to the parent inspection. No `inspection_assignments` table exists yet; the intended pattern is documented in §3.2.

Owner predicates use `is_org_owner(organization_id)` on the row's denormalized `organization_id`.

### 3.2 Inspection Assignment Pattern (Technician / Housekeeper)

Technicians and housekeepers do not receive blanket property access to occupancy transactions. They may `SELECT` transaction, inspection, and meter rows only when assigned to the handover inspection.

**Intended table** (Phase 3.5 or Phase 4 — not yet in schema):

```sql
-- Planned: links staff to a move-in or move-out handover
create table public.inspection_assignments (
  id                      uuid primary key default gen_random_uuid(),
  organization_id         uuid not null references public.organizations(id) on delete restrict,
  property_id             uuid not null references public.properties(id) on delete restrict,
  assigned_to             uuid not null references public.profiles(id) on delete restrict,
  move_in_transaction_id  uuid references public.move_in_transactions(id) on delete cascade,
  move_out_transaction_id uuid references public.move_out_transactions(id) on delete cascade,
  assigned_by             uuid not null references public.profiles(id) on delete restrict,
  created_at              timestamptz not null default now(),
  check (
    (move_in_transaction_id is not null)::int
    + (move_out_transaction_id is not null)::int = 1
  )
);
```

**RLS helper** (planned):

```sql
create function public.is_assigned_to_inspection(
  p_move_in_transaction_id uuid,
  p_move_out_transaction_id uuid
)
returns boolean ...
-- true when inspection_assignments has a row for auth.uid() matching either parent FK
```

Until `inspection_assignments` ships, technician and housekeeper occupancy `SELECT` policies are not enabled. Managers complete inspections directly in the move-in/move-out wizards.

### 3.3 Subscription RLS Matrix

Row-level grants for Phase 2.5 subscription tables — implementation phase: [06-implementation-roadmap.md](./06-implementation-roadmap.md) §5. Schema: [03-database-schema.md](./03-database-schema.md) §4.10. `✓` = allowed, `—` = denied. **Subscription limits are never enforced in RLS** — see §6.3.

#### `subscription_plans`

| Role | SELECT | INSERT | UPDATE | DELETE |
|---|---|:---:|:---:|:---:|
| Platform Admin | ✓† | ✓† | ✓† | ✓† |
| Owner | ✓ | — | — | — |
| Manager | ✓ | — | — | — |
| Technician | — | — | — | — |
| Housekeeper | — | — | — | — |
| Tenant | — | — | — | — |

#### `organization_subscriptions`

| Role | SELECT | INSERT | UPDATE | DELETE |
|---|---|:---:|:---:|:---:|
| Platform Admin | ✓† | ✓† | ✓† | ✓† |
| Owner | ✓ | ✓ | ✓ | ✓ |
| Manager | ✓‡ | — | — | — |
| Technician | — | — | — | — |
| Housekeeper | — | — | — | — |
| Tenant | — | — | — | — |

#### `usage_counters`

| Role | SELECT | INSERT | UPDATE | DELETE |
|---|---|:---:|:---:|:---:|
| Platform Admin | ✓† | ✓† | ✓† | ✓† |
| Owner | ✓ | — | — | — |
| Manager | ✓‡ | — | — | — |
| Technician | — | — | — | — |
| Housekeeper | — | — | — | — |
| Tenant | — | — | — | — |

Footnotes:

- †Platform admin DML uses service-role endpoints only — no authenticated RLS policies grant platform admin access.
- ‡Manager `SELECT` uses `is_org_owner(organization_id)` or `has_property_role(any_property_in_org, 'manager')` — any active manager membership in the organization.
- Owner predicates use `is_org_owner(organization_id)` on the row's `organization_id`.
- `usage_counters` rows are mutated only by SECURITY DEFINER helpers called from Server Actions — authenticated users have no direct `INSERT`/`UPDATE`/`DELETE`.

## 4. Active Membership Context

The UI must expose a property/role switcher when a user has more than one active membership. The selected membership controls route namespace and default property filters.

Recommended cookie:

| Cookie | Purpose |
|---|---|
| `habio-active-membership` | HMAC-signed payload containing `user_id`, `membership_id`, `role`, `organization_id`, `property_id`, and short expiry |

The cookie is a cache, not an authority. RLS still decides data access, and server actions must re-check membership state for writes.

## 5. Route Guard

Role routes:

| Role | URL prefix |
|---|---|
| `owner` | `/owner/...` |
| `manager` | `/manager/...` |
| `technician` | `/technician/...` |
| `housekeeper` | `/housekeeper/...` |
| `tenant` | `/tenant/...` |

Middleware flow (fast path validates a single membership by primary key; full membership list loads only on cache miss):

```typescript
export async function middleware(request: NextRequest) {
  const response = await updateSession(request)
  const userId = await readUserIdFromClaims(request)

  if (!userId) {
    return NextResponse.redirect(new URL('/auth/login', request.url))
  }

  const activeCookie = await parseActiveMembershipCookie(request)
  if (!activeCookie || activeCookie.userId !== userId) {
    return NextResponse.redirect(new URL('/select-membership', request.url))
  }

  const valid = await validateMembershipById(activeCookie.membershipId, userId)
  if (!valid) {
    return NextResponse.redirect(new URL('/select-membership', request.url))
  }

  const requestedRole = roleFromPath(request.nextUrl.pathname)
  if (requestedRole && requestedRole !== activeCookie.role) {
    return NextResponse.redirect(new URL(`/${activeCookie.role}/dashboard`, request.url))
  }

  return response
}
```

`loadActiveMemberships(userId)` runs only on `/select-membership` and after an explicit context switch — not on every authenticated request. `validateMembershipById` is a single primary-key lookup and stays `O(1)` regardless of how many memberships the user holds.

Public routes include `/auth/login`, `/auth/register`, `/auth/callback`, `/auth/invite/[token]`, `/auth/activate/[token]`, and webhook endpoints such as `/api/webhooks/line`.

## 6. Supabase RLS Strategy

### 6.1 Helper Functions

Use helper functions to centralize membership checks and avoid policy duplication.

```sql
create function public.is_org_owner(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.memberships m
    where m.user_id = (select auth.uid())
      and m.organization_id = p_org_id
      and m.property_id is null
      and m.role = 'owner'
      and m.deactivated_at is null
  );
$$;

create function public.has_property_role(p_property_id uuid, p_role membership_role)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.memberships m
    where m.user_id = (select auth.uid())
      and m.property_id = p_property_id
      and m.role = p_role
      and m.deactivated_at is null
  );
$$;

create function public.can_access_property(p_property_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.properties p
    where p.id = p_property_id
      and (
        public.is_org_owner(p.organization_id)
        or exists (
          select 1 from public.memberships m
          where m.user_id = (select auth.uid())
            and m.property_id = p_property_id
            and m.deactivated_at is null
        )
      )
  );
$$;
```

`SECURITY DEFINER` helpers are used to avoid recursive RLS lookups on `memberships`. They must include an `auth.uid()` predicate, use a fixed `search_path`, and have explicit execute grants reviewed in migration.

`can_access_property` is for one-time Server Action permission checks only. Do not use it in row-level `USING` clauses — it joins `properties` and calls `is_org_owner` per row. RLS policies should inline `is_org_owner(organization_id)` and `has_property_role(property_id, ...)` against denormalized scope columns instead.

### 6.2 Policy Patterns

`memberships`:

```sql
create policy "members can view own memberships"
on public.memberships
for select
to authenticated
using (user_id = (select auth.uid()));

create policy "owners can view org memberships"
on public.memberships
for select
to authenticated
using (public.is_org_owner(organization_id));
```

`properties`:

```sql
create policy "members can view accessible properties"
on public.properties
for select
to authenticated
using (
  public.is_org_owner(organization_id)
  or exists (
    select 1 from public.memberships m
    where m.user_id = (select auth.uid())
      and m.property_id = properties.id
      and m.deactivated_at is null
  )
);
```

`rooms`:

```sql
create policy "members can view scoped rooms"
on public.rooms
for select
to authenticated
using (
  public.is_org_owner(
    (select p.organization_id from public.properties p where p.id = property_id)
  )
  or exists (
    select 1 from public.memberships m
    where m.user_id = (select auth.uid())
      and m.property_id = rooms.property_id
      and m.deactivated_at is null
  )
  or exists (
    select 1
    from public.tenant_profiles tp
    where tp.user_id = (select auth.uid())
      and tp.room_id = rooms.id
      and tp.lease_status = 'active'
      and tp.archived_at is null
  )
);
```

`invitations`:

```sql
create policy "owners and managers can create invitations"
on public.invitations
for insert
to authenticated
with check (
  public.is_org_owner(organization_id)
  or public.has_property_role(property_id, 'manager')
);
```

`tenant_profiles`:

```sql
create policy "tenant profile scoped read"
on public.tenant_profiles
for select
to authenticated
using (
  user_id = (select auth.uid())
  or public.is_org_owner(organization_id)
  or public.has_property_role(property_id, 'manager')
);
```

`bills`:

```sql
create policy "bill scoped read"
on public.bills
for select
to authenticated
using (
  public.is_org_owner(organization_id)
  or public.has_property_role(property_id, 'manager')
  or exists (
    select 1 from public.tenant_profiles tp
    where tp.id = bills.tenant_profile_id
      and tp.user_id = (select auth.uid())
  )
);
```

`maintenance_tickets`:

```sql
create policy "maintenance scoped read"
on public.maintenance_tickets
for select
to authenticated
using (
  public.is_org_owner(organization_id)
  or public.has_property_role(property_id, 'manager')
  or assigned_to = (select auth.uid())
  or exists (
    select 1 from public.tenant_profiles tp
    where tp.id = maintenance_tickets.tenant_profile_id
      and tp.user_id = (select auth.uid())
  )
);
```

`billing_periods`:

```sql
create policy "billing period scoped read"
on public.billing_periods
for select
to authenticated
using (
  public.is_org_owner(organization_id)
  or public.has_property_role(property_id, 'manager')
);
```

`meter_readings`:

```sql
create policy "meter reading scoped read"
on public.meter_readings
for select
to authenticated
using (
  public.is_org_owner(organization_id)
  or public.has_property_role(property_id, 'manager')
  or public.has_property_role(property_id, 'housekeeper')
);
```

`housekeeping_tasks`:

```sql
create policy "housekeeping scoped read"
on public.housekeeping_tasks
for select
to authenticated
using (
  public.is_org_owner(organization_id)
  or public.has_property_role(property_id, 'manager')
  or assigned_to = (select auth.uid())
);
```

`move_in_transactions`:

```sql
create policy "move in scoped read"
on public.move_in_transactions
for select
to authenticated
using (
  public.is_org_owner(organization_id)
  or public.has_property_role(property_id, 'manager')
  or exists (
    select 1 from public.tenant_profiles tp
    where tp.id = move_in_transactions.tenant_profile_id
      and tp.user_id = (select auth.uid())
  )
  -- Technician/housekeeper: add OR is_assigned_to_inspection(id, null)
  -- after inspection_assignments table ships (see §3.2)
);

create policy "owners and managers manage move in"
on public.move_in_transactions
for all
to authenticated
using (
  public.is_org_owner(organization_id)
  or public.has_property_role(property_id, 'manager')
)
with check (
  public.is_org_owner(organization_id)
  or public.has_property_role(property_id, 'manager')
);
```

`move_out_transactions`:

```sql
create policy "move out scoped read"
on public.move_out_transactions
for select
to authenticated
using (
  public.is_org_owner(organization_id)
  or public.has_property_role(property_id, 'manager')
  or exists (
    select 1 from public.tenant_profiles tp
    where tp.id = move_out_transactions.tenant_profile_id
      and tp.user_id = (select auth.uid())
  )
  -- Technician/housekeeper: add OR is_assigned_to_inspection(null, id)
);

create policy "owners and managers manage move out"
on public.move_out_transactions
for all
to authenticated
using (
  public.is_org_owner(organization_id)
  or public.has_property_role(property_id, 'manager')
)
with check (
  public.is_org_owner(organization_id)
  or public.has_property_role(property_id, 'manager')
);
```

`inspection_items`:

```sql
create policy "inspection item scoped read"
on public.inspection_items
for select
to authenticated
using (
  public.is_org_owner(organization_id)
  or exists (
    select 1 from public.move_in_transactions mit
    where mit.id = inspection_items.move_in_transaction_id
      and public.has_property_role(mit.property_id, 'manager')
  )
  or exists (
    select 1 from public.move_out_transactions mot
    where mot.id = inspection_items.move_out_transaction_id
      and public.has_property_role(mot.property_id, 'manager')
  )
  or exists (
    select 1 from public.move_in_transactions mit
    join public.tenant_profiles tp on tp.id = mit.tenant_profile_id
    where mit.id = inspection_items.move_in_transaction_id
      and tp.user_id = (select auth.uid())
  )
  or exists (
    select 1 from public.move_out_transactions mot
    join public.tenant_profiles tp on tp.id = mot.tenant_profile_id
    where mot.id = inspection_items.move_out_transaction_id
      and tp.user_id = (select auth.uid())
  )
);

create policy "owners and managers manage inspection items"
on public.inspection_items
for all
to authenticated
using (
  public.is_org_owner(organization_id)
  or exists (
    select 1 from public.move_in_transactions mit
    where mit.id = inspection_items.move_in_transaction_id
      and public.has_property_role(mit.property_id, 'manager')
  )
  or exists (
    select 1 from public.move_out_transactions mot
    where mot.id = inspection_items.move_out_transaction_id
      and public.has_property_role(mot.property_id, 'manager')
  )
)
with check (
  public.is_org_owner(organization_id)
  or exists (
    select 1 from public.move_in_transactions mit
    where mit.id = inspection_items.move_in_transaction_id
      and public.has_property_role(mit.property_id, 'manager')
  )
  or exists (
    select 1 from public.move_out_transactions mot
    where mot.id = inspection_items.move_out_transaction_id
      and public.has_property_role(mot.property_id, 'manager')
  )
);
```

`meter_snapshots`:

```sql
create policy "meter snapshot scoped read"
on public.meter_snapshots
for select
to authenticated
using (
  public.is_org_owner(organization_id)
  or public.has_property_role(property_id, 'manager')
  or exists (
    select 1 from public.move_in_transactions mit
    join public.tenant_profiles tp on tp.id = mit.tenant_profile_id
    where mit.id = meter_snapshots.move_in_transaction_id
      and tp.user_id = (select auth.uid())
  )
  or exists (
    select 1 from public.move_out_transactions mot
    join public.tenant_profiles tp on tp.id = mot.tenant_profile_id
    where mot.id = meter_snapshots.move_out_transaction_id
      and tp.user_id = (select auth.uid())
  )
);

create policy "owners and managers insert meter snapshots"
on public.meter_snapshots
for insert
to authenticated
with check (
  public.is_org_owner(organization_id)
  or public.has_property_role(property_id, 'manager')
);
```

No `UPDATE` or `DELETE` policies on `meter_snapshots`. Schema-level `REVOKE UPDATE, DELETE` on `meter_snapshots` from `authenticated` is required (see `03-database-schema.md` §4.9.3).

`subscription_plans`:

```sql
create policy "authenticated can read subscription plans"
on public.subscription_plans
for select
to authenticated
using (true);
```

Public plan catalog — all authenticated users may read available plans. `INSERT`/`UPDATE`/`DELETE` are service-role only (platform admin seeding and plan management).

`organization_subscriptions`:

```sql
create policy "owners and managers can view org subscription"
on public.organization_subscriptions
for select
to authenticated
using (
  public.is_org_owner(organization_id)
  or exists (
    select 1 from public.memberships m
    where m.user_id = (select auth.uid())
      and m.organization_id = organization_subscriptions.organization_id
      and m.role = 'manager'
      and m.deactivated_at is null
  )
);

create policy "owners manage org subscription"
on public.organization_subscriptions
for all
to authenticated
using (public.is_org_owner(organization_id))
with check (public.is_org_owner(organization_id));
```

`usage_counters`:

```sql
create policy "owners and managers can view usage counters"
on public.usage_counters
for select
to authenticated
using (
  public.is_org_owner(organization_id)
  or exists (
    select 1 from public.memberships m
    where m.user_id = (select auth.uid())
      and m.organization_id = usage_counters.organization_id
      and m.role = 'manager'
      and m.deactivated_at is null
  )
);
```

No `INSERT`/`UPDATE`/`DELETE` policies for authenticated on `usage_counters`. Counter mutations run through SECURITY DEFINER helpers (`check_and_increment_usage`, etc.) called from Server Actions only.

### 6.3 Cross-Organization Isolation

Every policy must satisfy one of these predicates:

- Ownership through `memberships(role = 'owner', organization_id = row.organization_id)`.
- Property membership through `memberships(property_id = row.property_id)`.
- Direct user ownership for personal rows such as `profiles`, `notifications`, `line_connections`, or a tenant's own `tenant_profiles`.

Never authorize by email domain, user metadata, current route, or client-selected organization IDs.

**Subscription limits are never enforced in RLS.** Plan limits (`max_properties`, `max_rooms`) and feature gates (`is_feature_enabled`) are checked exclusively in Server Actions and SECURITY DEFINER RPCs. RLS policies on subscription tables grant read access to owners and managers and write access to owners (or service role for platform admin) — they do not block property or room creation based on plan limits. See [03-database-schema.md](./03-database-schema.md) §4.10.5 and [06-implementation-roadmap.md](./06-implementation-roadmap.md) §5.

## 7. Server Action Rules

- Owner signup is the only direct registration flow that creates an organization.
- Manager, technician, and housekeeper creation requires a valid pending invitation.
- Tenant creation is manager-driven and creates an activation invitation tied to room/lease data.
- Assignment actions must verify the assignee has the right active membership for the target property.
- Move-in and move-out completion must run through `complete_move_in` / `complete_move_out` RPCs so transaction, inspection items, meter snapshots, and lease status change atomically.
- Writes that create multiple related rows should run in one database transaction or RPC.

## 8. Risks and Recommendations

- RLS recursion: membership policies that query `memberships` directly can recurse. Use audited helper functions.
- RLS performance: do not use `can_access_property` in row-level `USING` clauses; inline `is_org_owner(organization_id)` against denormalized columns.
- Cookie staleness: active membership cookies must be short-lived and revalidated via `validateMembershipById` after membership changes.
- Invitation theft: store `token_hash`, set a TTL, mark tokens single-use, and avoid logging raw tokens.
- Multi-role UX: users need an explicit role/property switcher before entering role dashboards.
- Deactivation: use `deactivated_at` on memberships instead of deleting rows; last-owner deactivation is blocked by trigger.
- Co-ownership: schema supports multiple owners but product rules for transfer and primary billing contact are undecided (see OQ-07 in `07-risks-and-decisions.md`).
- Tests: add pgTAP coverage for cross-org denial, cross-property denial, multi-role access, invitation acceptance, revocation, last-owner guard, tenant self-service limits, occupancy transaction isolation, meter snapshot immutability, and inspection-assignment conditional reads.
- Occupancy immutability: `meter_snapshots` must remain INSERT-only; void transactions via `status`, not `DELETE`.
