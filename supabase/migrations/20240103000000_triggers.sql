-- Habio triggers and pg_cron jobs
-- See docs/03-database-schema.md

-- Auto-create profile on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    'tenant'
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER set_updated_at_profiles
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_properties
  BEFORE UPDATE ON public.properties
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_rooms
  BEFORE UPDATE ON public.rooms
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_tenants
  BEFORE UPDATE ON public.tenants
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_bills
  BEFORE UPDATE ON public.bills
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_maintenance_tickets
  BEFORE UPDATE ON public.maintenance_tickets
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_housekeeping_tasks
  BEFORE UPDATE ON public.housekeeping_tasks
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_line_connections
  BEFORE UPDATE ON public.line_connections
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_updated_at_property_staff
  BEFORE UPDATE ON public.property_staff
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Sync room status on lease change
CREATE OR REPLACE FUNCTION public.sync_room_status()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.lease_status = 'active' THEN
    UPDATE public.rooms SET status = 'occupied' WHERE id = NEW.room_id;
  ELSIF OLD.lease_status = 'active' AND NEW.lease_status <> 'active' THEN
    UPDATE public.rooms SET status = 'available' WHERE id = NEW.room_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER sync_room_on_lease_change
  AFTER INSERT OR UPDATE OF lease_status ON public.tenants
  FOR EACH ROW EXECUTE FUNCTION public.sync_room_status();

-- pg_cron: flip overdue bills (daily midnight UTC)
SELECT cron.schedule(
  'flip-overdue-bills',
  '0 0 * * *',
  $$
    UPDATE public.bills
    SET status = 'overdue'
    WHERE status = 'pending'
      AND due_date < CURRENT_DATE;
  $$
);

-- pg_cron: archive old read notifications (daily 02:00 UTC)
SELECT cron.schedule(
  'archive-old-notifications',
  '0 2 * * *',
  $$
    WITH moved AS (
      DELETE FROM public.notifications
      WHERE is_read = true
        AND created_at < now() - interval '90 days'
      RETURNING *
    )
    INSERT INTO public.notifications_archive
      (id, user_id, type, title, body, data, is_read, read_at, created_at)
    SELECT id, user_id, type, title, body, data, is_read, read_at, created_at
    FROM moved;
  $$
);
