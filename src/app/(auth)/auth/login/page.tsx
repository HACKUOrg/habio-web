import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getActiveMembershipForUser } from '@/lib/actions/membership'
import { membershipDashboardPath } from '@/lib/membership/paths'
import { LoginForm } from '@/components/auth/login-form'

export default async function LoginPage() {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const userId = data?.claims?.sub

  if (userId) {
    const activeMembership = await getActiveMembershipForUser(userId)
    if (activeMembership) {
      redirect(membershipDashboardPath(activeMembership.role))
    }
    redirect('/select-membership')
  }

  return (
    <div className="flex min-h-full flex-1 items-center justify-center p-6">
      <LoginForm />
    </div>
  )
}
