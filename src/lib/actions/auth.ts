'use server'

import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { clearRoleCacheInCookies, setRoleCacheInCookies } from '@/lib/role-cache-server'
import { roleDashboardPath, type UserRole } from '@/types'

export type AuthActionState = {
  error?: string
  success?: string
}

export async function signIn(
  _prevState: AuthActionState,
  formData: FormData
): Promise<AuthActionState> {
  const email = formData.get('email') as string
  const password = formData.get('password') as string

  if (!email || !password) {
    return { error: 'Email and password are required.' }
  }

  const supabase = await createClient()
  const { data, error } = await supabase.auth.signInWithPassword({ email, password })

  if (error) {
    return { error: error.message }
  }

  const userId = data.user?.id
  if (!userId) {
    return { error: 'Sign in failed. Please try again.' }
  }

  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('role')
    .eq('id', userId)
    .single()

  if (profileError || !profile?.role) {
    return { error: 'Unable to load your profile. Please contact support.' }
  }

  await setRoleCacheInCookies(userId, profile.role as UserRole)
  redirect(roleDashboardPath(profile.role as UserRole))
}

export async function signOut(): Promise<void> {
  const supabase = await createClient()
  await supabase.auth.signOut()
  await clearRoleCacheInCookies()
  redirect('/auth/login')
}

export async function resetPassword(
  _prevState: AuthActionState,
  formData: FormData
): Promise<AuthActionState> {
  const email = formData.get('email') as string

  if (!email) {
    return { error: 'Email is required.' }
  }

  const supabase = await createClient()
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? 'http://localhost:3000'
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${siteUrl}/auth/callback?next=/auth/login`,
  })

  if (error) {
    return { error: error.message }
  }

  return {
    success: 'If an account exists for that email, a reset link has been sent.',
  }
}
