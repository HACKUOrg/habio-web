-- Habio initial schema
-- See docs/03-database-schema.md

-- Extensions
CREATE EXTENSION IF NOT EXISTS "pg_cron" WITH SCHEMA "pg_catalog";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Custom types
CREATE TYPE public.user_role AS ENUM ('manager', 'tenant', 'technician', 'housekeeper');
CREATE TYPE public.room_type AS ENUM ('single', 'double', 'studio', 'suite');
CREATE TYPE public.room_status AS ENUM ('available', 'occupied', 'maintenance');
CREATE TYPE public.lease_status AS ENUM ('active', 'expiring', 'expired', 'terminated');
CREATE TYPE public.bill_status AS ENUM ('draft', 'pending', 'paid', 'overdue');
CREATE TYPE public.ticket_priority AS ENUM ('low', 'medium', 'high', 'urgent');
CREATE TYPE public.ticket_status AS ENUM ('open', 'in_progress', 'resolved', 'closed');
CREATE TYPE public.task_status AS ENUM ('pending', 'in_progress', 'completed', 'skipped');
CREATE TYPE public.notification_type AS ENUM (
  'bill_issued',
  'bill_overdue',
  'ticket_opened',
  'ticket_assigned',
  'ticket_status_updated',
  'ticket_comment_added',
  'task_assigned',
  'task_completed',
  'lease_expiring'
);

