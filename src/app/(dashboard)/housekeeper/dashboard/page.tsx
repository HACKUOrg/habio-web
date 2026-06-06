import { PageHeader } from '@/components/layout/page-header'
import { PlaceholderCard } from '@/components/dashboard/placeholder-card'

export default function HousekeeperDashboardPage() {
  return (
    <>
      <PageHeader
        title="Housekeeper Dashboard"
        description="Your assigned cleaning tasks for today."
      />
      <PlaceholderCard
        title="Today's Tasks"
        description="Task list — coming in Phase 3."
      />
    </>
  )
}
