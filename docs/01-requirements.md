# 01 — Requirements

## 1. Overview

Habio is a multi-property dormitory management SaaS. A single deployment serves multiple **organizations**, each owning one or more **properties**. Each property contains one or more **buildings**, and each building contains **rooms**.

The entity hierarchy is:

```
Organization → Property → Building → Room
```

**Managers** may operate a single property, multiple properties within an organization, or an entire organization. **Tenants**, **technicians**, and **housekeepers** interact with the platform through role-scoped views. See [09-multi-property.md](./09-multi-property.md) for the full architecture reference.

---

## 2. Roles

| Role | Description |
|---|---|
| **Manager** | Owns or operates one or more properties within an organization. May manage a single property, multiple properties, or an entire organization (via org-level admin scope). |
| **Tenant** | Rents a room. Views bills, raises maintenance tickets, checks housekeeping schedule. |
| **Technician** | Handles assigned maintenance tickets. Updates ticket progress and adds comments. |
| **Housekeeper** | Handles assigned cleaning tasks. Enters and submits meter readings for assigned properties. |

> A user has exactly one role. Role is stored in `profiles.role` and enforced by Row Level Security (RLS) plus Next.js middleware.

---

## 3. Feature Modules

### 3.1 Authentication

- Email + password sign-in via Supabase Auth
- Password reset via email link
- Session management via HTTP-only cookies (`@supabase/ssr`)
- Post-login redirect to role-specific dashboard
- Middleware-enforced route protection

### 3.2 Organization Management

- Create and manage organizations (property groups)
- Organization attributes: name, slug, plan
- Invite org members with scope: `owner`, `admin`, `viewer`
- Org owner/admin can manage all properties within the organization
- See [09-multi-property.md](./09-multi-property.md) §3 for hierarchy details

### 3.3 Property Management

- Create, update, and archive properties within an organization
- Property attributes: name, address, phone, status (`active`, `inactive`, `archived`)
- Assign a property manager (`properties.manager_id`)
- Property list filtered by organization context

### 3.4 Building Management

- Create, update buildings within a property
- Building attributes: name, total floors
- Buildings group rooms within a property (e.g., Building A, Building B)
- At least one building per property

### 3.5 Room Management

- Create, update, and archive rooms within a building
- Room attributes: number, floor, type (single/double/studio/suite), monthly rate, status
- Room statuses: `available`, `occupied`, `maintenance`
- Room numbers unique per property (across all buildings)
- Bulk room import (v2)

### 3.6 Tenant Management

- Invite or manually create tenant accounts linked to a room
- Lease lifecycle: active, expiring, expired, terminated
- Lease dates, emergency contact, and move-in notes
- Automatic room status update on lease start/end
- Tenant directory with search and filtering

### 3.7 Billing

- Manager generates monthly bills per tenant
- Bills contain line items: rent, utilities, late fees, one-off charges
- Bill statuses: `draft`, `pending`, `paid`, `overdue`
- Mark bill as paid (manual confirmation, no gateway in v1)
- Tenant views their bill history and current outstanding balance
- Overdue detection based on due date
- Utility charges can be generated from approved meter readings
- Payment gateway integration (v2)

### 3.8 Meter Reading

- Manager opens a billing period for a property (start/end dates)
- System pre-creates meter reading rows for all occupied rooms
- Housekeeper enters meter readings by property or building
- Housekeeper submits readings for manager review
- Manager reviews, approves, or rejects readings
- Manager generates utility bill line items from approved readings
- Billing period statuses: `open`, `closed`, `archived`
- Meter reading statuses: `pending`, `submitted`, `approved`, `rejected`
- Readings are immutable once the billing period is closed

### 3.9 Maintenance Tickets

- Tenant submits a maintenance request with title, description, and photo attachment
- Priority levels: `low`, `medium`, `high`, `urgent`
- Ticket statuses: `open`, `in_progress`, `resolved`, `closed`
- Manager assigns ticket to a technician
- Technician updates status and adds progress comments
- Notification sent to tenant on status change
- Manager views all tickets across property with filters

### 3.10 Housekeeping

- Manager creates housekeeping tasks with room, date, and notes
- Task statuses: `pending`, `in_progress`, `completed`, `skipped`
- Assign task to a housekeeper
- Housekeeper views their daily/weekly task list
- Housekeeper marks tasks complete with optional notes
- Manager monitors completion rates

### 3.11 Notifications

- In-app notification inbox for all roles
- Notification triggers:
  - Tenant: bill issued, bill overdue, ticket status update, housekeeping scheduled
  - Manager: ticket opened, ticket resolved, payment received (v2)
  - Technician: ticket assigned, ticket comment added
  - Housekeeper: task assigned
- LINE Messaging API push notifications (mirrors in-app notifications)
- Read/unread state per notification
- Real-time delivery via Supabase Realtime

---

## 4. User Stories

### Organization Owner / Admin

| ID | Story |
|---|---|
| O-01 | As an Organization Owner, I want to create an organization so I can group my properties under one account. |
| O-02 | As an Organization Owner, I want to add properties to my organization so I can manage multiple dormitory sites. |
| O-03 | As an Organization Owner, I want to invite other managers as org admins so they can help manage all properties. |
| O-04 | As an Organization Admin, I want to view all properties in my organization so I have a unified overview. |

