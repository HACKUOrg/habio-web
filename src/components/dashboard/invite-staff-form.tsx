'use client'

import { useActionState } from 'react'
import {
  createStaffInvitation,
  type InvitationActionState,
} from '@/lib/actions/staff-invitations'
import { MEMBERSHIP_ROLE_LABELS, type MembershipRole } from '@/types'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'

const initialState: InvitationActionState = {}

interface PropertyOption {
  id: string
  name: string
}

interface InviteStaffFormProps {
  properties: PropertyOption[]
  allowedRoles: Array<'manager' | 'technician' | 'housekeeper'>
  defaultPropertyId?: string | null
}

export function InviteStaffForm({
  properties,
  allowedRoles,
  defaultPropertyId,
}: InviteStaffFormProps) {
  const [state, formAction, isPending] = useActionState(createStaffInvitation, initialState)

  return (
    <Card>
      <CardHeader>
        <CardTitle>Invite staff member</CardTitle>
        <CardDescription>
          Send an invitation link. The invitee will create a password to join.
        </CardDescription>
      </CardHeader>
      <form action={formAction}>
        <CardContent className="space-y-4">
          {state.error && (
            <p className="text-sm text-destructive" role="alert">
              {state.error}
            </p>
          )}
          {state.inviteUrl && (
            <div className="rounded-md border bg-muted/50 p-3 text-sm">
              <p className="font-medium">Invitation created</p>
              <p className="mt-1 break-all text-muted-foreground">{state.inviteUrl}</p>
              <p className="mt-2 text-xs text-muted-foreground">
                Share this link with the invitee. Email delivery is not configured yet.
              </p>
            </div>
          )}
          <div className="space-y-2">
            <Label htmlFor="email">Email</Label>
            <Input id="email" name="email" type="email" required autoComplete="off" />
          </div>
          <div className="space-y-2">
            <Label htmlFor="role">Role</Label>
            <select
              id="role"
              name="role"
              required
              defaultValue={allowedRoles[0]}
              className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-xs outline-none focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50"
            >
              {allowedRoles.map((role) => (
                <option key={role} value={role}>
                  {MEMBERSHIP_ROLE_LABELS[role as MembershipRole]}
                </option>
              ))}
            </select>
          </div>
          {properties.length > 1 ? (
            <div className="space-y-2">
              <Label htmlFor="propertyId">Property</Label>
              <select
                id="propertyId"
                name="propertyId"
                required
                defaultValue={defaultPropertyId ?? properties[0]?.id}
                className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-xs outline-none focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50"
              >
                {properties.map((property) => (
                  <option key={property.id} value={property.id}>
                    {property.name}
                  </option>
                ))}
              </select>
            </div>
          ) : (
            <input
              type="hidden"
              name="propertyId"
              value={properties[0]?.id ?? defaultPropertyId ?? ''}
            />
          )}
        </CardContent>
        <CardFooter>
          <Button type="submit" disabled={isPending || properties.length === 0}>
            {isPending ? 'Creating invitation…' : 'Create invitation'}
          </Button>
        </CardFooter>
      </form>
    </Card>
  )
}
