'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { DEFAULT_PAGE_SIZE, decodeCursor, toPaginatedResult } from '@/lib/pagination'
import type { PaginatedResult } from '@/lib/pagination'
import type { PublicTables } from '@/types'

export type NotificationRow = PublicTables['notifications']['Row']
export type NotificationWithDelivery = NotificationRow & {
  in_app_status: string | null
}

export async function getNotifications(
  cursor?: string
): Promise<PaginatedResult<NotificationWithDelivery>> {
  const supabase = await createClient()
  const { data: claimsData } = await supabase.auth.getClaims()
  const userId = claimsData?.claims?.sub
  if (!userId) return { data: [], nextCursor: null, hasMore: false }

  const decoded = cursor ? decodeCursor(cursor) : null

  let query = supabase
    .from('notifications')
    .select('*, notification_deliveries(status, channel)')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .order('id', { ascending: false })
    .limit(DEFAULT_PAGE_SIZE + 1)

  if (decoded) {
    query = query.or(
      `created_at.lt.${decoded.created_at},and(created_at.eq.${decoded.created_at},id.lt.${decoded.id})`
    )
  }

  const { data, error } = await query
  if (error || !data) return { data: [], nextCursor: null, hasMore: false }

  const mapped = data.map(({ notification_deliveries: deliveries, ...notification }) => ({
    ...notification,
    in_app_status:
      (deliveries as { status: string; channel: string }[] | null)?.find(
        (d) => d.channel === 'in_app'
      )?.status ?? null,
  })) as NotificationWithDelivery[]

  return toPaginatedResult(mapped, DEFAULT_PAGE_SIZE)
}

export async function markNotificationRead(formData: FormData): Promise<void> {
  const id = String(formData.get('notificationId') ?? '').trim()
  if (!id) return

  const supabase = await createClient()
  const { data: claimsData } = await supabase.auth.getClaims()
  const userId = claimsData?.claims?.sub
  if (!userId) return

  await supabase
    .from('notifications')
    .update({ read_at: new Date().toISOString() })
    .eq('id', id)
    .eq('user_id', userId)
    .is('read_at', null)

  revalidatePath('/notifications')
}
