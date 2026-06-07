'use client'

import { useActionState } from 'react'
import Link from 'next/link'
import { acceptInvitation, type InvitationActionState } from '@/lib/actions/invitations'
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

interface InviteAcceptFormProps {
  token: string
  email: string
  role: MembershipRole
}

export function InviteAcceptForm({ token, email, role }: InviteAcceptFormProps) {
  const [state, formAction, isPending] = useActionState(acceptInvitation, initialState)

  return (
    <Card className="w-full max-w-md">
      <CardHeader>
        <CardTitle>Accept invitation</CardTitle>
        <CardDescription>
          You have been invited as a {MEMBERSHIP_ROLE_LABELS[role].toLowerCase()} for{' '}
          <span className="font-medium text-foreground">{email}</span>.
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
            <Label htmlFor="password">Password</Label>
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
            {isPending ? 'Joining…' : 'Accept invitation'}
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
