import type { MembershipRole } from '@/types'

export interface ActiveMembership {
  membershipId: string
  userId: string
  role: MembershipRole
  organizationId: string
  propertyId: string | null
}

export interface ActiveMembershipCookiePayload extends ActiveMembership {
  exp: number
}

export interface MembershipWithContext extends ActiveMembership {
  organizationName: string
  propertyName: string | null
}
