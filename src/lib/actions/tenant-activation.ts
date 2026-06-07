'use server'

import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { setActiveMembershipInCookies } from '@/lib/membership/cookie-server'
import { membershipDashboardPath } from '@/lib/membership/paths'
import type { MembershipRole } from '@/types'

export type TenantActivationActionState = {
  error?: string
}

interface TenantActivationPreview {
  id: string
  email: string
  organization_id: string
  property_id: string
  property_name: string
  room_id: string
  room_number: string
  lease_start: string
  lease_end: string | null
  expires_at: string
}

interface AcceptTenantActivationResult {
  membership_id: string
  tenant_profile_id: string
  organization_id: string
  property_id: string
  role: MembershipRole
}

export async function getTenantActivationPreview(
  token: string
): Promise<TenantActivationPreview | null> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('get_tenant_activation_preview', {
    p_token: token,
  })

  if (error || !data || typeof data !== 'object' || Array.isArray(data)) return null
  return data as unknown as TenantActivationPreview
}

export async function acceptTenantActivation(
  _prevState: TenantActivationActionState,
  formData: FormData
): Promise<TenantActivationActionState> {
  const token = String(formData.get('token') ?? '').trim()
  const password = String(formData.get('password') ?? '')
  const email = String(formData.get('email') ?? '').trim()

  if (!token) {
    return { error: 'Activation token is missing.' }
  }

  const supabase = await createClient()
  const { data: claimsData } = await supabase.auth.getClaims()
  let userId = claimsData?.claims?.sub

  if (!userId) {
    if (!email || !password) {
      return { error: 'Email and password are required to activate your account.' }
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

  const { data: acceptResult, error: acceptError } = await supabase.rpc('accept_tenant_activation', {
    p_token: token,
  })

  if (acceptError || !acceptResult) {
    return { error: acceptError?.message ?? 'Unable to complete activation.' }
  }

  const result = acceptResult as unknown as AcceptTenantActivationResult

  await setActiveMembershipInCookies({
    membershipId: result.membership_id,
    userId,
    role: result.role,
    organizationId: result.organization_id,
    propertyId: result.property_id,
  })

  redirect(membershipDashboardPath(result.role))
}
