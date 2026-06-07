'use server'

import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { setActiveMembershipInCookies } from '@/lib/membership/cookie-server'
import { membershipDashboardPath } from '@/lib/membership/paths'
import type { MembershipRole } from '@/types'

export type InvitationActionState = {
  error?: string
}

interface InvitationPreview {
  id: string
  email: string
  role: MembershipRole
  organization_id: string
  property_id: string
  expires_at: string
}

interface AcceptInvitationResult {
  membership_id: string
  organization_id: string
  property_id: string | null
  role: MembershipRole
}

export async function getInvitationPreview(token: string): Promise<InvitationPreview | null> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_invitation_preview', {
    p_token: token,
  })

  if (error || !data || typeof data !== 'object' || Array.isArray(data)) return null
  return data as unknown as InvitationPreview
}

export async function acceptInvitation(
  _prevState: InvitationActionState,
  formData: FormData
): Promise<InvitationActionState> {
  const token = String(formData.get('token') ?? '').trim()
  const password = String(formData.get('password') ?? '')
  const email = String(formData.get('email') ?? '').trim()

  if (!token) {
    return { error: 'Invitation token is missing.' }
  }

  const supabase = await createClient()
  const { data: claimsData } = await supabase.auth.getClaims()
  let userId = claimsData?.claims?.sub

  if (!userId) {
    if (!email || !password) {
      return { error: 'Email and password are required to accept this invitation.' }
    }

    const { data: signInData, error: signInError } = await supabase.auth.signInWithPassword({
      email,
      password,
    })

    if (signInError) {
      const { data: signUpData, error: signUpError } = await supabase.auth.signUp({
        email,
        password,
      })

      if (signUpError) {
        return { error: signUpError.message }
      }

      userId = signUpData.user?.id
    } else {
      userId = signInData.user?.id
    }

    if (!userId) {
      return { error: 'Unable to authenticate. Please try again.' }
    }
  }

  const { data: acceptResult, error: acceptError } = await supabase.rpc('accept_invitation', {
    p_token: token,
  })

  if (acceptError || !acceptResult) {
    return { error: acceptError?.message ?? 'Unable to accept invitation.' }
  }

  const result = acceptResult as unknown as AcceptInvitationResult

  await setActiveMembershipInCookies({
    membershipId: result.membership_id,
    userId,
    role: result.role,
    organizationId: result.organization_id,
    propertyId: result.property_id,
  })

  redirect(membershipDashboardPath(result.role))
}
