# 03 - Database Schema

## 1. Design Principles

- Supabase Auth owns identity in `auth.users`; Habio owns application profile and authorization data in `public`.
- Do not store roles on users. `profiles` contains display/contact data only.
- `memberships` is the single source of truth for access. A user may hold multiple roles across properties and organizations.
- `organization_id` scopes every membership and invitation. `property_id` is nullable only for organization-level owner access.
- Non-owner accounts are created through invitations or activation links. Managers, technicians, housekeepers, and tenants cannot self-register into an organization.
- `organization_id` and `property_id` are denormalized on operational tables so RLS can filter by org and property without deep joins.
- Tenant lease metadata lives in `tenant_profiles`; tenant authorization lives in the matching tenant membership.
- Use soft deactivation (`deactivated_at`, `archived_at`) for access and lease history instead of deleting business records.
- Every mutable table has `created_at` and `updated_at`; `updated_at` is maintained by trigger.
- All public tables exposed through Supabase APIs must have RLS enabled.

## 2. Entity Relationship Diagram

```mermaid
erDiagram
    auth_users {
        uuid id PK
        text email
    }

    profiles {
        uuid id PK
        text full_name
        text phone
        text avatar_url
        timestamptz created_at
        timestamptz updated_at
    }

    organizations {
        uuid id PK
        text name
        text slug
        text plan
        timestamptz created_at
        timestamptz updated_at
    }

    memberships {
        uuid id PK
        uuid user_id FK
        uuid organization_id FK
        uuid property_id FK
        text role
        uuid created_by FK
        timestamptz deactivated_at
        timestamptz created_at
    }

    invitations {
        uuid id PK
        uuid organization_id FK
        uuid property_id FK
        text email
        text role
        text token_hash
        text status
        timestamptz expires_at
        uuid invited_by FK
        timestamptz accepted_at
        timestamptz created_at
    }

    properties {
        uuid id PK
        uuid organization_id FK
        text name
        text address
        text phone
        text status
        text description
        timestamptz created_at
        timestamptz updated_at
    }

    buildings {
        uuid id PK
        uuid property_id FK
        text name
        int total_floors
        timestamptz created_at
        timestamptz updated_at
    }

    rooms {
        uuid id PK
        uuid property_id FK
        uuid building_id FK
        text room_number
        int floor
        text room_type
        text status
        numeric monthly_rate
        timestamptz archived_at
        timestamptz created_at
        timestamptz updated_at
    }

    tenant_profiles {
        uuid id PK
        uuid user_id FK
        uuid membership_id FK
        uuid organization_id FK
        uuid property_id FK
        uuid room_id FK
        date lease_start
        date lease_end
        text lease_status
        timestamptz archived_at
    }

    billing_periods {
        uuid id PK
        uuid organization_id FK
        uuid property_id FK
        text name
        date start_date
        date end_date
        text status
    }

    meter_readings {
        uuid id PK
        uuid billing_period_id FK
        uuid organization_id FK
        uuid room_id FK
        uuid property_id FK
        uuid submitted_by FK
        uuid approved_by FK
        text status
    }

    bills {
        uuid id PK
        uuid tenant_profile_id FK
        uuid property_id FK
        uuid organization_id FK
        uuid room_id FK
        uuid billing_period_id FK
        numeric total_amount
        text status
    }

    maintenance_tickets {
        uuid id PK
        uuid property_id FK
        uuid organization_id FK
        uuid room_id FK
        uuid tenant_profile_id FK
        uuid assigned_to FK
        text status
    }

    housekeeping_tasks {
        uuid id PK
        uuid organization_id FK
        uuid property_id FK
        uuid room_id FK
        uuid assigned_to FK
        uuid created_by FK
        text status
    }

    move_in_transactions {
        uuid id PK
        uuid organization_id FK
        uuid property_id FK
        uuid room_id FK
        uuid tenant_profile_id FK
        date move_in_date
        text status
        numeric security_deposit
        numeric advance_rent
        numeric electric_meter_start
        numeric water_meter_start
        uuid created_by FK
        timestamptz created_at
    }

    move_out_transactions {
        uuid id PK
        uuid organization_id FK
        uuid property_id FK
        uuid room_id FK
        uuid tenant_profile_id FK
        uuid move_in_transaction_id FK
        date move_out_date
        text status
        numeric deposit_refund
        uuid settled_by FK
        timestamptz settled_at
        uuid created_by FK
        timestamptz created_at
    }

    meter_snapshots {
        uuid id PK
        uuid organization_id FK
        uuid property_id FK
        uuid room_id FK
        text snapshot_type
        uuid move_in_transaction_id FK
        uuid move_out_transaction_id FK
        numeric electric_reading
        numeric water_reading
        date reading_date
        uuid submitted_by FK
        timestamptz created_at
    }

    inspection_items {
        uuid id PK
        uuid organization_id FK
        uuid move_in_transaction_id FK
        uuid move_out_transaction_id FK
        text item_name
        text status
        int sort_order
        uuid created_by FK
        timestamptz created_at
    }

    user_identities {
        uuid id PK
        uuid user_id FK
        text provider
        text provider_user_id
        timestamptz linked_at
        timestamptz last_login_at
    }

    notifications {
        uuid id PK
        uuid organization_id FK
        uuid user_id FK
        text event_type
        text title
        text body
        jsonb metadata
        timestamptz read_at
        timestamptz created_at
    }

    notification_deliveries {
        uuid id PK
        uuid notification_id FK
        text channel
        text status
        timestamptz sent_at
        text error
        timestamptz created_at
    }

    subscription_plans {
        uuid id PK
        text name
        integer max_properties
        integer max_rooms
        jsonb features
        timestamptz created_at
    }

    organization_subscriptions {
        uuid id PK
        uuid organization_id FK
        uuid plan_id FK
        text status
        text billing_cycle
        date current_period_start
        date current_period_end
        timestamptz trial_ends_at
        timestamptz cancelled_at
    }

    usage_counters {
        uuid organization_id FK
        text metric
        integer count
        timestamptz updated_at
    }

    auth_users ||--|| profiles : "extends"
    auth_users ||--o{ user_identities : "has"
    profiles ||--o{ memberships : "holds"
    organizations ||--o{ memberships : "scopes"
    properties ||--o{ memberships : "scopes"
    organizations ||--o{ invitations : "issues"
    properties ||--o{ invitations : "targets"
    organizations ||--o{ properties : "owns"
    properties ||--o{ buildings : "contains"
    buildings ||--o{ rooms : "contains"
    properties ||--o{ rooms : "contains"
    profiles ||--o{ tenant_profiles : "has"
    memberships ||--|| tenant_profiles : "authorizes"
    rooms ||--o{ tenant_profiles : "leases"
    tenant_profiles ||--o{ bills : "receives"
    tenant_profiles ||--o| move_in_transactions : "move_in"
    tenant_profiles ||--o| move_out_transactions : "move_out"
    move_in_transactions ||--o| move_out_transactions : "settles"
    move_in_transactions ||--|| meter_snapshots : "meters_at"
    move_out_transactions ||--|| meter_snapshots : "meters_at"
    move_in_transactions ||--o{ inspection_items : "checklists"
    move_out_transactions ||--o{ inspection_items : "checklists"
    organizations ||--o{ move_in_transactions : "scopes"
    organizations ||--o{ move_out_transactions : "scopes"
    properties ||--o{ move_in_transactions : "hosts"
    properties ||--o{ move_out_transactions : "hosts"
    rooms ||--o{ move_in_transactions : "handover"
    rooms ||--o{ move_out_transactions : "return"
    rooms ||--o{ maintenance_tickets : "reported_for"
    tenant_profiles ||--o{ maintenance_tickets : "opened_by"
    properties ||--o{ housekeeping_tasks : "schedules"
    auth_users ||--o{ notifications : "receives"
    notifications ||--o{ notification_deliveries : "delivered_via"
    organizations ||--o| organization_subscriptions : "subscribes"
    subscription_plans ||--o{ organization_subscriptions : "governs"
    organizations ||--o{ usage_counters : "tracks"
```

