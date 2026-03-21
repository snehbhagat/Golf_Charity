@AGENTS.md
# Golf Charity Subscription Platform

## Project Overview
Subscription web app: golf score tracking + charity fundraising + monthly prize draws.
Stack: Next.js 14 App Router, Supabase, Stripe, Resend, Tailwind, shadcn/ui.
Deploy target: Vercel (new account) + Supabase (new project).

## Core Business Rules — NEVER break these
- Scores: Stableford format, range 1–45, max 5 stored, rolling (oldest auto-dropped)
- Prize split: 5-match=40% (rollover if no winner), 4-match=35%, 3-match=25%
- Charity contribution: minimum 10% of subscription fee per user
- Draws: monthly cadence, must pass simulation mode before admin publishes
- Subscription validation: check status on every authenticated API request via middleware

## Folder Structure
/app               → Next.js App Router pages
/app/api           → All API routes
/app/(admin)       → Admin panel routes (role-gated)
/app/(user)        → Authenticated user routes
/components        → Reusable UI components
/lib/supabase      → DB client + typed queries
/lib/stripe        → Stripe helpers + webhook handler
/lib/draw-engine   → Draw algorithm logic (isolated, unit-testable)
/lib/prize-engine  → Prize pool calculation logic
/lib/score-engine  → Score validation + rolling logic

## Code Style
- TypeScript strict mode always
- Zod for all API input validation
- Server Actions for form mutations where possible
- RLS must be set on all Supabase tables — never bypass with service key in client code
- All monetary values stored in pence/cents (integers), displayed with formatting helpers

## Design System
- Emotion-driven, modern — NOT a traditional golf site
- No golf clichés (no fairways, plaid, club imagery as primary language)
- Lead with charity impact visually, not sport
- Subtle animations and micro-interactions throughout
- Mobile-first, fully responsive

## Environment Variables (never hardcode)
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY
STRIPE_SECRET_KEY
STRIPE_WEBHOOK_SECRET
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY
RESEND_API_KEY
NEXTAUTH_SECRET