# 07 — Risks & Technical Decisions

## 1. Architecture Decision Records (ADRs)

---

### ADR-001: Role stored in `profiles` table, not JWT claims

**Status**: Accepted

**Context**: Supabase Auth JWTs can embed custom claims. An alternative is to embed `role` in the JWT so middleware can read it without a database round-trip.

**Decision**: Store `role` in `public.profiles.role`. Read it in middleware via a server-side Supabase client after validating the session with `getClaims()`.

**Consequences**:
- (+) Role changes (e.g., promoting a user from tenant to manager) take effect immediately — no token rotation or re-login required
- (+) JWT payload stays small and does not need to be re-issued on every role change
- (+) RLS policies can use `current_user_role()` helper to read from `profiles`, keeping policies consistent with middleware logic
- (-) One extra DB query per middleware invocation; mitigated by keeping `profiles` lightweight and indexed on `id`
- (-) If the `profiles` table is unreachable, auth fails gracefully with a redirect to login

---

### ADR-002: Mutations via Next.js Server Actions, not a REST API layer

**Status**: Accepted

**Context**: Options for handling mutations include: (a) a dedicated REST API at `/api/`, (b) tRPC, (c) Next.js Server Actions.

**Decision**: Use Server Actions for all mutations. Server Actions are TypeScript functions exported from `'use server'` files, called directly from Client Components.

**Consequences**:
- (+) No additional API layer to maintain; types flow naturally from Server Action signature to form/component
- (+) Actions run on the server — RLS is always enforced via the server Supabase client
- (+) Works natively with React's `useTransition` and form `action` prop for optimistic UI
- (-) Server Actions are harder to test in isolation compared to a REST endpoint; mitigated by keeping actions thin (validate → call DB → revalidate path)
- (-) Not easily consumable by third-party clients; acceptable since Habio has no public API requirement in v1

---

### ADR-003: Shared database, shared schema multi-tenancy

**Status**: Accepted

**Context**: Multi-tenancy models include: (a) separate database per tenant, (b) separate schema per tenant, (c) shared schema with `property_id` discriminator + RLS.

**Decision**: Use shared schema with `organization_id` on `properties` and `property_id` on every operational table, enforced by RLS. Extended in ADR-008 with the Organization → Property → Building → Room hierarchy.

**Consequences**:
- (+) Operationally simple — one Supabase project, one migration to deploy
- (+) Supabase RLS is purpose-built for this pattern; well-documented and tested
- (+) Cross-property and cross-org analytics (future) is straightforward with admin queries
- (-) A RLS bug could theoretically leak cross-property or cross-org data; mitigated by pgTAP test suite and principle of defence in depth (middleware + RLS)
- (-) Very large deployments (hundreds of properties, millions of rows) may require table partitioning; acceptable trade-off for v1 scale

---

### ADR-004: `@supabase/ssr` with `getClaims()` instead of `getUser()`

**Status**: Accepted

**Context**: The existing `src/lib/supabase/middleware.ts` already uses `supabase.auth.getClaims()`. The alternative (`getUser()`) makes an extra network call to the Supabase Auth server on every request to validate the JWT.

**Decision**: Retain `getClaims()` which validates the JWT locally from the cookie, then trust the result. The `updateSession()` call in middleware handles token refresh automatically.

**Consequences**:
- (+) No extra network round-trip per request; faster middleware
- (+) Matches the pattern prescribed by the Supabase SSR library
- (-) `getClaims()` trusts the cookie-based JWT without a server-side liveness check; an attacker who can forge a cookie could bypass this — mitigated by Supabase's signed JWT with expiry and the server-side role lookup in `profiles`
- **Critical**: `getClaims()` must always be the first call after creating the server client in middleware, per Supabase documentation, to avoid session desync

---

### ADR-005: LINE integration via Official Account push, not chatbot-first

**Status**: Accepted

**Context**: LINE integration could be designed as: (a) a rich chatbot with command handling, (b) a one-way push notification channel, (c) a hybrid.

**Decision**: v1 is a one-way push channel only. The LINE Official Account sends notifications triggered by platform events. Inbound messages are not acted upon in v1 (the `follow` event links the account; all other messages receive a generic reply).