## 3. Custom Types

```sql
create type membership_role as enum (
  'owner',
  'manager',
  'technician',
  'housekeeper',
  'tenant'
);

create type invitation_status as enum (
  'pending',
  'accepted',
  'expired',
  'revoked'
);

create type room_type as enum ('single', 'double', 'studio', 'suite');
create type room_status as enum ('available', 'occupied', 'maintenance');
create type lease_status as enum ('active', 'expiring', 'expired', 'terminated');
create type bill_status as enum ('draft', 'pending', 'paid', 'overdue');
create type ticket_priority as enum ('low', 'medium', 'high', 'urgent');
create type ticket_status as enum ('open', 'in_progress', 'resolved', 'closed');
create type task_status as enum ('pending', 'in_progress', 'completed', 'skipped');
create type property_status as enum ('active', 'inactive', 'archived');
create type billing_period_status as enum ('open', 'closed', 'archived');
create type meter_reading_status as enum ('pending', 'submitted', 'approved', 'rejected');
create type move_in_transaction_status as enum ('draft', 'completed', 'voided');
create type move_out_transaction_status as enum ('draft', 'settled', 'disputed', 'voided');
create type inspection_item_status as enum ('good', 'damaged', 'missing', 'needs_repair');
create type meter_snapshot_type as enum ('move_in', 'move_out');
```

## 4. Core Tables

### 4.1 `profiles`

```sql
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

`profiles` must not contain `role`, `organization_id`, or authorization claims. Reading role from `raw_user_meta_data` is forbidden because that metadata is user-controlled.

### 4.2 `organizations`

```sql
create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  plan text not null default 'free',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

