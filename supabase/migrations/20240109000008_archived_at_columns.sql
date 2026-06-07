-- REC-13: Soft-delete archived_at columns
-- See docs/06-implementation-roadmap.md §11

ALTER TABLE public.properties
  ADD COLUMN IF NOT EXISTS archived_at timestamptz;

ALTER TABLE public.buildings
  ADD COLUMN IF NOT EXISTS archived_at timestamptz;

ALTER TABLE public.bills
  ADD COLUMN IF NOT EXISTS archived_at timestamptz;

ALTER TABLE public.maintenance_tickets
  ADD COLUMN IF NOT EXISTS archived_at timestamptz;

ALTER TABLE public.housekeeping_tasks
  ADD COLUMN IF NOT EXISTS archived_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_properties_active
  ON public.properties (organization_id, name)
  WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_buildings_active
  ON public.buildings (property_id, name)
  WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_bills_active
  ON public.bills (property_id, created_at DESC)
  WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_tickets_active
  ON public.maintenance_tickets (property_id, created_at DESC)
  WHERE archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_housekeeping_tasks_active
  ON public.housekeeping_tasks (property_id, scheduled_date)
  WHERE archived_at IS NULL;