**Consequences**:
- (+) Significantly reduced complexity; no NLP or command parsing required
- (+) All business logic remains in the Next.js app; LINE is purely a delivery channel
- (+) Easy to extend to chatbot commands in v2 without redesigning the outbound flow
- (-) Users cannot interact with Habio from LINE in v1; they must use the web app for any action

---

### ADR-006: Supabase Storage for maintenance attachments (not S3/Cloudinary)

**Status**: Accepted

**Context**: Photo attachments on maintenance tickets need secure, private storage with access control. Options: Supabase Storage, AWS S3, Cloudinary.

**Decision**: Use Supabase Storage with private bucket and signed URLs.

**Consequences**:
- (+) Single vendor (no additional credentials); access control integrates with the same RLS model
- (+) Signed upload URLs keep credentials off the client; signed download URLs expire automatically
- (-) Supabase Storage has fewer image transformation features than Cloudinary; not needed in v1
- (-) If Supabase Storage has an outage, attachment upload is unavailable; ticket creation proceeds without attachments (attachments are optional)

---

### ADR-007: In-app notifications as source of truth; LINE as delivery side effect

**Status**: Accepted

**Context**: Notification delivery could be: (a) fire-and-forget to LINE only, (b) persisted in DB only, (c) both.

**Decision**: Every notification is always inserted into the `notifications` table first. LINE push is attempted afterwards and is non-fatal — if it fails, the notification is still visible in-app.

**Consequences**:
- (+) No notifications are ever lost due to a LINE API outage or unlinked account
- (+) Notification history is available in-app regardless of LINE connection status
- (-) If the notification insert succeeds but the LINE push fails silently, the user may not know to check the app; mitigated by in-app Realtime delivery

---

### ADR-008: Organization as top-level SaaS tenant boundary

**Status**: Accepted

**Context**: The original schema used `properties` as the top-level entity with `properties.manager_id` as the sole access control point. Multi-property SaaS growth requires grouping properties under organizations (e.g., "ABC Property Group" owning multiple dormitory sites).

**Decision**: Introduce `organizations` and `organization_members` tables. Properties belong to organizations via `organization_id`. Org-level access is governed by `organization_members.scope` (`owner`, `admin`, `viewer`), separate from `profiles.role`.

**Consequences**:
- (+) Supports property groups, org-level admins, and future SaaS subscription billing per org
- (+) Managers can operate one property, multiple properties, or an entire organization
- (+) `is_property_manager()` extended to check both direct `manager_id` and org admin scope — existing RLS policies benefit automatically
- (-) Additional join in `is_property_manager()` for org admin check; mitigated by `(SELECT ...)` subquery pattern and indexed FKs
- (-) Migration required to backfill organizations for existing data

See [09-multi-property.md](./09-multi-property.md) for full details.

---

### ADR-009: Denormalized `property_id` on `rooms` alongside `building_id`

**Status**: Accepted

**Context**: With the new Building layer, rooms could be accessed only via `rooms.building_id → buildings.property_id`. However, all operational tables (`tenants`, `bills`, `maintenance_tickets`, `housekeeping_tasks`) and their RLS policies already filter by `property_id`.

**Decision**: Add `building_id` to `rooms` but retain `property_id` as a denormalized FK. Enforce consistency via application validation and optionally a trigger.

**Consequences**:
- (+) Existing RLS policies on operational tables require no structural changes
- (+) Queries for property-scoped data avoid joining through `buildings`
- (-) Denormalization risk: `rooms.property_id` could drift from `buildings.property_id`; mitigated by `WITH CHECK` in room insert/update policies and a validation trigger
- (-) Slightly more complex room creation (must set both FKs)

---

### ADR-010: Keep `viewer` scope with explicit read-only RLS policies

**Status**: Accepted

**Context**: The `organization_member_scope` enum includes `viewer`, but the initial multi-property RLS design only granted `viewer` members access to their own `organization_members` row and the org header — no operational data. An enum value with zero policy backing is a misleading API surface and a security audit finding.

**Decision**: Keep `viewer` in the enum and implement explicit `FOR SELECT` policies on `properties`, `rooms`, `bills`, and `maintenance_tickets` using a new `is_organization_viewer()` helper. Viewers cannot INSERT, UPDATE, or DELETE on any operational table.

