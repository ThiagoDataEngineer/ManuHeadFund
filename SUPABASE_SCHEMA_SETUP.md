# Supabase Schema Setup - ManuHeadFund Trading System

## Overview
Dados que podem ter problemas de sincronização entre GitHub Actions (cloud) e local devem estar no Supabase em tabelas dedicadas no schema `manuheadfund`.

## Current State
- **Local/JSON files**: `coin_registry.json`, `tier_a_drawdown_*.json`, `tori_proximity_state.json`, `beta_vs_btc.json`, `dsr_global.json`, `regime_state.json`
- **GitHub Actions**: Cria arquivos JSON mas não sincroniza com local
- **Problem**: 0 trades executing because data is fragmented

## Solution: Supabase Tables

### 1. Table: `fqs_registry` (Fundamental Quality Scores)
```sql
CREATE TABLE manuheadfund.fqs_registry (
  id BIGSERIAL PRIMARY KEY,
  market TEXT NOT NULL UNIQUE,
  fqs INTEGER NOT NULL,  -- 1-7 score
  category TEXT NOT NULL,  -- BLUE_CHIP, QUALITY, SPECULATIVE, AVOID
  age_years INTEGER,
  supply_capped BOOLEAN,
  burn_active BOOLEAN,
  utility_score NUMERIC(3,2),
  concentration_top10 NUMERIC(3,2),
  recovered_2021_ath BOOLEAN,
  listing_years INTEGER,
  notes TEXT,
  current_price_usd NUMERIC(20,8),
  ath_all_time_usd NUMERIC(20,8),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_fqs_registry_market ON manuheadfund.fqs_registry(market);
CREATE INDEX idx_fqs_registry_category ON manuheadfund.fqs_registry(category);
CREATE INDEX idx_fqs_registry_updated ON manuheadfund.fqs_registry(updated_at DESC);
```

### 2. Table: `tori_proximity` (Trendline Support/Resistance)
```sql
CREATE TABLE manuheadfund.tori_proximity (
  id BIGSERIAL PRIMARY KEY,
  market TEXT NOT NULL UNIQUE,
  valid BOOLEAN NOT NULL DEFAULT FALSE,
  side TEXT,  -- LONG, SHORT, NONE
  price NUMERIC(20,8),
  action_line NUMERIC(20,8),
  proximity_pct NUMERIC(5,2),
  touches INTEGER,
  slope_deg NUMERIC(6,2),
  rsi NUMERIC(5,2),
  vol_drying BOOLEAN,
  setup_ripening BOOLEAN,
  take_profit NUMERIC(20,8),
  stop_loss NUMERIC(20,8),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_tori_proximity_market ON manuheadfund.tori_proximity(market);
CREATE INDEX idx_tori_proximity_valid ON manuheadfund.tori_proximity(valid);
CREATE INDEX idx_tori_proximity_updated ON manuheadfund.tori_proximity(updated_at DESC);
```

### 3. Table: `alpha_history` (Historical Alpha Scores)
```sql
CREATE TABLE manuheadfund.alpha_history (
  id BIGSERIAL PRIMARY KEY,
  market TEXT NOT NULL UNIQUE,
  alpha_score NUMERIC(3,2),  -- 0-1
  win_rate NUMERIC(3,2),  -- 0-1
  n_samples INTEGER DEFAULT 0,
  avg_alpha NUMERIC(5,2),
  losing_to_btc BOOLEAN DEFAULT FALSE,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_alpha_history_market ON manuheadfund.alpha_history(market);
CREATE INDEX idx_alpha_history_updated ON manuheadfund.alpha_history(updated_at DESC);
```

### 4. Table: `beta_history` (Beta vs BTC)
```sql
CREATE TABLE manuheadfund.beta_history (
  id BIGSERIAL PRIMARY KEY,
  market TEXT NOT NULL UNIQUE,
  beta NUMERIC(5,4) NOT NULL,  -- 0.5-2.0 typical range
  window_days INTEGER DEFAULT 180,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_beta_history_market ON manuheadfund.beta_history(market);
CREATE INDEX idx_beta_history_updated ON manuheadfund.beta_history(updated_at DESC);
```

### 5. Table: `drawdown_history` (Drawdown vs Peak)
```sql
CREATE TABLE manuheadfund.drawdown_history (
  id BIGSERIAL PRIMARY KEY,
  market TEXT NOT NULL UNIQUE,
  price NUMERIC(20,8),
  peak_7d NUMERIC(20,8),
  vs_peak_pct NUMERIC(5,2),
  status TEXT,  -- OK, FLAGGED, CRITICAL
  flag_streak INTEGER DEFAULT 0,
  level TEXT,  -- GREEN, YELLOW, RED
  pct24h NUMERIC(5,2),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_drawdown_history_market ON manuheadfund.drawdown_history(market);
CREATE INDEX idx_drawdown_history_status ON manuheadfund.drawdown_history(status);
CREATE INDEX idx_drawdown_history_updated ON manuheadfund.drawdown_history(updated_at DESC);
```

### 6. Table: `regime_state` (Current Market Regime)
```sql
CREATE TABLE manuheadfund.regime_state (
  id BIGSERIAL PRIMARY KEY,
  phase TEXT NOT NULL,  -- phase_1_bull, phase_2_bull, phase_3_bear, etc
  bias TEXT,  -- BULL_STRONG, BULL_WEAK, BEAR_WEAK, BEAR_STRONG, NEUTRAL
  btc_drawdown_pct NUMERIC(5,2),
  macro_context TEXT,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_regime_state_updated ON manuheadfund.regime_state(updated_at DESC);
```

### 7. Table: `dsr_global` (Daily Sharpe Ratio & Performance)
```sql
CREATE TABLE manuheadfund.dsr_global (
  id BIGSERIAL PRIMARY KEY,
  market TEXT NOT NULL,
  dsr NUMERIC(5,4),  -- Daily Sharpe Ratio
  n_trials INTEGER DEFAULT 0,
  sharpe_30d NUMERIC(5,2),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(market, updated_at)
);

CREATE INDEX idx_dsr_global_market ON manuheadfund.dsr_global(market);
CREATE INDEX idx_dsr_global_updated ON manuheadfund.dsr_global(updated_at DESC);
```

## RLS Policies
All tables should have RLS enabled with policies allowing:
- Service role (GitHub Actions): Full CRUD
- Anon key (local app): Read-only

```sql
-- Example for fqs_registry
ALTER TABLE manuheadfund.fqs_registry ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access" ON manuheadfund.fqs_registry
  AS PERMISSIVE FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "Anon read-only" ON manuheadfund.fqs_registry
  AS PERMISSIVE FOR SELECT
  USING (auth.role() = 'anon');
```

## Migration Path
1. Create tables in Supabase
2. Migrate data from JSON files to Supabase
3. Update PowerShell code to read from Supabase (via state_store)
4. GitHub Actions writes to Supabase (not JSON files)
5. Local app reads from Supabase (fallback to local JSON if offline)

## Benefits
- ✅ Single source of truth (Supabase)
- ✅ Real-time sync between GitHub Actions and local
- ✅ No file sync issues
- ✅ Audit trail (created_at, updated_at)
- ✅ Scalable (supports 1000+ pairs)
- ✅ Accessible from anywhere (cloud + local)
