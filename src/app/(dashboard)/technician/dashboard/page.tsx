import { PageHeader } from '@/components/layout/page-header'
import { PlaceholderCard } from '@/components/dashboard/placeholder-card'

export default function TechnicianDashboardPage() {
  return (
    <>
      <PageHeader
        title="Technician Dashboard"
        description="Your assigned maintenance tickets."
      />
      <PlaceholderCard
        title="Assigned Tickets"
        description="Open ticket list — coming in Phase 3."
      />
    </>
  )
}
