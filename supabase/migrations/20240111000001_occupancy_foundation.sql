-- Phase 0: Occupancy transaction foundation (schema + RLS only; no completion RPCs)
-- See docs/03-database-schema.md §4.9 and docs/04-rbac.md §3.1, §6.2

-- ============================================================
-- Enums
-- ============================================================
DO $$ BEGIN
  CREATE TYPE public.move_in_transaction_status AS ENUM ('draft', 'completed', 'voided');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.move_out_transaction_status AS ENUM ('draft', 'settled', 'disputed', 'voided');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.inspection_item_status AS ENUM ('good', 'damaged', 'missing', 'needs_repair');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE public.meter_snapshot_type AS ENUM ('move_in', 'move_out');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================
-- move_in_transactions
-- ============================================================
CREATE TABLE IF NOT EXISTS public.move_in_transactions (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id      uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  property_id          uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
  room_id              uuid NOT NULL REFERENCES public.rooms(id) ON DELETE RESTRICT,
  tenant_profile_id    uuid NOT NULL REFERENCES public.tenant_profiles(id) ON DELETE RESTRICT,
  move_in_date         date NOT NULL,
  status               public.move_in_transaction_status NOT NULL DEFAULT 'draft',
  security_deposit     numeric(12, 2) NOT NULL DEFAULT 0 CHECK (security_deposit >= 0),
  advance_rent         numeric(12, 2) NOT NULL DEFAULT 0 CHECK (advance_rent >= 0),
  electric_meter_start numeric(12, 4) CHECK (electric_meter_start IS NULL OR electric_meter_start >= 0),
  water_meter_start    numeric(12, 4) CHECK (water_meter_start IS NULL OR water_meter_start >= 0),
  notes                text,
  created_by           uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (room_id, tenant_profile_id)
);