**Consequences**:
- (+) Supports future org-level reporting roles (accountants, auditors) without granting write access
- (+) Enum values match documented scope semantics in §2.1 of `04-rbac.md`
- (-) Additional policies to maintain and test in pgTAP
- (-) Viewer access is org-wide, not property-scoped; property-scoped viewers deferred to v2 if needed

---

### ADR-011: Provider-based identity model

**Status**: Accepted

**Context**: Supabase Auth supports only email/password out of the box. LINE login is required for tenant and staff workflows. Future providers (Google, Apple) may be needed. Coupling auth to email-only prevents future flexibility.

**Decision**: Store third-party identity records in `user_identities(provider, provider_user_id)` as a separate table, decoupled from `auth.users` and `memberships`. Each row represents one linked identity provider for one user.

**Rationale**:
- Adding a new provider (e.g., Google) requires only inserting rows with `provider='google'` — no schema migration.
- Authorization always resolves through `memberships`, not through identity provider.
- LINE linking is an explicit user action, not implicit on login.
- A `UNIQUE(provider, provider_user_id)` constraint prevents one LINE account from being linked to multiple Habio users.

**Consequences**:
- LINE linking requires an explicit post-authentication "link" action before a user's LINE UID is stored.
- The link flow must handle the case where a LINE UID is already linked to a different `auth.users` row.
- `handle_new_user` trigger inserts an `email` identity row on every new Supabase Auth user creation.

---

## 2. Risk Register

### Risk Matrix

| ID | Risk | Likelihood | Impact | Severity |
|---|---|:---:|:---:|:---:|
| R-01 | RLS policy misconfiguration leaks cross-property data | Low | Critical | High |
| R-02 | Schema breaking change needed after Phase 2 | Medium | High | High |
| R-03 | LINE webhook fails HMAC validation in production | Medium | Medium | Medium |
| R-04 | `getClaims()` desync causes random logouts | Low | High | Medium |
| R-05 | Supabase Realtime WebSocket instability | Low | Medium | Low |
| R-06 | Tenant photo upload exceeds Storage limits | Low | Low | Low |
| R-07 | Vercel cold starts cause high TTFB on dashboard | Medium | Medium | Medium |
| R-08 | LINE platform policy changes break integration | Low | Medium | Low |
| R-09 | Overdue bill detection runs late or misses rows | Medium | Medium | Medium |
| R-10 | Multiple active leases per room inconsistency | Low | High | Medium |
| R-11 | `rooms.building_id NOT NULL` migration breaks existing data | Medium | High | High |
| R-12 | RLS policy fan-out with org-level joins | Medium | Medium | Medium |
| R-13 | Organization slug collisions | Low | Medium | Low |
| R-14 | Cross-org data leak for multi-org managers | Low | Critical | High |
| R-15 | New signups default to `tenant` role | Medium | Medium | Medium |
| R-16 | Meter readings modified after billing period closed | Medium | Medium | Medium |
| R-17 | LINE notifications lack building context | Low | Low | Low |
| R-18 | `properties` INSERT blocked by `FOR ALL` RLS policy | High | Critical | Critical |
| R-19 | Org creation bootstrap circular RLS dependency | High | Critical | Critical |
| R-20 | `get_managed_property_ids()` full-table scan at scale | Medium | High | High |
| R-21 | Housekeeper can self-approve meter readings | Medium | Critical | High |
| R-22 | Concurrent open billing periods per property | Medium | High | High |
| R-23 | `viewer` scope has no operational data access | High | Medium | High |
| R-24 | Technician cross-property ticket read via misassignment | Medium | Critical | High |
| R-25 | `rooms.UNIQUE(property_id, room_number)` blocks multi-building numbering | Medium | High | High |
| R-26 | No FK link between `bills` and `billing_periods` | Medium | Medium | Medium |
| R-27 | `organization_members` missing composite index on access path | Medium | High | High |
| R-28 | RLS join fan-out on `meter_readings` at SaaS scale | Medium | Medium | Medium |
| R-39 | User identity duplication — same LINE UID linked to two `auth.users` rows | Medium | High | High |
| R-40 | LINE account linked to wrong user (e.g. shared device) | Low | High | High |
| R-41 | Membership and identity desynchronization | Low | Medium | Medium |
| R-42 | Notification volume scalability | Medium | Medium | Medium |
| R-43 | LINE webhook security — forged requests reach delivery pipeline | Low | High | High |

---

### R-01: RLS Policy Misconfiguration

