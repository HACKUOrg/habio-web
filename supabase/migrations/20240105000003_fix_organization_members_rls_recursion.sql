-- Fix infinite recursion in organization_members RLS
-- The owner policy queried organization_members inside its own USING clause.
-- Use SECURITY DEFINER helpers so membership checks bypass RLS.

CREATE OR REPLACE FUNCTION public.is_organization_owner(p_org_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.organization_members
    WHERE organization_id = p_org_id
      AND user_id = (SELECT auth.uid())
      AND scope = 'owner'
  )
$$;

CREATE OR REPLACE FUNCTION public.is_organization_member(p_org_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.organization_members
    WHERE organization_id = p_org_id
      AND user_id = (SELECT auth.uid())
  )
$$;

REVOKE EXECUTE ON FUNCTION public.is_organization_owner(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_organization_member(uuid) FROM PUBLIC, anon;

-- organizations: member read — use helper instead of direct subquery
DROP POLICY IF EXISTS "organizations: member read" ON public.organizations;
CREATE POLICY "organizations: member read"
  ON public.organizations FOR SELECT
  TO authenticated
  USING (public.is_organization_member(id));

-- organization_members: split owner FOR ALL into per-command policies
DROP POLICY IF EXISTS "org_members: owner full access" ON public.organization_members;

CREATE POLICY "org_members: owner select"
  ON public.organization_members FOR SELECT
  TO authenticated
  USING (public.is_organization_owner(organization_id));

CREATE POLICY "org_members: owner insert"
  ON public.organization_members FOR INSERT
  TO authenticated
  WITH CHECK (public.is_organization_owner(organization_id));

CREATE POLICY "org_members: owner update"
  ON public.organization_members FOR UPDATE
  TO authenticated
  USING (public.is_organization_owner(organization_id))
  WITH CHECK (public.is_organization_owner(organization_id));

CREATE POLICY "org_members: owner delete"
  ON public.organization_members FOR DELETE
  TO authenticated
  USING (public.is_organization_owner(organization_id));
