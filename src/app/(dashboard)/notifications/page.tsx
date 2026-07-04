import Link from 'next/link'
import { PageHeader } from '@/components/layout/page-header'
import { getNotifications, markNotificationRead } from '@/lib/actions/notifications'
import { Button } from '@/components/ui/button'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'

export default async function NotificationsPage({
  searchParams,
}: {
  searchParams: Promise<{ cursor?: string }>
}) {
  const params = await searchParams
  const { data, nextCursor, hasMore } = await getNotifications(params.cursor)

  return (
    <>
      <PageHeader
        title="Notifications"
        description="In-app notifications and delivery status."
      />
      {data.length === 0 ? (
        <Card>
          <CardHeader>
            <CardTitle>No notifications</CardTitle>
            <CardDescription>You are all caught up.</CardDescription>
          </CardHeader>
        </Card>
      ) : (
        <ul className="space-y-3">
          {data.map((notification) => {
            const isUnread = !notification.read_at

            return (
              <li key={notification.id}>
                <Card className={isUnread ? 'ring-primary/30' : undefined}>
                  <CardHeader className="flex-row items-start justify-between gap-4 space-y-0">
                    <div className="space-y-1">
                      <CardTitle className="text-base">{notification.title}</CardTitle>
                      {notification.body && (
                        <CardDescription>{notification.body}</CardDescription>
                      )}
                    </div>
                    {isUnread && (
                      <form action={markNotificationRead}>
                        <input type="hidden" name="notificationId" value={notification.id} />
                        <Button type="submit" variant="outline" size="sm">
                          Mark read
                        </Button>
                      </form>
                    )}
                  </CardHeader>
                  <CardContent className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-muted-foreground">
                    <span>{new Date(notification.created_at).toLocaleString()}</span>
                    {notification.in_app_status && (
                      <span>In-app: {notification.in_app_status}</span>
                    )}
                  </CardContent>
                </Card>
              </li>
            )
          })}
        </ul>
      )}
      {hasMore && nextCursor && (
        <div className="mt-6">
          <Button variant="outline" asChild>
            <Link href={`/notifications?cursor=${nextCursor}`}>Load more</Link>
          </Button>
        </div>
      )}
    </>
  )
}