**Description**: A bug in a RLS policy (e.g., missing `property_id` check) allows a manager to read another manager's data.

**Mitigation**:
1. Every table's RLS policies covered by pgTAP tests in `supabase/tests/`
2. Tests run in CI before every deployment
3. Middleware role enforcement acts as a second barrier
4. Manual security review before production launch

---

### R-02: Schema Breaking Change After Phase 2

**Description**: A feature requirement emerges in Phase 3+ that requires modifying a table that already has production data (e.g., renaming a column, changing a type).

**Mitigation**:
1. Schema design reviewed before Phase 1 implementation begins (this document)
2. All changes via new migrations — no modifying existing migration files
3. Use expand-contract pattern: add new column → migrate data → drop old column across separate deployments
4. Semantic versioning on migrations to track changes

---

### R-03: LINE Webhook HMAC Validation Failure

**Description**: The LINE webhook rejects all incoming events in production due to a `LINE_CHANNEL_SECRET` misconfiguration.

**Mitigation**:
1. `LINE_CHANNEL_SECRET` validated in CI by running a test webhook event with a known signature
2. Webhook route logs validation failures at `warn` level without exposing the secret
3. LINE account link tested in staging before production

---

### R-04: Session Desync with `getClaims()`

**Description**: Supabase's `updateSession()` cookie-refresh mechanism fails, causing users to be randomly logged out.

**Mitigation**:
1. Follow Supabase documentation strictly: `getClaims()` is the first call after `createServerClient` in middleware, with no code between them
2. `supabaseResponse` returned as-is from `updateSession()` without modification
3. Integration test: verify that a user stays logged in after 60 minutes of activity

---

### R-05: Supabase Realtime WebSocket Instability

**Description**: Realtime subscriptions drop and notifications are not delivered in real-time, degrading UX.

**Mitigation**:
1. Realtime is a progressive enhancement; the notification inbox page always shows the correct state on load (server-rendered)
2. Client hook implements reconnect with exponential backoff via Supabase client's built-in channel re-subscription
3. Badge count is re-fetched on page focus as a fallback

---

### R-07: Vercel Cold Starts on Dashboard Pages

**Description**: Server Components that fetch data on first load incur a cold start penalty, causing TTFB > 1 s for the first user per region.

**Mitigation**:
1. Use Vercel's Fluid Compute (enabled by default in Next.js 16) which keeps functions warm
2. Cache non-user-specific data (e.g., property metadata) with `unstable_cache` or `revalidate` headers
3. Measure TTFB in staging with Vercel Analytics before launch

---

### R-09: Overdue Bill Detection Runs Late

**Description**: A cron job that flips `pending` bills to `overdue` runs infrequently or misses rows, causing incorrect bill status.

**Mitigation**:
1. Use Supabase `pg_cron` extension (`cron.schedule`) to run the overdue check at midnight UTC daily — runs inside the database, not dependent on external services
2. Bill list page also computes overdue status client-side based on `due_date < now()` as a display fallback, even if the DB status hasn't been flipped yet
3. `idx_bills_overdue` on `(status, due_date)` keeps the cron query fast (defined in `03-database-schema.md` §4.8)

**pg_cron job:**

```sql
SELECT cron.schedule(
  'flip-overdue-bills',
  '0 0 * * *',
  $$
    UPDATE public.bills
    SET status = 'overdue'
    WHERE status = 'pending'
      AND due_date < CURRENT_DATE;
  $$
);
```

---

### R-10: Multiple Active Leases Per Room

**Description**: A data integrity bug allows two tenants to have `lease_status = 'active'` for the same room simultaneously, corrupting occupancy data.

**Mitigation**:
1. Application-layer check in `createTenant` Server Action: verify room has no active tenant before inserting
2. Database-layer: partial unique index on `(room_id)` WHERE `lease_status = 'active'` and `archived_at IS NULL`
3. The `sync_room_status` trigger will set room status to `occupied` on any active lease — a second active lease insert would be caught by the unique index first

```sql
CREATE UNIQUE INDEX tenants_one_active_per_room
  ON public.tenants (room_id)
  WHERE lease_status = 'active' AND archived_at IS NULL;
```

---

### R-11: `rooms.building_id NOT NULL` Migration

**Description**: Existing rooms have no `building_id`. Enforcing `NOT NULL` before backfill will fail the migration.

