'use server'

import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import {
  clearActiveMembershipInCookies,
  setActiveMembershipInCookies,
} from '@/lib/membership/cookie-server'
import { membershipDashboardPath } from '@/lib/membership/paths'
import {
  loadActiveMemberships,
  toActiveMembership,
  validateMembershipById,
} from '@/lib/membership/queries'
import type { ActiveMembership } from '@/lib/membership/types'

export async function selectMembership(formData: FormData): Promise<void> {
  const membershipId = String(formData.get('membershipId') ?? '').trim()
  if (!membershipId) {
    redirect('/select-membership?error=invalid')
  }
  await switchActiveMembership(membershipId)
}

export async function switchActiveMembership(membershipId: string): Promise<void> {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const userId = data?.claims?.sub

  if (!userId) {
    redirect('/auth/login')
  }

  const membership = await validateMembershipById(supabase, membershipId, userId)
  if (!membership) {
    redirect('/select-membership?error=invalid')
  }

  await setActiveMembershipInCookies(membership)
  redirect(membershipDashboardPath(membership.role))
}

export async function resolvePostAuthRedirect(userId: string): Promise<string> {
  const supabase = await createClient()
  const memberships = await loadActiveMemberships(supabase, userId)

  if (memberships.length === 0) {
    return '/auth/register'
  }

  if (memberships.length === 1) {
    await setActiveMembershipInCookies(toActiveMembership(memberships[0]))
    return membershipDashboardPath(memberships[0].role)
  }

  return '/select-membership'
}

export async function getActiveMembershipForUser(
  userId: string
): Promise<ActiveMembership | null> {
  const supabase = await createClient()
  const { getActiveMembershipFromCookies } = await import('@/lib/membership/cookie-server')
  const cached = await getActiveMembershipFromCookies()

  if (!cached || cached.userId !== userId) {
    return null
  }

  return validateMembershipById(supabase, cached.membershipId, userId)
}

export async function clearMembershipSession(): Promise<void> {
  await clearActiveMembershipInCookies()
}
