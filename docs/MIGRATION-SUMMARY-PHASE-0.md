# Phase 0 Migration Summary — Auth and RBAC Foundation

This document summarizes the Habio Phase 0 database and authorization foundation. Authoritative design sources: [03-database-schema.md](./03-database-schema.md), [04-rbac.md](./04-rbac.md), [06-implementation-roadmap.md](./06-implementation-roadmap.md).

## Migration order

Migrations apply in timestamp order under `supabase/migrations/`:

| Order | File | Purpose |
|------:|------|---------|
| 1 | `20240101000000_initial_schema.sql` | Legacy bootstrap (profiles, properties, rooms, bills, tickets) |
| 2 | `20240102000000_rls_policies.sql` | Initial RLS (superseded by membership migrations) |
| 3 | `20240103000000_triggers.sql` | `handle_new_user`, `set_updated_at`, pg_cron jobs |
| 4 | `20240104000000_security_and_performance_fixes.sql` | Security/performance hardening |
| 5 | `20240105000000_multi_property_schema.sql` | Organizations, buildings, billing_periods |
| 6 | `20240105000001_multi_property_backfill.sql` | Multi-property backfill |
| 7 | `20240105000002_multi_property_constraints_rls.sql` | Multi-property constraints |
| 8 | `20240105000003_fix_organization_members_rls_recursion.sql` | RLS recursion fix |
| 9 | `20240106000000_membership_schema.sql` | `membership_role`, `memberships`, `invitations`, `tenant_profiles` |
| 10 | `20240106000001_membership_backfill.sql` | Legacy → membership backfill |
| 11 | `20240106000002_membership_constraints_triggers.sql` | Partial uniques, org-consistency, archival cron |
| 12 | `20240106000003_membership_rls.sql` | RLS helpers and membership policies |
| 13 | `20240106000004_membership_drop_legacy.sql` | Drop `profiles.role`, `organization_members`, etc. |
| 14 | `20240107000000_auth_flow_rpcs.sql` | Owner signup / invite acceptance RPCs |
| 15 | `20240108000000_tenant_activation_rpcs.sql` | Tenant activation RPC |
| 16 | `20240109000000_user_identities.sql` | `user_identities`, email identity on signup |
| 17 | `20240109000001_notification_deliveries.sql` | `notification_deliveries` |
| 18 | `20240109000002_audit_logs.sql` | `audit_logs`, `record_audit_event`, archive |
| 19 | `20240109000003_platform_admins.sql` | `platform_admins`, `organizations.suspended_at` |
| 20 | `20240109000004_archival_cron_jobs.sql` | pg_cron archival jobs |
| 21 | `20240109000005_fix_buildings_rls.sql` | Buildings RLS + `organization_id` denorm |
| 22 | `20240109000006_fix_tickets_rls.sql` | Maintenance ticket RLS fix |
| 23 | `20240109000007_invitations_org_level.sql` | Org-level owner invitation support |
| 24 | `20240109000008_archived_at_columns.sql` | `archived_at` on operational tables |
| 25 | `20240109000009_subscription_tables.sql` | Subscription tables (prototype limits) |
| 26 | `20240109000010_activity_feed_views.sql` | Activity feed views over `audit_logs` |
| 27 | `20240110000000_phase0_foundation.sql` | Schema reconciliation (notifications, archival, audit INSERT revoke) |
| 28 | **`20240111000000_subscription_alignment.sql`** | **Align plans/usage_counters/RLS with approved schema** |
| 29 | **`20240111000001_occupancy_foundation.sql`** | **Occupancy tables, triggers, RLS (no completion RPCs)** |

## Tables created in Phase 0

### Core identity and authorization

| Table | Notes |
|-------|-------|
| `profiles` | Display/contact only; no role column |
| `organizations` | `plan` cache, `suspended_at` |
| `properties`, `buildings`, `rooms` | Property hierarchy |
| `memberships` | Single source of truth for access |
| `invitations` | Hashed tokens, property-scoped staff invites |
| `tenant_profiles` | Lease metadata; auth via tenant membership |
| `user_identities` | Email/LINE/Google/Apple linkage |

### Platform and audit

| Table | Notes |
|-------|-------|
| `platform_admins` | Service-role only; no authenticated RLS |
| `audit_logs` | INSERT-only; `REVOKE UPDATE, DELETE` on `authenticated` |
| `audit_logs_archive` | pg_cron target (180 days) |

### Notifications (schema only)

| Table | Notes |
|-------|-------|
| `notifications` | In-app events; `organization_id`, `event_type`, `metadata` |
| `notification_deliveries` | Per-channel delivery state; no user writes |
| `notifications_archive` | pg_cron target (read + 90 days) |

### Subscription foundation

| Table | Notes |
|-------|-------|
| `subscription_plans` | Catalog; `max_properties`, `max_rooms` (org-wide), `features` jsonb |
| `organization_subscriptions` | One row per org; owners manage via RLS |
| `usage_counters` | PK `(organization_id, metric)`; no `period_start` |

### Occupancy foundation (tables only)

| Table | Notes |
|-------|-------|
| `move_in_transactions` | Draft/completed/voided lifecycle |
| `move_out_transactions` | Draft/settled/disputed/voided lifecycle |
| `meter_snapshots` | Immutable; `REVOKE UPDATE, DELETE` on `authenticated` |
| `inspection_items` | Checklist rows per parent transaction |

### Archival

| Table | Notes |
|-------|-------|
| `invitations_archive` | Accepted/expired/revoked invitations (90 days) |

## Enums (Phase 0 scope)

