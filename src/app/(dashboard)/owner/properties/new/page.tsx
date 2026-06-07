import { PageHeader } from '@/components/layout/page-header'
import { PropertyForm } from '@/components/dashboard/property-form'

export default function NewPropertyPage() {
  return (
    <>
      <PageHeader title="New property" description="Add a property to your organization." />
      <div className="max-w-xl">
        <PropertyForm />
      </div>
    </>
  )
}
