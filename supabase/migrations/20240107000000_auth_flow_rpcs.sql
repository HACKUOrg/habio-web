-- SECURITY DEFINER RPCs for owner onboarding and invitation acceptance.
-- RLS does not allow self-service org/membership creation for these flows.

CREATE OR REPLACE FUNCTION public.slugify_org_name(p_name text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT trim(both '-' from regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '-', 'g'));
$$;

CREATE OR REPLACE FUNCTION public.create_owner_organization(
  p_org_name text,
  p_property_name text,
  p_property_address text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_org_id uuid;
  v_property_id uuid;
  v_membership_id uuid;
  v_slug text;
  v_suffix int := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_org_name IS NULL OR trim(p_org_name) = '' THEN
    RAISE EXCEPTION 'Organization name is required';
  END IF;

  IF p_property_name IS NULL OR trim(p_property_name) = '' THEN
    RAISE EXCEPTION 'Property name is required';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.memberships m
    WHERE m.user_id = v_user_id
      AND m.role = 'owner'
      AND m.property_id IS NULL
      AND m.deactivated_at IS NULL
  ) THEN
    RAISE EXCEPTION 'User already has an owner membership';
  END IF;

  v_slug := public.slugify_org_name(p_org_name);
  IF v_slug = '' THEN
    v_slug := 'organization';
  END IF;

  WHILE EXISTS (SELECT 1 FROM public.organizations o WHERE o.slug = v_slug) LOOP
    v_suffix := v_suffix + 1;
    v_slug := public.slugify_org_name(p_org_name) || '-' || v_suffix::text;
  END LOOP;

  INSERT INTO public.organizations (name, slug)
  VALUES (trim(p_org_name), v_slug)
  RETURNING id INTO v_org_id;

  INSERT INTO public.properties (organization_id, name, address)
  VALUES (v_org_id, trim(p_property_name), NULLIF(trim(p_property_address), ''))
  RETURNING id INTO v_property_id;

  INSERT INTO public.memberships (user_id, organization_id, property_id, role, created_by)
  VALUES (v_user_id, v_org_id, NULL, 'owner', v_user_id)
  RETURNING id INTO v_membership_id;

  RETURN json_build_object(
    'organization_id', v_org_id,
    'property_id', v_property_id,
    'membership_id', v_membership_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_invitation_preview(p_token text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hash text;
  v_row public.invitations%ROWTYPE;
BEGIN
  IF p_token IS NULL OR length(trim(p_token)) < 16 THEN
    RETURN NULL;
  END IF;

  v_hash := encode(digest(trim(p_token), 'sha256'), 'hex');

  SELECT *
  INTO v_row
  FROM public.invitations i
  WHERE i.token_hash = v_hash
    AND i.status = 'pending'
    AND i.expires_at > now();

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  RETURN json_build_object(
    'id', v_row.id,
    'email', v_row.email,
    'role', v_row.role,
    'organization_id', v_row.organization_id,
    'property_id', v_row.property_id,
    'expires_at', v_row.expires_at
  );
END;
$$;

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

REVOKE EXECUTE ON FUNCTION public.slugify_org_name(text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.create_owner_organization(text, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_invitation_preview(text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.accept_invitation(text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_owner_organization(text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_invitation_preview(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.accept_invitation(text) TO authenticated;
