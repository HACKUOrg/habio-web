'use client'

import Link from 'next/link'
import { ArrowLeftRight, LogOut } from 'lucide-react'
import { signOut } from '@/lib/actions/auth'
import { Avatar, AvatarFallback } from '@/components/ui/avatar'
import { Button } from '@/components/ui/button'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { MEMBERSHIP_ROLE_LABELS, type MembershipWithContext } from '@/types'

interface TopnavProps {
  fullName: string
  membership: MembershipWithContext
  hasMultipleMemberships: boolean
}

function getInitials(name: string): string {
  return name
    .split(' ')
    .map((part) => part[0])
    .join('')
    .slice(0, 2)
    .toUpperCase()
}

export function Topnav({ fullName, membership, hasMultipleMemberships }: TopnavProps) {
  const roleLabel = MEMBERSHIP_ROLE_LABELS[membership.role]
  const contextLabel = membership.propertyName
    ? `${roleLabel} · ${membership.propertyName}`
    : `${roleLabel} · ${membership.organizationName}`

  return (
    <header className="flex h-14 items-center justify-between border-b px-6">
      <p className="text-sm text-muted-foreground">{contextLabel}</p>
      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="ghost" className="relative h-9 w-9 rounded-full">
            <Avatar className="h-9 w-9">
              <AvatarFallback>{getInitials(fullName)}</AvatarFallback>
            </Avatar>
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end" className="w-56">
          <DropdownMenuLabel>
            <div className="flex flex-col space-y-1">
              <p className="text-sm font-medium">{fullName}</p>
              <p className="text-xs text-muted-foreground">{contextLabel}</p>
            </div>
          </DropdownMenuLabel>
          <DropdownMenuSeparator />
          {hasMultipleMemberships && (
            <DropdownMenuItem asChild>
              <Link href="/select-membership" className="flex cursor-pointer items-center">
                <ArrowLeftRight className="mr-2 h-4 w-4" />
                Switch workspace
              </Link>
            </DropdownMenuItem>
          )}
          <DropdownMenuItem asChild>
            <form action={signOut}>
              <button
                type="submit"
                className="flex w-full cursor-pointer items-center text-destructive focus:text-destructive"
              >
                <LogOut className="mr-2 h-4 w-4" />
                Sign out
              </button>
            </form>
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
    </header>
  )
}
