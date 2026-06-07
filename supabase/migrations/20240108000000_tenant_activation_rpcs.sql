-- Tenant activation metadata on invitations + SECURITY DEFINER RPCs
-- See docs/08-auth-and-invitation-flow.md §4

ALTER TABLE public.invitations
  ADD COLUMN IF NOT EXISTS room_id uuid REFERENCES public.rooms(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS lease_start date,
  ADD COLUMN IF NOT EXISTS lease_end date;

ALTER TABLE public.invitations
  ADD CONSTRAINT invitations_tenant_scope_check CHECK (
    role <> 'tenant'
    OR (
      room_id IS NOT NULL
      AND lease_start IS NOT NULL
    )
  );

CREATE INDEX IF NOT EXISTS idx_invitations_room_id
  ON public.invitations (room_id)
  WHERE room_id IS NOT NULL;

-- Reject tenant invitations in generic staff accept flow
CREATE OR REPLACE FUNCTION public.accept_invitation(p_token text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_email text;
  v_hash text;
  v_row public.invitations%ROWTYPE;
  v_membership_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_token IS NULL OR length(trim(p_token)) < 16 THEN
    RAISE EXCEPTION 'Invalid invitation token';
  END IF;

  SELECT lower(u.email)
  INTO v_user_email
  FROM auth.users u
  WHERE u.id = v_user_id;

  v_hash := encode(digest(trim(p_token), 'sha256'), 'hex');

  SELECT *
  INTO v_row
  FROM public.invitations i
  WHERE i.token_hash = v_hash
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invitation not found';
  END IF;

  IF v_row.role = 'tenant' THEN
    RAISE EXCEPTION 'Use tenant activation flow for tenant invitations';
  END IF;

  IF v_row.status <> 'pending' THEN
    RAISE EXCEPTION 'Invitation is no longer valid';
  END IF;

  IF v_row.expires_at <= now() THEN
    UPDATE public.invitations
    SET status = 'expired'
    WHERE id = v_row.id;
    RAISE EXCEPTION 'Invitation has expired';
  END IF;

  IF lower(v_row.email::text) <> v_user_email THEN
    RAISE EXCEPTION 'Signed-in email does not match the invitation';
  END IF;

  SELECT m.id
  INTO v_membership_id
  FROM public.memberships m
  WHERE m.user_id = v_user_id
    AND m.organization_id = v_row.organization_id
    AND m.property_id IS NOT DISTINCT FROM v_row.property_id
    AND m.role = v_row.role
    AND m.deactivated_at IS NULL
  LIMIT 1;

  IF v_membership_id IS NULL THEN
    INSERT INTO public.memberships (
      user_id,
      organization_id,
      property_id,
      role,
      created_by
    )
    VALUES (
      v_user_id,
      v_row.organization_id,
      v_row.property_id,
      v_row.role,
      v_row.invited_by
    )
    RETURNING id INTO v_membership_id;
  END IF;

  UPDATE public.invitations
  SET
    status = 'accepted',
    accepted_at = now()
  WHERE id = v_row.id;

  RETURN json_build_object(
    'membership_id', v_membership_id,
    'organization_id', v_row.organization_id,
    'property_id', v_row.property_id,
    'role', v_row.role
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_tenant_activation_preview(p_token text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hash text;
  v_row public.invitations%ROWTYPE;
  v_property_name text;
  v_room_number text;
BEGIN
  IF p_token IS NULL OR length(trim(p_token)) < 16 THEN
    RETURN NULL;
  END IF;

  v_hash := encode(digest(trim(p_token), 'sha256'), 'hex');

  SELECT *
  INTO v_row
  FROM public.invitations i
  WHERE i.token_hash = v_hash
    AND i.role = 'tenant'
    AND i.status = 'pending'
    AND i.expires_at > now();

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT p.name
  INTO v_property_name
  FROM public.properties p
  WHERE p.id = v_row.property_id;

  SELECT r.room_number
  INTO v_room_number
  FROM public.rooms r
  WHERE r.id = v_row.room_id;

  RETURN json_build_object(
    'id', v_row.id,
    'email', v_row.email,
    'organization_id', v_row.organization_id,
    'property_id', v_row.property_id,
    'property_name', v_property_name,
    'room_id', v_row.room_id,
    'room_number', v_room_number,
    'lease_start', v_row.lease_start,
    'lease_end', v_row.lease_end,
    'expires_at', v_row.expires_at
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_tenant_activation(p_token text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_email text;
  v_hash text;
  v_row public.invitations%ROWTYPE;
  v_membership_id uuid;
  v_tenant_profile_id uuid;
  v_room_status public.room_status;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_token IS NULL OR length(trim(p_token)) < 16 THEN
    RAISE EXCEPTION 'Invalid activation token';
  END IF;

  SELECT lower(u.email)
  INTO v_user_email
  FROM auth.users u
  WHERE u.id = v_user_id;

  v_hash := encode(digest(trim(p_token), 'sha256'), 'hex');

  SELECT *
  INTO v_row
  FROM public.invitations i
  WHERE i.token_hash = v_hash
    AND i.role = 'tenant'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Activation link not found';
  END IF;

  IF v_row.status <> 'pending' THEN
    RAISE EXCEPTION 'Activation link is no longer valid';
  END IF;

  IF v_row.expires_at <= now() THEN
    UPDATE public.invitations
    SET status = 'expired'
    WHERE id = v_row.id;
    RAISE EXCEPTION 'Activation link has expired';
  END IF;

  IF lower(v_row.email::text) <> v_user_email THEN
    RAISE EXCEPTION 'Signed-in email does not match the activation link';
  END IF;

  SELECT r.status
  INTO v_room_status
  FROM public.rooms r
  WHERE r.id = v_row.room_id
    AND r.property_id = v_row.property_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Assigned room not found';
  END IF;

  IF v_room_status <> 'available' THEN
    RAISE EXCEPTION 'Room is no longer available';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.tenant_profiles tp
    WHERE tp.room_id = v_row.room_id
      AND tp.lease_status = 'active'
      AND tp.archived_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Room already has an active tenant';
  END IF;

  SELECT m.id
  INTO v_membership_id
  FROM public.memberships m
  WHERE m.user_id = v_user_id
    AND m.organization_id = v_row.organization_id
    AND m.property_id = v_row.property_id
    AND m.role = 'tenant'
    AND m.deactivated_at IS NULL
  LIMIT 1;

  IF v_membership_id IS NULL THEN
    INSERT INTO public.memberships (
      user_id,
      organization_id,
      property_id,
      role,
      created_by
    )
    VALUES (
      v_user_id,
      v_row.organization_id,
      v_row.property_id,
      'tenant',
      v_row.invited_by
    )
    RETURNING id INTO v_membership_id;
  END IF;

  SELECT tp.id
  INTO v_tenant_profile_id
  FROM public.tenant_profiles tp
  WHERE tp.membership_id = v_membership_id
  LIMIT 1;

  IF v_tenant_profile_id IS NULL THEN
    INSERT INTO public.tenant_profiles (
      user_id,
      membership_id,
      organization_id,
      property_id,
      room_id,
      lease_start,
      lease_end,
      lease_status
    )
    VALUES (
      v_user_id,
      v_membership_id,
      v_row.organization_id,
      v_row.property_id,
      v_row.room_id,
      v_row.lease_start,
      v_row.lease_end,
      'active'
    )
    RETURNING id INTO v_tenant_profile_id;
  END IF;

  UPDATE public.invitations
  SET
    status = 'accepted',
    accepted_at = now()
  WHERE id = v_row.id;

  RETURN json_build_object(
    'membership_id', v_membership_id,
    'tenant_profile_id', v_tenant_profile_id,
    'organization_id', v_row.organization_id,
    'property_id', v_row.property_id,
    'role', 'tenant'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_tenant_activation(
  p_email text,
  p_property_id uuid,
  p_room_id uuid,
  p_lease_start date,
  p_lease_end date DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_org_id uuid;
  v_room_status public.room_status;
  v_token text;
  v_token_hash text;
  v_invitation_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_email IS NULL OR trim(p_email) = '' THEN
    RAISE EXCEPTION 'Email is required';
  END IF;

  IF p_property_id IS NULL OR p_room_id IS NULL OR p_lease_start IS NULL THEN
    RAISE EXCEPTION 'Property, room, and lease start are required';
  END IF;

  SELECT p.organization_id
  INTO v_org_id
  FROM public.properties p
  WHERE p.id = p_property_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Property not found';
  END IF;

  IF NOT (
    public.is_org_owner(v_org_id)
    OR public.has_property_role(p_property_id, 'manager')
  ) THEN
    RAISE EXCEPTION 'Not authorized to create tenant activations for this property';
  END IF;

  SELECT r.status
  INTO v_room_status
  FROM public.rooms r
  WHERE r.id = p_room_id
    AND r.property_id = p_property_id
    AND r.archived_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Room not found in this property';
  END IF;

  IF v_room_status <> 'available' THEN
    RAISE EXCEPTION 'Room is not available';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.tenant_profiles tp
    WHERE tp.room_id = p_room_id
      AND tp.lease_status = 'active'
      AND tp.archived_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Room already has an active tenant';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.invitations i
    WHERE i.email = lower(trim(p_email))
      AND i.property_id = p_property_id
      AND i.role = 'tenant'
      AND i.status = 'pending'
      AND i.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'A pending tenant activation already exists for this email';
  END IF;

  v_token := encode(gen_random_bytes(32), 'hex');
  v_token_hash := encode(digest(v_token, 'sha256'), 'hex');

  INSERT INTO public.invitations (
    organization_id,
    property_id,
    email,
    role,
    token_hash,
    expires_at,
    invited_by,
    room_id,
    lease_start,
    lease_end
  )
  VALUES (
    v_org_id,
    p_property_id,
    lower(trim(p_email)),
    'tenant',
    v_token_hash,
    now() + interval '7 days',
    v_user_id,
    p_room_id,
    p_lease_start,
    p_lease_end
  )
  RETURNING id INTO v_invitation_id;

  RETURN json_build_object(
    'invitation_id', v_invitation_id,
    'token', v_token
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_staff_invitation(
  p_email text,
  p_role public.membership_role,
  p_property_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_org_id uuid;
  v_token text;
  v_token_hash text;
  v_invitation_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_email IS NULL OR trim(p_email) = '' THEN
    RAISE EXCEPTION 'Email is required';
  END IF;

  IF p_property_id IS NULL THEN
    RAISE EXCEPTION 'Property is required';
  END IF;

  IF p_role NOT IN ('manager', 'technician', 'housekeeper') THEN
    RAISE EXCEPTION 'Invalid staff role for invitation';
  END IF;

  SELECT p.organization_id
  INTO v_org_id
  FROM public.properties p
  WHERE p.id = p_property_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Property not found';
  END IF;

  IF p_role = 'manager' THEN
    IF NOT public.is_org_owner(v_org_id) THEN
      RAISE EXCEPTION 'Only owners can invite managers';
    END IF;
  ELSIF p_role IN ('technician', 'housekeeper') THEN
    IF NOT (
      public.is_org_owner(v_org_id)
      OR public.has_property_role(p_property_id, 'manager')
    ) THEN
      RAISE EXCEPTION 'Not authorized to invite staff for this property';
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.invitations i
    WHERE i.email = lower(trim(p_email))
      AND i.organization_id = v_org_id
      AND i.property_id = p_property_id
      AND i.role = p_role
      AND i.status = 'pending'
      AND i.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'A pending invitation already exists for this email and role';
  END IF;

  v_token := encode(gen_random_bytes(32), 'hex');
  v_token_hash := encode(digest(v_token, 'sha256'), 'hex');

  INSERT INTO public.invitations (
    organization_id,
    property_id,
    email,
    role,
    token_hash,
    expires_at,
    invited_by
  )
  VALUES (
    v_org_id,
    p_property_id,
    lower(trim(p_email)),
    p_role,
    v_token_hash,
    now() + interval '7 days',
    v_user_id
  )
  RETURNING id INTO v_invitation_id;

  RETURN json_build_object(
    'invitation_id', v_invitation_id,
    'token', v_token
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_tenant_activation_preview(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.accept_tenant_activation(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.create_tenant_activation(text, uuid, uuid, date, date) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.create_staff_invitation(text, public.membership_role, uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_tenant_activation_preview(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accept_tenant_activation(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_tenant_activation(text, uuid, uuid, date, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_staff_invitation(text, public.membership_role, uuid) TO authenticated;
