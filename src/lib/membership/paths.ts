import type { MembershipRole } from '@/types'

export const MEMBERSHIP_ROLE_ROUTES: MembershipRole[] = [
  'owner',
  'manager',
  'technician',
  'housekeeper',
  'tenant',
]

export function membershipDashboardPath(role: MembershipRole): string {
  return `/${role}/dashboard`
}

export function roleFromPath(pathname: string): MembershipRole | null {
  const segment = pathname.split('/').filter(Boolean)[0]
  if (!segment) return null
  return MEMBERSHIP_ROLE_ROUTES.includes(segment as MembershipRole)
    ? (segment as MembershipRole)
    : null
}
