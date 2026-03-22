/**
 * NextAuth v5 (Auth.js) configuration.
 *
 * Strategy: JWT (no database sessions) + Credentials provider that delegates
 * password verification to Supabase Auth.  The Supabase adapter is included for
 * future OAuth provider support; it requires database session strategy, so it is
 * commented out until needed.
 *
 * Primary session management in this app is handled by @supabase/ssr cookies.
 * NextAuth is present for /api/auth/* compatibility and as a secondary layer.
 */

import NextAuth from 'next-auth'
import Credentials from 'next-auth/providers/credentials'
import { createClient } from '@supabase/supabase-js'
import { z } from 'zod'

// ── Validation schema ────────────────────────────────────────────────────────
const credentialsSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6),
})

// ── Admin Supabase client (server-side only, never exposed to browser) ───────
const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

// ── NextAuth config ───────────────────────────────────────────────────────────
export const { auth, handlers, signIn, signOut } = NextAuth({
  session: {
    strategy: 'jwt',
  },

  providers: [
    Credentials({
      name: 'Email & Password',
      credentials: {
        email: { label: 'Email', type: 'email', placeholder: 'you@example.com' },
        password: { label: 'Password', type: 'password' },
      },
      async authorize(credentials) {
        const parsed = credentialsSchema.safeParse(credentials)
        if (!parsed.success) return null

        const { data: authData, error } = await supabaseAdmin.auth.signInWithPassword({
          email: parsed.data.email,
          password: parsed.data.password,
        })

        if (error || !authData.user) return null

        return {
          id: authData.user.id,
          email: authData.user.email ?? '',
          name: (authData.user.user_metadata?.full_name as string | undefined) ?? null,
        }
      },
    }),
  ],

  callbacks: {
    async jwt({ token, user }) {
      if (user?.id) {
        token.sub = user.id
      }
      return token
    },
    async session({ session, token }) {
      if (token.sub) {
        session.user.id = token.sub
      }
      return session
    },
  },

  pages: {
    signIn: '/login',
    error: '/login',
  },

  secret: process.env.NEXTAUTH_SECRET,
})
