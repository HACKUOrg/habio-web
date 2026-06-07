-- REC-05: pg_cron archival jobs for invitations, notifications, and audit_logs
-- See docs/06-implementation-roadmap.md §2 (Phase 0 exit criteria)
-- Note: 20240103000000 already registers 'archive-old-notifications' (daily 02:00 UTC).
-- That job is daily and archives only read notifications older than 90 days.
-- These new jobs run weekly and archive ALL notifications (read or unread) older than 90 days,
-- invitations (accepted/expired/revoked) older than 30 days, and audit_logs older than 180 days.
-- The existing daily job is complementary and can coexist.

-- ============================================================
-- Archive invitations older than 30 days (accepted/expired/revoked)
-- ============================================================
SELECT cron.schedule(
  'archive-old-invitations',
  '0 3 * * 0',  -- weekly Sunday 03:00 UTC
  $$
    WITH moved AS (
      DELETE FROM public.invitations
      WHERE status IN ('accepted', 'expired', 'revoked')
        AND created_at < now() - interval '30 days'
      RETURNING *
    )
    INSERT INTO public.invitations_archive
    SELECT * FROM moved
    ON CONFLICT (id) DO NOTHING;
  $$
);

-- ============================================================
-- Archive notifications older than 90 days
-- ============================================================
SELECT cron.schedule(
  'archive-old-notifications-weekly',
  '0 4 * * 0',  -- weekly Sunday 04:00 UTC
  $$
    WITH moved AS (
      DELETE FROM public.notifications
      WHERE created_at < now() - interval '90 days'
      RETURNING *
    )
    INSERT INTO public.notifications_archive
      (id, user_id, type, title, body, data, is_read, read_at, created_at)
    SELECT id, user_id, type, title, body, data, is_read, read_at, created_at
    FROM moved
    ON CONFLICT (id) DO NOTHING;
  $$
);

-- ============================================================
-- Archive audit_logs older than 180 days
-- ============================================================
SELECT cron.schedule(
  'archive-old-audit-logs',
  '0 5 * * 0',  -- weekly Sunday 05:00 UTC
  $$
    WITH moved AS (
      DELETE FROM public.audit_logs
      WHERE created_at < now() - interval '180 days'
      RETURNING *
    )
    INSERT INTO public.audit_logs_archive
      (id, actor_id, organization_id, property_id, event_type, metadata, created_at)
    SELECT id, actor_id, organization_id, property_id, event_type, metadata, created_at
    FROM moved
    ON CONFLICT (id) DO NOTHING;
  $$
);