Ownership is derived from `memberships(role = 'owner', property_id is null)`, not an `owner_id` column.

`organizations.plan` is a **denormalized cache** of the current plan name (e.g. `free`, `starter`). It is synced via trigger or Server Action when `organization_subscriptions.plan_id` changes so Server Components can display the plan without joining subscription tables. The authoritative subscription state lives in `organization_subscriptions` — see §4.10.

### 4.3 `properties`

```sql
create table public.properties (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  name text not null,
  address text not null,
  phone text,
  status property_status not null default 'active',
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_properties_organization_id on public.properties (organization_id);
create index idx_properties_status on public.properties (organization_id, status);
```

Managers are assigned through property-scoped memberships. A property may have multiple managers.

### 4.4 `memberships`

```sql
create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  property_id uuid references public.properties(id) on delete cascade,
  role membership_role not null,
  created_by uuid references public.profiles(id) on delete set null,
  deactivated_at timestamptz,
  created_at timestamptz not null default now(),
  constraint memberships_scope_check check (
    (role = 'owner' and property_id is null)
    or (role <> 'owner' and property_id is not null)
  )
);

-- PostgreSQL treats NULL != NULL in table-level UNIQUE constraints, so owner rows
-- (property_id IS NULL) are not deduplicated by a single composite unique.
-- Use partial unique indexes instead:
create unique index memberships_owner_unique
  on public.memberships (user_id, organization_id)
  where role = 'owner' and property_id is null and deactivated_at is null;

create unique index memberships_property_role_unique
  on public.memberships (user_id, organization_id, property_id, role)
  where property_id is not null and deactivated_at is null;

create index idx_memberships_user_active
  on public.memberships (user_id, role, organization_id, property_id)
  where deactivated_at is null;

create index idx_memberships_org_role
  on public.memberships (organization_id, role)
  where deactivated_at is null;

create index idx_memberships_property_role
  on public.memberships (property_id, role)
  where deactivated_at is null;

create index idx_memberships_created_by
  on public.memberships (created_by);
```

Role scoping:

| Role | Scope | `property_id` | Notes |
|---|---|---:|---|
| `owner` | Organization | null | Full organization access |
| `manager` | Property | required | One row per managed property |
| `technician` | Property | required | May belong to multiple properties |
| `housekeeper` | Property | required | May belong to multiple properties |
| `tenant` | Property | required | Lease details live in `tenant_profiles` |

### 4.5 `invitations`

```sql
create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  property_id uuid references public.properties(id) on delete cascade,
  email citext not null,
  role membership_role not null check (role in ('manager', 'technician', 'housekeeper', 'tenant')),
  token_hash text not null unique,
  status invitation_status not null default 'pending',
  expires_at timestamptz not null,
  invited_by uuid not null references public.profiles(id) on delete restrict,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  -- All invited roles are property-scoped; org-level invites are not supported.
  constraint invitations_property_scope_check check (property_id is not null)
);

create index idx_invitations_email_status on public.invitations (lower(email), status);
create index idx_invitations_org_status on public.invitations (organization_id, status, created_at desc);
create index idx_invitations_property_role on public.invitations (property_id, role, status);
```

Store a hash of the token, not the raw token. The raw token should exist only in the email link and in memory during validation.

### 4.6 `buildings` and `rooms`

```sql
create table public.buildings (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  name text not null,
  total_floors integer not null default 1 check (total_floors >= 1),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (property_id, name)
);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  property_id uuid not null references public.properties(id) on delete cascade,
  building_id uuid not null references public.buildings(id) on delete restrict,
  room_number text not null,
  floor integer not null default 1,
  room_type room_type not null default 'single',
  status room_status not null default 'available',
  monthly_rate numeric(10, 2) not null check (monthly_rate >= 0),
  notes text,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (building_id, room_number)
);
```

`rooms.property_id` is denormalized from `buildings.property_id` for RLS and list query performance.

### 4.7 `tenant_profiles`

```sql
create table public.tenant_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete restrict,
  membership_id uuid not null references public.memberships(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  property_id uuid not null references public.properties(id) on delete restrict,
  room_id uuid not null references public.rooms(id) on delete restrict,
  lease_start date not null,
  lease_end date,
  lease_status lease_status not null default 'active',
  emergency_contact_name text,
  emergency_contact_phone text,
  notes text,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (membership_id)
);

create index idx_tenant_profiles_user_id on public.tenant_profiles (user_id);
create index idx_tenant_profiles_organization_id on public.tenant_profiles (organization_id);
create index idx_tenant_profiles_property_id on public.tenant_profiles (property_id);
create index idx_tenant_profiles_room_id on public.tenant_profiles (room_id);
create index idx_tenant_profiles_lease_status on public.tenant_profiles (property_id, lease_status);

create unique index tenant_profiles_one_active_per_room
  on public.tenant_profiles (room_id)
  where lease_status = 'active' and archived_at is null;
```

