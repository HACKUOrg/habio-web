import type { NextRequest, NextResponse } from 'next/server'
import type { ActiveMembership, ActiveMembershipCookiePayload } from '@/lib/membership/types'

export const ACTIVE_MEMBERSHIP_COOKIE = 'habio-active-membership'
const CACHE_TTL_SECONDS = 1800

function getSecret(): string {
  const secret =
    process.env.MEMBERSHIP_COOKIE_SECRET ?? process.env.ROLE_CACHE_SECRET
  if (!secret) {
    throw new Error('MEMBERSHIP_COOKIE_SECRET or ROLE_CACHE_SECRET is not configured')
  }
  return secret
}

async function importKey(): Promise<CryptoKey> {
  const encoder = new TextEncoder()
  return crypto.subtle.importKey(
    'raw',
    encoder.encode(getSecret()),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  )
}

function toBase64Url(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer)
  let binary = ''
  for (const byte of bytes) {
    binary += String.fromCharCode(byte)
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function fromBase64Url(value: string): string {
  const padded = value + '='.repeat((4 - (value.length % 4)) % 4)
  const base64 = padded.replace(/-/g, '+').replace(/_/g, '/')
  return atob(base64)
}

async function signPayload(encodedPayload: string): Promise<string> {
  const key = await importKey()
  const encoder = new TextEncoder()
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(encodedPayload))
  return toBase64Url(signature)
}

function encodePayload(payload: ActiveMembershipCookiePayload): string {
  return btoa(JSON.stringify(payload))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')
}

function decodePayload(encoded: string): ActiveMembershipCookiePayload | null {
  try {
    const json = fromBase64Url(encoded)
    const parsed = JSON.parse(json) as ActiveMembershipCookiePayload
    if (
      !parsed.membershipId ||
      !parsed.userId ||
      !parsed.role ||
      !parsed.organizationId ||
      !parsed.exp
    ) {
      return null
    }
    return parsed
  } catch {
    return null
  }
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false
  let result = 0
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i)
  }
  return result === 0
}

export async function parseActiveMembershipCookie(
  request: NextRequest
): Promise<ActiveMembership | null> {
  const cookie = request.cookies.get(ACTIVE_MEMBERSHIP_COOKIE)?.value
  if (!cookie) return null

  const dotIndex = cookie.lastIndexOf('.')
  if (dotIndex === -1) return null

  const encodedPayload = cookie.slice(0, dotIndex)
  const signature = cookie.slice(dotIndex + 1)
  const expectedSignature = await signPayload(encodedPayload)

  if (!timingSafeEqual(signature, expectedSignature)) return null

  const payload = decodePayload(encodedPayload)
  if (!payload) return null
  if (payload.exp < Math.floor(Date.now() / 1000)) return null

  return {
    membershipId: payload.membershipId,
    userId: payload.userId,
    role: payload.role,
    organizationId: payload.organizationId,
    propertyId: payload.propertyId,
  }
}

export async function setActiveMembershipCookie(
  response: NextResponse,
  membership: ActiveMembership
): Promise<void> {
  const payload: ActiveMembershipCookiePayload = {
    ...membership,
    exp: Math.floor(Date.now() / 1000) + CACHE_TTL_SECONDS,
  }
  const encodedPayload = encodePayload(payload)
  const signature = await signPayload(encodedPayload)
  const value = `${encodedPayload}.${signature}`

  response.cookies.set(ACTIVE_MEMBERSHIP_COOKIE, value, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    maxAge: CACHE_TTL_SECONDS,
    path: '/',
  })
}

export function clearActiveMembershipCookie(response: NextResponse): void {
  response.cookies.set(ACTIVE_MEMBERSHIP_COOKIE, '', {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    maxAge: 0,
    path: '/',
  })
}
