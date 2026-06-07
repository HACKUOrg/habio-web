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
| `manager` | Property | Owner invitation | Manages assigned properties, rooms, tenants, billing, tasks, and maintenance |
| `technician` | Property | Owner or manager invitation | Handles assigned maintenance jobs in assigned properties |
| `housekeeper` | Property | Owner or manager invitation | Handles assigned cleaning tasks and meter readings |
| `tenant` | Property and room | Manager activation flow | Views own room, bills, and requests maintenance |

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
| Notifications | R/U own | R/U own | R/U own | R/U own | R/U own |
| Profiles | R org users | R assigned-property users | R own | R own | R own |

Legend: C = create, R = read, U = update, D = delete, - = no access.

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

### 6.3 Cross-Organization Isolation

Every policy must satisfy one of these predicates:

- Ownership through `memberships(role = 'owner', organization_id = row.organization_id)`.
- Property membership through `memberships(property_id = row.property_id)`.
- Direct user ownership for personal rows such as `profiles`, `notifications`, `line_connections`, or a tenant's own `tenant_profiles`.

Never authorize by email domain, user metadata, current route, or client-selected organization IDs.

## 7. Server Action Rules

- Owner signup is the only direct registration flow that creates an organization.
- Manager, technician, and housekeeper creation requires a valid pending invitation.
- Tenant creation is manager-driven and creates an activation invitation tied to room/lease data.
- Assignment actions must verify the assignee has the right active membership for the target property.
- Writes that create multiple related rows should run in one database transaction or RPC.

## 8. Risks and Recommendations

- RLS recursion: membership policies that query `memberships` directly can recurse. Use audited helper functions.
- RLS performance: do not use `can_access_property` in row-level `USING` clauses; inline `is_org_owner(organization_id)` against denormalized columns.
- Cookie staleness: active membership cookies must be short-lived and revalidated via `validateMembershipById` after membership changes.
- Invitation theft: store `token_hash`, set a TTL, mark tokens single-use, and avoid logging raw tokens.
- Multi-role UX: users need an explicit role/property switcher before entering role dashboards.
- Deactivation: use `deactivated_at` on memberships instead of deleting rows; last-owner deactivation is blocked by trigger.
- Co-ownership: schema supports multiple owners but product rules for transfer and primary billing contact are undecided (see OQ-07 in `07-risks-and-decisions.md`).
- Tests: add pgTAP coverage for cross-org denial, cross-property denial, multi-role access, invitation acceptance, revocation, last-owner guard, and tenant self-service limits.