- `membership_role`, `invitation_status`
- `property_status`, `room_type`, `room_status`, `lease_status`
- `billing_period_status`, `meter_reading_status`
- `bill_status`, `ticket_priority`, `ticket_status`, `task_status`
- `notification_channel`, `notification_delivery_status`
- `move_in_transaction_status`, `move_out_transaction_status`
- `inspection_item_status`, `meter_snapshot_type`

## SECURITY DEFINER helpers

| Function | Purpose |
|----------|---------|
| `is_org_owner(org_id)` | Org-level owner check |
| `has_property_role(property_id, role)` | Property-scoped role check |
| `can_access_property(property_id)` | Server Action permission check only (not RLS `USING`) |
| `can_manage_property(property_id)` | Owner or manager |
| `is_staff_role(role)` | Owner/manager/technician/housekeeper |
| `is_platform_admin()` | Platform admin grant check |
| `is_feature_enabled(org_id, feature_key)` | Plan feature gate (Server Actions/RPCs only) |
| `check_property_limit(org_id)` | Legacy limit helper (Phase 2.5 enforcement) |
| `record_audit_event(...)` | INSERT-only audit writes |
| `handle_new_user()` | Creates `profiles` + email `user_identities` row |
| `sync_organization_plan_from_subscription()` | Syncs `organizations.plan` on `plan_id` change |

All helpers use `SET search_path = public` (or `public, pg_temp` for triggers) and include `auth.uid()` predicates where applicable.

## RLS policy summary

- **Membership model**: policies inline `is_org_owner(organization_id)` and `has_property_role(property_id, …)` against denormalized scope columns.
- **Cross-org isolation**: every operational policy requires org ownership, property membership, or direct user ownership.
- **Subscription limits are never enforced in RLS** — read/write grants only.
- **`usage_counters`**: SELECT for owners/managers; no authenticated INSERT/UPDATE/DELETE.
- **`subscription_plans`**: SELECT for all authenticated users.
- **`organization_subscriptions`**: owners CRUD; managers SELECT.
- **`audit_logs`**: owners/managers SELECT; INSERT via `record_audit_event` only (direct authenticated INSERT revoked in `phase0_foundation`).
- **`meter_snapshots`**: SELECT/INSERT per role matrix; no UPDATE/DELETE grants.
- **`platform_admins`**: no authenticated policies; service-role only.
- **Technician/housekeeper occupancy SELECT**: deferred until `inspection_assignments` (Phase 4).

## Seed data

### `subscription_plans`

| Plan | `max_properties` | `max_rooms` | `features` |
|------|----------------:|------------:|------------|
| free | 1 | 20 | `{}` |
| starter | 3 | 50 | `{}` |
| pro | 10 | 200 | `{}` |
| enterprise | null (unlimited) | null (unlimited) | `{}` |

Existing organizations are backfilled onto the free plan via `organization_subscriptions` and receive zeroed `usage_counters` rows for `active_properties`, `active_rooms`, and `active_tenants`.

## pg_cron jobs

| Job | Schedule | Action |
|-----|----------|--------|
| `archive-old-invitations` | Sun 03:00 UTC | Move accepted/expired/revoked invitations > 90 days to archive |
| `archive-old-notifications` | Sun 04:00 UTC | Move read notifications > 90 days to archive |
| `archive-old-audit-logs` | Sun 05:00 UTC | Move audit_logs > 180 days to archive |

Requires `pg_cron` extension (enabled in initial migration).

## pgTAP tests

| File | Coverage |
|------|----------|
| `supabase/tests/rls_policies.test.sql` | Schema integrity, legacy removal, cross-org denial, audit_logs immutability, platform_admins guard |
| `supabase/tests/membership_rls.test.sql` | Membership indexes, helper functions, housekeeper/technician guards, last-owner trigger |
| `supabase/tests/phase0_subscription.test.sql` | Plan seed limits, `usage_counters` DML denial, `is_feature_enabled` |
| `supabase/tests/occupancy_foundation.test.sql` | Occupancy schema, tenant read, technician denial, meter_snapshots immutability, scope triggers |

### How to run tests

```bash
# Reset local DB and apply all migrations + seed
supabase db reset

# Run pgTAP suite (requires pg_prove or supabase test db)
pg_prove -U postgres -h 127.0.0.1 -p 54322 -d postgres supabase/tests/*.test.sql
# or
supabase test db
```

## Deferred to later phases

| Item | Phase | Notes |
|------|-------|-------|
| Auth UI, middleware, cookies | 1 | No frontend in Phase 0 |
| Notification delivery logic | 5 | Schema only in Phase 0 |
| LINE Messaging API | 5 | `user_identities` ready |
| `complete_move_in` / `complete_move_out` RPCs | 3.5 | Tables and RLS in place |
| `check_and_increment_usage` / `decrement_usage` | 2.5 | Limit enforcement in Server Actions |
| `inspection_assignments` + staff occupancy SELECT | 4 | Technician/housekeeper read deferred |
| Billing operational tables logic | 3 | `billing_periods`, `bills` exist from earlier migrations |
| `audit_logs_archive` authenticated policies | 6 | Service/cron writes only |
| TypeScript type regeneration | 2+ | Run `supabase gen types` after applying migrations |

## Gaps and blockers

1. **Supabase CLI not verified in this session** — run `supabase db reset` locally to validate migration chain.
2. **`check_property_limit`** still counts live properties instead of `usage_counters`; replace with `check_and_increment_usage` in Phase 2.5.
3. **Completion RPC signatures** undocumented — define before Phase 3.5 backend work.
4. **Dispute/void workflows** — status enums exist; resolution RPCs not specified.
