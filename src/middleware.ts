import { createServerClient } from '@supabase/ssr'
import { type NextRequest, NextResponse } from 'next/server'
import type { Database, SubscriptionStatus } from '@/types/database'

// ── Route pattern matchers ────────────────────────────────────────────────────
const DASHBOARD_RE = /^\/dashboard(\/.*)?$/
const ADMIN_RE = /^\/admin(\/.*)?$/

/** Subscription statuses that grant dashboard access */
const ACTIVE_SUB_STATUSES = new Set<SubscriptionStatus>(['active', 'trialing'])

// ── Middleware ────────────────────────────────────────────────────────────────
export async function middleware(request: NextRequest) {
  // We mutate this reference inside the cookie setter so session cookies are
  // forwarded correctly to the browser (required by @supabase/ssr).
  let supabaseResponse = NextResponse.next({ request })

  const supabase = createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
          // Rebuild the response so the updated cookies are forwarded
          supabaseResponse = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          )
        },
      },
    }
  )

  // IMPORTANT: getUser() — not getSession() — to validate the JWT server-side.
  // Do not remove; this keeps the session alive.
  const {
    data: { user },
  } = await supabase.auth.getUser()

  const { pathname } = request.nextUrl
  const isProtectedDashboard = DASHBOARD_RE.test(pathname)
  const isProtectedAdmin = ADMIN_RE.test(pathname)

  // ── Unauthenticated guard ──────────────────────────────────────────────────
  if (!user && (isProtectedDashboard || isProtectedAdmin)) {
    const loginUrl = new URL('/login', request.url)
    loginUrl.searchParams.set('next', pathname)
    return NextResponse.redirect(loginUrl)
  }

  // ── Authenticated path enrichment ──────────────────────────────────────────
  if (user) {
    const [{ data: userData }, { data: subData }] = await Promise.all([
      supabase.from('users').select('role').eq('id', user.id).single(),
      supabase
        .from('subscriptions')
        .select('status')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle(),
    ])

    const isAdmin = userData?.role === 'admin'
    const subStatus: SubscriptionStatus =
      (subData?.status as SubscriptionStatus | undefined) ?? 'inactive'
    const hasActiveSub = ACTIVE_SUB_STATUSES.has(subStatus)

    // ── Admin guard ──────────────────────────────────────────────────────────
    if (isProtectedAdmin && !isAdmin) {
      return NextResponse.redirect(new URL('/', request.url))
    }

    // ── Subscription guard (admins bypass) ───────────────────────────────────
    if (isProtectedDashboard && !isAdmin && !hasActiveSub) {
      return NextResponse.redirect(new URL('/subscribe', request.url))
    }

    // ── Attach enriched headers for downstream use ────────────────────────────
    const requestHeaders = new Headers(request.headers)
    requestHeaders.set('x-user-id', user.id)
    requestHeaders.set(
      'x-user-role',
      isAdmin ? 'admin' : hasActiveSub ? 'subscriber' : 'inactive'
    )
    requestHeaders.set('x-subscription-status', subStatus)

    return NextResponse.next({ request: { headers: requestHeaders } })
  }

  return supabaseResponse
}

// ── Matcher — exclude static assets ──────────────────────────────────────────
export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon\\.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
