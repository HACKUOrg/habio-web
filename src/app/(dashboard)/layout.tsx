import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveMembershipForUser } from '@/lib/actions/membership'
import { loadActiveMemberships } from '@/lib/membership/queries'
import { Sidebar } from '@/components/layout/sidebar'
import { Topnav } from '@/components/layout/topnav'
import type { MembershipWithContext } from '@/types'

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const userId = data?.claims?.sub

  if (!userId) {
    redirect('/auth/login')
  }

  const activeMembership = await getActiveMembershipForUser(userId)
  if (!activeMembership) {
    redirect('/select-membership')
  }

  const { data: profile } = await supabase
    .from('profiles')
    .select('full_name')
    .eq('id', userId)
    .single()

  const memberships = await loadActiveMemberships(supabase, userId)
  const activeContext =
    memberships.find((m) => m.membershipId === activeMembership.membershipId) ??
    ({
      ...activeMembership,
      organizationName: 'Organization',
      propertyName: null,
    } satisfies MembershipWithContext)

  return (
    <div className="flex min-h-full flex-1">
      <Sidebar role={activeMembership.role} />
      <div className="flex flex-1 flex-col">
        <Topnav
          fullName={profile?.full_name ?? 'User'}
          membership={activeContext}
          hasMultipleMemberships={memberships.length > 1}
        />
        <main className="flex-1 p-6">{children}</main>
      </div>
    </div>
  )
}