### Manager

| ID | Story |
|---|---|
| M-01 | As a Manager, I want to add buildings to my property so I can organise rooms by structure. |
| M-02 | As a Manager, I want to add rooms to a building so I can track occupancy. |
| M-03 | As a Manager, I want to create a tenant account and assign them to a room so they can access the platform. |
| M-04 | As a Manager, I want to generate a monthly bill for a tenant so rent and utilities are tracked. |
| M-05 | As a Manager, I want to mark a bill as paid so I can reconcile payments. |
| M-06 | As a Manager, I want to open a billing period and review meter readings so utility charges are accurate. |
| M-07 | As a Manager, I want to approve meter readings and generate utility bill line items so billing is automated. |
| M-08 | As a Manager, I want to view all open maintenance tickets so I can prioritise repairs. |
| M-09 | As a Manager, I want to assign a maintenance ticket to a technician so work is allocated. |
| M-10 | As a Manager, I want to create and assign housekeeping tasks so cleaning is scheduled. |
| M-11 | As a Manager, I want to view a dashboard summary of occupancy, outstanding bills, and open tickets across my properties. |
| M-12 | As a Manager, I want to switch between properties so I can manage multiple sites from one account. |

### Tenant

| ID | Story |
|---|---|
| T-01 | As a Tenant, I want to view my current bill so I know what I owe. |
| T-02 | As a Tenant, I want to view my billing history so I can track past payments. |
| T-03 | As a Tenant, I want to raise a maintenance ticket so I can report an issue in my room. |
| T-04 | As a Tenant, I want to see the status of my maintenance tickets so I know when my issue is being fixed. |
| T-05 | As a Tenant, I want to receive notifications so I am informed of changes without logging in. |
| T-06 | As a Tenant, I want to view my room details and lease dates so I can plan my stay. |

### Technician

| ID | Story |
|---|---|
| TC-01 | As a Technician, I want to view my assigned tickets so I know what work I need to do. |
| TC-02 | As a Technician, I want to update the status of a ticket so the manager and tenant are kept informed. |
| TC-03 | As a Technician, I want to add comments to a ticket so I can record progress notes and request clarification. |

### Housekeeper

| ID | Story |
|---|---|
| HK-01 | As a Housekeeper, I want to view my assigned tasks for the day so I can plan my rounds. |
| HK-02 | As a Housekeeper, I want to mark a task as complete so the manager knows the room has been cleaned. |
| HK-03 | As a Housekeeper, I want to add notes to a task so I can flag issues in a room. |
| HK-04 | As a Housekeeper, I want to enter meter readings by property or building so utility usage is recorded. |
| HK-05 | As a Housekeeper, I want to submit meter readings for manager review so the billing process can proceed. |

---

## 5. Non-Functional Requirements

### 5.1 Performance

- Time to first byte (TTFB) < 200 ms for server-rendered dashboard pages
- Largest Contentful Paint (LCP) < 2.5 s on a standard mobile connection
- Database queries targeting <50 ms p95 via proper indexing

### 5.2 Security

- All routes protected by Supabase Auth session validation in middleware
- RLS policies enforce data isolation between organizations and properties
- No cross-org or cross-property data leakage — a manager cannot read another organization's data
- Org-level access validated via `organization_members` in addition to `properties.manager_id`
- Passwords never stored in application layer (delegated to Supabase Auth)
- LINE webhook endpoint validated with channel signature (HMAC-SHA256)
- Environment secrets never exposed to the client bundle

### 5.3 Availability & Reliability

- Target 99.9% uptime (Supabase + Vercel SLA)
- Graceful error boundaries on all dashboard pages
- Optimistic UI updates with rollback on error

### 5.4 Scalability

- Multi-property, multi-organization architecture; shared schema with RLS (no per-tenant database isolation)
- Organization → Property → Building → Room hierarchy supports SaaS growth
- Keyset (cursor-based) pagination on all list views (default page size: 20); offset pagination is not permitted on operational tables at scale
- `organization_id` denormalized on all operational tables for org-level RLS and analytics without joins
- Supabase connection pooling via PgBouncer

### 5.5 Accessibility

- WCAG 2.1 AA compliance target
- Keyboard-navigable UI
- Minimum 4.5:1 colour contrast ratio

### 5.6 Internationalisation

- v1: Thai and English language support
- Date, currency (THB), and number formatting per locale

### 5.7 Auditability

- Created/updated timestamps on all tables
- Soft-delete pattern for rooms and tenants (archived flag, not hard delete)

---

## 6. Out of Scope (v1)

- Online payment gateway integration
- Platform-level subscription billing (Stripe for org plans)
- Bulk room/tenant import via CSV
- Custom billing cycles (non-monthly)
- Multi-language LINE bot responses
- Native mobile application
- Accounting/ERP integrations
- Custom domains / white-labeling per organization
- Audit log for enterprise compliance
- IoT meter auto-read integration
