-- Activity feed views over audit_logs
-- See docs/06-implementation-roadmap.md §13

CREATE OR REPLACE VIEW public.organization_activity_feed
WITH (security_invoker = true)
AS
SELECT
  id,
  actor_id,
  organization_id,
  property_id,
  event_type,
  metadata,
  created_at
FROM public.audit_logs
WHERE organization_id IS NOT NULL;

CREATE OR REPLACE VIEW public.property_activity_feed
WITH (security_invoker = true)
AS
SELECT
  id,
  actor_id,
  organization_id,
  property_id,
  event_type,
  metadata,
  created_at
FROM public.audit_logs
WHERE property_id IS NOT NULL;

GRANT SELECT ON public.organization_activity_feed TO authenticated;
GRANT SELECT ON public.property_activity_feed TO authenticated;
