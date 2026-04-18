-- ============================================================================
-- Crypto Airdrop Farming System v4.0 — PostgreSQL Schema
-- ============================================================================
-- Database: farming_db
-- PostgreSQL Version: 15+
-- Total Tables: 30 (21 base + 3 personas + 6 protocols)
-- Total ENUMs: 14
-- Total Indexes: 35+
-- Created: 2026-02-24
-- ============================================================================

-- ============================================================================
-- SECTION 1: ENUM TYPES
-- ============================================================================

CREATE TYPE wallet_tier AS ENUM ('A', 'B', 'C');

CREATE TYPE persona_type AS ENUM (
    'ActiveTrader',
    'CasualUser',
    'WeekendWarrior',
    'Ghost',
    'MorningTrader',
    'NightOwl',
    'WeekdayOnly',
    'MonthlyActive',
    'BridgeMaxi',
    'DeFiDegen',
    'NFTCollector',
    'Governance'
);

CREATE TYPE wallet_status AS ENUM ('inactive', 'warming_up', 'active', 'paused', 'post_snapshot', 'compromised', 'retired');

CREATE TYPE tx_type AS ENUM (
    'SWAP',
    'BRIDGE',
    'STAKE',
    'LP',
    'NFT_MINT',
    'WRAP',
    'APPROVE',
    'CANCEL',
    'GOVERNANCE_VOTE',
    'GOVERNANCE_VOTE_DIRECT',
    'GITCOIN_DONATE',
    'POAP_CLAIM',
    'ENS_REGISTER',
    'SNAPSHOT_VOTE',
    'LENS_POST'
);

CREATE TYPE action_layer AS ENUM ('web3py', 'openclaw');

CREATE TYPE tx_status AS ENUM ('pending', 'submitted', 'confirmed', 'failed', 'cancelled', 'replaced');

CREATE TYPE gas_preference AS ENUM ('slow', 'normal', 'fast');

CREATE TYPE withdrawal_status AS ENUM ('planned', 'pending_approval', 'approved', 'executing', 'completed', 'rejected');

CREATE TYPE openclaw_task_status AS ENUM ('queued', 'running', 'completed', 'failed', 'skipped');

CREATE TYPE rpc_health_status AS ENUM ('healthy', 'degraded', 'down');

CREATE TYPE funding_withdrawal_status AS ENUM ('planned', 'requested', 'processing', 'completed', 'failed');

CREATE TYPE cex_exchange AS ENUM ('binance', 'bybit', 'okx', 'kucoin', 'mexc');

CREATE TYPE proxy_protocol AS ENUM ('http', 'https', 'socks5', 'socks5h');

CREATE TYPE event_severity AS ENUM ('info', 'warning', 'error', 'critical');

-- ============================================================================
-- SECTION 2: INFRASTRUCTURE TABLES
-- ============================================================================