A tenant activation accepts an invitation, creates a tenant membership, creates the tenant profile, and marks the room occupied in one transaction.

### 4.8 `user_identities`

Stores provider-specific identity records for each user. One row per linked provider. Supports email, LINE, and future providers (Google, Apple) without schema changes.

```sql
create table public.user_identities (
  id               uuid        primary key default gen_random_uuid(),
  user_id          uuid        not null references auth.users(id) on delete cascade,
  provider         text        not null
                               check (provider in ('email','line','google','apple')),
  provider_user_id text        not null,
  linked_at        timestamptz not null default now(),
  last_login_at    timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (provider, provider_user_id)
);

create index on public.user_identities (user_id);
```

RLS:
- Users can read and manage their own identity rows.
- Owners can read identity rows for members of their organization (for LINE verification status display).
- No cross-user writes permitted.

Identity rows are inert without a matching membership. Removing an identity row does not affect membership. Deactivating a membership does not remove identity rows.

### 4.9 Occupancy Transaction Tables

Move-in and move-out transactions are the authoritative handover and settlement records for a tenancy. RLS grants per role: [04-rbac.md](./04-rbac.md) §3.1. They are separate from operational `meter_readings` (Phase 4 billing approval). `meter_snapshots` captured here are immutable; start/end readings are denormalized onto the parent transaction for list views.

#### 4.9.1 `move_in_transactions`

```sql
create table public.move_in_transactions (
  id                  uuid primary key default gen_random_uuid(),
  organization_id     uuid not null references public.organizations(id) on delete restrict,
  property_id         uuid not null references public.properties(id) on delete restrict,
  room_id             uuid not null references public.rooms(id) on delete restrict,
  tenant_profile_id   uuid not null references public.tenant_profiles(id) on delete restrict,
  move_in_date        date not null,
  status              move_in_transaction_status not null default 'draft',
  security_deposit    numeric(12, 2) not null default 0 check (security_deposit >= 0),
  advance_rent        numeric(12, 2) not null default 0 check (advance_rent >= 0),
  electric_meter_start numeric(12, 4) check (electric_meter_start is null or electric_meter_start >= 0),
  water_meter_start   numeric(12, 4) check (water_meter_start is null or water_meter_start >= 0),
  notes               text,
  created_by          uuid not null references public.profiles(id) on delete restrict,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (room_id, tenant_profile_id)
);

create index idx_move_in_transactions_org_created
  on public.move_in_transactions (organization_id, created_at desc);
create index idx_move_in_transactions_property_created
  on public.move_in_transactions (property_id, created_at desc);
create index idx_move_in_transactions_tenant_profile
  on public.move_in_transactions (tenant_profile_id);
create index idx_move_in_transactions_room
  on public.move_in_transactions (room_id);
create index idx_move_in_transactions_status
  on public.move_in_transactions (property_id, status)
  where status = 'draft';
```

`electric_meter_start` and `water_meter_start` are denormalized from the linked `meter_snapshots` row when a move-in is completed. Set them in the same transaction as the snapshot insert.

#### 4.9.2 `move_out_transactions`

```sql
create table public.move_out_transactions (
  id                      uuid primary key default gen_random_uuid(),
  organization_id         uuid not null references public.organizations(id) on delete restrict,
  property_id             uuid not null references public.properties(id) on delete restrict,
  room_id                 uuid not null references public.rooms(id) on delete restrict,
  tenant_profile_id       uuid not null references public.tenant_profiles(id) on delete restrict,
  move_in_transaction_id  uuid references public.move_in_transactions(id) on delete restrict,
  move_out_date           date not null,
  status                  move_out_transaction_status not null default 'draft',
  electric_meter_end      numeric(12, 4) check (electric_meter_end is null or electric_meter_end >= 0),
  water_meter_end         numeric(12, 4) check (water_meter_end is null or water_meter_end >= 0),
  damage_charge           numeric(12, 2) not null default 0 check (damage_charge >= 0),
  cleaning_fee            numeric(12, 2) not null default 0 check (cleaning_fee >= 0),
  other_deductions        numeric(12, 2) not null default 0 check (other_deductions >= 0),
  deposit_refund          numeric(12, 2) not null default 0 check (deposit_refund >= 0),
  notes                   text,
  settlement_notes        text,
  created_by              uuid not null references public.profiles(id) on delete restrict,
  settled_by              uuid references public.profiles(id) on delete set null,
  settled_at              timestamptz,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (tenant_profile_id)
);

create index idx_move_out_transactions_org_created
  on public.move_out_transactions (organization_id, created_at desc);
create index idx_move_out_transactions_property_created
  on public.move_out_transactions (property_id, created_at desc);
create index idx_move_out_transactions_tenant_profile
  on public.move_out_transactions (tenant_profile_id);
create index idx_move_out_transactions_room
  on public.move_out_transactions (room_id);
create index idx_move_out_transactions_move_in
  on public.move_out_transactions (move_in_transaction_id)
  where move_in_transaction_id is not null;
create index idx_move_out_transactions_status
  on public.move_out_transactions (property_id, status)
  where status in ('draft', 'disputed');
```

