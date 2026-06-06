export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type UserRole = 'manager' | 'tenant' | 'technician' | 'housekeeper'
export type RoomType = 'single' | 'double' | 'studio' | 'suite'
export type RoomStatus = 'available' | 'occupied' | 'maintenance'
export type LeaseStatus = 'active' | 'expiring' | 'expired' | 'terminated'
export type BillStatus = 'draft' | 'pending' | 'paid' | 'overdue'
export type TicketPriority = 'low' | 'medium' | 'high' | 'urgent'
export type TicketStatus = 'open' | 'in_progress' | 'resolved' | 'closed'
export type TaskStatus = 'pending' | 'in_progress' | 'completed' | 'skipped'
export type NotificationType =
  | 'bill_issued'
  | 'bill_overdue'
  | 'ticket_opened'
  | 'ticket_assigned'
  | 'ticket_status_updated'
  | 'ticket_comment_added'
  | 'task_assigned'
  | 'task_completed'
  | 'lease_expiring'

export interface Database {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string
          full_name: string
          phone: string | null
          role: UserRole
          avatar_url: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id: string
          full_name: string
          phone?: string | null
          role?: UserRole
          avatar_url?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          full_name?: string
          phone?: string | null
          role?: UserRole
          avatar_url?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      properties: {
        Row: {
          id: string
          manager_id: string
          name: string
          address: string
          description: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          manager_id: string
          name: string
          address: string
          description?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          manager_id?: string
          name?: string
          address?: string
          description?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      rooms: {
        Row: {
          id: string
          property_id: string
          room_number: string
          floor: number
          room_type: RoomType
          status: RoomStatus
          monthly_rate: number
          notes: string | null
          archived_at: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          property_id: string
          room_number: string
          floor?: number
          room_type?: RoomType
          status?: RoomStatus
          monthly_rate: number
          notes?: string | null
          archived_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          property_id?: string
          room_number?: string
          floor?: number
          room_type?: RoomType
          status?: RoomStatus
          monthly_rate?: number
          notes?: string | null
          archived_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      tenants: {
        Row: {
          id: string
          user_id: string
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
        Insert: {
          id?: string
          user_id: string
          property_id: string
          room_id: string
          lease_start: string
          lease_end?: string | null
          lease_status?: LeaseStatus
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          notes?: string | null
          archived_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          property_id?: string
          room_id?: string
          lease_start?: string
          lease_end?: string | null
          lease_status?: LeaseStatus
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          notes?: string | null
          archived_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      bills: {
        Row: {
          id: string
          tenant_id: string
          property_id: string
          room_id: string
          billing_period_start: string
          billing_period_end: string
          total_amount: number
          status: BillStatus
          due_date: string
          paid_at: string | null
          notes: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          tenant_id: string
          property_id: string
          room_id: string
          billing_period_start: string
          billing_period_end: string
          total_amount?: number
          status?: BillStatus
          due_date: string
          paid_at?: string | null
          notes?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          tenant_id?: string
          property_id?: string
          room_id?: string
          billing_period_start?: string
          billing_period_end?: string
          total_amount?: number
          status?: BillStatus
          due_date?: string
          paid_at?: string | null
          notes?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      bill_line_items: {
        Row: {
          id: string
          bill_id: string
          description: string
          quantity: number
          unit_price: number
          amount: number
          sort_order: number
        }
        Insert: {
          id?: string
          bill_id: string
          description: string
          quantity?: number
          unit_price: number
          sort_order?: number
        }
        Update: {
          id?: string
          bill_id?: string
          description?: string
          quantity?: number
          unit_price?: number
          sort_order?: number
        }
        Relationships: []
      }
      maintenance_tickets: {
        Row: {
          id: string
          property_id: string
          room_id: string
          tenant_id: string | null
          assigned_to: string | null
          title: string
          description: string | null
          priority: TicketPriority
          status: TicketStatus
          resolved_at: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          property_id: string
          room_id: string
          tenant_id?: string | null
          assigned_to?: string | null
          title: string
          description?: string | null
          priority?: TicketPriority
          status?: TicketStatus
          resolved_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          property_id?: string
          room_id?: string
          tenant_id?: string | null
          assigned_to?: string | null
          title?: string
          description?: string | null
          priority?: TicketPriority
          status?: TicketStatus
          resolved_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      maintenance_comments: {
        Row: {
          id: string
          ticket_id: string
          user_id: string
          content: string
          created_at: string
        }
        Insert: {
          id?: string
          ticket_id: string
          user_id: string
          content: string
          created_at?: string
        }
        Update: {
          id?: string
          ticket_id?: string
          user_id?: string
          content?: string
          created_at?: string
        }
        Relationships: []
      }
      maintenance_attachments: {
        Row: {
          id: string
          ticket_id: string
          storage_path: string
          filename: string
          file_size_bytes: number
          mime_type: string
          created_at: string
        }
        Insert: {
          id?: string
          ticket_id: string
          storage_path: string
          filename: string
          file_size_bytes: number
          mime_type: string
          created_at?: string
        }
        Update: {
          id?: string
          ticket_id?: string
          storage_path?: string
          filename?: string
          file_size_bytes?: number
          mime_type?: string
          created_at?: string
        }
        Relationships: []
      }
      housekeeping_tasks: {
        Row: {
          id: string
          property_id: string
          room_id: string
          assigned_to: string | null
          created_by: string
          scheduled_date: string
          status: TaskStatus
          notes: string | null
          completion_notes: string | null
          completed_at: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          property_id: string
          room_id: string
          assigned_to?: string | null
          created_by: string
          scheduled_date: string
          status?: TaskStatus
          notes?: string | null
          completion_notes?: string | null
          completed_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          property_id?: string
          room_id?: string
          assigned_to?: string | null
          created_by?: string
          scheduled_date?: string
          status?: TaskStatus
          notes?: string | null
          completion_notes?: string | null
          completed_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      notifications: {
        Row: {
          id: string
          user_id: string
          type: NotificationType
          title: string
          body: string
          data: Json | null
          is_read: boolean
          read_at: string | null
          created_at: string
        }
        Insert: {
          id?: string
          user_id: string
          type: NotificationType
          title: string
          body: string
          data?: Json | null
          is_read?: boolean
          read_at?: string | null
          created_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          type?: NotificationType
          title?: string
          body?: string
          data?: Json | null
          is_read?: boolean
          read_at?: string | null
          created_at?: string
        }
        Relationships: []
      }
      notifications_archive: {
        Row: {
          id: string
          user_id: string
          type: NotificationType
          title: string
          body: string
          data: Json | null
          is_read: boolean
          read_at: string | null
          created_at: string
          archived_at: string
        }
        Insert: {
          id: string
          user_id: string
          type: NotificationType
          title: string
          body: string
          data?: Json | null
          is_read?: boolean
          read_at?: string | null
          created_at: string
          archived_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          type?: NotificationType
          title?: string
          body?: string
          data?: Json | null
          is_read?: boolean
          read_at?: string | null
          created_at?: string
          archived_at?: string
        }
        Relationships: []
      }
      property_staff: {
        Row: {
          id: string
          property_id: string
          user_id: string
          role: 'technician' | 'housekeeper'
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          property_id: string
          user_id: string
          role: 'technician' | 'housekeeper'
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          property_id?: string
          user_id?: string
          role?: 'technician' | 'housekeeper'
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
      line_connections: {
        Row: {
          id: string
          user_id: string
          line_user_id: string
          is_active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          line_user_id: string
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          line_user_id?: string
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: Record<string, never>
    Functions: {
      current_user_role: { Args: Record<string, never>; Returns: UserRole }
      is_property_manager: { Args: { p_property_id: string }; Returns: boolean }
      is_property_tenant: { Args: { p_property_id: string }; Returns: boolean }
    }
    Enums: {
      user_role: UserRole
      room_type: RoomType
      room_status: RoomStatus
      lease_status: LeaseStatus
      bill_status: BillStatus
      ticket_priority: TicketPriority
      ticket_status: TicketStatus
      task_status: TaskStatus
      notification_type: NotificationType
    }
    CompositeTypes: Record<string, never>
  }
}