CREATE INDEX IF NOT EXISTS idx_move_in_transactions_org_created
  ON public.move_in_transactions (organization_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_move_in_transactions_property_created
  ON public.move_in_transactions (property_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_move_in_transactions_tenant_profile
  ON public.move_in_transactions (tenant_profile_id);

CREATE INDEX IF NOT EXISTS idx_move_in_transactions_room
  ON public.move_in_transactions (room_id);

CREATE INDEX IF NOT EXISTS idx_move_in_transactions_status
  ON public.move_in_transactions (property_id, status)
  WHERE status = 'draft';

-- ============================================================
-- move_out_transactions
-- ============================================================
CREATE TABLE IF NOT EXISTS public.move_out_transactions (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id        uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  property_id            uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
  room_id                uuid NOT NULL REFERENCES public.rooms(id) ON DELETE RESTRICT,
  tenant_profile_id      uuid NOT NULL REFERENCES public.tenant_profiles(id) ON DELETE RESTRICT,
  move_in_transaction_id uuid REFERENCES public.move_in_transactions(id) ON DELETE RESTRICT,
  move_out_date          date NOT NULL,
  status                 public.move_out_transaction_status NOT NULL DEFAULT 'draft',
  electric_meter_end     numeric(12, 4) CHECK (electric_meter_end IS NULL OR electric_meter_end >= 0),
  water_meter_end        numeric(12, 4) CHECK (water_meter_end IS NULL OR water_meter_end >= 0),
  damage_charge          numeric(12, 2) NOT NULL DEFAULT 0 CHECK (damage_charge >= 0),
  cleaning_fee           numeric(12, 2) NOT NULL DEFAULT 0 CHECK (cleaning_fee >= 0),
  other_deductions       numeric(12, 2) NOT NULL DEFAULT 0 CHECK (other_deductions >= 0),
  deposit_refund         numeric(12, 2) NOT NULL DEFAULT 0 CHECK (deposit_refund >= 0),
  notes                  text,
  settlement_notes       text,
  created_by             uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  settled_by             uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  settled_at             timestamptz,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_profile_id)
);

CREATE INDEX IF NOT EXISTS idx_move_out_transactions_org_created
  ON public.move_out_transactions (organization_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_move_out_transactions_property_created
  ON public.move_out_transactions (property_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_move_out_transactions_tenant_profile
  ON public.move_out_transactions (tenant_profile_id);

CREATE INDEX IF NOT EXISTS idx_move_out_transactions_room
  ON public.move_out_transactions (room_id);

CREATE INDEX IF NOT EXISTS idx_move_out_transactions_move_in
  ON public.move_out_transactions (move_in_transaction_id)
  WHERE move_in_transaction_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_move_out_transactions_status
  ON public.move_out_transactions (property_id, status)
  WHERE status IN ('draft', 'disputed');

-- ============================================================
-- meter_snapshots (immutable)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.meter_snapshots (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id         uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  property_id             uuid NOT NULL REFERENCES public.properties(id) ON DELETE RESTRICT,
  room_id                 uuid NOT NULL REFERENCES public.rooms(id) ON DELETE RESTRICT,
  snapshot_type           public.meter_snapshot_type NOT NULL,
  move_in_transaction_id  uuid REFERENCES public.move_in_transactions(id) ON DELETE RESTRICT,
  move_out_transaction_id uuid REFERENCES public.move_out_transactions(id) ON DELETE RESTRICT,
  electric_reading        numeric(12, 4) NOT NULL CHECK (electric_reading >= 0),
  water_reading           numeric(12, 4) NOT NULL CHECK (water_reading >= 0),
  reading_date            date NOT NULL,
  photo_url               text,
  submitted_by            uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at              timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT meter_snapshots_parent_xor CHECK (
    (move_in_transaction_id IS NOT NULL)::int
    + (move_out_transaction_id IS NOT NULL)::int = 1
  ),
  CONSTRAINT meter_snapshots_type_parent_match CHECK (
    (snapshot_type = 'move_in' AND move_in_transaction_id IS NOT NULL)
    OR (snapshot_type = 'move_out' AND move_out_transaction_id IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS meter_snapshots_one_per_move_in
  ON public.meter_snapshots (move_in_transaction_id)
  WHERE move_in_transaction_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS meter_snapshots_one_per_move_out
  ON public.meter_snapshots (move_out_transaction_id)
  WHERE move_out_transaction_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_meter_snapshots_property_created
  ON public.meter_snapshots (property_id, created_at DESC);

REVOKE UPDATE, DELETE ON public.meter_snapshots FROM authenticated;

-- ============================================================
-- inspection_items
-- ============================================================
CREATE TABLE IF NOT EXISTS public.inspection_items (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id         uuid NOT NULL REFERENCES public.organizations(id) ON DELETE RESTRICT,
  move_in_transaction_id  uuid REFERENCES public.move_in_transactions(id) ON DELETE CASCADE,
  move_out_transaction_id uuid REFERENCES public.move_out_transactions(id) ON DELETE CASCADE,
  item_name               text NOT NULL,
  status                  public.inspection_item_status NOT NULL DEFAULT 'good',
  notes                   text,
  photo_url               text,
  sort_order              integer NOT NULL DEFAULT 0,
  created_by              uuid NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT inspection_items_parent_xor CHECK (
    (move_in_transaction_id IS NOT NULL)::int
    + (move_out_transaction_id IS NOT NULL)::int = 1
  )
);

CREATE INDEX IF NOT EXISTS idx_inspection_items_move_in
  ON public.inspection_items (move_in_transaction_id)
  WHERE move_in_transaction_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_inspection_items_move_out
  ON public.inspection_items (move_out_transaction_id)
  WHERE move_out_transaction_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_inspection_items_organization
  ON public.inspection_items (organization_id);

-- ============================================================
-- updated_at triggers
-- ============================================================
DROP TRIGGER IF EXISTS set_updated_at_move_in_transactions ON public.move_in_transactions;
CREATE TRIGGER set_updated_at_move_in_transactions
  BEFORE UPDATE ON public.move_in_transactions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_move_out_transactions ON public.move_out_transactions;
CREATE TRIGGER set_updated_at_move_out_transactions
  BEFORE UPDATE ON public.move_out_transactions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_inspection_items ON public.inspection_items;
CREATE TRIGGER set_updated_at_inspection_items
  BEFORE UPDATE ON public.inspection_items
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================
-- Org/property/room consistency triggers
-- ============================================================
CREATE OR REPLACE FUNCTION public.validate_move_in_transaction_scope()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_org uuid;
  v_property uuid;
  v_room uuid;
BEGIN
  SELECT tp.organization_id, tp.property_id, tp.room_id
  INTO v_org, v_property, v_room
  FROM public.tenant_profiles tp
  WHERE tp.id = NEW.tenant_profile_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'tenant_profile_id % does not exist', NEW.tenant_profile_id;
  END IF;

  IF NEW.organization_id IS DISTINCT FROM v_org
     OR NEW.property_id IS DISTINCT FROM v_property
     OR NEW.room_id IS DISTINCT FROM v_room THEN
    RAISE EXCEPTION 'move_in_transactions scope does not match tenant_profile';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_move_out_transaction_scope()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_org uuid;
  v_property uuid;
  v_room uuid;
BEGIN
  SELECT tp.organization_id, tp.property_id, tp.room_id
  INTO v_org, v_property, v_room
  FROM public.tenant_profiles tp
  WHERE tp.id = NEW.tenant_profile_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'tenant_profile_id % does not exist', NEW.tenant_profile_id;
  END IF;

  IF NEW.organization_id IS DISTINCT FROM v_org
     OR NEW.property_id IS DISTINCT FROM v_property
     OR NEW.room_id IS DISTINCT FROM v_room THEN
    RAISE EXCEPTION 'move_out_transactions scope does not match tenant_profile';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_meter_snapshot_scope()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_org uuid;
  v_property uuid;
  v_room uuid;
BEGIN
  IF NEW.move_in_transaction_id IS NOT NULL THEN
    SELECT mit.organization_id, mit.property_id, mit.room_id
    INTO v_org, v_property, v_room
    FROM public.move_in_transactions mit
    WHERE mit.id = NEW.move_in_transaction_id;
  ELSE
    SELECT mot.organization_id, mot.property_id, mot.room_id
    INTO v_org, v_property, v_room
    FROM public.move_out_transactions mot
    WHERE mot.id = NEW.move_out_transaction_id;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'parent transaction does not exist';
  END IF;

  IF NEW.organization_id IS DISTINCT FROM v_org
     OR NEW.property_id IS DISTINCT FROM v_property
     OR NEW.room_id IS DISTINCT FROM v_room THEN
    RAISE EXCEPTION 'meter_snapshots scope does not match parent transaction';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.validate_inspection_item_scope()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_org uuid;
BEGIN
  IF NEW.move_in_transaction_id IS NOT NULL THEN
    SELECT mit.organization_id INTO v_org
    FROM public.move_in_transactions mit
    WHERE mit.id = NEW.move_in_transaction_id;
  ELSE
    SELECT mot.organization_id INTO v_org
    FROM public.move_out_transactions mot
    WHERE mot.id = NEW.move_out_transaction_id;
  END IF;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'parent transaction does not exist';
  END IF;

  IF NEW.organization_id IS DISTINCT FROM v_org THEN
    RAISE EXCEPTION 'inspection_items.organization_id does not match parent transaction';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS move_in_transactions_scope_check ON public.move_in_transactions;
CREATE TRIGGER move_in_transactions_scope_check
  BEFORE INSERT OR UPDATE ON public.move_in_transactions
  FOR EACH ROW EXECUTE FUNCTION public.validate_move_in_transaction_scope();

DROP TRIGGER IF EXISTS move_out_transactions_scope_check ON public.move_out_transactions;
CREATE TRIGGER move_out_transactions_scope_check
  BEFORE INSERT OR UPDATE ON public.move_out_transactions
  FOR EACH ROW EXECUTE FUNCTION public.validate_move_out_transaction_scope();

DROP TRIGGER IF EXISTS meter_snapshots_scope_check ON public.meter_snapshots;
CREATE TRIGGER meter_snapshots_scope_check
  BEFORE INSERT OR UPDATE ON public.meter_snapshots
  FOR EACH ROW EXECUTE FUNCTION public.validate_meter_snapshot_scope();

DROP TRIGGER IF EXISTS inspection_items_scope_check ON public.inspection_items;
CREATE TRIGGER inspection_items_scope_check
  BEFORE INSERT OR UPDATE ON public.inspection_items
  FOR EACH ROW EXECUTE FUNCTION public.validate_inspection_item_scope();

REVOKE EXECUTE ON FUNCTION public.validate_move_in_transaction_scope() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.validate_move_out_transaction_scope() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.validate_meter_snapshot_scope() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.validate_inspection_item_scope() FROM PUBLIC, anon, authenticated;

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.move_in_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.move_out_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meter_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inspection_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "move_in_transactions: scoped read"
  ON public.move_in_transactions FOR SELECT
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
    OR EXISTS (
      SELECT 1
      FROM public.tenant_profiles tp
      WHERE tp.id = move_in_transactions.tenant_profile_id
        AND tp.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "move_in_transactions: owners and managers manage"
  ON public.move_in_transactions FOR ALL
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  )
  WITH CHECK (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  );

CREATE POLICY "move_out_transactions: scoped read"
  ON public.move_out_transactions FOR SELECT
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
    OR EXISTS (
      SELECT 1
      FROM public.tenant_profiles tp
      WHERE tp.id = move_out_transactions.tenant_profile_id
        AND tp.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "move_out_transactions: owners and managers manage"
  ON public.move_out_transactions FOR ALL
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  )
  WITH CHECK (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  );

CREATE POLICY "meter_snapshots: scoped read"
  ON public.meter_snapshots FOR SELECT
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
    OR EXISTS (
      SELECT 1
      FROM public.move_in_transactions mit
      JOIN public.tenant_profiles tp ON tp.id = mit.tenant_profile_id
      WHERE mit.id = meter_snapshots.move_in_transaction_id
        AND tp.user_id = (SELECT auth.uid())
    )
    OR EXISTS (
      SELECT 1
      FROM public.move_out_transactions mot
      JOIN public.tenant_profiles tp ON tp.id = mot.tenant_profile_id
      WHERE mot.id = meter_snapshots.move_out_transaction_id
        AND tp.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "meter_snapshots: owners and managers insert"
  ON public.meter_snapshots FOR INSERT
  TO authenticated
  WITH CHECK (
    public.is_org_owner(organization_id)
    OR public.has_property_role(property_id, 'manager')
  );

CREATE POLICY "inspection_items: scoped read"
  ON public.inspection_items FOR SELECT
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR EXISTS (
      SELECT 1
      FROM public.move_in_transactions mit
      WHERE mit.id = inspection_items.move_in_transaction_id
        AND public.has_property_role(mit.property_id, 'manager')
    )
    OR EXISTS (
      SELECT 1
      FROM public.move_out_transactions mot
      WHERE mot.id = inspection_items.move_out_transaction_id
        AND public.has_property_role(mot.property_id, 'manager')
    )
    OR EXISTS (
      SELECT 1
      FROM public.move_in_transactions mit
      JOIN public.tenant_profiles tp ON tp.id = mit.tenant_profile_id
      WHERE mit.id = inspection_items.move_in_transaction_id
        AND tp.user_id = (SELECT auth.uid())
    )
    OR EXISTS (
      SELECT 1
      FROM public.move_out_transactions mot
      JOIN public.tenant_profiles tp ON tp.id = mot.tenant_profile_id
      WHERE mot.id = inspection_items.move_out_transaction_id
        AND tp.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "inspection_items: owners and managers manage"
  ON public.inspection_items FOR ALL
  TO authenticated
  USING (
    public.is_org_owner(organization_id)
    OR EXISTS (
      SELECT 1
      FROM public.move_in_transactions mit
      WHERE mit.id = inspection_items.move_in_transaction_id
        AND public.has_property_role(mit.property_id, 'manager')
    )
    OR EXISTS (
      SELECT 1
      FROM public.move_out_transactions mot
      WHERE mot.id = inspection_items.move_out_transaction_id
        AND public.has_property_role(mot.property_id, 'manager')
    )
  )
  WITH CHECK (
    public.is_org_owner(organization_id)
    OR EXISTS (
      SELECT 1
      FROM public.move_in_transactions mit
      WHERE mit.id = inspection_items.move_in_transaction_id
        AND public.has_property_role(mit.property_id, 'manager')
    )
    OR EXISTS (
      SELECT 1
      FROM public.move_out_transactions mot
      WHERE mot.id = inspection_items.move_out_transaction_id
        AND public.has_property_role(mot.property_id, 'manager')
    )
  );
