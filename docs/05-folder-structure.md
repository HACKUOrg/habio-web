# 05 — Folder Structure

## 1. Design Principles

- **Colocation**: feature-specific code (components, hooks, actions) lives near the route that uses it; only truly shared code is lifted to `src/components/` or `src/lib/`
- **Route groups** `(auth)` and `(dashboard)` isolate auth pages from the protected app shell without affecting the URL
- **Role-scoped route trees**: each role gets its own directory under `(dashboard)`, preventing accidental cross-role component sharing
- **Server Actions in `src/lib/actions/`**: all mutations are colocated by domain, importable by any Server Component or Client Component
- **No barrel files** in `src/app/` — Next.js App Router handles module discovery; barrels cause issues with Server/Client component boundaries

---

## 2. Full Directory Tree

```
habio-web/
├── docs/                               # Architecture documentation (this folder)
├── public/                             # Static assets
├── supabase/                           # Supabase CLI workspace
│   ├── config.toml                     # Supabase project config
│   ├── migrations/                     # Ordered SQL migration files
│   │   └── 20240101000000_initial_schema.sql
│   ├── seed.sql                        # Dev seed data
│   └── tests/                          # pgTAP RLS tests
│       └── rls_policies.test.sql
└── src/
    ├── middleware.ts                   # Root Next.js middleware (auth guard + role redirect)
    ├── app/
    │   ├── globals.css                 # Tailwind base styles + CSS variables
    │   ├── layout.tsx                  # Root layout (fonts, metadata)
    │   │
    │   ├── (auth)/                     # Public auth routes — no dashboard shell
    │   │   └── auth/
    │   │       ├── login/
    │   │       │   └── page.tsx        # Sign-in form
    │   │       ├── forgot-password/
    │   │       │   └── page.tsx        # Password reset request
    │   │       └── callback/
    │   │           └── route.ts        # Supabase Auth callback handler
    │   │
    │   ├── (dashboard)/                # Protected routes — renders inside dashboard shell
    │   │   ├── layout.tsx              # Dashboard shell (sidebar, topnav, notification bell)
    │   │   │
    │   │   ├── manager/                # Manager-only pages
    │   │   │   ├── dashboard/
    │   │   │   │   └── page.tsx        # Overview: occupancy, outstanding bills, open tickets
    │   │   │   ├── properties/
    │   │   │   │   ├── page.tsx        # Property list
    │   │   │   │   └── [propertyId]/
    │   │   │   │       └── page.tsx    # Single property overview
    │   │   │   ├── rooms/
    │   │   │   │   ├── page.tsx        # Room list with status filter
    │   │   │   │   ├── new/
    │   │   │   │   │   └── page.tsx    # Create room form
    │   │   │   │   └── [roomId]/
    │   │   │   │       └── page.tsx    # Room detail + tenant history
    │   │   │   ├── tenants/
    │   │   │   │   ├── page.tsx        # Tenant directory
    │   │   │   │   ├── new/
    │   │   │   │   │   └── page.tsx    # Invite / create tenant
    │   │   │   │   └── [tenantId]/
    │   │   │   │       └── page.tsx    # Tenant detail + lease + billing summary
    │   │   │   ├── billing/
    │   │   │   │   ├── page.tsx        # Bill list with status filter
    │   │   │   │   ├── new/
    │   │   │   │   │   └── page.tsx    # Generate bill form
    │   │   │   │   └── [billId]/
    │   │   │   │       └── page.tsx    # Bill detail + line items + mark paid
    │   │   │   ├── maintenance/
    │   │   │   │   ├── page.tsx        # Ticket list (all statuses, filter by priority)
    │   │   │   │   └── [ticketId]/
    │   │   │   │       └── page.tsx    # Ticket detail + assignment + comments
    │   │   │   └── housekeeping/
    │   │   │       ├── page.tsx        # Task calendar / list view
    │   │   │       └── new/
    │   │   │           └── page.tsx    # Create task form
    │   │   │
    │   │   ├── tenant/                 # Tenant-only pages
    │   │   │   ├── dashboard/
    │   │   │   │   └── page.tsx        # Overview: room info, current bill, open tickets
    │   │   │   ├── room/
    │   │   │   │   └── page.tsx        # Room detail + lease info
    │   │   │   ├── billing/
    │   │   │   │   ├── page.tsx        # Bill history list
    │   │   │   │   └── [billId]/
    │   │   │   │       └── page.tsx    # Bill detail + line items
    │   │   │   └── maintenance/
    │   │   │       ├── page.tsx        # Own ticket list
    │   │   │       ├── new/
    │   │   │       │   └── page.tsx    # Submit ticket form + photo upload
    │   │   │       └── [ticketId]/
    │   │   │           └── page.tsx    # Ticket detail + status + comments
    │   │   │
    │   │   ├── technician/             # Technician-only pages
    │   │   │   ├── dashboard/
    │   │   │   │   └── page.tsx        # Overview: assigned open tickets
    │   │   │   └── tickets/
    │   │   │       ├── page.tsx        # Assigned ticket list
    │   │   │       └── [ticketId]/
    │   │   │           └── page.tsx    # Ticket detail + status update + comments
    │   │   │
    │   │   ├── housekeeper/            # Housekeeper-only pages
    │   │   │   ├── dashboard/
    │   │   │   │   └── page.tsx        # Today's tasks + weekly view
    │   │   │   └── tasks/
    │   │   │       └── [taskId]/
    │   │   │           └── page.tsx    # Task detail + mark complete + notes
    │   │   │
    │   │   └── notifications/          # Shared across all roles
    │   │       └── page.tsx            # Full notification inbox
    │   │
    │   └── api/
    │       └── webhooks/
    │           └── line/
    │               └── route.ts        # LINE webhook ingest + HMAC validation
    │
    ├── components/
    │   ├── ui/                         # shadcn/ui primitives (auto-generated, do not hand-edit)
    │   │   ├── button.tsx
    │   │   ├── card.tsx
    │   │   ├── dialog.tsx
    │   │   ├── input.tsx
    │   │   ├── select.tsx
    │   │   ├── table.tsx
    │   │   └── ...
    │   ├── layout/                     # App shell components
    │   │   ├── sidebar.tsx             # Role-aware navigation sidebar
    │   │   ├── topnav.tsx              # Top navigation bar
    │   │   ├── notification-bell.tsx   # Realtime notification badge + popover
    │   │   └── page-header.tsx         # Reusable page heading with breadcrumbs
    │   ├── auth/
    │   │   ├── login-form.tsx          # Email/password sign-in form
    │   │   └── forgot-password-form.tsx
    │   ├── rooms/
    │   │   ├── room-card.tsx           # Room status card (used in list + detail)
    │   │   ├── room-form.tsx           # Create/edit room form
    │   │   └── room-status-badge.tsx   # Colour-coded status pill
    │   ├── tenants/
    │   │   ├── tenant-card.tsx
    │   │   ├── tenant-form.tsx
    │   │   └── lease-status-badge.tsx
    │   ├── billing/
    │   │   ├── bill-card.tsx
    │   │   ├── bill-form.tsx           # Generate bill + line item editor
    │   │   ├── line-item-row.tsx
    │   │   └── bill-status-badge.tsx
    │   ├── maintenance/
    │   │   ├── ticket-card.tsx
    │   │   ├── ticket-form.tsx         # Submit ticket + attachment upload
    │   │   ├── ticket-comments.tsx     # Comment thread
    │   │   ├── priority-badge.tsx
    │   │   └── ticket-status-badge.tsx
    │   ├── housekeeping/
    │   │   ├── task-card.tsx
    │   │   ├── task-form.tsx
    │   │   └── task-status-badge.tsx
    │   └── notifications/
    │       ├── notification-item.tsx   # Single notification row
    │       └── notification-list.tsx   # Paginated inbox
    │
    ├── lib/
    │   ├── supabase/
    │   │   ├── client.ts               # Browser Supabase client (createBrowserClient)
    │   │   ├── server.ts               # Server Supabase client (createServerClient)
    │   │   └── middleware.ts           # updateSession() helper
    │   ├── line/
    │   │   ├── client.ts               # LINE SDK wrapper (pushMessage, validateSignature)
    │   │   └── messages.ts             # Flex message templates
    │   ├── actions/                    # Next.js Server Actions (all mutations)
    │   │   ├── auth.ts                 # signIn, signOut, resetPassword
    │   │   ├── rooms.ts                # createRoom, updateRoom, archiveRoom
    │   │   ├── tenants.ts              # createTenant, updateTenant, archiveTenant
    │   │   ├── billing.ts              # createBill, updateBill, markBillPaid, addLineItem
    │   │   ├── maintenance.ts          # createTicket, updateTicket, assignTicket, addComment
    │   │   ├── housekeeping.ts         # createTask, updateTask, assignTask, completeTask
    │   │   └── notifications.ts        # markRead, markAllRead
    │   ├── validations/                # Zod schemas (shared by actions + forms)
    │   │   ├── room.ts
    │   │   ├── tenant.ts
    │   │   ├── bill.ts
    │   │   ├── ticket.ts
    │   │   └── task.ts
    │   └── utils.ts                    # cn() and other utility functions
    │
    ├── hooks/
    │   ├── use-realtime-notifications.ts  # Supabase Realtime subscription for notifications
    │   ├── use-realtime-tickets.ts        # Realtime subscription for ticket board (manager)
    │   └── use-realtime-tasks.ts          # Realtime subscription for task list (housekeeper)
    │
    └── types/
        ├── database.ts                 # Generated by `supabase gen types typescript`
        └── index.ts                    # App-level type aliases and utility types
```

