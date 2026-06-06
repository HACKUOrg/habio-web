import { NextResponse, type NextRequest } from 'next/server'
import { getRoleFromCache, setRoleCacheCookie } from '@/lib/role-cache'
import { updateSession } from '@/lib/supabase/middleware'
import { ROLE_ROUTES, roleDashboardPath, type UserRole } from '@/types'

export async function middleware(request: NextRequest) {
  const { response, supabase, userId } = await updateSession(request)
  const path = request.nextUrl.pathname

  if (!userId) {
    return NextResponse.redirect(new URL('/auth/login', request.url))
  }

  let role: UserRole | null = await getRoleFromCache(request, userId)

  if (!role) {
    const { data: profile } = await supabase
      .from('profiles')
      .select('role')
      .eq('id', userId)
      .single()

    const fetchedRole = profile?.role as UserRole | undefined
    if (!fetchedRole) {
      return NextResponse.redirect(new URL('/auth/login', request.url))
    }

    role = fetchedRole
    await setRoleCacheCookie(response, userId, role)
  }

  const requestedRole = ROLE_ROUTES.find((r) => path.startsWith(`/${r}`))
  if (requestedRole && requestedRole !== role) {
    return NextResponse.redirect(new URL(roleDashboardPath(role), request.url))
  }

  if (path === '/') {
    return NextResponse.redirect(new URL(roleDashboardPath(role), request.url))
  }

  return response
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|auth|api/webhooks).*)'],
}
