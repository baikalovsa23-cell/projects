--
-- PostgreSQL database dump
--

\restrict nVwWFesRjQw0oVncWRBfkCt74q18ujm7UL2stvqhkpEUDUluaN4H2BNfXyD00tL

-- Dumped from database version 17.9 (Debian 17.9-0+deb13u1)
-- Dumped by pg_dump version 17.9 (Debian 17.9-0+deb13u1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: action_layer; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.action_layer AS ENUM (
    'web3py',
    'openclaw'
);


ALTER TYPE public.action_layer OWNER TO postgres;

--
-- Name: cex_exchange; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.cex_exchange AS ENUM (
    'binance',
    'bybit',
    'okx',
    'kucoin',
    'mexc'
);


ALTER TYPE public.cex_exchange OWNER TO postgres;

--
-- Name: event_severity; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.event_severity AS ENUM (
    'info',
    'warning',
    'error',
    'critical'
);


ALTER TYPE public.event_severity OWNER TO postgres;

--
-- Name: funding_withdrawal_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.funding_withdrawal_status AS ENUM (
    'planned',
    'requested',
    'processing',
    'completed',
    'failed'
);


ALTER TYPE public.funding_withdrawal_status OWNER TO postgres;

--
-- Name: gas_preference; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.gas_preference AS ENUM (
    'slow',
    'normal',
    'fast'
);


ALTER TYPE public.gas_preference OWNER TO postgres;

--
-- Name: openclaw_task_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.openclaw_task_status AS ENUM (
    'queued',
    'running',
    'completed',
    'failed',
    'skipped'
);


ALTER TYPE public.openclaw_task_status OWNER TO postgres;

--
-- Name: persona_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.persona_type AS ENUM (
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


ALTER TYPE public.persona_type OWNER TO postgres;

--
-- Name: proxy_protocol; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.proxy_protocol AS ENUM (
    'http',
    'https',
    'socks5',
    'socks5h'
);


ALTER TYPE public.proxy_protocol OWNER TO postgres;

--
-- Name: research_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.research_status AS ENUM (
    'pending_approval',
    'approved',
    'rejected',
    'auto_rejected',
    'duplicate'
);


ALTER TYPE public.research_status OWNER TO postgres;

--
-- Name: rpc_health_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.rpc_health_status AS ENUM (
    'healthy',
    'degraded',
    'down'
);


ALTER TYPE public.rpc_health_status OWNER TO postgres;

--
-- Name: tx_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.tx_status AS ENUM (
    'pending',
    'submitted',
    'confirmed',
    'failed',
    'cancelled',
    'replaced'
);


ALTER TYPE public.tx_status OWNER TO postgres;

--
-- Name: tx_type; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.tx_type AS ENUM (
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


ALTER TYPE public.tx_type OWNER TO postgres;

--
-- Name: wallet_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.wallet_status AS ENUM (
    'inactive',
    'warming_up',
    'active',
    'paused',
    'post_snapshot',
    'compromised',
    'retired'
);


ALTER TYPE public.wallet_status OWNER TO postgres;

--
-- Name: wallet_tier; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.wallet_tier AS ENUM (
    'A',
    'B',
    'C'
);


ALTER TYPE public.wallet_tier OWNER TO postgres;

--
-- Name: withdrawal_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.withdrawal_status AS ENUM (
    'planned',
    'pending_approval',
    'approved',
    'executing',
    'completed',
    'rejected'
);


ALTER TYPE public.withdrawal_status OWNER TO postgres;

--
-- Name: approve_protocol(integer, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.approve_protocol(pending_id integer, approved_by_user character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    protocol_data RECORD;
    new_protocol_id INTEGER;
BEGIN
    -- Fetch pending protocol
    SELECT * INTO protocol_data
    FROM protocol_research_pending
    WHERE id = pending_id AND status = 'pending_approval';
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Protocol ID % not found or already processed', pending_id;
    END IF;
    
    -- Calculate final priority score with bridge penalty
    -- (stored in priority_score column of protocols table)
    
    -- Insert into protocols table (including bridge fields)
    INSERT INTO protocols (
        name,
        category,
        chains,
        has_points_program,
        points_program_url,
        priority_score,
        is_active,
        last_researched_at,
        -- Bridge fields (added in migration 031)
        bridge_required,
        bridge_from_network,
        bridge_provider,
        bridge_cost_usd,
        cex_support
    ) VALUES (
        protocol_data.name,
        protocol_data.category,
        protocol_data.chains,
        protocol_data.has_points_program,
        protocol_data.points_program_url,
        calculate_final_priority_score(
            protocol_data.airdrop_score,
            protocol_data.bridge_required,
            protocol_data.bridge_cost_usd,
            protocol_data.bridge_safety_score
        ),
        TRUE,
        NOW(),
        -- Bridge fields
        protocol_data.bridge_required,
        protocol_data.bridge_from_network,
        protocol_data.bridge_provider,
        protocol_data.bridge_cost_usd,
        protocol_data.cex_support
    )
    RETURNING id INTO new_protocol_id;
    
    -- Update pending status
    UPDATE protocol_research_pending
    SET 
        status = 'approved',
        approved_by = approved_by_user,
        approved_at = NOW(),
        updated_at = NOW()
    WHERE id = pending_id;
    
    RETURN new_protocol_id;
END;
$$;


ALTER FUNCTION public.approve_protocol(pending_id integer, approved_by_user character varying) OWNER TO postgres;

--
-- Name: auto_reject_stale_protocols(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.auto_reject_stale_protocols() RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    rejected_count INTEGER;
BEGIN
    UPDATE protocol_research_pending
    SET 
        status = 'auto_rejected',
        rejected_reason = 'Auto-rejected: No action taken within 7 days',
        rejected_at = NOW(),
        updated_at = NOW()
    WHERE 
        status = 'pending_approval'
        AND created_at < NOW() - INTERVAL '7 days';
    
    GET DIAGNOSTICS rejected_count = ROW_COUNT;
    
    -- Log the cleanup
    IF rejected_count > 0 THEN
        INSERT INTO research_logs (
            cycle_start_at,
            cycle_end_at,
            status,
            protocols_auto_rejected,
            summary_report
        ) VALUES (
            NOW(),
            NOW(),
            'completed',
            rejected_count,
            FORMAT('Auto-rejected %s stale protocols (older than 7 days)', rejected_count)
        );
    END IF;
    
    RETURN rejected_count;
END;
$$;


ALTER FUNCTION public.auto_reject_stale_protocols() OWNER TO postgres;

--
-- Name: auto_reject_stale_unreachable_protocols(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.auto_reject_stale_unreachable_protocols() RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    rejected_count INTEGER;
BEGIN
    UPDATE protocol_research_pending
    SET 
        status = 'auto_rejected',
        rejected_reason = 'Bridge unavailable for 30 days (4 recheck attempts)',
        rejected_at = NOW(),
        updated_at = NOW()
    WHERE 
        bridge_available = FALSE
        AND bridge_recheck_count >= 4
        AND status = 'pending_approval';
    
    GET DIAGNOSTICS rejected_count = ROW_COUNT;
    
    IF rejected_count > 0 THEN
        INSERT INTO research_logs (
            cycle_start_at,
            cycle_end_at,
            status,
            protocols_auto_rejected,
            summary_report
        ) VALUES (
            NOW(),
            NOW(),
            'completed',
            rejected_count,
            FORMAT('Auto-rejected %s unreachable protocols (no bridge for 30 days)', rejected_count)
        );
    END IF;
    
    RETURN rejected_count;
END;
$$;


ALTER FUNCTION public.auto_reject_stale_unreachable_protocols() OWNER TO postgres;

--
-- Name: FUNCTION auto_reject_stale_unreachable_protocols(); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.auto_reject_stale_unreachable_protocols() IS 'Auto-rejects protocols that have been unreachable for 30+ days (4 recheck attempts).';


--
-- Name: calculate_bridge_safety_score(bigint, integer, integer, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_bridge_safety_score(p_tvl_usd bigint, p_rank integer, p_hacks_count integer DEFAULT 0, p_is_verified boolean DEFAULT true) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
DECLARE
    v_score INTEGER := 0;
BEGIN
    -- TVL score (40 points max)
    IF p_tvl_usd >= 100000000 THEN        -- $100M+
        v_score := v_score + 40;
    ELSIF p_tvl_usd >= 50000000 THEN      -- $50M+
        v_score := v_score + 35;
    ELSIF p_tvl_usd >= 10000000 THEN      -- $10M+
        v_score := v_score + 25;
    ELSIF p_tvl_usd >= 5000000 THEN       -- $5M+
        v_score := v_score + 15;
    END IF;
    
    -- Rank score (30 points max)
    IF p_rank <= 5 THEN
        v_score := v_score + 30;
    ELSIF p_rank <= 10 THEN
        v_score := v_score + 25;
    ELSIF p_rank <= 25 THEN
        v_score := v_score + 20;
    ELSIF p_rank <= 50 THEN
        v_score := v_score + 15;
    END IF;
    
    -- No hacks (20 points)
    IF p_hacks_count = 0 THEN
        v_score := v_score + 20;
    ELSE
        v_score := v_score - (p_hacks_count * 10);  -- -10 per hack
    END IF;
    
    -- Verified contract (10 points)
    IF p_is_verified THEN
        v_score := v_score + 10;
    END IF;
    
    -- Clamp to 0-100
    RETURN GREATEST(0, LEAST(100, v_score));
END;
$_$;


ALTER FUNCTION public.calculate_bridge_safety_score(p_tvl_usd bigint, p_rank integer, p_hacks_count integer, p_is_verified boolean) OWNER TO postgres;

--
-- Name: FUNCTION calculate_bridge_safety_score(p_tvl_usd bigint, p_rank integer, p_hacks_count integer, p_is_verified boolean); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.calculate_bridge_safety_score(p_tvl_usd bigint, p_rank integer, p_hacks_count integer, p_is_verified boolean) IS 'Calculate bridge safety score 0-100 based on TVL, rank, hacks, verification';


--
-- Name: calculate_final_priority_score(integer, boolean, numeric, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_final_priority_score(p_airdrop_score integer, p_bridge_required boolean DEFAULT false, p_bridge_cost_usd numeric DEFAULT NULL::numeric, p_bridge_safety_score integer DEFAULT NULL::integer) RETURNS integer
    LANGUAGE plpgsql
    AS $_$
DECLARE
    v_base_score INTEGER := p_airdrop_score;
    v_bridge_penalty INTEGER := 0;
    v_cost_penalty INTEGER := 0;
    v_safety_penalty INTEGER := 0;
    v_final_score INTEGER;
BEGIN
    -- Only apply penalty if bridge is required
    IF p_bridge_required THEN
        -- Cost penalty: $1 = -2 points, max -10
        IF p_bridge_cost_usd IS NOT NULL THEN
            v_cost_penalty := LEAST(10, FLOOR(p_bridge_cost_usd * 2));
        END IF;
        
        -- Safety penalty: lower safety = higher penalty
        -- 100 safety = 0 penalty, 50 safety = -5 penalty, 0 safety = -10 penalty
        IF p_bridge_safety_score IS NOT NULL THEN
            v_safety_penalty := GREATEST(0, (100 - p_bridge_safety_score) / 10);
        END IF;
        
        v_bridge_penalty := v_cost_penalty + v_safety_penalty;
    END IF;
    
    v_final_score := GREATEST(0, v_base_score - v_bridge_penalty);
    
    RETURN v_final_score;
END;
$_$;


ALTER FUNCTION public.calculate_final_priority_score(p_airdrop_score integer, p_bridge_required boolean, p_bridge_cost_usd numeric, p_bridge_safety_score integer) OWNER TO postgres;

--
-- Name: cleanup_all_expired_cache(); Type: FUNCTION; Schema: public; Owner: farming_user
--

CREATE FUNCTION public.cleanup_all_expired_cache() RETURNS TABLE(cache_type text, deleted_count integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY SELECT 'cex_networks'::TEXT, cleanup_expired_cex_cache();
    RETURN QUERY SELECT 'defillama_bridges'::TEXT, cleanup_expired_defillama_cache();
    RAISE NOTICE 'Cache cleanup completed';
END;
$$;


ALTER FUNCTION public.cleanup_all_expired_cache() OWNER TO farming_user;

--
-- Name: cleanup_expired_cex_cache(); Type: FUNCTION; Schema: public; Owner: farming_user
--

CREATE FUNCTION public.cleanup_expired_cex_cache() RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    DELETE FROM cex_networks_cache
    WHERE expires_at < NOW() AND is_stale = FALSE;
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RAISE NOTICE 'Cleaned % expired CEX cache entries', v_deleted_count;
    RETURN v_deleted_count;
END;
$$;


ALTER FUNCTION public.cleanup_expired_cex_cache() OWNER TO farming_user;

--
-- Name: cleanup_expired_defillama_cache(); Type: FUNCTION; Schema: public; Owner: farming_user
--

CREATE FUNCTION public.cleanup_expired_defillama_cache() RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_deleted_count INTEGER;
BEGIN
    DELETE FROM defillama_bridges_cache
    WHERE expires_at < NOW();
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    RAISE NOTICE 'Cleaned % expired DeFiLlama cache entries', v_deleted_count;
    RETURN v_deleted_count;
END;
$$;


ALTER FUNCTION public.cleanup_expired_defillama_cache() OWNER TO farming_user;

--
-- Name: clear_expired_token_cache(); Type: FUNCTION; Schema: public; Owner: farming_user
--

CREATE FUNCTION public.clear_expired_token_cache() RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM token_check_cache 
    WHERE checked_at < NOW() - INTERVAL '24 hours';
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    RETURN deleted_count;
END;
$$;


ALTER FUNCTION public.clear_expired_token_cache() OWNER TO farming_user;

--
-- Name: FUNCTION clear_expired_token_cache(); Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON FUNCTION public.clear_expired_token_cache() IS 'Removes token cache entries older than 24 hours - returns count of deleted rows';


--
-- Name: get_active_farming_chains(); Type: FUNCTION; Schema: public; Owner: farming_user
--

CREATE FUNCTION public.get_active_farming_chains() RETURNS TABLE(chain character varying, farm_status character varying, token_ticker character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT 
        cre.chain::VARCHAR,
        cre.farm_status::VARCHAR,
        cre.token_ticker::VARCHAR
    FROM chain_rpc_endpoints cre
    WHERE cre.farm_status IN ('ACTIVE', 'TARGET')
      AND cre.is_active = TRUE
    ORDER BY cre.chain;
END;
$$;


ALTER FUNCTION public.get_active_farming_chains() OWNER TO farming_user;

--
-- Name: FUNCTION get_active_farming_chains(); Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON FUNCTION public.get_active_farming_chains() IS 'Returns list of chains with ACTIVE or TARGET farm_status for protocol filtering';


--
-- Name: get_cex_cached_networks(character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_cex_cached_networks(p_cex_name character varying, p_coin character varying DEFAULT 'ETH'::character varying) RETURNS TABLE(supported_networks jsonb, is_stale boolean, fetched_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.supported_networks,
        c.is_stale,
        c.fetched_at
    FROM cex_networks_cache c
    WHERE c.cex_name = p_cex_name
      AND c.coin = p_coin
      AND (c.expires_at > NOW() OR c.is_stale = TRUE)  -- Return even if stale (fallback)
    LIMIT 1;
END;
$$;


ALTER FUNCTION public.get_cex_cached_networks(p_cex_name character varying, p_coin character varying) OWNER TO postgres;

--
-- Name: FUNCTION get_cex_cached_networks(p_cex_name character varying, p_coin character varying); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.get_cex_cached_networks(p_cex_name character varying, p_coin character varying) IS 'Get cached CEX networks (returns stale cache if fresh not available)';


--
-- Name: get_recent_airdrops(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_recent_airdrops(hours_ago integer DEFAULT 24) RETURNS TABLE(wallet_id integer, chain character varying, token_symbol character varying, balance_human numeric, first_detected_at timestamp with time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        wt.wallet_id,
        wt.chain,
        wt.token_symbol,
        wt.balance_human,
        wt.first_detected_at
    FROM wallet_tokens wt
    WHERE wt.first_detected_at >= NOW() - INTERVAL '1 hour' * hours_ago
      AND wt.balance_human > 0
    ORDER BY wt.first_detected_at DESC;
END;
$$;


ALTER FUNCTION public.get_recent_airdrops(hours_ago integer) OWNER TO postgres;

--
-- Name: FUNCTION get_recent_airdrops(hours_ago integer); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.get_recent_airdrops(hours_ago integer) IS 'Get tokens detected in last N hours (default 24h)';


--
-- Name: get_scan_statistics(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_scan_statistics(last_n_scans integer DEFAULT 10) RETURNS TABLE(scan_id integer, scan_date timestamp with time zone, duration_sec numeric, wallets_scanned integer, new_tokens integer, api_errors integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        asl.id,
        asl.scan_start_at,
        asl.scan_duration_seconds,
        asl.total_wallets_scanned,
        asl.new_tokens_detected,
        asl.api_errors_encountered
    FROM airdrop_scan_logs asl
    WHERE asl.status = 'completed'
    ORDER BY asl.scan_start_at DESC
    LIMIT last_n_scans;
END;
$$;


ALTER FUNCTION public.get_scan_statistics(last_n_scans integer) OWNER TO postgres;

--
-- Name: FUNCTION get_scan_statistics(last_n_scans integer); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.get_scan_statistics(last_n_scans integer) IS 'Get statistics for last N scan cycles (default 10)';


--
-- Name: get_unreachable_protocols_for_recheck(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_unreachable_protocols_for_recheck() RETURNS TABLE(id integer, name character varying, chain character varying, bridge_from_network character varying, bridge_recheck_count integer, airdrop_score integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        prp.id,
        prp.name,
        prp.chains[1] as chain,
        prp.bridge_from_network,
        prp.bridge_recheck_count,
        prp.airdrop_score
    FROM protocol_research_pending prp
    WHERE prp.bridge_available = FALSE
      AND prp.status = 'pending_approval'
      AND prp.bridge_recheck_after <= NOW()
      AND prp.bridge_recheck_count < 4
    ORDER BY prp.airdrop_score DESC;
END;
$$;


ALTER FUNCTION public.get_unreachable_protocols_for_recheck() OWNER TO postgres;

--
-- Name: FUNCTION get_unreachable_protocols_for_recheck(); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.get_unreachable_protocols_for_recheck() IS 'Returns unreachable protocols that need bridge recheck. Max 4 attempts (30 days).';


--
-- Name: get_wallet_funding_source_address(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_wallet_funding_source_address(p_wallet_id integer) RETURNS character varying
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_cex_withdrawal_address VARCHAR(42);
BEGIN
    -- Get CEX subaccount withdrawal address that funded this wallet
    SELECT cs.withdrawal_address
    INTO v_cex_withdrawal_address
    FROM funding_withdrawals fw
    JOIN funding_chains fc ON fw.funding_chain_id = fc.id
    JOIN cex_subaccounts cs ON fc.cex_subaccount_id = cs.id
    WHERE fw.wallet_id = p_wallet_id
      AND fw.status = 'completed'
    LIMIT 1;
    
    RETURN v_cex_withdrawal_address;
END;
$$;


ALTER FUNCTION public.get_wallet_funding_source_address(p_wallet_id integer) OWNER TO postgres;

--
-- Name: FUNCTION get_wallet_funding_source_address(p_wallet_id integer); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.get_wallet_funding_source_address(p_wallet_id integer) IS 'Returns the CEX subaccount withdrawal address that originally funded this wallet.
     This is the address that should be set as authorized_withdrawal_address.
     Returns NULL if wallet not funded yet.';


--
-- Name: initialize_authorized_withdrawal_addresses(); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.initialize_authorized_withdrawal_addresses()
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_wallet_record RECORD;
    v_source_address VARCHAR(42);
    v_update_count INTEGER := 0;
BEGIN
    -- Loop through all funded wallets without authorized_withdrawal_address
    FOR v_wallet_record IN
        SELECT w.id, w.address
        FROM wallets w
        WHERE w.authorized_withdrawal_address IS NULL
          AND w.last_funded_at IS NOT NULL
    LOOP
        -- Get funding source address
        v_source_address := get_wallet_funding_source_address(v_wallet_record.id);
        
        IF v_source_address IS NOT NULL THEN
            -- Set session variables for audit trigger
            PERFORM set_config('app.username', 'migration_019', FALSE);
            PERFORM set_config('app.change_reason', 'Initial setup during migration 019', FALSE);
            
            -- Update wallet
            UPDATE wallets
            SET authorized_withdrawal_address = v_source_address
            WHERE id = v_wallet_record.id;
            
            v_update_count := v_update_count + 1;
            
            RAISE NOTICE 'Set authorized address for wallet % to %', 
                         v_wallet_record.id, v_source_address;
        ELSE
            RAISE WARNING 'Could not determine funding source for wallet %', 
                          v_wallet_record.id;
        END IF;
    END LOOP;
    
    RAISE NOTICE 'Initialized authorized_withdrawal_address for % wallets', v_update_count;
END;
$$;


ALTER PROCEDURE public.initialize_authorized_withdrawal_addresses() OWNER TO postgres;

--
-- Name: PROCEDURE initialize_authorized_withdrawal_addresses(); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON PROCEDURE public.initialize_authorized_withdrawal_addresses() IS 'One-time migration procedure to populate authorized_withdrawal_address for existing funded wallets.
     Looks up CEX subaccount that funded each wallet and sets it as authorized address.
     Run after migration to fix existing wallets.';


--
-- Name: is_bridge_safe(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.is_bridge_safe(p_safety_score integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN p_safety_score >= 60;  -- 60+ = auto-approve
END;
$$;


ALTER FUNCTION public.is_bridge_safe(p_safety_score integer) OWNER TO postgres;

--
-- Name: FUNCTION is_bridge_safe(p_safety_score integer); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.is_bridge_safe(p_safety_score integer) IS 'Returns TRUE if bridge safety score >= 60 (auto-approve threshold)';


--
-- Name: log_authorized_withdrawal_address_change(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.log_authorized_withdrawal_address_change() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Only log if authorized_withdrawal_address changed
    IF (TG_OP = 'UPDATE' AND OLD.authorized_withdrawal_address IS DISTINCT FROM NEW.authorized_withdrawal_address) 
       OR (TG_OP = 'INSERT' AND NEW.authorized_withdrawal_address IS NOT NULL) THEN
        
        INSERT INTO wallet_withdrawal_address_history (
            wallet_id,
            old_address,
            new_address,
            changed_by,
            change_reason,
            approval_status
        ) VALUES (
            NEW.id,
            OLD.authorized_withdrawal_address,  -- NULL for INSERT
            NEW.authorized_withdrawal_address,
            COALESCE(current_setting('app.username', TRUE), 'system'),
            COALESCE(current_setting('app.change_reason', TRUE), 'Automatic update'),
            'approved'  -- System changes are pre-approved
        );
    END IF;
    
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.log_authorized_withdrawal_address_change() OWNER TO postgres;

--
-- Name: FUNCTION log_authorized_withdrawal_address_change(); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.log_authorized_withdrawal_address_change() IS 'Trigger function to automatically log all changes to authorized_withdrawal_address.
     Creates audit trail entry in wallet_withdrawal_address_history.';


--
-- Name: quick_isolation_check(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.quick_isolation_check() RETURNS json
    LANGUAGE plpgsql
    AS $$
DECLARE
    result JSON;
    critical_count INTEGER;
    high_count INTEGER;
    total_issues INTEGER;
BEGIN
    -- Count issues by severity
    SELECT 
        COUNT(*) FILTER (WHERE severity = 'CRITICAL') as critical,
        COUNT(*) FILTER (WHERE severity = 'HIGH') as high,
        COUNT(*) as total
    INTO critical_count, high_count, total_issues
    FROM validate_funding_isolation();
    
    -- Return summary
    result := json_build_object(
        'timestamp', NOW(),
        'total_issues', total_issues,
        'critical', critical_count,
        'high', high_count,
        'status', CASE 
            WHEN critical_count > 0 THEN 'CRITICAL'
            WHEN high_count > 0 THEN 'WARNING'
            ELSE 'OK'
        END
    );
    
    RETURN result;
END;
$$;


ALTER FUNCTION public.quick_isolation_check() OWNER TO postgres;

--
-- Name: FUNCTION quick_isolation_check(); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.quick_isolation_check() IS 'Returns JSON summary of isolation status (for monitoring)';


--
-- Name: rollback_migration_026(); Type: FUNCTION; Schema: public; Owner: farming_user
--

CREATE FUNCTION public.rollback_migration_026() RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_result TEXT := 'Rollback completed (partial - v3.0 architecture preserved)';
BEGIN
    -- NOTE: v3.0 architecture uses direct CEX → wallet funding
    -- Intermediate wallets are DEPRECATED and will NOT be restored
    
    DROP VIEW IF EXISTS v_direct_funding_schedule;
    DROP VIEW IF EXISTS v_funding_interleave_quality;
    DROP VIEW IF EXISTS v_funding_temporal_distribution;
    
    DROP FUNCTION IF EXISTS validate_direct_funding_schedule();
    
    DROP INDEX IF EXISTS idx_funding_withdrawals_cex_scheduled;
    DROP INDEX IF EXISTS idx_funding_withdrawals_interleave;
    DROP INDEX IF EXISTS idx_funding_withdrawals_completed;
    
    DELETE FROM schema_migrations WHERE version = '026';
    
    RAISE NOTICE 'Migration 026 rolled back (partial)';
    RAISE NOTICE 'Direct funding architecture (v3.0) preserved';
    RAISE NOTICE 'Intermediate wallets remain DEPRECATED';
    
    RETURN v_result;
END;
$$;


ALTER FUNCTION public.rollback_migration_026() OWNER TO farming_user;

--
-- Name: update_cex_cache_expires(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_cex_cache_expires() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.expires_at = NEW.fetched_at + INTERVAL '24 hours';
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_cex_cache_expires() OWNER TO postgres;

--
-- Name: update_defillama_cache_expires(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_defillama_cache_expires() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.expires_at = NEW.fetched_at + INTERVAL '6 hours';
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_defillama_cache_expires() OWNER TO postgres;

--
-- Name: update_openclaw_profiles_updated_at(); Type: FUNCTION; Schema: public; Owner: farming_user
--

CREATE FUNCTION public.update_openclaw_profiles_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_openclaw_profiles_updated_at() OWNER TO farming_user;

--
-- Name: update_openclaw_tasks_updated_at(); Type: FUNCTION; Schema: public; Owner: farming_user
--

CREATE FUNCTION public.update_openclaw_tasks_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_openclaw_tasks_updated_at() OWNER TO farming_user;

--
-- Name: update_protocol_bridge_info(integer, boolean, character varying, numeric, integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_protocol_bridge_info(p_protocol_id integer, p_bridge_available boolean, p_bridge_provider character varying DEFAULT NULL::character varying, p_bridge_cost_usd numeric DEFAULT NULL::numeric, p_bridge_safety_score integer DEFAULT NULL::integer, p_unreachable_reason text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF p_bridge_available THEN
        -- Bridge became available
        UPDATE protocol_research_pending
        SET 
            bridge_available = TRUE,
            bridge_provider = p_bridge_provider,
            bridge_cost_usd = p_bridge_cost_usd,
            bridge_safety_score = p_bridge_safety_score,
            bridge_checked_at = NOW(),
            bridge_unreachable_reason = NULL,
            bridge_recheck_after = NULL
        WHERE id = p_protocol_id;
    ELSE
        -- Still unreachable - increment count and set next recheck
        UPDATE protocol_research_pending
        SET 
            bridge_available = FALSE,
            bridge_unreachable_reason = p_unreachable_reason,
            bridge_checked_at = NOW(),
            bridge_recheck_count = bridge_recheck_count + 1,
            bridge_recheck_after = NOW() + INTERVAL '7 days'
        WHERE id = p_protocol_id;
    END IF;
END;
$$;


ALTER FUNCTION public.update_protocol_bridge_info(p_protocol_id integer, p_bridge_available boolean, p_bridge_provider character varying, p_bridge_cost_usd numeric, p_bridge_safety_score integer, p_unreachable_reason text) OWNER TO postgres;

--
-- Name: update_research_timestamp(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_research_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_research_timestamp() OWNER TO postgres;

--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_updated_at_column() OWNER TO postgres;

--
-- Name: update_wallet_token_timestamp(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_wallet_token_timestamp() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.last_updated = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_wallet_token_timestamp() OWNER TO postgres;

--
-- Name: validate_all_authorized_addresses(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validate_all_authorized_addresses() RETURNS TABLE(wallet_id integer, wallet_address character varying, issue_type character varying, issue_description text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Issue 1: Funded wallet without authorized address
    RETURN QUERY
    SELECT 
        w.id,
        w.address,
        'MISSING_AUTHORIZED_ADDRESS'::VARCHAR,
        'Wallet funded but authorized_withdrawal_address not set'::TEXT
    FROM wallets w
    WHERE w.last_funded_at IS NOT NULL
      AND w.authorized_withdrawal_address IS NULL;
    
    -- Issue 2: Authorized address is burn address
    RETURN QUERY
    SELECT 
        w.id,
        w.address,
        'BURN_ADDRESS'::VARCHAR,
        'Authorized address is burn address: ' || w.authorized_withdrawal_address
    FROM wallets w
    WHERE w.authorized_withdrawal_address IN (
        '0x0000000000000000000000000000000000000000',
        '0x000000000000000000000000000000000000dead',
        '0xdead000000000000000042069420694206942069'
    );
    
    -- Issue 3: Authorized address doesn't match funding source
    RETURN QUERY
    SELECT 
        w.id,
        w.address,
        'ADDRESS_MISMATCH'::VARCHAR,
        'Authorized address does not match funding source: ' || 
        w.authorized_withdrawal_address || ' vs ' || 
        COALESCE(get_wallet_funding_source_address(w.id), 'NULL')
    FROM wallets w
    WHERE w.authorized_withdrawal_address IS NOT NULL
      AND w.authorized_withdrawal_address != COALESCE(get_wallet_funding_source_address(w.id), '');
END;
$$;


ALTER FUNCTION public.validate_all_authorized_addresses() OWNER TO postgres;

--
-- Name: FUNCTION validate_all_authorized_addresses(); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.validate_all_authorized_addresses() IS 'Security audit function. Returns all wallets with authorized address  issues.
     Run periodically to detect configuration drift or security violations.';


--
-- Name: validate_cluster_size_distribution(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validate_cluster_size_distribution() RETURNS TABLE(cluster_size integer, chain_count bigint, percentage numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        fc.actual_wallet_count AS cluster_size,
        COUNT(*) AS chain_count,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage
    FROM funding_chains fc
    GROUP BY fc.actual_wallet_count
    ORDER BY fc.actual_wallet_count;
END;
$$;


ALTER FUNCTION public.validate_cluster_size_distribution() OWNER TO postgres;

--
-- Name: FUNCTION validate_cluster_size_distribution(); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.validate_cluster_size_distribution() IS 'Returns distribution of cluster sizes. Should have variety (3,4,5,6,7), not all 5.';


--
-- Name: validate_consolidation_clusters(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validate_consolidation_clusters() RETURNS TABLE(intermediate_wallet_address character varying, source_wallet_count integer, funding_chain_number integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        icw.address AS intermediate_wallet_address,
        array_length(icw.source_wallet_ids, 1) AS source_wallet_count,
        fc.chain_number AS funding_chain_number
    FROM intermediate_consolidation_wallets icw
    JOIN funding_chains fc ON icw.funding_chain_id = fc.id
    ORDER BY fc.chain_number;
END;
$$;


ALTER FUNCTION public.validate_consolidation_clusters() OWNER TO postgres;

--
-- Name: FUNCTION validate_consolidation_clusters(); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.validate_consolidation_clusters() IS 'Validates that consolidation clusters have variable sizes (not all same).
     Should return variety of source_wallet_count values (3-7), matching funding chain sizes.';


--
-- Name: validate_direct_funding_schedule(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validate_direct_funding_schedule() RETURNS TABLE(check_name text, severity text, status text, details text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check 1: No Star patterns (all chains have different subaccounts)
    RETURN QUERY
    SELECT 
        'No Star Patterns'::TEXT,
        'CRITICAL'::TEXT,
        CASE WHEN COUNT(DISTINCT cex_subaccount_id) = COUNT(*) THEN 'PASS' ELSE 'FAIL' END,
        FORMAT('Funding chains: %s total, %s unique subaccounts', 
               COUNT(*), COUNT(DISTINCT cex_subaccount_id))
    FROM funding_chains;

    -- Check 2: All withdrawals are direct (no intermediate hops)
    RETURN QUERY
    SELECT 
        'All Direct Withdrawals'::TEXT,
        'CRITICAL'::TEXT,
        CASE WHEN COUNT(*) FILTER (WHERE direct_cex_withdrawal = FALSE) = 0 THEN 'PASS' ELSE 'FAIL' END,
        FORMAT('%s direct, %s via intermediate (should be 0)', 
               COUNT(*) FILTER (WHERE direct_cex_withdrawal = TRUE),
               COUNT(*) FILTER (WHERE direct_cex_withdrawal = FALSE))
    FROM funding_withdrawals;

    -- Check 3: Interleaving quality (each round has diversity)
    RETURN QUERY
    SELECT 
        'Interleave Diversity'::TEXT,
        'HIGH'::TEXT,
        CASE WHEN MIN(unique_exchanges) >= 3 THEN 'PASS' ELSE 'WARN' END,
        FORMAT('Min exchanges per round: %s (should be ≥3)', MIN(unique_exchanges))
    FROM v_funding_interleave_quality;

    -- Check 4: Temporal spread (7 days)
    RETURN QUERY
    SELECT 
        'Temporal Spread'::TEXT,
        'HIGH'::TEXT,
        CASE 
            WHEN EXTRACT(EPOCH FROM (MAX(cex_withdrawal_scheduled_at) - MIN(cex_withdrawal_scheduled_at)))/86400 BETWEEN 6 AND 8
            THEN 'PASS' 
            ELSE 'FAIL' 
        END,
        FORMAT('%s days spread (target: 7 days)', 
               ROUND(EXTRACT(EPOCH FROM (MAX(cex_withdrawal_scheduled_at) - MIN(cex_withdrawal_scheduled_at)))/86400, 1))
    FROM funding_withdrawals
    WHERE direct_cex_withdrawal = TRUE;

    -- Check 5: No burst withdrawals (min 1h gap between same subaccount)
    RETURN QUERY
    WITH gaps AS (
        SELECT 
            cex_subaccount_id,
            cex_withdrawal_scheduled_at,
            LAG(cex_withdrawal_scheduled_at) OVER (PARTITION BY cex_subaccount_id ORDER BY cex_withdrawal_scheduled_at) as prev_time,
            EXTRACT(EPOCH FROM (cex_withdrawal_scheduled_at - LAG(cex_withdrawal_scheduled_at) OVER (PARTITION BY cex_subaccount_id ORDER BY cex_withdrawal_scheduled_at)))/3600 as gap_hours
        FROM funding_withdrawals
        WHERE direct_cex_withdrawal = TRUE
    )
    SELECT 
        'No Burst Withdrawals'::TEXT,
        'HIGH'::TEXT,
        CASE WHEN MIN(gap_hours) >= 1.0 OR MIN(gap_hours) IS NULL THEN 'PASS' ELSE 'FAIL' END,
        FORMAT('Min gap: %sh (should be ≥1h)', ROUND(MIN(gap_hours), 2))
    FROM gaps
    WHERE gap_hours IS NOT NULL;

    -- Check 6: Cluster size variability (3-7 wallets per chain)
    RETURN QUERY
    WITH cluster_sizes AS (
        SELECT 
            funding_chain_id,
            COUNT(*) as wallets_count
        FROM funding_withdrawals
        WHERE direct_cex_withdrawal = TRUE
        GROUP BY funding_chain_id
    )
    SELECT 
        'Variable Cluster Sizes'::TEXT,
        'MEDIUM'::TEXT,
        CASE WHEN COUNT(DISTINCT wallets_count) >= 3 THEN 'PASS' ELSE 'WARN' END,
        FORMAT('%s unique cluster sizes (target: ≥3 for variability)', COUNT(DISTINCT wallets_count))
    FROM cluster_sizes;

END;
$$;


ALTER FUNCTION public.validate_direct_funding_schedule() OWNER TO postgres;

--
-- Name: FUNCTION validate_direct_funding_schedule(); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.validate_direct_funding_schedule() IS 'Validates direct funding schedule for anti-Sybil compliance.
 Run after setup_direct_funding.py to ensure quality.';


--
-- Name: validate_funding_isolation(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validate_funding_isolation() RETURNS TABLE(issue_type text, severity text, details text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check 1: Subaccount reuse (CRITICAL)
    RETURN QUERY
    SELECT 
        'SUBACCOUNT_REUSE'::TEXT,
        'CRITICAL'::TEXT,
        'Subaccount ' || cex_subaccount_id || ' used by ' || COUNT(*) || ' chains: ' || 
        ARRAY_AGG(id ORDER BY id)::TEXT as details
    FROM funding_chains
    WHERE cex_subaccount_id IS NOT NULL
    GROUP BY cex_subaccount_id
    HAVING COUNT(*) > 1;
    
    -- Check 2: Stuck intermediate wallets (HIGH)
    -- Wallets funded but not forwarded after expected delay + 24h buffer
    RETURN QUERY
    SELECT
        'STUCK_INTERMEDIATE'::TEXT,
        'HIGH'::TEXT,
        'Wallet ' || ifw.address || ' (layer ' || ifw.layer || ') stuck for ' || 
        ROUND(EXTRACT(EPOCH FROM (NOW() - ifw.cex_funded_at))/3600, 1) || 'h | ' ||
        'Expected forward at: ' || (ifw.cex_funded_at + (fc.intermediate_delay_1_hours || ' hours')::INTERVAL)::TEXT
    FROM intermediate_funding_wallets ifw
    JOIN funding_chains fc ON ifw.funding_chain_id = fc.id
    WHERE ifw.status = 'funded'
      AND ifw.cex_funded_at IS NOT NULL
      AND NOW() > ifw.cex_funded_at + (fc.intermediate_delay_1_hours + 24 || ' hours')::INTERVAL;
    
    -- Check 3: Intermediate wallets without funding chain (MEDIUM)
    RETURN QUERY
    SELECT
        'ORPHAN_INTERMEDIATE'::TEXT,
        'MEDIUM'::TEXT,
        'Wallet ' || address || ' has no valid funding_chain_id: ' || funding_chain_id::TEXT
    FROM intermediate_funding_wallets ifw
    WHERE NOT EXISTS (
        SELECT 1 FROM funding_chains fc WHERE fc.id = ifw.funding_chain_id
    );
    
    -- Check 4: Chains with missing intermediate wallets (MEDIUM)
    RETURN QUERY
    SELECT
        'MISSING_INTERMEDIATE'::TEXT,
        'MEDIUM'::TEXT,
        'Chain ' || id || ' has intermediate_wallet_1=' || 
        COALESCE(intermediate_wallet_1, 'NULL') || ' but no DB record'
    FROM funding_chains fc
    WHERE intermediate_wallet_1 IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM intermediate_funding_wallets ifw 
          WHERE ifw.address = fc.intermediate_wallet_1
      );
    
    -- Check 5: Variable cluster size violations (LOW)
    -- Alert if all chains have same size (anti-sybil violation)
    RETURN QUERY
    SELECT
        'UNIFORM_CLUSTER_SIZE'::TEXT,
        'LOW'::TEXT,
        'All ' || COUNT(*) || ' chains have size ' || actual_wallet_count || ' (expected: variable 3-7)'
    FROM funding_chains
    WHERE actual_wallet_count IS NOT NULL
    GROUP BY actual_wallet_count
    HAVING COUNT(*) = (SELECT COUNT(*) FROM funding_chains WHERE actual_wallet_count IS NOT NULL)
      AND COUNT(*) > 1;
    
    -- Check 6: Proxy assignment issues (MEDIUM)
    RETURN QUERY
    SELECT
        'INTERMEDIATE_NO_PROXY'::TEXT,
        'MEDIUM'::TEXT,
        'Intermediate wallet ' || address || ' (layer ' || layer || ') has no proxy assigned'
    FROM intermediate_funding_wallets
    WHERE proxy_id IS NULL;
    
END;
$$;


ALTER FUNCTION public.validate_funding_isolation() OWNER TO postgres;

--
-- Name: FUNCTION validate_funding_isolation(); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.validate_funding_isolation() IS 'Validates funding chain isolation and detects anti-Sybil violations';


--
-- Name: validate_withdrawal_destination(integer, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validate_withdrawal_destination(p_wallet_id integer, p_destination_address character varying) RETURNS TABLE(is_valid boolean, error_message text, authorized_address character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_authorized_address VARCHAR(42);
BEGIN
    -- Get authorized address for wallet
    SELECT authorized_withdrawal_address
    INTO v_authorized_address
    FROM wallets
    WHERE id = p_wallet_id;
    
    -- Check 1: Wallet exists
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, 
                            'Wallet not found', 
                            NULL::VARCHAR;
        RETURN;
    END IF;
    
    -- Check 2: Authorized address is set
    IF v_authorized_address IS NULL THEN
        RETURN QUERY SELECT FALSE, 
                            'Wallet has no authorized_withdrawal_address (not funded yet?)', 
                            NULL::VARCHAR;
        RETURN;
    END IF;
    
    -- Check 3: Destination matches authorized address (case-insensitive)
    IF LOWER(p_destination_address) != LOWER(v_authorized_address) THEN
        RETURN QUERY SELECT FALSE, 
                            'Destination does not match authorized_withdrawal_address', 
                            v_authorized_address;
        RETURN;
    END IF;
    
    -- All checks passed
    RETURN QUERY SELECT TRUE, 
                        'Valid destination', 
                        v_authorized_address;
END;
$$;


ALTER FUNCTION public.validate_withdrawal_destination(p_wallet_id integer, p_destination_address character varying) OWNER TO postgres;

--
-- Name: FUNCTION validate_withdrawal_destination(p_wallet_id integer, p_destination_address character varying); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.validate_withdrawal_destination(p_wallet_id integer, p_destination_address character varying) IS 'Validates that withdrawal destination matches wallet authorized_withdrawal_address.
     Used by withdrawal orchestrator before creating withdrawal plans.
     
     Returns:
     - is_valid: TRUE if destination matches authorized address
     - error_message: Reason if validation failed
     - authorized_address: What the authorized address is (for logging)';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: airdrop_scan_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.airdrop_scan_logs (
    id integer NOT NULL,
    scan_start_at timestamp with time zone NOT NULL,
    scan_end_at timestamp with time zone,
    status character varying(50) DEFAULT 'running'::character varying,
    total_wallets_scanned integer DEFAULT 0,
    total_chains_scanned integer DEFAULT 0,
    total_api_calls integer DEFAULT 0,
    new_tokens_detected integer DEFAULT 0,
    alerts_sent integer DEFAULT 0,
    scan_duration_seconds numeric(10,2),
    avg_api_response_time_ms numeric(10,2),
    api_errors_encountered integer DEFAULT 0,
    rate_limit_hits integer DEFAULT 0,
    timeout_errors integer DEFAULT 0,
    error_details jsonb,
    chain_stats jsonb,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.airdrop_scan_logs OWNER TO postgres;

--
-- Name: TABLE airdrop_scan_logs; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.airdrop_scan_logs IS 'Audit trail for Module 17 airdrop detection cycles';


--
-- Name: COLUMN airdrop_scan_logs.scan_duration_seconds; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.airdrop_scan_logs.scan_duration_seconds IS 'Total time for scan cycle (target: ~110 seconds for 90 wallets)';


--
-- Name: COLUMN airdrop_scan_logs.chain_stats; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.airdrop_scan_logs.chain_stats IS 'Per-chain performance metrics for debugging bottlenecks';


--
-- Name: airdrop_scan_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.airdrop_scan_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.airdrop_scan_logs_id_seq OWNER TO postgres;

--
-- Name: airdrop_scan_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.airdrop_scan_logs_id_seq OWNED BY public.airdrop_scan_logs.id;


--
-- Name: airdrops; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.airdrops (
    id integer NOT NULL,
    protocol_id integer,
    token_symbol character varying(50) NOT NULL,
    token_contract_address character varying(42),
    chain character varying(50) NOT NULL,
    announced_at date,
    snapshot_date date,
    claim_start_date date,
    claim_end_date date,
    total_allocation bigint,
    vesting_schedule text,
    is_confirmed boolean DEFAULT false,
    confidence_score numeric(3,2),
    notes text,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.airdrops OWNER TO postgres;

--
-- Name: TABLE airdrops; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.airdrops IS 'Detected airdrops by airdrop_detector.py';


--
-- Name: COLUMN airdrops.confidence_score; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.airdrops.confidence_score IS 'Confidence from token_verifier.py (>0.6 triggers alert)';


--
-- Name: airdrops_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.airdrops_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.airdrops_id_seq OWNER TO postgres;

--
-- Name: airdrops_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.airdrops_id_seq OWNED BY public.airdrops.id;


--
-- Name: bridge_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bridge_history (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    from_network character varying(100) NOT NULL,
    to_network character varying(100) NOT NULL,
    amount_eth numeric(18,8) NOT NULL,
    provider character varying(100) NOT NULL,
    cost_usd numeric(10,2),
    tx_hash character varying(66),
    defillama_tvl_usd bigint,
    defillama_volume_30d_usd bigint,
    defillama_rank integer,
    defillama_hacks integer DEFAULT 0,
    safety_score integer,
    cex_checked character varying(100),
    cex_support_found boolean DEFAULT false,
    status character varying(20) DEFAULT 'pending'::character varying,
    error_message text,
    created_at timestamp with time zone DEFAULT now(),
    completed_at timestamp with time zone,
    CONSTRAINT chk_bridge_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'processing'::character varying, 'completed'::character varying, 'failed'::character varying, 'rejected'::character varying])::text[])))
);


ALTER TABLE public.bridge_history OWNER TO postgres;

--
-- Name: TABLE bridge_history; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.bridge_history IS 'Log of all bridge operations with DeFiLlama safety metrics and CEX check results';


--
-- Name: COLUMN bridge_history.from_network; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.bridge_history.from_network IS 'Source network - typically Arbitrum or another major L2';


--
-- Name: COLUMN bridge_history.to_network; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.bridge_history.to_network IS 'Destination network - can be ANY L2 (no hardcoded list, dynamic check)';


--
-- Name: COLUMN bridge_history.safety_score; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.bridge_history.safety_score IS 'Calculated safety score 0-100 based on TVL, rank, hacks';


--
-- Name: COLUMN bridge_history.cex_checked; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.bridge_history.cex_checked IS 'Comma-separated list of CEXes checked before bridge decision';


--
-- Name: COLUMN bridge_history.cex_support_found; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.bridge_history.cex_support_found IS 'TRUE if any CEX supports the destination network (bridge not needed)';


--
-- Name: bridge_history_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.bridge_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bridge_history_id_seq OWNER TO postgres;

--
-- Name: bridge_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.bridge_history_id_seq OWNED BY public.bridge_history.id;


--
-- Name: cex_networks_cache; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cex_networks_cache (
    id integer NOT NULL,
    cex_name character varying(50) NOT NULL,
    coin character varying(20) DEFAULT 'ETH'::character varying NOT NULL,
    supported_networks jsonb NOT NULL,
    fetched_at timestamp with time zone DEFAULT now(),
    expires_at timestamp with time zone NOT NULL,
    is_stale boolean DEFAULT false
);


ALTER TABLE public.cex_networks_cache OWNER TO postgres;

--
-- Name: TABLE cex_networks_cache; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.cex_networks_cache IS 'Cache for CEX supported networks (24-hour TTL). Updated via live API calls.';


--
-- Name: COLUMN cex_networks_cache.supported_networks; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.cex_networks_cache.supported_networks IS 'JSON array of network names from live CEX API';


--
-- Name: COLUMN cex_networks_cache.expires_at; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.cex_networks_cache.expires_at IS 'Cache expiration time (24 hours from fetch)';


--
-- Name: COLUMN cex_networks_cache.is_stale; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.cex_networks_cache.is_stale IS 'TRUE if API failed and using expired cache as fallback';


--
-- Name: cex_networks_cache_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.cex_networks_cache_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cex_networks_cache_id_seq OWNER TO postgres;

--
-- Name: cex_networks_cache_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.cex_networks_cache_id_seq OWNED BY public.cex_networks_cache.id;


--
-- Name: cex_subaccounts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cex_subaccounts (
    id integer NOT NULL,
    exchange public.cex_exchange NOT NULL,
    subaccount_name character varying(255) NOT NULL,
    api_key text NOT NULL,
    api_secret text NOT NULL,
    api_passphrase text,
    is_active boolean DEFAULT true,
    withdrawal_network character varying(50),
    balance_usdt numeric(18,8) DEFAULT 0,
    last_balance_check timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.cex_subaccounts OWNER TO postgres;

--
-- Name: TABLE cex_subaccounts; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.cex_subaccounts IS '18 subaccounts across 5 exchanges';


--
-- Name: COLUMN cex_subaccounts.api_key; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.cex_subaccounts.api_key IS 'Encrypted with Fernet (funding/secrets.py)';


--
-- Name: COLUMN cex_subaccounts.withdrawal_network; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.cex_subaccounts.withdrawal_network IS 'L2 network for withdrawals (NOT Ethereum mainnet!)';


--
-- Name: cex_subaccounts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.cex_subaccounts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cex_subaccounts_id_seq OWNER TO postgres;

--
-- Name: cex_subaccounts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.cex_subaccounts_id_seq OWNED BY public.cex_subaccounts.id;


--
-- Name: chain_aliases; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.chain_aliases (
    id integer NOT NULL,
    chain_id integer NOT NULL,
    alias character varying(100) NOT NULL,
    source character varying(50) DEFAULT 'manual'::character varying,
    last_seen timestamp with time zone DEFAULT now(),
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.chain_aliases OWNER TO postgres;

--
-- Name: TABLE chain_aliases; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.chain_aliases IS 'Alternative names for blockchain networks (normalization)';


--
-- Name: COLUMN chain_aliases.chain_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.chain_aliases.chain_id IS 'Chain ID (e.g., 42161 for Arbitrum)';


--
-- Name: COLUMN chain_aliases.alias; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.chain_aliases.alias IS 'Alternative name (e.g., "eth-mainnet" for "ethereum")';


--
-- Name: COLUMN chain_aliases.source; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.chain_aliases.source IS 'Where this alias came from: "chainid", "defillama", "socket", "cex", "manual"';


--
-- Name: COLUMN chain_aliases.last_seen; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.chain_aliases.last_seen IS 'When this alias was last encountered in external data';


--
-- Name: chain_aliases_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.chain_aliases_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.chain_aliases_id_seq OWNER TO postgres;

--
-- Name: chain_aliases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.chain_aliases_id_seq OWNED BY public.chain_aliases.id;


--
-- Name: chain_rpc_endpoints; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.chain_rpc_endpoints (
    id integer NOT NULL,
    chain character varying(50) NOT NULL,
    url text NOT NULL,
    priority integer DEFAULT 1,
    is_active boolean DEFAULT true,
    last_used_at timestamp with time zone,
    success_count integer DEFAULT 0,
    failure_count integer DEFAULT 0,
    avg_response_ms integer,
    created_at timestamp with time zone DEFAULT now(),
    chain_id integer,
    is_l2 boolean DEFAULT false,
    l1_data_fee boolean DEFAULT false,
    network_type character varying(20) DEFAULT 'sidechain'::character varying,
    gas_multiplier numeric(3,1) DEFAULT 2.0,
    is_auto_discovered boolean DEFAULT false,
    withdrawal_only boolean DEFAULT false,
    low_priority_rpc text,
    native_token character varying(20) DEFAULT 'ETH'::character varying,
    block_time numeric(4,2) DEFAULT 2.0,
    is_poa boolean DEFAULT false,
    farm_status character varying(20) DEFAULT 'ACTIVE'::character varying,
    token_ticker character varying(50)
);


ALTER TABLE public.chain_rpc_endpoints OWNER TO postgres;

--
-- Name: TABLE chain_rpc_endpoints; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.chain_rpc_endpoints IS 'RPC URLs for each supported chain with failover';


--
-- Name: COLUMN chain_rpc_endpoints.priority; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.chain_rpc_endpoints.priority IS '1=primary, 2=secondary fallback, etc.';


--
-- Name: COLUMN chain_rpc_endpoints.is_auto_discovered; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.chain_rpc_endpoints.is_auto_discovered IS 'TRUE if this chain was auto-discovered by ChainDiscoveryService';


--
-- Name: COLUMN chain_rpc_endpoints.farm_status; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.chain_rpc_endpoints.farm_status IS 'Farming status: ACTIVE (normal), DROPPED (airdrop passed), TARGET (priority), BLACKLISTED (unsafe)';


--
-- Name: chain_rpc_endpoints_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.chain_rpc_endpoints_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.chain_rpc_endpoints_id_seq OWNER TO postgres;

--
-- Name: chain_rpc_endpoints_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.chain_rpc_endpoints_id_seq OWNED BY public.chain_rpc_endpoints.id;


--
-- Name: chain_rpc_health_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.chain_rpc_health_log (
    id integer NOT NULL,
    rpc_endpoint_id integer NOT NULL,
    status public.rpc_health_status NOT NULL,
    response_time_ms integer,
    error_message text,
    checked_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.chain_rpc_health_log OWNER TO postgres;

--
-- Name: TABLE chain_rpc_health_log; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.chain_rpc_health_log IS 'RPC health monitoring log (retention: 7 days)';


--
-- Name: chain_rpc_health_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.chain_rpc_health_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.chain_rpc_health_log_id_seq OWNER TO postgres;

--
-- Name: chain_rpc_health_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.chain_rpc_health_log_id_seq OWNED BY public.chain_rpc_health_log.id;


--
-- Name: chain_tokens; Type: TABLE; Schema: public; Owner: farming_user
--

CREATE TABLE public.chain_tokens (
    id integer NOT NULL,
    chain_id integer NOT NULL,
    token_symbol character varying(10) NOT NULL,
    token_address character varying(42) NOT NULL,
    is_native_wrapped boolean DEFAULT false,
    decimals integer DEFAULT 18,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.chain_tokens OWNER TO farming_user;

--
-- Name: TABLE chain_tokens; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON TABLE public.chain_tokens IS 'Stores token addresses for different chains, including WETH and common tokens';


--
-- Name: COLUMN chain_tokens.token_address; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.chain_tokens.token_address IS 'Contract address of the token on the chain';


--
-- Name: COLUMN chain_tokens.is_native_wrapped; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.chain_tokens.is_native_wrapped IS 'TRUE for native wrapped tokens (WETH, WMATIC, WBNB)';


--
-- Name: chain_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: farming_user
--

CREATE SEQUENCE public.chain_tokens_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.chain_tokens_id_seq OWNER TO farming_user;

--
-- Name: chain_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: farming_user
--

ALTER SEQUENCE public.chain_tokens_id_seq OWNED BY public.chain_tokens.id;


--
-- Name: defillama_bridges_cache; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.defillama_bridges_cache (
    id integer NOT NULL,
    bridge_name character varying(100) NOT NULL,
    display_name character varying(100),
    chains jsonb,
    tvl_usd bigint,
    volume_30d_usd bigint,
    rank integer,
    hacks jsonb,
    fetched_at timestamp with time zone DEFAULT now(),
    expires_at timestamp with time zone NOT NULL
);


ALTER TABLE public.defillama_bridges_cache OWNER TO postgres;

--
-- Name: TABLE defillama_bridges_cache; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.defillama_bridges_cache IS 'Cache for DeFiLlama bridges data (6-hour TTL). Used for safety verification.';


--
-- Name: COLUMN defillama_bridges_cache.tvl_usd; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.defillama_bridges_cache.tvl_usd IS 'Total Value Locked in USD - used for safety score calculation';


--
-- Name: COLUMN defillama_bridges_cache.rank; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.defillama_bridges_cache.rank IS 'Rank in DeFiLlama bridges list - TOP-50 required for auto-approve';


--
-- Name: defillama_bridges_cache_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.defillama_bridges_cache_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.defillama_bridges_cache_id_seq OWNER TO postgres;

--
-- Name: defillama_bridges_cache_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.defillama_bridges_cache_id_seq OWNED BY public.defillama_bridges_cache.id;


--
-- Name: discovery_failures; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.discovery_failures (
    id integer NOT NULL,
    network_name character varying(100) NOT NULL,
    sources_checked text[] NOT NULL,
    error_message text,
    retry_count integer DEFAULT 0,
    last_retry_at timestamp with time zone,
    resolved boolean DEFAULT false,
    resolved_at timestamp with time zone,
    resolved_chain_id integer,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.discovery_failures OWNER TO postgres;

--
-- Name: TABLE discovery_failures; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.discovery_failures IS 'Log of failed chain discovery attempts for manual review';


--
-- Name: COLUMN discovery_failures.network_name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.discovery_failures.network_name IS 'Network name that could not be discovered';


--
-- Name: COLUMN discovery_failures.sources_checked; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.discovery_failures.sources_checked IS 'Array of sources that were checked: ["chainid", "defillama", "socket"]';


--
-- Name: COLUMN discovery_failures.error_message; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.discovery_failures.error_message IS 'Error message from discovery attempt';


--
-- Name: COLUMN discovery_failures.retry_count; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.discovery_failures.retry_count IS 'Number of times discovery was retried';


--
-- Name: COLUMN discovery_failures.resolved; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.discovery_failures.resolved IS 'TRUE if the chain was later registered manually or discovered';


--
-- Name: COLUMN discovery_failures.resolved_chain_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.discovery_failures.resolved_chain_id IS 'Chain ID if the network was later resolved';


--
-- Name: discovery_failures_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.discovery_failures_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.discovery_failures_id_seq OWNER TO postgres;

--
-- Name: discovery_failures_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.discovery_failures_id_seq OWNED BY public.discovery_failures.id;


--
-- Name: ens_names; Type: TABLE; Schema: public; Owner: farming_user
--

CREATE TABLE public.ens_names (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    ens_name text NOT NULL,
    parent_domain text,
    registration_tx_hash text,
    registered_at timestamp with time zone,
    expires_at timestamp with time zone,
    cost_eth numeric(18,8),
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.ens_names OWNER TO farming_user;

--
-- Name: TABLE ens_names; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON TABLE public.ens_names IS 'ENS names/subdomains — target: 1 per Tier A wallet (prefer FREE: cb.id, base.eth)';


--
-- Name: COLUMN ens_names.ens_name; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.ens_names.ens_name IS 'Full ENS name: user.cb.id, wallet42.base.eth, name.myproject.eth';


--
-- Name: COLUMN ens_names.parent_domain; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.ens_names.parent_domain IS 'Parent domain: cb.id (FREE), base.eth (FREE), myproject.eth ($5-10)';


--
-- Name: COLUMN ens_names.cost_eth; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.ens_names.cost_eth IS 'Registration cost in ETH — 0 for FREE options, 0.003-0.01 for premium';


--
-- Name: ens_names_id_seq; Type: SEQUENCE; Schema: public; Owner: farming_user
--

CREATE SEQUENCE public.ens_names_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.ens_names_id_seq OWNER TO farming_user;

--
-- Name: ens_names_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: farming_user
--

ALTER SEQUENCE public.ens_names_id_seq OWNED BY public.ens_names.id;


--
-- Name: funding_chains; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.funding_chains (
    id integer NOT NULL,
    chain_number integer NOT NULL,
    cex_subaccount_id integer NOT NULL,
    withdrawal_network character varying(50) NOT NULL,
    base_amount_usdt numeric(10,2) NOT NULL,
    wallets_count integer DEFAULT 5,
    status character varying(50) DEFAULT 'pending'::character varying,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    actual_wallet_count integer DEFAULT 5,
    CONSTRAINT funding_chains_actual_wallet_count_check CHECK (((actual_wallet_count >= 3) AND (actual_wallet_count <= 7))),
    CONSTRAINT funding_chains_chain_number_check CHECK (((chain_number >= 1) AND (chain_number <= 25)))
);


ALTER TABLE public.funding_chains OWNER TO postgres;

--
-- Name: TABLE funding_chains; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.funding_chains IS 'v3.0: Direct CEX → wallet funding chains. NO intermediate wallets.
 Each chain: 1 unique CEX subaccount → 3-7 target wallets (variable cluster sizes).
 18 total chains = full exchange/subaccount/network diversity.';


--
-- Name: COLUMN funding_chains.base_amount_usdt; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.funding_chains.base_amount_usdt IS 'Base amount per wallet (actual will vary ±25%)';


--
-- Name: COLUMN funding_chains.actual_wallet_count; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.funding_chains.actual_wallet_count IS 'Actual number of target wallets for this chain (variable: 3-7). 
     Anti-Sybil: Prevents "always 5 wallets per chain" pattern. 
     Gaussian distribution: mean=5, std=1.2, clipped to [3,7].';


--
-- Name: funding_chains_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.funding_chains_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.funding_chains_id_seq OWNER TO postgres;

--
-- Name: funding_chains_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.funding_chains_id_seq OWNED BY public.funding_chains.id;


--
-- Name: funding_withdrawals; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.funding_withdrawals (
    id integer NOT NULL,
    funding_chain_id integer NOT NULL,
    wallet_id integer,
    cex_subaccount_id integer NOT NULL,
    withdrawal_network character varying(50) NOT NULL,
    amount_usdt numeric(10,4) NOT NULL,
    withdrawal_address character varying(42) NOT NULL,
    cex_txid character varying(255),
    blockchain_txhash character varying(66),
    status public.funding_withdrawal_status DEFAULT 'planned'::public.funding_withdrawal_status,
    delay_minutes integer,
    scheduled_at timestamp with time zone,
    requested_at timestamp with time zone,
    completed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    direct_cex_withdrawal boolean DEFAULT true,
    cex_withdrawal_scheduled_at timestamp with time zone,
    cex_withdrawal_completed_at timestamp with time zone,
    interleave_round integer,
    interleave_position integer
);


ALTER TABLE public.funding_withdrawals OWNER TO postgres;

--
-- Name: TABLE funding_withdrawals; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.funding_withdrawals IS '90 withdrawals from CEX to wallets with temporal isolation';


--
-- Name: COLUMN funding_withdrawals.cex_txid; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.funding_withdrawals.cex_txid IS 'Transaction ID from CEX withdrawal API response.';


--
-- Name: COLUMN funding_withdrawals.delay_minutes; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.funding_withdrawals.delay_minutes IS 'Temporal isolation: 60-240 baseline, +20-60 if night, or 300-600 for "sleep pause"';


--
-- Name: COLUMN funding_withdrawals.direct_cex_withdrawal; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.funding_withdrawals.direct_cex_withdrawal IS 'TRUE = direct CEX → target wallet (v3.0 architecture).
 FALSE = using intermediate wallets (deprecated v2.0).';


--
-- Name: COLUMN funding_withdrawals.cex_withdrawal_scheduled_at; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.funding_withdrawals.cex_withdrawal_scheduled_at IS 'Interleaved schedule timestamp. Withdrawals processed when scheduled_at <= NOW().
 Uses Gaussian delays (2-10h) to spread 90 withdrawals over 7 days.';


--
-- Name: COLUMN funding_withdrawals.cex_withdrawal_completed_at; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.funding_withdrawals.cex_withdrawal_completed_at IS 'Timestamp when CEX withdrawal was successfully completed (confirmed on-chain).';


--
-- Name: COLUMN funding_withdrawals.interleave_round; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.funding_withdrawals.interleave_round IS 'Round number in interleaved execution (0-17 for 18 funding chains).
 Ensures exchange diversity: no consecutive withdrawals from same CEX.';


--
-- Name: COLUMN funding_withdrawals.interleave_position; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.funding_withdrawals.interleave_position IS 'Position within the round (determines order of execution within round).';


--
-- Name: funding_withdrawals_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.funding_withdrawals_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.funding_withdrawals_id_seq OWNER TO postgres;

--
-- Name: funding_withdrawals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.funding_withdrawals_id_seq OWNED BY public.funding_withdrawals.id;


--
-- Name: gas_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.gas_history (
    id integer NOT NULL,
    chain_id integer NOT NULL,
    gas_price_gwei numeric(10,4) NOT NULL,
    recorded_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.gas_history OWNER TO postgres;

--
-- Name: gas_history_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.gas_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.gas_history_id_seq OWNER TO postgres;

--
-- Name: gas_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.gas_history_id_seq OWNED BY public.gas_history.id;


--
-- Name: gas_snapshots; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.gas_snapshots (
    id integer NOT NULL,
    chain character varying(50) NOT NULL,
    slow_gwei numeric(10,2) NOT NULL,
    normal_gwei numeric(10,2) NOT NULL,
    fast_gwei numeric(10,2) NOT NULL,
    block_number bigint,
    recorded_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.gas_snapshots OWNER TO postgres;

--
-- Name: TABLE gas_snapshots; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.gas_snapshots IS 'Gas price monitoring for adaptive.py skip logic';


--
-- Name: gas_snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.gas_snapshots_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.gas_snapshots_id_seq OWNER TO postgres;

--
-- Name: gas_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.gas_snapshots_id_seq OWNED BY public.gas_snapshots.id;


--
-- Name: gitcoin_stamps; Type: TABLE; Schema: public; Owner: farming_user
--

CREATE TABLE public.gitcoin_stamps (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    stamp_type character varying(100) NOT NULL,
    stamp_id text,
    earned_at timestamp with time zone,
    expires_at timestamp with time zone,
    score_contribution numeric(5,2),
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.gitcoin_stamps OWNER TO farming_user;

--
-- Name: TABLE gitcoin_stamps; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON TABLE public.gitcoin_stamps IS 'Gitcoin Passport stamps — target: 5+ stamps per Tier A wallet';


--
-- Name: COLUMN gitcoin_stamps.stamp_type; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.gitcoin_stamps.stamp_type IS 'Stamp type: github, twitter, discord, google, linkedin, brightid, ens, poh, etc.';


--
-- Name: COLUMN gitcoin_stamps.score_contribution; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.gitcoin_stamps.score_contribution IS 'Score contribution (ranges 0.5-10 depending on stamp)';


--
-- Name: COLUMN gitcoin_stamps.metadata; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.gitcoin_stamps.metadata IS 'JSONB: {"github_username": "user123", "followers": 50, ...}';


--
-- Name: gitcoin_stamps_id_seq; Type: SEQUENCE; Schema: public; Owner: farming_user
--

CREATE SEQUENCE public.gitcoin_stamps_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.gitcoin_stamps_id_seq OWNER TO farming_user;

--
-- Name: gitcoin_stamps_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: farming_user
--

ALTER SEQUENCE public.gitcoin_stamps_id_seq OWNED BY public.gitcoin_stamps.id;


--
-- Name: lens_profiles; Type: TABLE; Schema: public; Owner: farming_user
--

CREATE TABLE public.lens_profiles (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    profile_id text,
    handle text,
    created_tx_hash text,
    follower_count integer DEFAULT 0,
    following_count integer DEFAULT 0,
    publication_count integer DEFAULT 0,
    last_activity_at timestamp with time zone,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.lens_profiles OWNER TO farming_user;

--
-- Name: TABLE lens_profiles; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON TABLE public.lens_profiles IS 'Lens Protocol profiles — target: 1 profile + 2-3 posts per Tier A wallet';


--
-- Name: COLUMN lens_profiles.profile_id; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.lens_profiles.profile_id IS 'Lens profile ID (hex string)';


--
-- Name: COLUMN lens_profiles.handle; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.lens_profiles.handle IS 'Lens handle: user123.lens';


--
-- Name: COLUMN lens_profiles.publication_count; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.lens_profiles.publication_count IS 'Total publications: posts + comments + mirrors';


--
-- Name: COLUMN lens_profiles.metadata; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.lens_profiles.metadata IS 'JSONB: {"bio": "...", "avatar_url": "...", "cover_image_url": "..."}';


--
-- Name: lens_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: farming_user
--

CREATE SEQUENCE public.lens_profiles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.lens_profiles_id_seq OWNER TO farming_user;

--
-- Name: lens_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: farming_user
--

ALTER SEQUENCE public.lens_profiles_id_seq OWNED BY public.lens_profiles.id;


--
-- Name: news_items; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.news_items (
    id integer NOT NULL,
    title text NOT NULL,
    url text NOT NULL,
    source character varying(255),
    published_at timestamp with time zone,
    keywords character varying(100)[],
    relevance_score numeric(3,2),
    is_reviewed boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.news_items OWNER TO postgres;

--
-- Name: TABLE news_items; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.news_items IS 'Crypto news from CryptoPanic API analyzed by news_analyzer.py';


--
-- Name: news_items_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.news_items_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.news_items_id_seq OWNER TO postgres;

--
-- Name: news_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.news_items_id_seq OWNED BY public.news_items.id;


--
-- Name: openclaw_profiles; Type: TABLE; Schema: public; Owner: farming_user
--

CREATE TABLE public.openclaw_profiles (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    browser_fingerprint jsonb,
    cookies jsonb,
    local_storage jsonb,
    session_storage jsonb,
    indexed_db_state jsonb,
    profile_path text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.openclaw_profiles OWNER TO farming_user;

--
-- Name: TABLE openclaw_profiles; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON TABLE public.openclaw_profiles IS 'Browser profiles for 18 Tier A wallets — persistent sessions';


--
-- Name: COLUMN openclaw_profiles.browser_fingerprint; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.openclaw_profiles.browser_fingerprint IS 'Unique fingerprint per wallet (canvas, WebGL, fonts, timezone)';


--
-- Name: COLUMN openclaw_profiles.cookies; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.openclaw_profiles.cookies IS 'OAuth cookies (GitHub, Twitter, Discord) — stored as encrypted JSONB';


--
-- Name: COLUMN openclaw_profiles.profile_path; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.openclaw_profiles.profile_path IS 'Path to browser profile directory on Worker node';


--
-- Name: openclaw_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: farming_user
--

CREATE SEQUENCE public.openclaw_profiles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.openclaw_profiles_id_seq OWNER TO farming_user;

--
-- Name: openclaw_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: farming_user
--

ALTER SEQUENCE public.openclaw_profiles_id_seq OWNED BY public.openclaw_profiles.id;


--
-- Name: openclaw_reputation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.openclaw_reputation (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    has_ens boolean DEFAULT false,
    ens_name character varying(255),
    gitcoin_passport_score numeric(5,2) DEFAULT 0,
    gitcoin_stamps_count integer DEFAULT 0,
    poap_count integer DEFAULT 0,
    snapshot_votes_count integer DEFAULT 0,
    lens_profile boolean DEFAULT false,
    total_donations_usdt numeric(10,2) DEFAULT 0,
    last_updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.openclaw_reputation OWNER TO postgres;

--
-- Name: TABLE openclaw_reputation; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.openclaw_reputation IS 'On-chain reputation for 18 Tier A wallets';


--
-- Name: COLUMN openclaw_reputation.gitcoin_passport_score; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.openclaw_reputation.gitcoin_passport_score IS 'Target: ≥25 for strong Sybil resistance';


--
-- Name: openclaw_reputation_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.openclaw_reputation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.openclaw_reputation_id_seq OWNER TO postgres;

--
-- Name: openclaw_reputation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.openclaw_reputation_id_seq OWNED BY public.openclaw_reputation.id;


--
-- Name: openclaw_task_history; Type: TABLE; Schema: public; Owner: farming_user
--

CREATE TABLE public.openclaw_task_history (
    id integer NOT NULL,
    task_id integer NOT NULL,
    attempt_number integer DEFAULT 1 NOT NULL,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    duration_seconds integer,
    screenshot_path text,
    error_message text,
    stack_trace text,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.openclaw_task_history OWNER TO farming_user;

--
-- Name: TABLE openclaw_task_history; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON TABLE public.openclaw_task_history IS 'Task execution history — one record per retry attempt';


--
-- Name: COLUMN openclaw_task_history.attempt_number; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.openclaw_task_history.attempt_number IS 'Retry attempt: 1 (first try), 2-3 (retries)';


--
-- Name: COLUMN openclaw_task_history.screenshot_path; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.openclaw_task_history.screenshot_path IS 'Screenshot for audit trail — stored for 90 days';


--
-- Name: COLUMN openclaw_task_history.metadata; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.openclaw_task_history.metadata IS 'JSONB: {"tx_hash": "0x...", "stamp_score": 15, "poap_token_id": 123456, ...}';


--
-- Name: openclaw_task_history_id_seq; Type: SEQUENCE; Schema: public; Owner: farming_user
--

CREATE SEQUENCE public.openclaw_task_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.openclaw_task_history_id_seq OWNER TO farming_user;

--
-- Name: openclaw_task_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: farming_user
--

ALTER SEQUENCE public.openclaw_task_history_id_seq OWNED BY public.openclaw_task_history.id;


--
-- Name: openclaw_tasks; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.openclaw_tasks (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    task_type character varying(100) NOT NULL,
    protocol_id integer,
    task_params jsonb,
    status public.openclaw_task_status DEFAULT 'queued'::public.openclaw_task_status,
    scheduled_at timestamp with time zone NOT NULL,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    error_message text,
    retry_count integer DEFAULT 0,
    max_retries integer DEFAULT 3,
    created_at timestamp with time zone DEFAULT now(),
    priority integer DEFAULT 5,
    assigned_worker_id integer
);


ALTER TABLE public.openclaw_tasks OWNER TO postgres;

--
-- Name: TABLE openclaw_tasks; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.openclaw_tasks IS 'Browser automation tasks for 18 Tier A wallets via OpenClaw';


--
-- Name: COLUMN openclaw_tasks.priority; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.openclaw_tasks.priority IS 'Priority: 1 (highest) to 10 (lowest) — Gitcoin/ENS are priority 1';


--
-- Name: COLUMN openclaw_tasks.assigned_worker_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.openclaw_tasks.assigned_worker_id IS 'Worker assignment: NULL (unassigned), 1 (NL), 2-3 (IS)';


--
-- Name: openclaw_tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.openclaw_tasks_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.openclaw_tasks_id_seq OWNER TO postgres;

--
-- Name: openclaw_tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.openclaw_tasks_id_seq OWNED BY public.openclaw_tasks.id;


--
-- Name: personas_config; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.personas_config (
    id integer NOT NULL,
    persona_type public.persona_type NOT NULL,
    description text,
    default_tx_per_week_mean numeric(4,2) NOT NULL,
    default_tx_per_week_stddev numeric(4,2) NOT NULL,
    default_preferred_hours_range integer[] NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.personas_config OWNER TO postgres;

--
-- Name: TABLE personas_config; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.personas_config IS 'Template archetypes for generating unique wallet personas';


--
-- Name: personas_config_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.personas_config_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.personas_config_id_seq OWNER TO postgres;

--
-- Name: personas_config_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.personas_config_id_seq OWNED BY public.personas_config.id;


--
-- Name: poap_tokens; Type: TABLE; Schema: public; Owner: farming_user
--

CREATE TABLE public.poap_tokens (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    event_id integer NOT NULL,
    event_name text NOT NULL,
    token_id text,
    claimed_at timestamp with time zone,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.poap_tokens OWNER TO farming_user;

--
-- Name: TABLE poap_tokens; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON TABLE public.poap_tokens IS 'POAP tokens — target: 3-5 POAPs per Tier A wallet';


--
-- Name: COLUMN poap_tokens.event_id; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.poap_tokens.event_id IS 'POAP event ID (from POAP API)';


--
-- Name: COLUMN poap_tokens.token_id; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.poap_tokens.token_id IS 'POAP token ID after minting (ERC-721)';


--
-- Name: COLUMN poap_tokens.metadata; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.poap_tokens.metadata IS 'JSONB: {"image_url": "...", "description": "...", "event_date": "2026-02-15", ...}';


--
-- Name: poap_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: farming_user
--

CREATE SEQUENCE public.poap_tokens_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.poap_tokens_id_seq OWNER TO farming_user;

--
-- Name: poap_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: farming_user
--

ALTER SEQUENCE public.poap_tokens_id_seq OWNED BY public.poap_tokens.id;


--
-- Name: points_programs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.points_programs (
    id integer NOT NULL,
    protocol_id integer NOT NULL,
    program_name character varying(255) NOT NULL,
    api_url text,
    check_method character varying(50),
    multiplier_active boolean DEFAULT false,
    multiplier_ends_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.points_programs OWNER TO postgres;

--
-- Name: TABLE points_programs; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.points_programs IS 'Points loyalty programs (e.g., Blast Points, Scroll Marks)';


--
-- Name: points_programs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.points_programs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.points_programs_id_seq OWNER TO postgres;

--
-- Name: points_programs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.points_programs_id_seq OWNED BY public.points_programs.id;


--
-- Name: protocol_actions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.protocol_actions (
    id integer NOT NULL,
    protocol_id integer NOT NULL,
    action_name character varying(255) NOT NULL,
    tx_type public.tx_type NOT NULL,
    layer public.action_layer NOT NULL,
    chain character varying(50) NOT NULL,
    contract_id integer,
    function_signature text,
    default_params jsonb,
    min_amount_usdt numeric(10,4),
    max_amount_usdt numeric(10,4),
    estimated_gas_gwei integer,
    points_multiplier numeric(3,2) DEFAULT 1.0,
    is_enabled boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.protocol_actions OWNER TO postgres;

--
-- Name: TABLE protocol_actions; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.protocol_actions IS 'Specific on-chain actions for each protocol';


--
-- Name: COLUMN protocol_actions.layer; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_actions.layer IS '"web3py" for direct RPC, "openclaw" for browser automation';


--
-- Name: COLUMN protocol_actions.points_multiplier; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_actions.points_multiplier IS 'Points boost (e.g., 2.0 for double points campaigns)';


--
-- Name: protocol_actions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.protocol_actions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.protocol_actions_id_seq OWNER TO postgres;

--
-- Name: protocol_actions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.protocol_actions_id_seq OWNED BY public.protocol_actions.id;


--
-- Name: protocol_contracts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.protocol_contracts (
    id integer NOT NULL,
    protocol_id integer NOT NULL,
    chain character varying(50) NOT NULL,
    contract_type character varying(100) NOT NULL,
    address character varying(42) NOT NULL,
    abi_json jsonb,
    is_verified boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT chk_contract_address CHECK (((address)::text ~ '^0x[a-fA-F0-9]{40}$'::text))
);


ALTER TABLE public.protocol_contracts OWNER TO postgres;

--
-- Name: TABLE protocol_contracts; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.protocol_contracts IS 'Smart contracts for each protocol on supported chains';


--
-- Name: COLUMN protocol_contracts.abi_json; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_contracts.abi_json IS 'Contract ABI (can be partial for common functions)';


--
-- Name: protocol_contracts_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.protocol_contracts_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.protocol_contracts_id_seq OWNER TO postgres;

--
-- Name: protocol_contracts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.protocol_contracts_id_seq OWNED BY public.protocol_contracts.id;


--
-- Name: protocol_research_pending; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.protocol_research_pending (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    category character varying(100),
    chains character varying(100)[],
    website_url text,
    twitter_url text,
    discord_url text,
    airdrop_score integer NOT NULL,
    has_points_program boolean DEFAULT false,
    points_program_url text,
    has_token boolean DEFAULT false,
    current_tvl_usd numeric(18,2),
    tvl_change_30d_pct numeric(6,2),
    launch_date date,
    recommended_actions jsonb NOT NULL,
    reasoning text NOT NULL,
    raw_llm_response jsonb,
    status public.research_status DEFAULT 'pending_approval'::public.research_status,
    approved_by character varying(100),
    approved_at timestamp with time zone,
    rejected_reason text,
    rejected_at timestamp with time zone,
    discovered_from character varying(100),
    source_article_url text,
    source_article_title text,
    source_published_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    bridge_required boolean DEFAULT false,
    bridge_from_network character varying(50) DEFAULT 'Arbitrum'::character varying,
    bridge_provider character varying(100),
    bridge_cost_usd numeric(10,2),
    bridge_time_minutes integer,
    bridge_safety_score integer,
    bridge_available boolean DEFAULT true,
    bridge_checked_at timestamp with time zone,
    cex_support_found character varying(50),
    bridge_unreachable_reason text,
    bridge_recheck_after timestamp with time zone,
    bridge_recheck_count integer DEFAULT 0,
    cex_support character varying(50),
    risk_tags text[],
    risk_level character varying(20) DEFAULT 'LOW'::character varying,
    requires_manual boolean DEFAULT false,
    CONSTRAINT chk_valid_urls CHECK ((((website_url IS NULL) OR (website_url ~ '^https?://'::text)) AND ((twitter_url IS NULL) OR (twitter_url ~ '^https?://(twitter\.com|x\.com)/'::text)) AND ((discord_url IS NULL) OR (discord_url ~ '^https?://(discord\.gg|discord\.com)/'::text)))),
    CONSTRAINT protocol_research_pending_airdrop_score_check CHECK (((airdrop_score >= 0) AND (airdrop_score <= 100)))
);


ALTER TABLE public.protocol_research_pending OWNER TO postgres;

--
-- Name: TABLE protocol_research_pending; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.protocol_research_pending IS 'LLM-discovered protocols awaiting human approval via Telegram';


--
-- Name: COLUMN protocol_research_pending.airdrop_score; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.airdrop_score IS 'LLM-assigned probability (0-100): 80+ = high priority, 50-79 = medium, <50 = low/auto-reject';


--
-- Name: COLUMN protocol_research_pending.recommended_actions; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.recommended_actions IS 'JSON array: ["SWAP", "LP", "STAKE"] - used to auto-create protocol_actions';


--
-- Name: COLUMN protocol_research_pending.reasoning; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.reasoning IS 'LLM explanation shown in Telegram notification';


--
-- Name: COLUMN protocol_research_pending.bridge_required; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.bridge_required IS 'TRUE if the protocol network requires bridge (no CEX direct withdrawal support)';


--
-- Name: COLUMN protocol_research_pending.bridge_from_network; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.bridge_from_network IS 'Source network for bridge, usually Arbitrum or Base (default: Arbitrum)';


--
-- Name: COLUMN protocol_research_pending.bridge_provider; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.bridge_provider IS 'Bridge aggregator: socket, across, relay, or NULL if unavailable';


--
-- Name: COLUMN protocol_research_pending.bridge_cost_usd; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.bridge_cost_usd IS 'Estimated bridge cost in USD from aggregator API';


--
-- Name: COLUMN protocol_research_pending.bridge_safety_score; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.bridge_safety_score IS 'DeFiLlama safety score 0-100 (TVL + rank + no hacks + verified)';


--
-- Name: COLUMN protocol_research_pending.bridge_available; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.bridge_available IS 'TRUE if bridge route found, FALSE if unreachable';


--
-- Name: COLUMN protocol_research_pending.bridge_checked_at; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.bridge_checked_at IS 'Timestamp of last bridge availability check';


--
-- Name: COLUMN protocol_research_pending.cex_support_found; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.cex_support_found IS 'CEX name if direct withdrawal possible (e.g., "bybit"), NULL if bridge required';


--
-- Name: COLUMN protocol_research_pending.bridge_unreachable_reason; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.bridge_unreachable_reason IS 'Reason why bridge is unavailable (e.g., "No route found via Socket/Across/Relay")';


--
-- Name: COLUMN protocol_research_pending.bridge_recheck_after; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.bridge_recheck_after IS 'When to recheck unreachable protocol (7 days from last check)';


--
-- Name: COLUMN protocol_research_pending.bridge_recheck_count; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.bridge_recheck_count IS 'Number of recheck attempts (max 4, then auto-reject)';


--
-- Name: COLUMN protocol_research_pending.cex_support; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.cex_support IS 'CEX name if direct withdrawal to network is supported (e.g., "bybit", "kucoin")';


--
-- Name: COLUMN protocol_research_pending.risk_tags; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.risk_tags IS 'Risk tags from RiskScorer: KYC, SYBIL, DERIVATIVES, etc.';


--
-- Name: COLUMN protocol_research_pending.risk_level; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.risk_level IS 'Risk level: LOW, MEDIUM, HIGH, CRITICAL';


--
-- Name: COLUMN protocol_research_pending.requires_manual; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocol_research_pending.requires_manual IS 'TRUE if protocol requires manual intervention';


--
-- Name: protocol_research_pending_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.protocol_research_pending_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.protocol_research_pending_id_seq OWNER TO postgres;

--
-- Name: protocol_research_pending_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.protocol_research_pending_id_seq OWNED BY public.protocol_research_pending.id;


--
-- Name: protocol_research_reports; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.protocol_research_reports (
    id integer NOT NULL,
    run_date date NOT NULL,
    protocols_discovered integer DEFAULT 0,
    protocols_updated integer DEFAULT 0,
    llm_model character varying(100),
    execution_time_seconds integer,
    report_summary text,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.protocol_research_reports OWNER TO postgres;

--
-- Name: TABLE protocol_research_reports; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.protocol_research_reports IS 'Weekly LLM agent reports (every Sunday 02:00 UTC)';


--
-- Name: protocol_research_reports_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.protocol_research_reports_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.protocol_research_reports_id_seq OWNER TO postgres;

--
-- Name: protocol_research_reports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.protocol_research_reports_id_seq OWNED BY public.protocol_research_reports.id;


--
-- Name: protocols; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.protocols (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    category character varying(100),
    chains character varying(100)[],
    has_points_program boolean DEFAULT false,
    points_program_url text,
    airdrop_announced boolean DEFAULT false,
    airdrop_snapshot_date date,
    priority_score integer DEFAULT 50,
    is_active boolean DEFAULT true,
    last_researched_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    bridge_required boolean DEFAULT false,
    bridge_from_network character varying(50),
    bridge_provider character varying(100),
    bridge_cost_usd numeric(10,2),
    cex_support character varying(50),
    risk_tags text[],
    risk_level character varying(20) DEFAULT 'LOW'::character varying,
    requires_manual boolean DEFAULT false
);


ALTER TABLE public.protocols OWNER TO postgres;

--
-- Name: TABLE protocols; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.protocols IS 'DeFi protocols discovered by LLM agent and manual input';


--
-- Name: COLUMN protocols.priority_score; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocols.priority_score IS 'LLM-assigned priority (0-100) based on airdrop potential';


--
-- Name: COLUMN protocols.bridge_required; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocols.bridge_required IS 'TRUE if protocol requires bridge to access (no CEX support)';


--
-- Name: COLUMN protocols.cex_support; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocols.cex_support IS 'CEX name if direct withdrawal possible (e.g., "bybit")';


--
-- Name: COLUMN protocols.risk_tags; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocols.risk_tags IS 'Risk tags from RiskScorer: KYC, SYBIL, DERIVATIVES, etc.';


--
-- Name: COLUMN protocols.risk_level; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocols.risk_level IS 'Risk level: LOW, MEDIUM, HIGH, CRITICAL';


--
-- Name: COLUMN protocols.requires_manual; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.protocols.requires_manual IS 'TRUE if protocol requires manual intervention (KYC, etc.)';


--
-- Name: protocols_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.protocols_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.protocols_id_seq OWNER TO postgres;

--
-- Name: protocols_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.protocols_id_seq OWNED BY public.protocols.id;


--
-- Name: proxy_pool; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.proxy_pool (
    id integer NOT NULL,
    ip_address character varying(255) NOT NULL,
    port integer NOT NULL,
    protocol public.proxy_protocol NOT NULL,
    username character varying(255) NOT NULL,
    password character varying(255) NOT NULL,
    country_code character varying(2) NOT NULL,
    provider character varying(50) NOT NULL,
    session_id character varying(255),
    is_active boolean DEFAULT true,
    last_used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    timezone character varying(50) NOT NULL,
    utc_offset integer NOT NULL,
    validation_status character varying(20) DEFAULT 'unknown'::character varying,
    last_validated_at timestamp with time zone,
    validation_error text,
    response_time_ms integer,
    detected_ip character varying(45),
    detected_country character varying(2)
);


ALTER TABLE public.proxy_pool OWNER TO postgres;

--
-- Name: TABLE proxy_pool; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.proxy_pool IS '90 proxies: 45 IPRoyal NL + 45 Decodo IS';


--
-- Name: COLUMN proxy_pool.session_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.proxy_pool.session_id IS 'Sticky session ID (7 days for IPRoyal, 60 min for Decodo)';


--
-- Name: proxy_pool_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.proxy_pool_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.proxy_pool_id_seq OWNER TO postgres;

--
-- Name: proxy_pool_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.proxy_pool_id_seq OWNED BY public.proxy_pool.id;


--
-- Name: research_logs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.research_logs (
    id integer NOT NULL,
    cycle_start_at timestamp with time zone NOT NULL,
    cycle_end_at timestamp with time zone,
    status character varying(50) DEFAULT 'running'::character varying,
    total_sources_checked integer DEFAULT 0,
    total_candidates_found integer DEFAULT 0,
    total_analyzed_by_llm integer DEFAULT 0,
    total_added_to_pending integer DEFAULT 0,
    total_duplicates integer DEFAULT 0,
    total_rejected_low_score integer DEFAULT 0,
    source_stats jsonb,
    llm_api_calls integer DEFAULT 0,
    llm_tokens_used integer DEFAULT 0,
    estimated_cost_usd numeric(6,4) DEFAULT 0,
    errors_encountered integer DEFAULT 0,
    error_details jsonb,
    summary_report text,
    protocols_auto_rejected integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.research_logs OWNER TO postgres;

--
-- Name: TABLE research_logs; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.research_logs IS 'Audit trail for weekly research cycles - tracks costs, performance, and errors';


--
-- Name: COLUMN research_logs.estimated_cost_usd; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.research_logs.estimated_cost_usd IS 'OpenRouter API cost: ~$0.01-0.03 per protocol (GPT-4 Turbo)';


--
-- Name: COLUMN research_logs.summary_report; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.research_logs.summary_report IS 'Formatted summary sent to Telegram';


--
-- Name: research_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.research_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.research_logs_id_seq OWNER TO postgres;

--
-- Name: research_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.research_logs_id_seq OWNED BY public.research_logs.id;


--
-- Name: safety_gates; Type: TABLE; Schema: public; Owner: farming_user
--

CREATE TABLE public.safety_gates (
    id integer NOT NULL,
    gate_name character varying(50) NOT NULL,
    is_open boolean DEFAULT false,
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.safety_gates OWNER TO farming_user;

--
-- Name: TABLE safety_gates; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON TABLE public.safety_gates IS 'Safety gates that must be opened before mainnet execution';


--
-- Name: COLUMN safety_gates.gate_name; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.safety_gates.gate_name IS 'Unique gate identifier';


--
-- Name: COLUMN safety_gates.is_open; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.safety_gates.is_open IS 'Whether the gate is open (allows mainnet)';


--
-- Name: safety_gates_id_seq; Type: SEQUENCE; Schema: public; Owner: farming_user
--

CREATE SEQUENCE public.safety_gates_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.safety_gates_id_seq OWNER TO farming_user;

--
-- Name: safety_gates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: farming_user
--

ALTER SEQUENCE public.safety_gates_id_seq OWNED BY public.safety_gates.id;


--
-- Name: scheduled_transactions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.scheduled_transactions (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    protocol_action_id integer NOT NULL,
    tx_type public.tx_type NOT NULL,
    layer public.action_layer NOT NULL,
    scheduled_at timestamp with time zone NOT NULL,
    amount_usdt numeric(10,4),
    params jsonb,
    status public.tx_status DEFAULT 'pending'::public.tx_status,
    tx_hash character varying(66),
    gas_used bigint,
    gas_price_gwei numeric(10,2),
    error_message text,
    executed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    from_network character varying(50),
    to_network character varying(50),
    depends_on_tx_id integer,
    bridge_required boolean DEFAULT false,
    bridge_provider character varying(100),
    bridge_status character varying(50) DEFAULT 'not_required'::character varying
);


ALTER TABLE public.scheduled_transactions OWNER TO postgres;

--
-- Name: TABLE scheduled_transactions; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.scheduled_transactions IS 'Scheduled transactions queue from activity/scheduler.py';


--
-- Name: COLUMN scheduled_transactions.from_network; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.scheduled_transactions.from_network IS 'Source network for BRIDGE transactions';


--
-- Name: COLUMN scheduled_transactions.to_network; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.scheduled_transactions.to_network IS 'Destination network for BRIDGE transactions';


--
-- Name: COLUMN scheduled_transactions.depends_on_tx_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.scheduled_transactions.depends_on_tx_id IS 'Dependency: wait for this TX to complete before executing';


--
-- Name: COLUMN scheduled_transactions.bridge_provider; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.scheduled_transactions.bridge_provider IS 'Bridge provider used (socket, across, relay)';


--
-- Name: COLUMN scheduled_transactions.bridge_status; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.scheduled_transactions.bridge_status IS 'Status of bridge operation';


--
-- Name: scheduled_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.scheduled_transactions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.scheduled_transactions_id_seq OWNER TO postgres;

--
-- Name: scheduled_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.scheduled_transactions_id_seq OWNED BY public.scheduled_transactions.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: farming_user
--

CREATE TABLE public.schema_migrations (
    version character varying(255) NOT NULL,
    applied_at timestamp with time zone DEFAULT now(),
    description text
);


ALTER TABLE public.schema_migrations OWNER TO farming_user;

--
-- Name: snapshot_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.snapshot_events (
    id integer NOT NULL,
    protocol_id integer NOT NULL,
    snapshot_date date NOT NULL,
    post_snapshot_duration_days integer DEFAULT 21,
    wallets_affected integer[],
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.snapshot_events OWNER TO postgres;

--
-- Name: TABLE snapshot_events; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.snapshot_events IS 'Protocol snapshot events for post-snapshot activity continuation';


--
-- Name: snapshot_events_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.snapshot_events_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.snapshot_events_id_seq OWNER TO postgres;

--
-- Name: snapshot_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.snapshot_events_id_seq OWNED BY public.snapshot_events.id;


--
-- Name: snapshot_votes; Type: TABLE; Schema: public; Owner: farming_user
--

CREATE TABLE public.snapshot_votes (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    proposal_id text NOT NULL,
    space text NOT NULL,
    choice text,
    voting_power numeric(18,8),
    voted_at timestamp with time zone,
    metadata jsonb,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.snapshot_votes OWNER TO farming_user;

--
-- Name: TABLE snapshot_votes; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON TABLE public.snapshot_votes IS 'Snapshot votes — target: 5-10 votes per Tier A wallet';


--
-- Name: COLUMN snapshot_votes.space; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.snapshot_votes.space IS 'Snapshot space: aave.eth, uniswap.eth, gitcoin.eth, etc.';


--
-- Name: COLUMN snapshot_votes.choice; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.snapshot_votes.choice IS 'Vote choice: for/against/abstain or custom (multi-choice proposals)';


--
-- Name: COLUMN snapshot_votes.voting_power; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.snapshot_votes.voting_power IS 'Voting power (based on token balance at snapshot block)';


--
-- Name: COLUMN snapshot_votes.metadata; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.snapshot_votes.metadata IS 'JSONB: {"title": "Proposal Title", "choices": ["Yes", "No"], "reason": "..."}';


--
-- Name: snapshot_votes_id_seq; Type: SEQUENCE; Schema: public; Owner: farming_user
--

CREATE SEQUENCE public.snapshot_votes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.snapshot_votes_id_seq OWNER TO farming_user;

--
-- Name: snapshot_votes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: farming_user
--

ALTER SEQUENCE public.snapshot_votes_id_seq OWNED BY public.snapshot_votes.id;


--
-- Name: system_config; Type: TABLE; Schema: public; Owner: farming_user
--

CREATE TABLE public.system_config (
    key character varying(100) NOT NULL,
    value text NOT NULL,
    value_type character varying(20) DEFAULT 'string'::character varying NOT NULL,
    description text,
    category character varying(50),
    is_sensitive boolean DEFAULT false,
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.system_config OWNER TO farming_user;

--
-- Name: TABLE system_config; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON TABLE public.system_config IS 'System-wide configuration settings. Replaces hardcoded values in code.';


--
-- Name: COLUMN system_config.key; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.system_config.key IS 'Configuration key (e.g., "decodo_ttl_minutes")';


--
-- Name: COLUMN system_config.value; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.system_config.value IS 'Configuration value (stored as TEXT, parsed by type)';


--
-- Name: COLUMN system_config.value_type; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.system_config.value_type IS 'Value type: string, integer, float, boolean, json';


--
-- Name: COLUMN system_config.description; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.system_config.description IS 'Human-readable description of the setting';


--
-- Name: COLUMN system_config.category; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.system_config.category IS 'Category for grouping (e.g., "proxy", "gas", "validation")';


--
-- Name: COLUMN system_config.is_sensitive; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.system_config.is_sensitive IS 'Whether value contains sensitive data (passwords, keys)';


--
-- Name: COLUMN system_config.updated_at; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.system_config.updated_at IS 'Last update timestamp';


--
-- Name: system_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.system_events (
    id integer NOT NULL,
    event_type character varying(100) NOT NULL,
    severity public.event_severity NOT NULL,
    component character varying(100),
    message text NOT NULL,
    metadata jsonb,
    telegram_sent boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.system_events OWNER TO postgres;

--
-- Name: TABLE system_events; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.system_events IS 'System events log for monitoring and Telegram alerts';


--
-- Name: system_events_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.system_events_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.system_events_id_seq OWNER TO postgres;

--
-- Name: system_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.system_events_id_seq OWNED BY public.system_events.id;


--
-- Name: system_state; Type: TABLE; Schema: public; Owner: farming_user
--

CREATE TABLE public.system_state (
    key character varying(100) NOT NULL,
    value boolean DEFAULT false NOT NULL,
    updated_at timestamp with time zone DEFAULT now(),
    updated_by character varying(255),
    metadata jsonb
);


ALTER TABLE public.system_state OWNER TO farming_user;

--
-- Name: token_check_cache; Type: TABLE; Schema: public; Owner: farming_user
--

CREATE TABLE public.token_check_cache (
    protocol_name character varying(100) NOT NULL,
    has_token boolean NOT NULL,
    ticker character varying(20),
    market_cap_usd numeric,
    checked_at timestamp with time zone NOT NULL,
    source character varying(20) NOT NULL
);


ALTER TABLE public.token_check_cache OWNER TO farming_user;

--
-- Name: TABLE token_check_cache; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON TABLE public.token_check_cache IS 'Cache for token existence checks - used by Smart Risk Engine to skip protocols with existing tokens';


--
-- Name: COLUMN token_check_cache.protocol_name; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.token_check_cache.protocol_name IS 'Protocol/chain name to check (e.g., "arbitrum", "uniswap")';


--
-- Name: COLUMN token_check_cache.has_token; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.token_check_cache.has_token IS 'TRUE if protocol has its own token listed on CoinGecko/DeFiLlama';


--
-- Name: COLUMN token_check_cache.ticker; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.token_check_cache.ticker IS 'Token ticker symbol (e.g., "ARB", "UNI")';


--
-- Name: COLUMN token_check_cache.market_cap_usd; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.token_check_cache.market_cap_usd IS 'Market cap in USD from CoinGecko';


--
-- Name: COLUMN token_check_cache.checked_at; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.token_check_cache.checked_at IS 'Timestamp of last check - cache expires after 24 hours';


--
-- Name: COLUMN token_check_cache.source; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.token_check_cache.source IS 'Data source: "coingecko" or "defillama"';


--
-- Name: v_bridge_stats_by_network; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_bridge_stats_by_network AS
 SELECT to_network,
    count(*) AS total_bridges,
    count(*) FILTER (WHERE ((status)::text = 'completed'::text)) AS successful_bridges,
    count(*) FILTER (WHERE ((status)::text = 'failed'::text)) AS failed_bridges,
    avg(cost_usd) AS avg_cost_usd,
    avg(safety_score) AS avg_safety_score,
    sum(amount_eth) AS total_eth_bridged
   FROM public.bridge_history
  GROUP BY to_network
  ORDER BY (count(*)) DESC;


ALTER VIEW public.v_bridge_stats_by_network OWNER TO postgres;

--
-- Name: VIEW v_bridge_stats_by_network; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.v_bridge_stats_by_network IS 'Bridge statistics by destination network';


--
-- Name: wallets; Type: TABLE; Schema: public; Owner: farming_user
--

CREATE TABLE public.wallets (
    id integer NOT NULL,
    address character varying(42) NOT NULL,
    encrypted_private_key text NOT NULL,
    tier public.wallet_tier NOT NULL,
    worker_node_id integer NOT NULL,
    proxy_id integer NOT NULL,
    status public.wallet_status DEFAULT 'inactive'::public.wallet_status,
    last_funded_at timestamp with time zone,
    first_tx_at timestamp with time zone,
    last_tx_at timestamp with time zone,
    total_tx_count integer DEFAULT 0,
    openclaw_enabled boolean DEFAULT false,
    post_snapshot_active_until timestamp with time zone,
    reputation_score numeric(5,2) DEFAULT 0,
    notes text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    authorized_withdrawal_address character varying(42),
    warmup_status character varying(20) DEFAULT 'inactive'::character varying,
    warmup_completed_at timestamp without time zone,
    funding_cex_subaccount_id integer,
    funding_network character varying(50),
    funding_chain_id integer,
    withdrawal_network character varying(100),
    CONSTRAINT check_authorized_address_format CHECK (((authorized_withdrawal_address IS NULL) OR ((authorized_withdrawal_address)::text ~* '^0x[a-fA-F0-9]{40}$'::text))),
    CONSTRAINT check_authorized_not_burn_address CHECK (((authorized_withdrawal_address IS NULL) OR ((authorized_withdrawal_address)::text <> ALL ((ARRAY['0x0000000000000000000000000000000000000000'::character varying, '0x000000000000000000000000000000000000dead'::character varying, '0xdead000000000000000042069420694206942069'::character varying])::text[])))),
    CONSTRAINT chk_address_format CHECK (((address)::text ~ '^0x[a-fA-F0-9]{40}$'::text)),
    CONSTRAINT wallets_funding_network_check CHECK (((funding_network)::text = ANY ((ARRAY['Base'::character varying, 'Arbitrum'::character varying, 'Polygon'::character varying, 'BNB Chain'::character varying, 'Optimism'::character varying, 'Ink'::character varying, 'MegaETH'::character varying])::text[]))),
    CONSTRAINT wallets_warmup_status_check CHECK (((warmup_status)::text = ANY ((ARRAY['inactive'::character varying, 'warming_up'::character varying, 'active'::character varying])::text[])))
);


ALTER TABLE public.wallets OWNER TO farming_user;

--
-- Name: TABLE wallets; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON TABLE public.wallets IS '90 wallets: 18 Tier A (OpenClaw), 45 Tier B, 27 Tier C';


--
-- Name: COLUMN wallets.last_funded_at; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.wallets.last_funded_at IS 'CEX funding time - used for 2-4h bridge emulation delay';


--
-- Name: COLUMN wallets.first_tx_at; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.wallets.first_tx_at IS 'Timestamp of first transaction after funding';


--
-- Name: COLUMN wallets.openclaw_enabled; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.wallets.openclaw_enabled IS 'TRUE only for 18 Tier A wallets';


--
-- Name: COLUMN wallets.authorized_withdrawal_address; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.wallets.authorized_withdrawal_address IS '🔒 CRITICAL SECURITY: Only address allowed for withdrawals from this wallet.
     Set automatically during funding (from CEX subaccount withdrawal_address).
     Prevents accidental loss of funds to burn addresses or wrong destinations.
     NULL = wallet not yet funded / address not set.
     
     Security Policy:
     - Set by funding engine when wallet receives funds from CEX
     - Cannot be changed without human approval (Telegram confirmation)
     - All withdrawal plans MUST use this address (enforced by code)
     - Provides defense in depth against bugs and typos';


--
-- Name: COLUMN wallets.warmup_status; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.wallets.warmup_status IS 'Wallet warm-up state: inactive → warming_up → active';


--
-- Name: COLUMN wallets.warmup_completed_at; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.wallets.warmup_completed_at IS 'Timestamp when warm-up phase completed (3+ successful transactions)';


--
-- Name: COLUMN wallets.withdrawal_network; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON COLUMN public.wallets.withdrawal_network IS 'Network for final withdrawal to authorized address (e.g., arbitrum, base, optimism). Each wallet has a unique network within its CEX subaccount for anti-Sybil diversification.';


--
-- Name: v_direct_funding_schedule; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_direct_funding_schedule AS
 SELECT fw.id AS withdrawal_id,
    fw.cex_withdrawal_scheduled_at AS scheduled_time,
    cs.exchange,
    cs.subaccount_name,
    w.address AS target_wallet,
    w.tier,
    fw.amount_usdt,
    p.country_code AS proxy_region,
    fw.withdrawal_network,
    fw.interleave_round,
    fw.interleave_position,
    fw.status,
    (EXTRACT(epoch FROM (fw.cex_withdrawal_scheduled_at - now())) / (3600)::numeric) AS hours_until_execution,
        CASE
            WHEN (fw.cex_withdrawal_scheduled_at <= now()) THEN 'READY'::text
            WHEN (fw.cex_withdrawal_scheduled_at <= (now() + '01:00:00'::interval)) THEN 'UPCOMING'::text
            ELSE 'SCHEDULED'::text
        END AS execution_status
   FROM (((public.funding_withdrawals fw
     JOIN public.wallets w ON ((fw.wallet_id = w.id)))
     JOIN public.cex_subaccounts cs ON ((fw.cex_subaccount_id = cs.id)))
     JOIN public.proxy_pool p ON ((w.proxy_id = p.id)))
  WHERE (fw.direct_cex_withdrawal = true)
  ORDER BY fw.cex_withdrawal_scheduled_at;


ALTER VIEW public.v_direct_funding_schedule OWNER TO postgres;

--
-- Name: VIEW v_direct_funding_schedule; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.v_direct_funding_schedule IS 'Real-time view of direct funding schedule.
 Shows upcoming CEX withdrawals with execution status.';


--
-- Name: v_funding_interleave_quality; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_funding_interleave_quality AS
 SELECT fw.interleave_round,
    count(*) AS withdrawals_in_round,
    count(DISTINCT cs.exchange) AS unique_exchanges,
    count(DISTINCT cs.subaccount_name) AS unique_subaccounts,
    count(DISTINCT fw.withdrawal_network) AS unique_networks,
    count(DISTINCT p.country_code) AS unique_proxy_regions,
    min(fw.cex_withdrawal_scheduled_at) AS round_start,
    max(fw.cex_withdrawal_scheduled_at) AS round_end,
    (EXTRACT(epoch FROM (max(fw.cex_withdrawal_scheduled_at) - min(fw.cex_withdrawal_scheduled_at))) / (3600)::numeric) AS round_duration_hours
   FROM ((public.funding_withdrawals fw
     JOIN public.cex_subaccounts cs ON ((fw.cex_subaccount_id = cs.id)))
     JOIN public.proxy_pool p ON ((fw.wallet_id = p.id)))
  WHERE (fw.direct_cex_withdrawal = true)
  GROUP BY fw.interleave_round
  ORDER BY fw.interleave_round;


ALTER VIEW public.v_funding_interleave_quality OWNER TO postgres;

--
-- Name: VIEW v_funding_interleave_quality; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.v_funding_interleave_quality IS 'Quality metrics for interleaved execution.
 Each round should have high exchange/network/proxy diversity.';


--
-- Name: v_funding_temporal_distribution; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_funding_temporal_distribution AS
 WITH daily_stats AS (
         SELECT date_trunc('day'::text, fw.cex_withdrawal_scheduled_at) AS day,
            count(*) AS withdrawals_count,
            count(DISTINCT fw.cex_subaccount_id) AS unique_subaccounts,
            array_agg(DISTINCT cs.exchange) AS exchanges,
            avg(fw.amount_usdt) AS avg_amount_usdt
           FROM (public.funding_withdrawals fw
             JOIN public.cex_subaccounts cs ON ((fw.cex_subaccount_id = cs.id)))
          WHERE (fw.direct_cex_withdrawal = true)
          GROUP BY (date_trunc('day'::text, fw.cex_withdrawal_scheduled_at))
        )
 SELECT day,
    withdrawals_count,
    unique_subaccounts,
    exchanges,
    avg_amount_usdt,
    round((((withdrawals_count)::numeric / sum(withdrawals_count) OVER ()) * (100)::numeric), 2) AS percentage_of_total
   FROM daily_stats
  ORDER BY day;


ALTER VIEW public.v_funding_temporal_distribution OWNER TO postgres;

--
-- Name: VIEW v_funding_temporal_distribution; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.v_funding_temporal_distribution IS 'Daily breakdown of funding schedule.
 Should show relatively even distribution over 7 days (12-15 withdrawals/day).';


--
-- Name: v_protocols_requiring_bridge; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_protocols_requiring_bridge AS
 SELECT id AS protocol_id,
    name AS protocol_name,
    unnest(chains) AS chain,
    bridge_required,
    bridge_from_network,
    bridge_provider,
    cex_support
   FROM public.protocols p
  WHERE ((is_active = true) AND (bridge_required = true));


ALTER VIEW public.v_protocols_requiring_bridge OWNER TO postgres;

--
-- Name: VIEW v_protocols_requiring_bridge; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.v_protocols_requiring_bridge IS 'Protocols requiring bridge with unnested chains array';


--
-- Name: v_recent_bridges; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_recent_bridges AS
 SELECT bh.id,
    bh.wallet_id,
    w.address AS wallet_address,
    bh.from_network,
    bh.to_network,
    bh.amount_eth,
    bh.provider,
    bh.cost_usd,
    bh.safety_score,
    bh.status,
    bh.tx_hash,
    bh.created_at,
    bh.completed_at,
    bh.cex_support_found
   FROM (public.bridge_history bh
     JOIN public.wallets w ON ((w.id = bh.wallet_id)))
  ORDER BY bh.created_at DESC
 LIMIT 100;


ALTER VIEW public.v_recent_bridges OWNER TO postgres;

--
-- Name: VIEW v_recent_bridges; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.v_recent_bridges IS 'Recent bridge operations for monitoring';


--
-- Name: v_subaccount_usage; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_subaccount_usage AS
 SELECT cs.id,
    cs.exchange,
    cs.subaccount_name,
    fc.id AS funding_chain_id,
    fc.chain_number,
    fc.actual_wallet_count,
    fc.withdrawal_network,
    fc.status,
    fc.created_at
   FROM (public.cex_subaccounts cs
     LEFT JOIN public.funding_chains fc ON ((cs.id = fc.cex_subaccount_id)))
  ORDER BY cs.exchange, cs.subaccount_name;


ALTER VIEW public.v_subaccount_usage OWNER TO postgres;

--
-- Name: VIEW v_subaccount_usage; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.v_subaccount_usage IS 'Shows which funding chains use which CEX subaccounts (should be 1:1)';


--
-- Name: v_wallets_funding_info; Type: VIEW; Schema: public; Owner: farming_user
--

CREATE VIEW public.v_wallets_funding_info AS
 SELECT w.id AS wallet_id,
    w.address,
    w.tier,
    cs.exchange,
    cs.subaccount_name,
    w.funding_network,
    w.funding_chain_id,
    fc.chain_number,
    fc.actual_wallet_count AS cluster_size
   FROM ((public.wallets w
     LEFT JOIN public.cex_subaccounts cs ON ((w.funding_cex_subaccount_id = cs.id)))
     LEFT JOIN public.funding_chains fc ON ((w.funding_chain_id = fc.id)))
  ORDER BY cs.exchange, cs.subaccount_name, w.funding_network, w.address;


ALTER VIEW public.v_wallets_funding_info OWNER TO farming_user;

--
-- Name: wallet_personas; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wallet_personas (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    persona_type public.persona_type NOT NULL,
    preferred_hours integer[] NOT NULL,
    tx_per_week_mean numeric(4,2) NOT NULL,
    tx_per_week_stddev numeric(4,2) NOT NULL,
    skip_week_probability numeric(3,2) DEFAULT 0.05,
    tx_weight_swap numeric(3,2) NOT NULL,
    tx_weight_bridge numeric(3,2) NOT NULL,
    tx_weight_liquidity numeric(3,2) NOT NULL,
    tx_weight_stake numeric(3,2) NOT NULL,
    tx_weight_nft numeric(3,2) NOT NULL,
    slippage_tolerance numeric(4,2) NOT NULL,
    gas_preference public.gas_preference NOT NULL,
    gas_preference_weights jsonb NOT NULL,
    amount_noise_pct numeric(3,2) DEFAULT 0.05,
    time_noise_minutes integer DEFAULT 10,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT chk_tx_weights_sum CHECK (((((((tx_weight_swap + tx_weight_bridge) + tx_weight_liquidity) + tx_weight_stake) + tx_weight_nft) >= 0.99) AND (((((tx_weight_swap + tx_weight_bridge) + tx_weight_liquidity) + tx_weight_stake) + tx_weight_nft) <= 1.01)))
);


ALTER TABLE public.wallet_personas OWNER TO postgres;

--
-- Name: TABLE wallet_personas; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.wallet_personas IS '90 unique behavioral personas - CRITICAL for Anti-Sybil';


--
-- Name: COLUMN wallet_personas.preferred_hours; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.wallet_personas.preferred_hours IS 'Active hours array aligned with worker timezone (UTC+1 for NL, UTC+0 for IS)';


--
-- Name: COLUMN wallet_personas.slippage_tolerance; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.wallet_personas.slippage_tolerance IS 'Unique per wallet: 0.33%-1.10% to avoid clustering';


--
-- Name: COLUMN wallet_personas.amount_noise_pct; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.wallet_personas.amount_noise_pct IS 'Add ±3-8% noise to all transaction amounts';


--
-- Name: wallet_personas_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wallet_personas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wallet_personas_id_seq OWNER TO postgres;

--
-- Name: wallet_personas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wallet_personas_id_seq OWNED BY public.wallet_personas.id;


--
-- Name: wallet_points_balances; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wallet_points_balances (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    points_program_id integer NOT NULL,
    points_amount numeric(18,2) DEFAULT 0,
    last_updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.wallet_points_balances OWNER TO postgres;

--
-- Name: TABLE wallet_points_balances; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.wallet_points_balances IS 'Points balances for each wallet in each program';


--
-- Name: wallet_points_balances_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wallet_points_balances_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wallet_points_balances_id_seq OWNER TO postgres;

--
-- Name: wallet_points_balances_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wallet_points_balances_id_seq OWNED BY public.wallet_points_balances.id;


--
-- Name: wallet_protocol_assignments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wallet_protocol_assignments (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    protocol_id integer NOT NULL,
    assigned_at timestamp with time zone DEFAULT now(),
    interaction_count integer DEFAULT 0,
    last_interaction_at timestamp with time zone
);


ALTER TABLE public.wallet_protocol_assignments OWNER TO postgres;

--
-- Name: TABLE wallet_protocol_assignments; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.wallet_protocol_assignments IS 'Which protocols each wallet should interact with';


--
-- Name: wallet_protocol_assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wallet_protocol_assignments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wallet_protocol_assignments_id_seq OWNER TO postgres;

--
-- Name: wallet_protocol_assignments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wallet_protocol_assignments_id_seq OWNED BY public.wallet_protocol_assignments.id;


--
-- Name: wallet_tokens; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wallet_tokens (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    chain character varying(50) NOT NULL,
    token_contract_address character varying(42) NOT NULL,
    token_symbol character varying(50) NOT NULL,
    token_name text,
    decimals integer NOT NULL,
    balance numeric(78,0) NOT NULL,
    balance_human numeric(30,18),
    first_detected_at timestamp with time zone DEFAULT now(),
    last_updated timestamp with time zone DEFAULT now(),
    CONSTRAINT wallet_tokens_decimals_check CHECK (((decimals >= 0) AND (decimals <= 78)))
);


ALTER TABLE public.wallet_tokens OWNER TO postgres;

--
-- Name: TABLE wallet_tokens; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.wallet_tokens IS 'Detected token balances on wallets (Module 17)';


--
-- Name: COLUMN wallet_tokens.balance; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.wallet_tokens.balance IS 'Raw balance as returned by Explorer API (need to divide by 10^decimals)';


--
-- Name: COLUMN wallet_tokens.balance_human; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.wallet_tokens.balance_human IS 'Human-readable balance for display in Telegram / UI';


--
-- Name: COLUMN wallet_tokens.first_detected_at; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.wallet_tokens.first_detected_at IS 'Timestamp when token was first detected (for airdrop timing analysis)';


--
-- Name: wallet_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wallet_tokens_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wallet_tokens_id_seq OWNER TO postgres;

--
-- Name: wallet_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wallet_tokens_id_seq OWNED BY public.wallet_tokens.id;


--
-- Name: wallet_transactions; Type: TABLE; Schema: public; Owner: farming_user
--

CREATE TABLE public.wallet_transactions (
    id integer NOT NULL,
    wallet_id integer,
    protocol_action_id integer,
    tx_hash character varying(66) NOT NULL,
    chain character varying(50) NOT NULL,
    from_address character varying(42) NOT NULL,
    to_address character varying(42),
    value numeric,
    gas_used numeric,
    status character varying(20) NOT NULL,
    block_number integer,
    confirmed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.wallet_transactions OWNER TO farming_user;

--
-- Name: TABLE wallet_transactions; Type: COMMENT; Schema: public; Owner: farming_user
--

COMMENT ON TABLE public.wallet_transactions IS 'History of executed on-chain transactions';


--
-- Name: wallet_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: farming_user
--

CREATE SEQUENCE public.wallet_transactions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wallet_transactions_id_seq OWNER TO farming_user;

--
-- Name: wallet_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: farming_user
--

ALTER SEQUENCE public.wallet_transactions_id_seq OWNED BY public.wallet_transactions.id;


--
-- Name: wallet_withdrawal_address_history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wallet_withdrawal_address_history (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    old_address character varying(42),
    new_address character varying(42) NOT NULL,
    changed_by character varying(100) NOT NULL,
    change_reason text NOT NULL,
    approval_status character varying(50) DEFAULT 'pending'::character varying,
    approved_by character varying(100),
    approved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT wallet_withdrawal_address_history_approval_status_check CHECK (((approval_status)::text = ANY ((ARRAY['pending'::character varying, 'approved'::character varying, 'rejected'::character varying])::text[]))),
    CONSTRAINT wallet_withdrawal_address_history_new_address_check CHECK (((new_address)::text ~* '^0x[a-fA-F0-9]{40}$'::text))
);


ALTER TABLE public.wallet_withdrawal_address_history OWNER TO postgres;

--
-- Name: TABLE wallet_withdrawal_address_history; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.wallet_withdrawal_address_history IS 'Complete audit trail for all changes to authorized_withdrawal_address.
     Every change requires:
     - Reason (mandatory text field)
     - Changed by (system or operator username)
     - Approval workflow (for manual changes)';


--
-- Name: COLUMN wallet_withdrawal_address_history.changed_by; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.wallet_withdrawal_address_history.changed_by IS 'Who initiated the change:
     - "system" = Automatic during funding setup
     - "operator_username" = Manual change (emergency only)';


--
-- Name: COLUMN wallet_withdrawal_address_history.change_reason; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.wallet_withdrawal_address_history.change_reason IS 'Mandatory reason for change:
     - "Initial funding setup from CEX subaccount" (system)
     - "Cold wallet compromised, changing to backup" (manual)
     - "Correcting incorrect initial address" (manual)';


--
-- Name: wallet_withdrawal_address_history_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.wallet_withdrawal_address_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wallet_withdrawal_address_history_id_seq OWNER TO postgres;

--
-- Name: wallet_withdrawal_address_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.wallet_withdrawal_address_history_id_seq OWNED BY public.wallet_withdrawal_address_history.id;


--
-- Name: wallet_withdrawal_security_status; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.wallet_withdrawal_security_status AS
 SELECT id AS wallet_id,
    address AS wallet_address,
    tier,
    status AS wallet_status,
    authorized_withdrawal_address,
    last_funded_at,
        CASE
            WHEN (authorized_withdrawal_address IS NULL) THEN 'NOT_SET'::text
            WHEN ((authorized_withdrawal_address)::text = ANY ((ARRAY['0x0000000000000000000000000000000000000000'::character varying, '0x000000000000000000000000000000000000dead'::character varying, '0xdead000000000000000042069420694206942069'::character varying])::text[])) THEN 'BURN_ADDRESS_DANGER'::text
            ELSE 'OK'::text
        END AS security_status,
    ( SELECT count(*) AS count
           FROM public.wallet_withdrawal_address_history wwah
          WHERE (wwah.wallet_id = w.id)) AS address_change_count,
    ( SELECT max(wwah.created_at) AS max
           FROM public.wallet_withdrawal_address_history wwah
          WHERE (wwah.wallet_id = w.id)) AS last_address_change_at
   FROM public.wallets w
  ORDER BY id;


ALTER VIEW public.wallet_withdrawal_security_status OWNER TO postgres;

--
-- Name: VIEW wallet_withdrawal_security_status; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON VIEW public.wallet_withdrawal_security_status IS 'Security monitoring view for authorized withdrawal addresses.
     Flags:
     - NOT_SET: Wallet not yet funded or address not configured
     - BURN_ADDRESS_DANGER: CRITICAL - authorized address is burn address (should never happen)
     - OK: Normal state';


--
-- Name: wallets_id_seq; Type: SEQUENCE; Schema: public; Owner: farming_user
--

CREATE SEQUENCE public.wallets_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.wallets_id_seq OWNER TO farming_user;

--
-- Name: wallets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: farming_user
--

ALTER SEQUENCE public.wallets_id_seq OWNED BY public.wallets.id;


--
-- Name: weekly_plans; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.weekly_plans (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    week_start_date date NOT NULL,
    planned_tx_count integer NOT NULL,
    actual_tx_count integer DEFAULT 0,
    is_skipped boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.weekly_plans OWNER TO postgres;

--
-- Name: TABLE weekly_plans; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.weekly_plans IS 'Weekly transaction plans generated by Gaussian scheduler';


--
-- Name: weekly_plans_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.weekly_plans_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.weekly_plans_id_seq OWNER TO postgres;

--
-- Name: weekly_plans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.weekly_plans_id_seq OWNED BY public.weekly_plans.id;


--
-- Name: withdrawal_plans; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.withdrawal_plans (
    id integer NOT NULL,
    wallet_id integer NOT NULL,
    tier public.wallet_tier NOT NULL,
    total_steps integer NOT NULL,
    current_step integer DEFAULT 0,
    status public.withdrawal_status DEFAULT 'planned'::public.withdrawal_status,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.withdrawal_plans OWNER TO postgres;

--
-- Name: TABLE withdrawal_plans; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.withdrawal_plans IS 'Multi-stage withdrawal plans (A: 4 steps, B: 3, C: 2)';


--
-- Name: withdrawal_plans_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.withdrawal_plans_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.withdrawal_plans_id_seq OWNER TO postgres;

--
-- Name: withdrawal_plans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.withdrawal_plans_id_seq OWNED BY public.withdrawal_plans.id;


--
-- Name: withdrawal_steps; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.withdrawal_steps (
    id integer NOT NULL,
    withdrawal_plan_id integer NOT NULL,
    step_number integer NOT NULL,
    percentage numeric(5,2) NOT NULL,
    destination_address character varying(42) NOT NULL,
    status public.withdrawal_status DEFAULT 'planned'::public.withdrawal_status,
    scheduled_at timestamp with time zone,
    approved_at timestamp with time zone,
    approved_by character varying(100),
    executed_at timestamp with time zone,
    tx_hash character varying(66),
    amount_usdt numeric(10,4),
    created_at timestamp with time zone DEFAULT now()
);


ALTER TABLE public.withdrawal_steps OWNER TO postgres;

--
-- Name: TABLE withdrawal_steps; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.withdrawal_steps IS 'Individual withdrawal steps requiring Telegram approval';


--
-- Name: withdrawal_steps_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.withdrawal_steps_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.withdrawal_steps_id_seq OWNER TO postgres;

--
-- Name: withdrawal_steps_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.withdrawal_steps_id_seq OWNED BY public.withdrawal_steps.id;


--
-- Name: worker_nodes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.worker_nodes (
    id integer NOT NULL,
    worker_id integer NOT NULL,
    hostname character varying(255) NOT NULL,
    ip_address inet NOT NULL,
    location character varying(100) NOT NULL,
    timezone character varying(50) NOT NULL,
    utc_offset integer NOT NULL,
    status character varying(50) DEFAULT 'active'::character varying,
    last_heartbeat timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT worker_nodes_worker_id_check CHECK (((worker_id >= 1) AND (worker_id <= 3)))
);


ALTER TABLE public.worker_nodes OWNER TO postgres;

--
-- Name: TABLE worker_nodes; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.worker_nodes IS 'Worker nodes configuration - 3 workers (1 NL, 2 IS)';


--
-- Name: COLUMN worker_nodes.worker_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.worker_nodes.worker_id IS 'Worker ID: 1 (NL), 2-3 (IS)';


--
-- Name: COLUMN worker_nodes.utc_offset; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.worker_nodes.utc_offset IS 'UTC offset: +1 for NL, 0 for IS';


--
-- Name: worker_nodes_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.worker_nodes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.worker_nodes_id_seq OWNER TO postgres;

--
-- Name: worker_nodes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.worker_nodes_id_seq OWNED BY public.worker_nodes.id;


--
-- Name: airdrop_scan_logs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.airdrop_scan_logs ALTER COLUMN id SET DEFAULT nextval('public.airdrop_scan_logs_id_seq'::regclass);


--
-- Name: airdrops id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.airdrops ALTER COLUMN id SET DEFAULT nextval('public.airdrops_id_seq'::regclass);


--
-- Name: bridge_history id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bridge_history ALTER COLUMN id SET DEFAULT nextval('public.bridge_history_id_seq'::regclass);


--
-- Name: cex_networks_cache id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cex_networks_cache ALTER COLUMN id SET DEFAULT nextval('public.cex_networks_cache_id_seq'::regclass);


--
-- Name: cex_subaccounts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cex_subaccounts ALTER COLUMN id SET DEFAULT nextval('public.cex_subaccounts_id_seq'::regclass);


--
-- Name: chain_aliases id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chain_aliases ALTER COLUMN id SET DEFAULT nextval('public.chain_aliases_id_seq'::regclass);


--
-- Name: chain_rpc_endpoints id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chain_rpc_endpoints ALTER COLUMN id SET DEFAULT nextval('public.chain_rpc_endpoints_id_seq'::regclass);


--
-- Name: chain_rpc_health_log id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chain_rpc_health_log ALTER COLUMN id SET DEFAULT nextval('public.chain_rpc_health_log_id_seq'::regclass);


--
-- Name: chain_tokens id; Type: DEFAULT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.chain_tokens ALTER COLUMN id SET DEFAULT nextval('public.chain_tokens_id_seq'::regclass);


--
-- Name: defillama_bridges_cache id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.defillama_bridges_cache ALTER COLUMN id SET DEFAULT nextval('public.defillama_bridges_cache_id_seq'::regclass);


--
-- Name: discovery_failures id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discovery_failures ALTER COLUMN id SET DEFAULT nextval('public.discovery_failures_id_seq'::regclass);


--
-- Name: ens_names id; Type: DEFAULT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.ens_names ALTER COLUMN id SET DEFAULT nextval('public.ens_names_id_seq'::regclass);


--
-- Name: funding_chains id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.funding_chains ALTER COLUMN id SET DEFAULT nextval('public.funding_chains_id_seq'::regclass);


--
-- Name: funding_withdrawals id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.funding_withdrawals ALTER COLUMN id SET DEFAULT nextval('public.funding_withdrawals_id_seq'::regclass);


--
-- Name: gas_history id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gas_history ALTER COLUMN id SET DEFAULT nextval('public.gas_history_id_seq'::regclass);


--
-- Name: gas_snapshots id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gas_snapshots ALTER COLUMN id SET DEFAULT nextval('public.gas_snapshots_id_seq'::regclass);


--
-- Name: gitcoin_stamps id; Type: DEFAULT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.gitcoin_stamps ALTER COLUMN id SET DEFAULT nextval('public.gitcoin_stamps_id_seq'::regclass);


--
-- Name: lens_profiles id; Type: DEFAULT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.lens_profiles ALTER COLUMN id SET DEFAULT nextval('public.lens_profiles_id_seq'::regclass);


--
-- Name: news_items id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.news_items ALTER COLUMN id SET DEFAULT nextval('public.news_items_id_seq'::regclass);


--
-- Name: openclaw_profiles id; Type: DEFAULT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.openclaw_profiles ALTER COLUMN id SET DEFAULT nextval('public.openclaw_profiles_id_seq'::regclass);


--
-- Name: openclaw_reputation id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.openclaw_reputation ALTER COLUMN id SET DEFAULT nextval('public.openclaw_reputation_id_seq'::regclass);


--
-- Name: openclaw_task_history id; Type: DEFAULT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.openclaw_task_history ALTER COLUMN id SET DEFAULT nextval('public.openclaw_task_history_id_seq'::regclass);


--
-- Name: openclaw_tasks id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.openclaw_tasks ALTER COLUMN id SET DEFAULT nextval('public.openclaw_tasks_id_seq'::regclass);


--
-- Name: personas_config id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.personas_config ALTER COLUMN id SET DEFAULT nextval('public.personas_config_id_seq'::regclass);


--
-- Name: poap_tokens id; Type: DEFAULT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.poap_tokens ALTER COLUMN id SET DEFAULT nextval('public.poap_tokens_id_seq'::regclass);


--
-- Name: points_programs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.points_programs ALTER COLUMN id SET DEFAULT nextval('public.points_programs_id_seq'::regclass);


--
-- Name: protocol_actions id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_actions ALTER COLUMN id SET DEFAULT nextval('public.protocol_actions_id_seq'::regclass);


--
-- Name: protocol_contracts id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_contracts ALTER COLUMN id SET DEFAULT nextval('public.protocol_contracts_id_seq'::regclass);


--
-- Name: protocol_research_pending id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_research_pending ALTER COLUMN id SET DEFAULT nextval('public.protocol_research_pending_id_seq'::regclass);


--
-- Name: protocol_research_reports id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_research_reports ALTER COLUMN id SET DEFAULT nextval('public.protocol_research_reports_id_seq'::regclass);


--
-- Name: protocols id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocols ALTER COLUMN id SET DEFAULT nextval('public.protocols_id_seq'::regclass);


--
-- Name: proxy_pool id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.proxy_pool ALTER COLUMN id SET DEFAULT nextval('public.proxy_pool_id_seq'::regclass);


--
-- Name: research_logs id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.research_logs ALTER COLUMN id SET DEFAULT nextval('public.research_logs_id_seq'::regclass);


--
-- Name: safety_gates id; Type: DEFAULT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.safety_gates ALTER COLUMN id SET DEFAULT nextval('public.safety_gates_id_seq'::regclass);


--
-- Name: scheduled_transactions id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scheduled_transactions ALTER COLUMN id SET DEFAULT nextval('public.scheduled_transactions_id_seq'::regclass);


--
-- Name: snapshot_events id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.snapshot_events ALTER COLUMN id SET DEFAULT nextval('public.snapshot_events_id_seq'::regclass);


--
-- Name: snapshot_votes id; Type: DEFAULT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.snapshot_votes ALTER COLUMN id SET DEFAULT nextval('public.snapshot_votes_id_seq'::regclass);


--
-- Name: system_events id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.system_events ALTER COLUMN id SET DEFAULT nextval('public.system_events_id_seq'::regclass);


--
-- Name: wallet_personas id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_personas ALTER COLUMN id SET DEFAULT nextval('public.wallet_personas_id_seq'::regclass);


--
-- Name: wallet_points_balances id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_points_balances ALTER COLUMN id SET DEFAULT nextval('public.wallet_points_balances_id_seq'::regclass);


--
-- Name: wallet_protocol_assignments id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_protocol_assignments ALTER COLUMN id SET DEFAULT nextval('public.wallet_protocol_assignments_id_seq'::regclass);


--
-- Name: wallet_tokens id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_tokens ALTER COLUMN id SET DEFAULT nextval('public.wallet_tokens_id_seq'::regclass);


--
-- Name: wallet_transactions id; Type: DEFAULT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.wallet_transactions ALTER COLUMN id SET DEFAULT nextval('public.wallet_transactions_id_seq'::regclass);


--
-- Name: wallet_withdrawal_address_history id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_withdrawal_address_history ALTER COLUMN id SET DEFAULT nextval('public.wallet_withdrawal_address_history_id_seq'::regclass);


--
-- Name: wallets id; Type: DEFAULT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.wallets ALTER COLUMN id SET DEFAULT nextval('public.wallets_id_seq'::regclass);


--
-- Name: weekly_plans id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.weekly_plans ALTER COLUMN id SET DEFAULT nextval('public.weekly_plans_id_seq'::regclass);


--
-- Name: withdrawal_plans id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.withdrawal_plans ALTER COLUMN id SET DEFAULT nextval('public.withdrawal_plans_id_seq'::regclass);


--
-- Name: withdrawal_steps id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.withdrawal_steps ALTER COLUMN id SET DEFAULT nextval('public.withdrawal_steps_id_seq'::regclass);


--
-- Name: worker_nodes id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.worker_nodes ALTER COLUMN id SET DEFAULT nextval('public.worker_nodes_id_seq'::regclass);


--
-- Name: airdrop_scan_logs airdrop_scan_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.airdrop_scan_logs
    ADD CONSTRAINT airdrop_scan_logs_pkey PRIMARY KEY (id);


--
-- Name: airdrops airdrops_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.airdrops
    ADD CONSTRAINT airdrops_pkey PRIMARY KEY (id);


--
-- Name: bridge_history bridge_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bridge_history
    ADD CONSTRAINT bridge_history_pkey PRIMARY KEY (id);


--
-- Name: cex_networks_cache cex_networks_cache_cex_name_coin_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cex_networks_cache
    ADD CONSTRAINT cex_networks_cache_cex_name_coin_key UNIQUE (cex_name, coin);


--
-- Name: cex_networks_cache cex_networks_cache_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cex_networks_cache
    ADD CONSTRAINT cex_networks_cache_pkey PRIMARY KEY (id);


--
-- Name: cex_subaccounts cex_subaccounts_exchange_subaccount_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cex_subaccounts
    ADD CONSTRAINT cex_subaccounts_exchange_subaccount_name_key UNIQUE (exchange, subaccount_name);


--
-- Name: cex_subaccounts cex_subaccounts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cex_subaccounts
    ADD CONSTRAINT cex_subaccounts_pkey PRIMARY KEY (id);


--
-- Name: chain_aliases chain_aliases_alias_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chain_aliases
    ADD CONSTRAINT chain_aliases_alias_unique UNIQUE (alias);


--
-- Name: chain_aliases chain_aliases_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chain_aliases
    ADD CONSTRAINT chain_aliases_pkey PRIMARY KEY (id);


--
-- Name: chain_rpc_endpoints chain_rpc_endpoints_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chain_rpc_endpoints
    ADD CONSTRAINT chain_rpc_endpoints_pkey PRIMARY KEY (id);


--
-- Name: chain_rpc_health_log chain_rpc_health_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chain_rpc_health_log
    ADD CONSTRAINT chain_rpc_health_log_pkey PRIMARY KEY (id);


--
-- Name: chain_tokens chain_tokens_chain_id_token_symbol_key; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.chain_tokens
    ADD CONSTRAINT chain_tokens_chain_id_token_symbol_key UNIQUE (chain_id, token_symbol);


--
-- Name: chain_tokens chain_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.chain_tokens
    ADD CONSTRAINT chain_tokens_pkey PRIMARY KEY (id);


--
-- Name: defillama_bridges_cache defillama_bridges_cache_bridge_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.defillama_bridges_cache
    ADD CONSTRAINT defillama_bridges_cache_bridge_name_key UNIQUE (bridge_name);


--
-- Name: defillama_bridges_cache defillama_bridges_cache_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.defillama_bridges_cache
    ADD CONSTRAINT defillama_bridges_cache_pkey PRIMARY KEY (id);


--
-- Name: discovery_failures discovery_failures_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.discovery_failures
    ADD CONSTRAINT discovery_failures_pkey PRIMARY KEY (id);


--
-- Name: ens_names ens_names_pkey; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.ens_names
    ADD CONSTRAINT ens_names_pkey PRIMARY KEY (id);


--
-- Name: ens_names ens_names_wallet_id_ens_name_key; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.ens_names
    ADD CONSTRAINT ens_names_wallet_id_ens_name_key UNIQUE (wallet_id, ens_name);


--
-- Name: funding_chains funding_chains_chain_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.funding_chains
    ADD CONSTRAINT funding_chains_chain_number_key UNIQUE (chain_number);


--
-- Name: funding_chains funding_chains_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.funding_chains
    ADD CONSTRAINT funding_chains_pkey PRIMARY KEY (id);


--
-- Name: funding_withdrawals funding_withdrawals_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.funding_withdrawals
    ADD CONSTRAINT funding_withdrawals_pkey PRIMARY KEY (id);


--
-- Name: gas_history gas_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gas_history
    ADD CONSTRAINT gas_history_pkey PRIMARY KEY (id);


--
-- Name: gas_snapshots gas_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gas_snapshots
    ADD CONSTRAINT gas_snapshots_pkey PRIMARY KEY (id);


--
-- Name: gitcoin_stamps gitcoin_stamps_pkey; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.gitcoin_stamps
    ADD CONSTRAINT gitcoin_stamps_pkey PRIMARY KEY (id);


--
-- Name: gitcoin_stamps gitcoin_stamps_wallet_id_stamp_type_key; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.gitcoin_stamps
    ADD CONSTRAINT gitcoin_stamps_wallet_id_stamp_type_key UNIQUE (wallet_id, stamp_type);


--
-- Name: lens_profiles lens_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.lens_profiles
    ADD CONSTRAINT lens_profiles_pkey PRIMARY KEY (id);


--
-- Name: lens_profiles lens_profiles_wallet_id_key; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.lens_profiles
    ADD CONSTRAINT lens_profiles_wallet_id_key UNIQUE (wallet_id);


--
-- Name: news_items news_items_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.news_items
    ADD CONSTRAINT news_items_pkey PRIMARY KEY (id);


--
-- Name: news_items news_items_url_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.news_items
    ADD CONSTRAINT news_items_url_key UNIQUE (url);


--
-- Name: openclaw_profiles openclaw_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.openclaw_profiles
    ADD CONSTRAINT openclaw_profiles_pkey PRIMARY KEY (id);


--
-- Name: openclaw_profiles openclaw_profiles_wallet_id_key; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.openclaw_profiles
    ADD CONSTRAINT openclaw_profiles_wallet_id_key UNIQUE (wallet_id);


--
-- Name: openclaw_reputation openclaw_reputation_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.openclaw_reputation
    ADD CONSTRAINT openclaw_reputation_pkey PRIMARY KEY (id);


--
-- Name: openclaw_reputation openclaw_reputation_wallet_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.openclaw_reputation
    ADD CONSTRAINT openclaw_reputation_wallet_id_key UNIQUE (wallet_id);


--
-- Name: openclaw_task_history openclaw_task_history_pkey; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.openclaw_task_history
    ADD CONSTRAINT openclaw_task_history_pkey PRIMARY KEY (id);


--
-- Name: openclaw_tasks openclaw_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.openclaw_tasks
    ADD CONSTRAINT openclaw_tasks_pkey PRIMARY KEY (id);


--
-- Name: personas_config personas_config_persona_type_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.personas_config
    ADD CONSTRAINT personas_config_persona_type_key UNIQUE (persona_type);


--
-- Name: personas_config personas_config_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.personas_config
    ADD CONSTRAINT personas_config_pkey PRIMARY KEY (id);


--
-- Name: poap_tokens poap_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.poap_tokens
    ADD CONSTRAINT poap_tokens_pkey PRIMARY KEY (id);


--
-- Name: poap_tokens poap_tokens_wallet_id_event_id_key; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.poap_tokens
    ADD CONSTRAINT poap_tokens_wallet_id_event_id_key UNIQUE (wallet_id, event_id);


--
-- Name: points_programs points_programs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.points_programs
    ADD CONSTRAINT points_programs_pkey PRIMARY KEY (id);


--
-- Name: points_programs points_programs_protocol_id_program_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.points_programs
    ADD CONSTRAINT points_programs_protocol_id_program_name_key UNIQUE (protocol_id, program_name);


--
-- Name: protocol_actions protocol_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_actions
    ADD CONSTRAINT protocol_actions_pkey PRIMARY KEY (id);


--
-- Name: protocol_actions protocol_actions_protocol_id_action_name_chain_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_actions
    ADD CONSTRAINT protocol_actions_protocol_id_action_name_chain_key UNIQUE (protocol_id, action_name, chain);


--
-- Name: protocol_contracts protocol_contracts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_contracts
    ADD CONSTRAINT protocol_contracts_pkey PRIMARY KEY (id);


--
-- Name: protocol_contracts protocol_contracts_protocol_id_chain_contract_type_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_contracts
    ADD CONSTRAINT protocol_contracts_protocol_id_chain_contract_type_key UNIQUE (protocol_id, chain, contract_type);


--
-- Name: protocol_research_pending protocol_research_pending_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_research_pending
    ADD CONSTRAINT protocol_research_pending_pkey PRIMARY KEY (id);


--
-- Name: protocol_research_reports protocol_research_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_research_reports
    ADD CONSTRAINT protocol_research_reports_pkey PRIMARY KEY (id);


--
-- Name: protocols protocols_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocols
    ADD CONSTRAINT protocols_name_key UNIQUE (name);


--
-- Name: protocols protocols_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocols
    ADD CONSTRAINT protocols_pkey PRIMARY KEY (id);


--
-- Name: proxy_pool proxy_pool_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.proxy_pool
    ADD CONSTRAINT proxy_pool_pkey PRIMARY KEY (id);


--
-- Name: research_logs research_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.research_logs
    ADD CONSTRAINT research_logs_pkey PRIMARY KEY (id);


--
-- Name: safety_gates safety_gates_gate_name_key; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.safety_gates
    ADD CONSTRAINT safety_gates_gate_name_key UNIQUE (gate_name);


--
-- Name: safety_gates safety_gates_pkey; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.safety_gates
    ADD CONSTRAINT safety_gates_pkey PRIMARY KEY (id);


--
-- Name: scheduled_transactions scheduled_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scheduled_transactions
    ADD CONSTRAINT scheduled_transactions_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: snapshot_events snapshot_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.snapshot_events
    ADD CONSTRAINT snapshot_events_pkey PRIMARY KEY (id);


--
-- Name: snapshot_votes snapshot_votes_pkey; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.snapshot_votes
    ADD CONSTRAINT snapshot_votes_pkey PRIMARY KEY (id);


--
-- Name: snapshot_votes snapshot_votes_wallet_id_proposal_id_key; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.snapshot_votes
    ADD CONSTRAINT snapshot_votes_wallet_id_proposal_id_key UNIQUE (wallet_id, proposal_id);


--
-- Name: system_config system_config_pkey; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.system_config
    ADD CONSTRAINT system_config_pkey PRIMARY KEY (key);


--
-- Name: system_events system_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.system_events
    ADD CONSTRAINT system_events_pkey PRIMARY KEY (id);


--
-- Name: system_state system_state_pkey; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.system_state
    ADD CONSTRAINT system_state_pkey PRIMARY KEY (key);


--
-- Name: token_check_cache token_check_cache_pkey; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.token_check_cache
    ADD CONSTRAINT token_check_cache_pkey PRIMARY KEY (protocol_name);


--
-- Name: protocol_research_pending unique_pending_protocol; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_research_pending
    ADD CONSTRAINT unique_pending_protocol UNIQUE (name);


--
-- Name: funding_chains unique_subaccount_per_chain; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.funding_chains
    ADD CONSTRAINT unique_subaccount_per_chain UNIQUE (cex_subaccount_id);


--
-- Name: CONSTRAINT unique_subaccount_per_chain ON funding_chains; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON CONSTRAINT unique_subaccount_per_chain ON public.funding_chains IS 'Each CEX subaccount must fund exactly one chain (1:1 mapping for anti-Sybil isolation)';


--
-- Name: wallet_tokens unique_wallet_token; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_tokens
    ADD CONSTRAINT unique_wallet_token UNIQUE (wallet_id, chain, token_contract_address);


--
-- Name: wallet_personas wallet_personas_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_personas
    ADD CONSTRAINT wallet_personas_pkey PRIMARY KEY (id);


--
-- Name: wallet_personas wallet_personas_wallet_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_personas
    ADD CONSTRAINT wallet_personas_wallet_id_key UNIQUE (wallet_id);


--
-- Name: wallet_points_balances wallet_points_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_points_balances
    ADD CONSTRAINT wallet_points_balances_pkey PRIMARY KEY (id);


--
-- Name: wallet_points_balances wallet_points_balances_wallet_id_points_program_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_points_balances
    ADD CONSTRAINT wallet_points_balances_wallet_id_points_program_id_key UNIQUE (wallet_id, points_program_id);


--
-- Name: wallet_protocol_assignments wallet_protocol_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_protocol_assignments
    ADD CONSTRAINT wallet_protocol_assignments_pkey PRIMARY KEY (id);


--
-- Name: wallet_protocol_assignments wallet_protocol_assignments_wallet_id_protocol_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_protocol_assignments
    ADD CONSTRAINT wallet_protocol_assignments_wallet_id_protocol_id_key UNIQUE (wallet_id, protocol_id);


--
-- Name: wallet_tokens wallet_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_tokens
    ADD CONSTRAINT wallet_tokens_pkey PRIMARY KEY (id);


--
-- Name: wallet_transactions wallet_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_pkey PRIMARY KEY (id);


--
-- Name: wallet_withdrawal_address_history wallet_withdrawal_address_history_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_withdrawal_address_history
    ADD CONSTRAINT wallet_withdrawal_address_history_pkey PRIMARY KEY (id);


--
-- Name: wallets wallets_address_key; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_address_key UNIQUE (address);


--
-- Name: wallets wallets_pkey; Type: CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_pkey PRIMARY KEY (id);


--
-- Name: weekly_plans weekly_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.weekly_plans
    ADD CONSTRAINT weekly_plans_pkey PRIMARY KEY (id);


--
-- Name: weekly_plans weekly_plans_wallet_id_week_start_date_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.weekly_plans
    ADD CONSTRAINT weekly_plans_wallet_id_week_start_date_key UNIQUE (wallet_id, week_start_date);


--
-- Name: withdrawal_plans withdrawal_plans_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.withdrawal_plans
    ADD CONSTRAINT withdrawal_plans_pkey PRIMARY KEY (id);


--
-- Name: withdrawal_steps withdrawal_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.withdrawal_steps
    ADD CONSTRAINT withdrawal_steps_pkey PRIMARY KEY (id);


--
-- Name: withdrawal_steps withdrawal_steps_withdrawal_plan_id_step_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.withdrawal_steps
    ADD CONSTRAINT withdrawal_steps_withdrawal_plan_id_step_number_key UNIQUE (withdrawal_plan_id, step_number);


--
-- Name: worker_nodes worker_nodes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.worker_nodes
    ADD CONSTRAINT worker_nodes_pkey PRIMARY KEY (id);


--
-- Name: worker_nodes worker_nodes_worker_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.worker_nodes
    ADD CONSTRAINT worker_nodes_worker_id_key UNIQUE (worker_id);


--
-- Name: idx_airdrop_scan_logs_new_tokens; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_airdrop_scan_logs_new_tokens ON public.airdrop_scan_logs USING btree (new_tokens_detected DESC) WHERE (new_tokens_detected > 0);


--
-- Name: idx_airdrop_scan_logs_start; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_airdrop_scan_logs_start ON public.airdrop_scan_logs USING btree (scan_start_at DESC);


--
-- Name: idx_airdrop_scan_logs_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_airdrop_scan_logs_status ON public.airdrop_scan_logs USING btree (status);


--
-- Name: idx_airdrops_confirmed; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_airdrops_confirmed ON public.airdrops USING btree (is_confirmed);


--
-- Name: idx_airdrops_protocol; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_airdrops_protocol ON public.airdrops USING btree (protocol_id);


--
-- Name: idx_bridge_history_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_bridge_history_created ON public.bridge_history USING btree (created_at DESC);


--
-- Name: idx_bridge_history_provider; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_bridge_history_provider ON public.bridge_history USING btree (provider);


--
-- Name: idx_bridge_history_safety; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_bridge_history_safety ON public.bridge_history USING btree (safety_score);


--
-- Name: idx_bridge_history_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_bridge_history_status ON public.bridge_history USING btree (status);


--
-- Name: idx_bridge_history_to_network; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_bridge_history_to_network ON public.bridge_history USING btree (to_network);


--
-- Name: idx_bridge_history_wallet; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_bridge_history_wallet ON public.bridge_history USING btree (wallet_id);


--
-- Name: idx_cex_cache_cex; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cex_cache_cex ON public.cex_networks_cache USING btree (cex_name);


--
-- Name: idx_cex_cache_expires; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cex_cache_expires ON public.cex_networks_cache USING btree (expires_at);


--
-- Name: idx_cex_cache_stale; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cex_cache_stale ON public.cex_networks_cache USING btree (is_stale) WHERE (is_stale = true);


--
-- Name: idx_cex_subaccounts_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cex_subaccounts_active ON public.cex_subaccounts USING btree (is_active);


--
-- Name: idx_cex_subaccounts_exchange; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_cex_subaccounts_exchange ON public.cex_subaccounts USING btree (exchange);


--
-- Name: idx_chain_aliases_alias; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chain_aliases_alias ON public.chain_aliases USING btree (alias);


--
-- Name: idx_chain_aliases_chain_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chain_aliases_chain_id ON public.chain_aliases USING btree (chain_id);


--
-- Name: idx_chain_aliases_source; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chain_aliases_source ON public.chain_aliases USING btree (source);


--
-- Name: idx_chain_rpc_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chain_rpc_active ON public.chain_rpc_endpoints USING btree (is_active);


--
-- Name: idx_chain_rpc_chain; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chain_rpc_chain ON public.chain_rpc_endpoints USING btree (chain, priority);


--
-- Name: idx_chain_rpc_chain_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chain_rpc_chain_id ON public.chain_rpc_endpoints USING btree (chain_id) WHERE (chain_id IS NOT NULL);


--
-- Name: idx_chain_rpc_farm_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chain_rpc_farm_status ON public.chain_rpc_endpoints USING btree (farm_status) WHERE ((farm_status)::text = ANY ((ARRAY['ACTIVE'::character varying, 'TARGET'::character varying])::text[]));


--
-- Name: idx_chain_rpc_health_checked; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chain_rpc_health_checked ON public.chain_rpc_health_log USING btree (checked_at);


--
-- Name: idx_chain_rpc_health_endpoint; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_chain_rpc_health_endpoint ON public.chain_rpc_health_log USING btree (rpc_endpoint_id);


--
-- Name: idx_chain_tokens_chain_id; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_chain_tokens_chain_id ON public.chain_tokens USING btree (chain_id);


--
-- Name: idx_chain_tokens_native_wrapped; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_chain_tokens_native_wrapped ON public.chain_tokens USING btree (is_native_wrapped);


--
-- Name: idx_defillama_cache_expires; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_defillama_cache_expires ON public.defillama_bridges_cache USING btree (expires_at);


--
-- Name: idx_defillama_cache_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_defillama_cache_name ON public.defillama_bridges_cache USING btree (bridge_name);


--
-- Name: idx_defillama_cache_rank; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_defillama_cache_rank ON public.defillama_bridges_cache USING btree (rank);


--
-- Name: idx_defillama_cache_tvl; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_defillama_cache_tvl ON public.defillama_bridges_cache USING btree (tvl_usd DESC);


--
-- Name: idx_discovery_failures_created_at; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_discovery_failures_created_at ON public.discovery_failures USING btree (created_at DESC);


--
-- Name: idx_discovery_failures_network_name; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_discovery_failures_network_name ON public.discovery_failures USING btree (network_name);


--
-- Name: idx_discovery_failures_resolved; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_discovery_failures_resolved ON public.discovery_failures USING btree (resolved) WHERE (resolved = false);


--
-- Name: idx_ens_names_registered; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_ens_names_registered ON public.ens_names USING btree (registered_at);


--
-- Name: idx_ens_names_wallet; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_ens_names_wallet ON public.ens_names USING btree (wallet_id);


--
-- Name: idx_funding_chains_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_funding_chains_status ON public.funding_chains USING btree (status);


--
-- Name: idx_funding_chains_subaccount; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_funding_chains_subaccount ON public.funding_chains USING btree (cex_subaccount_id) WHERE (cex_subaccount_id IS NOT NULL);


--
-- Name: idx_funding_withdrawals_cex_scheduled; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_funding_withdrawals_cex_scheduled ON public.funding_withdrawals USING btree (cex_withdrawal_scheduled_at) WHERE (status = ANY (ARRAY['planned'::public.funding_withdrawal_status, 'processing'::public.funding_withdrawal_status]));


--
-- Name: idx_funding_withdrawals_chain; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_funding_withdrawals_chain ON public.funding_withdrawals USING btree (funding_chain_id);


--
-- Name: idx_funding_withdrawals_completed; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_funding_withdrawals_completed ON public.funding_withdrawals USING btree (cex_withdrawal_completed_at) WHERE ((direct_cex_withdrawal = true) AND (status = 'completed'::public.funding_withdrawal_status));


--
-- Name: idx_funding_withdrawals_interleave; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_funding_withdrawals_interleave ON public.funding_withdrawals USING btree (interleave_round, interleave_position) WHERE (direct_cex_withdrawal = true);


--
-- Name: idx_funding_withdrawals_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_funding_withdrawals_status ON public.funding_withdrawals USING btree (status);


--
-- Name: idx_funding_withdrawals_wallet; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_funding_withdrawals_wallet ON public.funding_withdrawals USING btree (wallet_id);


--
-- Name: idx_gas_history_chain_time; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_gas_history_chain_time ON public.gas_history USING btree (chain_id, recorded_at DESC);


--
-- Name: idx_gas_history_retention; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_gas_history_retention ON public.gas_history USING btree (recorded_at);


--
-- Name: idx_gas_snapshots_chain; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_gas_snapshots_chain ON public.gas_snapshots USING btree (chain);


--
-- Name: idx_gas_snapshots_recorded; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_gas_snapshots_recorded ON public.gas_snapshots USING btree (recorded_at);


--
-- Name: idx_gitcoin_stamps_earned; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_gitcoin_stamps_earned ON public.gitcoin_stamps USING btree (earned_at);


--
-- Name: idx_gitcoin_stamps_wallet; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_gitcoin_stamps_wallet ON public.gitcoin_stamps USING btree (wallet_id);


--
-- Name: idx_lens_profiles_activity; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_lens_profiles_activity ON public.lens_profiles USING btree (last_activity_at);


--
-- Name: idx_lens_profiles_wallet; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_lens_profiles_wallet ON public.lens_profiles USING btree (wallet_id);


--
-- Name: idx_news_items_published; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_news_items_published ON public.news_items USING btree (published_at DESC);


--
-- Name: idx_news_items_relevance; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_news_items_relevance ON public.news_items USING btree (relevance_score DESC);


--
-- Name: idx_openclaw_reputation_passport; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_openclaw_reputation_passport ON public.openclaw_reputation USING btree (gitcoin_passport_score);


--
-- Name: idx_openclaw_task_history_completed; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_openclaw_task_history_completed ON public.openclaw_task_history USING btree (completed_at);


--
-- Name: idx_openclaw_task_history_task; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_openclaw_task_history_task ON public.openclaw_task_history USING btree (task_id);


--
-- Name: idx_openclaw_tasks_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_openclaw_tasks_created ON public.openclaw_tasks USING btree (created_at);


--
-- Name: idx_openclaw_tasks_scheduled; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_openclaw_tasks_scheduled ON public.openclaw_tasks USING btree (scheduled_at);


--
-- Name: idx_openclaw_tasks_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_openclaw_tasks_status ON public.openclaw_tasks USING btree (status);


--
-- Name: idx_openclaw_tasks_wallet; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_openclaw_tasks_wallet ON public.openclaw_tasks USING btree (wallet_id);


--
-- Name: idx_openclaw_tasks_worker; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_openclaw_tasks_worker ON public.openclaw_tasks USING btree (assigned_worker_id);


--
-- Name: idx_poap_tokens_claimed; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_poap_tokens_claimed ON public.poap_tokens USING btree (claimed_at);


--
-- Name: idx_poap_tokens_wallet; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_poap_tokens_wallet ON public.poap_tokens USING btree (wallet_id);


--
-- Name: idx_points_programs_protocol; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_points_programs_protocol ON public.points_programs USING btree (protocol_id);


--
-- Name: idx_protocol_actions_enabled; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_protocol_actions_enabled ON public.protocol_actions USING btree (is_enabled);


--
-- Name: idx_protocol_actions_layer; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_protocol_actions_layer ON public.protocol_actions USING btree (layer);


--
-- Name: idx_protocol_actions_protocol; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_protocol_actions_protocol ON public.protocol_actions USING btree (protocol_id);


--
-- Name: idx_protocol_bridge_available; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_protocol_bridge_available ON public.protocol_research_pending USING btree (bridge_available);


--
-- Name: idx_protocol_bridge_required; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_protocol_bridge_required ON public.protocol_research_pending USING btree (bridge_required) WHERE (bridge_required = true);


--
-- Name: idx_protocol_bridge_safety; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_protocol_bridge_safety ON public.protocol_research_pending USING btree (bridge_safety_score);


--
-- Name: idx_protocol_contracts_chain; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_protocol_contracts_chain ON public.protocol_contracts USING btree (chain);


--
-- Name: idx_protocol_contracts_protocol; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_protocol_contracts_protocol ON public.protocol_contracts USING btree (protocol_id);


--
-- Name: idx_protocol_research_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_protocol_research_date ON public.protocol_research_reports USING btree (run_date);


--
-- Name: idx_protocols_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_protocols_active ON public.protocols USING btree (is_active);


--
-- Name: idx_protocols_points; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_protocols_points ON public.protocols USING btree (has_points_program) WHERE (has_points_program = true);


--
-- Name: idx_protocols_priority; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_protocols_priority ON public.protocols USING btree (priority_score DESC);


--
-- Name: idx_proxy_pool_country_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_proxy_pool_country_active ON public.proxy_pool USING btree (country_code, is_active);


--
-- Name: idx_proxy_pool_provider; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_proxy_pool_provider ON public.proxy_pool USING btree (provider);


--
-- Name: idx_proxy_pool_timezone; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_proxy_pool_timezone ON public.proxy_pool USING btree (timezone);


--
-- Name: idx_proxy_pool_validation; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_proxy_pool_validation ON public.proxy_pool USING btree (validation_status, is_active);


--
-- Name: idx_research_logs_cost; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_research_logs_cost ON public.research_logs USING btree (estimated_cost_usd DESC);


--
-- Name: idx_research_logs_cycle; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_research_logs_cycle ON public.research_logs USING btree (cycle_start_at DESC);


--
-- Name: idx_research_logs_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_research_logs_status ON public.research_logs USING btree (status);


--
-- Name: idx_research_pending_bridge_recheck; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_research_pending_bridge_recheck ON public.protocol_research_pending USING btree (bridge_recheck_after) WHERE ((bridge_available = false) AND (status = 'pending_approval'::public.research_status));


--
-- Name: idx_research_pending_bridge_required; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_research_pending_bridge_required ON public.protocol_research_pending USING btree (bridge_required, bridge_available) WHERE (bridge_required = true);


--
-- Name: idx_research_pending_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_research_pending_created ON public.protocol_research_pending USING btree (created_at DESC);


--
-- Name: idx_research_pending_high_priority; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_research_pending_high_priority ON public.protocol_research_pending USING btree (airdrop_score DESC, status) WHERE ((airdrop_score >= 80) AND (status = 'pending_approval'::public.research_status));


--
-- Name: idx_research_pending_score; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_research_pending_score ON public.protocol_research_pending USING btree (airdrop_score DESC);


--
-- Name: idx_research_pending_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_research_pending_status ON public.protocol_research_pending USING btree (status);


--
-- Name: idx_research_pending_unreachable; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_research_pending_unreachable ON public.protocol_research_pending USING btree (bridge_available, bridge_recheck_count) WHERE (bridge_available = false);


--
-- Name: idx_scheduled_tx_bridge; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scheduled_tx_bridge ON public.scheduled_transactions USING btree (bridge_required, bridge_status) WHERE (bridge_required = true);


--
-- Name: idx_scheduled_tx_scheduled; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scheduled_tx_scheduled ON public.scheduled_transactions USING btree (scheduled_at);


--
-- Name: idx_scheduled_tx_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scheduled_tx_status ON public.scheduled_transactions USING btree (status);


--
-- Name: idx_scheduled_tx_wallet; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_scheduled_tx_wallet ON public.scheduled_transactions USING btree (wallet_id);


--
-- Name: idx_schema_migrations_applied_at; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_schema_migrations_applied_at ON public.schema_migrations USING btree (applied_at DESC);


--
-- Name: idx_snapshot_events_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_snapshot_events_date ON public.snapshot_events USING btree (snapshot_date);


--
-- Name: idx_snapshot_events_protocol; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_snapshot_events_protocol ON public.snapshot_events USING btree (protocol_id);


--
-- Name: idx_snapshot_votes_space; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_snapshot_votes_space ON public.snapshot_votes USING btree (space);


--
-- Name: idx_snapshot_votes_voted; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_snapshot_votes_voted ON public.snapshot_votes USING btree (voted_at);


--
-- Name: idx_snapshot_votes_wallet; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_snapshot_votes_wallet ON public.snapshot_votes USING btree (wallet_id);


--
-- Name: idx_system_config_category; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_system_config_category ON public.system_config USING btree (category);


--
-- Name: idx_system_config_updated_at; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_system_config_updated_at ON public.system_config USING btree (updated_at DESC);


--
-- Name: idx_system_events_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_system_events_created ON public.system_events USING btree (created_at);


--
-- Name: idx_system_events_severity; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_system_events_severity ON public.system_events USING btree (severity);


--
-- Name: idx_system_events_telegram; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_system_events_telegram ON public.system_events USING btree (telegram_sent) WHERE (telegram_sent = false);


--
-- Name: idx_token_cache_checked_at; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_token_cache_checked_at ON public.token_check_cache USING btree (checked_at);


--
-- Name: idx_wallet_personas_type; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wallet_personas_type ON public.wallet_personas USING btree (persona_type);


--
-- Name: idx_wallet_points_program; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wallet_points_program ON public.wallet_points_balances USING btree (points_program_id);


--
-- Name: idx_wallet_points_wallet; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wallet_points_wallet ON public.wallet_points_balances USING btree (wallet_id);


--
-- Name: idx_wallet_protocol_protocol; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wallet_protocol_protocol ON public.wallet_protocol_assignments USING btree (protocol_id);


--
-- Name: idx_wallet_protocol_wallet; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wallet_protocol_wallet ON public.wallet_protocol_assignments USING btree (wallet_id);


--
-- Name: idx_wallet_tokens_chain; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wallet_tokens_chain ON public.wallet_tokens USING btree (chain);


--
-- Name: idx_wallet_tokens_first_detected; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wallet_tokens_first_detected ON public.wallet_tokens USING btree (first_detected_at DESC);


--
-- Name: idx_wallet_tokens_recent_airdrops; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wallet_tokens_recent_airdrops ON public.wallet_tokens USING btree (first_detected_at DESC, balance_human DESC) WHERE (balance_human > (0)::numeric);


--
-- Name: idx_wallet_tokens_updated; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wallet_tokens_updated ON public.wallet_tokens USING btree (last_updated DESC);


--
-- Name: idx_wallet_tokens_wallet; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_wallet_tokens_wallet ON public.wallet_tokens USING btree (wallet_id);


--
-- Name: idx_wallet_transactions_tx_hash; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_wallet_transactions_tx_hash ON public.wallet_transactions USING btree (tx_hash);


--
-- Name: idx_wallet_transactions_wallet_id; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_wallet_transactions_wallet_id ON public.wallet_transactions USING btree (wallet_id);


--
-- Name: idx_wallets_authorized_withdrawal; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_wallets_authorized_withdrawal ON public.wallets USING btree (authorized_withdrawal_address);


--
-- Name: idx_wallets_openclaw; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_wallets_openclaw ON public.wallets USING btree (openclaw_enabled) WHERE (openclaw_enabled = true);


--
-- Name: idx_wallets_status; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_wallets_status ON public.wallets USING btree (status);


--
-- Name: idx_wallets_tier; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_wallets_tier ON public.wallets USING btree (tier);


--
-- Name: idx_wallets_warmup_status; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_wallets_warmup_status ON public.wallets USING btree (warmup_status);


--
-- Name: idx_wallets_withdrawal_network; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_wallets_withdrawal_network ON public.wallets USING btree (withdrawal_network);


--
-- Name: idx_wallets_worker; Type: INDEX; Schema: public; Owner: farming_user
--

CREATE INDEX idx_wallets_worker ON public.wallets USING btree (worker_node_id);


--
-- Name: idx_weekly_plans_wallet; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_weekly_plans_wallet ON public.weekly_plans USING btree (wallet_id);


--
-- Name: idx_weekly_plans_week; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_weekly_plans_week ON public.weekly_plans USING btree (week_start_date);


--
-- Name: idx_withdrawal_address_history_approval; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_withdrawal_address_history_approval ON public.wallet_withdrawal_address_history USING btree (approval_status);


--
-- Name: idx_withdrawal_address_history_created; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_withdrawal_address_history_created ON public.wallet_withdrawal_address_history USING btree (created_at DESC);


--
-- Name: idx_withdrawal_address_history_wallet; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_withdrawal_address_history_wallet ON public.wallet_withdrawal_address_history USING btree (wallet_id);


--
-- Name: idx_withdrawal_plans_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_withdrawal_plans_status ON public.withdrawal_plans USING btree (status);


--
-- Name: idx_withdrawal_plans_wallet; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_withdrawal_plans_wallet ON public.withdrawal_plans USING btree (wallet_id);


--
-- Name: idx_withdrawal_steps_plan; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_withdrawal_steps_plan ON public.withdrawal_steps USING btree (withdrawal_plan_id);


--
-- Name: idx_withdrawal_steps_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_withdrawal_steps_status ON public.withdrawal_steps USING btree (status);


--
-- Name: cex_networks_cache trg_cex_cache_expires; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_cex_cache_expires BEFORE INSERT OR UPDATE ON public.cex_networks_cache FOR EACH ROW EXECUTE FUNCTION public.update_cex_cache_expires();


--
-- Name: defillama_bridges_cache trg_defillama_cache_expires; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_defillama_cache_expires BEFORE INSERT OR UPDATE ON public.defillama_bridges_cache FOR EACH ROW EXECUTE FUNCTION public.update_defillama_cache_expires();


--
-- Name: wallets trigger_log_authorized_withdrawal_address; Type: TRIGGER; Schema: public; Owner: farming_user
--

CREATE TRIGGER trigger_log_authorized_withdrawal_address AFTER INSERT OR UPDATE OF authorized_withdrawal_address ON public.wallets FOR EACH ROW EXECUTE FUNCTION public.log_authorized_withdrawal_address_change();


--
-- Name: openclaw_profiles trigger_openclaw_profiles_updated_at; Type: TRIGGER; Schema: public; Owner: farming_user
--

CREATE TRIGGER trigger_openclaw_profiles_updated_at BEFORE UPDATE ON public.openclaw_profiles FOR EACH ROW EXECUTE FUNCTION public.update_openclaw_profiles_updated_at();


--
-- Name: openclaw_tasks trigger_openclaw_tasks_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_openclaw_tasks_updated_at BEFORE UPDATE ON public.openclaw_tasks FOR EACH ROW EXECUTE FUNCTION public.update_openclaw_tasks_updated_at();


--
-- Name: research_logs trigger_update_research_logs_timestamp; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_research_logs_timestamp BEFORE UPDATE ON public.research_logs FOR EACH ROW EXECUTE FUNCTION public.update_research_timestamp();


--
-- Name: protocol_research_pending trigger_update_research_pending_timestamp; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_research_pending_timestamp BEFORE UPDATE ON public.protocol_research_pending FOR EACH ROW EXECUTE FUNCTION public.update_research_timestamp();


--
-- Name: wallet_tokens trigger_update_wallet_token_timestamp; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_wallet_token_timestamp BEFORE UPDATE ON public.wallet_tokens FOR EACH ROW EXECUTE FUNCTION public.update_wallet_token_timestamp();


--
-- Name: cex_subaccounts update_cex_subaccounts_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_cex_subaccounts_updated_at BEFORE UPDATE ON public.cex_subaccounts FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: protocol_actions update_protocol_actions_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_protocol_actions_updated_at BEFORE UPDATE ON public.protocol_actions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: protocols update_protocols_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_protocols_updated_at BEFORE UPDATE ON public.protocols FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: wallet_personas update_wallet_personas_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_wallet_personas_updated_at BEFORE UPDATE ON public.wallet_personas FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: wallets update_wallets_updated_at; Type: TRIGGER; Schema: public; Owner: farming_user
--

CREATE TRIGGER update_wallets_updated_at BEFORE UPDATE ON public.wallets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: withdrawal_plans update_withdrawal_plans_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_withdrawal_plans_updated_at BEFORE UPDATE ON public.withdrawal_plans FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: worker_nodes update_worker_nodes_updated_at; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER update_worker_nodes_updated_at BEFORE UPDATE ON public.worker_nodes FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: airdrops airdrops_protocol_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.airdrops
    ADD CONSTRAINT airdrops_protocol_id_fkey FOREIGN KEY (protocol_id) REFERENCES public.protocols(id);


--
-- Name: bridge_history bridge_history_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bridge_history
    ADD CONSTRAINT bridge_history_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: chain_rpc_health_log chain_rpc_health_log_rpc_endpoint_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.chain_rpc_health_log
    ADD CONSTRAINT chain_rpc_health_log_rpc_endpoint_id_fkey FOREIGN KEY (rpc_endpoint_id) REFERENCES public.chain_rpc_endpoints(id);


--
-- Name: ens_names ens_names_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.ens_names
    ADD CONSTRAINT ens_names_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: funding_withdrawals fk_funding_withdrawals_wallet; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.funding_withdrawals
    ADD CONSTRAINT fk_funding_withdrawals_wallet FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: funding_chains funding_chains_cex_subaccount_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.funding_chains
    ADD CONSTRAINT funding_chains_cex_subaccount_id_fkey FOREIGN KEY (cex_subaccount_id) REFERENCES public.cex_subaccounts(id);


--
-- Name: funding_withdrawals funding_withdrawals_cex_subaccount_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.funding_withdrawals
    ADD CONSTRAINT funding_withdrawals_cex_subaccount_id_fkey FOREIGN KEY (cex_subaccount_id) REFERENCES public.cex_subaccounts(id);


--
-- Name: funding_withdrawals funding_withdrawals_funding_chain_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.funding_withdrawals
    ADD CONSTRAINT funding_withdrawals_funding_chain_id_fkey FOREIGN KEY (funding_chain_id) REFERENCES public.funding_chains(id);


--
-- Name: gitcoin_stamps gitcoin_stamps_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.gitcoin_stamps
    ADD CONSTRAINT gitcoin_stamps_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: lens_profiles lens_profiles_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.lens_profiles
    ADD CONSTRAINT lens_profiles_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: openclaw_profiles openclaw_profiles_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.openclaw_profiles
    ADD CONSTRAINT openclaw_profiles_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: openclaw_reputation openclaw_reputation_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.openclaw_reputation
    ADD CONSTRAINT openclaw_reputation_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: openclaw_task_history openclaw_task_history_task_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.openclaw_task_history
    ADD CONSTRAINT openclaw_task_history_task_id_fkey FOREIGN KEY (task_id) REFERENCES public.openclaw_tasks(id);


--
-- Name: openclaw_tasks openclaw_tasks_assigned_worker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.openclaw_tasks
    ADD CONSTRAINT openclaw_tasks_assigned_worker_id_fkey FOREIGN KEY (assigned_worker_id) REFERENCES public.worker_nodes(worker_id);


--
-- Name: openclaw_tasks openclaw_tasks_protocol_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.openclaw_tasks
    ADD CONSTRAINT openclaw_tasks_protocol_id_fkey FOREIGN KEY (protocol_id) REFERENCES public.protocols(id);


--
-- Name: openclaw_tasks openclaw_tasks_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.openclaw_tasks
    ADD CONSTRAINT openclaw_tasks_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: poap_tokens poap_tokens_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.poap_tokens
    ADD CONSTRAINT poap_tokens_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: points_programs points_programs_protocol_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.points_programs
    ADD CONSTRAINT points_programs_protocol_id_fkey FOREIGN KEY (protocol_id) REFERENCES public.protocols(id);


--
-- Name: protocol_actions protocol_actions_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_actions
    ADD CONSTRAINT protocol_actions_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.protocol_contracts(id);


--
-- Name: protocol_actions protocol_actions_protocol_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_actions
    ADD CONSTRAINT protocol_actions_protocol_id_fkey FOREIGN KEY (protocol_id) REFERENCES public.protocols(id);


--
-- Name: protocol_contracts protocol_contracts_protocol_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.protocol_contracts
    ADD CONSTRAINT protocol_contracts_protocol_id_fkey FOREIGN KEY (protocol_id) REFERENCES public.protocols(id);


--
-- Name: scheduled_transactions scheduled_transactions_depends_on_tx_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scheduled_transactions
    ADD CONSTRAINT scheduled_transactions_depends_on_tx_id_fkey FOREIGN KEY (depends_on_tx_id) REFERENCES public.scheduled_transactions(id);


--
-- Name: scheduled_transactions scheduled_transactions_protocol_action_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scheduled_transactions
    ADD CONSTRAINT scheduled_transactions_protocol_action_id_fkey FOREIGN KEY (protocol_action_id) REFERENCES public.protocol_actions(id);


--
-- Name: scheduled_transactions scheduled_transactions_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.scheduled_transactions
    ADD CONSTRAINT scheduled_transactions_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: snapshot_events snapshot_events_protocol_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.snapshot_events
    ADD CONSTRAINT snapshot_events_protocol_id_fkey FOREIGN KEY (protocol_id) REFERENCES public.protocols(id);


--
-- Name: snapshot_votes snapshot_votes_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.snapshot_votes
    ADD CONSTRAINT snapshot_votes_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: wallet_personas wallet_personas_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_personas
    ADD CONSTRAINT wallet_personas_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: wallet_points_balances wallet_points_balances_points_program_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_points_balances
    ADD CONSTRAINT wallet_points_balances_points_program_id_fkey FOREIGN KEY (points_program_id) REFERENCES public.points_programs(id);


--
-- Name: wallet_points_balances wallet_points_balances_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_points_balances
    ADD CONSTRAINT wallet_points_balances_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: wallet_protocol_assignments wallet_protocol_assignments_protocol_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_protocol_assignments
    ADD CONSTRAINT wallet_protocol_assignments_protocol_id_fkey FOREIGN KEY (protocol_id) REFERENCES public.protocols(id);


--
-- Name: wallet_protocol_assignments wallet_protocol_assignments_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_protocol_assignments
    ADD CONSTRAINT wallet_protocol_assignments_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: wallet_tokens wallet_tokens_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_tokens
    ADD CONSTRAINT wallet_tokens_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id) ON DELETE CASCADE;


--
-- Name: wallet_transactions wallet_transactions_protocol_action_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_protocol_action_id_fkey FOREIGN KEY (protocol_action_id) REFERENCES public.protocol_actions(id) ON DELETE SET NULL;


--
-- Name: wallet_transactions wallet_transactions_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id) ON DELETE CASCADE;


--
-- Name: wallet_withdrawal_address_history wallet_withdrawal_address_history_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_withdrawal_address_history
    ADD CONSTRAINT wallet_withdrawal_address_history_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id) ON DELETE CASCADE;


--
-- Name: wallets wallets_funding_cex_subaccount_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_funding_cex_subaccount_id_fkey FOREIGN KEY (funding_cex_subaccount_id) REFERENCES public.cex_subaccounts(id);


--
-- Name: wallets wallets_funding_chain_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_funding_chain_id_fkey FOREIGN KEY (funding_chain_id) REFERENCES public.funding_chains(id);


--
-- Name: wallets wallets_proxy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_proxy_id_fkey FOREIGN KEY (proxy_id) REFERENCES public.proxy_pool(id);


--
-- Name: wallets wallets_worker_node_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: farming_user
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_worker_node_id_fkey FOREIGN KEY (worker_node_id) REFERENCES public.worker_nodes(id);


--
-- Name: weekly_plans weekly_plans_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.weekly_plans
    ADD CONSTRAINT weekly_plans_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: withdrawal_plans withdrawal_plans_wallet_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.withdrawal_plans
    ADD CONSTRAINT withdrawal_plans_wallet_id_fkey FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: withdrawal_steps withdrawal_steps_withdrawal_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.withdrawal_steps
    ADD CONSTRAINT withdrawal_steps_withdrawal_plan_id_fkey FOREIGN KEY (withdrawal_plan_id) REFERENCES public.withdrawal_plans(id);


--
-- Name: TABLE airdrop_scan_logs; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.airdrop_scan_logs TO farming_user;


--
-- Name: SEQUENCE airdrop_scan_logs_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.airdrop_scan_logs_id_seq TO farming_user;


--
-- Name: TABLE airdrops; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.airdrops TO farming_user;


--
-- Name: SEQUENCE airdrops_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.airdrops_id_seq TO farming_user;


--
-- Name: TABLE bridge_history; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.bridge_history TO farming_user;


--
-- Name: TABLE cex_networks_cache; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.cex_networks_cache TO farming_user;


--
-- Name: TABLE cex_subaccounts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.cex_subaccounts TO farming_user;


--
-- Name: SEQUENCE cex_subaccounts_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.cex_subaccounts_id_seq TO farming_user;


--
-- Name: TABLE chain_aliases; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.chain_aliases TO farming_user;


--
-- Name: SEQUENCE chain_aliases_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT USAGE ON SEQUENCE public.chain_aliases_id_seq TO farming_user;


--
-- Name: TABLE chain_rpc_endpoints; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.chain_rpc_endpoints TO farming_user;


--
-- Name: SEQUENCE chain_rpc_endpoints_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.chain_rpc_endpoints_id_seq TO farming_user;


--
-- Name: TABLE chain_rpc_health_log; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.chain_rpc_health_log TO farming_user;


--
-- Name: SEQUENCE chain_rpc_health_log_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.chain_rpc_health_log_id_seq TO farming_user;


--
-- Name: TABLE defillama_bridges_cache; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.defillama_bridges_cache TO farming_user;


--
-- Name: TABLE discovery_failures; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.discovery_failures TO farming_user;


--
-- Name: SEQUENCE discovery_failures_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT USAGE ON SEQUENCE public.discovery_failures_id_seq TO farming_user;


--
-- Name: TABLE funding_chains; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.funding_chains TO farming_user;


--
-- Name: SEQUENCE funding_chains_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.funding_chains_id_seq TO farming_user;


--
-- Name: TABLE funding_withdrawals; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.funding_withdrawals TO farming_user;


--
-- Name: SEQUENCE funding_withdrawals_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.funding_withdrawals_id_seq TO farming_user;


--
-- Name: TABLE gas_history; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.gas_history TO farming_user;


--
-- Name: TABLE gas_snapshots; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.gas_snapshots TO farming_user;


--
-- Name: SEQUENCE gas_snapshots_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.gas_snapshots_id_seq TO farming_user;


--
-- Name: TABLE news_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.news_items TO farming_user;


--
-- Name: SEQUENCE news_items_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.news_items_id_seq TO farming_user;


--
-- Name: TABLE openclaw_reputation; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.openclaw_reputation TO farming_user;


--
-- Name: SEQUENCE openclaw_reputation_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.openclaw_reputation_id_seq TO farming_user;


--
-- Name: TABLE openclaw_tasks; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.openclaw_tasks TO farming_user;


--
-- Name: SEQUENCE openclaw_tasks_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.openclaw_tasks_id_seq TO farming_user;


--
-- Name: TABLE personas_config; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.personas_config TO farming_user;


--
-- Name: SEQUENCE personas_config_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.personas_config_id_seq TO farming_user;


--
-- Name: TABLE points_programs; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.points_programs TO farming_user;


--
-- Name: SEQUENCE points_programs_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.points_programs_id_seq TO farming_user;


--
-- Name: TABLE protocol_actions; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.protocol_actions TO farming_user;


--
-- Name: SEQUENCE protocol_actions_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.protocol_actions_id_seq TO farming_user;


--
-- Name: TABLE protocol_contracts; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.protocol_contracts TO farming_user;


--
-- Name: SEQUENCE protocol_contracts_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.protocol_contracts_id_seq TO farming_user;


--
-- Name: TABLE protocol_research_pending; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.protocol_research_pending TO farming_user;


--
-- Name: SEQUENCE protocol_research_pending_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.protocol_research_pending_id_seq TO farming_user;


--
-- Name: TABLE protocol_research_reports; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.protocol_research_reports TO farming_user;


--
-- Name: SEQUENCE protocol_research_reports_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.protocol_research_reports_id_seq TO farming_user;


--
-- Name: TABLE protocols; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.protocols TO farming_user;


--
-- Name: SEQUENCE protocols_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.protocols_id_seq TO farming_user;


--
-- Name: TABLE proxy_pool; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.proxy_pool TO farming_user;


--
-- Name: SEQUENCE proxy_pool_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.proxy_pool_id_seq TO farming_user;


--
-- Name: TABLE research_logs; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.research_logs TO farming_user;


--
-- Name: SEQUENCE research_logs_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.research_logs_id_seq TO farming_user;


--
-- Name: TABLE scheduled_transactions; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.scheduled_transactions TO farming_user;


--
-- Name: SEQUENCE scheduled_transactions_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.scheduled_transactions_id_seq TO farming_user;


--
-- Name: TABLE snapshot_events; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.snapshot_events TO farming_user;


--
-- Name: SEQUENCE snapshot_events_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.snapshot_events_id_seq TO farming_user;


--
-- Name: TABLE system_events; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.system_events TO farming_user;


--
-- Name: SEQUENCE system_events_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.system_events_id_seq TO farming_user;


--
-- Name: TABLE v_bridge_stats_by_network; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_bridge_stats_by_network TO farming_user;


--
-- Name: TABLE v_direct_funding_schedule; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_direct_funding_schedule TO farming_user;


--
-- Name: TABLE v_funding_interleave_quality; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_funding_interleave_quality TO farming_user;


--
-- Name: TABLE v_funding_temporal_distribution; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_funding_temporal_distribution TO farming_user;


--
-- Name: TABLE v_protocols_requiring_bridge; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_protocols_requiring_bridge TO farming_user;


--
-- Name: TABLE v_recent_bridges; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_recent_bridges TO farming_user;


--
-- Name: TABLE v_subaccount_usage; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.v_subaccount_usage TO farming_user;


--
-- Name: TABLE wallet_personas; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wallet_personas TO farming_user;


--
-- Name: SEQUENCE wallet_personas_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.wallet_personas_id_seq TO farming_user;


--
-- Name: TABLE wallet_points_balances; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wallet_points_balances TO farming_user;


--
-- Name: SEQUENCE wallet_points_balances_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.wallet_points_balances_id_seq TO farming_user;


--
-- Name: TABLE wallet_protocol_assignments; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wallet_protocol_assignments TO farming_user;


--
-- Name: SEQUENCE wallet_protocol_assignments_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.wallet_protocol_assignments_id_seq TO farming_user;


--
-- Name: TABLE wallet_tokens; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wallet_tokens TO farming_user;


--
-- Name: SEQUENCE wallet_tokens_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.wallet_tokens_id_seq TO farming_user;


--
-- Name: TABLE wallet_withdrawal_address_history; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wallet_withdrawal_address_history TO farming_user;


--
-- Name: SEQUENCE wallet_withdrawal_address_history_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.wallet_withdrawal_address_history_id_seq TO farming_user;


--
-- Name: TABLE wallet_withdrawal_security_status; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.wallet_withdrawal_security_status TO farming_user;


--
-- Name: TABLE weekly_plans; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.weekly_plans TO farming_user;


--
-- Name: SEQUENCE weekly_plans_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.weekly_plans_id_seq TO farming_user;


--
-- Name: TABLE withdrawal_plans; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.withdrawal_plans TO farming_user;


--
-- Name: SEQUENCE withdrawal_plans_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.withdrawal_plans_id_seq TO farming_user;


--
-- Name: TABLE withdrawal_steps; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.withdrawal_steps TO farming_user;


--
-- Name: SEQUENCE withdrawal_steps_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.withdrawal_steps_id_seq TO farming_user;


--
-- Name: TABLE worker_nodes; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.worker_nodes TO farming_user;


--
-- Name: SEQUENCE worker_nodes_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.worker_nodes_id_seq TO farming_user;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: postgres
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO farming_user;


--
-- PostgreSQL database dump complete
--

\unrestrict nVwWFesRjQw0oVncWRBfkCt74q18ujm7UL2stvqhkpEUDUluaN4H2BNfXyD00tL

