'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { LayoutDashboard } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { MembershipRole } from '@/types'

interface SidebarProps {
  role: MembershipRole
}

const accountLink = (role: MembershipRole) => ({
  href: `/${role}/account/link-line`,
  label: 'Account',
})

const sharedNav = [{ href: '/notifications', label: 'Notifications' }]

const navItems: Record<MembershipRole, { href: string; label: string }[]> = {
  owner: [
    { href: '/owner/dashboard', label: 'Dashboard' },
    { href: '/owner/properties', label: 'Properties' },
    { href: '/owner/staff/invite', label: 'Invite staff' },
    { href: '/manager/tenants/new', label: 'Add tenant' },
    ...sharedNav,
    accountLink('owner'),
  ],
  manager: [
    { href: '/manager/dashboard', label: 'Dashboard' },
    { href: '/manager/staff/invite', label: 'Invite staff' },
    { href: '/manager/tenants/new', label: 'Add tenant' },
    ...sharedNav,
    accountLink('manager'),
  ],
  tenant: [
    { href: '/tenant/dashboard', label: 'Dashboard' },
    ...sharedNav,
    accountLink('tenant'),
  ],
  technician: [
    { href: '/technician/dashboard', label: 'Dashboard' },
    ...sharedNav,
    accountLink('technician'),
  ],
  housekeeper: [
    { href: '/housekeeper/dashboard', label: 'Dashboard' },
    ...sharedNav,
    accountLink('housekeeper'),
  ],
}

export function Sidebar({ role }: SidebarProps) {
  const pathname = usePathname()
  const items = navItems[role]

  return (
    <aside className="flex w-56 shrink-0 flex-col border-r bg-muted/30">
      <div className="flex h-14 items-center border-b px-4">
        <Link href={`/${role}/dashboard`} className="text-lg font-semibold">
          Habio
        </Link>
      </div>
      <nav className="flex flex-1 flex-col gap-1 p-3">
        {items.map((item) => {
          const isActive =
            pathname === item.href || (item.href !== `/${role}/dashboard` && pathname.startsWith(item.href))
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                'flex items-center gap-2 rounded-md px-3 py-2 text-sm font-medium transition-colors',
                isActive
                  ? 'bg-primary text-primary-foreground'
                  : 'text-muted-foreground hover:bg-muted hover:text-foreground'
              )}
            >
              <LayoutDashboard className="h-4 w-4" />
              {item.label}
            </Link>
          )
        })}
      </nav>
    </aside>
  )
}
