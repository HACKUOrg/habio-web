'use server'

import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveMembershipForUser } from '@/lib/actions/membership'
import { recordAuditEvent } from '@/lib/audit/record'
import {
  DEFAULT_PAGE_SIZE,
  decodeCursor,
  toPaginatedResult,
  buildCursorFilter,
  type PaginatedResult,
} from '@/lib/pagination'
import type { PropertyRow, PropertyStatus } from '@/types'

export type PropertyActionState = {
  error?: string
}

async function requireOwnerMembership() {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const userId = data?.claims?.sub
  if (!userId) redirect('/auth/login')

  const active = await getActiveMembershipForUser(userId)
  if (!active || active.role !== 'owner') {
    redirect('/select-membership')
  }

  return { supabase, active }
}

export async function listOrganizationProperties(
  cursor?: string | null
): Promise<PaginatedResult<PropertyRow>> {
  const { supabase, active } = await requireOwnerMembership()
  const decoded = cursor ? decodeCursor(cursor) : null
  const cursorFilter = buildCursorFilter(decoded)

  let query = supabase
    .from('properties')
    .select('*')
    .eq('organization_id', active.organizationId)
    .is('archived_at', null)
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .limit(DEFAULT_PAGE_SIZE + 1)

  if (cursorFilter) {
    query = query.or(cursorFilter)
  }

  const { data, error } = await query

  if (error || !data) {
    return { data: [], nextCursor: null, hasMore: false }
  }

  return toPaginatedResult(data as PropertyRow[], DEFAULT_PAGE_SIZE)
}

export async function getProperty(propertyId: string): Promise<PropertyRow | null> {
  const { supabase, active } = await requireOwnerMembership()

  const { data, error } = await supabase
    .from('properties')
    .select('*')
    .eq('id', propertyId)
    .eq('organization_id', active.organizationId)
    .maybeSingle()

  if (error || !data) return null
  return data as PropertyRow
}

export async function createProperty(
  _prevState: PropertyActionState,
  formData: FormData
): Promise<PropertyActionState> {
  const name = String(formData.get('name') ?? '').trim()
  const address = String(formData.get('address') ?? '').trim()
  const phone = String(formData.get('phone') ?? '').trim() || null
  const description = String(formData.get('description') ?? '').trim() || null

  if (!name || !address) {
    return { error: 'Name and address are required.' }
  }

  const { supabase, active } = await requireOwnerMembership()

  const { data: withinLimit, error: limitError } = await supabase.rpc('check_property_limit', {
    p_org_id: active.organizationId,
  })

  if (limitError) {
    return { error: limitError.message }
  }

  if (!withinLimit) {
    return { error: 'Property limit reached for your subscription plan. Upgrade to add more properties.' }
  }

  const { data, error } = await supabase
    .from('properties')
    .insert({
      organization_id: active.organizationId,
      name,
      address,
      phone,
      description,
      status: 'active' as PropertyStatus,
    })
    .select('id')
    .single()

  if (error || !data) {
    return { error: error?.message ?? 'Unable to create property.' }
  }

  await recordAuditEvent(supabase, {
    organizationId: active.organizationId,
    propertyId: data.id,
    eventType: 'property_created',
    metadata: { name, address },
  })

  revalidatePath('/owner/properties')
  redirect(`/owner/properties/${data.id}/edit`)
}

export async function updateProperty(
  _prevState: PropertyActionState,
  formData: FormData
): Promise<PropertyActionState> {
  const propertyId = String(formData.get('propertyId') ?? '').trim()
  const name = String(formData.get('name') ?? '').trim()
  const address = String(formData.get('address') ?? '').trim()
  const phone = String(formData.get('phone') ?? '').trim() || null
  const description = String(formData.get('description') ?? '').trim() || null
  const status = String(formData.get('status') ?? 'active') as PropertyStatus

  if (!propertyId || !name || !address) {
    return { error: 'Name and address are required.' }
  }

  const { supabase, active } = await requireOwnerMembership()

  const { error } = await supabase
    .from('properties')
    .update({ name, address, phone, description, status })
    .eq('id', propertyId)
    .eq('organization_id', active.organizationId)

  if (error) {
    return { error: error.message }
  }

  await recordAuditEvent(supabase, {
    organizationId: active.organizationId,
    propertyId,
    eventType: 'property_updated',
    metadata: { name, status },
  })

  revalidatePath('/owner/properties')
  revalidatePath(`/owner/properties/${propertyId}/edit`)
  return {}
}
