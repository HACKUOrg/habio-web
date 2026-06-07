export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      audit_logs: {
        Row: {
          actor_id: string | null
          created_at: string
          event_type: string
          id: string
          metadata: Json
          organization_id: string | null
          property_id: string | null
        }
        Insert: {
          actor_id?: string | null
          created_at?: string
          event_type: string
          id?: string
          metadata?: Json
          organization_id?: string | null
          property_id?: string | null
        }
        Update: {
          actor_id?: string | null
          created_at?: string
          event_type?: string
          id?: string
          metadata?: Json
          organization_id?: string | null
          property_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_logs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_logs_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
        ]
      }
      audit_logs_archive: {
        Row: {
          actor_id: string | null
          archived_at: string
          created_at: string
          event_type: string
          id: string
          metadata: Json
          organization_id: string | null
          property_id: string | null
        }
        Insert: {
          actor_id?: string | null
          archived_at?: string
          created_at: string
          event_type: string
          id: string
          metadata?: Json
          organization_id?: string | null
          property_id?: string | null
        }
        Update: {
          actor_id?: string | null
          archived_at?: string
          created_at?: string
          event_type?: string
          id?: string
          metadata?: Json
          organization_id?: string | null
          property_id?: string | null
        }
        Relationships: []
      }
      bill_line_items: {
        Row: {
          amount: number | null
          bill_id: string
          description: string
          id: string
          quantity: number
          sort_order: number
          unit_price: number
        }
        Insert: {
          amount?: number | null
          bill_id: string
          description: string
          id?: string
          quantity?: number
          sort_order?: number
          unit_price: number
        }
        Update: {
          amount?: number | null
          bill_id?: string
          description?: string
          id?: string
          quantity?: number
          sort_order?: number
          unit_price?: number
        }
        Relationships: [
          {
            foreignKeyName: "bill_line_items_bill_id_fkey"
            columns: ["bill_id"]
            isOneToOne: false
            referencedRelation: "bills"
            referencedColumns: ["id"]
          },
        ]
      }
      billing_periods: {
        Row: {
          created_at: string
          created_by: string
          end_date: string
          id: string
          name: string
          organization_id: string
          property_id: string
          start_date: string
          status: Database["public"]["Enums"]["billing_period_status"]
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by: string
          end_date: string
          id?: string
          name: string
          organization_id: string
          property_id: string
          start_date: string
          status?: Database["public"]["Enums"]["billing_period_status"]
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string
          end_date?: string
          id?: string
          name?: string
          organization_id?: string
          property_id?: string
          start_date?: string
          status?: Database["public"]["Enums"]["billing_period_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "billing_periods_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "billing_periods_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "billing_periods_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
        ]
      }
      bills: {
        Row: {
          archived_at: string | null
          billing_period_end: string
          billing_period_id: string | null
          billing_period_start: string
          created_at: string
          due_date: string
          id: string
          notes: string | null
          organization_id: string
          paid_at: string | null
          property_id: string
          room_id: string
          status: Database["public"]["Enums"]["bill_status"]
          tenant_profile_id: string
          total_amount: number
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          billing_period_end: string
          billing_period_id?: string | null
          billing_period_start: string
          created_at?: string
          due_date: string
          id?: string
          notes?: string | null
          organization_id: string
          paid_at?: string | null
          property_id: string
          room_id: string
          status?: Database["public"]["Enums"]["bill_status"]
          tenant_profile_id: string
          total_amount?: number
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          billing_period_end?: string
          billing_period_id?: string | null
          billing_period_start?: string
          created_at?: string
          due_date?: string
          id?: string
          notes?: string | null
          organization_id?: string
          paid_at?: string | null
          property_id?: string
          room_id?: string
          status?: Database["public"]["Enums"]["bill_status"]
          tenant_profile_id?: string
          total_amount?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "bills_billing_period_id_fkey"
            columns: ["billing_period_id"]
            isOneToOne: false
            referencedRelation: "billing_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bills_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bills_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bills_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bills_tenant_profile_id_fkey"
            columns: ["tenant_profile_id"]
            isOneToOne: false
            referencedRelation: "tenant_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      buildings: {
        Row: {
          archived_at: string | null
          created_at: string
          id: string
          name: string
          organization_id: string
          property_id: string
          total_floors: number
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          id?: string
          name: string
          organization_id: string
          property_id: string
          total_floors?: number
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          id?: string
          name?: string
          organization_id?: string
          property_id?: string
          total_floors?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "buildings_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "buildings_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
        ]
      }
      housekeeping_tasks: {
        Row: {
          archived_at: string | null
          assigned_to: string | null
          completed_at: string | null
          completion_notes: string | null
          created_at: string
          created_by: string
          id: string
          notes: string | null
          organization_id: string
          property_id: string
          room_id: string
          scheduled_date: string
          status: Database["public"]["Enums"]["task_status"]
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          assigned_to?: string | null
          completed_at?: string | null
          completion_notes?: string | null
          created_at?: string
          created_by: string
          id?: string
          notes?: string | null
          organization_id: string
          property_id: string
          room_id: string
          scheduled_date: string
          status?: Database["public"]["Enums"]["task_status"]
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          assigned_to?: string | null
          completed_at?: string | null
          completion_notes?: string | null
          created_at?: string
          created_by?: string
          id?: string
          notes?: string | null
          organization_id?: string
          property_id?: string
          room_id?: string
          scheduled_date?: string
          status?: Database["public"]["Enums"]["task_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "housekeeping_tasks_assigned_to_fkey"
            columns: ["assigned_to"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "housekeeping_tasks_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "housekeeping_tasks_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "housekeeping_tasks_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "housekeeping_tasks_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      invitations: {
        Row: {
          accepted_at: string | null
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string
          lease_end: string | null
          lease_start: string | null
          organization_id: string
          property_id: string | null
          role: Database["public"]["Enums"]["membership_role"]
          room_id: string | null
          status: Database["public"]["Enums"]["invitation_status"]
          token_hash: string
        }
        Insert: {
          accepted_at?: string | null
          created_at?: string
          email: string
          expires_at: string
          id?: string
          invited_by: string
          lease_end?: string | null
          lease_start?: string | null
          organization_id: string
          property_id?: string | null
          role: Database["public"]["Enums"]["membership_role"]
          room_id?: string | null
          status?: Database["public"]["Enums"]["invitation_status"]
          token_hash: string
        }
        Update: {
          accepted_at?: string | null
          created_at?: string
          email?: string
          expires_at?: string
          id?: string
          invited_by?: string
          lease_end?: string | null
          lease_start?: string | null
          organization_id?: string
          property_id?: string | null
          role?: Database["public"]["Enums"]["membership_role"]
          room_id?: string | null
          status?: Database["public"]["Enums"]["invitation_status"]
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "invitations_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invitations_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invitations_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "invitations_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
        ]
      }
      invitations_archive: {
        Row: {
          accepted_at: string | null
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string
          organization_id: string
          property_id: string
          role: Database["public"]["Enums"]["membership_role"]
          status: Database["public"]["Enums"]["invitation_status"]
          token_hash: string
        }
        Insert: {
          accepted_at?: string | null
          created_at?: string
          email: string
          expires_at: string
          id?: string
          invited_by: string
          organization_id: string
          property_id: string
          role: Database["public"]["Enums"]["membership_role"]
          status?: Database["public"]["Enums"]["invitation_status"]
          token_hash: string
        }
        Update: {
          accepted_at?: string | null
          created_at?: string
          email?: string
          expires_at?: string
          id?: string
          invited_by?: string
          organization_id?: string
          property_id?: string
          role?: Database["public"]["Enums"]["membership_role"]
          status?: Database["public"]["Enums"]["invitation_status"]
          token_hash?: string
        }
        Relationships: []
      }
      maintenance_attachments: {
        Row: {
          created_at: string
          file_size_bytes: number
          filename: string
          id: string
          mime_type: string
          storage_path: string
          ticket_id: string
        }
        Insert: {
          created_at?: string
          file_size_bytes: number
          filename: string
          id?: string
          mime_type: string
          storage_path: string
          ticket_id: string
        }
        Update: {
          created_at?: string
          file_size_bytes?: number
          filename?: string
          id?: string
          mime_type?: string
          storage_path?: string
          ticket_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "maintenance_attachments_ticket_id_fkey"
            columns: ["ticket_id"]
            isOneToOne: false
            referencedRelation: "maintenance_tickets"
            referencedColumns: ["id"]
          },
        ]
      }
      maintenance_comments: {
        Row: {
          content: string
          created_at: string
          id: string
          ticket_id: string
          user_id: string
        }
        Insert: {
          content: string
          created_at?: string
          id?: string
          ticket_id: string
          user_id: string
        }
        Update: {
          content?: string
          created_at?: string
          id?: string
          ticket_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "maintenance_comments_ticket_id_fkey"
            columns: ["ticket_id"]
            isOneToOne: false
            referencedRelation: "maintenance_tickets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maintenance_comments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      maintenance_tickets: {
        Row: {
          archived_at: string | null
          assigned_to: string | null
          created_at: string
          description: string | null
          id: string
          organization_id: string
          priority: Database["public"]["Enums"]["ticket_priority"]
          property_id: string
          resolved_at: string | null
          room_id: string
          status: Database["public"]["Enums"]["ticket_status"]
          tenant_profile_id: string | null
          title: string
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          assigned_to?: string | null
          created_at?: string
          description?: string | null
          id?: string
          organization_id: string
          priority?: Database["public"]["Enums"]["ticket_priority"]
          property_id: string
          resolved_at?: string | null
          room_id: string
          status?: Database["public"]["Enums"]["ticket_status"]
          tenant_profile_id?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          assigned_to?: string | null
          created_at?: string
          description?: string | null
          id?: string
          organization_id?: string
          priority?: Database["public"]["Enums"]["ticket_priority"]
          property_id?: string
          resolved_at?: string | null
          room_id?: string
          status?: Database["public"]["Enums"]["ticket_status"]
          tenant_profile_id?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "maintenance_tickets_assigned_to_fkey"
            columns: ["assigned_to"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maintenance_tickets_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maintenance_tickets_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maintenance_tickets_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "maintenance_tickets_tenant_profile_id_fkey"
            columns: ["tenant_profile_id"]
            isOneToOne: false
            referencedRelation: "tenant_profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      memberships: {
        Row: {
          created_at: string
          created_by: string | null
          deactivated_at: string | null
          id: string
          organization_id: string
          property_id: string | null
          role: Database["public"]["Enums"]["membership_role"]
          user_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          deactivated_at?: string | null
          id?: string
          organization_id: string
          property_id?: string | null
          role: Database["public"]["Enums"]["membership_role"]
          user_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          deactivated_at?: string | null
          id?: string
          organization_id?: string
          property_id?: string | null
          role?: Database["public"]["Enums"]["membership_role"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "memberships_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "memberships_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "memberships_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "memberships_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      meter_readings: {
        Row: {
          approved_by: string | null
          billing_period_id: string
          created_at: string
          current_reading: number | null
          id: string
          notes: string | null
          organization_id: string
          previous_reading: number
          property_id: string
          reading_date: string | null
          room_id: string
          status: Database["public"]["Enums"]["meter_reading_status"]
          submitted_by: string | null
          updated_at: string
        }
        Insert: {
          approved_by?: string | null
          billing_period_id: string
          created_at?: string
          current_reading?: number | null
          id?: string
          notes?: string | null
          organization_id: string
          previous_reading?: number
          property_id: string
          reading_date?: string | null
          room_id: string
          status?: Database["public"]["Enums"]["meter_reading_status"]
          submitted_by?: string | null
          updated_at?: string
        }
        Update: {
          approved_by?: string | null
          billing_period_id?: string
          created_at?: string
          current_reading?: number | null
          id?: string
          notes?: string | null
          organization_id?: string
          previous_reading?: number
          property_id?: string
          reading_date?: string | null
          room_id?: string
          status?: Database["public"]["Enums"]["meter_reading_status"]
          submitted_by?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "meter_readings_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meter_readings_billing_period_id_fkey"
            columns: ["billing_period_id"]
            isOneToOne: false
            referencedRelation: "billing_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meter_readings_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meter_readings_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meter_readings_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "meter_readings_submitted_by_fkey"
            columns: ["submitted_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_deliveries: {
        Row: {
          channel: Database["public"]["Enums"]["notification_channel"]
          created_at: string
          error: string | null
          id: string
          notification_id: string
          sent_at: string | null
          status: Database["public"]["Enums"]["notification_delivery_status"]
        }
        Insert: {
          channel: Database["public"]["Enums"]["notification_channel"]
          created_at?: string
          error?: string | null
          id?: string
          notification_id: string
          sent_at?: string | null
          status?: Database["public"]["Enums"]["notification_delivery_status"]
        }
        Update: {
          channel?: Database["public"]["Enums"]["notification_channel"]
          created_at?: string
          error?: string | null
          id?: string
          notification_id?: string
          sent_at?: string | null
          status?: Database["public"]["Enums"]["notification_delivery_status"]
        }
        Relationships: [
          {
            foreignKeyName: "notification_deliveries_notification_id_fkey"
            columns: ["notification_id"]
            isOneToOne: false
            referencedRelation: "notifications"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          body: string | null
          created_at: string
          event_type: string
          id: string
          metadata: Json | null
          organization_id: string
          read_at: string | null
          title: string
          user_id: string
        }
        Insert: {
          body?: string | null
          created_at?: string
          event_type: string
          id?: string
          metadata?: Json | null
          organization_id: string
          read_at?: string | null
          title: string
          user_id: string
        }
        Update: {
          body?: string | null
          created_at?: string
          event_type?: string
          id?: string
          metadata?: Json | null
          organization_id?: string
          read_at?: string | null
          title?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications_archive: {
        Row: {
          archived_at: string
          body: string | null
          created_at: string
          event_type: string
          id: string
          metadata: Json | null
          organization_id: string
          read_at: string | null
          title: string
          user_id: string
        }
        Insert: {
          archived_at?: string
          body?: string | null
          created_at?: string
          event_type: string
          id?: string
          metadata?: Json | null
          organization_id: string
          read_at?: string | null
          title: string
          user_id: string
        }
        Update: {
          archived_at?: string
          body?: string | null
          created_at?: string
          event_type?: string
          id?: string
          metadata?: Json | null
          organization_id?: string
          read_at?: string | null
          title?: string
          user_id?: string
        }
        Relationships: []
      }
      organization_subscriptions: {
        Row: {
          billing_cycle: string
          cancelled_at: string | null
          created_at: string
          current_period_end: string
          current_period_start: string
          id: string
          organization_id: string
          plan_id: string
          status: string
          trial_ends_at: string | null
          updated_at: string
        }
        Insert: {
          billing_cycle?: string
          cancelled_at?: string | null
          created_at?: string
          current_period_end: string
          current_period_start: string
          id?: string
          organization_id: string
          plan_id: string
          status?: string
          trial_ends_at?: string | null
          updated_at?: string
        }
        Update: {
          billing_cycle?: string
          cancelled_at?: string | null
          created_at?: string
          current_period_end?: string
          current_period_start?: string
          id?: string
          organization_id?: string
          plan_id?: string
          status?: string
          trial_ends_at?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_subscriptions_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: true
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "organization_subscriptions_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "subscription_plans"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          created_at: string
          id: string
          name: string
          plan: string
          slug: string
          suspended_at: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          plan?: string
          slug: string
          suspended_at?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          plan?: string
          slug?: string
          suspended_at?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      platform_admins: {
        Row: {
          created_at: string
          granted_by: string | null
          id: string
          revoked_at: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          granted_by?: string | null
          id?: string
          revoked_at?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          granted_by?: string | null
          id?: string
          revoked_at?: string | null
          user_id?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          full_name: string
          id: string
          phone: string | null
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          full_name: string
          id: string
          phone?: string | null
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          full_name?: string
          id?: string
          phone?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      properties: {
        Row: {
          address: string
          archived_at: string | null
          created_at: string
          description: string | null
          id: string
          name: string
          organization_id: string
          phone: string | null
          status: Database["public"]["Enums"]["property_status"]
          updated_at: string
        }
        Insert: {
          address: string
          archived_at?: string | null
          created_at?: string
          description?: string | null
          id?: string
          name: string
          organization_id: string
          phone?: string | null
          status?: Database["public"]["Enums"]["property_status"]
          updated_at?: string
        }
        Update: {
          address?: string
          archived_at?: string | null
          created_at?: string
          description?: string | null
          id?: string
          name?: string
          organization_id?: string
          phone?: string | null
          status?: Database["public"]["Enums"]["property_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "properties_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      rooms: {
        Row: {
          archived_at: string | null
          building_id: string
          created_at: string
          floor: number
          id: string
          monthly_rate: number
          notes: string | null
          property_id: string
          room_number: string
          room_type: Database["public"]["Enums"]["room_type"]
          status: Database["public"]["Enums"]["room_status"]
          updated_at: string
        }
        Insert: {
          archived_at?: string | null
          building_id: string
          created_at?: string
          floor?: number
          id?: string
          monthly_rate: number
          notes?: string | null
          property_id: string
          room_number: string
          room_type?: Database["public"]["Enums"]["room_type"]
          status?: Database["public"]["Enums"]["room_status"]
          updated_at?: string
        }
        Update: {
          archived_at?: string | null
          building_id?: string
          created_at?: string
          floor?: number
          id?: string
          monthly_rate?: number
          notes?: string | null
          property_id?: string
          room_number?: string
          room_type?: Database["public"]["Enums"]["room_type"]
          status?: Database["public"]["Enums"]["room_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "rooms_building_id_fkey"
            columns: ["building_id"]
            isOneToOne: false
            referencedRelation: "buildings"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "rooms_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
        ]
      }
      subscription_plans: {
        Row: {
          created_at: string
          features: Json
          id: string
          max_properties: number | null
          max_rooms_per_property: number | null
          name: string
        }
        Insert: {
          created_at?: string
          features?: Json
          id?: string
          max_properties?: number | null
          max_rooms_per_property?: number | null
          name: string
        }
        Update: {
          created_at?: string
          features?: Json
          id?: string
          max_properties?: number | null
          max_rooms_per_property?: number | null
          name?: string
        }
        Relationships: []
      }
      tenant_profiles: {
        Row: {
          archived_at: string | null
          created_at: string
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          id: string
          lease_end: string | null
          lease_start: string
          lease_status: Database["public"]["Enums"]["lease_status"]
          membership_id: string
          notes: string | null
          organization_id: string
          property_id: string
          room_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          id?: string
          lease_end?: string | null
          lease_start: string
          lease_status?: Database["public"]["Enums"]["lease_status"]
          membership_id: string
          notes?: string | null
          organization_id: string
          property_id: string
          room_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          id?: string
          lease_end?: string | null
          lease_start?: string
          lease_status?: Database["public"]["Enums"]["lease_status"]
          membership_id?: string
          notes?: string | null
          organization_id?: string
          property_id?: string
          room_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tenant_profiles_membership_id_fkey"
            columns: ["membership_id"]
            isOneToOne: true
            referencedRelation: "memberships"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_profiles_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_profiles_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_profiles_room_id_fkey"
            columns: ["room_id"]
            isOneToOne: false
            referencedRelation: "rooms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_profiles_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      usage_counters: {
        Row: {
          count: number
          metric: string
          organization_id: string
          period_start: string
          updated_at: string
        }
        Insert: {
          count?: number
          metric: string
          organization_id: string
          period_start: string
          updated_at?: string
        }
        Update: {
          count?: number
          metric?: string
          organization_id?: string
          period_start?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "usage_counters_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      user_identities: {
        Row: {
          id: string
          last_login_at: string | null
          linked_at: string
          provider: string
          provider_user_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          id?: string
          last_login_at?: string | null
          linked_at?: string
          provider: string
          provider_user_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          id?: string
          last_login_at?: string | null
          linked_at?: string
          provider?: string
          provider_user_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      organization_activity_feed: {
        Row: {
          actor_id: string | null
          created_at: string | null
          event_type: string | null
          id: string | null
          metadata: Json | null
          organization_id: string | null
          property_id: string | null
        }
        Insert: {
          actor_id?: string | null
          created_at?: string | null
          event_type?: string | null
          id?: string | null
          metadata?: Json | null
          organization_id?: string | null
          property_id?: string | null
        }
        Update: {
          actor_id?: string | null
          created_at?: string | null
          event_type?: string | null
          id?: string | null
          metadata?: Json | null
          organization_id?: string | null
          property_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_logs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_logs_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
        ]
      }
      property_activity_feed: {
        Row: {
          actor_id: string | null
          created_at: string | null
          event_type: string | null
          id: string | null
          metadata: Json | null
          organization_id: string | null
          property_id: string | null
        }
        Insert: {
          actor_id?: string | null
          created_at?: string | null
          event_type?: string | null
          id?: string | null
          metadata?: Json | null
          organization_id?: string | null
          property_id?: string | null
        }
        Update: {
          actor_id?: string | null
          created_at?: string | null
          event_type?: string | null
          id?: string | null
          metadata?: Json | null
          organization_id?: string | null
          property_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_logs_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_logs_property_id_fkey"
            columns: ["property_id"]
            isOneToOne: false
            referencedRelation: "properties"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      accept_invitation: { Args: { p_token: string }; Returns: Json }
      accept_tenant_activation: { Args: { p_token: string }; Returns: Json }
      can_access_property: { Args: { p_property_id: string }; Returns: boolean }
      can_manage_property: { Args: { p_property_id: string }; Returns: boolean }
      check_property_limit: { Args: { p_org_id: string }; Returns: boolean }
      create_owner_invitation: { Args: { p_email: string }; Returns: Json }
      create_owner_organization: {
        Args: {
          p_org_name: string
          p_property_address?: string
          p_property_name: string
        }
        Returns: Json
      }
      create_staff_invitation: {
        Args: {
          p_email: string
          p_property_id: string
          p_role: Database["public"]["Enums"]["membership_role"]
        }
        Returns: Json
      }
      create_tenant_activation: {
        Args: {
          p_email: string
          p_lease_end?: string
          p_lease_start: string
          p_property_id: string
          p_room_id: string
        }
        Returns: Json
      }
      get_invitation_preview: { Args: { p_token: string }; Returns: Json }
      get_tenant_activation_preview: {
        Args: { p_token: string }
        Returns: Json
      }
      has_property_role: {
        Args: {
          p_property_id: string
          p_role: Database["public"]["Enums"]["membership_role"]
        }
        Returns: boolean
      }
      is_feature_enabled: {
        Args: { p_feature_key: string; p_org_id: string }
        Returns: boolean
      }
      is_org_owner: { Args: { p_org_id: string }; Returns: boolean }
      is_platform_admin: { Args: never; Returns: boolean }
      is_property_manager: { Args: { p_property_id: string }; Returns: boolean }
      is_staff_role: {
        Args: { p_role: Database["public"]["Enums"]["membership_role"] }
        Returns: boolean
      }
      record_audit_event: {
        Args: {
          p_event_type: string
          p_metadata?: Json
          p_organization_id: string
          p_property_id: string
        }
        Returns: undefined
      }
      slugify_org_name: { Args: { p_name: string }; Returns: string }
    }
    Enums: {
      bill_status: "draft" | "pending" | "paid" | "overdue"
      billing_period_status: "open" | "closed" | "archived"
      invitation_status: "pending" | "accepted" | "expired" | "revoked"
      lease_status: "active" | "expiring" | "expired" | "terminated"
      membership_role:
        | "owner"
        | "manager"
        | "technician"
        | "housekeeper"
        | "tenant"
      meter_reading_status: "pending" | "submitted" | "approved" | "rejected"
      notification_channel: "in_app" | "email" | "line"
      notification_delivery_status:
        | "pending"
        | "sent"
        | "failed"
        | "read"
        | "skipped"
      notification_type:
        | "bill_issued"
        | "bill_overdue"
        | "ticket_opened"
        | "ticket_assigned"
        | "ticket_status_updated"
        | "ticket_comment_added"
        | "task_assigned"
        | "task_completed"
        | "lease_expiring"
        | "meter_reading_submitted"
        | "meter_reading_approved"
        | "meter_reading_rejected"
      property_status: "active" | "inactive" | "archived"
      room_status: "available" | "occupied" | "maintenance"
      room_type: "single" | "double" | "studio" | "suite"
      task_status: "pending" | "in_progress" | "completed" | "skipped"
      ticket_priority: "low" | "medium" | "high" | "urgent"
      ticket_status: "open" | "in_progress" | "resolved" | "closed"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      bill_status: ["draft", "pending", "paid", "overdue"],
      billing_period_status: ["open", "closed", "archived"],
      invitation_status: ["pending", "accepted", "expired", "revoked"],
      lease_status: ["active", "expiring", "expired", "terminated"],
      membership_role: [
        "owner",
        "manager",
        "technician",
        "housekeeper",
        "tenant",
      ],
      meter_reading_status: ["pending", "submitted", "approved", "rejected"],
      notification_channel: ["in_app", "email", "line"],
      notification_delivery_status: [
        "pending",
        "sent",
        "failed",
        "read",
        "skipped",
      ],
      notification_type: [
        "bill_issued",
        "bill_overdue",
        "ticket_opened",
        "ticket_assigned",
        "ticket_status_updated",
        "ticket_comment_added",
        "task_assigned",
        "task_completed",
        "lease_expiring",
        "meter_reading_submitted",
        "meter_reading_approved",
        "meter_reading_rejected",
      ],
      property_status: ["active", "inactive", "archived"],
      room_status: ["available", "occupied", "maintenance"],
      room_type: ["single", "double", "studio", "suite"],
      task_status: ["pending", "in_progress", "completed", "skipped"],
      ticket_priority: ["low", "medium", "high", "urgent"],
      ticket_status: ["open", "in_progress", "resolved", "closed"],
    },
  },
} as const

