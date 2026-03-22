'use client'

import { useActionState } from 'react'
import Link from 'next/link'
import { forgotPasswordAction, type AuthActionResult } from '@/actions/auth'

const initialState: AuthActionResult = {}

export default function ForgotPasswordPage() {
  const [state, formAction, pending] = useActionState(forgotPasswordAction, initialState)

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="w-full max-w-md space-y-6">
        <div className="text-center">
          <h1 className="text-2xl font-bold tracking-tight">Reset your password</h1>
          <p className="mt-1 text-sm text-gray-500">
            Enter your email and we&apos;ll send you a reset link.
          </p>
        </div>

        <form action={formAction} className="space-y-4">
          {state.error && (
            <div className="rounded-md bg-red-50 p-3 text-sm text-red-700" role="alert">
              {state.error}
            </div>
          )}

          {state.success && (
            <div className="rounded-md bg-green-50 p-3 text-sm text-green-700" role="status">
              {state.success}
            </div>
          )}

          <div>
            <label htmlFor="email" className="block text-sm font-medium text-gray-700 mb-1">
              Email address
            </label>
            <input
              id="email"
              name="email"
              type="email"
              autoComplete="email"
              required
              className="block w-full rounded-md border border-gray-300 px-3 py-2 text-sm shadow-sm placeholder:text-gray-400 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              placeholder="you@example.com"
            />
          </div>

          <button
            id="forgot-password-submit"
            type="submit"
            disabled={pending || !!state.success}
            className="w-full flex justify-center rounded-md bg-indigo-600 px-4 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            {pending ? 'Sending…' : 'Send reset link'}
          </button>
        </form>

        <div className="text-center">
          <Link href="/login" className="text-sm font-medium text-indigo-600 hover:underline">
            ← Back to sign in
          </Link>
        </div>
      </div>
    </div>
  )
}
