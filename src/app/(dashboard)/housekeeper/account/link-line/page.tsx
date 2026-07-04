import { PageHeader } from '@/components/layout/page-header'
import { LinkLineCard } from '@/components/account/link-line-card'

export default async function HousekeeperLinkLinePage({
  searchParams,
}: {
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}) {
  const { linked, unlinked, error } = await searchParams
  return (
    <>
      <PageHeader
        title="LINE Account"
        description="Manage your LINE account connection."
      />
      <LinkLineCard
        linked={linked === '1'}
        unlinked={unlinked === '1'}
        error={typeof error === 'string' ? error : undefined}
      />
    </>
  )
}