`electric_meter_end` and `water_meter_end` are denormalized from the linked `meter_snapshots` row when a move-out is settled. Hard deletes are forbidden; void disputed or draft rows via `status` instead.

#### 4.9.3 `meter_snapshots`

Immutable utility readings captured at move-in or move-out. One row per transaction. Operational `meter_readings` used in billing approval are a separate table.

```sql
create table public.meter_snapshots (
  id                      uuid primary key default gen_random_uuid(),
  organization_id         uuid not null references public.organizations(id) on delete restrict,
  property_id             uuid not null references public.properties(id) on delete restrict,
  room_id                 uuid not null references public.rooms(id) on delete restrict,
  snapshot_type           meter_snapshot_type not null,
  move_in_transaction_id  uuid references public.move_in_transactions(id) on delete restrict,
  move_out_transaction_id uuid references public.move_out_transactions(id) on delete restrict,
  electric_reading        numeric(12, 4) not null check (electric_reading >= 0),
  water_reading           numeric(12, 4) not null check (water_reading >= 0),
  reading_date            date not null,
  photo_url               text,
  submitted_by            uuid not null references public.profiles(id) on delete restrict,
  created_at              timestamptz not null default now(),
  constraint meter_snapshots_parent_xor check (
    (move_in_transaction_id is not null)::int
    + (move_out_transaction_id is not null)::int = 1
  ),
  constraint meter_snapshots_type_parent_match check (
    (snapshot_type = 'move_in' and move_in_transaction_id is not null)
    or (snapshot_type = 'move_out' and move_out_transaction_id is not null)
  )
);

create unique index meter_snapshots_one_per_move_in
  on public.meter_snapshots (move_in_transaction_id)
  where move_in_transaction_id is not null;

create unique index meter_snapshots_one_per_move_out
  on public.meter_snapshots (move_out_transaction_id)
  where move_out_transaction_id is not null;

create index idx_meter_snapshots_property_created
  on public.meter_snapshots (property_id, created_at desc);

revoke update, delete on public.meter_snapshots from authenticated;
```

#### 4.9.4 `inspection_items`

Checklist rows for a move-in or move-out handover. Property scope is resolved through the parent transaction.

```sql
create table public.inspection_items (
  id                      uuid primary key default gen_random_uuid(),
  organization_id         uuid not null references public.organizations(id) on delete restrict,
  move_in_transaction_id  uuid references public.move_in_transactions(id) on delete cascade,
  move_out_transaction_id uuid references public.move_out_transactions(id) on delete cascade,
  item_name               text not null,
  status                  inspection_item_status not null default 'good',
  notes                   text,
  photo_url               text,
  sort_order              integer not null default 0,
  created_by              uuid not null references public.profiles(id) on delete restrict,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint inspection_items_parent_xor check (
    (move_in_transaction_id is not null)::int
    + (move_out_transaction_id is not null)::int = 1
  )
);

create index idx_inspection_items_move_in
  on public.inspection_items (move_in_transaction_id)
  where move_in_transaction_id is not null;

create index idx_inspection_items_move_out
  on public.inspection_items (move_out_transaction_id)
  where move_out_transaction_id is not null;

create index idx_inspection_items_organization
  on public.inspection_items (organization_id);
```

#### 4.9.5 Occupancy integrity constraints

Org and property consistency triggers (same pattern as `validate_membership_org_consistency`) must verify that `organization_id`, `property_id`, and `room_id` on transaction and snapshot rows match the referenced `tenant_profiles` and `properties` rows at insert/update time.

Completion workflows run in SECURITY DEFINER RPCs (`complete_move_in`, `complete_move_out`) called from Server Actions — see [06-implementation-roadmap.md](./06-implementation-roadmap.md) §7 for phase deliverables and RPC behavior. Completing a move-in sets `tenant_profiles.lease_status = 'active'` (fires `sync_room_on_lease_change` and increments `usage_counters.active_tenants`). Settling a move-out sets `tenant_profiles.lease_status = 'terminated'` (decrements `active_tenants`).

### 4.10 Subscription Tables

Subscription and usage tables support org-wide plan limits and feature flags. RLS grants read access to owners and managers; **limit enforcement is never done in RLS** — see [04-rbac.md](./04-rbac.md) §6.3 and [06-implementation-roadmap.md](./06-implementation-roadmap.md) §5.

#### 4.10.1 `subscription_plans`

Catalog of available plans. `max_properties` and `max_rooms` are **org-wide totals** (not per-property). `null` means unlimited.

```sql
create table public.subscription_plans (
  id              uuid primary key default gen_random_uuid(),
  name            text not null unique,
  max_properties  integer,          -- null = unlimited
  max_rooms       integer,          -- null = unlimited (org-wide total)
  features        jsonb not null default '{}',
  created_at      timestamptz not null default now()
);
```

