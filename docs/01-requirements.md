# 01 — Requirements

## 1. Overview

Habio is a multi-tenant dormitory management SaaS. A single deployment serves multiple dormitory **properties**, each operated independently by its own **Manager**. Tenants, technicians, and housekeepers interact with the platform through role-scoped views.

---

## 2. Roles

| Role | Description |
|---|---|
| **Manager** | Owns or operates one or more properties. Full administrative control within their properties. |
| **Tenant** | Rents a room. Views bills, raises maintenance tickets, checks housekeeping schedule. |
| **Technician** | Handles assigned maintenance tickets. Updates ticket progress and adds comments. |
| **Housekeeper** | Handles assigned cleaning tasks. Updates task status. |

> A user has exactly one role. Role is stored in `profiles.role` and enforced by Row Level Security (RLS) plus Next.js middleware.

---

## 3. Feature Modules

### 3.1 Authentication

- Email + password sign-in via Supabase Auth
- Password reset via email link
- Session management via HTTP-only cookies (`@supabase/ssr`)
- Post-login redirect to role-specific dashboard
- Middleware-enforced route protection

### 3.2 Room Management

- Create, update, and archive rooms within a property
- Room attributes: number, floor, type (single/double/studio), monthly rate, status
- Room statuses: `available`, `occupied`, `maintenance`
- Bulk room import (v2)

### 3.3 Tenant Management

- Invite or manually create tenant accounts linked to a room
- Lease lifecycle: active, expiring, expired, terminated
- Lease dates, emergency contact, and move-in notes
- Automatic room status update on lease start/end
- Tenant directory with search and filtering

### 3.4 Billing

- Manager generates monthly bills per tenant
- Bills contain line items: rent, utilities, late fees, one-off charges
- Bill statuses: `draft`, `pending`, `paid`, `overdue`
- Mark bill as paid (manual confirmation, no gateway in v1)
- Tenant views their bill history and current outstanding balance
- Overdue detection based on due date
- Payment gateway integration (v2)

### 3.5 Maintenance Tickets

- Tenant submits a maintenance request with title, description, and photo attachment
- Priority levels: `low`, `medium`, `high`, `urgent`
- Ticket statuses: `open`, `in_progress`, `resolved`, `closed`
- Manager assigns ticket to a technician
- Technician updates status and adds progress comments
- Notification sent to tenant on status change
- Manager views all tickets across property with filters

### 3.6 Housekeeping

- Manager creates housekeeping tasks with room, date, and notes
- Task statuses: `pending`, `in_progress`, `completed`, `skipped`
- Assign task to a housekeeper
- Housekeeper views their daily/weekly task list
- Housekeeper marks tasks complete with optional notes
- Manager monitors completion rates

### 3.7 Notifications

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

### Manager

| ID | Story |
|---|---|
| M-01 | As a Manager, I want to add rooms to my property so I can track occupancy. |
| M-02 | As a Manager, I want to create a tenant account and assign them to a room so they can access the platform. |
| M-03 | As a Manager, I want to generate a monthly bill for a tenant so rent and utilities are tracked. |
| M-04 | As a Manager, I want to mark a bill as paid so I can reconcile payments. |
| M-05 | As a Manager, I want to view all open maintenance tickets so I can prioritise repairs. |
| M-06 | As a Manager, I want to assign a maintenance ticket to a technician so work is allocated. |
| M-07 | As a Manager, I want to create and assign housekeeping tasks so cleaning is scheduled. |
| M-08 | As a Manager, I want to view a dashboard summary of occupancy, outstanding bills, and open tickets. |

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

---

## 5. Non-Functional Requirements

### 5.1 Performance

- Time to first byte (TTFB) < 200 ms for server-rendered dashboard pages
- Largest Contentful Paint (LCP) < 2.5 s on a standard mobile connection
- Database queries targeting <50 ms p95 via proper indexing

### 5.2 Security

- All routes protected by Supabase Auth session validation in middleware
- RLS policies enforce data isolation between properties
- No cross-property data leakage — a manager cannot read another manager's data
- Passwords never stored in application layer (delegated to Supabase Auth)
- LINE webhook endpoint validated with channel signature (HMAC-SHA256)
- Environment secrets never exposed to the client bundle

### 5.3 Availability & Reliability

- Target 99.9% uptime (Supabase + Vercel SLA)
- Graceful error boundaries on all dashboard pages
- Optimistic UI updates with rollback on error

### 5.4 Scalability

- Multi-property architecture from day one; no per-tenant database isolation
- Pagination on all list views (default page size: 20)
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
- Bulk room/tenant import via CSV
- Custom billing cycles (non-monthly)
- Multi-language LINE bot responses
- Native mobile application
- Accounting/ERP integrations
