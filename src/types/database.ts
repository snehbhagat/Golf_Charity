export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

// ─── Enums ──────────────────────────────────────────────────────────────────

export type SubscriptionStatus =
  | 'active'
  | 'inactive'
  | 'past_due'
  | 'canceled'
  | 'trialing'

export type DrawStatus = 'pending' | 'simulated' | 'published' | 'cancelled'

export type PrizeMatchTier = 'five_match' | 'four_match' | 'three_match'

// ─── Table Row Types ────────────────────────────────────────────────────────

export interface User {
  id: string                        // uuid, references auth.users
  email: string
  full_name: string | null
  avatar_url: string | null
  role: 'user' | 'admin'
  stripe_customer_id: string | null
  created_at: string
  updated_at: string
}

export interface Subscription {
  id: string                        // uuid
  user_id: string                   // references users.id
  stripe_subscription_id: string
  stripe_price_id: string
  status: SubscriptionStatus
  current_period_start: string
  current_period_end: string
  /** Monthly subscription fee in pence/cents */
  amount_pence: number
  /** Charity contribution per cycle in pence/cents (min 10% of amount_pence) */
  charity_contribution_pence: number
  cancel_at_period_end: boolean
  created_at: string
  updated_at: string
}

export interface Score {
  id: string                        // uuid
  user_id: string                   // references users.id
  /** Stableford score (range 1–45) */
  score: number
  played_at: string                 // date the round was played
  notes: string | null
  created_at: string
}

export interface Draw {
  id: string                        // uuid
  month: number                     // 1–12
  year: number
  status: DrawStatus
  /** Numbers drawn for this month's prize sequence */
  drawn_numbers: number[]
  /** ISO string timestamp when draw was run */
  run_at: string | null
  simulated_at: string | null
  published_at: string | null
  created_by: string                // admin user_id
  created_at: string
  updated_at: string
}

export interface DrawEntry {
  id: string                        // uuid
  draw_id: string                   // references draws.id
  user_id: string                   // references users.id
  /** Array of score values entered for this draw (up to 5) */
  scores_snapshot: number[]
  matches: number                   // how many scores matched drawn numbers
  is_winner: boolean
  tier: PrizeMatchTier | null       // null if not a winner
  created_at: string
}

export interface Winner {
  id: string                        // uuid
  draw_id: string                   // references draws.id
  draw_entry_id: string             // references draw_entries.id
  user_id: string                   // references users.id
  tier: PrizeMatchTier
  /** Prize amount won in pence/cents */
  prize_amount_pence: number
  /** Whether the prize has been paid out */
  paid_out: boolean
  paid_out_at: string | null
  created_at: string
}

export interface PrizePool {
  id: string                        // uuid
  draw_id: string                   // references draws.id
  /** Total prize pool in pence/cents */
  total_pence: number
  /** 40% — rolls over if no winner */
  five_match_pence: number
  /** 35% */
  four_match_pence: number
  /** 25% */
  three_match_pence: number
  /** Rollover carried forward from previous month (pence/cents) */
  rollover_pence: number
  created_at: string
  updated_at: string
}

export interface Charity {
  id: string                        // uuid
  name: string
  description: string | null
  logo_url: string | null
  website_url: string | null
  is_active: boolean
  created_at: string
  updated_at: string
}

export interface Donation {
  id: string                        // uuid
  user_id: string                   // references users.id
  subscription_id: string           // references subscriptions.id
  charity_id: string                // references charities.id
  /** Donation amount in pence/cents */
  amount_pence: number
  /** Stripe payment intent or transfer ID */
  stripe_payment_id: string | null
  donated_at: string
  created_at: string
}

// ─── Database Schema (for Supabase typed client) ───────────────────────────

export interface Database {
  public: {
    Tables: {
      users: {
        Row: User
        Insert: Omit<User, 'created_at' | 'updated_at'>
        Update: Partial<Omit<User, 'id' | 'created_at'>>
      }
      subscriptions: {
        Row: Subscription
        Insert: Omit<Subscription, 'id' | 'created_at' | 'updated_at'>
        Update: Partial<Omit<Subscription, 'id' | 'created_at'>>
      }
      scores: {
        Row: Score
        Insert: Omit<Score, 'id' | 'created_at'>
        Update: Partial<Omit<Score, 'id' | 'created_at'>>
      }
      draws: {
        Row: Draw
        Insert: Omit<Draw, 'id' | 'created_at' | 'updated_at'>
        Update: Partial<Omit<Draw, 'id' | 'created_at'>>
      }
      draw_entries: {
        Row: DrawEntry
        Insert: Omit<DrawEntry, 'id' | 'created_at'>
        Update: Partial<Omit<DrawEntry, 'id' | 'created_at'>>
      }
      winners: {
        Row: Winner
        Insert: Omit<Winner, 'id' | 'created_at'>
        Update: Partial<Omit<Winner, 'id' | 'created_at'>>
      }
      prize_pools: {
        Row: PrizePool
        Insert: Omit<PrizePool, 'id' | 'created_at' | 'updated_at'>
        Update: Partial<Omit<PrizePool, 'id' | 'created_at'>>
      }
      charities: {
        Row: Charity
        Insert: Omit<Charity, 'id' | 'created_at' | 'updated_at'>
        Update: Partial<Omit<Charity, 'id' | 'created_at'>>
      }
      donations: {
        Row: Donation
        Insert: Omit<Donation, 'id' | 'created_at'>
        Update: Partial<Omit<Donation, 'id' | 'created_at'>>
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      [_ in never]: never
    }
    Enums: {
      subscription_status: SubscriptionStatus
      draw_status: DrawStatus
      prize_match_tier: PrizeMatchTier
    }
  }
}
