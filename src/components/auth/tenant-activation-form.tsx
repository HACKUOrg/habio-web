'use client'

import { useActionState } from 'react'
import Link from 'next/link'
import {
  acceptTenantActivation,
  type TenantActivationActionState,
} from '@/lib/actions/tenant-activation'
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

const initialState: TenantActivationActionState = {}

interface TenantActivationFormProps {
  token: string
  email: string
  propertyName: string
  roomNumber: string
  leaseStart: string
  leaseEnd: string | null
}

export function TenantActivationForm({
  token,
  email,
  propertyName,
  roomNumber,
  leaseStart,
  leaseEnd,
}: TenantActivationFormProps) {
  const [state, formAction, isPending] = useActionState(acceptTenantActivation, initialState)

  return (
    <Card className="w-full max-w-md">
      <CardHeader>
        <CardTitle>Activate your tenant account</CardTitle>
        <CardDescription>
          You have been assigned to room {roomNumber} at {propertyName}. Lease starts{' '}
          {leaseStart}
          {leaseEnd ? ` and ends ${leaseEnd}` : ''}.
        </CardDescription>
      </CardHeader>
      <form action={formAction}>
        <input type="hidden" name="token" value={token} />
        <CardContent className="space-y-4">
          {state.error && (
            <p className="text-sm text-destructive" role="alert">
              {state.error}
            </p>
          )}
          <div className="space-y-2">
            <Label htmlFor="email">Email</Label>
            <Input
              id="email"
              name="email"
              type="email"
              defaultValue={email}
              required
              autoComplete="email"
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="password">Create password</Label>
            <Input
              id="password"
              name="password"
              type="password"
              required
              autoComplete="new-password"
              minLength={8}
            />
          </div>
        </CardContent>
        <CardFooter className="flex flex-col gap-4">
          <Button type="submit" className="w-full" disabled={isPending}>
            {isPending ? 'Activating…' : 'Activate account'}
          </Button>
          <Link
            href="/auth/login"
            className="text-sm text-muted-foreground hover:text-foreground"
          >
            Already have an account? Sign in first
          </Link>
        </CardFooter>
      </form>
    </Card>
  )
}
