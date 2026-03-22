import { createClient } from '@supabase/supabase-js'
import { NextResponse } from 'next/server'
import { z } from 'zod'
import type { Database } from '@/types/database'

// ── Validation ────────────────────────────────────────────────────────────────
const signupSchema = z.object({
  full_name: z.string().min(2, 'Name must be at least 2 characters'),
  email: z.string().email('Invalid email address'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
})

// ── Service-role client (never expose key to browser) ────────────────────────
function getServiceClient() {
  return createClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  )
}

// ── POST /api/auth/signup ─────────────────────────────────────────────────────
export async function POST(request: Request) {
  let body: unknown
  try {
    body = await request.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const parsed = signupSchema.safeParse(body)
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0]?.message ?? 'Invalid input' },
      { status: 422 }
    )
  }

  const { full_name, email, password } = parsed.data
  const supabase = getServiceClient()

  // 1. Create the auth user via admin API (no confirmation email needed in dev)
  const { data: authData, error: authError } = await supabase.auth.admin.createUser({
    email,
    password,
    email_confirm: true, // auto-confirm so user can sign in immediately
    user_metadata: { full_name },
  })

  if (authError) {
    const status = authError.message.toLowerCase().includes('already registered') ? 409 : 400
    return NextResponse.json({ error: authError.message }, { status })
  }

  if (!authData.user) {
    return NextResponse.json({ error: 'User creation failed' }, { status: 500 })
  }

  // 2. Insert into public.users  (trigger may do this too — upsert is safe)
  const { error: dbError } = await supabase.from('users').upsert(
    {
      id: authData.user.id,
      email,
      full_name,
      role: 'user',
      avatar_url: null,
      stripe_customer_id: null,
    },
    { onConflict: 'id' }
  )

  if (dbError) {
    // Roll back the auth user so the system stays consistent
    await supabase.auth.admin.deleteUser(authData.user.id)
    return NextResponse.json({ error: 'Failed to create user profile' }, { status: 500 })
  }

  return NextResponse.json({ userId: authData.user.id }, { status: 201 })
}
