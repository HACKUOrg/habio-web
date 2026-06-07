import type { Database } from './database'

export type { Database } from './database'

export type PublicTables = Database['public']['Tables']
export type PublicEnums = Database['public']['Enums']

export type MembershipRole =
  | 'owner'
  | 'manager'
  | 'technician'
  | 'housekeeper'
  | 'tenant'

export type InvitationStatus = 'pending' | 'accepted' | 'expired' | 'revoked'

export type RoomType = PublicEnums['room_type']
export type RoomStatus = PublicEnums['room_status']
export type LeaseStatus = PublicEnums['lease_status']
export type BillStatus = PublicEnums['bill_status']
export type TicketPriority = PublicEnums['ticket_priority']
export type TicketStatus = PublicEnums['ticket_status']
export type TaskStatus = PublicEnums['task_status']
export type NotificationType = PublicEnums['notification_type']
export type PropertyStatus = PublicEnums['property_status']
export type BillingPeriodStatus = PublicEnums['billing_period_status']
export type MeterReadingStatus = PublicEnums['meter_reading_status']

export type ProfileRow = PublicTables['profiles']['Row']
export type OrganizationRow = PublicTables['organizations']['Row']
export type PropertyRow = PublicTables['properties']['Row']
export type BuildingRow = PublicTables['buildings']['Row']
export type RoomRow = PublicTables['rooms']['Row']
export type BillingPeriodRow = PublicTables['billing_periods']['Row']
export type MeterReadingRow = PublicTables['meter_readings']['Row']
export type BillRow = PublicTables['bills']['Row']

type MembershipFallbackRow = {
  id: string
  user_id: string
  organization_id: string
  property_id: string | null
  role: MembershipRole
  created_by: string | null
  deactivated_at: string | null
  created_at: string
}

type InvitationFallbackRow = {
  id: string
  organization_id: string
  property_id: string | null
  email: string
  role: Exclude<MembershipRole, 'owner'>
  token_hash: string
  status: InvitationStatus
  expires_at: string
  invited_by: string
  accepted_at: string | null
  created_at: string
}

type TenantProfileFallbackRow = {
  id: string
  user_id: string
  membership_id: string
  organization_id: string
  property_id: string
  room_id: string
  lease_start: string
  lease_end: string | null
  lease_status: LeaseStatus
  emergency_contact_name: string | null
  emergency_contact_phone: string | null
  notes: string | null
  archived_at: string | null
  created_at: string
  updated_at: string
}

export type MembershipRow = PublicTables extends {
  memberships: { Row: infer Row }
}
  ? Row
  : MembershipFallbackRow

export type InvitationRow = PublicTables extends {
  invitations: { Row: infer Row }
}
  ? Row
  : InvitationFallbackRow

export type TenantProfileRow = PublicTables extends {
  tenant_profiles: { Row: infer Row }
}
  ? Row
  : TenantProfileFallbackRow

export type { ActiveMembership, MembershipWithContext } from '@/lib/membership/types'
export {
  MEMBERSHIP_ROLE_ROUTES,
  membershipDashboardPath,
  roleFromPath,
} from '@/lib/membership/paths'

export const MEMBERSHIP_ROLE_LABELS: Record<MembershipRole, string> = {
  owner: 'Owner',
  manager: 'Manager',
  technician: 'Technician',
  housekeeper: 'Housekeeper',
  tenant: 'Tenant',
}
