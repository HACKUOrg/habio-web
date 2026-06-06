import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { Sidebar } from '@/components/layout/sidebar'
import { Topnav } from '@/components/layout/topnav'
import type { UserRole } from '@/types'

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

  const { data: profile } = await supabase
    .from('profiles')
    .select('full_name, role')
    .eq('id', userId)
    .single()

  if (!profile?.role) {
    redirect('/auth/login')
  }

  const role = profile.role as UserRole

  return (
    <div className="flex min-h-full flex-1">
      <Sidebar role={role} />
      <div className="flex flex-1 flex-col">
        <Topnav fullName={profile.full_name} role={role} />
        <main className="flex-1 p-6">{children}</main>
      </div>
    </div>
  )
}
