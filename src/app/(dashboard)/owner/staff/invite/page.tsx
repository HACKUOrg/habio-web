import { redirect } from 'next/navigation'
import { PageHeader } from '@/components/layout/page-header'
import { InviteStaffForm } from '@/components/dashboard/invite-staff-form'
import {
  getInvitableProperties,
  listPendingInvitations,
  revokeInvitation,
} from '@/lib/actions/staff-invitations'
import { invitableRolesForMembership } from '@/lib/invitations/roles'
import { getActiveMembershipForUser } from '@/lib/actions/membership'
import { createClient } from '@/lib/supabase/server'
import { MEMBERSHIP_ROLE_LABELS } from '@/types'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Button } from '@/components/ui/button'

export default async function OwnerInviteStaffPage() {
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const userId = data?.claims?.sub
  if (!userId) redirect('/auth/login')

  const active = await getActiveMembershipForUser(userId)
  if (!active || active.role !== 'owner') redirect('/select-membership')

  const properties = await getInvitableProperties()
  const allowedRoles = invitableRolesForMembership('owner')
  const { data: pending } = await listPendingInvitations()

  return (
    <>
      <PageHeader
        title="Invite staff"
        description="Invite managers, technicians, and housekeepers to your organization."
      />
      <div className="grid gap-6 lg:grid-cols-2">
        <InviteStaffForm properties={properties} allowedRoles={allowedRoles} />
        <Card>
          <CardHeader>
            <CardTitle>Pending invitations</CardTitle>
            <CardDescription>Active invitation links awaiting acceptance.</CardDescription>
          </CardHeader>
          <CardContent>
            {pending.length === 0 ? (
              <p className="text-sm text-muted-foreground">No pending invitations.</p>
            ) : (
              <ul className="space-y-3">
                {pending.map((inv) => (
                  <li key={inv.id} className="flex items-center justify-between gap-2 text-sm">
                    <span>
                      <span className="font-medium">{inv.email}</span>
                      <span className="text-muted-foreground">
                        {' '}
                        — {MEMBERSHIP_ROLE_LABELS[inv.role]}
                        {inv.properties?.name ? ` @ ${inv.properties.name}` : ''}
                      </span>
                    </span>
                    <form action={revokeInvitation}>
                      <input type="hidden" name="invitationId" value={inv.id} />
                      <Button type="submit" variant="destructive" size="sm">
                        Revoke
                      </Button>
                    </form>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>
    </>
  )
}
