import { PageHeader } from '@/components/layout/page-header'
import { PlaceholderCard } from '@/components/dashboard/placeholder-card'

export default function ManagerDashboardPage() {
  return (
    <>
      <PageHeader
        title="Manager Dashboard"
        description="Overview of your property — occupancy, bills, and tickets."
      />
      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        <PlaceholderCard
          title="Occupancy"
          description="Room occupancy summary — coming in Phase 2."
        />
        <PlaceholderCard
          title="Outstanding Bills"
          description="Billing overview — coming in Phase 2."
        />
        <PlaceholderCard
          title="Open Tickets"
          description="Maintenance ticket summary — coming in Phase 3."
        />
      </div>
    </>
  )
}
