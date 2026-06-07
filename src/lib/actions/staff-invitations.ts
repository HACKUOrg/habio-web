'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { getActiveMembershipForUser } from '@/lib/actions/membership'
import { recordAuditEvent } from '@/lib/audit/record'
import { sendActivationEmail, sendInvitationEmail } from '@/lib/email/send'
import {
  invitableRolesForMembership,
  type InvitableRole,
} from '@/lib/invitations/roles'
import {
  DEFAULT_PAGE_SIZE,
  decodeCursor,
  toPaginatedResult,
  buildCursorFilter,
  type PaginatedResult,
} from '@/lib/pagination'
import type { MembershipRole } from '@/types'

export type InvitationActionState = {
  error?: string
  inviteUrl?: string
}

interface CreateInvitationResult {
  invitation_id: string
  token: string
}

interface PropertyOption {
  id: string
  name: string
}

export type PendingInvitationRow = {
  id: string
  email: string
  role: MembershipRole
  status: string
  expires_at: string
  created_at: string
  properties: { name: string } | null
}

export async function getInvitableProperties(): Promise<PropertyOption[]> {
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  const userId = claims?.claims?.sub
  if (!userId) return []

  const active = await getActiveMembershipForUser(userId)
  if (!active) return []

  if (active.role === 'owner') {
    const { data } = await supabase
      .from('properties')
      .select('id, name')
      .eq('organization_id', active.organizationId)
      .neq('status', 'archived')
      .is('archived_at', null)
      .order('name')

    return (data ?? []) as PropertyOption[]
  }

  if (active.role === 'manager' && active.propertyId) {
    const { data } = await supabase
      .from('properties')
      .select('id, name')
      .eq('id', active.propertyId)
      .neq('status', 'archived')
      .is('archived_at', null)
      .maybeSingle()

    return data ? [data as PropertyOption] : []
  }

  return []
}

export async function createStaffInvitation(
  _prevState: InvitationActionState,
  formData: FormData
): Promise<InvitationActionState> {
  const email = String(formData.get('email') ?? '').trim()
  const role = String(formData.get('role') ?? '') as InvitableRole
  const propertyId = String(formData.get('propertyId') ?? '').trim()

  if (!email || !role || !propertyId) {
    return { error: 'Email, role, and property are required.' }
  }

  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  const userId = claims?.claims?.sub
  if (!userId) {
    return { error: 'You must be signed in to send invitations.' }
  }

  const active = await getActiveMembershipForUser(userId)
  if (!active) {
    return { error: 'No active membership found.' }
  }

  const allowedRoles = invitableRolesForMembership(active.role)
  if (!allowedRoles.includes(role)) {
    return { error: 'You are not allowed to invite this role.' }
  }

  const { data: property } = await supabase
    .from('properties')
    .select('name')
    .eq('id', propertyId)
    .maybeSingle()

  const { data, error } = await supabase.rpc('create_staff_invitation', {
    p_email: email,
    p_role: role,
    p_property_id: propertyId,
  })

  if (error || !data) {
    return { error: error?.message ?? 'Unable to create invitation.' }
  }

  const result = data as unknown as CreateInvitationResult
  const baseUrl = process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'
  const inviteUrl = `${baseUrl}/auth/invite/${result.token}`

  await sendInvitationEmail({
    to: email,
    inviteUrl,
    role,
    propertyName: property?.name ?? null,
  })

  await recordAuditEvent(supabase, {
    organizationId: active.organizationId,
    propertyId,
    eventType: 'invitation_created',
    metadata: { email, role, invitation_id: result.invitation_id },
  })

  revalidatePath(`/${active.role}/staff/invite`)

  return { inviteUrl }
}