**Mitigation**:
1. Phase A: add `building_id` as nullable
2. Phase B: create one "Main Building" per property and backfill all rooms
3. Phase C: enforce `NOT NULL` only after verification query returns zero nulls
4. See [09-multi-property.md](./09-multi-property.md) §10 for the full migration plan

---

### R-12: RLS Policy Fan-out with Org Joins

**Description**: Org-level access requires joining through `organization_members → properties` on every `is_property_manager()` call, potentially degrading query performance at scale.

**Mitigation**:
1. Centralize access logic in `is_property_manager()` and `is_organization_admin()` helpers
2. Use `(SELECT auth.uid())` and `(SELECT is_organization_admin(...))` subquery pattern for per-query caching
3. Index `organization_members(organization_id, user_id)` and `properties(organization_id)`
4. Monitor slow queries via Supabase dashboard; add materialized views if needed at scale

---

### R-13: Organization Slug Collisions

**Description**: User-facing org slugs (for subdomain routing) must be unique and URL-safe.

**Mitigation**:
1. `UNIQUE` constraint on `organizations.slug` at database level
2. Server-side slug validation and auto-generation in `createOrganization` action
3. Reserved slug list (e.g., `admin`, `api`, `www`) checked before insert

---

### R-14: Cross-Org Data Leak

**Description**: A manager who belongs to multiple organizations could see properties from org A while operating in org B context.

**Mitigation**:
1. RLS on `properties` uses `is_property_manager(id)` which checks org membership per property, not a global org list
2. Manager UI always scopes queries to the selected property context (`/manager/properties/[propertyId]/...`)
3. pgTAP tests verify cross-org isolation for multi-org users
4. Never rely on client-side filtering alone — RLS is the security guarantee

---

### R-15: New Signups Default to `tenant` Role

**Description**: The `handle_new_user` trigger defaults every signup to `role = 'tenant'`. Org owners must be explicitly upgraded.

**Mitigation**:
1. Org creation flow (`createOrganization` Server Action) sets caller's role to `manager` and creates `organization_members` row with `scope = 'owner'`
2. Role elevation uses service role key — never from user-controlled metadata
3. Keep existing trigger default; org creation is a deliberate post-signup action

---

### R-16: Meter Readings Modified After Period Closed

**Description**: If a billing period is closed, housekeepers or managers could still modify readings, corrupting billing data.

**Mitigation**:
1. RLS `WITH CHECK` on `meter_readings` enforces parent `billing_period.status = 'open'`
2. Manager approve/reject actions check period status before mutation
3. Application-layer validation in `submitMeterReading` and `approveMeterReading` actions

---

### R-17: LINE Notifications Lack Building Context

**Description**: Push notifications reference `property_id`; the new building layer adds granularity that LINE messages do not convey.

**Mitigation**:
1. Notifications remain property-scoped for v1
2. Include room number in notification body (already available via `room_id`)
3. Building-level notification targeting deferred to v2

---

### R-18: `properties` INSERT Blocked by `FOR ALL` RLS Policy

**Description**: The `properties: manager full access` policy used `WITH CHECK (is_property_manager(id))` on INSERT. Since the row does not exist yet, `is_property_manager` always returns `false` and all property creation is blocked.

**Mitigation**:
1. Split into separate SELECT/UPDATE/DELETE and INSERT policies (see `04-rbac.md` §5.3)
2. INSERT policy checks `manager_id = auth.uid()` and org membership directly
3. pgTAP test: authenticated org admin can INSERT a property

---

### R-19: Org Creation Bootstrap Circular RLS Dependency

**Description**: The `org_members: owner full access` INSERT policy requires an existing `owner` row in `organization_members`. The first owner row cannot be inserted by an authenticated client session.

**Mitigation**:
1. `createOrganization` Server Action uses service role key for the initial `organization_members` INSERT
2. Documented in `04-rbac.md` §5.14 and §6 Service Role Usage table
3. pgTAP test: org creation flow succeeds end-to-end via Server Action

---

### R-20: `get_managed_property_ids()` Full-Table Scan at Scale

**Description**: The original implementation called `is_organization_admin(p.organization_id)` per row of `properties`, materializing correlated subqueries across thousands of properties.

