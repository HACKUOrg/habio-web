import type { Database, UserRole } from './database'

export type { Database, UserRole } from './database'
export type {
  RoomType,
  RoomStatus,
  LeaseStatus,
  BillStatus,
  TicketPriority,
  TicketStatus,
  TaskStatus,
  NotificationType,
} from './database'

export type ProfileRow = Database['public']['Tables']['profiles']['Row']
export type PropertyRow = Database['public']['Tables']['properties']['Row']
export type RoomRow = Database['public']['Tables']['rooms']['Row']
export type TenantRow = Database['public']['Tables']['tenants']['Row']
export type BillRow = Database['public']['Tables']['bills']['Row']

export const ROLE_ROUTES: UserRole[] = [
  'manager',
  'tenant',
  'technician',
  'housekeeper',
]

export function roleDashboardPath(role: UserRole): string {
  return `/${role}/dashboard`
}
