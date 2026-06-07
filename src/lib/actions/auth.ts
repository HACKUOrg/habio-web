'use server'

import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import {
  clearMembershipSession,
  resolvePostAuthRedirect,
} from '@/lib/actions/membership'

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

  const destination = await resolvePostAuthRedirect(userId)
  redirect(destination)
}

export async function signOut(): Promise<void> {
  const supabase = await createClient()
  await supabase.auth.signOut()
  await clearMembershipSession()
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
