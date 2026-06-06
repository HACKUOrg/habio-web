import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { LoginForm } from '@/components/auth/login-form'
import { roleDashboardPath, type UserRole } from '@/types'

export default async function LoginPage() {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const userId = data?.claims?.sub

  if (userId) {
    const { data: profile } = await supabase
      .from('profiles')
      .select('role')
      .eq('id', userId)
      .single()

    if (profile?.role) {
      redirect(roleDashboardPath(profile.role as UserRole))
    }
  }

  return (
    <div className="flex min-h-full flex-1 items-center justify-center p-6">
      <LoginForm />
    </div>
  )
}
