'use client'

import { useActionState } from 'react'
import { completeOwnerOnboarding, type OnboardingActionState } from '@/lib/actions/onboarding'
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

export function CompleteOnboardingForm() {
  const [state, formAction, isPending] = useActionState(completeOwnerOnboarding, initialState)

  return (
    <Card className="w-full max-w-md">
      <CardHeader>
        <CardTitle>Finish setting up your organization</CardTitle>
        <CardDescription>
          Your account exists but no organization was created yet. Complete setup to continue.
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
        <CardFooter>
          <Button type="submit" className="w-full" disabled={isPending}>
            {isPending ? 'Creating organization…' : 'Continue'}
          </Button>
        </CardFooter>
      </form>
    </Card>
  )
}
