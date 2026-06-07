import Link from 'next/link'
import { PageHeader } from '@/components/layout/page-header'
import { listOrganizationProperties } from '@/lib/actions/properties'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'

const statusLabel: Record<string, string> = {
  active: 'Active',
  inactive: 'Inactive',
  archived: 'Archived',
}

export default async function OwnerPropertiesPage() {
  const { data: properties } = await listOrganizationProperties()

  return (
    <>
      <PageHeader
        title="Properties"
        description="Manage properties across your organization."
        action={
          <Button asChild>
            <Link href="/owner/properties/new">Add property</Link>
          </Button>
        }
      />
      {properties.length === 0 ? (
        <Card>
          <CardHeader>
            <CardTitle>No properties yet</CardTitle>
            <CardDescription>Create your first property to get started.</CardDescription>
          </CardHeader>
          <CardContent>
            <Button asChild>
              <Link href="/owner/properties/new">Add property</Link>
            </Button>
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {properties.map((property) => (
            <Card key={property.id}>
              <CardHeader>
                <CardTitle className="text-lg">{property.name}</CardTitle>
                <CardDescription>{property.address}</CardDescription>
              </CardHeader>
              <CardContent className="flex items-center justify-between">
                <span className="text-xs text-muted-foreground">
                  {statusLabel[property.status] ?? property.status}
                </span>
                <Button variant="outline" size="sm" asChild>
                  <Link href={`/owner/properties/${property.id}/edit`}>Edit</Link>
                </Button>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </>
  )
}
