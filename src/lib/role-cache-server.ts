import { cookies } from 'next/headers'
import type { UserRole } from '@/types'
import { ROLE_CACHE_COOKIE } from '@/lib/role-cache'

const CACHE_TTL_SECONDS = 600

interface RoleCachePayload {
  role: UserRole
  uid: string
  exp: number
}

function getSecret(): string {
  const secret = process.env.ROLE_CACHE_SECRET
  if (!secret) {
    throw new Error('ROLE_CACHE_SECRET is not configured')
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

async function signPayload(encodedPayload: string): Promise<string> {
  const key = await importKey()
  const encoder = new TextEncoder()
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(encodedPayload))
  return toBase64Url(signature)
}

function encodePayload(payload: RoleCachePayload): string {
  return btoa(JSON.stringify(payload))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')
}

export async function setRoleCacheInCookies(userId: string, role: UserRole): Promise<void> {
  const cookieStore = await cookies()
  const payload: RoleCachePayload = {
    role,
    uid: userId,
    exp: Math.floor(Date.now() / 1000) + CACHE_TTL_SECONDS,
  }
  const encodedPayload = encodePayload(payload)
  const signature = await signPayload(encodedPayload)
  const value = `${encodedPayload}.${signature}`

  cookieStore.set(ROLE_CACHE_COOKIE, value, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    maxAge: CACHE_TTL_SECONDS,
    path: '/',
  })
}

export async function clearRoleCacheInCookies(): Promise<void> {
  const cookieStore = await cookies()
  cookieStore.set(ROLE_CACHE_COOKIE, '', {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    maxAge: 0,
    path: '/',
  })
}
