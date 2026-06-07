import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { loadActiveMemberships } from '@/lib/membership/queries'
import { CompleteOnboardingForm } from '@/components/auth/complete-onboarding-form'
import { RegisterForm } from '@/components/auth/register-form'

export default async function RegisterPage() {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const userId = data?.claims?.sub

  if (userId) {
    const memberships = await loadActiveMemberships(supabase, userId)
    if (memberships.length > 0) {
      redirect('/select-membership')
    }

    return (
      <div className="flex min-h-full flex-1 items-center justify-center p-6">
        <CompleteOnboardingForm />
      </div>
    )
  }

  return (
    <div className="flex min-h-full flex-1 items-center justify-center p-6">
      <RegisterForm />
    </div>
  )
}
