-- Phase 0A: Membership-based RBAC additive schema
-- See docs/03-database-schema.md and docs/06-implementation-roadmap.md §9

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;

-- ============================================================
-- New enums
-- ============================================================
CREATE TYPE public.membership_role AS ENUM (
  'owner',
  'manager',
  'technician',
  'housekeeper',
  'tenant'
);

CREATE TYPE public.invitation_status AS ENUM (
  'pending',
  'accepted',
  'expired',
  'revoked'
);

-- ============================================================
-- memberships
-- ============================================================
CREATE TABLE public.memberships (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  property_id     uuid REFERENCES public.properties(id) ON DELETE CASCADE,
  role            public.membership_role NOT NULL,
  created_by      uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  deactivated_at  timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT memberships_scope_check CHECK (
    (role = 'owner' AND property_id IS NULL)
    OR (role <> 'owner' AND property_id IS NOT NULL)
  )
);

CREATE INDEX idx_memberships_user_active
  ON public.memberships (user_id, role, organization_id, property_id)
  WHERE deactivated_at IS NULL;

CREATE INDEX idx_memberships_org_role
  ON public.memberships (organization_id, role)
  WHERE deactivated_at IS NULL;

CREATE INDEX idx_memberships_property_role
  ON public.memberships (property_id, role)
  WHERE deactivated_at IS NULL;

CREATE INDEX idx_memberships_created_by
  ON public.memberships (created_by);

-- ============================================================
-- invitations
-- ============================================================
CREATE TABLE public.invitations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  property_id     uuid NOT NULL REFERENCES public.properties(id) ON DELETE CASCADE,
  email           citext NOT NULL,
  role            public.membership_role NOT NULL
    CHECK (role IN ('manager', 'technician', 'housekeeper', 'tenant')),
  token_hash      text NOT NULL UNIQUE,
  status          public.invitation_status NOT NULL DEFAULT 'pending',
  expires_at      timestamptz NOT NULL,
  invited_by      uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  accepted_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT invitations_property_scope_check CHECK (property_id IS NOT NULL)
);

CREATE INDEX idx_invitations_email_status
  ON public.invitations (lower(email::text), status);

CREATE INDEX idx_invitations_org_status
  ON public.invitations (organization_id, status, created_at DESC);

CREATE INDEX idx_invitations_property_role
  ON public.invitations (property_id, role, status);

-- ============================================================
-- tenant_profiles
-- ============================================================
CREATE TABLE public.tenant_profiles (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  membership_id            uuid NOT NULL REFERENCES public.memberships(id) ON DELETE RESTRICT,
  organization_id          uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
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
  updated_at               timestamptz NOT NULL DEFAULT now(),
  UNIQUE (membership_id)
);

CREATE INDEX idx_tenant_profiles_user_id
  ON public.tenant_profiles (user_id);

CREATE INDEX idx_tenant_profiles_organization_id
  ON public.tenant_profiles (organization_id);

CREATE INDEX idx_tenant_profiles_property_id
  ON public.tenant_profiles (property_id);

CREATE INDEX idx_tenant_profiles_room_id
  ON public.tenant_profiles (room_id);

CREATE INDEX idx_tenant_profiles_lease_status
  ON public.tenant_profiles (property_id, lease_status);

CREATE UNIQUE INDEX tenant_profiles_one_active_per_room
  ON public.tenant_profiles (room_id)
  WHERE lease_status = 'active' AND archived_at IS NULL;

CREATE TRIGGER set_updated_at_tenant_profiles
  BEFORE UPDATE ON public.tenant_profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================
-- Denormalize organization_id on operational tables (nullable until backfill)
-- ============================================================
ALTER TABLE public.billing_periods
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE RESTRICT;

ALTER TABLE public.meter_readings
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE RESTRICT;

ALTER TABLE public.housekeeping_tasks
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_billing_periods_organization_id
  ON public.billing_periods (organization_id);

CREATE INDEX IF NOT EXISTS idx_meter_readings_organization_id
  ON public.meter_readings (organization_id);

CREATE INDEX IF NOT EXISTS idx_housekeeping_tasks_organization_id
  ON public.housekeeping_tasks (organization_id);

-- ============================================================
-- Migrate bills and tickets to tenant_profile_id (nullable until backfill)
-- ============================================================
ALTER TABLE public.bills
  ADD COLUMN IF NOT EXISTS tenant_profile_id uuid REFERENCES public.tenant_profiles(id) ON DELETE RESTRICT;

CREATE INDEX IF NOT EXISTS idx_bills_tenant_profile_id
  ON public.bills (tenant_profile_id);

ALTER TABLE public.maintenance_tickets
  ADD COLUMN IF NOT EXISTS tenant_profile_id uuid REFERENCES public.tenant_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_tickets_tenant_profile_id
  ON public.maintenance_tickets (tenant_profile_id);

-- ============================================================
-- invitations_archive
-- ============================================================
CREATE TABLE public.invitations_archive (
  LIKE public.invitations INCLUDING ALL
);

ALTER TABLE public.invitations_archive ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.invitations_archive IS
  'Archive of accepted/expired invitations. Written by pg_cron; no client policies.';