-- Worker Nodes (3 Workers)
CREATE TABLE worker_nodes (
    id SERIAL PRIMARY KEY,
    worker_id INTEGER NOT NULL UNIQUE CHECK (worker_id BETWEEN 1 AND 3),
    hostname VARCHAR(255) NOT NULL,
    ip_address INET NOT NULL UNIQUE,
    location VARCHAR(100) NOT NULL, -- 'Amsterdam, NL' или 'Reykjavik, IS'
    timezone VARCHAR(50) NOT NULL, -- 'Europe/Amsterdam' или 'Atlantic/Reykjavik'
    utc_offset INTEGER NOT NULL, -- +1 для NL, 0 для IS
    status VARCHAR(50) DEFAULT 'active',
    last_heartbeat TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE worker_nodes IS 'Worker nodes configuration - 3 workers (1 NL, 2 IS)';
COMMENT ON COLUMN worker_nodes.worker_id IS 'Worker ID: 1 (NL), 2-3 (IS)';
COMMENT ON COLUMN worker_nodes.utc_offset IS 'UTC offset: +1 for NL, 0 for IS';

-- Proxy Pool (215 proxies: 30 IPRoyal NL + 100 Decodo IS + 85 Decodo CA)
CREATE TABLE proxy_pool (
    id SERIAL PRIMARY KEY,
    ip_address VARCHAR(255) NOT NULL, -- hostname для rotating: geo.iproyal.com, gate.decodo.com
    port INTEGER NOT NULL,
    protocol proxy_protocol NOT NULL,
    username VARCHAR(255) NOT NULL,
    password VARCHAR(255) NOT NULL,
    country_code VARCHAR(2) NOT NULL, -- 'NL' или 'IS'
    provider VARCHAR(50) NOT NULL, -- 'iproyal' или 'decodo'
    session_id VARCHAR(255), -- Уникальный session ID для sticky sessions
    is_active BOOLEAN DEFAULT TRUE,
    last_used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    -- Validation fields (added for proxy health tracking)
    validation_status VARCHAR(20) DEFAULT 'unknown', -- 'unknown', 'valid', 'invalid', 'checking'
    last_validated_at TIMESTAMPTZ,
    validation_error TEXT,
    response_time_ms INTEGER,
    detected_ip VARCHAR(45), -- IP detected during validation
    detected_country VARCHAR(2) -- Country detected during validation
);

COMMENT ON TABLE proxy_pool IS '215 proxies: 30 IPRoyal NL + 100 Decodo IS + 85 Decodo CA (v0.33.0)';
COMMENT ON COLUMN proxy_pool.session_id IS 'Sticky session ID (7 days for IPRoyal, 60 min for Decodo)';
COMMENT ON COLUMN proxy_pool.validation_status IS 'Proxy validation status: unknown, valid, invalid, checking';
COMMENT ON COLUMN proxy_pool.last_validated_at IS 'Last validation timestamp';
COMMENT ON COLUMN proxy_pool.validation_error IS 'Error message if validation failed';
COMMENT ON COLUMN proxy_pool.response_time_ms IS 'Proxy response time in milliseconds';
COMMENT ON COLUMN proxy_pool.detected_ip IS 'Exit IP detected during validation';
COMMENT ON COLUMN proxy_pool.detected_country IS 'Exit country detected during validation';

CREATE INDEX idx_proxy_pool_country_active ON proxy_pool(country_code, is_active);
CREATE INDEX idx_proxy_pool_provider ON proxy_pool(provider);
CREATE INDEX idx_proxy_pool_validation ON proxy_pool(validation_status, is_active);

-- ============================================================================
-- SECTION 3: CEX TABLES
-- ============================================================================

-- CEX Subaccounts (18 субаккаунтов: OKX-4, Binance-4, Bybit-4, KuCoin-3, MEXC-3)
CREATE TABLE cex_subaccounts (
    id SERIAL PRIMARY KEY,
    exchange cex_exchange NOT NULL,
    subaccount_name VARCHAR(255) NOT NULL,
    api_key TEXT NOT NULL, -- Encrypted с Fernet
    api_secret TEXT NOT NULL, -- Encrypted с Fernet
    api_passphrase TEXT, -- Только для OKX и KuCoin (encrypted)
    is_active BOOLEAN DEFAULT TRUE,
    withdrawal_network VARCHAR(50), -- Base, Polygon, Arbitrum, BNB Chain и т.д.
    balance_usdt DECIMAL(18, 8) DEFAULT 0,
    last_balance_check TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(exchange, subaccount_name)
);

COMMENT ON TABLE cex_subaccounts IS '18 subaccounts across 5 exchanges';
COMMENT ON COLUMN cex_subaccounts.api_key IS 'Encrypted with Fernet (funding/secrets.py)';
COMMENT ON COLUMN cex_subaccounts.withdrawal_network IS 'L2 network for withdrawals (NOT Ethereum mainnet!)';

CREATE INDEX idx_cex_subaccounts_exchange ON cex_subaccounts(exchange);
CREATE INDEX idx_cex_subaccounts_active ON cex_subaccounts(is_active);

-- Funding Chains (18 цепочек: каждая цепочка → 5 кошельков)
CREATE TABLE funding_chains (
    id SERIAL PRIMARY KEY,
    chain_number INTEGER NOT NULL UNIQUE CHECK (chain_number BETWEEN 1 AND 18),
    cex_subaccount_id INTEGER NOT NULL REFERENCES cex_subaccounts(id),
    withdrawal_network VARCHAR(50) NOT NULL,
    base_amount_usdt DECIMAL(10, 2) NOT NULL, --  Базовая сумма (будет варьироваться ±25%)
    wallets_count INTEGER DEFAULT 5,
    status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'in_progress', 'completed', 'paused'
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE funding_chains IS '18 funding chains, each funds 5 wallets with temporal isolation 60-240 min';
COMMENT ON COLUMN funding_chains.base_amount_usdt IS 'Base amount per wallet (actual will vary ±25%)';

CREATE INDEX idx_funding_chains_status ON funding_chains(status);

-- Funding Withdrawals (90 выводов: каждый кошелёк финансируется 1 раз)
CREATE TABLE funding_withdrawals (
    id SERIAL PRIMARY KEY,
    funding_chain_id INTEGER NOT NULL REFERENCES funding_chains(id),
    wallet_id INTEGER, -- Will reference wallets(id) after wallets table created
    cex_subaccount_id INTEGER NOT NULL REFERENCES cex_subaccounts(id),
    withdrawal_network VARCHAR(50) NOT NULL,
    amount_usdt DECIMAL(10, 4) NOT NULL, -- Точная сумма с ±25% шумом
    withdrawal_address VARCHAR(42) NOT NULL,
    cex_txid VARCHAR(255), -- Transaction ID from CEX
    blockchain_txhash VARCHAR(66), -- On-chain transaction hash
    status funding_withdrawal_status DEFAULT 'planned',
    delay_minutes INTEGER, -- Temporal isolation delay (60-240 min базовый, до 600 мин для "long pause")
    scheduled_at TIMESTAMPTZ,
    requested_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE funding_withdrawals IS '90 withdrawals from CEX to wallets with temporal isolation';
COMMENT ON COLUMN funding_withdrawals.delay_minutes IS 'Temporal isolation: 60-240 baseline, +20-60 if night, or 300-600 for "sleep pause"';

CREATE INDEX idx_funding_withdrawals_chain ON funding_withdrawals(funding_chain_id);
CREATE INDEX idx_funding_withdrawals_wallet ON funding_withdrawals(wallet_id);
CREATE INDEX idx_funding_withdrawals_status ON funding_withdrawals(status);

-- ============================================================================
-- SECTION 4: WALLETS TABLES
-- ============================================================================

-- Wallets (90 кошельков: 18 Tier A, 45 Tier B, 27 Tier C)
CREATE TABLE wallets (
    id SERIAL PRIMARY KEY,
    address VARCHAR(42) NOT NULL UNIQUE,
    encrypted_private_key TEXT NOT NULL, -- Fernet encrypted
    tier wallet_tier NOT NULL,
    worker_node_id INTEGER NOT NULL REFERENCES worker_nodes(id),
    proxy_id INTEGER NOT NULL REFERENCES proxy_pool(id),
    status wallet_status DEFAULT 'inactive',
    last_funded_at TIMESTAMPTZ, -- Когда получил средства с CEX (важно для "bridge emulation")
    first_tx_at TIMESTAMPTZ, -- Время первой транзакции (должно быть +2-4ч после last_funded_at)
    last_tx_at TIMESTAMPTZ,
    total_tx_count INTEGER DEFAULT 0,
    openclaw_enabled BOOLEAN DEFAULT FALSE, -- TRUE только для Tier A
    post_snapshot_active_until TIMESTAMPTZ, -- Продолжать активность 2-4 недели после snapshot
    reputation_score DECIMAL(5, 2) DEFAULT 0, -- Gitcoin Passport Score (цель: ≥25 для Tier A)
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT chk_address_format CHECK (address ~ '^0x[a-f0-9]{40}$'),
    CONSTRAINT chk_address_lowercase CHECK (address = LOWER(address))
);

COMMENT ON TABLE wallets IS '90 wallets: 18 Tier A (OpenClaw), 45 Tier B, 27 Tier C';
COMMENT ON COLUMN wallets.last_funded_at IS 'CEX funding time - used for 2-4h bridge emulation delay';
COMMENT ON COLUMN wallets.first_tx_at IS 'MUST be >= last_funded_at + 120-240 minutes (bridge delay)';
COMMENT ON COLUMN wallets.openclaw_enabled IS 'TRUE only for 18 Tier A wallets';

CREATE INDEX idx_wallets_tier ON wallets(tier);
CREATE INDEX idx_wallets_worker ON wallets(worker_node_id);
CREATE INDEX idx_wallets_status ON wallets(status);
CREATE INDEX idx_wallets_openclaw ON wallets(openclaw_enabled) WHERE openclaw_enabled = TRUE;

-- Wallet Personas (90 уникальных персон)
CREATE TABLE wallet_personas (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL UNIQUE REFERENCES wallets(id),
    persona_type persona_type NOT NULL,
    
    -- Temporal behavior
    preferred_hours INTEGER[] NOT NULL, -- Массив часов активности (по timezone воркера), например {8,9,10,14,15,16,18,19,20,21}
    tx_per_week_mean DECIMAL(4, 2) NOT NULL, -- µ для Gaussian (Tier A: 4.5, B: 2.5, C: 1.0)
    tx_per_week_stddev DECIMAL(4, 2) NOT NULL, -- σ для Gaussian (Tier A: 1.2, B: 0.8, C: 0.5)
    skip_week_probability DECIMAL(3, 2) DEFAULT 0.05, -- 5% шанс пропустить неделю
    
    -- Transaction type distribution (сумма = 1.0)
    tx_weight_swap DECIMAL(3, 2) NOT NULL, -- Типично 0.35-0.45
    tx_weight_bridge DECIMAL(3, 2) NOT NULL, -- Типично 0.20-0.30
    tx_weight_liquidity DECIMAL(3, 2) NOT NULL, -- Типично 0.15-0.25
    tx_weight_stake DECIMAL(3, 2) NOT NULL, -- Типично 0.05-0.15
    tx_weight_nft DECIMAL(3, 2) NOT NULL, -- Типично 0.02-0.08
    
    -- Risk tolerance
    slippage_tolerance DECIMAL(4, 2) NOT NULL, -- Уникальное: 0.33%-1.10%
    gas_preference gas_preference NOT NULL, -- 'slow', 'normal', 'fast' (с весами)
    gas_preference_weights JSONB NOT NULL, -- Например: {"slow": 0.2, "normal": 0.6, "fast": 0.2}
    
    -- Anti-Sybil noise parameters
    amount_noise_pct DECIMAL(3, 2) DEFAULT 0.05, -- ±3-8% шум к суммам транзакций
    time_noise_minutes INTEGER DEFAULT 10, -- ±10-25 минут шум к времени
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT chk_tx_weights_sum CHECK (
        ABS((tx_weight_swap + tx_weight_bridge + tx_weight_liquidity + tx_weight_stake + tx_weight_nft) - 1.00) < 0.01
    )
);

COMMENT ON TABLE wallet_personas IS '90 unique behavioral personas - CRITICAL for Anti-Sybil';
COMMENT ON COLUMN wallet_personas.preferred_hours IS 'Active hours array aligned with worker timezone (UTC+1 for NL, UTC+0 for IS)';
COMMENT ON COLUMN wallet_personas.slippage_tolerance IS 'Unique per wallet: 0.33%-1.10% to avoid clustering';
COMMENT ON COLUMN wallet_personas.amount_noise_pct IS 'Add ±3-8% noise to all transaction amounts';

CREATE INDEX idx_wallet_personas_type ON wallet_personas(persona_type);

-- Personas Config (4 архетипа-шаблона для генерации уникальных персон)
CREATE TABLE personas_config (
    id SERIAL PRIMARY KEY,
    persona_type persona_type NOT NULL UNIQUE,
    description TEXT,
    default_tx_per_week_mean DECIMAL(4, 2) NOT NULL,
    default_tx_per_week_stddev DECIMAL(4, 2) NOT NULL,
    default_preferred_hours_range INTEGER[] NOT NULL, -- Диапазон часов для выборки
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE personas_config IS 'Template archetypes for generating unique wallet personas (12 archetypes)';
-- NOTE: Seed data is in database/seeds/seed_personas_config.sql

-- ============================================================================
-- SECTION 5: PROTOCOLS TABLES
-- ============================================================================

-- Protocols (DeFi протоколы для фарминга)
CREATE TABLE protocols (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    category VARCHAR(100), -- 'DEX', 'Lending', 'Bridge', 'NFT Marketplace' и т.д.
    chains VARCHAR(100)[], -- Массив поддерживаемых сетей: ['base', 'arbitrum', 'optimism']
    has_points_program BOOLEAN DEFAULT FALSE,
    points_program_url TEXT,
    airdrop_announced BOOLEAN DEFAULT FALSE,
    airdrop_snapshot_date DATE,
    priority_score INTEGER DEFAULT 50, -- 0-100, используется LLM агентом
    is_active BOOLEAN DEFAULT TRUE,
    last_researched_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE protocols IS 'DeFi protocols discovered by LLM agent and manual input';
COMMENT ON COLUMN protocols.priority_score IS 'LLM-assigned priority (0-100) based on airdrop potential';

CREATE INDEX idx_protocols_active ON protocols(is_active);
CREATE INDEX idx_protocols_points ON protocols(has_points_program) WHERE has_points_program = TRUE;
CREATE INDEX idx_protocols_priority ON protocols(priority_score DESC);

-- Protocol Contracts (ABI и адреса контрактов)
CREATE TABLE protocol_contracts (
    id SERIAL PRIMARY KEY,
    protocol_id INTEGER NOT NULL REFERENCES protocols(id),
    chain VARCHAR(50) NOT NULL, -- 'base', 'arbitrum', 'optimism' и т.д.
    contract_type VARCHAR(100) NOT NULL, -- 'Router', 'Pool', 'Staking', 'NFT' и т.д.
    address VARCHAR(42) NOT NULL,
    abi_json JSONB, -- Полный ABI или основные функции
    is_verified BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    CONSTRAINT chk_contract_address CHECK (address ~ '^0x[a-f0-9]{40}$'),
    CONSTRAINT chk_contract_address_lowercase CHECK (address = LOWER(address)),
    UNIQUE(protocol_id, chain, contract_type)
);

COMMENT ON TABLE protocol_contracts IS 'Smart contracts for each protocol on supported chains';
COMMENT ON COLUMN protocol_contracts.abi_json IS 'Contract ABI (can be partial for common functions)';

CREATE INDEX idx_protocol_contracts_protocol ON protocol_contracts(protocol_id);
CREATE INDEX idx_protocol_contracts_chain ON protocol_contracts(chain);

-- Protocol Actions (Конкретные действия: swap, stake, add liquidity и т.д.)
CREATE TABLE protocol_actions (
    id SERIAL PRIMARY KEY,
    protocol_id INTEGER NOT NULL REFERENCES protocols(id),
    action_name VARCHAR(255) NOT NULL, -- 'swap_exact_eth_for_tokens', 'add_liquidity' и т.д.
    tx_type tx_type NOT NULL,
    layer action_layer NOT NULL, -- 'web3py' или 'openclaw'
    chain VARCHAR(50) NOT NULL,
    contract_id INTEGER REFERENCES protocol_contracts(id),
    function_signature TEXT, -- Для web3py: 'swapExactETHForTokens(uint256,address[],address,uint256)'
    default_params JSONB, -- Параметры по умолчанию
    min_amount_usdt DECIMAL(10, 4),
    max_amount_usdt DECIMAL(10, 4),
    estimated_gas_gwei INTEGER,
    points_multiplier DECIMAL(3, 2) DEFAULT 1.0, -- Если протокол даёт x2 points за это действие
    is_enabled BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(protocol_id, action_name, chain)
);

COMMENT ON TABLE protocol_actions IS 'Specific on-chain actions for each protocol';
COMMENT ON COLUMN protocol_actions.layer IS '"web3py" for direct RPC, "openclaw" for browser automation';
COMMENT ON COLUMN protocol_actions.points_multiplier IS 'Points boost (e.g., 2.0 for double points campaigns)';

CREATE INDEX idx_protocol_actions_protocol ON protocol_actions(protocol_id);
CREATE INDEX idx_protocol_actions_enabled ON protocol_actions(is_enabled);
CREATE INDEX idx_protocol_actions_layer ON protocol_actions(layer);

-- Chain RPC Endpoints (RPC URLs для каждой сети)
CREATE TABLE chain_rpc_endpoints (
    id SERIAL PRIMARY KEY,
    chain VARCHAR(50) NOT NULL,
    url TEXT NOT NULL,
    priority INTEGER DEFAULT 1, -- 1 = primary, 2 = fallback, и т.д.
    is_active BOOLEAN DEFAULT TRUE,
    last_used_at TIMESTAMPTZ,
    success_count INTEGER DEFAULT 0,
    failure_count INTEGER DEFAULT 0,
    avg_response_ms INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE chain_rpc_endpoints IS 'RPC URLs for each supported chain with failover';
COMMENT ON COLUMN chain_rpc_endpoints.priority IS '1=primary, 2=secondary fallback, etc.';

CREATE INDEX idx_chain_rpc_chain ON chain_rpc_endpoints(chain, priority);
CREATE INDEX idx_chain_rpc_active ON chain_rpc_endpoints(is_active);

-- Chain RPC Health Log (Мониторинг здоровья RPC)
CREATE TABLE chain_rpc_health_log (
    id SERIAL PRIMARY KEY,
    rpc_endpoint_id INTEGER NOT NULL REFERENCES chain_rpc_endpoints(id),
    status rpc_health_status NOT NULL,
    response_time_ms INTEGER,
    error_message TEXT,
    checked_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE chain_rpc_health_log IS 'RPC health monitoring log (retention: 7 days)';

CREATE INDEX idx_chain_rpc_health_endpoint ON chain_rpc_health_log(rpc_endpoint_id);
CREATE INDEX idx_chain_rpc_health_checked ON chain_rpc_health_log(checked_at);

-- ============================================================================
-- SECTION 6: POINTS & ACTIVITY TABLES
-- ============================================================================

-- Points Programs (Программы начисления points)
CREATE TABLE points_programs (
    id SERIAL PRIMARY KEY,
    protocol_id INTEGER NOT NULL REFERENCES protocols(id),
    program_name VARCHAR(255) NOT NULL,
    api_url TEXT, -- API для проверки баланса points (если есть публичный)
    check_method VARCHAR(50), -- 'api', 'contract', 'manual'
    multiplier_active BOOLEAN DEFAULT FALSE,
    multiplier_ends_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(protocol_id, program_name)
);

COMMENT ON TABLE points_programs IS 'Points loyalty programs (e.g., Blast Points, Scroll Marks)';

CREATE INDEX idx_points_programs_protocol ON points_programs(protocol_id);

-- Wallet Points Balances (Балансы points у кошельков)
CREATE TABLE wallet_points_balances (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL REFERENCES wallets(id),
    points_program_id INTEGER NOT NULL REFERENCES points_programs(id),
    points_amount DECIMAL(18, 2) DEFAULT 0,
    last_updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(wallet_id, points_program_id)
);

COMMENT ON TABLE wallet_points_balances IS 'Points balances for each wallet in each program';

CREATE INDEX idx_wallet_points_wallet ON wallet_points_balances(wallet_id);
CREATE INDEX idx_wallet_points_program ON wallet_points_balances(points_program_id);

-- Wallet Protocol Assignments (Какой кошелёк какие протоколы использует)
CREATE TABLE wallet_protocol_assignments (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL REFERENCES wallets(id),
    protocol_id INTEGER NOT NULL REFERENCES protocols(id),
    assigned_at TIMESTAMPTZ DEFAULT NOW(),
    interaction_count INTEGER DEFAULT 0,
    last_interaction_at TIMESTAMPTZ,
    
    UNIQUE(wallet_id, protocol_id)
);

COMMENT ON TABLE wallet_protocol_assignments IS 'Which protocols each wallet should interact with';

CREATE INDEX idx_wallet_protocol_wallet ON wallet_protocol_assignments(wallet_id);
CREATE INDEX idx_wallet_protocol_protocol ON wallet_protocol_assignments(protocol_id);

-- Scheduled Transactions (Запланированные транзакции)
CREATE TABLE scheduled_transactions (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL REFERENCES wallets(id),
    protocol_action_id INTEGER NOT NULL REFERENCES protocol_actions(id),
    tx_type tx_type NOT NULL,
    layer action_layer NOT NULL,
    scheduled_at TIMESTAMPTZ NOT NULL,
    amount_usdt DECIMAL(10, 4),
    params JSONB, -- Параметры транзакции (зависит от действия)
    status tx_status DEFAULT 'pending',
    tx_hash VARCHAR(66),
    gas_used BIGINT,
    gas_price_gwei DECIMAL(10, 2),
    error_message TEXT,
    executed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE scheduled_transactions IS 'Scheduled transactions queue from activity/scheduler.py';

CREATE INDEX idx_scheduled_tx_wallet ON scheduled_transactions(wallet_id);
CREATE INDEX idx_scheduled_tx_scheduled ON scheduled_transactions(scheduled_at);
CREATE INDEX idx_scheduled_tx_status ON scheduled_transactions(status);

-- Weekly Plans (Недельные планы транзакций по Gaussian распределению)
CREATE TABLE weekly_plans (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL REFERENCES wallets(id),
    week_start_date DATE NOT NULL,
    planned_tx_count INTEGER NOT NULL,
    actual_tx_count INTEGER DEFAULT 0,
    is_skipped BOOLEAN DEFAULT FALSE, -- skip_week_probability
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(wallet_id, week_start_date)
);

COMMENT ON TABLE weekly_plans IS 'Weekly transaction plans generated by Gaussian scheduler';

CREATE INDEX idx_weekly_plans_wallet ON weekly_plans(wallet_id);
CREATE INDEX idx_weekly_plans_week ON weekly_plans(week_start_date);

-- ============================================================================
-- SECTION 7: OPENCLAW TABLES
-- ============================================================================

-- OpenClaw Tasks (Задачи для OpenClaw — только Tier A)
CREATE TABLE openclaw_tasks (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL REFERENCES wallets(id),
    task_type VARCHAR(100) NOT NULL, -- 'gitcoin_donate', 'ens_register', 'poap_claim', 'snapshot_vote' и т.д.
    protocol_id INTEGER REFERENCES protocols(id),
    task_params JSONB, -- Параметры задачи (URL, адреса и т.д.)
    status openclaw_task_status DEFAULT 'queued',
    scheduled_at TIMESTAMPTZ NOT NULL,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE openclaw_tasks IS 'Browser automation tasks for 18 Tier A wallets via OpenClaw';

CREATE INDEX idx_openclaw_tasks_wallet ON openclaw_tasks(wallet_id);
CREATE INDEX idx_openclaw_tasks_status ON openclaw_tasks(status);
CREATE INDEX idx_openclaw_tasks_scheduled ON openclaw_tasks(scheduled_at);

-- OpenClaw Reputation (Репутация Tier A кошельков: Gitcoin Passport, ENS и т.д.)
CREATE TABLE openclaw_reputation (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL UNIQUE REFERENCES wallets(id),
    has_ens BOOLEAN DEFAULT FALSE,
    ens_name VARCHAR(255),
    gitcoin_passport_score DECIMAL(5, 2) DEFAULT 0, -- Цель: ≥25
    gitcoin_stamps_count INTEGER DEFAULT 0,
    poap_count INTEGER DEFAULT 0,
    snapshot_votes_count INTEGER DEFAULT 0,
    lens_profile BOOLEAN DEFAULT FALSE,
    total_donations_usdt DECIMAL(10, 2) DEFAULT 0, -- Gitcoin donations ($36 для Tier A)
    last_updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE openclaw_reputation IS 'On-chain reputation for 18 Tier A wallets';
COMMENT ON COLUMN openclaw_reputation.gitcoin_passport_score IS 'Target: ≥25 for strong Sybil resistance';

CREATE INDEX idx_openclaw_reputation_passport ON openclaw_reputation(gitcoin_passport_score);

-- ============================================================================
-- SECTION 8: AIRDROPS & WITHDRAWAL TABLES
-- ============================================================================

-- Airdrops (Обнаруженные аирдропы)
CREATE TABLE airdrops (
    id SERIAL PRIMARY KEY,
    protocol_id INTEGER REFERENCES protocols(id),
    token_symbol VARCHAR(50) NOT NULL,
    token_contract_address VARCHAR(42),
    chain VARCHAR(50) NOT NULL,
    announced_at DATE,
    snapshot_date DATE,
    claim_start_date DATE,
    claim_end_date DATE,
    total_allocation BIGINT,
    vesting_schedule TEXT,
    is_confirmed BOOLEAN DEFAULT FALSE, -- Подтверждён ли аирдроп (через CoinGecko или официальные каналы)
    confidence_score DECIMAL(3, 2), -- 0.0-1.0 от token_verifier.py
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE airdrops IS 'Detected airdrops by airdrop_detector.py';
COMMENT ON COLUMN airdrops.confidence_score IS 'Confidence from token_verifier.py (>0.6 triggers alert)';

CREATE INDEX idx_airdrops_protocol ON airdrops(protocol_id);
CREATE INDEX idx_airdrops_confirmed ON airdrops(is_confirmed);

-- Snapshot Events (Snapshot события для пост-snapshot активности)
CREATE TABLE snapshot_events (
    id SERIAL PRIMARY KEY,
    protocol_id INTEGER NOT NULL REFERENCES protocols(id),
    snapshot_date DATE NOT NULL,
    post_snapshot_duration_days INTEGER DEFAULT 21, -- 2-4 недели
    wallets_affected INTEGER[],
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE snapshot_events IS 'Protocol snapshot events for post-snapshot activity continuation';

CREATE INDEX idx_snapshot_events_protocol ON snapshot_events(protocol_id);
CREATE INDEX idx_snapshot_events_date ON snapshot_events(snapshot_date);

-- Withdrawal Plans (Планы вывода средств по Tier-стратегиям)
CREATE TABLE withdrawal_plans (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL REFERENCES wallets(id),
    tier wallet_tier NOT NULL,
    total_steps INTEGER NOT NULL, -- Tier A: 4, Tier B: 3, Tier C: 2
    current_step INTEGER DEFAULT 0,
    status withdrawal_status DEFAULT 'planned',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE withdrawal_plans IS 'Multi-stage withdrawal plans (A: 4 steps, B: 3, C: 2)';

CREATE INDEX idx_withdrawal_plans_wallet ON withdrawal_plans(wallet_id);
CREATE INDEX idx_withdrawal_plans_status ON withdrawal_plans(status);

-- Withdrawal Steps (Этапы вывода для каждого плана)
CREATE TABLE withdrawal_steps (
    id SERIAL PRIMARY KEY,
    withdrawal_plan_id INTEGER NOT NULL REFERENCES withdrawal_plans(id),
    step_number INTEGER NOT NULL,
    percentage DECIMAL(5, 2) NOT NULL, -- Процент от общей суммы
    destination_address VARCHAR(42) NOT NULL,
    status withdrawal_status DEFAULT 'planned',
    scheduled_at TIMESTAMPTZ,
    approved_at TIMESTAMPTZ,
    approved_by VARCHAR(100), -- Telegram username
    executed_at TIMESTAMPTZ,
    tx_hash VARCHAR(66),
    amount_usdt DECIMAL(10, 4),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(withdrawal_plan_id, step_number)
);

COMMENT ON TABLE withdrawal_steps IS 'Individual withdrawal steps requiring Telegram approval';

CREATE INDEX idx_withdrawal_steps_plan ON withdrawal_steps(withdrawal_plan_id);
CREATE INDEX idx_withdrawal_steps_status ON withdrawal_steps(status);

-- ============================================================================
-- SECTION 9: MONITORING TABLES
-- ============================================================================

-- Gas Snapshots (Мониторинг gas цен)
CREATE TABLE gas_snapshots (
    id SERIAL PRIMARY KEY,
    chain VARCHAR(50) NOT NULL,
    slow_gwei DECIMAL(10, 2) NOT NULL,
    normal_gwei DECIMAL(10, 2) NOT NULL,
    fast_gwei DECIMAL(10, 2) NOT NULL,
    block_number BIGINT,
    recorded_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE gas_snapshots IS 'Gas price monitoring for adaptive.py skip logic';

CREATE INDEX idx_gas_snapshots_chain ON gas_snapshots(chain);
CREATE INDEX idx_gas_snapshots_recorded ON gas_snapshots(recorded_at);

-- Protocol Research Reports (Отчёты LLM-агента по исследованию протоколов)
CREATE TABLE protocol_research_reports (
    id SERIAL PRIMARY KEY,
    run_date DATE NOT NULL,
    protocols_discovered INTEGER DEFAULT 0,
    protocols_updated INTEGER DEFAULT 0,
    llm_model VARCHAR(100), -- 'anthropic/claude-sonnet-4', 'openai/gpt-4' и т.д.
    execution_time_seconds INTEGER,
    report_summary TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE protocol_research_reports IS 'Weekly LLM agent reports (every Sunday 02:00 UTC)';

CREATE INDEX idx_protocol_research_date ON protocol_research_reports(run_date);

-- News Items (Новости из CryptoPanic)
CREATE TABLE news_items (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    url TEXT NOT NULL UNIQUE,
    source VARCHAR(255),
    published_at TIMESTAMPTZ,
    keywords VARCHAR(100)[], -- 'airdrop', 'points', 'layer 2' и т.д.
    relevance_score DECIMAL(3, 2), -- 0.0-1.0
    is_reviewed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE news_items IS 'Crypto news from CryptoPanic API analyzed by news_analyzer.py';

CREATE INDEX idx_news_items_published ON news_items(published_at DESC);
CREATE INDEX idx_news_items_relevance ON news_items(relevance_score DESC);

-- System Events (Системные события и алерты)
CREATE TABLE system_events (
    id SERIAL PRIMARY KEY,
    event_type VARCHAR(100) NOT NULL, -- 'worker_down', 'rpc_failure', 'funding_completed', 'airdrop_detected' и т.д.
    severity event_severity NOT NULL,
    component VARCHAR(100), -- 'worker_1', 'master_node', 'funding_engine' и т.д.
    message TEXT NOT NULL,
    metadata JSONB, -- Дополнительная информация
    telegram_sent BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE system_events IS 'System events log for monitoring and Telegram alerts';

CREATE INDEX idx_system_events_severity ON system_events(severity);
CREATE INDEX idx_system_events_created ON system_events(created_at);
CREATE INDEX idx_system_events_telegram ON system_events(telegram_sent) WHERE telegram_sent = FALSE;

-- Wallet Transactions (История транзакций)
CREATE TABLE wallet_transactions (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER REFERENCES wallets(id) ON DELETE CASCADE,
    protocol_action_id INTEGER REFERENCES protocol_actions(id) ON DELETE SET NULL,
    tx_hash VARCHAR(66) NOT NULL,
    chain VARCHAR(50) NOT NULL,
    from_address VARCHAR(42) NOT NULL,
    to_address VARCHAR(42),
    value NUMERIC,
    gas_used NUMERIC,
    status VARCHAR(20) NOT NULL,
    block_number INTEGER,
    confirmed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE wallet_transactions IS 'History of executed on-chain transactions';

CREATE INDEX idx_wallet_transactions_wallet_id ON wallet_transactions(wallet_id);
CREATE INDEX idx_wallet_transactions_tx_hash ON wallet_transactions(tx_hash);

-- Dry Run Logs (Логи симуляций)
CREATE TABLE dry_run_logs (
    id SERIAL PRIMARY KEY,
    wallet_address VARCHAR(42) NOT NULL,
    chain VARCHAR(50) NOT NULL,
    tx_type VARCHAR(50) NOT NULL,
    value NUMERIC,
    estimated_gas NUMERIC,
    estimated_cost_usd NUMERIC,
    would_succeed BOOLEAN NOT NULL,
    failure_reason TEXT,
    simulated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE dry_run_logs IS 'Logs of transaction simulations in dry-run mode';

CREATE INDEX idx_dry_run_logs_wallet_address ON dry_run_logs(wallet_address);

-- Safety Gates (Глобальные переключатели безопасности)
CREATE TABLE safety_gates (
    id SERIAL PRIMARY KEY,
    gate_name VARCHAR(50) UNIQUE NOT NULL,
    is_open BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE safety_gates IS 'Global safety switches for mainnet execution';

-- ============================================================================
-- SECTION 10: FOREIGN KEY CONSTRAINTS (DEFERRED)
-- ============================================================================

-- Add foreign key from funding_withdrawals to wallets (after wallets table exists)
ALTER TABLE funding_withdrawals
    ADD CONSTRAINT fk_funding_withdrawals_wallet
    FOREIGN KEY (wallet_id) REFERENCES wallets(id);

-- ============================================================================
-- SECTION 11: HELPER FUNCTIONS
-- ============================================================================

-- Function to update updated_at timestamp automatically
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to relevant tables
CREATE TRIGGER update_worker_nodes_updated_at BEFORE UPDATE ON worker_nodes FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_cex_subaccounts_updated_at BEFORE UPDATE ON cex_subaccounts FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_wallets_updated_at BEFORE UPDATE ON wallets FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_wallet_personas_updated_at BEFORE UPDATE ON wallet_personas FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_protocols_updated_at BEFORE UPDATE ON protocols FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_protocol_actions_updated_at BEFORE UPDATE ON protocol_actions FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_withdrawal_plans_updated_at BEFORE UPDATE ON withdrawal_plans FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- SECTION 12: DATA INITIALIZATION
-- ============================================================================

-- Insert Worker Nodes (3 workers будут добавлены через worker_setup.sh)
-- Placeholder: будет заполнено через setup скрипты

-- Personas Config (12 архетипов)
-- Заполняется через: database/seeds/seed_personas_config.sql

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================

-- Summary:
-- ✅ 30 tables created
-- ✅ 14 ENUM types defined
-- ✅ 35+ indexes created
-- ✅ Foreign key constraints applied
-- ✅ Triggers for auto-updating timestamps
-- ✅ Comments on all tables and critical columns
-- ✅ Anti-Sybil design: unique personas, temporal isolation, noise parameters

-- Next steps:
-- 1. Run: psql -U farming_user -d farming_db -f database/schema.sql
-- 2. Run: psql -U farming_user -d farming_db -f database/seeds/seed_personas_config.sql (12 archetypes)
-- 3. Run: psql -U farming_user -d farming_db -f database/seed_proxies.sql (90 proxies)
-- 4. Run: psql -U farming_user -d farming_db -f database/seed_cex_subaccounts.sql (18 subaccounts)
-- 5. Import: python database/db_manager.py (CRUD operations)
