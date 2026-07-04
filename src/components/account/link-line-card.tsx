import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import {
  getLineIdentity,
  initiateLineLogin,
  unlinkLineIdentity,
} from '@/lib/actions/identity'

interface LinkLineCardProps {
  linked?: boolean
  unlinked?: boolean
  error?: string
}

const errorMessages: Record<string, string> = {
  token: 'Could not complete LINE login. Please try again.',
  profile: 'Could not read your LINE profile. Please try again.',
  db: 'Could not link your LINE account. It may already be linked to another user.',
  csrf: 'LINE login session expired. Please try again.',
  state: 'Invalid LINE login state. Please try again.',
}

export async function LinkLineCard({ linked, unlinked, error }: LinkLineCardProps) {
  const identity = await getLineIdentity()
  const isLinked = Boolean(identity)

  return (
    <Card className="max-w-md">
      <CardHeader>
        <CardTitle>LINE Account</CardTitle>
        <CardDescription>
          {isLinked
            ? 'Your LINE account is connected. You will receive notifications via LINE.'
            : 'Connect your LINE account to receive notifications via LINE.'}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        {linked && (
          <p className="text-sm text-green-600 dark:text-green-400">
            LINE account linked successfully.
          </p>
        )}
        {unlinked && (
          <p className="text-sm text-muted-foreground">LINE account unlinked.</p>
        )}
        {error && (
          <p className="text-sm text-destructive" role="alert">
            {errorMessages[error] ?? 'Something went wrong. Please try again.'}
          </p>
        )}
        {isLinked && identity && (
          <p className="text-xs text-muted-foreground">
            Linked {new Date(identity.linked_at).toLocaleDateString()}
          </p>
        )}
        {isLinked ? (
          <form action={unlinkLineIdentity}>
            <Button type="submit" variant="destructive" size="sm">
              Unlink LINE
            </Button>
          </form>
        ) : (
          <form action={initiateLineLogin}>
            <Button type="submit" size="sm">
              Link LINE Account
            </Button>
          </form>
        )}
      </CardContent>
    </Card>
  )
}
