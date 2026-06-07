import type { MembershipRole } from '@/types'

export type InvitableRole = 'manager' | 'technician' | 'housekeeper'

export function invitableRolesForMembership(role: MembershipRole): InvitableRole[] {
  if (role === 'owner') return ['manager', 'technician', 'housekeeper']
  if (role === 'manager') return ['technician', 'housekeeper']
  return []
}
