import { PageHeader } from '@/components/layout/page-header'
import { PlaceholderCard } from '@/components/dashboard/placeholder-card'

export default function TenantDashboardPage() {
  return (
    <>
      <PageHeader
        title="Tenant Dashboard"
        description="Your room, current bill, and maintenance requests."
      />
      <div className="grid gap-4 md:grid-cols-2">
        <PlaceholderCard
          title="My Room"
          description="Room and lease details — coming in Phase 2."
        />
        <PlaceholderCard
          title="Current Bill"
          description="Billing summary — coming in Phase 2."
        />
        <PlaceholderCard
          title="Maintenance"
          description="Ticket status — coming in Phase 3."
        />
      </div>
    </>
  )
}
