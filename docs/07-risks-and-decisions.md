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

**Decision**: Use shared schema with `property_id` on every operational table, enforced by RLS.

**Consequences**:
- (+) Operationally simple — one Supabase project, one migration to deploy
- (+) Supabase RLS is purpose-built for this pattern; well-documented and tested
- (+) Cross-property analytics (future) is straightforward with admin queries
- (-) A RLS bug could theoretically leak cross-property data; mitigated by pgTAP test suite and principle of defence in depth (middleware + RLS)
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
3. `idx_bills_overdue` on `(status, due_date)` keeps the cron query fast (defined in `03-database-schema.md` §4.5)

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

## 3. Open Questions

These items require further clarification before implementation begins:

| # | Question | Owner | Target Phase |
|---|---|---|---|
| OQ-01 | Should managers be able to manage multiple properties, or is each property tied to one manager account? | Product | Phase 1 |
| OQ-02 | ~~Are technicians and housekeepers property-specific, or can they be shared across properties by the same manager?~~ **Resolved**: staff are property-specific via the `property_staff` table. A user can appear in multiple properties' staff lists (e.g., a freelance technician shared across buildings), but assignment actions validate `property_staff` membership before writing. See `03-database-schema.md` §​4.12 and `04-rbac.md` §​5.13. | Product | Phase 1 |
| OQ-03 | Should tenants be able to sign up themselves, or is all tenant creation manager-initiated? | Product | Phase 2 |
| OQ-04 | What is the LINE Official Account strategy — one account for all properties, or one per property? | Product | Phase 4 |
| OQ-05 | Is THB the only supported currency, or should the billing system be currency-agnostic? | Product | Phase 2 |
| OQ-06 | Are bill line items (utilities, etc.) entered manually each month, or does the system auto-populate recurring items? | Product | Phase 2 |