**Mitigation**:
1. Refactored to a flattened `IN` subquery against `organization_members` (see `04-rbac.md` §5.1)
2. Composite index `idx_org_members_user_scope` on `(user_id, organization_id, scope)` (see `03-database-schema.md` §4.3)
3. Monitor query plans via Supabase dashboard after Phase 0 migration

---

### R-21: Housekeeper Can Self-Approve Meter Readings

**Description**: The `meter_readings: housekeeper update own` policy had no constraint on the `status` column value being written. A housekeeper could UPDATE their reading to `status = 'approved'`, bypassing manager approval.

**Mitigation**:
1. Added `status IN ('pending', 'submitted')` to the `WITH CHECK` clause (see `04-rbac.md` §5.18)
2. pgTAP test: housekeeper UPDATE to `approved` is denied
3. Manager approve action is the only path to `approved` status

---

### R-22: Concurrent Open Billing Periods Per Property

**Description**: The "one open period per property" rule was app-enforced only. Two concurrent `createBillingPeriod` calls could both pass the app check and insert duplicate open periods.

**Mitigation**:
1. Partial unique index `billing_periods_one_open_per_property` on `(property_id) WHERE status = 'open'` (see `03-database-schema.md` §4.10)
2. Application-layer check retained as first line of defence
3. pgTAP test: second open period INSERT raises unique violation

---

### R-23: `viewer` Scope Has No Operational Data Access

**Description**: `organization_member_scope` included `viewer` but no RLS policy granted viewers access to properties, rooms, bills, or tickets — only the org header row.

**Mitigation**:
1. Decision documented in ADR-010: keep `viewer` and implement read-only policies
2. `is_organization_viewer()` helper and `FOR SELECT` policies on operational tables (see `04-rbac.md` §5.1, §5.3, §5.4, §5.6, §5.8)
3. pgTAP tests verify viewer can SELECT but not INSERT/UPDATE/DELETE

---

### R-24: Technician Cross-Property Ticket Read via Misassignment

**Description**: Technician ticket policies checked only `assigned_to = auth.uid()` without verifying `property_staff` membership. A misassigned ticket from Property A could be read by a technician from Property B.

**Mitigation**:
1. Added `is_property_staff(property_id)` to technician ticket SELECT/UPDATE policies (see `04-rbac.md` §5.8)
2. Same fix applied to housekeeper task policies (§5.10)
3. Server Actions still validate `property_staff` before assignment

---

### R-25: `rooms.UNIQUE(property_id, room_number)` Blocks Multi-Building Numbering

**Description**: Properties with multiple buildings commonly reuse room numbers (e.g., Building A Room 101 and Building B Room 101). A property-scoped unique constraint rejected valid data.

**Mitigation**:
1. Changed uniqueness to `UNIQUE (building_id, room_number)` (see `03-database-schema.md` §4.6)
2. UI may still warn about cross-building duplicates; DB reflects physical reality
3. Migration backfill: existing single-building properties unaffected

---

### R-26: No FK Link Between `bills` and `billing_periods`

**Description**: Bills generated from meter readings had no persisted link to the source billing period. Reporting required fragile date-range matching.

**Mitigation**:
1. Added nullable `billing_period_id` FK on `bills` (see `03-database-schema.md` §4.8)
2. `generateBillsFromReadings` Server Action sets `billing_period_id` on created bills
3. Nullable to preserve backward compatibility with manually generated bills

---

### R-27: `organization_members` Missing Composite Index on Access Path

**Description**: `is_organization_admin()` queries `(organization_id, user_id, scope)` but only separate single-column indexes existed. The core access-check path is called on every `is_property_manager()` evaluation.

**Mitigation**:
1. Replaced separate indexes with composite `idx_org_members_user_scope` on `(user_id, organization_id, scope)` (see `03-database-schema.md` §4.3)
2. Covers `get_managed_property_ids()` IN subquery as well
3. Verify index usage in `EXPLAIN ANALYZE` after migration

---

### R-28: RLS Join Fan-Out on `meter_readings` at SaaS Scale

**Description**: Manager read policy on `meter_readings` joined `billing_periods → rooms` and called `is_property_manager()` per row. At hundreds of properties with millions of readings, list queries and Realtime broadcasts degrade.

