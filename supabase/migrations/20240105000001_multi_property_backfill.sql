-- Phase 0B: Multi-property data backfill
-- See docs/09-multi-property.md §10 Phase B
-- Idempotent: safe to re-run; only fills rows that are still NULL.

-- ============================================================
-- B.1–B.3: One organization per manager, link properties
-- ============================================================
WITH managers AS (
  SELECT DISTINCT ON (p.manager_id)
    p.manager_id,
    p.name AS first_property_name,
    p.id AS first_property_id
  FROM public.properties p
  WHERE p.organization_id IS NULL
  ORDER BY p.manager_id, p.created_at ASC
),
inserted_orgs AS (
  INSERT INTO public.organizations (name, slug, owner_id)
  SELECT
    m.first_property_name || ' Organization',
    lower(regexp_replace(trim(m.first_property_name), '[^a-zA-Z0-9]+', '-', 'g'))
      || '-' || left(replace(m.first_property_id::text, '-', ''), 8),
    m.manager_id
  FROM managers m
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.organizations o
    WHERE o.owner_id = m.manager_id
  )
  RETURNING id, owner_id
),
all_orgs AS (
  SELECT id, owner_id FROM inserted_orgs
  UNION
  SELECT o.id, o.owner_id
  FROM public.organizations o
  WHERE o.owner_id IN (SELECT manager_id FROM managers)
)
INSERT INTO public.organization_members (organization_id, user_id, scope)
SELECT ao.id, ao.owner_id, 'owner'
FROM all_orgs ao
WHERE NOT EXISTS (
  SELECT 1
  FROM public.organization_members om
  WHERE om.organization_id = ao.id
    AND om.user_id = ao.owner_id
);

UPDATE public.properties p
SET organization_id = o.id
FROM public.organizations o
WHERE p.organization_id IS NULL
  AND o.owner_id = p.manager_id;

-- ============================================================
-- B.4–B.5: Default "Main Building" per property, link rooms
-- ============================================================
INSERT INTO public.buildings (property_id, name, total_floors)
SELECT p.id, 'Main Building', 1
FROM public.properties p
WHERE NOT EXISTS (
  SELECT 1 FROM public.buildings b WHERE b.property_id = p.id
);

UPDATE public.rooms r
SET building_id = b.id
FROM public.buildings b
WHERE r.building_id IS NULL
  AND b.property_id = r.property_id
  AND b.name = 'Main Building';

-- ============================================================
-- Denormalized organization_id on operational tables
-- ============================================================
UPDATE public.bills bill
SET organization_id = p.organization_id
FROM public.properties p
WHERE bill.property_id = p.id
  AND bill.organization_id IS NULL
  AND p.organization_id IS NOT NULL;

UPDATE public.maintenance_tickets t
SET organization_id = p.organization_id
FROM public.properties p
WHERE t.property_id = p.id
  AND t.organization_id IS NULL
  AND p.organization_id IS NOT NULL;
