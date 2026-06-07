export const DEFAULT_PAGE_SIZE = 20

export type Cursor = {
  created_at: string
  id: string
}

export type PaginatedResult<T> = {
  data: T[]
  nextCursor: string | null
  hasMore: boolean
}

export function encodeCursor(cursor: Cursor): string {
  const json = JSON.stringify(cursor)
  return btoa(json).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

export function decodeCursor(encoded: string): Cursor | null {
  try {
    const padded = encoded + '='.repeat((4 - (encoded.length % 4)) % 4)
    const base64 = padded.replace(/-/g, '+').replace(/_/g, '/')
    const json = atob(base64)
    const parsed = JSON.parse(json) as Cursor
    if (typeof parsed.created_at !== 'string' || typeof parsed.id !== 'string') {
      return null
    }
    return parsed
  } catch {
    return null
  }
}

export function buildCursorFilter(cursor: Cursor | null): string | null {
  if (!cursor) return null
  return `created_at.lt.${cursor.created_at},and(created_at.eq.${cursor.created_at},id.lt.${cursor.id})`
}

export function toPaginatedResult<T extends { id: string; created_at: string }>(
  data: T[],
  pageSize: number
): PaginatedResult<T> {
  const hasMore = data.length > pageSize
  const sliced = hasMore ? data.slice(0, pageSize) : data
  const last = sliced[sliced.length - 1]
  const nextCursor =
    hasMore && last
      ? encodeCursor({ created_at: last.created_at, id: last.id })
      : null

  return { data: sliced, nextCursor, hasMore }
}
