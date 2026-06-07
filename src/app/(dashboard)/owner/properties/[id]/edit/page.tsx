import { notFound } from 'next/navigation'
import { PageHeader } from '@/components/layout/page-header'
import { PropertyForm } from '@/components/dashboard/property-form'
import { getProperty } from '@/lib/actions/properties'

export default async function EditPropertyPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const { id } = await params
  const property = await getProperty(id)

  if (!property) {
    notFound()
  }

  return (
    <>
      <PageHeader title="Edit property" description={property.name} />
      <div className="max-w-xl">
        <PropertyForm property={property} />
      </div>
    </>
  )
}
