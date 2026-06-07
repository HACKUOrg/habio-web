-- REC-09: Org-level owner invitations
-- See docs/08-auth-and-invitation-flow.md

ALTER TABLE public.invitations
  DROP CONSTRAINT IF EXISTS invitations_property_scope_check;

ALTER TABLE public.invitations
  ALTER COLUMN property_id DROP NOT NULL;

ALTER TABLE public.invitations
  DROP CONSTRAINT IF EXISTS invitations_role_check;

ALTER TABLE public.invitations
  ADD CONSTRAINT invitations_role_check CHECK (
    role IN ('owner', 'manager', 'technician', 'housekeeper', 'tenant')
  );

ALTER TABLE public.invitations
  ADD CONSTRAINT invitations_property_scope_check CHECK (
    (role = 'owner' AND property_id IS NULL)
    OR (role <> 'owner' AND property_id IS NOT NULL)
  );

-- ============================================================
-- create_owner_invitation
-- ============================================================
CREATE OR REPLACE FUNCTION public.create_owner_invitation(p_email text)
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

  SELECT m.organization_id
  INTO v_org_id
  FROM public.memberships m
  WHERE m.user_id = v_user_id
    AND m.role = 'owner'
    AND m.property_id IS NULL
    AND m.deactivated_at IS NULL
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Only active owners can invite co-owners';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.invitations i
    WHERE i.email = lower(trim(p_email))
      AND i.organization_id = v_org_id
      AND i.role = 'owner'
      AND i.status = 'pending'
      AND i.expires_at > now()
  ) THEN
    RAISE EXCEPTION 'A pending owner invitation already exists for this email';
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
    NULL,
    lower(trim(p_email)),
    'owner',
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

-- ============================================================
-- accept_invitation — support owner role (property_id NULL)
-- ============================================================
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

REVOKE EXECUTE ON FUNCTION public.create_owner_invitation(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_owner_invitation(text) TO authenticated;
