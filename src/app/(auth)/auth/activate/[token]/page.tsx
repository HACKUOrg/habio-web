import Link from 'next/link'
import { getTenantActivationPreview } from '@/lib/actions/tenant-activation'
import { TenantActivationForm } from '@/components/auth/tenant-activation-form'
import {
  Card,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'

export default async function TenantActivatePage({
  params,
}: {
  params: Promise<{ token: string }>
}) {
  const { token } = await params
  const activation = await getTenantActivationPreview(token)

  if (!activation) {
    return (
      <div className="flex min-h-full flex-1 items-center justify-center p-6">
        <Card className="w-full max-w-md">
          <CardHeader>
            <CardTitle>Activation link unavailable</CardTitle>
            <CardDescription>
              This activation link is invalid or has expired. Contact your property manager
              for a new link.
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
      <TenantActivationForm
        token={token}
        email={activation.email}
        propertyName={activation.property_name}
        roomNumber={activation.room_number}
        leaseStart={activation.lease_start}
        leaseEnd={activation.lease_end}
      />
    </div>
  )
}