-- profiles
CREATE TABLE public.profiles (
  id            uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name     text NOT NULL,
  phone         text,
  role          public.user_role NOT NULL DEFAULT 'tenant',
  avatar_url    text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_profiles_role ON public.profiles (role);

-- properties
CREATE TABLE public.properties (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  manager_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  name        text NOT NULL,
  address     text NOT NULL,
  description text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_properties_manager_id ON public.properties (manager_id);

-- rooms
CREATE TABLE public.rooms (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id   uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  room_number   text NOT NULL,
  floor         integer NOT NULL DEFAULT 1,
  room_type     public.room_type NOT NULL DEFAULT 'single',
  status        public.room_status NOT NULL DEFAULT 'available',
  monthly_rate  numeric(10, 2) NOT NULL CHECK (monthly_rate >= 0),
  notes         text,
  archived_at   timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (property_id, room_number)
);

CREATE INDEX idx_rooms_property_id ON public.rooms (property_id);
CREATE INDEX idx_rooms_status ON public.rooms (property_id, status);

-- tenants
CREATE TABLE public.tenants (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  property_id              uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
  room_id                  uuid NOT NULL REFERENCES public.rooms(id) ON DELETE RESTRICT,
  lease_start              date NOT NULL,
  lease_end                date,
  lease_status             public.lease_status NOT NULL DEFAULT 'active',
  emergency_contact_name   text,
  emergency_contact_phone  text,
  notes                    text,
  archived_at              timestamptz,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_tenants_user_id ON public.tenants (user_id);
CREATE INDEX idx_tenants_property_id ON public.tenants (property_id);
CREATE INDEX idx_tenants_room_id ON public.tenants (room_id);
CREATE INDEX idx_tenants_lease_status ON public.tenants (property_id, lease_status);

CREATE UNIQUE INDEX tenants_one_active_per_room
  ON public.tenants (room_id)
  WHERE lease_status = 'active' AND archived_at IS NULL;

-- bills
CREATE TABLE public.bills (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id             uuid NOT NULL REFERENCES public.tenants(id) ON DELETE RESTRICT,
  property_id           uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
  room_id               uuid NOT NULL REFERENCES public.rooms(id) ON DELETE RESTRICT,
  billing_period_start  date NOT NULL,
  billing_period_end    date NOT NULL,
  total_amount          numeric(10, 2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
  status                public.bill_status NOT NULL DEFAULT 'draft',
  due_date              date NOT NULL,
  paid_at               timestamptz,
  notes                 text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CHECK (billing_period_end > billing_period_start)
);

CREATE INDEX idx_bills_tenant_id ON public.bills (tenant_id);
CREATE INDEX idx_bills_property_id ON public.bills (property_id);
CREATE INDEX idx_bills_status ON public.bills (property_id, status);
CREATE INDEX idx_bills_overdue ON public.bills (status, due_date);

-- bill_line_items
CREATE TABLE public.bill_line_items (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bill_id      uuid NOT NULL REFERENCES public.bills(id) ON DELETE CASCADE,
  description  text NOT NULL,
  quantity     numeric(10, 3) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price   numeric(10, 2) NOT NULL CHECK (unit_price >= 0),
  amount       numeric(10, 2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
  sort_order   integer NOT NULL DEFAULT 0
);

CREATE INDEX idx_bill_line_items_bill_id ON public.bill_line_items (bill_id);

-- maintenance_tickets
CREATE TABLE public.maintenance_tickets (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id  uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
  room_id      uuid NOT NULL REFERENCES public.rooms(id) ON DELETE RESTRICT,
  tenant_id    uuid REFERENCES public.tenants(id) ON DELETE SET NULL,
  assigned_to  uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  title        text NOT NULL,
  description  text,
  priority     public.ticket_priority NOT NULL DEFAULT 'medium',
  status       public.ticket_status NOT NULL DEFAULT 'open',
  resolved_at  timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_tickets_property_id ON public.maintenance_tickets (property_id);
CREATE INDEX idx_tickets_assigned_to ON public.maintenance_tickets (assigned_to);
CREATE INDEX idx_tickets_status ON public.maintenance_tickets (property_id, status);
CREATE INDEX idx_tickets_tenant_id ON public.maintenance_tickets (tenant_id);

-- maintenance_comments
CREATE TABLE public.maintenance_comments (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id  uuid NOT NULL REFERENCES public.maintenance_tickets(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  content    text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_comments_ticket_id ON public.maintenance_comments (ticket_id, created_at);

-- maintenance_attachments
CREATE TABLE public.maintenance_attachments (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id        uuid NOT NULL REFERENCES public.maintenance_tickets(id) ON DELETE CASCADE,
  storage_path     text NOT NULL,
  filename         text NOT NULL,
  file_size_bytes  integer NOT NULL CHECK (file_size_bytes > 0),
  mime_type        text NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- housekeeping_tasks
CREATE TABLE public.housekeeping_tasks (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id       uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
  room_id           uuid NOT NULL REFERENCES public.rooms(id) ON DELETE RESTRICT,
  assigned_to       uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_by        uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  scheduled_date    date NOT NULL,
  status            public.task_status NOT NULL DEFAULT 'pending',
  notes             text,
  completion_notes  text,
  completed_at      timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_tasks_property_id ON public.housekeeping_tasks (property_id);
CREATE INDEX idx_tasks_assigned_to ON public.housekeeping_tasks (assigned_to, scheduled_date);
CREATE INDEX idx_tasks_scheduled_date ON public.housekeeping_tasks (property_id, scheduled_date);

-- notifications
CREATE TABLE public.notifications (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type       public.notification_type NOT NULL,
  title      text NOT NULL,
  body       text NOT NULL,
  data       jsonb,
  is_read    boolean NOT NULL DEFAULT false,
  read_at    timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_notifications_user_id ON public.notifications (user_id, is_read, created_at DESC);
CREATE INDEX idx_notifications_created_at_brin ON public.notifications USING BRIN (created_at);

-- notifications_archive
CREATE TABLE public.notifications_archive (
  id          uuid PRIMARY KEY,
  user_id     uuid NOT NULL,
  type        public.notification_type NOT NULL,
  title       text NOT NULL,
  body        text NOT NULL,
  data        jsonb,
  is_read     boolean NOT NULL DEFAULT false,
  read_at     timestamptz,
  created_at  timestamptz NOT NULL,
  archived_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_notifications_archive_user_id ON public.notifications_archive (user_id, created_at DESC);

-- property_staff
CREATE TABLE public.property_staff (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id  uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role         public.user_role NOT NULL CHECK (role IN ('technician', 'housekeeper')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (property_id, user_id)
);

CREATE INDEX idx_property_staff_property_id ON public.property_staff (property_id, role);
CREATE INDEX idx_property_staff_user_id ON public.property_staff (user_id);

-- line_connections
CREATE TABLE public.line_connections (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  line_user_id  text NOT NULL,
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (line_user_id),
  UNIQUE (user_id)
);

CREATE INDEX idx_line_connections_user_id ON public.line_connections (user_id);
CREATE INDEX idx_line_connections_line_user_id ON public.line_connections (line_user_id);

-- Data API grants
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated;
