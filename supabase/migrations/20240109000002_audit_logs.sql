-- REC-03: audit_logs table with INSERT-only grants and archival table
-- See docs/06-implementation-roadmap.md §2 (Phase 0 exit criteria)

-- ============================================================
-- audit_logs
-- ============================================================
CREATE TABLE public.audit_logs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id        uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL,
  property_id     uuid REFERENCES public.properties(id) ON DELETE SET NULL,
  event_type      text NOT NULL,
  metadata        jsonb NOT NULL DEFAULT '{}',
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_logs_org_created
  ON public.audit_logs (organization_id, created_at DESC);

CREATE INDEX idx_audit_logs_property_created
  ON public.audit_logs (property_id, created_at DESC);

CREATE INDEX idx_audit_logs_event_type
  ON public.audit_logs (event_type, created_at DESC);

CREATE INDEX idx_audit_logs_actor
  ON public.audit_logs (actor_id, created_at DESC);

-- ============================================================
-- RLS
-- ============================================================
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- No authenticated UPDATE or DELETE
REVOKE UPDATE, DELETE ON public.audit_logs FROM authenticated, anon;
GRANT INSERT ON public.audit_logs TO authenticated;

CREATE POLICY "audit_logs: owner select"
  ON public.audit_logs FOR SELECT
  TO authenticated
  USING (public.is_org_owner(organization_id));

CREATE POLICY "audit_logs: manager select"
  ON public.audit_logs FOR SELECT
  TO authenticated
  USING (public.has_property_role(property_id, 'manager'));

-- ============================================================
-- Helper function — server actions call this to record events
-- ============================================================
CREATE OR REPLACE FUNCTION public.record_audit_event(
  p_organization_id uuid,
  p_property_id     uuid,
  p_event_type      text,
  p_metadata        jsonb DEFAULT '{}'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.audit_logs (actor_id, organization_id, property_id, event_type, metadata)
  VALUES (auth.uid(), p_organization_id, p_property_id, p_event_type, COALESCE(p_metadata, '{}'));
END;
$$;

REVOKE EXECUTE ON FUNCTION public.record_audit_event(uuid, uuid, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_audit_event(uuid, uuid, text, jsonb) TO authenticated;

-- ============================================================
-- audit_logs_archive (cron target; no client policies)
-- ============================================================
CREATE TABLE public.audit_logs_archive (
  id              uuid PRIMARY KEY,
  actor_id        uuid,
  organization_id uuid,
  property_id     uuid,
  event_type      text NOT NULL,
  metadata        jsonb NOT NULL DEFAULT '{}',
  created_at      timestamptz NOT NULL,
  archived_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_logs_archive_org
  ON public.audit_logs_archive (organization_id, created_at DESC);

ALTER TABLE public.audit_logs_archive ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.audit_logs_archive IS
  'Archive of audit_logs older than 180 days. Written by pg_cron; no client policies.';
