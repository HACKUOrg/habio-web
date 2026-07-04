'use server'

import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveMembershipFromCookies } from '@/lib/membership/cookie-server'

export async function getLineIdentity() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return null

  const { data } = await supabase
    .from('user_identities')
    .select('provider_user_id, linked_at')
    .eq('user_id', user.id)
    .eq('provider', 'line')
    .maybeSingle()

  return data
}

export async function initiateLineLogin() {
  const membership = await getActiveMembershipFromCookies()
  if (!membership) redirect('/select-membership')

  const nonce = crypto.randomUUID()
  const state = btoa(JSON.stringify({ nonce, role: membership.role }))

  const cookieStore = await cookies()
  cookieStore.set('line-oauth-state', nonce, {
    httpOnly: true,
    sameSite: 'lax',
    maxAge: 300,
    path: '/',
  })

  const callbackUrl = `${process.env.NEXT_PUBLIC_SITE_URL}/api/line/callback`
  const url = new URL('https://access.line.me/oauth2/v2.1/authorize')
  url.searchParams.set('response_type', 'code')
  url.searchParams.set('client_id', process.env.LINE_LOGIN_CHANNEL_ID!)
  url.searchParams.set('redirect_uri', callbackUrl)
  url.searchParams.set('state', state)
  url.searchParams.set('scope', 'profile openid')

  redirect(url.toString())
}

export async function unlinkLineIdentity() {
  const membership = await getActiveMembershipFromCookies()
  if (!membership) redirect('/select-membership')

  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) redirect('/auth/login')

  await supabase
    .from('user_identities')
    .delete()
    .eq('user_id', user.id)
    .eq('provider', 'line')

  redirect(`/${membership.role}/account/link-line?unlinked=1`)
}
