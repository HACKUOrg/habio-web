'use server'

import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { recordAuditEvent } from '@/lib/audit/record'
import { setActiveMembershipInCookies } from '@/lib/membership/cookie-server'
import { membershipDashboardPath } from '@/lib/membership/paths'
import type { MembershipRole } from '@/types'

export type OnboardingActionState = {
  error?: string
}

interface OwnerOrganizationResult {
  organization_id: string
  property_id: string
  membership_id: string
}

export async function registerOwner(
  _prevState: OnboardingActionState,
  formData: FormData
): Promise<OnboardingActionState> {
  const email = String(formData.get('email') ?? '').trim()
  const password = String(formData.get('password') ?? '')
  const fullName = String(formData.get('fullName') ?? '').trim()
  const orgName = String(formData.get('orgName') ?? '').trim()
  const propertyName = String(formData.get('propertyName') ?? '').trim()
  const propertyAddress = String(formData.get('propertyAddress') ?? '').trim()

  if (!email || !password || !fullName || !orgName || !propertyName) {
    return { error: 'All required fields must be filled in.' }
  }

  const supabase = await createClient()
  const { data: signUpData, error: signUpError } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: { full_name: fullName },
    },
  })

  if (signUpError) {
    return { error: signUpError.message }
  }

  const userId = signUpData.user?.id
  if (!userId) {
    return { error: 'Registration failed. Please try again.' }
  }

  const { data: orgResult, error: orgError } = await supabase.rpc('create_owner_organization', {
    p_org_name: orgName,
    p_property_name: propertyName,
    p_property_address: propertyAddress || undefined,
  })

  if (orgError || !orgResult) {
    return {
      error:
        orgError?.message ??
        'Account created but organization setup failed. Sign in and contact support.',
    }
  }

  const result = orgResult as unknown as OwnerOrganizationResult

  await recordAuditEvent(supabase, {
    organizationId: result.organization_id,
    propertyId: result.property_id,
    eventType: 'org_created',
    metadata: { org_name: orgName, property_name: propertyName },
  })

  await setActiveMembershipInCookies({
    membershipId: result.membership_id,
    userId,
    role: 'owner' satisfies MembershipRole,
    organizationId: result.organization_id,
    propertyId: null,
  })

  redirect(membershipDashboardPath('owner'))
}

export async function completeOwnerOnboarding(
  _prevState: OnboardingActionState,
  formData: FormData
): Promise<OnboardingActionState> {
  const orgName = String(formData.get('orgName') ?? '').trim()
  const propertyName = String(formData.get('propertyName') ?? '').trim()
  const propertyAddress = String(formData.get('propertyAddress') ?? '').trim()

  if (!orgName || !propertyName) {
    return { error: 'Organization and property names are required.' }
  }

  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const userId = data?.claims?.sub

  if (!userId) {
    redirect('/auth/login')
  }

  const { data: orgResult, error: orgError } = await supabase.rpc('create_owner_organization', {
    p_org_name: orgName,
    p_property_name: propertyName,
    p_property_address: propertyAddress || undefined,
  })

  if (orgError || !orgResult) {
    return { error: orgError?.message ?? 'Unable to create organization.' }
  }

  const result = orgResult as unknown as OwnerOrganizationResult

  await recordAuditEvent(supabase, {
    organizationId: result.organization_id,
    propertyId: result.property_id,
    eventType: 'org_created',
    metadata: { org_name: orgName, property_name: propertyName },
  })

  await setActiveMembershipInCookies({
    membershipId: result.membership_id,
    userId,
    role: 'owner',
    organizationId: result.organization_id,
    propertyId: null,
  })

  redirect(membershipDashboardPath('owner'))
}
