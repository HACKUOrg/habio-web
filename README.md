# Habio

Dormitory and rental property management platform.

## Tech stack

- Next.js 16 (App Router), React 19, Tailwind CSS 4, shadcn/ui
- Supabase (PostgreSQL, Auth, RLS)
- Vercel

## Local development

1. Copy environment variables:

```bash
cp .env.local .env.production
```

2. Fill in Supabase credentials from your dev project dashboard.

3. Apply database migrations:

```bash
supabase link --project-ref <your-project-ref>
supabase db push
```

4. (Optional) Seed dev test users:

```bash
supabase db reset   # local only — runs migrations + seed.sql
```

Dev seed accounts (password: `password123`):

| Email | Role |
|---|---|
| `manager@habio.dev` | Manager |
| `tenant@habio.dev` | Tenant |
| `technician@habio.dev` | Technician |
| `housekeeper@habio.dev` | Housekeeper |

5. Start the dev server:

```bash
npm run dev
```

## Deployment

### Vercel

Set these environment variables in the Vercel project (Preview → dev Supabase, Production → prod Supabase):

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
- `ROLE_CACHE_SECRET` (generate with `openssl rand -base64 32`)
- `NEXT_PUBLIC_SITE_URL` (your deployment URL)

### GitHub Actions (CI)

Configure these repository secrets for full CI (build + `supabase db push`):

| Secret | Purpose |
|---|---|
| `SUPABASE_ACCESS_TOKEN` | Supabase CLI authentication |
| `SUPABASE_PROJECT_REF` | Dev project reference ID |
| `NEXT_PUBLIC_SUPABASE_URL` | Build-time env |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Build-time env |
| `ROLE_CACHE_SECRET` | Build-time env |

Without Supabase secrets, CI still runs lint and build; migration push is skipped.

## Documentation

Architecture and implementation docs live in [`docs/`](docs/).