export async function createTenantActivation(
  _prevState: InvitationActionState,
  formData: FormData
): Promise<InvitationActionState> {
  const email = String(formData.get('email') ?? '').trim()
  const propertyId = String(formData.get('propertyId') ?? '').trim()
  const roomId = String(formData.get('roomId') ?? '').trim()
  const leaseStart = String(formData.get('leaseStart') ?? '').trim()
  const leaseEnd = String(formData.get('leaseEnd') ?? '').trim() || null

  if (!email || !propertyId || !roomId || !leaseStart) {
    return { error: 'Email, property, room, and lease start are required.' }
  }

  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  const userId = claims?.claims?.sub
  if (!userId) {
    return { error: 'You must be signed in.' }
  }

  const active = await getActiveMembershipForUser(userId)
  if (!active || (active.role !== 'owner' && active.role !== 'manager')) {
    return { error: 'Not authorized to create tenant activations.' }
  }

  const { data: property } = await supabase
    .from('properties')
    .select('name')
    .eq('id', propertyId)
    .maybeSingle()

  const { data: room } = await supabase
    .from('rooms')
    .select('room_number')
    .eq('id', roomId)
    .maybeSingle()

  const { data, error } = await supabase.rpc('create_tenant_activation', {
    p_email: email,
    p_property_id: propertyId,
    p_room_id: roomId,
    p_lease_start: leaseStart,
    p_lease_end: leaseEnd ?? undefined,
  })

  if (error || !data) {
    return { error: error?.message ?? 'Unable to create tenant activation.' }
  }

  const result = data as unknown as CreateInvitationResult
  const baseUrl = process.env.NEXT_PUBLIC_APP_URL ?? 'http://localhost:3000'
  const inviteUrl = `${baseUrl}/auth/activate/${result.token}`

  await sendActivationEmail({
    to: email,
    activateUrl: inviteUrl,
    propertyName: property?.name ?? null,
    roomNumber: room?.room_number ?? null,
  })

  await recordAuditEvent(supabase, {
    organizationId: active.organizationId,
    propertyId,
    eventType: 'tenant_activation_created',
    metadata: {
      email,
      room_id: roomId,
      invitation_id: result.invitation_id,
    },
  })

  revalidatePath(`/${active.role}/tenants/new`)

  return { inviteUrl }
}

export async function getAvailableRooms(propertyId: string) {
  const supabase = await createClient()
  const { data } = await supabase
    .from('rooms')
    .select('id, room_number, floor, monthly_rate')
    .eq('property_id', propertyId)
    .eq('status', 'available')
    .is('archived_at', null)
    .order('room_number')

  return data ?? []
}

export type RevokeInvitationActionState = {
  error?: string
  success?: boolean
}

export async function revokeInvitation(
  _prevState: RevokeInvitationActionState,
  formData: FormData
): Promise<RevokeInvitationActionState> {
  const invitationId = String(formData.get('invitationId') ?? '').trim()
  if (!invitationId) {
    return { error: 'Invitation ID is required.' }
  }

  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  const userId = claims?.claims?.sub
  if (!userId) {
    return { error: 'You must be signed in.' }
  }

  const active = await getActiveMembershipForUser(userId)
  if (!active || (active.role !== 'owner' && active.role !== 'manager')) {
    return { error: 'Not authorized to revoke invitations.' }
  }

  const { data: invitation, error: fetchError } = await supabase
    .from('invitations')
    .select('id, organization_id, property_id, status, email, role')
    .eq('id', invitationId)
    .maybeSingle()

  if (fetchError || !invitation) {
    return { error: 'Invitation not found.' }
  }

  if (active.role === 'owner' && invitation.organization_id !== active.organizationId) {
    return { error: 'Invitation does not belong to your organization.' }
  }

  if (active.role === 'manager') {
    if (!active.propertyId || invitation.property_id !== active.propertyId) {
      return { error: 'Invitation does not belong to your property.' }
    }
  }

  const { error: updateError } = await supabase
    .from('invitations')
    .update({ status: 'revoked' })
    .eq('id', invitationId)
    .eq('status', 'pending')

  if (updateError) {
    return { error: updateError.message }
  }

  await recordAuditEvent(supabase, {
    organizationId: invitation.organization_id,
    propertyId: invitation.property_id,
    eventType: 'invitation_revoked',
    metadata: {
      invitation_id: invitationId,
      email: invitation.email,
      role: invitation.role,
    },
  })

  revalidatePath(`/${active.role}/staff/invite`)
  return { success: true }
}

export async function listPendingInvitations(
  cursor?: string | null
): Promise<PaginatedResult<PendingInvitationRow>> {
  const supabase = await createClient()
  const { data: claims } = await supabase.auth.getClaims()
  const userId = claims?.claims?.sub
  if (!userId) {
    return { data: [], nextCursor: null, hasMore: false }
  }

  const active = await getActiveMembershipForUser(userId)
  if (!active) {
    return { data: [], nextCursor: null, hasMore: false }
  }

  const decoded = cursor ? decodeCursor(cursor) : null
  const cursorFilter = buildCursorFilter(decoded)

  let query = supabase
    .from('invitations')
    .select('id, email, role, status, expires_at, created_at, properties(name)')
    .eq('status', 'pending')
    .gt('expires_at', new Date().toISOString())
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .limit(DEFAULT_PAGE_SIZE + 1)

  if (active.role === 'owner') {
    query = query.eq('organization_id', active.organizationId)
  } else if (active.role === 'manager' && active.propertyId) {
    query = query.eq('property_id', active.propertyId)
  } else {
    return { data: [], nextCursor: null, hasMore: false }
  }

  if (cursorFilter) {
    query = query.or(cursorFilter)
  }

  const { data } = await query
  return toPaginatedResult((data ?? []) as PendingInvitationRow[], DEFAULT_PAGE_SIZE)
}
