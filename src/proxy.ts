import { NextResponse, type NextRequest } from 'next/server'
import {
  parseActiveMembershipCookie,
  setActiveMembershipCookie,
} from '@/lib/membership/cookie'
import { membershipDashboardPath, roleFromPath } from '@/lib/membership/paths'
import { validateMembershipById } from '@/lib/membership/queries'
import { updateSession } from '@/lib/supabase/middleware'

const MEMBERSHIP_EXEMPT_PATHS = ['/select-membership']

export async function proxy(request: NextRequest) {
  const { response, supabase, userId } = await updateSession(request)
  const path = request.nextUrl.pathname

  if (!userId) {
    return NextResponse.redirect(new URL('/auth/login', request.url))
  }

  if (MEMBERSHIP_EXEMPT_PATHS.some((prefix) => path === prefix || path.startsWith(`${prefix}/`))) {
    return response
  }

  const activeCookie = await parseActiveMembershipCookie(request)
  if (!activeCookie || activeCookie.userId !== userId) {
    return NextResponse.redirect(new URL('/select-membership', request.url))
  }

  const validMembership = await validateMembershipById(
    supabase,
    activeCookie.membershipId,
    userId
  )

  if (!validMembership) {
    const redirectResponse = NextResponse.redirect(
      new URL('/select-membership', request.url)
    )
    return redirectResponse
  }

  if (
    validMembership.role !== activeCookie.role ||
    validMembership.organizationId !== activeCookie.organizationId ||
    validMembership.propertyId !== activeCookie.propertyId
  ) {
    await setActiveMembershipCookie(response, validMembership)
  }

  const requestedRole = roleFromPath(path)
  if (requestedRole && requestedRole !== validMembership.role) {
    return NextResponse.redirect(
      new URL(membershipDashboardPath(validMembership.role), request.url)
    )
  }

  if (path === '/') {
    return NextResponse.redirect(
      new URL(membershipDashboardPath(validMembership.role), request.url)
    )
  }

  return response
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|auth|api/webhooks).*)'],
}
