'use client'

import { useActionState } from 'react'
import Link from 'next/link'
import { registerOwner, type OnboardingActionState } from '@/lib/actions/onboarding'
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

const initialState: OnboardingActionState = {}

export function RegisterForm() {
  const [state, formAction, isPending] = useActionState(registerOwner, initialState)

  return (
    <Card className="w-full max-w-md">
      <CardHeader>
        <CardTitle>Create your organization</CardTitle>
        <CardDescription>
          Register as an owner to set up your organization and first property.
        </CardDescription>
      </CardHeader>
      <form action={formAction}>
        <CardContent className="space-y-4">
          {state.error && (
            <p className="text-sm text-destructive" role="alert">
              {state.error}
            </p>
          )}
          <div className="space-y-2">
            <Label htmlFor="fullName">Full name</Label>
            <Input id="fullName" name="fullName" required autoComplete="name" />
          </div>
          <div className="space-y-2">
            <Label htmlFor="email">Email</Label>
            <Input id="email" name="email" type="email" required autoComplete="email" />
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
          <div className="space-y-2">
            <Label htmlFor="orgName">Organization name</Label>
            <Input id="orgName" name="orgName" required />
          </div>
          <div className="space-y-2">
            <Label htmlFor="propertyName">First property name</Label>
            <Input id="propertyName" name="propertyName" required />
          </div>
          <div className="space-y-2">
            <Label htmlFor="propertyAddress">Property address (optional)</Label>
            <Input id="propertyAddress" name="propertyAddress" />
          </div>
        </CardContent>
        <CardFooter className="flex flex-col gap-4">
          <Button type="submit" className="w-full" disabled={isPending}>
            {isPending ? 'Creating account…' : 'Create account'}
          </Button>
          <Link
            href="/auth/login"
            className="text-sm text-muted-foreground hover:text-foreground"
          >
            Already have an account? Sign in
          </Link>
        </CardFooter>
      </form>
    </Card>
  )
}
