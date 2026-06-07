import { redirect } from 'next/navigation'
import { PageHeader } from '@/components/layout/page-header'
import { CreateTenantForm } from '@/components/dashboard/create-tenant-form'
import { getInvitableProperties, getAvailableRooms } from '@/lib/actions/staff-invitations'
import { getActiveMembershipForUser } from '@/lib/actions/membership'
import { createClient } from '@/lib/supabase/server'

export default async function ManagerCreateTenantPage() {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const userId = data?.claims?.sub
  if (!userId) redirect('/auth/login')

  const active = await getActiveMembershipForUser(userId)
  if (!active || (active.role !== 'manager' && active.role !== 'owner')) {
    redirect('/select-membership')
  }

  const properties = await getInvitableProperties()
  const roomsByProperty: Record<
    string,
    Awaited<ReturnType<typeof getAvailableRooms>>
  > = {}

  for (const property of properties) {
    roomsByProperty[property.id] = await getAvailableRooms(property.id)
  }

  return (
    <>
      <PageHeader
        title="Add tenant"
        description="Create a tenant activation link with room and lease details."
      />
      <div className="max-w-xl">
        <CreateTenantForm
          properties={properties}
          roomsByProperty={roomsByProperty}
          defaultPropertyId={active.propertyId}
        />
      </div>
    </>
  )
}