**Plan features (`plan_features`).** Feature flags are stored in `subscription_plans.features` jsonb — no separate `plan_features` table. MVP seed data uses `features = '{}'` (no flags enabled). Future premium tiers set boolean keys to `true` in the JSON.

| Feature key | Description | MVP value |
|---|---|---|
| `advanced_reports` | Advanced analytics and exports | false |
| `api_access` | REST/webhook API key management | false |
| `custom_branding` | Custom logo, colors, domain | false |
| `priority_support` | Dedicated support SLA | false |
| `multi_owner` | Multiple org-level owners | false |

All core operational features (Billing, Tenant Management, Move-In, Move-Out, Maintenance, Housekeeping, LINE Integration) are available on every plan. Plans differentiate on **scale only**.

#### 4.10.2 `organization_subscriptions`

One row per organization. Links an organization to its active plan and billing period.

```sql
create table public.organization_subscriptions (
  id                    uuid primary key default gen_random_uuid(),
  organization_id       uuid not null unique references public.organizations(id) on delete cascade,
  plan_id               uuid not null references public.subscription_plans(id),
  status                text not null default 'active'
                        check (status in ('active', 'trialing', 'past_due', 'cancelled')),
  billing_cycle         text not null default 'monthly'
                        check (billing_cycle in ('monthly', 'annual')),
  current_period_start  date not null,
  current_period_end    date not null,
  trial_ends_at         timestamptz,
  cancelled_at          timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index idx_organization_subscriptions_plan
  on public.organization_subscriptions (plan_id);
```

When `plan_id` changes, sync `organizations.plan` to the new plan name in the same transaction.

#### 4.10.3 `usage_counters`

Point-in-time state counters — one row per org per metric. No `period_start`; limit checks use current counts only.

```sql
create table public.usage_counters (
  organization_id  uuid not null references public.organizations(id) on delete cascade,
  metric           text not null
                   check (metric in ('active_properties', 'active_rooms', 'active_tenants')),
  count            integer not null default 0 check (count >= 0),
  updated_at       timestamptz not null default now(),
  primary key (organization_id, metric)
);
```

| Event | Counter | Direction | Phase |
|---|---|---|---|
| Property created | `active_properties` | +1 | 2 |
| Property archived | `active_properties` | −1 | 2 |
| Room created | `active_rooms` | +1 | 2 |
| Room archived | `active_rooms` | −1 | 2 |
| Tenant `lease_status` → `active` | `active_tenants` | +1 | 3 |
| Tenant `lease_status` → `terminated` | `active_tenants` | −1 | 3.5 |

`active_tenants` is tracked for analytics and occupancy insight but has **no plan limit enforced in MVP**. Counter mutations use `INSERT … ON CONFLICT DO UPDATE … RETURNING` for atomic updates.

#### 4.10.4 `is_feature_enabled()` helper

Called from Server Actions and SECURITY DEFINER RPCs — not from RLS policies.

```sql
create or replace function public.is_feature_enabled(p_org_id uuid, p_feature_key text)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce(
    (
      select (sp.features ->> p_feature_key)::boolean
      from public.organization_subscriptions os
      join public.subscription_plans sp on sp.id = os.plan_id
      where os.organization_id = p_org_id
        and os.status = 'active'
    ),
    false
  );
$$;
```

#### 4.10.5 Enforcement rules

- **Enforcement:** Server Actions and SECURITY DEFINER RPCs only. Never enforce subscription limits in RLS `USING` / `WITH CHECK` clauses. Never enforce in client-side code alone.
- **Atomic limit checks:** Combine counter increment and limit check in a single `UPDATE … WHERE count < max RETURNING` query to prevent TOCTOU races.
- **RLS scope:** [04-rbac.md](./04-rbac.md) §3.3 and §6.2 define read/write policies for subscription tables.
- **Implementation phase:** [06-implementation-roadmap.md](./06-implementation-roadmap.md) §5 (Phase 2.5).

## 5. Operational Tables

Operational tables keep their existing structure with these relationship updates:

| Table | Required scope columns | Authorization reference |
|---|---|---|
| `billing_periods` | `organization_id`, `property_id` | Owner or manager membership |
| `meter_readings` | `organization_id`, `property_id`, `room_id` | Owner/manager review; housekeeper property membership for submit |
| `bills` | `organization_id`, `property_id`, `room_id`, `tenant_profile_id` | Owner/manager; tenant owns matching tenant profile |
| `maintenance_tickets` | `organization_id`, `property_id`, `room_id`, `tenant_profile_id`, `assigned_to` | Tenant own tickets; manager property; assigned technician |
| `housekeeping_tasks` | `organization_id`, `property_id`, `room_id`, `assigned_to`, `created_by` | Manager property; assigned housekeeper |
| `move_in_transactions` | `organization_id`, `property_id`, `room_id`, `tenant_profile_id`, `created_by` | Owner org; manager property; tenant owns matching profile |
| `move_out_transactions` | `organization_id`, `property_id`, `room_id`, `tenant_profile_id`, `move_in_transaction_id`, `created_by`, `settled_by` | Owner org; manager property; tenant owns matching profile |
| `meter_snapshots` | `organization_id`, `property_id`, `room_id`, `submitted_by` | Owner/manager property; tenant own transaction; staff when assigned to inspection |
| `inspection_items` | `organization_id`, `created_by` | Owner org; manager property; tenant own parent transaction; staff when assigned to inspection |
| `tenant_profiles` | `organization_id`, `property_id`, `room_id`, `membership_id` | Owner/manager; tenant owns own profile |
| `notifications` | `organization_id`, `user_id` | User owns notification |
| `notification_deliveries` | via `notification_id` | User owns parent notification |
| `user_identities` | `user_id` | User owns identity rows; owners may read org-member identities |

`organization_id` is denormalized on every operational table that participates in org-level RLS or analytics. Set it from the parent property at insert time via trigger or Server Action; do not rely on joins at read time.

### `notifications`

Stores notifications channel-independently. Created by server-side business logic when a triggering event occurs.

```sql
create table public.notifications (
  id              uuid        primary key default gen_random_uuid(),
  organization_id uuid        not null references public.organizations(id),
  user_id         uuid        not null references auth.users(id),
  event_type      text        not null,
  title           text        not null,
  body            text,
  metadata        jsonb,
  read_at         timestamptz,
  created_at      timestamptz not null default now()
);

create index on public.notifications (user_id, created_at desc);
create index on public.notifications (organization_id);
```

Valid `event_type` values: `maintenance_ticket_assigned`, `maintenance_ticket_updated`, `housekeeping_task_assigned`, `bill_created`, `bill_due`, `tenant_activated`, `meter_reading_approved`.

### `notification_deliveries`

Tracks delivery state per channel for each notification. A single notification may have up to one delivery row per channel.

```sql
create table public.notification_deliveries (
  id              uuid        primary key default gen_random_uuid(),
  notification_id uuid        not null references public.notifications(id) on delete cascade,
  channel         text        not null
                              check (channel in ('in_app','email','line')),
  status          text        not null default 'pending'
                              check (status in ('pending','sent','failed','skipped')),
  sent_at         timestamptz,
  error           text,
  created_at      timestamptz not null default now(),
  unique (notification_id, channel)
);

create index on public.notification_deliveries (notification_id);
```

RLS: users can read `notifications` and `notification_deliveries` for their own `user_id`. No direct user writes; rows are created by server actions.

`property_staff` is removed. Assignment actions check that the target assignee has an active `technician` or `housekeeper` membership for the same `property_id`.

### `notifications`

Stores notifications channel-independently. Created by server-side business logic when a triggering event occurs.

```sql
create table public.notifications (
  id              uuid        primary key default gen_random_uuid(),
  organization_id uuid        not null references public.organizations(id),
  user_id         uuid        not null references auth.users(id),
  event_type      text        not null,
  title           text        not null,
  body            text,
  metadata        jsonb,
  read_at         timestamptz,
  created_at      timestamptz not null default now()
);

create index on public.notifications (user_id, created_at desc);
create index on public.notifications (organization_id);
```

Valid `event_type` values: `maintenance_ticket_assigned`, `maintenance_ticket_updated`, `housekeeping_task_assigned`, `bill_created`, `bill_due`, `tenant_activated`, `meter_reading_approved`.

### `notification_deliveries`

Tracks delivery state per channel for each notification. A single notification may have up to one delivery row per channel.

```sql
create table public.notification_deliveries (
  id              uuid        primary key default gen_random_uuid(),
  notification_id uuid        not null references public.notifications(id) on delete cascade,
  channel         text        not null
                              check (channel in ('in_app','email','line')),
  status          text        not null default 'pending'
                              check (status in ('pending','sent','failed','skipped')),
  sent_at         timestamptz,
  error           text,
  created_at      timestamptz not null default now(),
  unique (notification_id, channel)
);

create index on public.notification_deliveries (notification_id);
```

RLS: users can read `notifications` and `notification_deliveries` for their own `user_id`. No direct user writes; rows are created by server actions.

## 6. RLS Helper Functions

Policy helper functions should be small, indexed, and auditable. Use `(select auth.uid())` inside helper SQL, and avoid reading user-controlled JWT metadata for authorization.

```sql
create function public.is_org_owner(p_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.memberships m
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
    select 1
    from public.memberships m
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
    select 1
    from public.properties p
    where p.id = p_property_id
      and (
        public.is_org_owner(p.organization_id)
        or exists (
          select 1
          from public.memberships m
          where m.user_id = (select auth.uid())
            and m.property_id = p_property_id
            and m.deactivated_at is null
        )
      )
  );
$$;

create function public.is_staff_role(p_role membership_role)
returns boolean
language sql
immutable
as $$
  select p_role in ('owner', 'manager', 'technician', 'housekeeper');
$$;
```

