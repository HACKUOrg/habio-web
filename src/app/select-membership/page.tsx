import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { selectMembership } from '@/lib/actions/membership'
import { setActiveMembershipInCookies } from '@/lib/membership/cookie-server'
import { membershipDashboardPath } from '@/lib/membership/paths'
import { loadActiveMemberships, toActiveMembership } from '@/lib/membership/queries'
import { MEMBERSHIP_ROLE_LABELS } from '@/types'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'

export default async function SelectMembershipPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>
}) {
  const params = await searchParams
  const supabase = await createClient()
  const { data } = await supabase.auth.getClaims()
  const userId = data?.claims?.sub

  if (!userId) {
    redirect('/auth/login')
  }

  const memberships = await loadActiveMemberships(supabase, userId)

  if (memberships.length === 0) {
    redirect('/auth/register')
  }

  if (memberships.length === 1) {
    await setActiveMembershipInCookies(toActiveMembership(memberships[0]))
    redirect(membershipDashboardPath(memberships[0].role))
  }

  return (
    <div className="flex min-h-full flex-1 items-center justify-center p-6">
      <Card className="w-full max-w-lg">
        <CardHeader>
          <CardTitle>Choose your workspace</CardTitle>
          <CardDescription>
            You have access to multiple roles or properties. Select which context to use.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {params.error === 'invalid' && (
            <p className="text-sm text-destructive" role="alert">
              Your previous session expired. Please choose a workspace again.
            </p>
          )}
          {memberships.map((membership) => (
            <form key={membership.membershipId} action={selectMembership}>
              <input type="hidden" name="membershipId" value={membership.membershipId} />
              <Button type="submit" variant="outline" className="h-auto w-full justify-start p-4">
                <div className="text-left">
                  <p className="font-medium">{MEMBERSHIP_ROLE_LABELS[membership.role]}</p>
                  <p className="text-sm text-muted-foreground">{membership.organizationName}</p>
                  {membership.propertyName && (
                    <p className="text-sm text-muted-foreground">{membership.propertyName}</p>
                  )}
                </div>
              </Button>
            </form>
          ))}
          <p className="pt-2 text-center text-sm text-muted-foreground">
            <Link href="/auth/login" className="hover:text-foreground">
              Sign in with a different account
            </Link>
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
