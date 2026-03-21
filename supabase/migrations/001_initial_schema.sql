-- ============================================================
-- Golf Charity Platform — Initial Schema
-- Migration: 001_initial_schema.sql
-- ============================================================
-- All monetary values stored in pence/cents (integer).
-- RLS enabled on every table.
-- Admin role: users.role = 'admin' bypasses row restrictions.
-- ============================================================

-- ─── Extensions ─────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─── Custom Types (Enums) ────────────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE subscription_status AS ENUM (
    'active', 'inactive', 'past_due', 'canceled', 'trialing'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE draw_status AS ENUM (
    'pending', 'simulated', 'published', 'cancelled'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE prize_match_tier AS ENUM (
    'five_match', 'four_match', 'three_match'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE user_role AS ENUM ('user', 'admin');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ─── Helper: is_admin() ──────────────────────────────────────────────────────
-- Returns true when the calling Supabase session belongs to an admin user.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;

-- ─── Table: users ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.users (
  id                  UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email               TEXT NOT NULL UNIQUE,
  full_name           TEXT,
  avatar_url          TEXT,
  role                user_role NOT NULL DEFAULT 'user',
  stripe_customer_id  TEXT UNIQUE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email           ON public.users (email);
CREATE INDEX IF NOT EXISTS idx_users_stripe_customer ON public.users (stripe_customer_id);
CREATE INDEX IF NOT EXISTS idx_users_role            ON public.users (role);

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users: own row select"
  ON public.users FOR SELECT
  USING (auth.uid() = id OR public.is_admin());

CREATE POLICY "users: own row insert"
  ON public.users FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "users: own row update"
  ON public.users FOR UPDATE
  USING (auth.uid() = id OR public.is_admin())
  WITH CHECK (auth.uid() = id OR public.is_admin());

CREATE POLICY "users: admin delete"
  ON public.users FOR DELETE
  USING (public.is_admin());

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ─── Table: charities ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.charities (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  description TEXT,
  logo_url    TEXT,
  website_url TEXT,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_charities_active ON public.charities (is_active);

ALTER TABLE public.charities ENABLE ROW LEVEL SECURITY;

-- Everyone can read active charities; only admins can write
CREATE POLICY "charities: public read"
  ON public.charities FOR SELECT
  USING (is_active = TRUE OR public.is_admin());

CREATE POLICY "charities: admin insert"
  ON public.charities FOR INSERT
  WITH CHECK (public.is_admin());

CREATE POLICY "charities: admin update"
  ON public.charities FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "charities: admin delete"
  ON public.charities FOR DELETE
  USING (public.is_admin());

CREATE TRIGGER trg_charities_updated_at
  BEFORE UPDATE ON public.charities
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ─── Table: subscriptions ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.subscriptions (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  stripe_subscription_id      TEXT NOT NULL UNIQUE,
  stripe_price_id             TEXT NOT NULL,
  status                      subscription_status NOT NULL DEFAULT 'inactive',
  current_period_start        TIMESTAMPTZ NOT NULL,
  current_period_end          TIMESTAMPTZ NOT NULL,
  -- All monetary values in pence/cents (integers)
  amount_pence                INTEGER NOT NULL CHECK (amount_pence >= 0),
  charity_contribution_pence  INTEGER NOT NULL CHECK (charity_contribution_pence >= 0),
  cancel_at_period_end        BOOLEAN NOT NULL DEFAULT FALSE,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id       ON public.subscriptions (user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status        ON public.subscriptions (status);
CREATE INDEX IF NOT EXISTS idx_subscriptions_stripe_sub_id ON public.subscriptions (stripe_subscription_id);

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "subscriptions: own row select"
  ON public.subscriptions FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

CREATE POLICY "subscriptions: service insert"
  ON public.subscriptions FOR INSERT
  WITH CHECK (auth.uid() = user_id OR public.is_admin());

CREATE POLICY "subscriptions: service update"
  ON public.subscriptions FOR UPDATE
  USING (auth.uid() = user_id OR public.is_admin())
  WITH CHECK (auth.uid() = user_id OR public.is_admin());

CREATE POLICY "subscriptions: admin delete"
  ON public.subscriptions FOR DELETE
  USING (public.is_admin());

CREATE TRIGGER trg_subscriptions_updated_at
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ─── Table: scores ──────────────────────────────────────────────────────────
-- Business rule: max 5 scores per user, oldest auto-deleted by trigger.
CREATE TABLE IF NOT EXISTS public.scores (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  -- Stableford range: 1–45
  score      INTEGER NOT NULL CHECK (score BETWEEN 1 AND 45),
  played_at  DATE NOT NULL,
  notes      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scores_user_id   ON public.scores (user_id);
CREATE INDEX IF NOT EXISTS idx_scores_played_at ON public.scores (user_id, played_at DESC);
CREATE INDEX IF NOT EXISTS idx_scores_created_at ON public.scores (user_id, created_at DESC);

ALTER TABLE public.scores ENABLE ROW LEVEL SECURITY;

CREATE POLICY "scores: own row select"
  ON public.scores FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

CREATE POLICY "scores: own row insert"
  ON public.scores FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "scores: own row update"
  ON public.scores FOR UPDATE
  USING (auth.uid() = user_id OR public.is_admin())
  WITH CHECK (auth.uid() = user_id OR public.is_admin());

CREATE POLICY "scores: own row delete"
  ON public.scores FOR DELETE
  USING (auth.uid() = user_id OR public.is_admin());

-- ─── Trigger: rolling 5-score cap ───────────────────────────────────────────
-- After a new score is inserted, if the user now has > 5 scores,
-- delete the oldest one (by created_at) to enforce the rolling cap.
CREATE OR REPLACE FUNCTION public.enforce_max_scores()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  score_count INTEGER;
  oldest_id   UUID;
BEGIN
  SELECT COUNT(*) INTO score_count
  FROM public.scores
  WHERE user_id = NEW.user_id;

  IF score_count > 5 THEN
    SELECT id INTO oldest_id
    FROM public.scores
    WHERE user_id = NEW.user_id
    ORDER BY created_at ASC
    LIMIT 1;

    DELETE FROM public.scores WHERE id = oldest_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_scores_rolling_cap
  AFTER INSERT ON public.scores
  FOR EACH ROW EXECUTE FUNCTION public.enforce_max_scores();

-- ─── Table: draws ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.draws (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  month          INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
  year           INTEGER NOT NULL CHECK (year >= 2024),
  status         draw_status NOT NULL DEFAULT 'pending',
  drawn_numbers  INTEGER[] NOT NULL DEFAULT '{}',
  run_at         TIMESTAMPTZ,
  simulated_at   TIMESTAMPTZ,
  published_at   TIMESTAMPTZ,
  created_by     UUID NOT NULL REFERENCES public.users(id),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (month, year)  -- Only one draw per calendar month
);

CREATE INDEX IF NOT EXISTS idx_draws_status      ON public.draws (status);
CREATE INDEX IF NOT EXISTS idx_draws_month_year  ON public.draws (year DESC, month DESC);

ALTER TABLE public.draws ENABLE ROW LEVEL SECURITY;

-- Published draws are visible to all authenticated users
CREATE POLICY "draws: authenticated select published"
  ON public.draws FOR SELECT
  USING (status = 'published' OR public.is_admin());

CREATE POLICY "draws: admin insert"
  ON public.draws FOR INSERT
  WITH CHECK (public.is_admin());

CREATE POLICY "draws: admin update"
  ON public.draws FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "draws: admin delete"
  ON public.draws FOR DELETE
  USING (public.is_admin());

CREATE TRIGGER trg_draws_updated_at
  BEFORE UPDATE ON public.draws
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ─── Table: draw_entries ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.draw_entries (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  draw_id          UUID NOT NULL REFERENCES public.draws(id) ON DELETE CASCADE,
  user_id          UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  scores_snapshot  INTEGER[] NOT NULL,  -- snapshot of scores at draw time
  matches          INTEGER NOT NULL DEFAULT 0 CHECK (matches BETWEEN 0 AND 5),
  is_winner        BOOLEAN NOT NULL DEFAULT FALSE,
  tier             prize_match_tier,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (draw_id, user_id)  -- One entry per user per draw
);

CREATE INDEX IF NOT EXISTS idx_draw_entries_draw_id  ON public.draw_entries (draw_id);
CREATE INDEX IF NOT EXISTS idx_draw_entries_user_id  ON public.draw_entries (user_id);
CREATE INDEX IF NOT EXISTS idx_draw_entries_winners  ON public.draw_entries (draw_id, is_winner);

ALTER TABLE public.draw_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "draw_entries: own row select"
  ON public.draw_entries FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

CREATE POLICY "draw_entries: admin insert"
  ON public.draw_entries FOR INSERT
  WITH CHECK (public.is_admin());

CREATE POLICY "draw_entries: admin update"
  ON public.draw_entries FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "draw_entries: admin delete"
  ON public.draw_entries FOR DELETE
  USING (public.is_admin());

-- ─── Table: prize_pools ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.prize_pools (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  draw_id              UUID NOT NULL UNIQUE REFERENCES public.draws(id) ON DELETE CASCADE,
  -- All amounts in pence/cents
  total_pence          INTEGER NOT NULL CHECK (total_pence >= 0),
  five_match_pence     INTEGER NOT NULL CHECK (five_match_pence >= 0),   -- 40%
  four_match_pence     INTEGER NOT NULL CHECK (four_match_pence >= 0),   -- 35%
  three_match_pence    INTEGER NOT NULL CHECK (three_match_pence >= 0),  -- 25%
  rollover_pence       INTEGER NOT NULL DEFAULT 0 CHECK (rollover_pence >= 0),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_prize_pools_draw_id ON public.prize_pools (draw_id);

ALTER TABLE public.prize_pools ENABLE ROW LEVEL SECURITY;

-- Authenticated users can view prize pools for published draws
CREATE POLICY "prize_pools: select published draw"
  ON public.prize_pools FOR SELECT
  USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1 FROM public.draws d
      WHERE d.id = prize_pools.draw_id AND d.status = 'published'
    )
  );

CREATE POLICY "prize_pools: admin insert"
  ON public.prize_pools FOR INSERT
  WITH CHECK (public.is_admin());

CREATE POLICY "prize_pools: admin update"
  ON public.prize_pools FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "prize_pools: admin delete"
  ON public.prize_pools FOR DELETE
  USING (public.is_admin());

CREATE TRIGGER trg_prize_pools_updated_at
  BEFORE UPDATE ON public.prize_pools
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ─── Table: winners ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.winners (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  draw_id            UUID NOT NULL REFERENCES public.draws(id) ON DELETE CASCADE,
  draw_entry_id      UUID NOT NULL REFERENCES public.draw_entries(id) ON DELETE CASCADE,
  user_id            UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  tier               prize_match_tier NOT NULL,
  -- Prize amount in pence/cents
  prize_amount_pence INTEGER NOT NULL CHECK (prize_amount_pence >= 0),
  paid_out           BOOLEAN NOT NULL DEFAULT FALSE,
  paid_out_at        TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_winners_draw_id  ON public.winners (draw_id);
CREATE INDEX IF NOT EXISTS idx_winners_user_id  ON public.winners (user_id);
CREATE INDEX IF NOT EXISTS idx_winners_paid_out ON public.winners (paid_out);

ALTER TABLE public.winners ENABLE ROW LEVEL SECURITY;

CREATE POLICY "winners: own row select"
  ON public.winners FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

CREATE POLICY "winners: admin insert"
  ON public.winners FOR INSERT
  WITH CHECK (public.is_admin());

CREATE POLICY "winners: admin update"
  ON public.winners FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "winners: admin delete"
  ON public.winners FOR DELETE
  USING (public.is_admin());

-- ─── Table: donations ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.donations (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  subscription_id   UUID NOT NULL REFERENCES public.subscriptions(id) ON DELETE CASCADE,
  charity_id        UUID NOT NULL REFERENCES public.charities(id),
  -- Amount in pence/cents
  amount_pence      INTEGER NOT NULL CHECK (amount_pence >= 0),
  stripe_payment_id TEXT,
  donated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_donations_user_id      ON public.donations (user_id);
CREATE INDEX IF NOT EXISTS idx_donations_charity_id   ON public.donations (charity_id);
CREATE INDEX IF NOT EXISTS idx_donations_sub_id       ON public.donations (subscription_id);
CREATE INDEX IF NOT EXISTS idx_donations_donated_at   ON public.donations (donated_at DESC);

ALTER TABLE public.donations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "donations: own row select"
  ON public.donations FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

CREATE POLICY "donations: service insert"
  ON public.donations FOR INSERT
  WITH CHECK (auth.uid() = user_id OR public.is_admin());

-- Donations are immutable by users; only admins can update/delete
CREATE POLICY "donations: admin update"
  ON public.donations FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE POLICY "donations: admin delete"
  ON public.donations FOR DELETE
  USING (public.is_admin());

-- ─── Auto-create user profile on signup ────────────────────────────────────
-- When a new auth.users row is created, mirror it into public.users.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name, avatar_url)
  VALUES (
    NEW.id,
    NEW.email,
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'avatar_url'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ─── Grant permissions ───────────────────────────────────────────────────────
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT SELECT ON public.charities TO anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;
GRANT EXECUTE ON FUNCTION public.enforce_max_scores() TO authenticated, service_role;
