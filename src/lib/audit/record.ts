import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '@/types/database'

export type AuditEventInput = {
  organizationId: string
  propertyId?: string | null
  eventType: string
  metadata?: Record<string, unknown>
}

export async function recordAuditEvent(
  supabase: SupabaseClient<Database>,
  event: AuditEventInput
): Promise<void> {
  const { error } = await supabase.rpc('record_audit_event', {
    p_organization_id: event.organizationId,
    p_property_id: event.propertyId ?? undefined,
    p_event_type: event.eventType,
    p_metadata: (event.metadata ?? {}) as Database['public']['Functions']['record_audit_event']['Args']['p_metadata'],
  })

  if (error) {
    console.error('Failed to record audit event:', event.eventType, error.message)
  }
}
