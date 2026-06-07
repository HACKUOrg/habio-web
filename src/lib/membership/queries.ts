import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '@/types/database'
import type { ActiveMembership, MembershipWithContext } from '@/lib/membership/types'

type Client = SupabaseClient<Database>

export async function validateMembershipById(
  supabase: Client,
  membershipId: string,
  userId: string
): Promise<ActiveMembership | null> {
  const { data } = await supabase
    .from('memberships')
    .select('id, user_id, organization_id, property_id, role')
    .eq('id', membershipId)
    .eq('user_id', userId)
    .is('deactivated_at', null)
    .maybeSingle()

  if (!data) return null

  return {
    membershipId: data.id,
    userId: data.user_id,
    role: data.role,
    organizationId: data.organization_id,
    propertyId: data.property_id,
  }
}

export async function loadActiveMemberships(
  supabase: Client,
  userId: string
): Promise<MembershipWithContext[]> {
  const { data: memberships, error } = await supabase
    .from('memberships')
    .select(
      `
      id,
      user_id,
      organization_id,
      property_id,
      role,
      organizations ( name ),
      properties ( name )
    `
    )
    .eq('user_id', userId)
    .is('deactivated_at', null)
    .order('created_at', { ascending: true })

  if (error || !memberships) return []

  return memberships.map((row) => ({
    membershipId: row.id,
    userId: row.user_id,
    role: row.role,
    organizationId: row.organization_id,
    propertyId: row.property_id,
    organizationName: row.organizations?.name ?? 'Organization',
    propertyName: row.properties?.name ?? null,
  }))
}

export function toActiveMembership(row: MembershipWithContext): ActiveMembership {
  return {
    membershipId: row.membershipId,
    userId: row.userId,
    role: row.role,
    organizationId: row.organizationId,
    propertyId: row.propertyId,
  }
}