---

## 3. Key Conventions

### 3.1 Server vs Client Components

| Pattern | Convention |
|---|---|
| Pages (`page.tsx`) | Server Components by default — fetch data directly |
| Forms and interactive widgets | Client Components — named `*-form.tsx`, `*-card.tsx` |
| Components with `useState`/`useEffect` | Must include `'use client'` directive at top |
| Server Actions | Regular TypeScript files, exported async functions with `'use server'` directive |

### 3.2 Data Fetching

- **Initial load**: `page.tsx` (Server Component) fetches via `supabase/server.ts` client — no loading spinners for above-the-fold content
- **Mutations**: Client Components call Server Actions via `useTransition` or form `action` prop
- **Realtime updates**: Client Components use custom hooks in `src/hooks/` that subscribe to Supabase Realtime channels

### 3.3 Naming Conventions

| File type | Convention | Example |
|---|---|---|
| Pages | lowercase with hyphens | `page.tsx` |
| Components | PascalCase | `RoomCard.tsx` → `room-card.tsx` (kebab) |
| Server Actions | camelCase, verb-noun | `createRoom`, `markBillPaid` |
| Zod schemas | camelCase, domain name | `roomSchema`, `createBillSchema` |
| Types | PascalCase | `Room`, `Tenant`, `Bill` |
| Database types | suffix `Row` for table types | `RoomRow`, `TenantRow` |

### 3.4 Environment Variables

| Variable | Used in | Description |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Client + Server | Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Client + Server | Supabase anon key |
| `SUPABASE_SERVICE_ROLE_KEY` | Server only | Service role for webhook/admin ops |
| `LINE_CHANNEL_ACCESS_TOKEN` | Server only | LINE SDK outbound token |
| `LINE_CHANNEL_SECRET` | Server only | HMAC webhook signature validation |
| `ROLE_CACHE_SECRET` | Server only | 32-byte secret for HMAC-signing the role cache cookie (see `02-system-architecture.md` §11) |

---

## 4. Supabase CLI Workspace

The `supabase/` directory at repo root is managed by the Supabase CLI and is separate from the Next.js app:

```
supabase/
├── config.toml                         # Project ID, local dev settings
├── migrations/
│   ├── 20240101000000_initial_schema.sql    # Enums + all tables
│   ├── 20240102000000_rls_policies.sql      # All RLS policies
│   └── 20240103000000_triggers.sql          # Triggers + helper functions
├── seed.sql                                  # Dev-only test data
└── tests/
    └── rls_policies.test.sql                 # pgTAP RLS tests
```
