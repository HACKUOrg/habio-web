'use client'

import { useActionState, useState } from 'react'
import {
  createTenantActivation,
  type InvitationActionState,
} from '@/lib/actions/staff-invitations'
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

interface RoomOption {
  id: string
  room_number: string
  floor: number
  monthly_rate: number
}

interface CreateTenantFormProps {
  properties: PropertyOption[]
  roomsByProperty: Record<string, RoomOption[]>
  defaultPropertyId?: string | null
}

export function CreateTenantForm({
  properties,
  roomsByProperty,
  defaultPropertyId,
}: CreateTenantFormProps) {
  const [state, formAction, isPending] = useActionState(createTenantActivation, initialState)
  const initialPropertyId = defaultPropertyId ?? properties[0]?.id ?? ''
  const [propertyId, setPropertyId] = useState(initialPropertyId)
  const rooms = roomsByProperty[propertyId] ?? []

  return (
    <Card>
      <CardHeader>
        <CardTitle>Create tenant activation</CardTitle>
        <CardDescription>
          Assign a room and send an activation link for the tenant to set their password.
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
              <p className="font-medium">Activation link created</p>
              <p className="mt-1 break-all text-muted-foreground">{state.inviteUrl}</p>
              <p className="mt-2 text-xs text-muted-foreground">
                Share this link with the tenant. Email delivery is not configured yet.
              </p>
            </div>
          )}
          <div className="space-y-2">
            <Label htmlFor="email">Tenant email</Label>
            <Input id="email" name="email" type="email" required autoComplete="off" />
          </div>
          {properties.length > 1 ? (
            <div className="space-y-2">
              <Label htmlFor="propertyId">Property</Label>
              <select
                id="propertyId"
                name="propertyId"
                required
                value={propertyId}
                onChange={(e) => setPropertyId(e.target.value)}
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
            <input type="hidden" name="propertyId" value={propertyId} />
          )}
          <div className="space-y-2">
            <Label htmlFor="roomId">Room</Label>
            <select
              id="roomId"
              name="roomId"
              required
              defaultValue=""
              className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-xs outline-none focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50"
            >
              <option value="" disabled>
                {rooms.length === 0 ? 'No available rooms' : 'Select a room'}
              </option>
              {rooms.map((room) => (
                <option key={room.id} value={room.id}>
                  {room.room_number} (floor {room.floor}) — ฿{room.monthly_rate}/mo
                </option>
              ))}
            </select>
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <div className="space-y-2">
              <Label htmlFor="leaseStart">Lease start</Label>
              <Input id="leaseStart" name="leaseStart" type="date" required />
            </div>
            <div className="space-y-2">
              <Label htmlFor="leaseEnd">Lease end (optional)</Label>
              <Input id="leaseEnd" name="leaseEnd" type="date" />
            </div>
          </div>
        </CardContent>
        <CardFooter>
          <Button type="submit" disabled={isPending || rooms.length === 0}>
            {isPending ? 'Creating activation…' : 'Create activation link'}
          </Button>
        </CardFooter>
      </form>
    </Card>
  )
}