**Mitigation**:
1. Denormalized `property_id` on `meter_readings` (see `03-database-schema.md` §4.11)
2. RLS simplified to `is_property_manager(property_id)` (see `04-rbac.md` §5.18)
3. Index `idx_meter_readings_property_id` for list queries
4. Denormalized `organization_id` on `bills` and `maintenance_tickets` for org-level analytics (M-06)

---

### R-29: Owner Membership UNIQUE Constraint Broken by NULL

**Description**: A table-level `UNIQUE (user_id, organization_id, property_id, role)` does not deduplicate owner rows because PostgreSQL treats `NULL != NULL`. A retry or race in owner signup can create duplicate owner memberships.

**Mitigation**:
1. Replace with partial unique indexes `memberships_owner_unique` and `memberships_property_role_unique` (see `03-database-schema.md` §4.4)
2. pgTAP test: second active owner INSERT for same user/org raises unique violation
3. Owner signup Server Action uses `ON CONFLICT` or transaction with advisory lock

---

### R-30: Cross-Organization Property Assignment via Memberships

**Description**: Without validation, an INSERT could set `memberships.property_id` to a property in a different organization than `memberships.organization_id`, granting cross-org access.

**Mitigation**:
1. `validate_membership_org_consistency` trigger on `memberships` (see `03-database-schema.md` §7)
2. Invitation acceptance Server Action validates property belongs to invitation organization
3. pgTAP test: cross-org property assignment is rejected

---

### R-31: Last Owner Deactivation Orphans Organization

**Description**: Ownership is derived from memberships, not `organizations.owner_id`. Deactivating the sole owner leaves the organization unreachable.

**Mitigation**:
1. `prevent_owner_orphan` trigger blocks deactivation of the last active owner (see `03-database-schema.md` §7)
2. UI requires ownership transfer before self-deactivation when co-owners exist
3. Product decision on co-ownership documented in OQ-07

---

### R-32: RLS Double-Evaluation of `is_org_owner` on Properties

**Description**: A policy combining `is_org_owner(organization_id) OR can_access_property(id)` calls `is_org_owner` twice per row because `can_access_property` invokes it internally.

**Mitigation**:
1. Inline membership existence check instead of `can_access_property` in row-level policies (see `04-rbac.md` §6.2)
2. Reserve `can_access_property` for Server Action one-time checks only
3. `EXPLAIN ANALYZE` on owner property list after migration

---

### R-33: Org-Level RLS Joins Through `properties` at Scale

**Description**: Tables without denormalized `organization_id` force correlated subqueries against `properties` in owner-level RLS. At 100,000 tenant profiles this adds significant per-row cost.

**Mitigation**:
1. Denormalize `organization_id` on `tenant_profiles`, `billing_periods`, `meter_readings`, and `housekeeping_tasks` (see `03-database-schema.md` §5)
2. Set `organization_id` at insert via trigger or Server Action
3. Owner policies use `is_org_owner(organization_id)` directly (see `04-rbac.md` §6.2)

---

### R-34: Middleware Loads All Memberships Per Request

**Description**: Loading every active membership on each request degrades edge middleware for users assigned to many properties (e.g., regional technicians with 50+ assignments).

**Mitigation**:
1. Fast path: `validateMembershipById` primary-key lookup from signed cookie (see `04-rbac.md` §5, `02-system-architecture.md` §4)
2. Full list only on `/select-membership` and explicit context switch
3. Index `idx_memberships_user_active` for switcher page

---

### R-35: Offset Pagination Degrades on Large Tables

**Description**: `LIMIT 20 OFFSET 2000` scans all preceding rows. Operational tables (`bills`, `maintenance_tickets`, `notifications`) will reach millions of rows at target scale.

**Mitigation**:
1. Mandate keyset pagination: `WHERE (created_at, id) < ($cursor_created_at, $cursor_id) ORDER BY created_at DESC, id DESC LIMIT 20` (see `01-requirements.md` §5.4)
2. Shared cursor pagination helper in application layer
3. No offset-based list APIs in v1

---

### R-36: Unbounded `invitations` Table Growth

**Description**: Accepted and expired invitations accumulate indefinitely. At 100,000+ tenants the table and `idx_invitations_email_status` index bloat.

**Mitigation**:
1. `invitations_archive` table and weekly `pg_cron` job (see `03-database-schema.md` §7.1)
2. Schedule archival in Phase 0 or Phase 1, not post-launch
3. Retain `accepted_at` on memberships as the durable audit record

