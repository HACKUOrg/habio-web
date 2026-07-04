import { NextResponse, type NextRequest } from 'next/server'
import { cookies } from 'next/headers'
import { createClient } from '@/lib/supabase/server'

export async function GET(request: NextRequest) {
  const { searchParams } = request.nextUrl
  const code = searchParams.get('code')
  const stateParam = searchParams.get('state')

  if (!code || !stateParam) {
    return NextResponse.redirect(new URL('/select-membership?error=line_callback', request.url))
  }

  // Parse state and verify CSRF nonce
  let role = 'owner'
  try {
    const stateData = JSON.parse(atob(stateParam)) as { nonce: string; role: string }
    const cookieStore = await cookies()
    const storedNonce = cookieStore.get('line-oauth-state')?.value
    if (!storedNonce || stateData.nonce !== storedNonce) {
      return NextResponse.redirect(new URL('/select-membership?error=csrf', request.url))
    }
    role = stateData.role
    cookieStore.delete('line-oauth-state')
  } catch {
    return NextResponse.redirect(new URL('/select-membership?error=state', request.url))
  }

  // Exchange auth code for access token
  const callbackUrl = `${process.env.NEXT_PUBLIC_SITE_URL}/api/line/callback`
  const tokenRes = await fetch('https://api.line.me/oauth2/v2.1/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      redirect_uri: callbackUrl,
      client_id: process.env.LINE_LOGIN_CHANNEL_ID!,
      client_secret: process.env.LINE_LOGIN_CHANNEL_SECRET!,
    }),
  })

  if (!tokenRes.ok) {
    return NextResponse.redirect(
      new URL(`/${role}/account/link-line?error=token`, request.url)
    )
  }

  const { access_token } = (await tokenRes.json()) as { access_token: string }

  // Fetch LINE profile to get the stable LINE userId
  const profileRes = await fetch('https://api.line.me/v2/profile', {
    headers: { Authorization: `Bearer ${access_token}` },
  })

  if (!profileRes.ok) {
    return NextResponse.redirect(
      new URL(`/${role}/account/link-line?error=profile`, request.url)
    )
  }

  const { userId: lineUserId } = (await profileRes.json()) as { userId: string }

  // Resolve authenticated Supabase user
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) {
    return NextResponse.redirect(new URL('/auth/login', request.url))
  }

  // Upsert LINE identity (conflict on user_id + provider unique constraint)
  const now = new Date().toISOString()
  const { error } = await supabase.from('user_identities').upsert(
    {
      user_id: user.id,
      provider: 'line',
      provider_user_id: lineUserId,
      linked_at: now,
      updated_at: now,
    },
    { onConflict: 'user_id,provider' }
  )

  if (error) {
    return NextResponse.redirect(
      new URL(`/${role}/account/link-line?error=db`, request.url)
    )
  }

  return NextResponse.redirect(
    new URL(`/${role}/account/link-line?linked=1`, request.url)
  )
}
