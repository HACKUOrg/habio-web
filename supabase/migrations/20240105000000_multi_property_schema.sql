-- Phase 0A: Multi-property additive schema
-- See docs/09-multi-property.md §10 Phase A and docs/03-database-schema.md

-- ============================================================
-- New enums
-- ============================================================
CREATE TYPE public.organization_member_scope AS ENUM ('owner', 'admin', 'viewer');
CREATE TYPE public.property_status AS ENUM ('active', 'inactive', 'archived');
CREATE TYPE public.billing_period_status AS ENUM ('open', 'closed', 'archived');
CREATE TYPE public.meter_reading_status AS ENUM ('pending', 'submitted', 'approved', 'rejected');

ALTER TYPE public.notification_type ADD VALUE IF NOT EXISTS 'meter_reading_submitted';
ALTER TYPE public.notification_type ADD VALUE IF NOT EXISTS 'meter_reading_approved';
ALTER TYPE public.notification_type ADD VALUE IF NOT EXISTS 'meter_reading_rejected';

-- ============================================================
-- organizations
-- ============================================================
CREATE TABLE public.organizations (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL,
  slug       text NOT NULL UNIQUE,
  owner_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  plan       text NOT NULL DEFAULT 'free',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_organizations_owner_id ON public.organizations (owner_id);

-- ============================================================
-- organization_members
-- ============================================================
CREATE TABLE public.organization_members (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  scope           public.organization_member_scope NOT NULL DEFAULT 'viewer',
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, user_id)
);

CREATE INDEX idx_org_members_user_scope
  ON public.organization_members (user_id, organization_id, scope);

-- ============================================================
-- buildings
-- ============================================================
CREATE TABLE public.buildings (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id  uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  name         text NOT NULL,
  total_floors integer NOT NULL DEFAULT 1 CHECK (total_floors >= 1),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  UNIQUE (property_id, name)
);

CREATE INDEX idx_buildings_property_id ON public.buildings (property_id);

-- ============================================================
-- billing_periods
-- ============================================================
CREATE TABLE public.billing_periods (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  property_id uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
  name        text NOT NULL,
  start_date  date NOT NULL,
  end_date    date NOT NULL,
  status      public.billing_period_status NOT NULL DEFAULT 'open',
  created_by  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CHECK (end_date > start_date)
);

CREATE INDEX idx_billing_periods_property_id ON public.billing_periods (property_id);
CREATE INDEX idx_billing_periods_status ON public.billing_periods (property_id, status);

CREATE UNIQUE INDEX billing_periods_one_open_per_property
  ON public.billing_periods (property_id)
  WHERE status = 'open';

-- ============================================================
-- meter_readings
-- ============================================================
CREATE TABLE public.meter_readings (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  billing_period_id uuid NOT NULL REFERENCES public.billing_periods(id) ON DELETE RESTRICT,
  room_id           uuid NOT NULL REFERENCES public.rooms(id) ON DELETE RESTRICT,
  property_id       uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
  previous_reading  numeric(10, 2) NOT NULL DEFAULT 0 CHECK (previous_reading >= 0),
  current_reading   numeric(10, 2) CHECK (current_reading >= 0),
  reading_date      date,
  submitted_by      uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  approved_by       uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  status            public.meter_reading_status NOT NULL DEFAULT 'pending',
  notes             text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (billing_period_id, room_id)
);

CREATE INDEX idx_meter_readings_billing_period_id ON public.meter_readings (billing_period_id);
CREATE INDEX idx_meter_readings_room_id ON public.meter_readings (room_id);
CREATE INDEX idx_meter_readings_property_id ON public.meter_readings (property_id);
CREATE INDEX idx_meter_readings_status ON public.meter_readings (billing_period_id, status);

-- ============================================================
-- Alter existing tables (nullable FKs until backfill)
-- ============================================================
ALTER TABLE public.properties
  ADD COLUMN organization_id uuid REFERENCES public.organizations(id) ON DELETE RESTRICT,
  ADD COLUMN phone text,
  ADD COLUMN status public.property_status NOT NULL DEFAULT 'active';

CREATE INDEX idx_properties_organization_id ON public.properties (organization_id);
CREATE INDEX idx_properties_status ON public.properties (organization_id, status);

ALTER TABLE public.rooms
  ADD COLUMN building_id uuid REFERENCES public.buildings(id) ON DELETE RESTRICT;

CREATE INDEX idx_rooms_building_id ON public.rooms (building_id);

ALTER TABLE public.bills
  ADD COLUMN organization_id uuid REFERENCES public.organizations(id) ON DELETE RESTRICT,
  ADD COLUMN billing_period_id uuid REFERENCES public.billing_periods(id) ON DELETE SET NULL;

CREATE INDEX idx_bills_organization_id_status ON public.bills (organization_id, status);
CREATE INDEX idx_bills_billing_period_id ON public.bills (billing_period_id);

ALTER TABLE public.maintenance_tickets
  ADD COLUMN organization_id uuid REFERENCES public.organizations(id) ON DELETE RESTRICT;

CREATE INDEX idx_tickets_organization_id_status ON public.maintenance_tickets (organization_id, status);

-- ============================================================
-- updated_at triggers for new tables
-- ============================================================
CREATE TRIGGER set_updated_at_organizations
  BEFORE UPDATE ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_buildings
  BEFORE UPDATE ON public.buildings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_billing_periods
  BEFORE UPDATE ON public.billing_periods
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_meter_readings
  BEFORE UPDATE ON public.meter_readings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
