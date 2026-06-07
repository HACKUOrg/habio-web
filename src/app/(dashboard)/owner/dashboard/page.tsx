import Link from 'next/link'
import { PageHeader } from '@/components/layout/page-header'
import { PlaceholderCard } from '@/components/dashboard/placeholder-card'
import { Button } from '@/components/ui/button'

export default function OwnerDashboardPage() {
  return (
    <>
      <PageHeader
        title="Owner Dashboard"
        description="Organization overview — properties, members, and billing."
      />
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        <PlaceholderCard
          title="Properties"
          description="Manage properties across your organization."
          action={
            <Button variant="outline" size="sm" asChild>
              <Link href="/owner/properties">View properties</Link>
            </Button>
          }
        />
        <PlaceholderCard
          title="Members"
          description="Invite managers, technicians, and housekeepers."
          action={
            <Button variant="outline" size="sm" asChild>
              <Link href="/owner/staff/invite">Invite staff</Link>
            </Button>
          }
        />
        <PlaceholderCard
          title="Billing Plan"
          description="Organization billing settings — coming in Phase 2."
        />
      </div>
    </>
  )
}