---

### R-37: Unbounded `notifications` Table Growth

**Description**: At 100,000 tenants receiving ~10 notifications per month, the table grows by ~1M rows/month, degrading Realtime broadcast and inbox queries.

**Mitigation**:
1. `notifications_archive` table and weekly `pg_cron` job (see `03-database-schema.md` §7.1)
2. Schedule archival in Phase 0 or Phase 1 alongside invitations archival
3. Realtime subscriptions scoped to recent unread rows only

---

### R-38: Staff and Tenant Roles Mixed in Single Enum

**Description**: `membership_role` includes `tenant` alongside staff roles. Permission checks must explicitly distinguish tenant scope (room-level via `tenant_profiles`) from staff scope (property-level).

**Mitigation**:
1. `is_staff_role()` helper function (see `03-database-schema.md` §6)
2. Staff-only Server Actions call `is_staff_role` before property operations
3. pgTAP tests verify tenant membership cannot access staff routes or cross-room data

---

### R-39: User Identity Duplication

**Description**: The same LINE UID is linked to two different `auth.users` rows if the uniqueness check is bypassed or races.

**Mitigation**:
1. `UNIQUE(provider, provider_user_id)` constraint on `user_identities`
2. Server action checks for existing link before insert
3. Database constraint is the final guard

---

### R-40: LINE Account Linked to Wrong User

**Description**: A user on a shared device links their LINE account to another person's Habio account.

**Mitigation**:
1. Require an active authenticated session before allowing any link
2. Display LINE display name and profile photo in a confirmation step before committing
3. Allow self-unlink at any time from account settings

---

### R-41: Membership and Identity Desynchronization

**Description**: A user is deactivated (`memberships.deactivated_at` set) but their LINE identity row remains, causing confusion about their access state.

**Mitigation**:
1. Membership deactivation is the single access gate; identity rows are inert without an active membership
2. Document clearly that identity ≠ access in `04-rbac.md` §2.1
3. Optionally show "inactive" status on LINE link UI when membership is deactivated

---

### R-42: Notification Volume Scalability

**Description**: High-frequency business events (e.g., bulk billing) flood the `notifications` table and slow inbox queries.

**Mitigation**:
1. Archive notifications older than 90 days via `pg_cron` job into `notifications_archive`
2. Keyset-paginate all inbox queries
3. Index on `(user_id, created_at desc)`

---

### R-43: LINE Webhook Security

**Description**: Forged POST requests reach the LINE webhook endpoint and inject malicious notification payloads.

**Mitigation**:
1. HMAC-SHA256 channel signature validation on every webhook request (deferred to Phase 5 implementation)
2. Schema and endpoint stub are ready but no delivery logic is active until Phase 5
3. Webhook writes use service role only after signature validation passes

---

## 3. Open Questions

These items require further clarification before implementation begins:

| # | Question | Owner | Target Phase |
|---|---|---|---|
| OQ-01 | ~~Should managers be able to manage multiple properties, or is each property tied to one manager account?~~ **Resolved**: Managers can manage one property, multiple properties within an org, or an entire org via `organization_members.scope`. See ADR-008 and [09-multi-property.md](./09-multi-property.md). | Product | Phase 0 |
| OQ-02 | ~~Are technicians and housekeepers property-specific, or can they be shared across properties by the same manager?~~ **Resolved**: staff are property-specific via the `property_staff` table. A user can appear in multiple properties' staff lists (e.g., a freelance technician shared across buildings), but assignment actions validate `property_staff` membership before writing. See `03-database-schema.md` §​4.12 and `04-rbac.md` §​5.13. | Product | Phase 1 |
| OQ-03 | Should tenants be able to sign up themselves, or is all tenant creation manager-initiated? | Product | Phase 2 |
| OQ-04 | What is the LINE Official Account strategy — one account for all properties, or one per property? | Product | Phase 4 |
| OQ-05 | Is THB the only supported currency, or should the billing system be currency-agnostic? | Product | Phase 2 |
| OQ-06 | Are bill line items (utilities, etc.) entered manually each month, or does the system auto-populate recurring items? | Product | Phase 2 |
| OQ-07 | Does Habio support co-ownership (multiple owners per org) and ownership transfer? The schema allows multiple owner memberships but there is no primary-owner or billing-contact distinction yet. | Product | Phase 0 |
