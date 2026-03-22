import { createClient } from '@/lib/supabase/server'
import type { Session, User } from '@supabase/supabase-js'
import type { SubscriptionStatus } from '@/types/database'

export type UserRole = 'admin' | 'subscriber' | 'inactive'

/** Returns the current Supabase session (anon client, cookie-based). */
export async function getSession(): Promise<Session | null> {
  const supabase = await createClient()
  const {
    data: { session },
  } = await supabase.auth.getSession()
  return session
}

/**
 * Returns the authenticated user after server-side validation.
 * Prefer this over reading from the session — it calls the Supabase Auth server.
 */
export async function getUser(): Promise<User | null> {
  const supabase = await createClient()
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser()
  if (error || !user) return null
  return user
}

/**
 * Returns the application-level role for the current user.
 *
 * Mapping:
 *   users.role === 'admin'              → 'admin'
 *   subscription.status ∈ active set   → 'subscriber'
 *   otherwise                          → 'inactive'
 */
export async function getUserRole(): Promise<UserRole> {
  const user = await getUser()
  if (!user) return 'inactive'

  const supabase = await createClient()

  const [{ data: userData }, { data: subscription }] = await Promise.all([
    supabase.from('users').select('role').eq('id', user.id).single(),
    supabase
      .from('subscriptions')
      .select('status')
      .eq('user_id', user.id)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle(),
  ])

  if (userData?.role === 'admin') return 'admin'

  const ACTIVE_STATUSES: SubscriptionStatus[] = ['active', 'trialing']
  if (subscription && ACTIVE_STATUSES.includes(subscription.status)) {
    return 'subscriber'
  }

  return 'inactive'
}
