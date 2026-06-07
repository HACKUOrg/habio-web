import Link from 'next/link'
import { getInvitationPreview } from '@/lib/actions/invitations'
import { InviteAcceptForm } from '@/components/auth/invite-accept-form'
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'

export default async function InvitePage({
  params,
}: {
  params: Promise<{ token: string }>
}) {
  const { token } = await params
  const invitation = await getInvitationPreview(token)

  if (!invitation) {
    return (
      <div className="flex min-h-full flex-1 items-center justify-center p-6">
        <Card className="w-full max-w-md">
          <CardHeader>
            <CardTitle>Invitation unavailable</CardTitle>
            <CardDescription>
              This invitation link is invalid or has expired. Ask your organization admin to
              send a new invitation.
            </CardDescription>
          </CardHeader>
          <p className="px-6 pb-6 text-center text-sm">
            <Link href="/auth/login" className="text-muted-foreground hover:text-foreground">
              Back to sign in
            </Link>
          </p>
        </Card>
      </div>
    )
  }

  return (
    <div className="flex min-h-full flex-1 items-center justify-center p-6">
      <InviteAcceptForm token={token} email={invitation.email} role={invitation.role} />
    </div>
  )
}