`can_access_property` is for one-time Server Action permission checks. Do not use it in row-level `USING` clauses — it joins `properties` and calls `is_org_owner` per evaluation. RLS policies should inline `is_org_owner(organization_id)` and `has_property_role(property_id, ...)` against denormalized scope columns instead.

Because `security definer` bypasses RLS, revoke default `PUBLIC` execute grants where appropriate and grant only the roles that need the helper. Keep helpers in migrations and run Supabase advisors before release.

## 7. Triggers

```sql
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.email));
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();
```

Membership integrity:

```sql
create function public.validate_membership_org_consistency()
returns trigger language plpgsql as $$
begin
  if new.property_id is not null then
    if not exists (
      select 1 from public.properties p
      where p.id = new.property_id
        and p.organization_id = new.organization_id
    ) then
      raise exception 'property_id does not belong to organization_id';
    end if;
  end if;
  return new;
end;
$$;

create trigger memberships_org_consistency
before insert or update on public.memberships
for each row execute function public.validate_membership_org_consistency();

create function public.prevent_owner_orphan()
returns trigger language plpgsql as $$
begin
  if new.deactivated_at is not null and new.role = 'owner' then
    if not exists (
      select 1 from public.memberships
      where organization_id = new.organization_id
        and role = 'owner'
        and property_id is null
        and deactivated_at is null
        and id <> new.id
    ) then
      raise exception 'cannot deactivate the last owner of an organization';
    end if;
  end if;
  return new;
end;
$$;

create trigger memberships_prevent_owner_orphan
before update of deactivated_at on public.memberships
for each row execute function public.prevent_owner_orphan();
```

Room status sync should run from `tenant_profiles` lease changes:

```sql
create trigger sync_room_on_lease_change
after insert or update of lease_status on public.tenant_profiles
for each row execute function public.sync_room_status();
```

## 7.1 Archival Tables and pg_cron Jobs

High-volume tables need scheduled archival before they affect RLS scan cost and Realtime performance.

```sql
create table public.invitations_archive (
  like public.invitations including all
);

create table public.notifications_archive (
  like public.notifications including all
);

-- Move accepted and expired invitations older than 90 days
select cron.schedule(
  'archive-old-invitations',
  '0 3 * * 0',
  $$
    with moved as (
      delete from public.invitations
      where status in ('accepted', 'expired')
        and created_at < now() - interval '90 days'
      returning *
    )
    insert into public.invitations_archive select * from moved;
  $$
);

-- Move read notifications older than 90 days
select cron.schedule(
  'archive-old-notifications',
  '0 4 * * 0',
  $$
    with moved as (
      delete from public.notifications
      where read_at is not null
        and created_at < now() - interval '90 days'
      returning *
    )
    insert into public.notifications_archive select * from moved;
  $$
);
```

Schedule both jobs in Phase 0 or Phase 1 — not after launch. At 100,000 tenants, `invitations` and `notifications` grow by hundreds of thousands of rows per quarter without archival.

## 8. Migration Strategy

| Phase | Steps |
|---|---|
| Phase 0 — identity | Create `user_identities` with RLS; `handle_new_user` inserts `email` identity row on registration. |
| Phase 0 — notifications | Create `notifications` and `notification_deliveries` — schema only; no delivery logic. |
| Phase 3.5 — occupancy | Create `move_in_transactions`, `move_out_transactions`, `meter_snapshots`, and `inspection_items` with occupancy enums, indexes, org-consistency triggers, and `complete_move_in` / `complete_move_out` RPCs. Revoke UPDATE/DELETE on `meter_snapshots`. |
| Additive | Create `membership_role`, `invitation_status`, `memberships`, `invitations`, and `tenant_profiles`; add compatibility columns if needed. |
| Backfill | Convert `organization_members.scope = owner` to owner memberships; convert `properties.manager_id` to manager memberships; convert `property_staff` to technician/housekeeper memberships; convert `tenants` to tenant memberships and tenant profiles. |
| Enforce | Add NOT NULL, check constraints, partial unique indexes on memberships, org-consistency and last-owner triggers, and `organization_id` on operational tables. |
| Replace RLS | Replace old helpers with membership helpers. Enable RLS on new tables before exposing them through Supabase APIs. |
| Drop legacy shape | Drop `profiles.role`, `organization_members`, `property_staff`, `properties.manager_id`, and the old `tenants` table after verification. |
| Verify | Regenerate types, update seed data, and add pgTAP tests for cross-organization and cross-property denial. |

## 9. Security Grants

```sql
revoke insert, update, delete on all tables in schema public from anon;
```

Authenticated users may keep DML grants only where RLS policies provide row-level authorization. `invitations`, tenant activation, and membership creation should be performed by server-side actions that validate the caller and run inside transactions.
