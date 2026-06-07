'use client'

import { useActionState } from 'react'
import Link from 'next/link'
import {
  createProperty,
  updateProperty,
  type PropertyActionState,
} from '@/lib/actions/properties'
import type { PropertyRow } from '@/types'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Card,
  CardContent,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'

const createInitial: PropertyActionState = {}
const updateInitial: PropertyActionState = {}

interface PropertyFormProps {
  property?: PropertyRow
}

export function PropertyForm({ property }: PropertyFormProps) {
  const isEdit = Boolean(property)
  const [state, formAction, isPending] = useActionState(
    isEdit ? updateProperty : createProperty,
    isEdit ? updateInitial : createInitial
  )

  return (
    <Card>
      <CardHeader>
        <CardTitle>{isEdit ? 'Edit property' : 'New property'}</CardTitle>
      </CardHeader>
      <form action={formAction}>
        {isEdit && <input type="hidden" name="propertyId" value={property!.id} />}
        <CardContent className="space-y-4">
          {state.error && (
            <p className="text-sm text-destructive" role="alert">
              {state.error}
            </p>
          )}
          <div className="space-y-2">
            <Label htmlFor="name">Name</Label>
            <Input
              id="name"
              name="name"
              required
              defaultValue={property?.name ?? ''}
              placeholder="Sunrise Dormitory"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="address">Address</Label>
            <Input
              id="address"
              name="address"
              required
              defaultValue={property?.address ?? ''}
              placeholder="123 Main St, Bangkok"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="phone">Phone (optional)</Label>
            <Input
              id="phone"
              name="phone"
              type="tel"
              defaultValue={property?.phone ?? ''}
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="description">Description (optional)</Label>
            <textarea
              id="description"
              name="description"
              rows={3}
              defaultValue={property?.description ?? ''}
              className="flex min-h-[80px] w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-xs outline-none focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50"
            />
          </div>
          {isEdit && (
            <div className="space-y-2">
              <Label htmlFor="status">Status</Label>
              <select
                id="status"
                name="status"
                defaultValue={property?.status ?? 'active'}
                className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-xs outline-none focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50"
              >
                <option value="active">Active</option>
                <option value="inactive">Inactive</option>
                <option value="archived">Archived</option>
              </select>
            </div>
          )}
        </CardContent>
        <CardFooter className="flex gap-3">
          <Button type="submit" disabled={isPending}>
            {isPending ? 'Saving…' : isEdit ? 'Save changes' : 'Create property'}
          </Button>
          <Button variant="outline" asChild>
            <Link href="/owner/properties">Cancel</Link>
          </Button>
        </CardFooter>
      </form>
    </Card>
  )
}
