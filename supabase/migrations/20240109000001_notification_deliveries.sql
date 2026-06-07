-- REC-02: Multi-channel notification delivery tracking
-- See docs/02-system-architecture.md §3.2

CREATE TYPE public.notification_channel AS ENUM ('in_app', 'email', 'line');

CREATE TYPE public.notification_delivery_status AS ENUM (
  'pending',
  'sent',
  'failed',
  'read'
);

CREATE TABLE public.notification_deliveries (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid NOT NULL REFERENCES public.notifications(id) ON DELETE CASCADE,
  channel         public.notification_channel NOT NULL,
  status          public.notification_delivery_status NOT NULL DEFAULT 'pending',
  sent_at         timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (notification_id, channel)
);

CREATE INDEX idx_notification_deliveries_notification_id
  ON public.notification_deliveries (notification_id);

ALTER TABLE public.notification_deliveries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notification_deliveries: own select via notification"
  ON public.notification_deliveries FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.notifications n
      WHERE n.id = notification_deliveries.notification_id
        AND n.user_id = (SELECT auth.uid())
    )
  );

REVOKE INSERT, UPDATE, DELETE ON public.notification_deliveries FROM authenticated;

-- Tighten notifications INSERT (system/service role only)
REVOKE INSERT ON public.notifications FROM authenticated;
