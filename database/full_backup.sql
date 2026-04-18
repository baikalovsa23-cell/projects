--
-- PostgreSQL database dump
--

\restrict kfu1WL4KhTMLIaLU3T5H02IDcHZdYWjs9DGRnBM93SLVq4QX9HirgiNBv5uBTts

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
-- Data for Name: airdrop_scan_logs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.airdrop_scan_logs (id, scan_start_at, scan_end_at, status, total_wallets_scanned, total_chains_scanned, total_api_calls, new_tokens_detected, alerts_sent, scan_duration_seconds, avg_api_response_time_ms, api_errors_encountered, rate_limit_hits, timeout_errors, error_details, chain_stats, created_at) FROM stdin;
1	2026-02-26 19:03:08.122591+03	2026-02-26 19:13:08.122591+03	completed	90	7	630	5	2	110.53	185.42	0	0	0	\N	{"ink": {"errors": 0, "rpc_calls": 90, "duration_ms": 4500}, "base": {"errors": 0, "api_calls": 90, "duration_ms": 18000}, "megaeth": {"errors": 0, "rpc_calls": 90, "duration_ms": 4500}, "polygon": {"errors": 0, "api_calls": 90, "duration_ms": 18000}, "arbitrum": {"errors": 0, "api_calls": 90, "duration_ms": 18000}, "bnbchain": {"errors": 0, "api_calls": 90, "duration_ms": 18000}, "optimism": {"errors": 0, "api_calls": 90, "duration_ms": 18000}}	2026-02-26 20:03:08.122591+03
2	2026-02-26 20:03:08.125264+03	2026-02-26 20:03:08.125264+03	completed	0	0	0	0	0	\N	\N	0	0	0	\N	\N	2026-02-26 20:03:08.125264+03
\.


--
-- Data for Name: airdrops; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.airdrops (id, protocol_id, token_symbol, token_contract_address, chain, announced_at, snapshot_date, claim_start_date, claim_end_date, total_allocation, vesting_schedule, is_confirmed, confidence_score, notes, created_at) FROM stdin;
\.


--
-- Data for Name: bridge_history; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.bridge_history (id, wallet_id, from_network, to_network, amount_eth, provider, cost_usd, tx_hash, defillama_tvl_usd, defillama_volume_30d_usd, defillama_rank, defillama_hacks, safety_score, cex_checked, cex_support_found, status, error_message, created_at, completed_at) FROM stdin;
\.


--
-- Data for Name: cex_networks_cache; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cex_networks_cache (id, cex_name, coin, supported_networks, fetched_at, expires_at, is_stale) FROM stdin;
\.


--
-- Data for Name: cex_subaccounts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cex_subaccounts (id, exchange, subaccount_name, api_key, api_secret, api_passphrase, is_active, withdrawal_network, balance_usdt, last_balance_check, created_at, updated_at) FROM stdin;
9	bybit	BybitScalpMaster	gAAAAABpnWIKZHpdZrbRwaa2-VSgfLEGkjz8XqldXrrkpLwfbhfoLN00ffGvPB0Kw4xH4zwC2N6DWPMJnK7kSUoy8jUHZOoUdbZbDGgyI8dPnejYBECPWhg=	gAAAAABpnWIKRsfLGYFhYa9gcRj0x-CY8WWrkz3_aKaRXZV3g705qj8Z9d31_bBairSP-Z0Vhdhv2WzGxDadgwxKxmMmuuqJ89c4_EQDFyzrODuDv0nCK5VcQ9fVIWH34jSDL1ieDuv3	\N	t	Base	19.00000000	\N	2026-02-24 11:31:11.976027+03	2026-03-12 13:09:20.132521+03
10	bybit	DeltaNeutralTrade	gAAAAABpnWIKMIrRyaPfaH8a_nLZpu73gSolTOY6S6SZP7Mi1NQ2z71h8qSMfWFXzuWX0AkpDQtc1Q3P4ZIL71RC7h_wgjy4NojSSuFep7IJYqlzf-QRYOc=	gAAAAABpnWIKhc48EhA1fERsbuoFqg1PiOc8yuoN_DYH9UHpIYMqxEXmHBAZBMhjpg1wKYz-iQQHonUAAqAwMNGD7yW3JgIcnPtxzUGx8Jmto4pqm81TczTPki6ANfgz4hDJCWltcwHf	\N	t	Arbitrum One	4.00000000	\N	2026-02-24 11:31:11.976027+03	2026-03-12 13:09:20.132521+03
11	bybit	GlobalAssetManage	gAAAAABpnWIKCnPIZ8zI4cjKaMl2dV-XKVhDuiaKmIKCZhssHnw90qZnZzjStHUt8_Lt98ePVeI85OSTBmuafVlewFukTnLO9w92uG7UqKEFZZ4iW9swTCM=	gAAAAABpnWIKkY35PSWkYRwxMZtakDhcZVuzuYCMrLAqMw6eo6AEstpuL6hmrl4QwJyXezsWJ2Sxdx858asByGNIdbqb6Av-l0QNZspDqfABRxWoZmXet45H4ls82D0mVYLSsYLEUM6I	\N	t	OP Mainnet	4.00000000	\N	2026-02-24 11:31:11.976027+03	2026-03-12 13:09:20.132521+03
12	bybit	RiskControlAccount	gAAAAABpnWIKAyEwwSTnfm7CLQ0ZSG3UtJOi2GPrjua7QY0b-aBcqV5Cad61rk5YRTmoC7CRyMI9LiH0DP5yFJIvSIBL0rNRlroDqd1b0d5rV-KQyStjqzc=	gAAAAABpnWIKeqOTBoabm_RrslZOCx1DCrT3zslqQX26n7WPNBGR1OC9YLwbx0FRSRZXulETyPHqQdKmcOY-IsVvkSnY5SDGmHz2VpSJ6arqvrtluVmwygkjt-bGAdawH5ccG0xOefvj	\N	t	zkSync Era	5.00000000	\N	2026-02-24 11:31:11.976027+03	2026-03-12 13:09:20.132521+03
5	binance	BinanceGridBotOne	gAAAAABpnWIKzS6QTmCkvETTQfKXeI8T6iB_rNTdUQ_VYsrefZEJonjasfXANjqUDlQBGXgKexwrll0gHRfB2MiET2BnjlhrpxJ8R6xNrwXJBodzOd6al4mseWvB4sR3EZKM5PDj3Ys0vi74sHdTZjgp5kfkWR9Yt9D7c6wExOBAULxGKm-Y_Hg=	gAAAAABpnWIKbaxMS3EA3w253x7IDxoOoSe-vC9KAfXl3gC4lEwVBqbL-I0fGWA97s-QYgQpH4NQ2xvJX_w3eazbjb5gYUtwVH8uW2SPwP8bLcrT46kalk0gYW54Kq0V8f8DpKbs-D5SWNCQY9yyDX-z-t4SQKV1USn-dV_yfxxRgG3YLLuFKpI=	\N	t	Arbitrum One	19.00000000	\N	2026-02-24 11:31:11.97491+03	2026-03-12 13:09:20.132521+03
6	binance	SpotPortfolioMain	gAAAAABpnWIKNwnf-1LfKzpzOhRu4O4LxxvVnf8YYcqsxBYompxHn8XXzu4dJyuK7jQfsV9AK9QYJL_5MMQtIG60w0TrxYmeAXr2DyF0cqnSzxx1jwQumNhFH-Qdh70VyCyMqTmTiEaE1XIvqvxlwk-LrRHwBcSWj5Cp_KsZG9CQb0WYOQE41T0=	gAAAAABpnWIKNJxPw7POiKShKhirbqA38QAtO3lsrAF2eJkSDFRbx0FnG6kZy7dH-Nc47lnGJZj9kCGiP-98rnBnqJbRS72uGd5ou8LLE6eExy3F3UdP5MPG6NYoyAwrZmbRDR8Zd3SIh01grdvn-72TlK7DYtAUASRoDeBUZLNg0gKBnCldl6Y=	\N	t	Base	3.50000000	\N	2026-02-24 11:31:11.97491+03	2026-03-12 13:09:20.132521+03
7	binance	ArbitrageLiquidity	gAAAAABpnWIK2yrPMSw2FWAZRs8st3-D43hyX-j-4y4gqoYo7i_16PIwVkDZ6ZrvALWWQZlEJNDVajQlOj2vXEvPhhWJmUEq7luZSqiQLs_jpMe559VEGm1YKBJX-JVC2VWJlmf8GUbgS0DcccCKNlpS_Mmq_QSqFrNqWbGxn3FrC8-Rctbdp6g=	gAAAAABpnWIKrqxO4lekwQL1cOqr2UQOq-JFcXIgf2Ivg-OE47ZebcEaN_iS_hG30B4KV84xHbzvtDhkMk077Tg8n-ykcKn9HBq_eqIEXw__PDdNR0U8uqIKoHkgOq4mWWW1biFIMQbpOXBiOK9WG24b5coFXX_tGcngzaaKa3gqnOhSgcrkCGo=	\N	t	OP Mainnet	3.00000000	\N	2026-02-24 11:31:11.97491+03	2026-03-12 13:09:20.132521+03
8	binance	VentureGrowthFund	gAAAAABpnWIK_YnZam4Ov6dEBJMmglKPeI6YIBs71Zrg_18xAtMV610n5zTg3FyEtyNA_cjFDepWYINfs35IPaK6fb_-_aiS_oXjt8a257IQNsdG6wmJ9tE3JVkP8aBeW3friiJ_5lr7BfsdayRYhFvA-mxWIgxfi49LKXKUQXSHn4fFhuhCAlI=	gAAAAABpnWIKLmAaD8oeTsjrj0ded3PBBU-LOrpg2e0gVIOv8MfndeU5gyPV_IsTjs-rQ_g5lmAhbrLO6qiynn3XHj-9M9AbGtSsd7B_iVob84cyU72WfwX82Wvfq_rOJCVD80sFaCaN1psTNGBNZJx29oQpFNtvQEorungdWIAFr_FT8B7_DFI=	\N	t	SCROLL	3.00000000	\N	2026-02-24 11:31:11.97491+03	2026-03-12 13:09:20.132521+03
1	okx	AlphaTradingStrategy	gAAAAABpnWIK_wptIjCbrnb4vk5WCWTgR83w32jrWn2vjJE-_TsjbTvW1RgkrYUUpmBAo_3XH95hzhsinkNNmNrTtlnrRjN5IkY_QJDykyptKT1drSurH07JSPnYJifsXb875-EHGKYD	gAAAAABpnWIKuusfcnGtCdbfDZ7aW3s2Y5PMIgnF0LRBaB0F5MtqgPFbda30lK66-qyZVCcLgbjY5v9LYtCbgFbzHgNptTPJPysC-lKesJWolunLJNjYr_n1ybcTYHoOibOf_yTaxa1n	gAAAAABpnWIK1fKH6HYoZz-tDs8t54PkMfiX-YltyKbvB5gxW5WXRx76SfuIx3aaceM1vKvhVec2OhY9WNLTeLTEi4GfoPRgWA==	t	Arbitrum One	19.00000000	\N	2026-02-24 11:31:11.966116+03	2026-03-12 13:09:20.132521+03
2	okx	LongTermStakingVault	gAAAAABpnWIKXSVwni-3SAqII3kNTDnGZDugPa7THWgn4mWHIkIEsuLyj5imwXCLzHnLJOESRSvgeDfz_pqzlR1CgN2mu6oc0YUDCipnswQOXM5rRteNe9URdrqqgb9ihMqNqca0E-M4	gAAAAABpnWIKF8YWpGI6bk5_avI5IaEXtvouh58ABLvKN32wySykcbXufGnmzx5MYSMdAT_pWgQLhELtffUnwY5u7AkgVHsfIm16Mjr1sqyeqexJtWhAnwPkpoPgTlrm-KRHp2VxBgtq	gAAAAABpnWIKTI7fcsYBcSiKyP5snW3NNRUrmRu4PzFcnGE32LV_yKYpDaQ5GXhJKrQ5VY4X_oQPGDBonrnfS6CE4DTmPC9N3w==	t	Base	19.00000000	\N	2026-02-24 11:31:11.966116+03	2026-03-12 13:09:20.132521+03
3	okx	MarketMakingNode	gAAAAABpnWIKY-0t6J5SeNMBlbJJDHGPXMg_YuBPNLMdzf4sINvor6mmwmytaXsoPFBu9AQgTqtvlvtgvys5GYrS4tN2o3uVwHdDKpujePNK-XbEgW3nRf7JTJlrNy12xFMReZ2Bc9QL	gAAAAABpnWIKGi2dBfbmnFoVq5-sgKDbNjdwlY9ucTv47FzalDdIuQfYDrH_Xi9FlLOOIPS3dNT-TZwIKcxIQJGAKACXPHHUyKYG3zxL6JPNT8k0ndPbBmXGcY1x2XSIx4h5eZSJZXfz	gAAAAABpnWIKFSNWXdNS_gqMxaoCNhqzsR7Vx_qdY5nJGRSymgKaSKPfgt8yoVDYVo9j9Ku7wHRYSvvuCjQCXpl4wilQqiACVw==	t	OP Mainnet	3.70000000	\N	2026-02-24 11:31:11.966116+03	2026-03-12 13:09:20.132521+03
16	mexc	EarlyListingPlay23	gAAAAABpnWIKujhh33LCAkFQx9eGDYAQ_52Jyb7bEtdYmtsdyPZiMDP9oWDTh4nO8YbPKBipbI30Hmgd2Yc3MQuX27h9_AsAB1_wVz3iI44x6a6ZOrA8yuw=	gAAAAABpnWIKKUjI_fJvdPIvDt6cskMyO9YbcheojF54-uLvCHrNjF3_jFcj4_mYMKkOv7Y69wDePxJXaQxbhP7cPYZn5u13vmYfN44w5IFAtQfhJaCtA8htT8anq4EqIRnxuEJUzzp0	\N	t	Base	3.50000000	\N	2026-02-24 11:31:11.977697+03	2026-03-12 13:09:20.132521+03
17	mexc	MarketFlowEngine11	gAAAAABpnWIK9RaO2nkn-WW2qVyM9Q5sPtyFHtBW4fG3v7ES_4M-iNFpoO_nH-UESWGwHHoIxJiQoLFsssfGLwEOYuaiUfggwIO_iNVRkqKkK4JjtqTSmGI=	gAAAAABpnWIK3uMcga5-IPDiUzBP8ZjEpsj3qfS3KdTZrS7KLq_famRKj1aKgdVk1ZrDMwXBL4gpMiCUNz8o4_gd-NzKyaEeV1YPKYBv2bLyXpktuIiHP6R5H6Pp8CA5b-2Q-DZmAWXd	\N	t	OP Mainnet	3.50000000	\N	2026-02-24 11:31:11.977697+03	2026-03-12 13:09:20.132521+03
4	okx	DefiLiquidityPools	gAAAAABpnWIKccehAaHT8an5Sv2PFVQoGcXDluSVKX9ajwFkUuypyP275o4wB2APED3hUf94KA4LF0lhVrJWJZ2N9_No5fev2OTyee42NZYzR2yU2mjIJgXljpcLeisnGYLoxvjgU6E9	gAAAAABpnWIKWAMbZ2v9pJd40UgQfnmxgcullzlV0w2sHnl4GW-V8RvbaqGsSMBy408o3qBIgJ4kZYkDdved1dUMpD9YqRGlRknpkI89X9vmaL90BqOREk5szvxoBTTcoHxuUKU-ZLYs	gAAAAABpnWIKM7GfQ1OpFYoZ6LrJboRRqJ5KvSEli8Il3wKxZS38jNcbMyVukQY50ZsNs_n7XZ8-7Io93jvv4kF3csdKQH8nkA==	t	Base	3.60000000	\N	2026-02-24 11:31:11.966116+03	2026-03-12 13:22:55.209975+03
18	mexc	SecondaryReserve82	gAAAAABpnWIKkHvif_z3z3nBj0FnyLaY9xijwZkCxLkDSN6mVx6h7AZIYHreaS7Hwwz_AB4ahhoqtkx6EFS8FvtlCd0loqbmVG7Yhu19O3lD11Q4YluhKd0=	gAAAAABpnWIKPu5J0Hi2yfT3_LVD35g_5eW9xNjjRxe7mjracruBEl-VK0-fuRfJCmVD46tzqPkbEtO4PTgdZvJ8oxRgLlhk0kZLxOObDD4M6Nf28RQ_3pkZWGcqbiO2hIb1qezJ41aN	\N	t	BSC	3.00000000	\N	2026-02-24 11:31:11.977697+03	2026-03-12 13:22:55.209975+03
13	kucoin	HiddenGemHunter	gAAAAABpnWIKIO2Wwy2O7WMqBhOHhP-Sx8CKvuzx7J7bcoF9a8XWGpt7xhK8k5XBAmClhKYim3MvEX-rWRp_TgndWcR-c3jPgckCucGaX5zHjvcOauHlszk=	gAAAAABpnWIKMvr8YnBwpiu57_yVLzOiHKA0AhjbOfAAu25clrjTpD0IIe2kbCVAf6HoacFjoFAAIARxUZ4gos5Uv2kS2bgCVcdtMfWVqVkkPCWZZqcLrueqyYePVT4C_PoqJR4yZPBn	gAAAAABpvUMkF6nHZhoTlYC52ESAdqdaQ5zZ4ghtXFSx2mx1bYjlllyvQdqXM_3fsLthXeR4sB76IBufYWsTqooV8XkF6elMGg==	t	Arbitrum One	3.10000000	\N	2026-02-24 11:31:11.976935+03	2026-03-20 15:53:00.30265+03
14	kucoin	KCSYieldOptimizer	gAAAAABpnWIKZ3rGW9Km7mWQovugl3lYBCvlYXagM-9IESijHE9Mm21dql68-GlhERNnh6yJZg73EIBL_d1cqUngOC0zd2dA9SebCX1fmfFqoNpoLU4OkCA=	gAAAAABpnWIKrwrO93y0GgovHix5H1PsUAVPI0rXBrynGPklC0a5xYNIHr4WLsca9lK0Fig_wd3SW2XhEgX16-xCBDdmB6IxPkUoZmfn0spkhijcNjz9tPtXHb4AMDPJSDr1UNwyPU6z	gAAAAABpvUMkF6nHZhoTlYC52ESAdqdaQ5zZ4ghtXFSx2mx1bYjlllyvQdqXM_3fsLthXeR4sB76IBufYWsTqooV8XkF6elMGg==	t	OP Mainnet	3.10000000	\N	2026-02-24 11:31:11.976935+03	2026-03-20 15:53:00.30265+03
15	kucoin	BotDeploymentLab	gAAAAABpnWIKFPOjv1LJ8ncoOmAQ0Fq0i3e1lYOfqEK4oFK6qJtGd9B2bHYn09pgcP7YtmqibhLXBQ4L0S6U79A4RFcuxqYJjPB82d5qaM2jSaD7O3zgFzU=	gAAAAABpnWIKEAiAN6CxU4HbxibCYrzSL_SD3wE9EUrAbB0FmkALI__DUO79e9smh-KF57NjZ_TylvXsBb_dTsesreP0GMie9YFcfWGj5ru8QabrSAzoJRoGMXBXNdL-2xogsVoMvhii	gAAAAABpvUMkF6nHZhoTlYC52ESAdqdaQ5zZ4ghtXFSx2mx1bYjlllyvQdqXM_3fsLthXeR4sB76IBufYWsTqooV8XkF6elMGg==	t	Arbitrum One	3.00000000	\N	2026-02-24 11:31:11.976935+03	2026-03-20 15:53:00.30265+03
\.


--
-- Data for Name: chain_aliases; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.chain_aliases (id, chain_id, alias, source, last_seen, created_at) FROM stdin;
1	1	eth	manual	2026-03-09 20:16:49.85298+03	2026-03-09 20:16:49.85298+03
2	1	eth-mainnet	socket	2026-03-09 20:16:49.85298+03	2026-03-09 20:16:49.85298+03
3	1	ethereum mainnet	defillama	2026-03-09 20:16:49.85298+03	2026-03-09 20:16:49.85298+03
4	1	erc20	cex	2026-03-09 20:16:49.85298+03	2026-03-09 20:16:49.85298+03
5	1	mainnet	common	2026-03-09 20:16:49.85298+03	2026-03-09 20:16:49.85298+03
6	42161	arb	manual	2026-03-09 20:16:49.858428+03	2026-03-09 20:16:49.858428+03
7	42161	arbitrum one	socket	2026-03-09 20:16:49.858428+03	2026-03-09 20:16:49.858428+03
8	42161	arbitrum-one	across	2026-03-09 20:16:49.858428+03	2026-03-09 20:16:49.858428+03
9	42161	arb1	common	2026-03-09 20:16:49.858428+03	2026-03-09 20:16:49.858428+03
10	8453	base mainnet	socket	2026-03-09 20:16:49.859438+03	2026-03-09 20:16:49.859438+03
11	8453	base-mainnet	across	2026-03-09 20:16:49.859438+03	2026-03-09 20:16:49.859438+03
12	10	op	manual	2026-03-09 20:16:49.860082+03	2026-03-09 20:16:49.860082+03
13	10	op mainnet	socket	2026-03-09 20:16:49.860082+03	2026-03-09 20:16:49.860082+03
14	10	optimism mainnet	defillama	2026-03-09 20:16:49.860082+03	2026-03-09 20:16:49.860082+03
15	10	optimism-mainnet	across	2026-03-09 20:16:49.860082+03	2026-03-09 20:16:49.860082+03
16	137	matic	manual	2026-03-09 20:16:49.860631+03	2026-03-09 20:16:49.860631+03
17	137	polygon mainnet	defillama	2026-03-09 20:16:49.860631+03	2026-03-09 20:16:49.860631+03
18	137	polygon-mainnet	across	2026-03-09 20:16:49.860631+03	2026-03-09 20:16:49.860631+03
19	56	bsc	manual	2026-03-09 20:16:49.861593+03	2026-03-09 20:16:49.861593+03
20	56	bnb	common	2026-03-09 20:16:49.861593+03	2026-03-09 20:16:49.861593+03
21	56	bnb smart chain	socket	2026-03-09 20:16:49.861593+03	2026-03-09 20:16:49.861593+03
22	56	bnbchain	cex	2026-03-09 20:16:49.861593+03	2026-03-09 20:16:49.861593+03
23	324	zksync	manual	2026-03-09 20:16:49.862168+03	2026-03-09 20:16:49.862168+03
24	324	zksync era	defillama	2026-03-09 20:16:49.862168+03	2026-03-09 20:16:49.862168+03
25	324	era	common	2026-03-09 20:16:49.862168+03	2026-03-09 20:16:49.862168+03
26	534352	scroll	manual	2026-03-09 20:16:49.863004+03	2026-03-09 20:16:49.863004+03
27	534352	scroll mainnet	defillama	2026-03-09 20:16:49.863004+03	2026-03-09 20:16:49.863004+03
28	59144	linea	manual	2026-03-09 20:16:49.863477+03	2026-03-09 20:16:49.863477+03
29	59144	linea mainnet	defillama	2026-03-09 20:16:49.863477+03	2026-03-09 20:16:49.863477+03
30	5000	mantle	manual	2026-03-09 20:16:49.864329+03	2026-03-09 20:16:49.864329+03
31	57073	ink	manual	2026-03-09 20:16:49.864824+03	2026-03-09 20:16:49.864824+03
32	57073	ink mainnet	defillama	2026-03-09 20:16:49.864824+03	2026-03-09 20:16:49.864824+03
33	130	unichain	chainid	2026-03-09 20:21:11.852128+03	2026-03-09 20:21:11.850277+03
35	80069	berachain bepolia	chainid	2026-03-09 20:27:57.163246+03	2026-03-09 20:27:57.163246+03
36	80069	berachain-bepolia	chainid	2026-03-09 20:27:57.165247+03	2026-03-09 20:27:57.165247+03
37	42161	test-alias	test	2026-03-12 12:06:43.616393+03	2026-03-12 12:06:43.616393+03
38	420420	megaeth	manual	2026-03-16 19:56:19.843199+03	2026-03-16 19:56:19.843199+03
39	420420	mega	manual	2026-03-16 19:56:19.843199+03	2026-03-16 19:56:19.843199+03
\.


--
-- Data for Name: chain_rpc_endpoints; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.chain_rpc_endpoints (id, chain, url, priority, is_active, last_used_at, success_count, failure_count, avg_response_ms, created_at, chain_id, is_l2, l1_data_fee, network_type, gas_multiplier, is_auto_discovered, withdrawal_only, low_priority_rpc, native_token, block_time, is_poa, farm_status, token_ticker) FROM stdin;
16	mantle	https://rpc.mantle.xyz	1	t	\N	0	0	\N	2026-03-12 14:25:34.621544+03	5000	t	f	l2	1.0	f	f	https://rpc.mantle.xyz	ETH	2.00	f	ACTIVE	\N
15	manta	https://pacific-rpc.manta.network/http	1	t	\N	0	0	\N	2026-03-12 14:25:34.620254+03	169	t	f	l2	1.0	f	f	https://pacific-rpc.manta.network/http	ETH	2.00	f	ACTIVE	\N
14	arbitrum_nova	https://nova.arbitrum.io/rpc	1	t	\N	0	0	\N	2026-03-12 14:25:34.618248+03	42170	t	f	l2	1.0	f	f	https://nova.arbitrum.io/rpc	ETH	2.00	f	ACTIVE	\N
17	morph	https://rpc-quicknode.morphl2.io	1	t	\N	0	0	\N	2026-03-12 14:25:34.623334+03	2818	t	f	l2	1.0	f	f	https://rpc-quicknode.morphl2.io	ETH	2.00	f	ACTIVE	\N
13	polygon	https://polygon-rpc.com	1	t	\N	0	0	\N	2026-03-12 13:22:55.209975+03	137	f	f	sidechain	2.0	f	t	https://polygon-rpc.com	MATIC	2.00	t	ACTIVE	\N
12	bsc	https://bsc-dataseed.binance.org	1	t	\N	0	0	\N	2026-03-12 13:22:55.209975+03	56	f	f	sidechain	2.0	f	t	https://bsc-dataseed1.binance.org	BNB	3.00	t	ACTIVE	\N
7	zksync	https://mainnet.era.zksync.io	1	t	\N	0	0	\N	2026-02-26 20:24:43.526979+03	324	t	t	l2	5.0	f	f	https://mainnet.era.zksync.io	ETH	2.00	f	DROPPED	\N
8	linea	https://rpc.linea.build	1	t	\N	0	0	\N	2026-02-26 20:24:43.526979+03	59144	t	t	l2	5.0	f	f	https://linea.public-rpc.com	ETH	2.00	f	DROPPED	\N
9	scroll	https://rpc.scroll.io	1	t	\N	0	0	\N	2026-02-26 20:24:43.526979+03	534352	t	t	l2	5.0	f	f	https://scroll.public-rpc.com	ETH	2.00	f	DROPPED	\N
2	arbitrum	https://arb1.arbitrum.io/rpc	1	t	\N	0	0	\N	2026-02-26 20:24:43.526979+03	42161	t	t	l2	5.0	f	f	https://arbitrum.public-rpc.com	ETH	0.25	f	DROPPED	\N
3	optimism	https://mainnet.optimism.io	1	t	\N	0	0	\N	2026-02-26 20:24:43.526979+03	10	t	t	l2	5.0	f	f	https://optimism.publicnode.com	ETH	2.00	f	DROPPED	\N
10	unichain	https://mainnet.unichain.org	1	t	\N	0	0	\N	2026-03-09 20:21:11.845987+03	130	t	f	l2	2.0	t	f	https://mainnet.unichain.org	ETH	2.00	f	TARGET	\N
1	base	https://mainnet.base.org	1	t	\N	0	0	\N	2026-02-26 20:24:43.526979+03	8453	t	t	l2	5.0	f	f	https://base-rpc.publicnode.com	ETH	2.00	f	TARGET	\N
\.


--
-- Data for Name: chain_rpc_health_log; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.chain_rpc_health_log (id, rpc_endpoint_id, status, response_time_ms, error_message, checked_at) FROM stdin;
\.


--
-- Data for Name: chain_tokens; Type: TABLE DATA; Schema: public; Owner: farming_user
--

COPY public.chain_tokens (id, chain_id, token_symbol, token_address, is_native_wrapped, decimals, created_at) FROM stdin;
1	1	WETH	0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2	t	18	2026-03-22 10:10:44.135973+03
2	42161	WETH	0x82aF49447D8a07e3bd95BD0d56f35241523fBab1	t	18	2026-03-22 10:10:44.135973+03
3	8453	WETH	0x4200000000000000000000000000000000000006	t	18	2026-03-22 10:10:44.135973+03
4	10	WETH	0x4200000000000000000000000000000000000006	t	18	2026-03-22 10:10:44.135973+03
5	137	WMATIC	0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270	t	18	2026-03-22 10:10:44.135973+03
6	56	WBNB	0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c	t	18	2026-03-22 10:10:44.135973+03
7	57073	WETH	0x4200000000000000000000000000000000000006	t	18	2026-03-22 10:10:44.135973+03
8	1088	WETH	0x4200000000000000000000000000000000000006	t	18	2026-03-22 10:10:44.135973+03
9	42161	USDC	0xaf88d065e77c8cC2239327C5EDb3A432268e5831	f	6	2026-03-22 10:10:44.365822+03
10	8453	USDC	0x833589fCD6eDb6E08f4c7C32D4f71b54bDA02913	f	6	2026-03-22 10:10:44.365822+03
11	10	USDC	0x7F5c764cBc14f9669B88837ca1490cCa17c31607	f	6	2026-03-22 10:10:44.365822+03
12	137	USDC	0x3c499c542cEF5E3811e1192ce70d8cC03d5c335	f	6	2026-03-22 10:10:44.365822+03
13	42161	USDT	0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb	f	6	2026-03-22 10:10:44.365822+03
14	8453	USDT	0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb	f	6	2026-03-22 10:10:44.365822+03
15	10	USDT	0x94b008aA00579c1307B0EF2c499aD98a8ce58e58	f	6	2026-03-22 10:10:44.365822+03
16	137	USDT	0xc2132D05D31c914a87C6611C10748AEb04B58e8F	f	6	2026-03-22 10:10:44.365822+03
\.


--
-- Data for Name: defillama_bridges_cache; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.defillama_bridges_cache (id, bridge_name, display_name, chains, tvl_usd, volume_30d_usd, rank, hacks, fetched_at, expires_at) FROM stdin;
\.


--
-- Data for Name: discovery_failures; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.discovery_failures (id, network_name, sources_checked, error_message, retry_count, last_retry_at, resolved, resolved_at, resolved_chain_id, created_at) FROM stdin;
1	MegaETH	{chainid}	No RPC endpoints available for MegaETH Mainnet	0	\N	t	2026-03-16 19:56:19.843199+03	420420	2026-03-09 20:18:57.976043+03
\.


--
-- Data for Name: ens_names; Type: TABLE DATA; Schema: public; Owner: farming_user
--

COPY public.ens_names (id, wallet_id, ens_name, parent_domain, registration_tx_hash, registered_at, expires_at, cost_eth, created_at) FROM stdin;
\.


--
-- Data for Name: funding_chains; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.funding_chains (id, chain_number, cex_subaccount_id, withdrawal_network, base_amount_usdt, wallets_count, status, started_at, completed_at, created_at, actual_wallet_count) FROM stdin;
80	1	13	Ink	15.20	4	pending	\N	\N	2026-03-01 19:00:51.925447+03	4
81	2	3	Ink	15.20	4	pending	\N	\N	2026-03-01 19:00:51.945266+03	4
83	4	16	Polygon	11.40	3	pending	\N	\N	2026-03-01 19:00:51.968932+03	3
84	5	2	Ink	15.20	4	pending	\N	\N	2026-03-01 19:00:51.975648+03	4
85	6	17	Ink	22.80	6	pending	\N	\N	2026-03-01 19:00:51.982724+03	6
86	7	10	Base	19.00	5	pending	\N	\N	2026-03-01 19:00:51.994683+03	5
87	8	8	BNB Chain	15.20	4	pending	\N	\N	2026-03-01 19:00:52.006465+03	4
88	9	1	Ink	11.40	3	pending	\N	\N	2026-03-01 19:00:52.019398+03	3
89	11	9	Polygon	19.00	5	pending	\N	\N	2026-03-01 19:00:52.028888+03	5
90	12	7	Polygon	15.20	4	pending	\N	\N	2026-03-01 19:00:52.040421+03	4
91	13	5	Polygon	19.00	5	pending	\N	\N	2026-03-01 19:00:52.049956+03	5
92	14	6	BNB Chain	19.00	5	pending	\N	\N	2026-03-01 19:00:52.060852+03	5
93	15	14	BNB Chain	26.60	7	pending	\N	\N	2026-03-01 19:00:52.074782+03	7
94	16	11	BNB Chain	22.80	6	pending	\N	\N	2026-03-01 19:00:52.093091+03	6
95	17	15	Base	26.60	7	pending	\N	\N	2026-03-01 19:00:52.114676+03	7
96	18	18	Base	19.00	5	pending	\N	\N	2026-03-01 19:00:52.128164+03	5
100	19	12	BNB Chain	35.00	7	pending	\N	\N	2026-03-01 19:38:26.742624+03	7
82	3	4	Base	15.20	4	pending	\N	\N	2026-03-01 19:00:51.956504+03	6
\.


--
-- Data for Name: funding_withdrawals; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.funding_withdrawals (id, funding_chain_id, wallet_id, cex_subaccount_id, withdrawal_network, amount_usdt, withdrawal_address, cex_txid, blockchain_txhash, status, delay_minutes, scheduled_at, requested_at, completed_at, created_at, direct_cex_withdrawal, cex_withdrawal_scheduled_at, cex_withdrawal_completed_at, interleave_round, interleave_position) FROM stdin;
291	86	149	10	Polygon	3.5955	0x8e7FF44287f809eeb1a1d8cd41c3f373E6363D37	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.999765+03	t	2026-03-02 16:33:55.673426+03	\N	0	3
293	86	134	10	Polygon	3.1644	0xBE580CAD83568f84F3Cc589Fc386e4Eb19Fe108e	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.003458+03	t	2026-03-10 04:40:33.17374+03	\N	12	2
292	86	114	10	Polygon	3.0030	0xC458529e3B8510B2064959EAF562B32621Bb0f2a	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.001705+03	t	2026-03-11 10:35:36.644534+03	\N	14	3
345	100	80	12	BNB Chain	5.8244	0xae667016c0663EfcD6e56a0BeD47E9c431119199	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:38:26.753338+03	t	2026-03-01 21:32:05.951321+03	\N	\N	\N
312	91	83	5	Ink	3.5653	0xF22C7b5E1116975d71E9B7324e56FB1109E91Db3	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.054922+03	t	2026-03-03 16:05:42.79522+03	\N	2	1
313	91	120	5	Ink	4.1993	0xB605b58Cde7f1A05F69833968a963736F1AD3b98	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.056619+03	t	2026-03-10 05:41:44.530541+03	\N	12	3
314	91	112	5	Ink	3.2767	0xAcEC26ac4c7d02e490aCEb198631F6F8D19753d9	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.05834+03	t	2026-03-11 02:57:16.586999+03	\N	14	1
311	91	105	5	Ink	4.5554	0xDdd0A3b96403D4Be0B5ccd1808849cE0AA246cbF	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.053245+03	t	2026-03-12 01:51:40.980817+03	\N	15	2
317	92	100	6	BNB Chain	4.2593	0xD50fA1e57267eF8db916487B24046a8f74fd5E85	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.069193+03	t	2026-03-05 06:14:56.903812+03	\N	3	3
315	92	113	6	BNB Chain	4.6837	0xB2178A2B1Fce69Fa16f4507F9E18c1fB9D3Fb2b5	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.062892+03	t	2026-03-07 17:33:40.878614+03	\N	8	0
316	92	154	6	BNB Chain	4.3892	0xC40b2c9B6D6D0466C37dA4AE14AaA7185831f469	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.06453+03	t	2026-03-09 09:20:53.788362+03	\N	11	0
319	92	151	6	BNB Chain	3.6422	0xEE48c65eFd6508CE8c6E03861a8CA36Feee40b02	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.072764+03	t	2026-03-10 09:13:01.318494+03	\N	13	0
307	90	89	7	Polygon	4.0808	0xB0FB517883BE4FB8c57986A616fCDf21B37E5eEb	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.044327+03	t	2026-03-06 13:24:48.91563+03	\N	6	2
308	90	138	7	Polygon	3.8101	0x96141f48fd852D24DA335ca58850b4c5c54d5d98	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.046095+03	t	2026-03-07 20:04:20.027491+03	\N	8	1
306	90	79	7	Polygon	3.8990	0x4467EFcAB3020De031305B8C144A20e57758d482	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.042525+03	t	2026-03-08 14:16:39.608421+03	\N	9	3
309	90	144	7	Polygon	3.9707	0x13383F428F6788ab83347C6183d9446fF1FdC8f5	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.047616+03	t	2026-03-10 14:12:55.367484+03	\N	13	2
296	87	75	8	Polygon	3.0385	0x9748DbD2E9c5B5A4699293F6aD41a7350801d408	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.013559+03	t	2026-03-04 06:17:48.682119+03	\N	2	4
294	87	157	8	Polygon	3.5528	0x72743be4399EC985b1E053869b3029CfD094ca5D	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.008559+03	t	2026-03-06 22:08:42.005509+03	\N	7	0
297	87	128	8	Polygon	4.2231	0x674c661591cEbDddBaBb8BfFBb8E3f25378bECf1	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.016575+03	t	2026-03-11 23:06:09.517508+03	\N	15	1
295	87	146	8	Polygon	4.6296	0xc4FBb2A03fAe4CbFe823b53C5C0f1cCA83244532	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.011374+03	t	2026-03-12 02:53:50.901652+03	\N	15	3
298	88	91	1	MegaETH	3.3468	0x3aB0590C7C3c74A78D9569AeE33C0712B716b3f2	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.021552+03	t	2026-03-02 04:22:58.387248+03	\N	0	1
300	88	126	1	MegaETH	3.2842	0x1dDb2Bc11D4984001E6E9DADcA203966ae1cAd96	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.025437+03	t	2026-03-07 03:40:11.570217+03	\N	7	2
299	88	70	1	MegaETH	3.1793	0x19510aFc0e1E03aC61D9C92870ded47A3123A81B	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.023467+03	t	2026-03-13 05:09:07.569823+03	\N	17	1
281	84	97	2	Arbitrum	3.4523	0xfDe65a0Ed057256517b99099A27ff99f4C744621	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.979608+03	t	2026-03-03 04:34:38.849803+03	\N	1	3
280	84	103	2	Arbitrum	4.0359	0x7CbB2783F1540e213dCf53E5BEeb1c2102EBB95C	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.978301+03	t	2026-03-13 00:18:15.130047+03	\N	16	4
279	84	155	2	Arbitrum	4.3872	0x405F8cdCF7f2D9CC494084302380b73e6c0953e5	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.976984+03	t	2026-03-13 18:02:09.8871+03	\N	17	4
269	81	135	3	Polygon	4.5277	0xD9df537524cFf1A5205BD0B73184c2Ce61Bc3943	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.949395+03	t	2026-03-04 02:25:26.837142+03	\N	2	3
270	81	98	3	Polygon	3.9400	0x4ED3456163DBa34422e4f4dE780B8593DD23EafC	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.951605+03	t	2026-03-12 22:24:50.745766+03	\N	16	3
271	81	156	3	Polygon	3.4726	0x1D56088663c274eeb5715D764e36fcf4A2b86229	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.953591+03	t	2026-03-13 10:12:36.575351+03	\N	17	3
272	82	147	4	Polygon	4.4871	0x98Dd6F2Eb0395A4AE80Fc34da4DF697a6f29D136	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.958745+03	t	2026-03-08 00:41:15.282667+03	\N	8	3
274	82	123	4	Polygon	3.6343	0x7D96b11047B3Cab8F6676dbbE30857166aA61463	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.964498+03	t	2026-03-11 16:27:02.833773+03	\N	14	4
275	82	77	4	Polygon	4.3389	0xF35910C057C7663655445cb78d3983A28C188eaE	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.966443+03	t	2026-03-12 10:05:39.644432+03	\N	16	1
273	82	127	4	Polygon	4.4301	0xF9F82189c549C7C43c889D31fe10F2Ad363568E6	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.960378+03	t	2026-03-13 02:57:01.914163+03	\N	17	0
267	80	148	13	Polygon	4.5228	0x60CC956C78f8ed820c9Dd9A34E51fddC2E2500Aa	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.938587+03	t	2026-03-02 10:11:10.501619+03	\N	0	2
266	80	152	13	Polygon	3.2504	0x35F8C8f40eaB2a838F56d4bFf2040a60984F01fd	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.936656+03	t	2026-03-04 21:40:07.814441+03	\N	3	2
264	80	93	13	Polygon	3.6749	0x4C84CAc44e8D2d693F63827402bF743fd92cd2e1	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.930502+03	t	2026-03-05 12:07:24.703421+03	\N	4	1
324	93	121	14	Polygon	3.8438	0xEeFC44c50Da346E8298A36E9E7A342641479fFEF	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.088386+03	t	2026-03-06 04:44:15.02193+03	\N	5	3
320	93	73	14	Polygon	3.7870	0xE78B044126B28723b7C242dcDdf776539600C73f	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.078785+03	t	2026-03-08 12:45:47.261349+03	\N	9	2
322	93	85	14	Polygon	3.5391	0x4A6940F556B4E7dEf36C53A00Ea5Cd93B97EEE7c	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.082593+03	t	2026-03-08 21:50:49.210622+03	\N	10	2
277	83	130	16	Polygon	3.7914	0x10b812e6EBD07BE4e620959b9Eac641EafDE7436	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.972211+03	t	2026-03-05 21:55:31.270684+03	\N	5	0
276	83	86	16	Polygon	3.3360	0x26cd0DD5E268C7069483e8C1a607dC532622d61C	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.970661+03	t	2026-03-06 10:11:01.42477+03	\N	6	1
278	83	150	16	Polygon	3.4667	0x79B5cA55590c9268c908190aaa419EA34541e23D	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.973716+03	t	2026-03-10 03:08:27.806843+03	\N	12	1
283	85	108	17	Polygon	3.3990	0xa19a08F9422c768d6DE28cC31443Bf39cecE7D46	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.984206+03	t	2026-03-02 21:46:00.695641+03	\N	1	0
288	85	153	17	Polygon	3.4982	0x53941398b353DF9B695804A675D0F2a8d71629a9	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.992318+03	t	2026-03-02 23:16:36.35231+03	\N	1	1
286	85	133	17	Polygon	2.8687	0x7Ff72EaFc5F9594C7D70e8a26bBD57D234228319	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.988683+03	t	2026-03-06 01:57:34.532245+03	\N	5	2
284	85	137	17	Polygon	4.3217	0x1Fe6d9ff0E8DCA86429412b8A23174dFbb6E037B	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.985723+03	t	2026-03-07 13:33:50.706463+03	\N	7	4
285	85	136	17	Polygon	3.9659	0x33948339Eb5c337c4364Ebdb29481484F09F2C24	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.987249+03	t	2026-03-08 11:32:13.471929+03	\N	9	1
303	89	92	9	Base	3.1954	0xae8BBed706B0db3EAd8DD669Cf8C81bC79cDcCB3	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.034574+03	t	2026-03-04 10:17:24.808382+03	\N	3	0
304	89	129	9	Base	4.3637	0xb7717c2c4fE5363080DDc2408Fd8D2070c58894f	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.036337+03	t	2026-03-06 23:50:15.641325+03	\N	7	1
301	89	74	9	Base	4.3614	0x75C5499AC72DAeF83364fda275a040D3778Bbf4B	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.030875+03	t	2026-03-09 06:49:44.918137+03	\N	10	3
302	89	78	9	Base	4.6790	0x2Fde057CbE256c5Cf77a0bF3457fC2fFCA70F043	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.032865+03	t	2026-03-12 04:37:01.131354+03	\N	15	4
305	89	124	9	Base	3.4610	0x77eE2026B78f1f92144fC49EE8e5fbA8d6E51d86	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.038147+03	t	2026-03-12 13:37:12.141338+03	\N	16	2
290	86	94	10	Polygon	2.8776	0xA2f793c08cA784eF7902c55c9f24C1F99875e612	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.998341+03	t	2026-03-10 20:39:20.483032+03	\N	13	3
289	86	82	10	Polygon	3.9205	0x45f505b241522C8d20caEE8b934fadDa71c48fEE	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.996528+03	t	2026-03-13 08:12:22.758009+03	\N	17	2
328	94	158	11	Polygon	3.4393	0xf9B7b016dddBB0eaa9CE75AC78F0D87A0558C8a5	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.099903+03	t	2026-03-06 07:12:15.777234+03	\N	6	0
331	94	106	11	Polygon	3.2048	0x8E95a32a1d2A45CC7d1FA1495f3eFCdFAC325c77	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.107545+03	t	2026-03-08 18:30:57.614005+03	\N	10	1
330	94	84	11	Polygon	4.5876	0x1C387e357a23A5100EE46413D762eb7F893587f6	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.103507+03	t	2026-03-09 11:31:22.554853+03	\N	11	1
327	94	81	11	Polygon	4.0285	0x6ba4842E3422f7A6CdA6cb7Edc1e1652dB029ABB	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.096666+03	t	2026-03-09 19:45:07.944394+03	\N	12	0
332	94	99	11	Polygon	4.7224	0x6b018D943F5eb5426e9327D2945786ecA4F1CD3B	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.112116+03	t	2026-03-11 17:32:18.886608+03	\N	14	5
329	94	110	11	Polygon	3.4238	0x21C3e7FE71B243b96835DA024430CC1fcf126402	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.101823+03	t	2026-03-11 20:41:02.487501+03	\N	15	0
346	100	143	12	BNB Chain	4.7695	0x4e5be5eDa12E261F89785A91be52F991F075d3d3	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:38:26.764279+03	t	2026-03-01 22:12:40.864262+03	\N	\N	\N
347	100	125	12	BNB Chain	4.4339	0x9D48d22ab0f8F98E90e8ccDF1CA75d1de6085634	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:38:26.765918+03	t	2026-03-02 00:40:02.623188+03	\N	\N	\N
348	100	122	12	BNB Chain	5.2161	0x5EeFaeD710e78A3f030C327299CA399FD3937eda	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:38:26.76981+03	t	2026-03-01 22:05:38.848819+03	\N	\N	\N
349	100	141	12	BNB Chain	4.7165	0x164c20DFcba24d3f93F38DE41cbb9f32feb26860	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:38:26.774645+03	t	2026-03-01 21:12:36.930174+03	\N	\N	\N
350	100	132	12	BNB Chain	3.9428	0xFbfD8F8BcE36CB91C97Ba9917a018f9560A6212A	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:38:26.775821+03	t	2026-03-01 23:00:33.102025+03	\N	\N	\N
310	91	87	5	Ink	4.5156	0x106e0d48857c3EADAFDDa9DCECF3ebB80bb05CDe	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.051588+03	t	2026-03-09 12:54:30.222668+03	\N	11	2
318	92	96	6	BNB Chain	4.0354	0x28Aca1F2D769E4c94cbDA8db299A29Ca10A3c11F	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.071193+03	t	2026-03-02 02:49:00.783488+03	\N	0	0
282	84	76	2	Arbitrum	2.9703	0x70915d796a9659Ae1e733B00F87db0D37cdd75eD	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.980897+03	t	2026-03-12 06:57:31.308508+03	\N	16	0
268	81	109	3	Polygon	4.0207	0x929623e7321d8D0B80dC57AA19AD97a5290142a2	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.947239+03	t	2026-03-03 01:45:24.039674+03	\N	1	2
352	82	119	4	Polygon	2.7378	0xCE437F5Cbc092246b3887582A6F6886e09B7865E	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:38:53.112581+03	t	2026-03-01 22:08:57.018166+03	\N	\N	\N
353	82	111	4	Polygon	3.6328	0x1d3B748beC68e391490959A8325156E8F2A73AD9	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:38:53.119777+03	t	2026-03-01 23:08:40.94187+03	\N	\N	\N
265	80	90	13	Polygon	3.6781	0x1319ad348b84d069423cCf88D3073198e8f01c68	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.934422+03	t	2026-03-08 04:40:04.915401+03	\N	9	0
326	93	102	14	Polygon	4.3816	0x7951A2DAB3bF521849c0513777d493031F7ee8DC	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.091431+03	t	2026-03-03 17:17:18.231261+03	\N	2	2
323	93	101	14	Polygon	3.3566	0xF625B0E7A15c6490a1AeF4D9955e95A2d0dE4389	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.086723+03	t	2026-03-05 07:52:21.840498+03	\N	4	0
325	93	117	14	Polygon	3.3683	0x67a8f2421b7869370D89182A14f14FD16a09b040	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.08969+03	t	2026-03-05 20:36:40.818059+03	\N	4	3
321	93	140	14	Polygon	2.9922	0x9c9b6fce5Fe98c578E332A8C0237354507090Ce0	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.080745+03	t	2026-03-06 16:58:52.037633+03	\N	6	3
337	95	116	15	BNB Chain	3.2503	0x80F6719fEa96611Ef0D9e63DdDdF933e4f48a32E	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.123128+03	t	2026-03-03 06:25:48.191857+03	\N	2	0
338	95	142	15	BNB Chain	4.2367	0x5e885A345B6e63A3FC30226E22bCb9EC7CBE3876	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.124374+03	t	2026-03-05 17:33:55.154805+03	\N	4	2
339	95	71	15	BNB Chain	4.0742	0x4d03A80E49386c7A3cA82d41bF6641a54627fA2c	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.125737+03	t	2026-03-06 00:19:27.79547+03	\N	5	1
336	95	107	15	BNB Chain	3.5646	0xa89AA002FFEc15e1Cff95A60604af8f2044faDaf	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.121817+03	t	2026-03-06 18:15:16.36861+03	\N	6	4
333	95	72	15	BNB Chain	3.9837	0xcD61A654D79AAb27Daf77b9E0471615de9629951	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.11625+03	t	2026-03-07 05:46:21.01793+03	\N	7	3
334	95	115	15	BNB Chain	3.4591	0x7c18513e8f8b6C6bAf6bC0B4040D57E732f9710E	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.11903+03	t	2026-03-07 23:40:41.578262+03	\N	8	2
335	95	95	15	BNB Chain	3.2706	0x926819A4608A8392CDfFe1Fd333a27e24F88981c	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.120587+03	t	2026-03-10 13:10:58.263806+03	\N	13	1
342	96	69	18	BNB Chain	3.7313	0x38C66feE48071d872cD06D4faaFf8e2fD2054D3F	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.133091+03	t	2026-03-04 17:42:54.586828+03	\N	3	1
340	96	88	18	BNB Chain	4.6792	0x168BD8De0B96f6D4AceF721DEc7eB2ae60654b39	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.129923+03	t	2026-03-08 16:59:18.007919+03	\N	10	0
343	96	118	18	BNB Chain	4.0867	0xB1dFDF7B87B624e0b303846e93B927F5Ae0E49c8	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.134495+03	t	2026-03-09 17:43:54.891395+03	\N	11	4
341	96	104	18	BNB Chain	4.1709	0xD1e42eFfbe99871FA0188f7cDb22DCC6954e6039	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.131721+03	t	2026-03-11 00:38:39.037555+03	\N	14	0
344	96	131	18	BNB Chain	4.5870	0x183a5Fe19Ef43eb6b47C01f29F27c101F1dD02CF	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:52.135737+03	t	2026-03-11 06:13:45.862427+03	\N	14	2
351	100	139	12	BNB Chain	4.0742	0xb37010788E0F951ccc3576Bb185c23AC259becD9	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:38:26.777163+03	t	2026-03-01 22:13:17.349529+03	\N	\N	\N
287	85	145	17	Polygon	4.3774	0xb72cc922d27Df12A32bA773B73F04B97516466B3	\N	\N	planned	\N	\N	\N	\N	2026-03-01 19:00:51.990336+03	t	2026-03-09 13:55:20.466409+03	\N	11	3
\.


--
-- Data for Name: gas_history; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.gas_history (id, chain_id, gas_price_gwei, recorded_at) FROM stdin;
\.


--
-- Data for Name: gas_snapshots; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.gas_snapshots (id, chain, slow_gwei, normal_gwei, fast_gwei, block_number, recorded_at) FROM stdin;
\.


--
-- Data for Name: gitcoin_stamps; Type: TABLE DATA; Schema: public; Owner: farming_user
--

COPY public.gitcoin_stamps (id, wallet_id, stamp_type, stamp_id, earned_at, expires_at, score_contribution, metadata, created_at) FROM stdin;
\.


--
-- Data for Name: lens_profiles; Type: TABLE DATA; Schema: public; Owner: farming_user
--

COPY public.lens_profiles (id, wallet_id, profile_id, handle, created_tx_hash, follower_count, following_count, publication_count, last_activity_at, metadata, created_at) FROM stdin;
\.


--
-- Data for Name: news_items; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.news_items (id, title, url, source, published_at, keywords, relevance_score, is_reviewed, created_at) FROM stdin;
\.


--
-- Data for Name: openclaw_profiles; Type: TABLE DATA; Schema: public; Owner: farming_user
--

COPY public.openclaw_profiles (id, wallet_id, browser_fingerprint, cookies, local_storage, session_storage, indexed_db_state, profile_path, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: openclaw_reputation; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.openclaw_reputation (id, wallet_id, has_ens, ens_name, gitcoin_passport_score, gitcoin_stamps_count, poap_count, snapshot_votes_count, lens_profile, total_donations_usdt, last_updated_at) FROM stdin;
\.


--
-- Data for Name: openclaw_task_history; Type: TABLE DATA; Schema: public; Owner: farming_user
--

COPY public.openclaw_task_history (id, task_id, attempt_number, started_at, completed_at, duration_seconds, screenshot_path, error_message, stack_trace, metadata, created_at) FROM stdin;
\.


--
-- Data for Name: openclaw_tasks; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.openclaw_tasks (id, wallet_id, task_type, protocol_id, task_params, status, scheduled_at, started_at, completed_at, error_message, retry_count, max_retries, created_at, priority, assigned_worker_id) FROM stdin;
\.


--
-- Data for Name: personas_config; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.personas_config (id, persona_type, description, default_tx_per_week_mean, default_tx_per_week_stddev, default_preferred_hours_range, created_at) FROM stdin;
13	ActiveTrader	High activity: daytime and evening	4.50	1.20	{8,9,10,11,12,13,14,15,16,17,18,19,20,21,22}	2026-03-12 12:37:45.546687+03
14	CasualUser	Medium activity: primarily evenings	2.50	0.80	{17,18,19,20,21,22,23}	2026-03-12 12:37:45.546687+03
15	WeekendWarrior	Low weekday, high weekend activity	2.00	0.70	{10,11,12,13,14,15,16,17,18,19,20,21}	2026-03-12 12:37:45.546687+03
16	Ghost	Minimal activity: sporadic timing	1.00	0.50	{6,7,8,14,15,20,21,22,23}	2026-03-12 12:37:45.546687+03
17	MorningTrader	Active in morning hours (6-11 UTC)	3.50	1.00	{6,7,8,9,10,11}	2026-03-12 12:37:45.546687+03
18	NightOwl	Active in late evening/night (21-02 UTC)	3.00	0.90	{21,22,23,0,1,2}	2026-03-12 12:37:45.546687+03
19	WeekdayOnly	Only active Monday-Friday	2.50	0.80	{9,10,11,12,13,14,15,16,17,18}	2026-03-12 12:37:45.546687+03
20	MonthlyActive	Very low frequency, 1-2 TX per month	0.50	0.30	{10,11,12,13,14,15,16,17,18}	2026-03-12 12:37:45.546687+03
21	BridgeMaxi	Focus on bridge and cross-chain activity	2.50	0.80	{10,11,12,13,14,15,16,17,18,19,20}	2026-03-12 12:37:45.546687+03
22	DeFiDegen	High DeFi activity, complex transactions	4.00	1.10	{8,9,10,11,12,13,14,15,16,17,18,19,20,21,22}	2026-03-12 12:37:45.546687+03
23	NFTCollector	Focus on NFT mints and transfers	2.00	0.70	{12,13,14,15,16,17,18,19,20}	2026-03-12 12:37:45.546687+03
24	Governance	Focus on governance votes and delegation	1.50	0.60	{10,11,12,13,14,15,16,17,18,19,20}	2026-03-12 12:37:45.546687+03
\.


--
-- Data for Name: poap_tokens; Type: TABLE DATA; Schema: public; Owner: farming_user
--

COPY public.poap_tokens (id, wallet_id, event_id, event_name, token_id, claimed_at, metadata, created_at) FROM stdin;
\.


--
-- Data for Name: points_programs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.points_programs (id, protocol_id, program_name, api_url, check_method, multiplier_active, multiplier_ends_at, created_at) FROM stdin;
\.


--
-- Data for Name: protocol_actions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.protocol_actions (id, protocol_id, action_name, tx_type, layer, chain, contract_id, function_signature, default_params, min_amount_usdt, max_amount_usdt, estimated_gas_gwei, points_multiplier, is_enabled, created_at, updated_at) FROM stdin;
1	1	swap_eth_for_tokens	SWAP	web3py	arbitrum	\N	\N	\N	10.0000	500.0000	150	1.00	t	2026-03-25 19:38:11.545377+03	2026-03-25 19:38:11.545377+03
2	1	swap_eth_for_tokens	SWAP	web3py	base	\N	\N	\N	10.0000	500.0000	150	1.00	t	2026-03-25 19:38:11.545377+03	2026-03-25 19:38:11.545377+03
3	1	swap_eth_for_tokens	SWAP	web3py	optimism	\N	\N	\N	10.0000	500.0000	150	1.00	t	2026-03-25 19:38:11.545377+03	2026-03-25 19:38:11.545377+03
4	1	swap_eth_for_tokens	SWAP	web3py	polygon	\N	\N	\N	10.0000	500.0000	150	1.00	t	2026-03-25 19:38:11.545377+03	2026-03-25 19:38:11.545377+03
5	1	swap_eth_for_tokens	SWAP	web3py	bsc	\N	\N	\N	10.0000	500.0000	150	1.00	t	2026-03-25 19:38:11.545377+03	2026-03-25 19:38:11.545377+03
6	1	swap_eth_for_tokens	SWAP	web3py	zksync	\N	\N	\N	10.0000	500.0000	150	1.00	t	2026-03-25 19:38:11.545377+03	2026-03-25 19:38:11.545377+03
7	1	swap_eth_for_tokens	SWAP	web3py	unichain	\N	\N	\N	10.0000	500.0000	150	1.00	t	2026-03-25 19:38:11.545377+03	2026-03-25 19:38:11.545377+03
8	1	add_liquidity_eth	LP	web3py	arbitrum	\N	\N	\N	50.0000	1000.0000	250	1.00	t	2026-03-25 19:38:11.704995+03	2026-03-25 19:38:11.704995+03
9	1	add_liquidity_eth	LP	web3py	base	\N	\N	\N	50.0000	1000.0000	250	1.00	t	2026-03-25 19:38:11.704995+03	2026-03-25 19:38:11.704995+03
10	1	add_liquidity_eth	LP	web3py	optimism	\N	\N	\N	50.0000	1000.0000	250	1.00	t	2026-03-25 19:38:11.704995+03	2026-03-25 19:38:11.704995+03
11	1	add_liquidity_eth	LP	web3py	polygon	\N	\N	\N	50.0000	1000.0000	250	1.00	t	2026-03-25 19:38:11.704995+03	2026-03-25 19:38:11.704995+03
12	1	add_liquidity_eth	LP	web3py	bsc	\N	\N	\N	50.0000	1000.0000	250	1.00	t	2026-03-25 19:38:11.704995+03	2026-03-25 19:38:11.704995+03
13	1	add_liquidity_eth	LP	web3py	zksync	\N	\N	\N	50.0000	1000.0000	250	1.00	t	2026-03-25 19:38:11.704995+03	2026-03-25 19:38:11.704995+03
14	1	add_liquidity_eth	LP	web3py	unichain	\N	\N	\N	50.0000	1000.0000	250	1.00	t	2026-03-25 19:38:11.704995+03	2026-03-25 19:38:11.704995+03
15	1	wrap_eth	WRAP	web3py	arbitrum	\N	\N	\N	10.0000	500.0000	50	1.00	t	2026-03-25 19:38:11.844736+03	2026-03-25 19:38:11.844736+03
16	1	wrap_eth	WRAP	web3py	base	\N	\N	\N	10.0000	500.0000	50	1.00	t	2026-03-25 19:38:11.844736+03	2026-03-25 19:38:11.844736+03
17	1	wrap_eth	WRAP	web3py	optimism	\N	\N	\N	10.0000	500.0000	50	1.00	t	2026-03-25 19:38:11.844736+03	2026-03-25 19:38:11.844736+03
18	1	wrap_eth	WRAP	web3py	polygon	\N	\N	\N	10.0000	500.0000	50	1.00	t	2026-03-25 19:38:11.844736+03	2026-03-25 19:38:11.844736+03
19	1	wrap_eth	WRAP	web3py	bsc	\N	\N	\N	10.0000	500.0000	50	1.00	t	2026-03-25 19:38:11.844736+03	2026-03-25 19:38:11.844736+03
20	1	wrap_eth	WRAP	web3py	zksync	\N	\N	\N	10.0000	500.0000	50	1.00	t	2026-03-25 19:38:11.844736+03	2026-03-25 19:38:11.844736+03
21	1	wrap_eth	WRAP	web3py	unichain	\N	\N	\N	10.0000	500.0000	50	1.00	t	2026-03-25 19:38:11.844736+03	2026-03-25 19:38:11.844736+03
22	8	deposit_eth	STAKE	web3py	arbitrum	\N	\N	\N	50.0000	2000.0000	200	1.00	t	2026-03-25 19:38:11.984739+03	2026-03-25 19:38:11.984739+03
23	8	deposit_eth	STAKE	web3py	base	\N	\N	\N	50.0000	2000.0000	200	1.00	t	2026-03-25 19:38:11.984739+03	2026-03-25 19:38:11.984739+03
24	8	deposit_eth	STAKE	web3py	optimism	\N	\N	\N	50.0000	2000.0000	200	1.00	t	2026-03-25 19:38:11.984739+03	2026-03-25 19:38:11.984739+03
25	8	deposit_eth	STAKE	web3py	polygon	\N	\N	\N	50.0000	2000.0000	200	1.00	t	2026-03-25 19:38:11.984739+03	2026-03-25 19:38:11.984739+03
26	8	deposit_eth	STAKE	web3py	scroll	\N	\N	\N	50.0000	2000.0000	200	1.00	t	2026-03-25 19:38:11.984739+03	2026-03-25 19:38:11.984739+03
27	8	withdraw_eth	STAKE	web3py	arbitrum	\N	\N	\N	50.0000	2000.0000	200	1.00	t	2026-03-25 19:38:12.114769+03	2026-03-25 19:38:12.114769+03
28	8	withdraw_eth	STAKE	web3py	base	\N	\N	\N	50.0000	2000.0000	200	1.00	t	2026-03-25 19:38:12.114769+03	2026-03-25 19:38:12.114769+03
29	8	withdraw_eth	STAKE	web3py	optimism	\N	\N	\N	50.0000	2000.0000	200	1.00	t	2026-03-25 19:38:12.114769+03	2026-03-25 19:38:12.114769+03
30	8	withdraw_eth	STAKE	web3py	polygon	\N	\N	\N	50.0000	2000.0000	200	1.00	t	2026-03-25 19:38:12.114769+03	2026-03-25 19:38:12.114769+03
31	8	withdraw_eth	STAKE	web3py	scroll	\N	\N	\N	50.0000	2000.0000	200	1.00	t	2026-03-25 19:38:12.114769+03	2026-03-25 19:38:12.114769+03
32	10	stake_eth	STAKE	web3py	arbitrum	\N	\N	\N	100.0000	5000.0000	150	1.00	t	2026-03-25 19:38:12.224807+03	2026-03-25 19:38:12.224807+03
33	10	stake_eth	STAKE	web3py	base	\N	\N	\N	100.0000	5000.0000	150	1.00	t	2026-03-25 19:38:12.224807+03	2026-03-25 19:38:12.224807+03
34	10	stake_eth	STAKE	web3py	optimism	\N	\N	\N	100.0000	5000.0000	150	1.00	t	2026-03-25 19:38:12.224807+03	2026-03-25 19:38:12.224807+03
35	10	stake_eth	STAKE	web3py	polygon	\N	\N	\N	100.0000	5000.0000	150	1.00	t	2026-03-25 19:38:12.224807+03	2026-03-25 19:38:12.224807+03
36	12	bridge_eth	BRIDGE	web3py	arbitrum	\N	\N	\N	50.0000	1000.0000	300	1.00	t	2026-03-25 19:38:12.75498+03	2026-03-25 19:38:12.75498+03
37	12	bridge_eth	BRIDGE	web3py	base	\N	\N	\N	50.0000	1000.0000	300	1.00	t	2026-03-25 19:38:12.75498+03	2026-03-25 19:38:12.75498+03
38	12	bridge_eth	BRIDGE	web3py	optimism	\N	\N	\N	50.0000	1000.0000	300	1.00	t	2026-03-25 19:38:12.75498+03	2026-03-25 19:38:12.75498+03
39	12	bridge_eth	BRIDGE	web3py	polygon	\N	\N	\N	50.0000	1000.0000	300	1.00	t	2026-03-25 19:38:12.75498+03	2026-03-25 19:38:12.75498+03
40	12	bridge_eth	BRIDGE	web3py	bsc	\N	\N	\N	50.0000	1000.0000	300	1.00	t	2026-03-25 19:38:12.75498+03	2026-03-25 19:38:12.75498+03
41	12	bridge_eth	BRIDGE	web3py	zksync	\N	\N	\N	50.0000	1000.0000	300	1.00	t	2026-03-25 19:38:12.75498+03	2026-03-25 19:38:12.75498+03
42	5	add_liquidity	LP	web3py	arbitrum	\N	\N	\N	100.0000	2000.0000	350	1.00	t	2026-03-25 19:38:12.984842+03	2026-03-25 19:38:12.984842+03
43	5	add_liquidity	LP	web3py	base	\N	\N	\N	100.0000	2000.0000	350	1.00	t	2026-03-25 19:38:12.984842+03	2026-03-25 19:38:12.984842+03
44	5	add_liquidity	LP	web3py	optimism	\N	\N	\N	100.0000	2000.0000	350	1.00	t	2026-03-25 19:38:12.984842+03	2026-03-25 19:38:12.984842+03
45	5	add_liquidity	LP	web3py	polygon	\N	\N	\N	100.0000	2000.0000	350	1.00	t	2026-03-25 19:38:12.984842+03	2026-03-25 19:38:12.984842+03
46	5	swap_stablecoins	SWAP	web3py	arbitrum	\N	\N	\N	50.0000	500.0000	150	1.00	t	2026-03-25 19:38:13.115177+03	2026-03-25 19:38:13.115177+03
47	5	swap_stablecoins	SWAP	web3py	base	\N	\N	\N	50.0000	500.0000	150	1.00	t	2026-03-25 19:38:13.115177+03	2026-03-25 19:38:13.115177+03
48	5	swap_stablecoins	SWAP	web3py	optimism	\N	\N	\N	50.0000	500.0000	150	1.00	t	2026-03-25 19:38:13.115177+03	2026-03-25 19:38:13.115177+03
49	5	swap_stablecoins	SWAP	web3py	polygon	\N	\N	\N	50.0000	500.0000	150	1.00	t	2026-03-25 19:38:13.115177+03	2026-03-25 19:38:13.115177+03
50	3	swap_eth_for_tokens	SWAP	web3py	bsc	\N	\N	\N	10.0000	500.0000	100	1.00	t	2026-03-25 19:38:13.24976+03	2026-03-25 19:38:13.24976+03
51	3	swap_eth_for_tokens	SWAP	web3py	arbitrum	\N	\N	\N	10.0000	500.0000	100	1.00	t	2026-03-25 19:38:13.24976+03	2026-03-25 19:38:13.24976+03
52	3	swap_eth_for_tokens	SWAP	web3py	base	\N	\N	\N	10.0000	500.0000	100	1.00	t	2026-03-25 19:38:13.24976+03	2026-03-25 19:38:13.24976+03
53	3	swap_eth_for_tokens	SWAP	web3py	optimism	\N	\N	\N	10.0000	500.0000	100	1.00	t	2026-03-25 19:38:13.24976+03	2026-03-25 19:38:13.24976+03
54	3	swap_eth_for_tokens	SWAP	web3py	polygon	\N	\N	\N	10.0000	500.0000	100	1.00	t	2026-03-25 19:38:13.24976+03	2026-03-25 19:38:13.24976+03
55	3	add_liquidity_eth	LP	web3py	bsc	\N	\N	\N	50.0000	1000.0000	200	1.00	t	2026-03-25 19:38:13.434728+03	2026-03-25 19:38:13.434728+03
56	3	add_liquidity_eth	LP	web3py	arbitrum	\N	\N	\N	50.0000	1000.0000	200	1.00	t	2026-03-25 19:38:13.434728+03	2026-03-25 19:38:13.434728+03
57	3	add_liquidity_eth	LP	web3py	base	\N	\N	\N	50.0000	1000.0000	200	1.00	t	2026-03-25 19:38:13.434728+03	2026-03-25 19:38:13.434728+03
58	3	add_liquidity_eth	LP	web3py	optimism	\N	\N	\N	50.0000	1000.0000	200	1.00	t	2026-03-25 19:38:13.434728+03	2026-03-25 19:38:13.434728+03
59	3	add_liquidity_eth	LP	web3py	polygon	\N	\N	\N	50.0000	1000.0000	200	1.00	t	2026-03-25 19:38:13.434728+03	2026-03-25 19:38:13.434728+03
60	4	aggregate_swap	SWAP	web3py	arbitrum	\N	\N	\N	20.0000	1000.0000	180	1.00	t	2026-03-25 19:38:13.585161+03	2026-03-25 19:38:13.585161+03
61	4	aggregate_swap	SWAP	web3py	base	\N	\N	\N	20.0000	1000.0000	180	1.00	t	2026-03-25 19:38:13.585161+03	2026-03-25 19:38:13.585161+03
62	4	aggregate_swap	SWAP	web3py	optimism	\N	\N	\N	20.0000	1000.0000	180	1.00	t	2026-03-25 19:38:13.585161+03	2026-03-25 19:38:13.585161+03
63	4	aggregate_swap	SWAP	web3py	polygon	\N	\N	\N	20.0000	1000.0000	180	1.00	t	2026-03-25 19:38:13.585161+03	2026-03-25 19:38:13.585161+03
64	4	aggregate_swap	SWAP	web3py	bsc	\N	\N	\N	20.0000	1000.0000	180	1.00	t	2026-03-25 19:38:13.585161+03	2026-03-25 19:38:13.585161+03
65	4	aggregate_swap	SWAP	web3py	zksync	\N	\N	\N	20.0000	1000.0000	180	1.00	t	2026-03-25 19:38:13.585161+03	2026-03-25 19:38:13.585161+03
66	9	supply_eth	STAKE	web3py	arbitrum	\N	\N	\N	50.0000	2000.0000	200	1.00	t	2026-03-25 19:38:13.70485+03	2026-03-25 19:38:13.70485+03
67	9	supply_eth	STAKE	web3py	base	\N	\N	\N	50.0000	2000.0000	200	1.00	t	2026-03-25 19:38:13.70485+03	2026-03-25 19:38:13.70485+03
68	9	supply_eth	STAKE	web3py	optimism	\N	\N	\N	50.0000	2000.0000	200	1.00	t	2026-03-25 19:38:13.70485+03	2026-03-25 19:38:13.70485+03
69	9	supply_eth	STAKE	web3py	polygon	\N	\N	\N	50.0000	2000.0000	200	1.00	t	2026-03-25 19:38:13.70485+03	2026-03-25 19:38:13.70485+03
70	2	swap_eth_for_tokens	SWAP	web3py	arbitrum	\N	\N	\N	10.0000	500.0000	150	1.00	t	2026-03-25 19:38:13.84462+03	2026-03-25 19:38:13.84462+03
71	2	swap_eth_for_tokens	SWAP	web3py	base	\N	\N	\N	10.0000	500.0000	150	1.00	t	2026-03-25 19:38:13.84462+03	2026-03-25 19:38:13.84462+03
72	2	swap_eth_for_tokens	SWAP	web3py	optimism	\N	\N	\N	10.0000	500.0000	150	1.00	t	2026-03-25 19:38:13.84462+03	2026-03-25 19:38:13.84462+03
73	2	swap_eth_for_tokens	SWAP	web3py	polygon	\N	\N	\N	10.0000	500.0000	150	1.00	t	2026-03-25 19:38:13.84462+03	2026-03-25 19:38:13.84462+03
74	2	swap_eth_for_tokens	SWAP	web3py	bsc	\N	\N	\N	10.0000	500.0000	150	1.00	t	2026-03-25 19:38:13.84462+03	2026-03-25 19:38:13.84462+03
75	2	add_liquidity_eth	LP	web3py	arbitrum	\N	\N	\N	50.0000	1000.0000	250	1.00	t	2026-03-25 19:38:13.965225+03	2026-03-25 19:38:13.965225+03
76	2	add_liquidity_eth	LP	web3py	base	\N	\N	\N	50.0000	1000.0000	250	1.00	t	2026-03-25 19:38:13.965225+03	2026-03-25 19:38:13.965225+03
77	2	add_liquidity_eth	LP	web3py	optimism	\N	\N	\N	50.0000	1000.0000	250	1.00	t	2026-03-25 19:38:13.965225+03	2026-03-25 19:38:13.965225+03
78	2	add_liquidity_eth	LP	web3py	polygon	\N	\N	\N	50.0000	1000.0000	250	1.00	t	2026-03-25 19:38:13.965225+03	2026-03-25 19:38:13.965225+03
79	2	add_liquidity_eth	LP	web3py	bsc	\N	\N	\N	50.0000	1000.0000	250	1.00	t	2026-03-25 19:38:13.965225+03	2026-03-25 19:38:13.965225+03
80	15	mint_nft	NFT_MINT	openclaw	arbitrum	\N	\N	\N	10.0000	200.0000	100	1.00	t	2026-03-25 19:38:14.105557+03	2026-03-25 19:38:14.105557+03
81	15	mint_nft	NFT_MINT	openclaw	base	\N	\N	\N	10.0000	200.0000	100	1.00	t	2026-03-25 19:38:14.105557+03	2026-03-25 19:38:14.105557+03
82	15	mint_nft	NFT_MINT	openclaw	optimism	\N	\N	\N	10.0000	200.0000	100	1.00	t	2026-03-25 19:38:14.105557+03	2026-03-25 19:38:14.105557+03
83	15	mint_nft	NFT_MINT	openclaw	polygon	\N	\N	\N	10.0000	200.0000	100	1.00	t	2026-03-25 19:38:14.105557+03	2026-03-25 19:38:14.105557+03
84	17	vote_on_proposal	SNAPSHOT_VOTE	openclaw	arbitrum	\N	\N	\N	0.0000	0.0000	0	1.00	t	2026-03-25 19:38:14.224918+03	2026-03-25 19:38:14.224918+03
85	17	vote_on_proposal	SNAPSHOT_VOTE	openclaw	base	\N	\N	\N	0.0000	0.0000	0	1.00	t	2026-03-25 19:38:14.224918+03	2026-03-25 19:38:14.224918+03
86	17	vote_on_proposal	SNAPSHOT_VOTE	openclaw	optimism	\N	\N	\N	0.0000	0.0000	0	1.00	t	2026-03-25 19:38:14.224918+03	2026-03-25 19:38:14.224918+03
87	17	vote_on_proposal	SNAPSHOT_VOTE	openclaw	polygon	\N	\N	\N	0.0000	0.0000	0	1.00	t	2026-03-25 19:38:14.224918+03	2026-03-25 19:38:14.224918+03
88	18	register_ens	ENS_REGISTER	openclaw	arbitrum	\N	\N	\N	5.0000	50.0000	0	1.00	t	2026-03-25 19:38:14.344836+03	2026-03-25 19:38:14.344836+03
89	18	register_ens	ENS_REGISTER	openclaw	base	\N	\N	\N	5.0000	50.0000	0	1.00	t	2026-03-25 19:38:14.344836+03	2026-03-25 19:38:14.344836+03
90	18	register_ens	ENS_REGISTER	openclaw	optimism	\N	\N	\N	5.0000	50.0000	0	1.00	t	2026-03-25 19:38:14.344836+03	2026-03-25 19:38:14.344836+03
91	18	register_ens	ENS_REGISTER	openclaw	polygon	\N	\N	\N	5.0000	50.0000	0	1.00	t	2026-03-25 19:38:14.344836+03	2026-03-25 19:38:14.344836+03
92	19	swap_eth_for_tokens	SWAP	web3py	manta	\N	\N	\N	10.0000	500.0000	100	1.00	t	2026-03-25 19:38:14.465353+03	2026-03-25 19:38:14.465353+03
93	19	add_liquidity_eth	LP	web3py	manta	\N	\N	\N	50.0000	1000.0000	200	1.00	t	2026-03-25 19:38:14.599919+03	2026-03-25 19:38:14.599919+03
94	20	swap_eth_for_tokens	SWAP	web3py	mantle	\N	\N	\N	10.0000	500.0000	50	1.00	t	2026-03-25 19:38:14.744968+03	2026-03-25 19:38:14.744968+03
95	20	stake_mantle	STAKE	web3py	mantle	\N	\N	\N	50.0000	1000.0000	100	1.00	t	2026-03-25 19:38:14.864848+03	2026-03-25 19:38:14.864848+03
96	21	swap_eth_for_tokens	SWAP	web3py	linea	\N	\N	\N	10.0000	500.0000	100	1.00	t	2026-03-25 19:38:14.984923+03	2026-03-25 19:38:14.984923+03
97	21	add_liquidity_eth	LP	web3py	linea	\N	\N	\N	50.0000	1000.0000	200	1.00	t	2026-03-25 19:38:15.104975+03	2026-03-25 19:38:15.104975+03
98	22	swap_eth_for_tokens	SWAP	web3py	scroll	\N	\N	\N	10.0000	500.0000	100	1.00	t	2026-03-25 19:38:15.329776+03	2026-03-25 19:38:15.329776+03
99	22	bridge_eth	BRIDGE	web3py	scroll	\N	\N	\N	50.0000	1000.0000	200	1.00	t	2026-03-25 19:38:15.545327+03	2026-03-25 19:38:15.545327+03
100	24	swap_eth_for_tokens	SWAP	web3py	zksync	\N	\N	\N	10.0000	500.0000	50	1.00	t	2026-03-25 19:38:15.809894+03	2026-03-25 19:38:15.809894+03
101	24	add_liquidity_eth	LP	web3py	zksync	\N	\N	\N	50.0000	1000.0000	150	1.00	t	2026-03-25 19:38:15.959837+03	2026-03-25 19:38:15.959837+03
102	25	swap_eth_for_tokens	SWAP	web3py	unichain	\N	\N	\N	10.0000	500.0000	50	1.00	t	2026-03-25 19:38:16.11481+03	2026-03-25 19:38:16.11481+03
103	25	add_liquidity_eth	LP	web3py	unichain	\N	\N	\N	50.0000	1000.0000	150	1.00	t	2026-03-25 19:38:16.24+03	2026-03-25 19:38:16.24+03
104	23	swap_eth_for_tokens	SWAP	web3py	morph	\N	\N	\N	10.0000	500.0000	100	1.00	t	2026-03-25 19:38:16.385359+03	2026-03-25 19:38:16.385359+03
\.


--
-- Data for Name: protocol_contracts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.protocol_contracts (id, protocol_id, chain, contract_type, address, abi_json, is_verified, created_at) FROM stdin;
\.


--
-- Data for Name: protocol_research_pending; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.protocol_research_pending (id, name, category, chains, website_url, twitter_url, discord_url, airdrop_score, has_points_program, points_program_url, has_token, current_tvl_usd, tvl_change_30d_pct, launch_date, recommended_actions, reasoning, raw_llm_response, status, approved_by, approved_at, rejected_reason, rejected_at, discovered_from, source_article_url, source_article_title, source_published_at, created_at, updated_at, bridge_required, bridge_from_network, bridge_provider, bridge_cost_usd, bridge_time_minutes, bridge_safety_score, bridge_available, bridge_checked_at, cex_support_found, bridge_unreachable_reason, bridge_recheck_after, bridge_recheck_count, cex_support, risk_tags, risk_level, requires_manual) FROM stdin;
1	TestProtocol (Sample)	DEX	{base,arbitrum}	https://testprotocol.xyz	https://twitter.com/testprotocol	\N	85	t	https://testprotocol.xyz/points	f	25000000.00	120.50	\N	["SWAP", "LP"]	TestProtocol raised $50M Series A led by a16z. Active points program similar to Blast. No token launched yet.	\N	pending_approval	\N	\N	\N	\N	manual_testing	\N	TestProtocol Raises $50M in Series A Funding	\N	2026-02-25 17:37:45.480676+03	2026-03-06 10:13:21.275776+03	f	Arbitrum	\N	\N	\N	\N	t	2026-03-06 10:13:21.275776+03	\N	\N	\N	0	bybit	\N	LOW	f
2	InkDeFi (Bridge Required Sample)	DEX	{ink}	\N	\N	\N	90	t	\N	f	\N	\N	\N	["SWAP", "LP"]	New DEX on Ink chain with points program. Requires bridge from Arbitrum.	\N	pending_approval	\N	\N	\N	\N	manual_testing	\N	InkDeFi Launches on Ink Network	\N	2026-03-06 10:13:21.29006+03	2026-03-06 10:13:21.29006+03	t	Arbitrum	across	2.50	\N	95	t	2026-03-06 10:13:21.29006+03	\N	\N	\N	0	\N	\N	LOW	f
3	FutureChain Protocol (Unreachable Sample)	Lending	{unknown_chain_xyz}	\N	\N	\N	95	t	\N	f	\N	\N	\N	["STAKE", "LP"]	High potential protocol but on unsupported chain. Will recheck weekly.	\N	pending_approval	\N	\N	\N	\N	manual_testing	\N	FutureChain Raises $100M	\N	2026-03-06 10:13:21.293181+03	2026-03-06 10:13:21.293181+03	t	Arbitrum	\N	\N	\N	\N	f	2026-03-06 10:13:21.293181+03	\N	No bridge route found via Socket/Across/Relay. No CEX support.	2026-03-13 10:13:21.293181+03	0	\N	\N	LOW	f
\.


--
-- Data for Name: protocol_research_reports; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.protocol_research_reports (id, run_date, protocols_discovered, protocols_updated, llm_model, execution_time_seconds, report_summary, created_at) FROM stdin;
\.


--
-- Data for Name: protocols; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.protocols (id, name, category, chains, has_points_program, points_program_url, airdrop_announced, airdrop_snapshot_date, priority_score, is_active, last_researched_at, created_at, updated_at, bridge_required, bridge_from_network, bridge_provider, bridge_cost_usd, cex_support, risk_tags, risk_level, requires_manual) FROM stdin;
1	Uniswap	DEX	{arbitrum,base,optimism,polygon,bsc,zksync,unichain}	t	\N	f	\N	95	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
2	SushiSwap	DEX	{arbitrum,base,optimism,polygon,bsc}	t	\N	f	\N	80	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
3	PancakeSwap	DEX	{bsc,arbitrum,base,optimism,polygon}	t	\N	f	\N	85	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
4	1inch	DEX	{arbitrum,base,optimism,polygon,bsc,zksync}	f	\N	f	\N	75	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
5	Curve	DEX	{arbitrum,base,optimism,polygon}	t	\N	f	\N	90	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
6	Balancer	DEX	{arbitrum,base,optimism,polygon}	t	\N	f	\N	80	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
7	Jupiter	DEX	{arbitrum,base,optimism}	t	\N	f	\N	85	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
8	Aave	Lending	{arbitrum,base,optimism,polygon,scroll}	t	\N	f	\N	95	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
9	Compound	Lending	{arbitrum,base,optimism,polygon}	t	\N	f	\N	85	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
10	Lido	Staking	{arbitrum,base,optimism,polygon}	t	\N	f	\N	90	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
11	RocketPool	Staking	{arbitrum,base,optimism}	t	\N	f	\N	80	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
12	Stargate	Bridge	{arbitrum,base,optimism,polygon,bsc,zksync}	t	\N	f	\N	85	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
13	LayerZero	Bridge	{arbitrum,base,optimism,polygon,bsc}	t	\N	f	\N	90	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
14	Hop	Bridge	{arbitrum,base,optimism,polygon}	f	\N	f	\N	70	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
15	OpenSea	NFT Marketplace	{arbitrum,base,optimism,polygon}	f	\N	f	\N	60	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
16	Blur	NFT Marketplace	{arbitrum,base,optimism,polygon}	t	\N	f	\N	75	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
17	Snapshot	Governance	{arbitrum,base,optimism,polygon}	f	\N	f	\N	70	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
18	ENS	Governance	{arbitrum,base,optimism,polygon}	t	\N	f	\N	80	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
19	Manta	DEX	{manta}	t	\N	f	\N	90	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
20	Mantle	DEX	{mantle}	t	\N	f	\N	85	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
21	Linea	DEX	{linea}	t	\N	f	\N	85	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
22	Scroll	DEX	{scroll}	t	\N	f	\N	85	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
23	Morph	DEX	{morph}	t	\N	f	\N	80	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
24	zkSync	DEX	{zksync}	t	\N	f	\N	90	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
25	Unichain	DEX	{unichain}	t	\N	f	\N	95	t	\N	2026-03-25 19:38:11.275111+03	2026-03-25 19:39:54.635517+03	f	\N	\N	\N	\N	\N	LOW	f
\.


--
-- Data for Name: proxy_pool; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.proxy_pool (id, ip_address, port, protocol, username, password, country_code, provider, session_id, is_active, last_used_at, created_at, timezone, utc_offset, validation_status, last_validated_at, validation_error, response_time_ms, detected_ip, detected_country) FROM stdin;
459	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_nzzPexWTEkP1WzyseGZy1daBGXMzHEuM3kqOtL3XxyEIvSRQmycTfAfK7Zp3vqpEUUSR8FwxUWDx7XykMuCTZ7QUco1D6iRxYPJtjNj6KTPIk=	CA	decodo	20014	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
460	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_nzIT9pnwtSV9xRArk7Kn8O5G6EdqVBRB_AbCQ_QNq6Q8rhEpbTjAa9dl27qnWdNI6faGYxSQx73OLosHCsOLPBn20DhgEXmxS_LD4fGrO7ZqY=	CA	decodo	20015	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
461	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_n0GaBVADf5w_BcBK4Q57n4KX6llsmfSUJioE-orC9cKbsYt53itmQ9HxE7hTaeqBHHndcFWoJX0kXkHaoC0cfdYZJOcU01W4Y8rgosS_Tva0o=	CA	decodo	20016	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
7	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n1WXrVuE6n8w6tmSW5iYyUH-6u9D1zzEUo45SidH24eTMhEDBS7pjhKWx3W5dP2Sj8diIEQgH0GOWrIYDjBbTKANEREN78ANRoZgHuSMCumfTpKP5lYA-2sFKRiljd4ZqTHJ6GnK7LoPIGzu4ok8scHjOL4PkbO30NbEDRkafM9q4=	NL	iproyal	YnsOtKwE	t	2026-03-23 16:05:24.846688+03	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
8	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n1N3rRJ90do5t5_cl33ZUjzHGAf2PRJHUY3ylh2IGnpn-Qd0XQRf0rENFdXAgyYBkx9QvQi8iD5-E6fYrGlMevHp8MHb5N-FY01DguewLXbEJMh15w8UZxRb_d6nxdbrmhutrQ0HEqPww4i97aYFMXL1pUpJr76h3xtxWE-fGuiOY=	NL	iproyal	lrqZei2H	t	2026-03-23 16:05:45.032911+03	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
10	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n2NJOd0CtstC22Sjzd8Wkg3sw0niCU9T-TzKYn_ZyOI4BB926SFUhZqsJdRCCuzNiKI8hmndGtynWm4ykg11n-dm84FFBoCxYdKFENEqEQiifYafR5XZ3bcrJ90BndLaaxaG1ozo8QZ0FeaaBL9F_i4owsxt8kb5QGaixK2qDpwg0=	NL	iproyal	mwvLCxZE	t	2026-03-23 16:07:44.237109+03	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
23	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n4rCgksB6Vx_B8qinmGZOqFqqrp1oI43FPaGKghn2NA9sXx7G5kSClryzKvhYm5jj7xPS6jEdJlQJeqD1bBnu44YUfdOeZB9tiM2x5DzT-CxNSfjh7mdjCgq21ZRKl6xCUnpJTxkx7GRulE3AWele-Xg40GLv2gWANsVzLJWXhDkg=	NL	iproyal	C6nkwlac	t	2026-03-28 20:17:07.105783+03	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	invalid	2026-03-28 20:17:07.102689+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 1).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
464	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_n3uj2cwa0oMHFLdvRhJJiJEH_W6rYCHlGmNq1Xs_nDczB7sI14g5gN9Ka65AYaT4YERAZVhpknKuOxsw77vOU5dYgFYZuZzyu0KVuqDT8jCHA=	CA	decodo	20019	t	2026-03-28 20:17:10.173115+03	2026-02-28 11:35:32.1962+03	America/Toronto	-5	invalid	2026-03-28 20:17:10.170815+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
12	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n2D74lMSgKcH4VMcD2wQ4oacyJm7wTZfDo_pAKCWVnnA4358sqHEbSHeJAFSY_JZu03jonZjJlWSUR6gbUdgxqbHXjYwzvkVWME7q9XSNyhFkPZ23OAYHd2d0XAfnW0xjevRVQ1lmS9lfdEg6aG2vXFIJhU_WGgFxNjO3x2W4wl_Y=	NL	iproyal	6ibrwE6R	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
13	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n2FslzUGhUDbhwdwSfVnmPlY04_xOhlvs_Mezn40fTmLUHPVb2EqHkklmqpsk8XHZMCMbRS0UKx0G3jxKkHH-jru0ZoDOjfnWO4_zNNECx5wZAPL3V15nwP7CHd1MylisZxtOFFXBylGSz4Ye4NWAhhJx7h1kVKENuUhvGnc-LHp0=	NL	iproyal	9CP1Ylge	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
14	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n2O8jCpQ-DrlPgZxNh8By4AYB5jusW7Kwd0RLNQP-F-ew6Cj94CfmTSOIopfx_HP-nK-xXRMwaBhfeNIaFAn0NLLxLIRuSs_t1WaKVAITXetdJ7ekhJMWuyjX2W6IHUzoyFJmLLABswb7JdHZL1ZZfITMfbJmcvRqvsvh-L7QoSSA=	NL	iproyal	kL6SaDrV	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
15	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n2lGxboCnf6L3XcneqOXRXqonXU7ztsnxSDFQfmhwvstO3U3sFH9yuL9Vs23D6hfd3zmtMbmk4O7I-TJESwqdACq9qWRcZKeckboA9tsI8KFHl3cehGsrmprv3n7tjSvVf9C0OvGMkpc4KFbOju8a2WPmMHQYqdT6nGm6IiXcnKi8=	NL	iproyal	8rol4yn7	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
16	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n29KeS4TgGDSulINEF5wuBnzGewAXYYtm6ILOl9fHdUwKTXfF68uKxYs2DYOap52upddXZikGpAZ7aQRyW9K03BTpm-JpJxaxs_v_3lFCdWI5n08vfS6Le5qTFORLM2pZbyVmp6gbOl_e0R9k4DWYxyYIBAIdfw6NZu1RExprPl2w=	NL	iproyal	T7EuEg5N	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
462	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_n3uFO46OEN1kml_dkyOknqqzVp5Yl6sYbn5UBCbPfA3zOVqpKqz7NFuNln8SpViKt0noJAToJ1WGIDK-49vsVaaZxTR1nPoUbO-JZC7j0IPCE=	CA	decodo	20017	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
463	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_n3M8HoEWbxgJHu4ELo8FcV37yRpmvMX2wEiVWD1L6UEF4h6WNCiVwELaWXUicFeH5LqMG-hfEA5_EvGp7h7h1BZ9QLc46w7LNMVoSKK1qIQgA=	CA	decodo	20018	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
465	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_n3ba-z6gB590EwcrLjTqviTeiUI8YjyfwScDdZzGb41epJoeF6PaRN8KSXWmatCEZffD8lENwTWcagKfYxPJZljaEfTi2LMkMYFsXZIY12PS8=	CA	decodo	20020	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
466	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_n3Gvf-ybuVmiqY4kJC01QDbEWZnjR0j7Cth5F8YJC3-OyYWxLk1GuzCz4y2h9UWSoDWswvDwkmmC5LFfGTBDTevbsIZtjFNx1RxZikdbcCNuM=	CA	decodo	20021	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
9	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n2fe6gr1UnFTCT7N2sj2JkZ3HoIg-ianCwxuKBeqhZLrEQgpHv4sHkRJi11b2hqlJjZKa1KFKgKTVCZoPFnNlZ5oradKNuQ-DSVBtWNfsu0WXC_cQyjvNhnJjx27M_cTyF-z2pfD0mukBg9NV7_YaUAjzOHHP53whK4AeJdRxEAoU=	NL	iproyal	icCPTLWE	t	2026-03-28 20:17:13.312704+03	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	invalid	2026-03-28 20:17:13.311012+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 1).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
17	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n2dtZulAVKUY_7wnfRgfH7EobgEkMg0gYbpaIzmoT2qMvUpGWh-T84usQHOa6zQ7ZmRmzYHTwjVgwIO8BaWKTXlgnjI5wzuRsdEi5iI_hmRVt76WjPVYBkXbj6NoOd7HJJEVdNhwqDRDhGMwbA0AZ9Q5vXvIAToaHvznofTNE_kOA=	NL	iproyal	tbhSEU0W	t	2026-03-28 20:17:13.348997+03	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	invalid	2026-03-28 20:17:13.346522+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 1).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
60	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-15-sessionduration-60-country-is	gAAAAABpt_oHaZxeyxeIyddbQuVB-UI55nXm5DqCGFiSTTItOWd209gv3BNjh8yy7p72k4oLr72RUgtFIHKQLc0ee1kLL2P_wOqOnJen-SATJ7wz5z-D8Dc=	IS	decodo	15	t	2026-03-28 20:17:16.427296+03	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	invalid	2026-03-28 20:17:16.424767+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
46	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-1-sessionduration-60-country-is	gAAAAABpt_nsh7ZL_LE2G5BWWA1OByzlyuLXO2dV86J65vQWv04UIefxEwJhYUJ9mKak1MMRtawJ9C7d0kVlK03QoWHJ02j3XMEYv3qelYbYel2TrcyLWoo=	IS	decodo	1	t	2026-03-28 20:17:47.198895+03	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	invalid	2026-03-28 20:17:47.196626+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
47	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-2-sessionduration-60-country-is	gAAAAABpt_nsn86a69TEPEhgE4OMC1H9o3OwTkg_5Zt5BguGe11i12XuLXAT2rY-6JTLe9ZgrFDyObeKsswHR0TxoqkJUkL-NdhY0LNEnA8vh62iBjw50xw=	IS	decodo	2	t	2026-03-28 20:18:02.573617+03	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	invalid	2026-03-28 20:18:02.570338+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
470	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_n4ANMNHrijQN7lon_aGKHMncWoMxnG-OeJb5tz61J9v9xN0Nr3Xjm1rh-KLl5KZxZOK_eO4D6gx4KhuOhbd5DJUB1lNrqqMCwo7lLH4J5YF4c=	CA	decodo	20025	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
471	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_n4c3GlocjnGN_DqwP2X26biOw0zzkj0VTihCR1Wo_dE46iFCTeJkmv_cJ9ox1Nw8BGZiL2tCk3jbKOoNtX4Lum1m6Sd_qvOz7gExlRNjcg_vA=	CA	decodo	20026	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
472	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_n4H_bs_ANDK3JSnQfttEJxw4MkCiyZLyrn-a2022jowfB6ubovMqf1DrgXVS0LdELDxS-SF1v_P2qUxgozTE3q-B9jybrgNHjfpooWuBAPhdk=	CA	decodo	20027	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
18	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n4zh69xaBahDHH2iN85viiQsfGz06BFiAC1gUfsC4lKkHKuvNDLO1P-0v19XIuDtpxwGU50-pLO8O_VJublc5Xrse7yTiSXnNFOylTNtSxPRsKbCn2DT-h-52CdcWAI2JoJ_NFYrMCwz0ywMvia8uI22nSmpwdw5dbsiHNSzJaPwo=	NL	iproyal	J52x3XZz	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
20	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n4APaCJMBSO-pW3TD8Is1Cm6Ho-91YEg3n8Q3-JjTLovx0INOvwRxcylew5rqzrdTWL-LSfbakOQ7c-9cai5qEk8wUoz4ZhlmyGX33vghOc60TUAJqyJND5iFuMvT13OxQY0e83ruKDVBGFPChC8dcogHRmCdE_tI1Pnr92Bk7G9g=	NL	iproyal	mQ1LnRTj	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
21	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n4xmRQOe2mnp8reyuCF5kjmAqcfKwHW0ZWu8cJSDoAcnM7YxIcDxygjP0LH_uMkMCemV2AU8YMVa5R3Hiny6QMx7Nw8Xghc3Ere9-2pRznq84pXA1wioQJuFGjAQrfLO9L8m_YSidaFu3GOJynT52xd2H18Sbnrd9laWBkG7oSAWo=	NL	iproyal	1kAEFwMO	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
22	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n4FWtDuXMuO8HJ_4Yk1AG-paXMZ0uv1kh9XmIz3emgYOhOi9feAGWYqTKD_LkOb5UcMn5WehyZ6lshLIw9USYZcxYzNFZBc0aBlZzD6caQMqdJY9ube8H343noXSA5vPRn_5jZaJZoApNhChf3sCAjWVdsJkyMGPY4jiq-6MWr1_I=	NL	iproyal	u8sd6WHp	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
24	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n5bspvix1v6zD7mR7H1x-FGeVPIq57AT3hSc0tNYzVClgKXbeNfGrQGold5XmSWC_bu42V6cUk94x8mqGYGugCRx0AEXMBNcGEXXwvJ3h_dIrNUCA4N0KdQDgRWLjVq6SMMFaFhjnkvREVTHlkUnyFjcXzejpR2-GcYtkI6Xx8Jds=	NL	iproyal	UVYJdRBX	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
25	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n5UXcip9r35t99tOn8UQCkJ4LxUFvR7AWH2mDGnIR0f8-XME06WgiBix81fMW7Jai-OdcPYKp9knoLp3ZaCdpCxh3pWAxhBq6O9dNo0lr61tlrNT5R5aka44NmJWji-WWF7sZlHDyyX5OuSsPw6mvYHGECFyENiIxl4Ws_noT7FX8=	NL	iproyal	P57uAsCn	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
26	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n5XN9Gcd5b4I1TKkiiOBtRmE4SuXTUYdwAU6noXLEHCgsSYBb3IwtuY55r3tfsAvvNFDM29UlK4jZMwBRjgpTp6REPsYcntByUm-2U0Krvu1tdWro22f_DfcuPKHzPrp1206M6AoWqx5vMuW85viuhj0ce_e2Ue9ehlAtjQpMXdR4=	NL	iproyal	Exda9hy6	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
27	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n5ooQtiyb1lj5ElP5nNlpr7qj-2HWU3FfIpIF7bGl4ZIODV4crZvdbmsJYmz-HAN0G5J7tCjtvZoQiI1_uErETlLaZuIsoySkfOeM45h1GW8jli-6mo4SNta9ZX0Wxk66JDQwdFyoCaZ9uAPkE7UzbYS4VJrmorwlerkxYSRInQ4I=	NL	iproyal	klDUCj90	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
29	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n5fWIgJcLINzunANEmFxrTTs0cxp-OwRFLrl-SvyCIkfhM96y6Qc-hZENUx8-ikOct1_PjJtwbGNVEUOhKERAax_O4LhEHyJBqqBZK2Yt-6qKDXqRXS8Yix97XoGeWSH97TTPdRxL11jDUt2jXzinOcU3GXNPduAy7Ibfrtt-Kjyk=	NL	iproyal	AqWzhesr	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
30	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n5uA4AcF-CjBHnqYtZETi1Z3qSDW-7QauhsuZ_k6NuZ5tmPp6LUgt92tmyKhPZdz6NnO0Te2h7Oxm7guAfhcslOZKSrKik0aEMVbc4Kd5URoWU0yHBGyArXhQ7prk0bupXRcxEmn0H4jVF1ef3_oUN6JvsrSfwyMJRfByG08oCzms=	NL	iproyal	jGtrJJeQ	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
31	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n5ih5nHZah7QVtK2loSv25RpmWzJB1fxTguRGNHGzU1fc4WCuJcrkSclwQDOPMUNDFA48FsELFdfOGucwG5z9SkhDPjj2km-ExmJRXWNv7mMZTBOAEAlz67df9UAdja_yLN1U_c_xH46vbUrN6GZV-H-jFwNI5fEhIHC7leb16k0w=	NL	iproyal	Z1Iese6k	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
32	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n56EYaSgXeqF0L0SKhT856EGAr2tZmPfTrYnEDty6el8mnWEAPlxHBOlh8Zf5TEr9xHqN6jDa_RKLJD9jI-DxssyTQOpVjPS-i5QrJ1H7YP08Xp0i-OOaDlOrVVO1euXjX5M54sxGxZJuSQB-QloRkOsVzGBuN6439JMmUbaIrgT0=	NL	iproyal	JXcok1js	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
33	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n6YJNv1DqXKN3FqFkhpVqx87YbBwPUyPpFKuWUlasb_q5ijvbPxjwed7efpmaPZRyN-xk-TUgjBNotgPxKECLW7w-wAIhI0qBgZ7YIvY6efFk_OtUGZrkAOnDZ9Z66vQd-med1wOikEFYtDXTErw25_CxMVnG5mERZ18aLNsVz_nY=	NL	iproyal	Tw2GLgsQ	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
19	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n4nzMVUJSOYnSrlhN0wUOy9MF-a6vMiCQGx0jkHpuLfb-YiAF0xkK4OHg7M_9ohZH3kh6J2huf8ot3Jvh2rdW5LQ3QEX9N79thR97JtdkwuLED1Sy4wZi8BoT3-SpEPE2zlBiPSKWO4gVJHSCrnIfvF_1IC3Nw5BVsF8a8e6EQvv0=	NL	iproyal	pCXycFjm	t	2026-03-28 20:17:28.735371+03	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	invalid	2026-03-28 20:17:28.733209+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 1).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
467	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_n33HFHlayEI4NqpfyJBkBm1J0sS0-mPVkEcMiojHpJj4nKsjQrYDuzc_eF8A5LtUepE_lIkqXBA3Sr59ijnXvo-8jgUMZE5uwTSc1HZgJpKDU=	CA	decodo	20022	t	2026-03-28 20:17:34.865686+03	2026-02-28 11:35:32.1962+03	America/Toronto	-5	invalid	2026-03-28 20:17:34.860115+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
28	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n5ZWR6oJdLZhXYvanE9Zq42hVMuPTNJ4lnLMgvUAqQFifCTxtf7bohEY8l80WAKMDFe3CtwPt7i85JPqaT-nzaG1Qcnr-UblSU5_cXVDEU2kCKObhpag4fIG3Lg6T-X9MerWYbhXSdYL-8QmFJKPvILqXLOP1q_5OhQ5Fkm05YTuU=	NL	iproyal	XvO9tRf0	t	2026-03-28 20:17:59.487746+03	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	invalid	2026-03-28 20:17:59.486+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 1).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
94	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-49-sessionduration-60-country-is	gAAAAABpt_nsffoVrO8e7ElBCTQkjuy-gzTidAyboEcvqfxYS021NBM91Zs6TW0vLDu9yaLeRG4nO5UUz8E_bzxFh9UihLLKDpecfZ-jOHNxmTtNe0I6kKs=	IS	decodo	session-49	t	\N	2026-02-24 12:08:32.309329+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
95	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-50-sessionduration-60-country-is	gAAAAABpt_nsiCO3FdIGyvUdFI-MCURZyGuFBEQl_4OJXRWtiJkPlZxVmX0iXxcTEuVc8o8y6jkMGht8x_NToiYmwToxr7IyyAtrT3uCppTmcvJg8FtkQys=	IS	decodo	session-50	t	\N	2026-02-24 12:08:32.309329+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
96	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-51-sessionduration-60-country-is	gAAAAABpt_nsWR01NvFLk1PpvfAwLqC1Ny_5aSr6TjdP-pTXyhSYkwZtuIxx8lgOdJ0OsSE63FVyK4GCK9BjTKoe4HZ5j90FttiluyaglJax0UW3BtbXrIU=	IS	decodo	session-51	t	\N	2026-02-24 12:08:32.309329+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
97	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-52-sessionduration-60-country-is	gAAAAABpt_ntWRC_4D4a4gWUvORoNt9neUca8_WRvx4bQXnapAugxgZx_mx6G8QDSvUzGwIV2zGm6ZpdyUZzxY4EBT1i5yNn6ab_ayodtrlxKVlM5wUVn9g=	IS	decodo	session-52	t	\N	2026-02-24 12:08:32.309329+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
98	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-53-sessionduration-60-country-is	gAAAAABpt_nt0yb-kZf9kVrc0yKrR8kubCNvQzqdy8owoO6FLgoFru00QM-31XTzZwWrkBJNbOTLMskzCjwJe_yia5kz10nS_D4_9E1nLfFxwmHWlz2wg74=	IS	decodo	session-53	t	\N	2026-02-24 12:08:32.309329+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
99	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-54-sessionduration-60-country-is	gAAAAABpt_nt6ctZ1Y7SOgvRG4QwgajjR27Dn7lau6qbbFkw28fjs1RTzVs-IhfJMjNAvMFFShJGVCEmYnw_8f0gqcoOeDiRbrpWCWsKX3mWiPtWTwUJcWk=	IS	decodo	session-54	t	\N	2026-02-24 12:08:32.309329+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
100	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-55-sessionduration-60-country-is	gAAAAABpt_ntKn7oyvdTawLotqqtikTx6QlmcHoWg2yAfjvAree3jmpEIRrE4Vv4r6tmlxzxC50HYh7nRIwz_wxJEXw9dQMyrevlA5jMnZ4WQyxpAqk7imU=	IS	decodo	session-55	t	\N	2026-02-24 12:08:32.309329+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
101	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-56-sessionduration-60-country-is	gAAAAABpt_nt7C6wE6M4SdOh5ATTrlkQBUwDt5aTKQOC11G_OfA9lY_lPjOWwleN9OjpG5tCJsX9OLHR6GfI-T9YMDzlG2pMA1ETvvPyEsJTu6XVhOzsVks=	IS	decodo	session-56	t	\N	2026-02-24 12:08:32.309329+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
102	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-57-sessionduration-60-country-is	gAAAAABpt_ntwkUCvaA8H_EaRwICw1u_tFC6wgapggle8kgaklGiZzIQqbxfrlUBl-52xc3V9S9KXIjL0bKcgQyf1L7T8jguLhEWOtizbLXNQb4ZbHjSkXg=	IS	decodo	session-57	t	\N	2026-02-24 12:08:32.309329+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
104	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-59-sessionduration-60-country-is	gAAAAABpt_ntWRhLluAp70E8l_xJOwn6EaRYYyi04tithuvR2XoKMISBIC7lYXPJ6_bCxhTSNCqj5PWsRmXGdOJ9A6P1puH4ksq5Jgo7wRGHRpiE1IpXz_4=	IS	decodo	session-59	t	\N	2026-02-24 12:08:32.309329+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
105	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-60-sessionduration-60-country-is	gAAAAABpt_ntNabERNL5tyyt_zjFu2dIwO5PMX8vCpDV_pDwRMGZ-o3XGty-_3E670_PeMM0far4cfEejyHD3-NBG4w7kFJkdScG3ke_PEhh1lwF_CI1okU=	IS	decodo	session-60	t	\N	2026-02-24 12:08:32.309329+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
34	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n6XkQdL8d6mqd_nWpXo6vfDo_Mff2fGfxE0AlINzcZFeS_XZOL8GVtjYorIgaGJa_RB5Hj4eBzWYwcSQQAJ_WsnZq8iN2oeTwS-c99kJKGIijaRBW5IntLMub0gYf_WgjUL4Mj1jNcHVpOBdSVGeH3FQ99Jvn2OsjyZk8qtbPcVwQ=	NL	iproyal	qewxLlIX	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
35	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n6qJZAxCkQUdnDk_A4IsIOENdYpwnE8GQJPFZTRS1JcbLWE1C3Rp1u9eTCmjN5LOEmeZZSrBu6TFYssVhyqtQi1bVXEBMm3_b2bKOxkJnyrEGb2vxfzY2afJ16pRDbpFXJbcDPvsyN1XVYEY4_eGvkEi4XYz3iN3akAQQRV1aqbfQ=	NL	iproyal	KkTVaIHj	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
36	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n6nrzEYPInPZn7Eu6l5DRPwyw1hQvQp2XFqTEcfX3Ohy5GFgy9gEnlQ1aCHXDj3qJ7N2vjsFJW0n3-lWn55WAJqP3wBzc7LPiVvTu9eo9riW3TfLMIf1sw1Cvz0tRmDTDH-SuFLYcYpl54pJHwVfphwphN0koxMYpq59hxzxC7ez8=	NL	iproyal	9VbsPbUp	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
37	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n6cbCo9oKANGr3AXe4KBcHatGxMI3ZiwkzzpRnvJSsP-_IBIKN_rXYzneKzeFEgppY_maIc4kjlQV9s5ba3ar33IJMaShUiUml6E2xG_2wneBRTC2_P_RbJaftgoSQKTcCLDyP14ap386Hx-ZTu0Yxc_XDk0uDTCyDA9B17uvIu3A=	NL	iproyal	aEutCNks	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
103	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-58-sessionduration-60-country-is	gAAAAABpt_ntCFqX8YRacAbf1j4wGld88dUmMgZAa9691W4_WhhUR9vJV2O1NFcWbgWJaXQnfZI1GkYi-gYLk3gJxWGIjkP_ESbslYslqlk4ML56Mq-hktk=	IS	decodo	session-58	t	2026-03-28 20:17:13.237406+03	2026-02-24 12:08:32.309329+03	Atlantic/Reykjavik	0	invalid	2026-03-28 20:17:13.23555+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
93	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-48-sessionduration-60-country-is	gAAAAABpt_nsxTVpGDCF3m2LwfSVQu3_1_RVdsdxapukmEzSuSIhu9p6wuIof_OlpAw3VvrdNKpHg8EcTeyb6mRn5xmFL7f6H_pZuShJFygV9MEqaGpz6Ag=	IS	decodo	session-48	t	2026-03-28 20:17:31.805609+03	2026-02-24 12:08:32.309329+03	Atlantic/Reykjavik	0	invalid	2026-03-28 20:17:31.80304+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
468	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_n3OyRRDj1JdGxM0UoNshm8FKAgX9jDSi0tHY5A5kYYn3n89950ysahEwjBHThBCUr-DV5XiMZfxZ79gIoZoPsX7H3LFTL371ifXieY7tPMW9o=	CA	decodo	20023	t	2026-03-28 20:17:37.92205+03	2026-02-28 11:35:32.1962+03	America/Toronto	-5	invalid	2026-03-28 20:17:37.919636+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
11	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n2nDtWakyrlr0BpLCdUZ6RsH2f_mh7CkLzyX2zAqe6OiGJv1GZg-jRk12My6BdWGvnkM2sTfeL9R8YVPRQG6zXpbPjvyx9ULxGUihUv0L4QDsutlpU2gv-Dm-_ExQftE3Bp2EbD-diBcONCh6LLHfaHFOSSzNqfSBOo5ln_N69KjQ=	NL	iproyal	hYx43MeM	t	2026-03-28 20:17:41.033355+03	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	invalid	2026-03-28 20:17:41.030726+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 1).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
226	is.decodo.com	23031	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oRSjQT0jfzJ9cojIi5SuxQyOx7X_eoDks0cfI9ntpVR9GEUw-qhXy0W3Iti_UkXf2l8l-938yWRZgagTYFEjUXyK_9R2YrzI_NivUTLZBDgGk=	IS	decodo	23031	t	2026-03-28 20:17:44.14266+03	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	invalid	2026-03-28 20:17:44.140049+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
469	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_n3WxFxX3qAmoYxJcbDre6h24SAxT65dRt1PurmlBMTR7NAtChBbUwDfJUIwspZ0HpuLLEzz2a4qmI8Uzcc5FVeSDUGtZcw03X7-qx9MDyeI8g=	CA	decodo	20024	t	2026-03-28 20:17:53.314899+03	2026-02-28 11:35:32.1962+03	America/Toronto	-5	invalid	2026-03-28 20:17:53.312705+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
39	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n6Sl6576u7Rc1XVkuZxcp4depm-Fon0v7SbbcpUIt8iH8iDpvRRoEteixr9DD0POYDNmalD4zSa79Sk9iY6OBiPffYemyDhX5T4zECcS5xOeD7uKL8GejxlLPnoKaGh0c7OLdKMCARKbiOURT1o-a8kjdishQ3cU3uMGQbZLAyBnU=	NL	iproyal	FGJQjSoi	t	2026-03-28 20:18:02.653578+03	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	invalid	2026-03-28 20:18:02.65071+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 1).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
208	is.decodo.com	23013	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oPoGOzz6d11v7zmzT-zCdLcbxTn39eoF7H2lgAa7me53DpLzEUu6JOyLeuXrHwtgqpb2_PxSYEGI3wJsdQXIAnvGyvAsbkeOugKKsbwSnN0fs=	IS	decodo	23013	t	2026-03-28 20:18:05.726334+03	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	invalid	2026-03-28 20:18:05.723968+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
51	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-6-sessionduration-60-country-is	gAAAAABpt_oGFeJuUW5-_tgLMdWgxfVC1-sQK9YcHe02tU7Zrj3e5Z9S6NvS0j3YUTkgasZNSbYkr83PWBDKosDCnxR5XexnTXhgAgc5C_WR_ozQCMhouEo=	IS	decodo	6	t	2026-03-28 20:18:08.779806+03	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	invalid	2026-03-28 20:18:08.77759+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
38	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n6SibYEx3pjWmXde8Dz8OwQdN-2bHJXVCzkMiCp1zbS10Q40mH_ZPyT-BxkEoeg6yVCDHopa8wuvl_9hxWkn3SZ2_r8Dvght--yL3WyN6nfVkWcNJXvUX5ZaB9ElA07DssJ1WQf1MHWWIxFh08CWt6sj_cDQG0AQXeaIc1JXjk438=	NL	iproyal	1gk63iRv	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
40	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n6gjAhOp5_m9lIKi37bDM0oFSdOQqVH_IyQbOBrBVG4RB2KwrKZrSb2hxrSlvjjk6tnzqEPgNnJVlayCZNqCLUTRbGuW0-xzhqgtOfs9ganvrgaadwghHY_foQNKU2jTEj5kObX_UvU7H4iEPlIOCkCQ3rZfxC0Ia7TZ7HHp17_Tw=	NL	iproyal	LDRpC9tv	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
41	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n6f2qqFcPRG396YGUP043hy53k2GdbsFkf_IvaPelIZvNbw3eA6E7KJ9OsvqG9yHfrJGpc5t-sVzTYAiJJ_hwnvIW2nEjVmC54ZEQX0V4ArOsAq0YZ2eWLIE3VfKVadrxv41RDA-yHTvcoBTEst3-FZbw4AfyRDnkVJjUAocmVQ90=	NL	iproyal	8uXCgFma	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
43	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n7CR--p150iqwVoDHR0khHD22oCD0S8WSJjUFeHt3iiRT6G_lNN8hiwFm86cuOJOZv1C1btdsGXeWkQE0iN6nNv8rfU9xHbPfTw-TMJhnSfcSUXuboNAod6jgS8WB8U36Mgd-KoKEdcRp0Be8ecLuoEOHRogENFYpxudNSJDdtXgk=	NL	iproyal	rrOApVaC	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
44	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n7fEpe7CM542oDNJq9Sz2UgopY_KTyI9xHAIth0AF7l8rVXI2lQxnZ1xkCslVCo-xM97ZudlffgWdkKNbzjzmuWJTUIdWp6p2VNr8UegaF-ds9AecAVDG_mIhGTJMVMKBWTL043JHaTXr4yljooWrBxkxr6J8LjlbqhX4lLsxY17o=	NL	iproyal	VASV7VCa	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
45	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n7ZHj0DIihhUrY41OoVSZyNDnOnsye_B4uelYnYWtmsv64BxOqcfvwMxjR64acPb3ZGFVAnD7ul7jUHaSVH96cPV3BDI22cV1YFA_POXvOguNoHDJTZyBs1xhNy2xSHd7MR4PBWXzDpBH61D6rx6Od-ByIVmvmo5mdc1N7MQAMxKU=	NL	iproyal	T5uctAG4	t	2026-03-28 20:17:41.074334+03	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	invalid	2026-03-28 20:17:41.072442+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 1).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
42	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n7klqrhfM6ece6uyivwqDmflu5A0-QrvNBGPN79R3Q1LBQLLaRu4mN2jFr1P_EoKtIjkRoUZ1ggj8Z1MxoKAyT3KWiOaPjrXqkMo1pTDNmSAvy3lqq6OGpHH8MSMNtSF-t1Ep1hEbmTcSBWXxcB-aKJZwIeH9tb1PLuIvcyNOwYzU=	NL	iproyal	yQer8Kk6	t	2026-03-28 20:17:59.517643+03	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	invalid	2026-03-28 20:17:59.515852+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 1).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
237	is.decodo.com	23042	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_nvLBKY2tOYOQ_cgYfTk27N4-P-1tKYwZS0GZcyhf_S5LrOz1yH9e3pdR1qV6TuqXZWlEnlvTvo27tOGyaq43HDQLCcKHcQ5uj842pPah7XfNI=	IS	decodo	23042	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
238	is.decodo.com	23043	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_nvODa6YQwE8W5yMdpRJJ5NmY12PRbhSeHFSRTlgmiS50Enfl62t8NFDzadZ762fTS6A2qEyKP3zoDxF1YabE4fCEz6VJTWx5SHv2W4UoWVgF8=	IS	decodo	23043	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
239	is.decodo.com	23044	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_nvXjeTxXr8YpKMHEPwlz1zuyChXpc12uiAL__nwX3y_uZiuxZ-NcZY6xI_zQhD6cg7jmVM9stqi4xd8Epu8lCIi5q1l7QMifmZdJKfpvOaG2Q=	IS	decodo	23044	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
240	is.decodo.com	23045	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_nvAdcilpcyJiKIZtQcR4DTvmzCYMFP7pWc7MqYwiQ6KyVRoQ1_-YePTXHuL8l7fzSCzstqrr66KiZFeEBAIhzMw86nhj1zxct55o9sM2V2hys=	IS	decodo	23045	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
241	is.decodo.com	23046	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_nwWYwn5s3msygmdA1ZAtB06kMmdzIeeVvIpZoHkYUfVTb_pDV8MIGTNCDj7zPPAGhADuiPQxETX44Cz7hDy5zcaI_MquUjmlCuSBG_dzZYMPc=	IS	decodo	23046	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
242	is.decodo.com	23047	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_nw7OBr1VS2rVpBfjRtFf0i8Pnh7B0c2_iNKv7cnhRzPGzQEdAtseeDAvifbEQnzrrAhU7Zs0b3t0YwAOy4iXodCqhq6bpMBI9cje8K5F5Xa_s=	IS	decodo	23047	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
243	is.decodo.com	23048	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_nwyOs1fsfejsxzXsHZQVNXmbk-miWpUtI-pFLRl784h4vLddkzY9UfO78dutO8prZfQ_xVqul0-LWfO-C29AZIFvigBTitFqvNxGsXbne1-gg=	IS	decodo	23048	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
244	is.decodo.com	23049	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_nwsBzystMt0bgU1vpyQMviNjXi2HiUKmBYfxhLLDOSshqEPNe6PAxxP0i1ocR4IJ0v5cVC8oxyxITuLnaFgscmkeTYhqaGe_Fz9HuwTsjxP2A=	IS	decodo	23049	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
245	is.decodo.com	23050	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_nwp02nl-QXf4nPJFqXiVdnKQF1-MIad_qd4cBFLOSy3_fvMGy7UEjWWDfdej8Mj2_CLPvhc-65xVNq3EsM7wi-IQp_WOxpLemHYAUGZv4z5mM=	IS	decodo	23050	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
246	is.decodo.com	23051	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_nwCNVdCobD4Pu9HUTBAKEZUxJabBbfykI4o0hbUYhlO-syNk2RlqOnwrCCexh8zmlJoO6OXHS62JlTUh3B8zgFv4uyovO2WeKPgWz8Ak0kWR8=	IS	decodo	23051	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
247	is.decodo.com	23052	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_nwoHgpePhpDWa-pjTUgNP-SnRnp5MumlhYL7ITyi2E1IILaAW2PLzeVn54sfDIer3ju2isWLbOQiHMZYY3jUOcEIR0x9AROtIRMmS4gmIZG9w=	IS	decodo	23052	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
248	is.decodo.com	23053	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_nwRskWoj1x0E3QVWqsx2yQ20zVxN7IAERcO2Y_Y7B65u521HJS3zi4ufPKdV6We8ksv3Jb5iDGg9OygfF_cZI8tFTha0xJ6JV9JR3Enoa1-ww=	IS	decodo	23053	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
249	is.decodo.com	23054	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_nwK73E5FncOiI600An5WHtsu77DE8vh9EX9v_hPpVX9KJAu8DV9LcIARtiphg94chYBie72-St2UdJypGuYYUJliZiMg-8q3omo2HJWVDvhtE=	IS	decodo	23054	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
456	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_nzqBwEn64ruxeAr4OpJ4Bsu7UyTSVGOgYBlKaoAYK0qsIsZYeW07_oDnsgFDzlNqydvUSmPLtQkP-z64JBjNrePHeYaAZCGRkHbtKWWEvAhik=	CA	decodo	20011	t	2026-03-28 20:17:28.689757+03	2026-02-28 11:35:32.1962+03	America/Toronto	-5	invalid	2026-03-28 20:17:28.687327+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
457	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_nzX3AwPO_dADZCkzenq6BG8znItvPovIgXcELRkcb1N-TFb-eQnmMDolbKwQQ1iKDsLHZTrPYEP-8MYraApABXKJ7lR-GnXVB6jvHeyaQ4Bjw=	CA	decodo	20012	t	2026-03-28 20:17:40.99457+03	2026-02-28 11:35:32.1962+03	America/Toronto	-5	invalid	2026-03-28 20:17:40.992568+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
447	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_ny5Tfb-GT8UP6Omp-KMpQd4imH9b2d3ok30Xvl0P7ys3s-eBv0PWBoaRkSnQ6Cn44ZXU3_xBYxL_jDuGEwWisGWozRbZNP5ArI0X06ErLVp20=	CA	decodo	20002	t	2026-03-28 20:17:50.257972+03	2026-02-28 11:35:32.1962+03	America/Toronto	-5	invalid	2026-03-28 20:17:50.251799+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
446	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_nyNgEHNtm1etAu4NmdDRd9Rq2RNMXdRLnIp5vqyoWQLO3r-h1w9BgKgocvcOu_VsXvijiucg1KxwrcfkDh20BauIkMJMEJBlR6DZyb7ddxC2U=	CA	decodo	20001	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
448	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_nyq2ArxPBBSpKOKRb4jE_9qQlwn1EpvNxKKDEjVYLmDU4P2qwcxJ8614dEhEJjIltHbnhc2gBsEGqcXGFwrct2qvI-Kzp1YlRVHiJeNVx9RB4=	CA	decodo	20003	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
449	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_nyt90eBRre18m00hAfzqflHoxkXj5TjcleHx6BxXQ134PXeJP9ZRHqP-phWz--TWZUYYm1V-ORgNc1pO_t9I9DvzmsME4eGMuCRiEmPp3gnBU=	CA	decodo	20004	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
450	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_nyPZrruLtmnT19Ptspsa40Z31Bn_9lnt_jCyajdd61zNqrwU9axP7kjdmS_qQMEItGjfnzNsbKaYJUPxJtgzjgAnfJKTRv4sPmgowLEqiKvX4=	CA	decodo	20005	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
451	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_nyHN0Jvl1WhCJ-Qi_iygau2Xjpm6JgFLV0HLUcTPqh6c6E3_La8YXqPiP68I71rfbNZfpsFFCFoK8Qu52f50AgPIJbmoARrAHtfwHYvXffBX4=	CA	decodo	20006	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
452	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_nzpmO-excNa-kJs3nu1vKvLSSFQu-KrwJNksE6OscZ5luNnbM4uzapuUareEgBbq5a48HntceIRdlog4CXr66XK-L_59ANJChVfGk337ZXtas=	CA	decodo	20007	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
453	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_nzUr6FvTGw4akOR57lV1DislaxBRFUNcQew_H133hjxeL0Cw5IQU6_4_b0jGG_W9J8nmJdR48sXJCECmeNnbmjCEDSi6bk0jF7JeG_M3nU-PA=	CA	decodo	20008	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
454	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_nzoOhn207GPIN65kgaqPYIRC6B7aehWjFEQF3Exvb5cyerW7j04CILuHACUJRC-VS3lL5ly9ZU5L5HxWf1EQC1LYiulYwIM1SRnbGsHXmOY5o=	CA	decodo	20009	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
455	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_nzyMIq00d-7i2TDNKdtCzhhLbQZHFiIGxYRbiSOZRZRN_X7VwGt_Ud445uMA-S9XscJWlo_n_-fYCfGOLdRgAAZkdUaRbppLFvlrv7PZmMKA8=	CA	decodo	20010	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
458	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_nzM5MKoQ3bYPDeMywSBNzcJoOwjYjBQnE5E8ds0tkhXPCCbErMra9rFjnIcEU7qegr-1-g-fEjzwgKsHZd2kbKdx0KsLEn4Kex035B72wxBPA=	CA	decodo	20013	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
2	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n1nDcYr9XUQjE9OdQcGQqXDiaqiAD_GMjpvJ_7icyCZ7bzTo6HaUke4iBxQPXRXVw0xyKFH3RHtgufWGJo4ejQssmYSoiq1HN55qrSf98lDlgrVy1mdKQ4weFQ2xVmtInp6sRXbPZOUCGMTZydEzEV72b7o9atTEbv0VCoQdr0idc=	NL	iproyal	x1Wuf6Vm	t	2026-03-28 20:17:13.275047+03	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	invalid	2026-03-28 20:17:13.272974+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 1).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
1	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n1XNXbKPaGh-YNQDSQKb31VBn86yqhLOpz4e1hqbSxuO-Z-0HSLax0_B1yyT0QQagPImy2H_nYnPde5mxHTqE4VsoB-Gaiw3Y9I9y61fn-tNzxm5MKy9B1uDBYOTaaBDCIzZ0LVOS-td91tKvvnkj0qbb5n1mUx3Tt0JBVa8GKAhg=	NL	iproyal	ZGojuljg	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
3	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n1AIv3yvD_56_sWBh-tNcyT820wq2U0bxKJkQZYY7EzUJOIzPx0mc-GfG1btq5lTgEC5Fbx9T4pC4_mzsMnf8I4Eo-7DqNRwCk1FbGThv9_VKgVRL8QvP1xc_fBTVkwfmF12LjEnMeRYUM7HP_KHTmSjRj5WEmMQNXDgQjwTvh5tE=	NL	iproyal	FD0WtV8k	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
4	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n1wYB6IOFw89rbZqb6HFjs9_l5nS87mc15glNbjk_y1jMtZu7STJoFML4MYLeMFqfzDqIqMbRIx6rt_uWhUB8EJ3D_ErTPW10j0JUt5W1BZzBufCtCewK2yZdVlWSkOm-IUIukBQVOrxNCp6-HntLk-dI-s7fF3HTWa36xj7PpmT0=	NL	iproyal	6DgTaO1v	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
5	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n1FYl5aeSLrGhqkb2_jnc-mBMEtUwfObCbx7dy39NmKFnWVytka4qXN5M28UgAb27zfFgQwV5TdcQZmIpmFPYPyAgY4KY67ic5pBKwawgL9WrL6ool4l0F1x0zc5nJpcqn-c-wtlxFmPWDFc6hLmLH88vO0yNQQ16h_6U6RdIengg=	NL	iproyal	nm0QxJnf	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
6	geo.iproyal.com	12321	socks5	mtsJYVVhN3YaX3z7	gAAAAABpt_n1qEBUVrC_UztTc2p3T65iQMRfxtCY2z_J2dWGLFVI57JBt_Nlk0NkT-6kzA9c2HFG-ouT9J0QKX8MQSUQG1a7xlVwMbWeUFAN0mVIXg2fa7s4x4e2NqjvVTZwOkkhpmEHOmbKPgK1bIGhcs05eI90KGkjFoqVv4hJuTrxXl__KQc=	NL	iproyal	AIYadqPu	t	\N	2026-02-24 11:31:11.818064+03	Europe/Amsterdam	1	unknown	\N	\N	\N	\N	\N
86	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-41-sessionduration-60-country-is	gAAAAABpt_n3ypB-vbGfuEQK7K_NLRRj5xndpzPuGJ3uzxZRjgMpriJsQ2RXVrtTXNajcvkL0364knZMBfG0kupoO25WycGpWsnCHv-KIjkX9WkFSzJJzX0=	IS	decodo	41	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
74	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-29-sessionduration-60-country-is	gAAAAABpt_oJTFupaS24fDWSZXGHLwQSqaWypZiX4fJjx81wBgyQCjunjlhfVr2kvwndFaMSc7PPDNT_sl011kiE0Fq3BBG6ifE_XOXhjtRO8y2Xu-1WY04=	IS	decodo	29	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
49	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-4-sessionduration-60-country-is	gAAAAABpt_oGed29fo0_FUtAOH6zTDPoG017_pvEBvab0lWB5ZZAK2nfkmdN8dyoJoCWvsE8Hiv5Nb5vORs3u-mLpEYltyuAlstR7iP_zSmKCSC0_i2GgnI=	IS	decodo	4	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
50	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-5-sessionduration-60-country-is	gAAAAABpt_oG34XyWecUbdqsDqGLTLPEQ5r4IIf-cGhM5425PZMQ3M3_xvPxkecTkLYQbe-3gSDixxu2wfdXVde6dL5hn2RRF7S-U35Aocyn5UFD3OPEDjE=	IS	decodo	5	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
52	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-7-sessionduration-60-country-is	gAAAAABpt_oGAC-bLCovZpY8SGGaKioaJFeCYZ4Y8ReLR2RbxoIWuzWY_t6XvmfZP_Sy3r5shONMYJKho1EVR6ZsL2GXydaak7NDG5o5-W4w4R5DG3VLnig=	IS	decodo	7	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
53	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-8-sessionduration-60-country-is	gAAAAABpt_oGJkZLML9vS6ycBpqsHZiiY9USD94gS8ZTvnGxvJHw13sXQGuxi2xkI2HQP00ykAhvcHI-PbAobOfJJzuDK1LEjGzZXy0NJUGOuJsnyYIVZ28=	IS	decodo	8	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
54	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-9-sessionduration-60-country-is	gAAAAABpt_oGNaYry0peuXngsA8tld-yv7a0mMpnGU-NcnOeNmScN7JZAo0EJQOvc2TaXyhIQoYDVdxfNPKHEdx2Wg3Q5H52LWHiroIy7QWIziS8ksugtjg=	IS	decodo	9	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
55	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-10-sessionduration-60-country-is	gAAAAABpt_oGdhXTaIHVYFBw2vXlZiSdGA-c7tC2ZptKEF_OWvo1KvsZJBkaTdDOVjoDq6VJ71cNT1KcMT4zMfJEqxIvXLma6_FgGf4RBhh7gdJYiUaJJiE=	IS	decodo	10	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
56	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-11-sessionduration-60-country-is	gAAAAABpt_oHD5iUhutbOLrDuMCT-FwfED7vF56BzIZkMPv7kSmMjtfhC8DBpU5NycsZr1Hp-rTpAYaiVuoIBUlz67rJTkHRxRmGmovhREvnpLseWCGP8VQ=	IS	decodo	11	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
57	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-12-sessionduration-60-country-is	gAAAAABpt_oHbreLOOv2eMwJQ1YCzxB10TcKpP6vl5lH0Ik7U-HDgNmS6Mz7bMQec5GN-RXEd6T5tUdrXSB3WG_yZxIWIFSsY5WMSAH5IA-8CaLL1gBRFfI=	IS	decodo	12	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
58	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-13-sessionduration-60-country-is	gAAAAABpt_oHdq6TDm9fMC29iPQ1SDeyWl_-ssjY1IjmVVKoBPwyaImBwQmPIulKNrHu1ZjHf1kIJUV4ln_J2AJv-BKJzCTuN_FlxH60UwJ4wu8XT6Kk0RY=	IS	decodo	13	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
59	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-14-sessionduration-60-country-is	gAAAAABpt_oHozmzbsUB-QFghDqyzIgynMB244aY4XcJzEARYxP7TYahVHF2NqEnf3ulQC-r5JtCOiIaWP5GvNmkwSZtcxERPZ5NPAmDrJGHgK4kdaaegn4=	IS	decodo	14	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
61	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-16-sessionduration-60-country-is	gAAAAABpt_oHwcdUtHmqMFBeszgqKrn_PaobsZTHu0uzC9jG45zQgw2yxkgUti9WZw1lH_zC-TM-DX7ERPdr1wh1Fs1RRtSfQ2ym7epfo4iok055mi-TYAQ=	IS	decodo	16	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
62	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-17-sessionduration-60-country-is	gAAAAABpt_oH-TD0_R5DtGMqI6KvOTqtbpvo0pFuq2MqOXfJlRICtB8We2F1dZF-C7Xgaq5-GTN3dA_0pdWGsTPxw7wlLEFxllvF7Gt05Ta6F2z67_sLjLw=	IS	decodo	17	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
63	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-18-sessionduration-60-country-is	gAAAAABpt_oHZ47-b9bGZ7AQn-1fLhP4PKGT8ZPRzfy2Kwxg0fpMsnRK4yiEqg8xzD3HSwAYwxudjxTzHqG3imJjpSDzm4jhLwCvs7ihXi-LIYH5T_tZUao=	IS	decodo	18	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
64	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-19-sessionduration-60-country-is	gAAAAABpt_oHCzYu0KB3ZE8smZhDvu9xYmFrVWgyLIvFxtXHVtSyhza9zbB5yYSPBVF3eKDPU3u1uP5LoYs4QueH3TZqWtyIE2gk58Mm1YYZKY_m7KCO6u0=	IS	decodo	19	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
66	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-21-sessionduration-60-country-is	gAAAAABpt_oIoUoGjggy5jaMiY0isxltdrAoMrPsYQ0NfDaFPsfM3gkfpdmECgG0XWdk7pgmAVqMw9S9NA0bUDF4UTgSbfrWb3R2hFmfdeiyzoVczURgZLo=	IS	decodo	21	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
67	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-22-sessionduration-60-country-is	gAAAAABpt_oIgdV61JLf_cSRnsEsyjfsNjkLnL_JggiJw2RfHgoGHGArCYqFORwljjGIbq9-WTd9a1CukgG-Q3ZwwP09qvfAAk4yL00RrOKQwAFACpbj_AA=	IS	decodo	22	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
68	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-23-sessionduration-60-country-is	gAAAAABpt_oIgJ6dAQOQnJ0Gjo4K_xkYFIXneGI7k94cHe8hAGcYlGhZzfUeZ-t5wuyEDNxvr7t5TVyvPoWYCN-_o-Fdmy7fF5vKMGNnEiYkW8EJAn72jy8=	IS	decodo	23	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
69	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-24-sessionduration-60-country-is	gAAAAABpt_oI7x9OpuZtz40sZwhtjlLDOiRTINKkcBCi044jMo_OE3mpqM476DQUjsJexSx0yKIZvWWkLGCPkPIIQeLwy8p9_YZ5b92gKNe9F8YuGVoWIQM=	IS	decodo	24	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
70	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-25-sessionduration-60-country-is	gAAAAABpt_oIxLSzI3uaJ_pnykRj8BAD8UOM1UXxbHUlz3uzhhZWnt_vGNgE1RSXG8Frtp1zYLjkVQcH-RCgwWtswX1dRfTQggEZA5u0dFQgoeXX7axpCZo=	IS	decodo	25	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
71	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-26-sessionduration-60-country-is	gAAAAABpt_oIvQJDNZU32OgbbHjxPO_zZhBFU9MgT3OM-HGyzG_R8tK_BQ6ItPM_Ev_CaqHmqeYPq32ElMHpTCiWFdc5qxHBX-v6hjnRM3QIP8NlsCpBSWQ=	IS	decodo	26	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
72	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-27-sessionduration-60-country-is	gAAAAABpt_oI-jp_UEHl2Syrg__u4sGgUId_nu8pUqPK54-CP4dzeCsrsuuO1Pq7FlcQDRjA-4QkPpMf5ZDAtq7ko21nlRsKVze5nKRp8eTVSEA6z9zBnPI=	IS	decodo	27	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
73	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-28-sessionduration-60-country-is	gAAAAABpt_oI-VnSsdRKgwpCkn8biCKpFHG6ByH_7QMw26mzQlTHrYLVZQh-alBA76F7hP4i_lo43eA4S0Ls9bYC3MZg3MMb4oVqE4utOEd5Ya9_8yECmdg=	IS	decodo	28	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
65	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-20-sessionduration-60-country-is	gAAAAABpt_oIUD44nK4wNDFCu9VN22LA76P7hN9gpuWkj4TsoFW2CfpsUUCHGCh2D1YwUcfm906i_0f4c-iDVi2Fk2gV4rPKL1WzSaNGOy-mUqWdIrYc9T0=	IS	decodo	20	t	2026-03-28 20:17:22.560156+03	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	invalid	2026-03-28 20:17:22.558+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
48	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-3-sessionduration-60-country-is	gAAAAABpt_oGmnnU2xIqew-UQi8W2JJmk-GIvpnfUD1jOucPow1FiX0itJGwIb3YRUta45k_XTZCEFGEXW0LMZCB0LkJ7MYxnEeXqjMkLOkNZ0oopsVaWxc=	IS	decodo	3	t	2026-03-28 20:17:25.620589+03	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	invalid	2026-03-28 20:17:25.6186+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
76	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-31-sessionduration-60-country-is	gAAAAABpt_oJ-5QuXU-g4nm4AzpLCDk5T2-PRO_7oRlSLfmWNVmZpT51INikTZxbhY1oQKBUaOGfdyzvH4mUfJpgeRhVRxmNiUNzWgFlPTEduv9Tbbr1MlY=	IS	decodo	31	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
77	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-32-sessionduration-60-country-is	gAAAAABpt_oJsF_cpX57z4dLZWFm1of4ZjIpOvgYdSMF4QQJrxzt-4-jespwGcgp8E0Y1M3X_IAzDjTSaj2ug0op5wSYZtUx527CE3-0lzvWr-NOQMw_RTA=	IS	decodo	32	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
78	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-33-sessionduration-60-country-is	gAAAAABpt_oJ3EtJ7d-NiXMLha1sOBJwAnw9VtFBSl1OxwZjHGfozWJ5zntiYuDa9K87BwVlJbE2A4TQkxHM1d8d91MqYg1ZMDuF-YEM8elV3WYvDd0kvQ4=	IS	decodo	33	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
79	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-34-sessionduration-60-country-is	gAAAAABpt_oJkgQjjnYDhLFJfDY9GNgEAbQUJkSAe0mwA-i3qFk7WZj0L1lxvmhvFxRr4ghsUT8zH5nYL0XJl7ab-sNc7ft6eFweL7cXV8VKSGAmu3c0AeY=	IS	decodo	34	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
80	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-35-sessionduration-60-country-is	gAAAAABpt_oJ9Z-qsKNLwUwZIqwVHkxOs1IzamQcxX7GvKccRQsk2qMzm4BzHJ9q1YvCiXiaJHTHXP9oe-01wcCJb9NhQXK_2z9g-AmgyBKjlNpxNIBG1Ic=	IS	decodo	35	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
81	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-36-sessionduration-60-country-is	gAAAAABpt_oJjRV5RdII19ZUibKcQDJuteTENCZ_nYpqQwIEPG3m_G2D0OzfH0_eC0I03sKxJoUQt_IUnkaUTo5pU5UTx5RSaYuJbJLAJLecWsYL7nOnRm4=	IS	decodo	36	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
82	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-37-sessionduration-60-country-is	gAAAAABpt_oJnEJatLefKDI98GgRCZ_YafscP5H62BGOYgL7i56FfNCPLmiUIOeH3rp0_Hzr0Wnt21PDbekJLUwc_aUgL_x7y8JjGeQli1WAxyqUhU4wY5M=	IS	decodo	37	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
83	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-38-sessionduration-60-country-is	gAAAAABpt_oKMzSwPNNezoJOaYkLadeVFwnGuo3agckBXWqiQicT1bVjP2SnomoThTvmEu9158PWNMF5qUgYzBs4ma8Wi3Yd4BitYoiAU0QWFRMsxWYP_LE=	IS	decodo	38	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
84	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-39-sessionduration-60-country-is	gAAAAABpt_oKg2hy8OPajiGBtuUjfycWlESaMZKDI4sWjYdgbl1SCYYoq5hIdJqVi1MVixrm4fRDI0mMjv2CYlY3tPy1MMMDJBcbqf7uZwrdBX3J0El61vg=	IS	decodo	39	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
85	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-40-sessionduration-60-country-is	gAAAAABpt_oKT0lruCUO2gouMnYncjrCk61BnL4xcMLFTDduqf8-qXyzpiqfmUc1-5Cp4kmuyb2ZPAAuyIlJ8R7cn2NtcGuMM_Dbfbv55N_HhwLQxcyG57o=	IS	decodo	40	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
87	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-42-sessionduration-60-country-is	gAAAAABpt_oKZ6hWVvwIF8dKM9EgFgTHtOldRgE24ZQ_Z9Qh9OLy369VcVE5UfszFy53ieVcLrLZh018gzao4yaFuz-I7mq9rWoUiuaZiKD72Ok9o1EFvhs=	IS	decodo	42	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
88	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-43-sessionduration-60-country-is	gAAAAABpt_oKDGuLJA34fURKlKns765i_7xl6JA7iPak4gk_PaL44ICPkaPwIIhpSfeZ_L1REJSXFuIuTFdzd7L9OO8IDEQOF_ccF4sHUqa8kVrLkX04RtM=	IS	decodo	43	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
89	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-44-sessionduration-60-country-is	gAAAAABpt_oKSRQhUGtSfQ3rv2vk3KCnleG_54X77Mx3VOv_I9gr9Tb9qVkoy1HWmAKa3PjYQAutkOK23f4TRsIwygoezRz8khl5u0tkiqXwXxwpeiNdT5U=	IS	decodo	44	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
90	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-45-sessionduration-60-country-is	gAAAAABpt_oKYKWx2r-yT19tyBup4oy0A6hpYD0qmSr3inG8-xHBgN-1LJPc1tG4l2SLYDJju0ntevxiyeh_oiK_elGFz57wiPrhFFiNbjFAdIrVHwCczTM=	IS	decodo	45	t	\N	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
91	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-46-sessionduration-60-country-is	gAAAAABpt_oKrnkcGVDYut8WL0wMsbBLxLQYyQze6B51irwBP8CuVFNQzHFdMdT4cd-tEmWTAz1LsvJyAIIXmxZz4OIaQW2cW9PJg0bBKvWvOcbFSkLF2Ko=	IS	decodo	session-46	t	\N	2026-02-24 12:08:32.309329+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
92	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-47-sessionduration-60-country-is	gAAAAABpt_oKnsC1uhBGjEGNevj4iGWu3ZgJsTd3DLdwCyQDKxxRBSiEatRkuVYls7rgaDA0ds38iNkcxDxVk8EeWha2fh8iaMc-hmrKKYmnPNa0hO6mEck=	IS	decodo	session-47	t	\N	2026-02-24 12:08:32.309329+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
75	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-session-30-sessionduration-60-country-is	gAAAAABpt_oJy53NW3vZUmDYuUGFuPqejkZYGgDBQR4J61IQj2XbFb3ehGzVOfZEZRqqRMEGaESTdoM2BDq-7T7pEJeRTLQS28MZ3b6t0evRjUsvbD_hivk=	IS	decodo	30	t	2026-03-28 20:17:19.489319+03	2026-02-24 11:31:11.82809+03	Atlantic/Reykjavik	0	invalid	2026-03-28 20:17:19.486863+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
196	is.decodo.com	23001	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oOO1df4qJOQTbzgKAXD8Rhaampnl1U94783mc-5ms-lS2QoPnVdWetiEGxPN7_9L0XDt01eY8MtgvO0sqwSkMHXNdFRWVkElNoiX6GFx1U_4M=	IS	decodo	23001	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
197	is.decodo.com	23002	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oOcPlWbEVi9yhc24g_11-xO6VRI839OosDaOD6cLzgPfjLhriB-u7zv5H3X0yxRfH_lCD0elwBybqJa_kkh6ooBx4T2O5lcgHCRttbPzz-Gbs=	IS	decodo	23002	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
198	is.decodo.com	23003	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oOOGiuMIAqrVZFyIjcW8gxaaXJQXZ0bU1m685rZOlEu2UdI2G4D2zcBOE2PtLbGe2wy3jpN7Q7jjZvfPwojQxd538RKe_XEWeokqAcboZgV5U=	IS	decodo	23003	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
199	is.decodo.com	23004	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oO_oGQ0-IOQkFQ0EEVwB4dEF0T8fqEXSZUga5f476gq-6q_HfARG0sFx66E8upU-hHkOqGpPo7AQApEAI5lMFibmV5MEvoQLZLie-pnfGqcfw=	IS	decodo	23004	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
200	is.decodo.com	23005	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oP0zRUzFU-aCfsQfuERTY26rAFkVCB3BLe_mt4D57yalNv2Tf0cg4c0erD0C2QOZiY_xKYxXK-EmIN9ELfCOkHNT-6h3L0o4hwk1l9VbJKsv4=	IS	decodo	23005	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
201	is.decodo.com	23006	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oPSy9tfQzOsl0tBVaLyCJj7dyePCXQmWuNQd3hCMOHatPW6OsfKYVzx-KDbYpc6kymeO6X8OIQ4O3A1UwCnEVaH1-6YWlWgCg3VObShNzOj8w=	IS	decodo	23006	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
202	is.decodo.com	23007	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oP2Qn58xXkZ8r8gk97uA-w55UqaOTV8xacddFq9BIOoylOabsaHD8RDFDmP8d4CkmThQT3Rt61n7soCCXaTpSFjJrhysv90OhVA4ddk5rcSgk=	IS	decodo	23007	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
203	is.decodo.com	23008	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oP5Tinz38T0xBNUMztLOlOrD-sk42sREg0usp1bNcK0h5DBG68-jrAJM3v6yLaWtukGHXxapkXwrS8xhF_csvJH2uuY3YWigNcnUo7HCJh90Q=	IS	decodo	23008	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
204	is.decodo.com	23009	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oPkcGhalSkjbGJYKf_H9e9q0JuQZdkiCrqE-HyH3MQcilMpO5vtI6FD_tbd3K2P5fXT8CnZ9fnFBHJfd2NFlIr1ZV0wof7RpJ0zOeSc4MbOK8=	IS	decodo	23009	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
205	is.decodo.com	23010	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oPARwo5kCTHBslhOvWJvVwMNvkq0YKvjwx4SzkCiB2a1ggeaot8aIAmBlyF-XcrGaoyT68sACEK4N3dDpeT5rvDgwRLSuny4XAY5ODDFKa_ZQ=	IS	decodo	23010	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
206	is.decodo.com	23011	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oPDI_4sXhXUMC9bB8_CQYNT2dJaNsdlmjpe6tJ30lF7C5Jo4H7rnXZCIUMK5t-0wEwCESVNo6NF5ai6Ke9bujW5gKeSxzurexuanmcckar-xI=	IS	decodo	23011	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
207	is.decodo.com	23012	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oPQcJ9TgrgW675Z6UXMoP3quXOblbwW7EO0e4Owh-veCPjWI47XQI6EFkqNwnOpFfIHPDnjFmxLzMRxmUfGE1mh0HVY5iRRackFyedUTtZM0c=	IS	decodo	23012	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
209	is.decodo.com	23014	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oQe7GzXboiPIxbpULlokE0exB9555QC0sHUlFKLgUMA2Lc8LEMkOT-BeWqo3VL7MiCzeh2xkxeqFeh_x10y9czbbaQOHMZjbyUxpfJOZR3NYg=	IS	decodo	23014	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
210	is.decodo.com	23015	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oQ6WYlHDFH6zVwkazkGSQ_g9vP4kvQjtjHfvob8gYRqWoHaMKa_KKvyiHTy6oVUXE9LXfr9QhNpgZd3SA0v2TNnU90sFw2P5wr3rcrADyq0IY=	IS	decodo	23015	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
211	is.decodo.com	23016	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oQ4h5vmNmXD_eejW4gbKTNeYK60soN0x1dcAoFZOlfx-UVlO-zm8jv7ItZIlXxU9luvqwfbB9haAL1o76t-3imXt7O4gt84_in9-gRreF_n2E=	IS	decodo	23016	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
212	is.decodo.com	23017	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oQWP9watpgpBx0MmM907wWC4FBxoyLFRjsQ-8sQjLTekPThvrDrowAXOJtvqpZqzUVqmo-FUbrPrTUER_x6IT4G7XRcAeeVi4FJBDzTHhknqM=	IS	decodo	23017	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
213	is.decodo.com	23018	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oQTD7sF2pIpmsqmDOtpd-ksuRcjm02fdddhs_qPUuEDU-rUDPQ4lJx7fpEq4kxI2DU1MqtSw9cl9PCdNuqw-U59jqZPMIfPxLKZAk9bLqwVL4=	IS	decodo	23018	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
214	is.decodo.com	23019	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oQyIXaOfcTfCM4xvpB_0Du92ufngcr6wcs3-vrtDg2ALwqzxRLihESByqYHMBsGrf94rwHy6Ddo73cXI3Y-VeC-WahBbQ-UgnaySF9Laimpp8=	IS	decodo	23019	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
215	is.decodo.com	23020	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oQt7WVW-EotILGUAyNLkdlIA8dwJTGopcVFzq44GiXr6VonUimMPutoRag7IBoGsT1th7nGUZmq1SV3CzfMETRaL10q_vf89OAcRqbwvvUsKg=	IS	decodo	23020	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
216	is.decodo.com	23021	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oQjJavA9zRx4DE7dPZixDUHUyPGud8PjT80OuZg6FYatZNvfsrgFesQvlVmQ873qfXHj8Sz2l5NsWsVuEKqksb-tBcYxP81ndl6q9-jwEQKqw=	IS	decodo	23021	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
217	is.decodo.com	23022	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oQ6g6E7eQZ1utQcF-hu-byxD5HtanUrQxFk3x6znRX7PMf7dXua22iXOrCAYWBuOF5iZjjxMKwdQZWnSvuuFd8RWcJA0xFBvT0qFAt-Y4dhs4=	IS	decodo	23022	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
218	is.decodo.com	23023	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oRnMgpPWm1qfVxFozg3SgbrMbbxDi0A_jWRBp2AbPLIh3OS9On-ev6IB0eoAQ3nKfC8wOzCo4BIDJz3HqXz-mBvJVIJnXL22JdJgkf_2CeK9I=	IS	decodo	23023	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
219	is.decodo.com	23024	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oRA6kDPQii4bqpifmBEOv99b_cZ-kIRJ-9xLzNIjpdSKvbvfCGdAIXLI9q2Y3DgrBURCP-lRElaS6Nqea2LlAfZc9wLuoeUo9KRsjkF1MHViU=	IS	decodo	23024	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
220	is.decodo.com	23025	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oRpS_xZsgMQfDCf0ARseyBgKIqKw4sb2HgSw97kXG-pyPAjzIc9iRUydhKW6tROKd3gOcJHI3kRvJsbkJDd-8Qxf9BTLKQRFvays-yF4xP5oo=	IS	decodo	23025	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
221	is.decodo.com	23026	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oRqk_YiAhHDG1s24x1IBpoGg-RR7uKjViyfPldPTRyhDfIRNaE3RYLx5LhZdVMEN1FQTcXCuNo6Rmo10OgxHCZHD-d-jzNhgRJ2EinzW62BCQ=	IS	decodo	23026	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
222	is.decodo.com	23027	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oRpOOVkrHHnXalPGBc047XP2BCKNuMHos7NEMXWxkTqTZ37JPptLwQkjx75TWkO5wecJqKw-jVZ7hTRYiJU0TK52OD-RgVsFND4x8HuKRNiYs=	IS	decodo	23027	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
223	is.decodo.com	23028	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oRXU3HOCb05vfHkp0YPCNy2-WfJIphfmIXN6VkGWhLwfuC4hh7gFsxpOui3WQhCqnYoVkQMlaST-2EUaveLvCoZQ8TGPZaFAKKCbwCxCPku6I=	IS	decodo	23028	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
224	is.decodo.com	23029	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oRO0EJkmvkKBGFup4BGql2Xe7-BP9V7AqI7q8G7jkFls6vWvrC0XPSvavPXe1qMWufDZ-09zdFymT8hsWj6trugu_4g8PMdRU0SldB3a7PN3A=	IS	decodo	23029	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
225	is.decodo.com	23030	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oRZO_3zLTlHvvOhfy-VgDvjSiADnGFfXYD7mjc_zjatZJ9LMbhuhzU8__CUVgaREGut-Eyz5IlWtMmPLt6LMJXAKxN-pmpxnHotfnQemeKRkQ=	IS	decodo	23030	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
227	is.decodo.com	23032	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oSg_SM83oc5w2sUO5ySAnUKf4_5dPHKRtGs7qCShQZcbHV0oVrQEtWkntVog4JftcxRyTOX0m7F13Bh1heDaKOmg6AXZNKfGKAbaUKy-USCmg=	IS	decodo	23032	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
228	is.decodo.com	23033	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oSVvCt1_QGggFMdowdE6wpZmAL5IGNAqqb9zlx1BralnwcMWPJnzUffHsmmgv6exGP_lQSHxdbbWmbRUhLkLfXzeH767QqLX959wjw4eOOmzg=	IS	decodo	23033	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
229	is.decodo.com	23034	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oSZLMM4nCZ1Xp1Fny975KlX4BtBjYdIsjWHmm9qJxsjG597z0S5h_h-R4LFd0NNMJUfor8bqdc0IqXrRPiMBjDtogLail6v4lBxNDiohOampg=	IS	decodo	23034	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
230	is.decodo.com	23035	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oScgUUD3M6Z1ZYX_hkEbtbzvmn8f2-3WmbFEn-bFG41-bTOykrZ0VB2DlxAMdWd4zYIQNRRO4qWSwFvtRCgUbfZYyLAOkwHE78n04xB8fUrdU=	IS	decodo	23035	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
231	is.decodo.com	23036	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oSFXYpgEHraoR35Gm2izDYKNzQAl72Qv39JtiYAjgNaz-b_SMb6s5zWqO7hByZPl_Ykip9Od8r1zPOm1eaQoSSCh5KVNIamHysZF7Qy52-F3I=	IS	decodo	23036	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
232	is.decodo.com	23037	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oSz_z3nYcAw-nION1F0QIMytV6hpr5nL2gfCEVWgJ78A0Ofde7ntJGLM64FtmEUZOWSle4x5ajKJK4B8DHXu0xSijXjVBtx3SP_y1kosGGPpA=	IS	decodo	23037	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
233	is.decodo.com	23038	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oSqfq5sRkzWBjBlAmRD6_ngSAILl3xSh8C57Adsn6QYgQ_8IsADNpzNijkdSqoG8lR-TWLnV50Wu_hY4MBwRqKjIDJGhtZnxjq6nHM2IwyJX0=	IS	decodo	23038	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
234	is.decodo.com	23039	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oSvv6GrEZTjaJ6l9akvgxHvrDWrHi7LwLvGx6MQtWo1R2kyXk9a5kny0gK4Ava_s0XAvf_l5wRbMaPsYNB62W0tROM9NWI0UvY9DgNRb1iw2g=	IS	decodo	23039	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
235	is.decodo.com	23040	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oSKiY88BNiMkTvSwfKhL-k5acrV3ZgTcZTA5gH_xH3BQtGC3-f1kHs_J-yoK3dfuqB0uIzdQdvDybHmkWy3-5LhHgGypbnHxG-vCvIwujF3q4=	IS	decodo	23040	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
236	is.decodo.com	23041	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oSTeTgIAvkYJZ7msxi8ldZzbPXrc1HEKM4AIdXAeImgXMH2ZCnS0DzTdoCPZo-Wdj7whUWtprgtKUKGbego2HWjoEYuP3L1Ezs1zrWq4HGMbY=	IS	decodo	23041	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
250	is.decodo.com	23055	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oT5inmiTQT5JBouF3wJmMwsLUuYaJLjUioyBZ8fZxw1PeH-YnpDb_rM5It62s7ZL3zn9MayULdAjI9hTKAB3PgVOLCSq4OjIF-XdLVqatWyXM=	IS	decodo	23055	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
251	is.decodo.com	23056	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oT0VefdmFCJVVBheS8dhSYQXM2SelzKAL1b2XCa5NdXM86wy4gSbCvdrfvImhUH_xalzpFOc9GtJurnAN9NzUMaaT6u5Uwhzvxq1oo3AejcSU=	IS	decodo	23056	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
252	is.decodo.com	23057	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oTFuLWATc2FJURps5FWGJARNxmWFHvPww0oqJEXxz35DgooCiB4AFoZOw7gANWASRyp8rBqmGSmM8tbgADEMUjNdo4LxcCbqCMVQDeETI8-Ag=	IS	decodo	23057	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
253	is.decodo.com	23058	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oTr581nxTrBviQ53B34T5Mu2xA7NqxYZvmI282HXYAxH6hKqPaGgQpYlPI6iFwHuJ_JG7zP3d32a36ZCifcgwj56nbm5BqWXb9e7QkLFGrq6s=	IS	decodo	23058	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
254	is.decodo.com	23059	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oTJgYSAI7c1Ja1JYxVlV8nn18oUNW5gv1lUO_RLklHoW-LMb_3MHL3C9rNTecVj0YJ_LapdzGlWyMEj0vv_ZSHWd6bbDBJcfp2kE3epw_bhCM=	IS	decodo	23059	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
255	is.decodo.com	23060	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oToMSHlx3ktvyKw_OelsWQJ2RUQr9kI2YRK7RCpYUPX8AEk5q28DCP3AIz-6KHsQzdoX9Fx87Bxl-LbJpRvYeNL3wJ9HtlxTxN_6hY7EFGcQs=	IS	decodo	23060	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
256	is.decodo.com	23061	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oTXVQKVwIGgMf60l8WKydo7omvU_QNuZJKS91hvFj0kElevOkpvvq_PXibnyu5EJdEw2D-ubDONIpohmOF7I1MeFk9qdjiXEc3Ccy-uGsEDwI=	IS	decodo	23061	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
257	is.decodo.com	23062	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oT1Xf4x1waJ_gD90CkrobYkcSCEMtg68W-Iv-UXskq_hPBnIbwPdJZkc9mtr3J2QyUIUbbs9gPh-ylPZv4LQGNYcR_VEd1zGQLj6vfh0KelJg=	IS	decodo	23062	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
258	is.decodo.com	23063	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oTWtm5VE6xXC2QfjnD0YrEpaqa6CZYjRxWZr_5EsggrZjejeoUIckrQvse8UVmc_fu4Lc2GjImE-7-obfLjSDk9t5aYj5u28b_mCNdw9qnPCQ=	IS	decodo	23063	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
259	is.decodo.com	23064	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oUowaErWXx_2kel6LGpkNnANcgytOnJMxQ3QfYk0Hz7Lsly3SZyUUF5fYismzxQjd80klvOfF3JevTFwhcubavcd1-2CZH7Mn569ds9DxwQ0U=	IS	decodo	23064	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
260	is.decodo.com	23065	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oUDDUuq0YS2GWcVPZrEX7I-6ljICaPM8ipZ_mdCNM9C1rx3LLqx0iH32F552NSqWEcpt9raTuXGLw8p-gB9R8XsPu6vZJCsCjanhA4hgluALg=	IS	decodo	23065	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
261	is.decodo.com	23066	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oUVnyVnfhg6HwsLOgnBJ0QQTVoc7O-t-YFqV3Lt8Gd1X6OmQlbBd9FVM3HzA3fo3KR6sjeRAUnGbaB3a68_9QMfAZt0W5ka-MyQcYv17oJRCk=	IS	decodo	23066	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
262	is.decodo.com	23067	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oUHU1FM7JZNDtFakdcDGFk5msbLekg-mNtAlv7M0bLQMJsYXYdxAyJTVprnii-hpvF-MH-qX2ZYWGyWL91MIxACguSZW17Yq6F9ww9qtC45To=	IS	decodo	23067	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
263	is.decodo.com	23068	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oUdgJMX9tAZX86TX4BpfeSamzZB9Kf2eX9t_6po0exEmCPIYVQmqUyxlNd0fCg0LUQqELGpL95Z0bsQug1PIDvV-31NCvGHlP0kHiGglf7Rw0=	IS	decodo	23068	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
264	is.decodo.com	23069	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oUdL1qOkIXGyEgCSRakfDrO8uZZ6Aq1oEmj2u79Y0yPuJ1RyC1E-hYMW25PBf5uwa03VKYcgUk9QhYg2eXHn_75wWxngA5JHWEcKXaMpzUY68=	IS	decodo	23069	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
265	is.decodo.com	23070	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oUWNrcfC98jJoxawYYHw0VSfOlcUJa82FIZ5Xn80gpPk2vmIXGCHjnwp1BK4MeYzJljDRIrNax_kj3UUscuysMU62p6rri242ezr14-a1hRx4=	IS	decodo	23070	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
266	is.decodo.com	23071	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oUiJwD2bg574dsWaPYJrp2rodtZ5w_GOKKv55R3FytnHq6ORUvVOIAwgApNfipi0QPol8R1kGXYK5t2BiloaP_vCD8HRq3tRN4uAfcme7TSoU=	IS	decodo	23071	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
267	is.decodo.com	23072	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oVojQQUIQBrIVZX3pBNlbR69uji-Obnm4_s3s1ASZc7tRCKpTDh7Ct_ppuN4YkjHoETEhu4e4-a3Q_h78OvzY3sc4cbsn9AwLB0gV4PnM_pmc=	IS	decodo	23072	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
268	is.decodo.com	23073	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oVBGGpTgIs1BYN3oYiIQfeFLsBK2aWgt11x4IxDwc1fE_7hYUHRJGMATTX9sDQ2d81cG4_U69W27pYvNlarN6vXDn5bVSXMIfcF9l1mQTRoWc=	IS	decodo	23073	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
269	is.decodo.com	23074	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oVHOXaKBmmN2UTfOGrrbRLeig53sxIfuCahVR48Fi0K3kFSjby3mYPhf_WbHaBYSBHMWS-eMLSSXCR3waBf6YoHzaIUpnpeuoQgPlKHPHdmfU=	IS	decodo	23074	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
270	is.decodo.com	23075	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oVJS9s4D8EYf2ZD4JWpIBDDlxCr0EwVA6by-dImVs5DO-5zS5VssELAzMeCFCKpVLANdHZN021-AG26rs7k38cN4YPmYgBjDkfbV--smZuc8U=	IS	decodo	23075	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
271	is.decodo.com	23076	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oVjyIbUvCp0YnK78t1cq2oQthD2uUVK4Pv8ZkD4zHh2H2I9Dv-QYv1AVsJuLT1q4O61yhPmWwTnCmwSsMHfuHL2t51udcc-Q9azQLNQ_6EqQg=	IS	decodo	23076	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
272	is.decodo.com	23077	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oVLrFP8lYFI3TP1Gm6eORKuoagLekDcvo4ICTMYh4n0OrtAPk5CzCRi3qzZzL0i8IDn8hSnY6oo1YDdb5aFW4aP9ihtRMUeABQBqX6dMpMKso=	IS	decodo	23077	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
273	is.decodo.com	23078	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oVr4-TSmKQJxHZAqelPjiue0NGG1JUalfYJ5wehCY6S5aD5_OZPN4ngefpQlIf76o-i0UFTunw1qyEgsyowf1tRZdgzTEeq7ewMHcKkS6mlGA=	IS	decodo	23078	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
274	is.decodo.com	23079	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oV6SHryq13zPT2ZsUjBzo1bQYN3k2A3yTrj8T1DicZPWxXGq7gPB8n2fix6_VCksXkotBGStIagnmFfneNZp18HnHOHB9-nIvbOHssruZIA1Y=	IS	decodo	23079	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
275	is.decodo.com	23080	socks5h	user-sp8g3q9g5c-sessionduration-60	gAAAAABpt_oVNc70_DtT6MMSK-SmIrNwtpYHCX_5uAl90Xw9Di90kV-TGnCSvvwF4sxNdsAPEraCCWU1T9zMmHLYy-njWntJjamQtDJgtBbdGNZQopSS1Kw=	IS	decodo	23080	t	\N	2026-02-28 09:12:37.809203+03	Atlantic/Reykjavik	0	unknown	\N	\N	\N	\N	\N
475	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_ojOLtTp_eQn5-AUNGy92OY_inLViYbEznJkHetsj7no-5COrMMCO7K-tC0vyzBMbvBaY7pMEI4_zo-TO7C9ObttCU0gW09eku_vU2LAvhIzX8=	CA	decodo	20030	t	2026-03-28 20:17:56.377949+03	2026-02-28 11:35:32.1962+03	America/Toronto	-5	invalid	2026-03-28 20:17:56.375831+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
474	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_ojufT1APFy6hW2Ayo4LoXhxniOo3KTUJoKVzMvEjiTr0xlfHvmbExuRY-kjMYnbH-4KaHJT-CWOQd08BKbL_KzOuxpOP7qhIi9hdvJNhXlVbo=	CA	decodo	20029	t	2026-03-28 20:17:59.450413+03	2026-02-28 11:35:32.1962+03	America/Toronto	-5	invalid	2026-03-28 20:17:59.447916+03	Failed to perform, curl: (97) User was rejected by the SOCKS5 server (1 2).. See https://curl.se/libcurl/c/libcurl-errors.html first for more details.	\N	\N	\N
473	gate.decodo.com	7000	socks5h	user-sp8g3q9g5c-sessionduration-60-country-ca	gAAAAABpt_oj0_yyyaHPQoQ-4OLYBUI8HrZzmSp0lGSzPQ8qsJezS5_f4ZAJPwAn_tad6cgAAe1Yhqy4CLlk1BWBzdG_Oc6-3SIIYeBlYjEqgxQzZF_LKfk=	CA	decodo	20028	t	\N	2026-02-28 11:35:32.1962+03	America/Toronto	-5	unknown	\N	\N	\N	\N	\N
\.


--
-- Data for Name: research_logs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.research_logs (id, cycle_start_at, cycle_end_at, status, total_sources_checked, total_candidates_found, total_analyzed_by_llm, total_added_to_pending, total_duplicates, total_rejected_low_score, source_stats, llm_api_calls, llm_tokens_used, estimated_cost_usd, errors_encountered, error_details, summary_report, protocols_auto_rejected, created_at, updated_at) FROM stdin;
1	2026-02-25 17:37:45.482828+03	2026-02-25 17:37:45.482828+03	completed	0	0	0	0	0	0	\N	0	0	0.0000	0	\N	Migration 015: Protocol Research Engine tables created successfully	0	2026-02-25 17:37:45.482828+03	2026-02-25 17:37:45.482828+03
2	2026-03-06 10:13:21.294543+03	2026-03-06 10:13:21.294543+03	completed	0	0	0	0	0	0	\N	0	0	0.0000	0	\N	Migration 032: Protocol Research Bridge Integration completed. Added bridge fields to protocol_research_pending.	0	2026-03-06 10:13:21.294543+03	2026-03-06 10:13:21.294543+03
3	2026-03-29 19:17:34.778546+03	2026-03-29 19:17:36.528746+03	running	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	\N	Research cycle started	\N	2026-03-29 19:17:34.778751+03	2026-03-29 19:17:36.529267+03
4	2026-03-29 19:21:53.156527+03	2026-03-29 19:21:55.173139+03	running	\N	\N	\N	\N	\N	\N	\N	\N	0	\N	\N	\N	Research cycle started	\N	2026-03-29 19:21:53.156744+03	2026-03-29 19:21:55.173472+03
5	2026-03-29 19:52:34.004744+03	2026-03-29 19:52:35.868587+03	running	\N	\N	\N	\N	\N	\N	\N	\N	0	\N	\N	\N	Research cycle started	\N	2026-03-29 19:52:34.005123+03	2026-03-29 19:52:35.869276+03
\.


--
-- Data for Name: safety_gates; Type: TABLE DATA; Schema: public; Owner: farming_user
--

COPY public.safety_gates (id, gate_name, is_open, updated_at) FROM stdin;
1	mainnet_execution	f	2026-03-16 19:55:26.724711+03
2	dry_run_validation	f	2026-03-16 19:55:26.724711+03
3	funding_enabled	f	2026-03-16 19:55:26.724711+03
4	withdrawal_enabled	f	2026-03-16 19:55:26.724711+03
5	testnet_passed	f	2026-03-23 12:09:11.137147+03
6	funding_verified	f	2026-03-23 12:09:11.137147+03
7	proxy_health	f	2026-03-23 12:09:11.137147+03
8	rpc_health	f	2026-03-23 12:09:11.137147+03
9	gas_safe	f	2026-03-23 12:09:11.137147+03
10	manual_approval	f	2026-03-23 12:09:11.137147+03
\.


--
-- Data for Name: scheduled_transactions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.scheduled_transactions (id, wallet_id, protocol_action_id, tx_type, layer, scheduled_at, amount_usdt, params, status, tx_hash, gas_used, gas_price_gwei, error_message, executed_at, created_at, from_network, to_network, depends_on_tx_id, bridge_required, bridge_provider, bridge_status) FROM stdin;
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: public; Owner: farming_user
--

COPY public.schema_migrations (version, applied_at, description) FROM stdin;
001	2026-02-24 03:00:00+03	Initial Database Setup - 30 tables, 90 proxies, 18 CEX subaccounts
002	2026-02-25 03:00:00+03	OpenClaw Integration - 8 tables for browser automation (Tier A wallets)
015	2026-02-25 03:00:00+03	Protocol Research Engine - LLM-based protocol discovery and approval workflow
016	2026-02-25 03:00:00+03	Airdrop Detector - Token balance tracking and scan logging (Module 17)
017	2026-02-26 03:00:00+03	Funding Tree Mitigation - Anti-Sybil protection for funding patterns
018	2026-02-26 03:00:00+03	Consolidation Mitigation - Anti-Sybil protection for withdrawal consolidation
019	2026-02-26 03:00:00+03	Withdrawal Security Policy - Tier-based withdrawal strategies with human approval
020	2026-02-27 03:00:00+03	Update Personas to 12 Archetypes - Behavioral persona diversification
021	2026-02-27 03:00:00+03	Redistribute Personas - Reassign personas across wallets for diversity
022	2026-02-28 03:00:00+03	Testnet Dryrun - Safe testing mode on Sepolia testnet
023	2026-02-28 03:00:00+03	Add Proxy to Intermediate Wallets - Proxy assignment for intermediate wallets
024	2026-03-01 03:00:00+03	Enforce Subaccount Uniqueness - Ensure unique CEX subaccounts per funding chain
025	2026-03-01 03:00:00+03	Add Proxy to Consolidation Wallets - Proxy assignment for consolidation wallets
026	2026-03-01 03:00:00+03	Direct Funding Architecture v3.0 - Remove intermediate wallets, direct CEX withdrawals
027	2026-03-02 03:00:00+03	Fix Preferred Hours Diversity - Ensure unique activity hours per wallet
028	2026-03-02 03:00:00+03	Add Warmup State - Wallet warmup period before active farming
029	2026-03-03 03:00:00+03	Wallet Funding Denormalization - Performance optimization for funding queries
030	2026-03-03 03:00:00+03	Fix Canada Proxy Username - Correct proxy authentication for CA proxies
031	2026-03-04 03:00:00+03	Bridge Manager v2 - Enhanced bridge routing with DeFiLlama integration
032	2026-03-04 03:00:00+03	Protocol Research Bridge - Bridge availability checks for new protocols
033	2026-03-06 03:00:00+03	Timezone Fix - Correct timezone assignment from proxy_pool (P0 Critical Anti-Sybil)
034	2026-03-07 03:00:00+03	Gas Logic Refactoring - Modular gas estimation with L2 support
035	2026-03-08 03:00:00+03	Chain Aliases Discovery - Network name normalization for bridge/CEX compatibility
036	2026-03-09 03:00:00+03	Farm Status Risk Scorer - Real-time Sybil risk assessment
037	2026-03-10 03:00:00+03	Missing Tables - Add missing tables from schema review
038	2026-03-11 03:00:00+03	Drop Intermediate Tables - Remove deprecated intermediate wallet tables
039	2026-03-12 12:11:54.043042+03	Schema Migrations Tracking Table - Create migration versioning system
42	2026-03-23 12:08:20.733246+03	Safety gates seed data
\.


--
-- Data for Name: snapshot_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.snapshot_events (id, protocol_id, snapshot_date, post_snapshot_duration_days, wallets_affected, created_at) FROM stdin;
\.


--
-- Data for Name: snapshot_votes; Type: TABLE DATA; Schema: public; Owner: farming_user
--

COPY public.snapshot_votes (id, wallet_id, proposal_id, space, choice, voting_power, voted_at, metadata, created_at) FROM stdin;
\.


--
-- Data for Name: system_config; Type: TABLE DATA; Schema: public; Owner: farming_user
--

COPY public.system_config (key, value, value_type, description, category, is_sensitive, updated_at) FROM stdin;
proxy_validation_timeout	10	integer	Seconds to wait for proxy response during validation	proxy	f	2026-03-21 20:18:57.975793+03
proxy_validation_test_url	https://ipinfo.io/json	string	URL used for proxy validation	proxy	f	2026-03-21 20:18:57.975793+03
proxy_validation_cache_ttl_hours	1	integer	Hours before re-validating proxy	proxy	f	2026-03-21 20:18:57.975793+03
gas_safety_multiplier	1.2	float	Safety multiplier for gas estimation (default 1.2 = +20%)	gas	f	2026-03-21 20:18:58.871207+03
gas_noise_stddev	0.025	float	Standard deviation for Gaussian noise in gas randomization (anti-Sybil)	gas	f	2026-03-21 20:18:58.871207+03
gas_price_randomization_stddev	0.025	float	Standard deviation for gas price randomization (±2.5%)	gas	f	2026-03-21 20:18:58.871207+03
gas_heuristic_swap	150000	integer	Gas units for SWAP transactions (dry-run heuristic)	gas	f	2026-03-21 20:18:59.043714+03
gas_heuristic_bridge	200000	integer	Gas units for BRIDGE transactions (dry-run heuristic)	gas	f	2026-03-21 20:18:59.043714+03
gas_heuristic_stake	100000	integer	Gas units for STAKE transactions (dry-run heuristic)	gas	f	2026-03-21 20:18:59.043714+03
gas_heuristic_unstake	120000	integer	Gas units for UNSTAKE transactions (dry-run heuristic)	gas	f	2026-03-21 20:18:59.043714+03
gas_heuristic_lp_add	180000	integer	Gas units for LP_ADD transactions (dry-run heuristic)	gas	f	2026-03-21 20:18:59.043714+03
gas_heuristic_lp_remove	150000	integer	Gas units for LP_REMOVE transactions (dry-run heuristic)	gas	f	2026-03-21 20:18:59.043714+03
gas_heuristic_nft_mint	120000	integer	Gas units for NFT_MINT transactions (dry-run heuristic)	gas	f	2026-03-21 20:18:59.043714+03
gas_heuristic_wrap	50000	integer	Gas units for WRAP transactions (dry-run heuristic)	gas	f	2026-03-21 20:18:59.043714+03
gas_heuristic_unwrap	50000	integer	Gas units for UNWRAP transactions (dry-run heuristic)	gas	f	2026-03-21 20:18:59.043714+03
gas_heuristic_approve	50000	integer	Gas units for APPROVE transactions (dry-run heuristic)	gas	f	2026-03-21 20:18:59.043714+03
gas_heuristic_transfer	21000	integer	Gas units for TRANSFER transactions (dry-run heuristic)	gas	f	2026-03-21 20:18:59.043714+03
gas_heuristic_eth_transfer	21000	integer	Gas units for ETH_TRANSFER transactions (dry-run heuristic)	gas	f	2026-03-21 20:18:59.043714+03
gas_heuristic_token_transfer	65000	integer	Gas units for TOKEN_TRANSFER transactions (dry-run heuristic)	gas	f	2026-03-21 20:18:59.043714+03
gas_price_estimate_ethereum	30.0	float	Gas price estimate for Ethereum (gwei)	gas	f	2026-03-21 20:18:59.23663+03
gas_price_estimate_arbitrum	0.1	float	Gas price estimate for Arbitrum (gwei)	gas	f	2026-03-21 20:18:59.23663+03
gas_price_estimate_base	0.05	float	Gas price estimate for Base (gwei)	gas	f	2026-03-21 20:18:59.23663+03
gas_price_estimate_optimism	0.1	float	Gas price estimate for Optimism (gwei)	gas	f	2026-03-21 20:18:59.23663+03
gas_price_estimate_polygon	50.0	float	Gas price estimate for Polygon (gwei)	gas	f	2026-03-21 20:18:59.23663+03
gas_price_estimate_bsc	3.0	float	Gas price estimate for BSC (gwei)	gas	f	2026-03-21 20:18:59.23663+03
gas_price_estimate_ink	0.1	float	Gas price estimate for Ink (gwei)	gas	f	2026-03-21 20:18:59.23663+03
gas_price_estimate_sepolia	1.0	float	Gas price estimate for Sepolia testnet (gwei)	gas	f	2026-03-21 20:18:59.23663+03
gas_price_estimate_dry_run	1.0	float	Gas price estimate for dry-run mode (gwei)	gas	f	2026-03-21 20:18:59.23663+03
server_ips	["82.40.60.131", "82.40.60.132", "82.22.53.183", "82.22.53.184"]	json	Server IPs that must NEVER be exposed (IP leak detection)	security	f	2026-03-23 12:15:22.006718+03
decodo_ttl_minutes	60	integer	Decodo proxy session TTL in minutes	proxy	f	2026-03-23 12:15:22.006718+03
decodo_ttl_buffer_minutes	10	integer	Buffer minutes before TTL expires (wait if less than this)	proxy	f	2026-03-23 12:15:22.006718+03
\.


--
-- Data for Name: system_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.system_events (id, event_type, severity, component, message, metadata, telegram_sent, created_at) FROM stdin;
1	MIGRATION	info	\N	Migration 024: Subaccount uniqueness constraint added	{"constraint": "unique_subaccount_per_chain", "views_created": ["v_subaccount_usage", "v_intermediate_wallet_status"], "validation_function": "validate_funding_isolation"}	f	2026-02-28 21:56:16.850096+03
2	MIGRATION_COMPLETED	info	\N	Migration 028: Wallet warm-up state machine installed	{"note": "first_tx_at already existed, used for warmup status detection", "migration": "028_add_warmup_state.sql", "wallets_updated": "wallets with first_tx_at set to active"}	f	2026-03-01 23:15:05.03269+03
4	migration_complete	info	\N	Migration 038: Dropped intermediate/consolidation tables	{"migration_id": 38, "funding_model": "direct_cex_to_wallet", "views_dropped": ["v_intermediate_wallet_status"], "tables_dropped": ["intermediate_funding_wallets_deprecated_v2", "intermediate_consolidation_wallets_deprecated_v2", "intermediate_wallet_operations", "consolidation_plans", "consolidation_audit_trail", "phase2_transfer_queue"], "architecture_version": "4.0"}	f	2026-03-12 10:29:21.160605+03
5	cex_connection_check	warning	\N	CEX connection check: 7/18 successful	{"failed": 11, "successful": 7, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774009061107}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 2274}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774009067052}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 5934}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774009069924}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 2875}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774009072229}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 2302}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 1, "subaccount_name": "AlphaTradingStrategy", "response_time_ms": 806}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 2, "subaccount_name": "LongTermStakingVault", "response_time_ms": 721}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 3, "subaccount_name": "MarketMakingNode", "response_time_ms": 2977}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 4, "subaccount_name": "DefiLiquidityPools", "response_time_ms": 654}, {"status": "error", "exchange": "kucoin", "error_code": "UNKNOWN_ERROR", "error_message": "kucoin requires \\"password\\" credential", "subaccount_id": 13, "subaccount_name": "HiddenGemHunter", "response_time_ms": 1842}, {"status": "error", "exchange": "kucoin", "error_code": "UNKNOWN_ERROR", "error_message": "kucoin requires \\"password\\" credential", "subaccount_id": 14, "subaccount_name": "KCSYieldOptimizer", "response_time_ms": 2825}, {"status": "error", "exchange": "kucoin", "error_code": "UNKNOWN_ERROR", "error_message": "kucoin requires \\"password\\" credential", "subaccount_id": 15, "subaccount_name": "BotDeploymentLab", "response_time_ms": 1861}], "total_subaccounts": 18, "total_response_time_ms": 67043}	f	2026-03-20 15:18:29.708959+03
6	cex_connection_check	warning	\N	CEX connection check: 7/18 successful	{"failed": 11, "successful": 7, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774010269926}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 446}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774010270320}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 393}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774010270740}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 429}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774010271149}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 408}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 1, "subaccount_name": "AlphaTradingStrategy", "response_time_ms": 618}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 2, "subaccount_name": "LongTermStakingVault", "response_time_ms": 630}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 3, "subaccount_name": "MarketMakingNode", "response_time_ms": 1733}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 4, "subaccount_name": "DefiLiquidityPools", "response_time_ms": 603}, {"status": "error", "exchange": "kucoin", "error_code": "UNKNOWN_ERROR", "error_message": "kucoin requires \\"password\\" credential", "subaccount_id": 13, "subaccount_name": "HiddenGemHunter", "response_time_ms": 1926}, {"status": "error", "exchange": "kucoin", "error_code": "UNKNOWN_ERROR", "error_message": "kucoin requires \\"password\\" credential", "subaccount_id": 14, "subaccount_name": "KCSYieldOptimizer", "response_time_ms": 2360}, {"status": "error", "exchange": "kucoin", "error_code": "UNKNOWN_ERROR", "error_message": "kucoin requires \\"password\\" credential", "subaccount_id": 15, "subaccount_name": "BotDeploymentLab", "response_time_ms": 1851}], "total_subaccounts": 18, "total_response_time_ms": 53344}	f	2026-03-20 15:38:27.704972+03
7	cex_connection_check	warning	\N	CEX connection check: 7/18 successful	{"failed": 11, "successful": 7, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774010647416}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 409}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774010647845}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 427}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774010648283}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 447}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774010648722}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 439}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 1, "subaccount_name": "AlphaTradingStrategy", "response_time_ms": 1065}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 2, "subaccount_name": "LongTermStakingVault", "response_time_ms": 1222}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 3, "subaccount_name": "MarketMakingNode", "response_time_ms": 983}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 4, "subaccount_name": "DefiLiquidityPools", "response_time_ms": 599}, {"status": "error", "exchange": "kucoin", "error_code": "UNKNOWN_ERROR", "error_message": "kucoin requires \\"password\\" credential", "subaccount_id": 13, "subaccount_name": "HiddenGemHunter", "response_time_ms": 1893}, {"status": "error", "exchange": "kucoin", "error_code": "UNKNOWN_ERROR", "error_message": "kucoin requires \\"password\\" credential", "subaccount_id": 14, "subaccount_name": "KCSYieldOptimizer", "response_time_ms": 2153}, {"status": "error", "exchange": "kucoin", "error_code": "UNKNOWN_ERROR", "error_message": "kucoin requires \\"password\\" credential", "subaccount_id": 15, "subaccount_name": "BotDeploymentLab", "response_time_ms": 1768}], "total_subaccounts": 18, "total_response_time_ms": 50687}	f	2026-03-20 15:44:42.532853+03
8	cex_connection_check	warning	\N	CEX connection check: 10/18 successful	{"failed": 8, "successful": 10, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011293709}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 421}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011294140}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 439}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011294566}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 417}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011294978}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 412}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 1, "subaccount_name": "AlphaTradingStrategy", "response_time_ms": 648}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 2, "subaccount_name": "LongTermStakingVault", "response_time_ms": 1216}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 3, "subaccount_name": "MarketMakingNode", "response_time_ms": 1248}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 4, "subaccount_name": "DefiLiquidityPools", "response_time_ms": 611}], "total_subaccounts": 18, "total_response_time_ms": 56556}	f	2026-03-20 15:55:33.583395+03
9	cex_connection_check	warning	\N	CEX connection check: 10/18 successful	{"failed": 8, "successful": 10, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011386401}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 436}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011386847}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 435}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011387268}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 421}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011387667}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 398}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 1, "subaccount_name": "AlphaTradingStrategy", "response_time_ms": 563}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 2, "subaccount_name": "LongTermStakingVault", "response_time_ms": 1247}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 3, "subaccount_name": "MarketMakingNode", "response_time_ms": 853}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 4, "subaccount_name": "DefiLiquidityPools", "response_time_ms": 1223}], "total_subaccounts": 18, "total_response_time_ms": 55835}	f	2026-03-20 15:57:06.461859+03
10	cex_connection_check	warning	\N	CEX connection check: 10/18 successful	{"failed": 8, "successful": 10, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011489858}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 415}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011490277}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 410}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011490705}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 437}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011491139}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 421}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 1, "subaccount_name": "AlphaTradingStrategy", "response_time_ms": 1256}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 2, "subaccount_name": "LongTermStakingVault", "response_time_ms": 661}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 3, "subaccount_name": "MarketMakingNode", "response_time_ms": 1645}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 4, "subaccount_name": "DefiLiquidityPools", "response_time_ms": 1003}], "total_subaccounts": 18, "total_response_time_ms": 56944}	f	2026-03-20 15:58:50.450425+03
11	cex_connection_check	warning	\N	CEX connection check: 10/18 successful	{"failed": 8, "successful": 10, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011630389}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 424}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011630798}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 418}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011631197}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 388}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011631617}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 429}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 1, "subaccount_name": "AlphaTradingStrategy", "response_time_ms": 1072}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 2, "subaccount_name": "LongTermStakingVault", "response_time_ms": 589}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 3, "subaccount_name": "MarketMakingNode", "response_time_ms": 574}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 4, "subaccount_name": "DefiLiquidityPools", "response_time_ms": 581}], "total_subaccounts": 18, "total_response_time_ms": 54380}	f	2026-03-20 16:01:08.335072+03
12	cex_connection_check	warning	\N	CEX connection check: 14/18 successful	{"failed": 4, "successful": 14, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011765431}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 424}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011765847}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 404}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011766254}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 409}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011766632}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 377}], "total_subaccounts": 18, "total_response_time_ms": 51183}	f	2026-03-20 16:03:20.848054+03
13	cex_connection_check	warning	\N	CEX connection check: 14/18 successful	{"failed": 4, "successful": 14, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011856899}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 429}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011857293}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 393}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011857686}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 391}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774011858090}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 413}], "total_subaccounts": 18, "total_response_time_ms": 51729}	f	2026-03-20 16:04:53.915545+03
14	cex_connection_check	warning	\N	CEX connection check: 14/18 successful	{"failed": 4, "successful": 14, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774024153033}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 395}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774024153431}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 399}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774024153830}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 407}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774024154220}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 381}], "total_subaccounts": 18, "total_response_time_ms": 51143}	f	2026-03-20 19:29:49.150843+03
15	cex_connection_check	warning	\N	CEX connection check: 14/18 successful	{"failed": 4, "successful": 14, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774024264269}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 409}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774024264642}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 375}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774024265057}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 413}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774024265446}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 390}], "total_subaccounts": 18, "total_response_time_ms": 50289}	f	2026-03-20 19:31:39.272723+03
16	cex_connection_check	warning	\N	CEX connection check: 14/18 successful	{"failed": 4, "successful": 14, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774025179377}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 425}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774025179762}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 391}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774025180169}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 396}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774025180583}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 416}], "total_subaccounts": 18, "total_response_time_ms": 52445}	f	2026-03-20 19:46:55.939889+03
17	cex_connection_check	warning	\N	CEX connection check: 14/18 successful	{"failed": 4, "successful": 14, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774025318339}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 380}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774025318739}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 400}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774025319134}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 394}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774025319556}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 422}], "total_subaccounts": 18, "total_response_time_ms": 51798}	f	2026-03-20 19:49:14.151959+03
18	cex_connection_check	warning	\N	CEX connection check: 14/18 successful	{"failed": 4, "successful": 14, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774026210167}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 413}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774026210564}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 398}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774026210964}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 399}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774026211353}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 388}], "total_subaccounts": 18, "total_response_time_ms": 50226}	f	2026-03-20 20:04:05.354347+03
19	cex_connection_check	warning	\N	CEX connection check: 14/18 successful	{"failed": 4, "successful": 14, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774027248650}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 404}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774027249066}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 416}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774027249463}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 396}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774027249896}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 438}], "total_subaccounts": 18, "total_response_time_ms": 51979}	f	2026-03-20 20:21:24.743143+03
20	cex_connection_check	warning	\N	CEX connection check: 14/18 successful	{"failed": 4, "successful": 14, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774027578896}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 414}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774027579317}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 420}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774027579719}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 393}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774027580113}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 390}], "total_subaccounts": 18, "total_response_time_ms": 53162}	f	2026-03-20 20:26:56.15744+03
21	cex_connection_check	warning	\N	CEX connection check: 14/18 successful	{"failed": 4, "successful": 14, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774028383681}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 399}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774028384070}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 388}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774028384475}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 396}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774028384858}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 381}], "total_subaccounts": 18, "total_response_time_ms": 53909}	f	2026-03-20 20:40:21.417405+03
22	cex_connection_check	warning	\N	CEX connection check: 14/18 successful	{"failed": 4, "successful": 14, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774028675949}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 407}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774028676354}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 394}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774028676734}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 397}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774028677158}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 407}], "total_subaccounts": 18, "total_response_time_ms": 51572}	f	2026-03-20 20:45:11.668088+03
23	cex_connection_check	warning	\N	CEX connection check: 14/18 successful	{"failed": 4, "successful": 14, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774107959375}", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 412}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774107959768}", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 393}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774107960178}", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 409}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "bybit private api uses /user/v3/private/query-api to check if you have a unified account. The API key of user id must own one of permissions: \\"Account Transfer\\", \\"Subaccount Transfer\\", \\"Withdrawal\\" {\\"retCode\\":10005,\\"retMsg\\":\\"Permission denied, please check your API key permissions.\\",\\"result\\":{},\\"retExtInfo\\":{},\\"time\\":1774107960590}", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 411}], "total_subaccounts": 18, "total_response_time_ms": 53457}	f	2026-03-21 18:46:36.704099+03
24	cex_connection_check	warning	\N	CEX connection check: 10/18 successful	{"failed": 8, "successful": 10, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "UNKNOWN_ERROR", "error_message": "'BybitDirectClient' object has no attribute 'fetch_balance'", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 688}, {"status": "error", "exchange": "bybit", "error_code": "UNKNOWN_ERROR", "error_message": "'BybitDirectClient' object has no attribute 'fetch_balance'", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 652}, {"status": "error", "exchange": "bybit", "error_code": "UNKNOWN_ERROR", "error_message": "'BybitDirectClient' object has no attribute 'fetch_balance'", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 625}, {"status": "error", "exchange": "bybit", "error_code": "UNKNOWN_ERROR", "error_message": "'BybitDirectClient' object has no attribute 'fetch_balance'", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 639}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 1, "subaccount_name": "AlphaTradingStrategy", "response_time_ms": 1317}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 2, "subaccount_name": "LongTermStakingVault", "response_time_ms": 595}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 3, "subaccount_name": "MarketMakingNode", "response_time_ms": 1890}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 4, "subaccount_name": "DefiLiquidityPools", "response_time_ms": 1040}], "total_subaccounts": 18, "total_response_time_ms": 53549}	f	2026-03-21 18:50:47.663174+03
25	cex_connection_check	warning	\N	CEX connection check: 10/18 successful	{"failed": 8, "successful": 10, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "UNKNOWN_ERROR", "error_message": "'BybitDirectClient' object has no attribute 'fetch_balance'", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 709}, {"status": "error", "exchange": "bybit", "error_code": "UNKNOWN_ERROR", "error_message": "'BybitDirectClient' object has no attribute 'fetch_balance'", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 687}, {"status": "error", "exchange": "bybit", "error_code": "UNKNOWN_ERROR", "error_message": "'BybitDirectClient' object has no attribute 'fetch_balance'", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 627}, {"status": "error", "exchange": "bybit", "error_code": "UNKNOWN_ERROR", "error_message": "'BybitDirectClient' object has no attribute 'fetch_balance'", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 613}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 1, "subaccount_name": "AlphaTradingStrategy", "response_time_ms": 991}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 2, "subaccount_name": "LongTermStakingVault", "response_time_ms": 618}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 3, "subaccount_name": "MarketMakingNode", "response_time_ms": 647}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 4, "subaccount_name": "DefiLiquidityPools", "response_time_ms": 838}], "total_subaccounts": 18, "total_response_time_ms": 53395}	f	2026-03-21 18:52:01.036525+03
26	cex_connection_check	warning	\N	CEX connection check: 10/18 successful	{"failed": 8, "successful": 10, "failed_exchanges": [{"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "Bybit API error: Permission denied, please check your API key permissions. (code: 10005)", "subaccount_id": 9, "subaccount_name": "BybitScalpMaster", "response_time_ms": 454}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "Bybit API error: Permission denied, please check your API key permissions. (code: 10005)", "subaccount_id": 10, "subaccount_name": "DeltaNeutralTrade", "response_time_ms": 462}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "Bybit API error: Permission denied, please check your API key permissions. (code: 10005)", "subaccount_id": 11, "subaccount_name": "GlobalAssetManage", "response_time_ms": 513}, {"status": "error", "exchange": "bybit", "error_code": "PERMISSION_DENIED", "error_message": "Bybit API error: Permission denied, please check your API key permissions. (code: 10005)", "subaccount_id": 12, "subaccount_name": "RiskControlAccount", "response_time_ms": 400}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 1, "subaccount_name": "AlphaTradingStrategy", "response_time_ms": 1926}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 2, "subaccount_name": "LongTermStakingVault", "response_time_ms": 2075}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 3, "subaccount_name": "MarketMakingNode", "response_time_ms": 613}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 4, "subaccount_name": "DefiLiquidityPools", "response_time_ms": 617}], "total_subaccounts": 18, "total_response_time_ms": 55832}	f	2026-03-21 19:04:39.259954+03
27	cex_connection_check	warning	\N	CEX connection check: 14/18 successful	{"failed": 4, "successful": 14, "failed_exchanges": [{"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 1, "subaccount_name": "AlphaTradingStrategy", "response_time_ms": 614}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 2, "subaccount_name": "LongTermStakingVault", "response_time_ms": 2622}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 3, "subaccount_name": "MarketMakingNode", "response_time_ms": 624}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 4, "subaccount_name": "DefiLiquidityPools", "response_time_ms": 591}], "total_subaccounts": 18, "total_response_time_ms": 52889}	f	2026-03-21 19:17:42.565251+03
28	cex_connection_check	warning	\N	CEX connection check: 14/18 successful	{"failed": 4, "successful": 14, "failed_exchanges": [{"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 1, "subaccount_name": "AlphaTradingStrategy", "response_time_ms": 1488}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 2, "subaccount_name": "LongTermStakingVault", "response_time_ms": 632}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 3, "subaccount_name": "MarketMakingNode", "response_time_ms": 3125}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 4, "subaccount_name": "DefiLiquidityPools", "response_time_ms": 2174}], "total_subaccounts": 18, "total_response_time_ms": 57652}	f	2026-03-21 19:22:57.923578+03
29	cex_connection_check	warning	\N	CEX connection check: 14/18 successful	{"failed": 4, "successful": 14, "failed_exchanges": [{"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 1, "subaccount_name": "AlphaTradingStrategy", "response_time_ms": 636}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 2, "subaccount_name": "LongTermStakingVault", "response_time_ms": 599}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 3, "subaccount_name": "MarketMakingNode", "response_time_ms": 635}, {"status": "error", "exchange": "okx", "error_code": "UNKNOWN_ERROR", "error_message": "unsupported operand type(s) for +: 'NoneType' and 'str'", "subaccount_id": 4, "subaccount_name": "DefiLiquidityPools", "response_time_ms": 588}], "total_subaccounts": 18, "total_response_time_ms": 55290}	f	2026-03-21 19:25:17.21937+03
30	cex_connection_check	info	\N	CEX connection check: 18/18 successful	{"failed": 0, "successful": 18, "failed_exchanges": [], "total_subaccounts": 18, "total_response_time_ms": 78380}	f	2026-03-21 19:27:47.138431+03
31	cex_connection_check	info	\N	CEX connection check: 18/18 successful	{"failed": 0, "successful": 18, "failed_exchanges": [], "total_subaccounts": 18, "total_response_time_ms": 52235}	f	2026-03-21 19:29:03.968789+03
32	panic_mode_activated	critical	\N	PANIC MODE activated by user None	{"telegram_user_id": 8276377751}	f	2026-03-29 18:50:22.641538+03
33	panic_mode_deactivated	info	telegram_bot	System resumed by None	\N	f	2026-03-29 18:50:31.544846+03
\.


--
-- Data for Name: system_state; Type: TABLE DATA; Schema: public; Owner: farming_user
--

COPY public.system_state (key, value, updated_at, updated_by, metadata) FROM stdin;
maintenance_mode	f	2026-03-25 20:31:29.672189+03	system	\N
panic_mode	f	2026-03-29 18:50:31.541666+03	telegram:None	\N
\.


--
-- Data for Name: token_check_cache; Type: TABLE DATA; Schema: public; Owner: farming_user
--

COPY public.token_check_cache (protocol_name, has_token, ticker, market_cap_usd, checked_at, source) FROM stdin;
\.


--
-- Data for Name: wallet_personas; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wallet_personas (id, wallet_id, persona_type, preferred_hours, tx_per_week_mean, tx_per_week_stddev, skip_week_probability, tx_weight_swap, tx_weight_bridge, tx_weight_liquidity, tx_weight_stake, tx_weight_nft, slippage_tolerance, gas_preference, gas_preference_weights, amount_noise_pct, time_noise_minutes, created_at, updated_at) FROM stdin;
107	69	NFTCollector	{3,19,2,18,15,22}	1.00	0.50	0.17	0.31	0.16	0.12	0.14	0.27	1.02	slow	{"fast": 0.1628, "slow": 0.3808, "normal": 0.4564}	0.05	10	2026-03-06 14:03:50.97751+03	2026-03-06 14:03:50.97751+03
108	70	CasualUser	{13,21,9,19,17,10,12,15,11,18,14}	2.50	0.80	0.10	0.41	0.25	0.18	0.11	0.05	0.67	slow	{"fast": 0.1437, "slow": 0.3596, "normal": 0.4967}	0.05	10	2026-03-06 14:03:50.984537+03	2026-03-06 14:03:50.984537+03
109	71	ActiveTrader	{17,18,23,10,16,12,22,19,11,21,13,20,14,15}	4.50	1.20	0.04	0.42	0.23	0.20	0.10	0.05	0.53	normal	{"fast": 0.1478, "slow": 0.4197, "normal": 0.4325}	0.05	10	2026-03-06 14:03:50.98717+03	2026-03-06 14:03:50.98717+03
110	72	Governance	{10,16,15}	2.50	0.80	0.29	0.32	0.18	0.15	0.31	0.05	0.60	normal	{"fast": 0.1578, "slow": 0.3723, "normal": 0.4699}	0.05	10	2026-03-06 14:03:50.989511+03	2026-03-06 14:03:50.989511+03
111	73	MorningTrader	{7,9,6,11,8,12,10}	2.50	0.80	0.11	0.41	0.24	0.18	0.11	0.05	0.57	normal	{"fast": 0.1388, "slow": 0.4187, "normal": 0.4426}	0.05	10	2026-03-06 14:03:50.991805+03	2026-03-06 14:03:50.991805+03
112	74	NightOwl	{22,0,2,23,21,20,1}	2.50	0.80	0.05	0.40	0.24	0.20	0.10	0.06	0.67	slow	{"fast": 0.1584, "slow": 0.3608, "normal": 0.4808}	0.05	10	2026-03-06 14:03:50.994418+03	2026-03-06 14:03:50.994418+03
113	75	BridgeMaxi	{20,23,19,14,17,12,10}	1.00	0.50	0.12	0.20	0.51	0.15	0.09	0.05	1.06	normal	{"fast": 0.139, "slow": 0.4072, "normal": 0.4538}	0.05	10	2026-03-06 14:03:50.996868+03	2026-03-06 14:03:50.996868+03
114	76	WeekendWarrior	{13,8,15,9,14,11,20,17,16}	2.50	0.80	0.12	0.45	0.23	0.18	0.09	0.05	0.67	normal	{"fast": 0.1369, "slow": 0.3834, "normal": 0.4797}	0.05	10	2026-03-06 14:03:50.999244+03	2026-03-06 14:03:50.999244+03
115	77	Ghost	{1,3,15}	1.00	0.50	0.20	0.41	0.24	0.20	0.10	0.05	0.93	fast	{"fast": 0.1596, "slow": 0.3885, "normal": 0.4519}	0.05	10	2026-03-06 14:03:51.002705+03	2026-03-06 14:03:51.002705+03
116	78	Governance	{23,19,12}	4.50	1.20	0.27	0.32	0.19	0.15	0.29	0.05	0.55	slow	{"fast": 0.1297, "slow": 0.4162, "normal": 0.454}	0.05	10	2026-03-06 14:03:51.005815+03	2026-03-06 14:03:51.005815+03
117	79	CasualUser	{19,3,15,18,16,17,0,1,23,14,21}	1.00	0.50	0.12	0.39	0.25	0.19	0.13	0.05	1.03	fast	{"fast": 0.1508, "slow": 0.3795, "normal": 0.4697}	0.05	10	2026-03-06 14:03:51.008631+03	2026-03-06 14:03:51.008631+03
118	80	MonthlyActive	{10,20,23,13,19}	0.50	0.20	0.76	0.39	0.26	0.21	0.10	0.04	0.97	fast	{"fast": 0.1404, "slow": 0.3779, "normal": 0.4816}	0.05	10	2026-03-06 14:03:51.011563+03	2026-03-06 14:03:51.011563+03
119	81	WeekdayOnly	{20,21,19,11,18,17}	2.50	0.80	0.15	0.43	0.23	0.20	0.09	0.04	0.69	normal	{"fast": 0.1403, "slow": 0.4253, "normal": 0.4344}	0.05	10	2026-03-06 14:03:51.017366+03	2026-03-06 14:03:51.017366+03
120	82	NightOwl	{5,2,6,3,1,7,4}	2.50	0.80	0.11	0.37	0.26	0.20	0.12	0.05	0.63	slow	{"fast": 0.1634, "slow": 0.3764, "normal": 0.4602}	0.05	10	2026-03-06 14:03:51.01984+03	2026-03-06 14:03:51.01984+03
121	83	NightOwl	{7,2,3,5,4,1,6}	4.50	1.20	0.11	0.36	0.28	0.19	0.11	0.05	0.47	slow	{"fast": 0.1634, "slow": 0.3966, "normal": 0.44}	0.05	10	2026-03-06 14:03:51.022508+03	2026-03-06 14:03:51.022508+03
122	84	MonthlyActive	{2,0,19,18}	0.80	0.30	0.70	0.44	0.22	0.19	0.11	0.05	0.77	slow	{"fast": 0.1677, "slow": 0.3988, "normal": 0.4335}	0.05	10	2026-03-06 14:03:51.025119+03	2026-03-06 14:03:51.025119+03
123	85	DeFiDegen	{15,11,14,10,20,17,18,16,21,19,22,23,12,13}	2.50	0.80	0.04	0.16	0.09	0.52	0.18	0.05	0.58	normal	{"fast": 0.1592, "slow": 0.3883, "normal": 0.4525}	0.05	10	2026-03-06 14:03:51.027293+03	2026-03-06 14:03:51.027293+03
124	86	Ghost	{16,22,18,12,15}	2.50	0.80	0.27	0.44	0.21	0.20	0.10	0.05	0.55	normal	{"fast": 0.1439, "slow": 0.4008, "normal": 0.4553}	0.05	10	2026-03-06 14:03:51.029705+03	2026-03-06 14:03:51.029705+03
125	87	WeekendWarrior	{15,10,8,19,20,16,21,11}	1.00	0.50	0.14	0.37	0.26	0.22	0.10	0.05	0.90	slow	{"fast": 0.1504, "slow": 0.3982, "normal": 0.4514}	0.05	10	2026-03-06 14:03:51.031896+03	2026-03-06 14:03:51.031896+03
126	88	MonthlyActive	{14,17,23,12,21}	0.80	0.30	0.79	0.38	0.26	0.20	0.11	0.05	0.78	normal	{"fast": 0.1536, "slow": 0.3859, "normal": 0.4606}	0.05	10	2026-03-06 14:03:51.035391+03	2026-03-06 14:03:51.035391+03
127	89	NFTCollector	{17,11,12,9,19,13,8,15,10}	1.00	0.50	0.17	0.32	0.13	0.10	0.17	0.28	0.89	normal	{"fast": 0.1641, "slow": 0.397, "normal": 0.439}	0.05	10	2026-03-06 14:03:51.0389+03	2026-03-06 14:03:51.0389+03
128	90	BridgeMaxi	{13,17,9,19,15,21,11}	2.50	0.80	0.12	0.23	0.46	0.16	0.11	0.05	0.61	normal	{"fast": 0.1462, "slow": 0.3954, "normal": 0.4584}	0.05	10	2026-03-06 14:03:51.042033+03	2026-03-06 14:03:51.042033+03
129	91	WeekdayOnly	{23,20,0,14,16,22}	1.00	0.50	0.14	0.41	0.24	0.20	0.10	0.05	0.97	slow	{"fast": 0.1704, "slow": 0.366, "normal": 0.4636}	0.05	10	2026-03-06 14:03:51.045414+03	2026-03-06 14:03:51.045414+03
130	92	CasualUser	{11,12,15,21,10,19,18,20,13}	2.50	0.80	0.07	0.43	0.25	0.17	0.09	0.06	0.78	fast	{"fast": 0.1471, "slow": 0.4275, "normal": 0.4254}	0.05	10	2026-03-06 14:03:51.048952+03	2026-03-06 14:03:51.048952+03
131	93	WeekdayOnly	{19,22,13,20,15,18,12,17,23,11}	2.50	0.80	0.20	0.38	0.26	0.22	0.10	0.04	0.76	slow	{"fast": 0.1596, "slow": 0.4018, "normal": 0.4386}	0.05	10	2026-03-06 14:03:51.052277+03	2026-03-06 14:03:51.052277+03
132	94	MorningTrader	{15,13,12,11,17,16,14}	1.00	0.50	0.12	0.38	0.27	0.20	0.10	0.05	0.94	slow	{"fast": 0.1596, "slow": 0.4008, "normal": 0.4396}	0.05	10	2026-03-06 14:03:51.05525+03	2026-03-06 14:03:51.05525+03
133	95	Ghost	{16,11,21,13}	2.50	0.80	0.29	0.41	0.25	0.19	0.11	0.04	0.64	fast	{"fast": 0.141, "slow": 0.3999, "normal": 0.4591}	0.05	10	2026-03-06 14:03:51.057779+03	2026-03-06 14:03:51.057779+03
134	96	NFTCollector	{10,17,12,14,19,18,15}	1.00	0.50	0.11	0.31	0.13	0.09	0.16	0.31	1.09	slow	{"fast": 0.1418, "slow": 0.4222, "normal": 0.436}	0.05	10	2026-03-06 14:03:51.060623+03	2026-03-06 14:03:51.060623+03
135	97	MonthlyActive	{14,21,23,13,18}	0.80	0.30	0.65	0.38	0.24	0.22	0.10	0.05	0.75	normal	{"fast": 0.1384, "slow": 0.38, "normal": 0.4816}	0.05	10	2026-03-06 14:03:51.063995+03	2026-03-06 14:03:51.063995+03
136	98	BridgeMaxi	{14,18,16,17,19,20,2}	1.00	0.50	0.12	0.21	0.48	0.16	0.10	0.05	0.94	normal	{"fast": 0.1592, "slow": 0.3942, "normal": 0.4466}	0.05	10	2026-03-06 14:03:51.067436+03	2026-03-06 14:03:51.067436+03
137	99	CasualUser	{14,17,12,21,19,20,16,15}	2.50	0.80	0.13	0.40	0.25	0.20	0.10	0.05	0.67	slow	{"fast": 0.1442, "slow": 0.4084, "normal": 0.4474}	0.05	10	2026-03-06 14:03:51.070899+03	2026-03-06 14:03:51.070899+03
138	100	NightOwl	{21,22,19,1,23,20,0}	2.50	0.80	0.05	0.42	0.24	0.18	0.11	0.05	0.80	slow	{"fast": 0.1426, "slow": 0.4024, "normal": 0.455}	0.05	10	2026-03-06 14:03:51.074813+03	2026-03-06 14:03:51.074813+03
139	101	ActiveTrader	{10,17,19,12,22,14,18,13,20,23,16,21,15,11}	1.00	0.50	0.02	0.42	0.24	0.20	0.10	0.05	0.94	slow	{"fast": 0.1421, "slow": 0.3946, "normal": 0.4632}	0.05	10	2026-03-06 14:03:51.077818+03	2026-03-06 14:03:51.077818+03
140	102	Ghost	{19,21,12,10,14}	2.50	0.80	0.23	0.39	0.25	0.20	0.11	0.05	0.63	slow	{"fast": 0.1546, "slow": 0.3898, "normal": 0.4556}	0.05	10	2026-03-06 14:03:51.080603+03	2026-03-06 14:03:51.080603+03
141	103	MonthlyActive	{15,19,18,10,16,8}	0.80	0.30	0.85	0.41	0.25	0.21	0.08	0.04	0.54	normal	{"fast": 0.1487, "slow": 0.3706, "normal": 0.4807}	0.05	10	2026-03-06 14:03:51.083284+03	2026-03-06 14:03:51.083284+03
142	104	MonthlyActive	{20,23,10}	0.80	0.30	0.72	0.36	0.28	0.22	0.09	0.05	0.67	normal	{"fast": 0.1467, "slow": 0.3663, "normal": 0.487}	0.05	10	2026-03-06 14:03:51.086829+03	2026-03-06 14:03:51.086829+03
143	105	WeekendWarrior	{11,14,18,17,19,16,20,10,21}	4.50	1.20	0.16	0.42	0.23	0.20	0.10	0.05	0.52	normal	{"fast": 0.151, "slow": 0.4089, "normal": 0.4401}	0.05	10	2026-03-06 14:03:51.089345+03	2026-03-06 14:03:51.089345+03
144	106	DeFiDegen	{19,16,12,14,17,15,18,8,9,21,13,20,11,10}	2.50	0.80	0.03	0.16	0.10	0.48	0.21	0.05	0.65	slow	{"fast": 0.1463, "slow": 0.425, "normal": 0.4286}	0.05	10	2026-03-06 14:03:51.092496+03	2026-03-06 14:03:51.092496+03
145	107	ActiveTrader	{15,1,20,2,22,17,19,18,14,16,23,0,3,21}	2.50	0.80	0.04	0.39	0.23	0.21	0.11	0.06	0.55	fast	{"fast": 0.1445, "slow": 0.4104, "normal": 0.4451}	0.05	10	2026-03-06 14:03:51.095367+03	2026-03-06 14:03:51.095367+03
146	108	WeekendWarrior	{20,19,15,17,13,14,21}	2.50	0.80	0.16	0.42	0.26	0.20	0.08	0.04	0.77	fast	{"fast": 0.1676, "slow": 0.4059, "normal": 0.4265}	0.05	10	2026-03-06 14:03:51.099613+03	2026-03-06 14:03:51.099613+03
147	109	NFTCollector	{19,17,13,21,18,20,11,14,12,10}	1.00	0.50	0.19	0.32	0.13	0.10	0.16	0.30	0.81	slow	{"fast": 0.1655, "slow": 0.38, "normal": 0.4545}	0.05	10	2026-03-06 14:03:51.103359+03	2026-03-06 14:03:51.103359+03
148	110	MonthlyActive	{2,1,14,18,0}	1.50	0.50	0.76	0.41	0.24	0.19	0.11	0.05	0.44	slow	{"fast": 0.1552, "slow": 0.4058, "normal": 0.4389}	0.05	10	2026-03-06 14:03:51.10733+03	2026-03-06 14:03:51.10733+03
149	111	BridgeMaxi	{14,8,16,13,9,10}	1.00	0.50	0.12	0.20	0.48	0.17	0.10	0.05	0.86	normal	{"fast": 0.1582, "slow": 0.3708, "normal": 0.471}	0.05	10	2026-03-06 14:03:51.110602+03	2026-03-06 14:03:51.110602+03
150	112	WeekdayOnly	{16,19,11,12,22,23,20,18,10,15}	1.00	0.50	0.12	0.41	0.26	0.17	0.10	0.05	0.97	slow	{"fast": 0.152, "slow": 0.3872, "normal": 0.4608}	0.05	10	2026-03-06 14:03:51.113786+03	2026-03-06 14:03:51.113786+03
151	113	Governance	{12,11,21}	1.00	0.50	0.21	0.28	0.20	0.16	0.30	0.05	0.82	fast	{"fast": 0.1542, "slow": 0.4197, "normal": 0.426}	0.05	10	2026-03-06 14:03:51.11633+03	2026-03-06 14:03:51.11633+03
152	114	ActiveTrader	{16,14,13,15,17,21,23,19,22,10,20,12,11,18}	1.00	0.50	0.04	0.38	0.28	0.19	0.10	0.06	0.86	normal	{"fast": 0.1557, "slow": 0.4131, "normal": 0.4312}	0.05	10	2026-03-06 14:03:51.11878+03	2026-03-06 14:03:51.11878+03
153	115	Ghost	{20,9,13}	1.00	0.50	0.29	0.40	0.24	0.22	0.10	0.05	0.95	slow	{"fast": 0.1564, "slow": 0.4227, "normal": 0.4209}	0.05	10	2026-03-06 14:03:51.121168+03	2026-03-06 14:03:51.121168+03
154	116	Governance	{22,15,21,0,20,18}	4.50	1.20	0.28	0.31	0.20	0.15	0.30	0.04	0.54	slow	{"fast": 0.156, "slow": 0.3832, "normal": 0.4608}	0.05	10	2026-03-06 14:03:51.123526+03	2026-03-06 14:03:51.123526+03
155	117	DeFiDegen	{16,14,15,9,13,8,12,11,20,17,19,10,21,18}	2.50	0.80	0.04	0.15	0.11	0.47	0.21	0.06	0.68	normal	{"fast": 0.1466, "slow": 0.3926, "normal": 0.4608}	0.05	10	2026-03-06 14:03:51.125983+03	2026-03-06 14:03:51.125983+03
156	118	WeekdayOnly	{14,20,12,10,17,8}	2.50	0.80	0.10	0.41	0.24	0.19	0.10	0.06	0.78	normal	{"fast": 0.152, "slow": 0.3774, "normal": 0.4706}	0.05	10	2026-03-06 14:03:51.128217+03	2026-03-06 14:03:51.128217+03
157	119	MorningTrader	{11,13,12,15,16,14,17}	4.50	1.20	0.14	0.38	0.26	0.19	0.11	0.06	0.40	slow	{"fast": 0.1499, "slow": 0.4021, "normal": 0.448}	0.05	10	2026-03-06 14:03:51.130589+03	2026-03-06 14:03:51.130589+03
158	120	Ghost	{2,17,18,21,3,15,1}	4.50	1.20	0.30	0.46	0.21	0.19	0.10	0.04	0.44	slow	{"fast": 0.1408, "slow": 0.3915, "normal": 0.4677}	0.05	10	2026-03-06 14:03:51.132827+03	2026-03-06 14:03:51.132827+03
159	121	NFTCollector	{11,21,20,17,10,19,18}	4.50	1.20	0.17	0.28	0.14	0.10	0.14	0.34	0.40	normal	{"fast": 0.1466, "slow": 0.3916, "normal": 0.4619}	0.05	10	2026-03-06 14:03:51.135622+03	2026-03-06 14:03:51.135622+03
160	122	WeekendWarrior	{20,15,23,17,22,21,16}	4.50	1.20	0.17	0.39	0.28	0.17	0.10	0.05	0.39	fast	{"fast": 0.1361, "slow": 0.4164, "normal": 0.4475}	0.05	10	2026-03-06 14:03:51.138359+03	2026-03-06 14:03:51.138359+03
161	123	Governance	{18,23,16}	1.00	0.50	0.25	0.30	0.20	0.17	0.29	0.05	0.84	fast	{"fast": 0.1583, "slow": 0.4319, "normal": 0.4099}	0.05	10	2026-03-06 14:03:51.140948+03	2026-03-06 14:03:51.140948+03
162	124	Ghost	{14,12,18,15,23,11}	2.50	0.80	0.28	0.37	0.24	0.23	0.11	0.05	0.72	slow	{"fast": 0.1571, "slow": 0.3925, "normal": 0.4504}	0.05	10	2026-03-06 14:03:51.143327+03	2026-03-06 14:03:51.143327+03
163	125	Ghost	{21,18,10,11,13}	2.50	0.80	0.26	0.43	0.25	0.17	0.10	0.05	0.61	fast	{"fast": 0.1411, "slow": 0.4326, "normal": 0.4263}	0.05	10	2026-03-06 14:03:51.146097+03	2026-03-06 14:03:51.146097+03
164	126	Ghost	{19,18,20}	1.00	0.50	0.26	0.41	0.25	0.19	0.10	0.04	0.71	slow	{"fast": 0.1575, "slow": 0.4101, "normal": 0.4324}	0.05	10	2026-03-06 14:03:51.148348+03	2026-03-06 14:03:51.148348+03
165	127	NightOwl	{4,3,6,1,2,5,7}	2.50	0.80	0.06	0.41	0.25	0.18	0.11	0.05	0.57	normal	{"fast": 0.1341, "slow": 0.3918, "normal": 0.4741}	0.05	10	2026-03-06 14:03:51.150594+03	2026-03-06 14:03:51.150594+03
166	128	BridgeMaxi	{15,11,21,22,12,20,14,17,10,19}	2.50	0.80	0.10	0.19	0.52	0.14	0.10	0.05	0.63	normal	{"fast": 0.1571, "slow": 0.3904, "normal": 0.4525}	0.05	10	2026-03-06 14:03:51.152894+03	2026-03-06 14:03:51.152894+03
167	129	MorningTrader	{10,11,6,5,9,7,8}	1.00	0.50	0.09	0.41	0.21	0.21	0.11	0.06	0.75	normal	{"fast": 0.1367, "slow": 0.3842, "normal": 0.479}	0.05	10	2026-03-06 14:03:51.155488+03	2026-03-06 14:03:51.155488+03
168	130	BridgeMaxi	{20,22,3,21,19,0,15}	2.50	0.80	0.09	0.22	0.49	0.14	0.10	0.05	0.69	normal	{"fast": 0.1546, "slow": 0.3771, "normal": 0.4683}	0.05	10	2026-03-06 14:03:51.15823+03	2026-03-06 14:03:51.15823+03
169	131	Governance	{18,11,17,14}	2.50	0.80	0.25	0.30	0.18	0.13	0.35	0.04	0.74	normal	{"fast": 0.1383, "slow": 0.4125, "normal": 0.4492}	0.05	10	2026-03-06 14:03:51.160837+03	2026-03-06 14:03:51.160837+03
170	132	NightOwl	{1,7,4,6,5,2,3}	2.50	0.80	0.10	0.38	0.25	0.21	0.10	0.05	0.71	normal	{"fast": 0.1453, "slow": 0.4059, "normal": 0.4488}	0.05	10	2026-03-06 14:03:51.163554+03	2026-03-06 14:03:51.163554+03
171	133	CasualUser	{14,23,16,0,22,15,2,1,17,3}	1.00	0.50	0.05	0.38	0.27	0.21	0.08	0.05	0.93	normal	{"fast": 0.1385, "slow": 0.4162, "normal": 0.4453}	0.05	10	2026-03-06 14:03:51.166454+03	2026-03-06 14:03:51.166454+03
172	134	Governance	{21,16,18,23,11,10,17}	4.50	1.20	0.26	0.31	0.20	0.14	0.31	0.05	0.39	slow	{"fast": 0.1504, "slow": 0.4107, "normal": 0.4389}	0.05	10	2026-03-06 14:03:51.169216+03	2026-03-06 14:03:51.169216+03
173	135	DeFiDegen	{3,16,20,22,18,2,21,17,1,23,15,14,0,19}	1.00	0.50	0.00	0.15	0.11	0.48	0.21	0.06	0.97	slow	{"fast": 0.1612, "slow": 0.3911, "normal": 0.4477}	0.05	10	2026-03-06 14:03:51.171606+03	2026-03-06 14:03:51.171606+03
174	136	NightOwl	{1,0,19,21,23,20,22}	4.50	1.20	0.09	0.41	0.26	0.18	0.10	0.05	0.51	slow	{"fast": 0.158, "slow": 0.4066, "normal": 0.4354}	0.05	10	2026-03-06 14:03:51.173911+03	2026-03-06 14:03:51.173911+03
175	137	NightOwl	{22,19,23,20,0,1,21}	2.50	0.80	0.11	0.41	0.23	0.22	0.09	0.05	0.81	fast	{"fast": 0.1414, "slow": 0.4043, "normal": 0.4543}	0.05	10	2026-03-06 14:03:51.176238+03	2026-03-06 14:03:51.176238+03
176	138	MorningTrader	{13,15,16,11,14,12,17}	1.00	0.50	0.09	0.38	0.26	0.21	0.11	0.05	0.85	slow	{"fast": 0.1538, "slow": 0.4121, "normal": 0.4341}	0.05	10	2026-03-06 14:03:51.178615+03	2026-03-06 14:03:51.178615+03
177	139	MonthlyActive	{18,10,14}	0.80	0.30	0.71	0.37	0.26	0.21	0.10	0.05	0.65	normal	{"fast": 0.1417, "slow": 0.3963, "normal": 0.462}	0.05	10	2026-03-06 14:03:51.181002+03	2026-03-06 14:03:51.181002+03
178	140	BridgeMaxi	{11,10,16,15,18,13,21,17,8,20}	4.50	1.20	0.08	0.19	0.51	0.16	0.09	0.05	0.41	normal	{"fast": 0.1473, "slow": 0.3967, "normal": 0.4559}	0.05	10	2026-03-06 14:03:51.183411+03	2026-03-06 14:03:51.183411+03
179	141	WeekendWarrior	{20,9,15,10,12,16,17,11,19,13}	4.50	1.20	0.17	0.40	0.26	0.19	0.11	0.05	0.42	fast	{"fast": 0.1475, "slow": 0.4185, "normal": 0.434}	0.05	10	2026-03-06 14:03:51.185989+03	2026-03-06 14:03:51.185989+03
180	142	NightOwl	{7,1,5,6,3,2,4}	2.50	0.80	0.09	0.38	0.25	0.21	0.11	0.05	0.55	slow	{"fast": 0.1305, "slow": 0.4261, "normal": 0.4434}	0.05	10	2026-03-06 14:03:51.188841+03	2026-03-06 14:03:51.188841+03
181	143	BridgeMaxi	{17,3,23,18,1,21,22,20,14,2}	1.00	0.50	0.10	0.18	0.52	0.15	0.10	0.05	0.94	fast	{"fast": 0.1333, "slow": 0.3825, "normal": 0.4842}	0.05	10	2026-03-06 14:03:51.191811+03	2026-03-06 14:03:51.191811+03
182	144	WeekendWarrior	{8,16,20,14,18,11,19}	1.00	0.50	0.13	0.40	0.26	0.18	0.10	0.06	0.91	fast	{"fast": 0.1497, "slow": 0.4197, "normal": 0.4305}	0.05	10	2026-03-06 14:03:51.194596+03	2026-03-06 14:03:51.194596+03
183	145	WeekendWarrior	{17,23,19,21,20,22}	4.50	1.20	0.15	0.41	0.26	0.18	0.09	0.06	0.50	normal	{"fast": 0.1644, "slow": 0.3891, "normal": 0.4465}	0.05	10	2026-03-06 14:03:51.197842+03	2026-03-06 14:03:51.197842+03
184	146	WeekdayOnly	{17,21,0,15,19,3,16,2,20}	1.00	0.50	0.11	0.44	0.22	0.19	0.10	0.05	0.92	normal	{"fast": 0.1317, "slow": 0.4153, "normal": 0.4529}	0.05	10	2026-03-06 14:03:51.200324+03	2026-03-06 14:03:51.200324+03
185	147	BridgeMaxi	{10,12,17,22,16,19,23,20,18}	2.50	0.80	0.08	0.18	0.50	0.17	0.10	0.05	0.81	slow	{"fast": 0.1491, "slow": 0.4026, "normal": 0.4483}	0.05	10	2026-03-06 14:03:51.202784+03	2026-03-06 14:03:51.202784+03
186	148	NightOwl	{0,22,23,21,1,20,19}	2.50	0.80	0.07	0.41	0.22	0.21	0.10	0.05	0.63	fast	{"fast": 0.1485, "slow": 0.341, "normal": 0.5105}	0.05	10	2026-03-06 14:03:51.205847+03	2026-03-06 14:03:51.205847+03
187	149	Governance	{17,9,21,10,8,14}	2.50	0.80	0.27	0.34	0.19	0.13	0.30	0.05	0.68	normal	{"fast": 0.1656, "slow": 0.426, "normal": 0.4083}	0.05	10	2026-03-06 14:03:51.208184+03	2026-03-06 14:03:51.208184+03
188	150	CasualUser	{19,11,17,16,13,10,23,21,20,14,22}	2.50	0.80	0.08	0.35	0.28	0.20	0.12	0.06	0.63	normal	{"fast": 0.1503, "slow": 0.3997, "normal": 0.45}	0.05	10	2026-03-06 14:03:51.210517+03	2026-03-06 14:03:51.210517+03
189	151	WeekendWarrior	{17,23,18,3,1,19,21,15,16}	2.50	0.80	0.16	0.40	0.26	0.19	0.10	0.05	0.84	slow	{"fast": 0.1481, "slow": 0.4386, "normal": 0.4132}	0.05	10	2026-03-06 14:03:51.212947+03	2026-03-06 14:03:51.212947+03
190	152	WeekdayOnly	{19,15,18,16,0,3,17,1}	2.50	0.80	0.13	0.39	0.23	0.22	0.11	0.05	0.77	fast	{"fast": 0.1475, "slow": 0.3834, "normal": 0.4691}	0.05	10	2026-03-06 14:03:51.21536+03	2026-03-06 14:03:51.21536+03
191	153	WeekdayOnly	{16,15,8,14,21,12,9}	4.50	1.20	0.15	0.39	0.25	0.20	0.11	0.05	0.48	normal	{"fast": 0.1375, "slow": 0.4052, "normal": 0.4573}	0.05	10	2026-03-06 14:03:51.217834+03	2026-03-06 14:03:51.217834+03
192	154	Ghost	{21,19,14,16,1}	2.50	0.80	0.24	0.39	0.23	0.22	0.10	0.06	0.54	normal	{"fast": 0.1557, "slow": 0.4004, "normal": 0.4439}	0.05	10	2026-03-06 14:03:51.220387+03	2026-03-06 14:03:51.220387+03
193	155	DeFiDegen	{22,23,20,16,21,15,17,0,18,14,19,3,2,1}	4.50	1.20	0.00	0.15	0.10	0.49	0.21	0.05	0.36	slow	{"fast": 0.1449, "slow": 0.4181, "normal": 0.437}	0.05	10	2026-03-06 14:03:51.222715+03	2026-03-06 14:03:51.222715+03
194	156	BridgeMaxi	{22,15,23,17,21,20}	2.50	0.80	0.08	0.20	0.54	0.12	0.09	0.05	0.65	normal	{"fast": 0.1654, "slow": 0.3655, "normal": 0.4691}	0.05	10	2026-03-06 14:03:51.225239+03	2026-03-06 14:03:51.225239+03
195	157	Governance	{18,13,17,14,19,12,15}	4.50	1.20	0.26	0.30	0.22	0.14	0.29	0.05	0.51	normal	{"fast": 0.1517, "slow": 0.3911, "normal": 0.4572}	0.05	10	2026-03-06 14:03:51.227664+03	2026-03-06 14:03:51.227664+03
196	158	MonthlyActive	{17,13,18,20,11,15,22}	0.80	0.30	0.72	0.43	0.25	0.16	0.10	0.05	0.63	normal	{"fast": 0.1488, "slow": 0.3985, "normal": 0.4527}	0.05	10	2026-03-06 14:03:51.23014+03	2026-03-06 14:03:51.23014+03
\.


--
-- Data for Name: wallet_points_balances; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wallet_points_balances (id, wallet_id, points_program_id, points_amount, last_updated_at) FROM stdin;
\.


--
-- Data for Name: wallet_protocol_assignments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wallet_protocol_assignments (id, wallet_id, protocol_id, assigned_at, interaction_count, last_interaction_at) FROM stdin;
\.


--
-- Data for Name: wallet_tokens; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wallet_tokens (id, wallet_id, chain, token_contract_address, token_symbol, token_name, decimals, balance, balance_human, first_detected_at, last_updated) FROM stdin;
\.


--
-- Data for Name: wallet_transactions; Type: TABLE DATA; Schema: public; Owner: farming_user
--

COPY public.wallet_transactions (id, wallet_id, protocol_action_id, tx_hash, chain, from_address, to_address, value, gas_used, status, block_number, confirmed_at, created_at) FROM stdin;
\.


--
-- Data for Name: wallet_withdrawal_address_history; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wallet_withdrawal_address_history (id, wallet_id, old_address, new_address, changed_by, change_reason, approval_status, approved_by, approved_at, created_at) FROM stdin;
\.


--
-- Data for Name: wallets; Type: TABLE DATA; Schema: public; Owner: farming_user
--

COPY public.wallets (id, address, encrypted_private_key, tier, worker_node_id, proxy_id, status, last_funded_at, first_tx_at, last_tx_at, total_tx_count, openclaw_enabled, post_snapshot_active_until, reputation_score, notes, created_at, updated_at, authorized_withdrawal_address, warmup_status, warmup_completed_at, funding_cex_subaccount_id, funding_network, funding_chain_id, withdrawal_network) FROM stdin;
137	0x1Fe6d9ff0E8DCA86429412b8A23174dFbb6E037B	gAAAAABpnWqdDfuSlIHFdMPoHmB2dthzOl8LnQS_GOTu4nMmdgzcYVy4SqWG4y73DfY53CJDN0aVuvfD6T72SK3g71n6DzSI2cVdvh_KXGhyXMpbvsN0Lox8wBhe0gfG0uGs7DigmEe4kZbr3XbfKaBRHKqphmI9tPyQlE0yMLbma06W0SiKUR0=	B	1	23	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.644683+03	2026-03-12 14:25:34.602336+03	\N	inactive	\N	17	Polygon	85	arbitrum
83	0xF22C7b5E1116975d71E9B7324e56FB1109E91Db3	gAAAAABpnWqdcFev4JHarfek_YV8zOARHte3wifYnpk4NUJYQVzs8UxJcbL71tQPl1eyC9GLfqEPB5a0q72oNdMzJqvnhCdcjlnBFGiWqsOqOMcP9Vy91ABAp0b4NpRWV1yJeg81I6MOUvECHAq2eFDxwEgvxXC_xaESK7qSh2EWpjEqf4tpHXE=	A	1	464	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.359484+03	2026-03-12 14:25:34.602336+03	\N	inactive	\N	5	Ink	91	arbitrum
74	0x75C5499AC72DAeF83364fda275a040D3778Bbf4B	gAAAAABpnWqdG-QWXuhLdUVAFJhzk2AO3EDTxnMtAw_i-BVBCaGK9niqQBOYL349SogcvvKDyO_R1XsdltE13UrmW3KQzB8XrYVSCIpKxw6llwpFGnyMej1FdLrYtCUfeoucc3_hfByNUcQZ_QHAswKCJFcO_bnlcgbBLM6K4G0ZZOXwvBPcb7Y=	B	1	103	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.314331+03	2026-03-12 14:25:34.604915+03	\N	inactive	\N	9	Base	89	base
141	0x164c20DFcba24d3f93F38DE41cbb9f32feb26860	gAAAAABpnWqd2tzEvWD9Azrsrm5rc5zNJjEdp0cMZMrLKQcVRP7hy0sEe2f6YHatSTRrD4FSr8naCD3p_Etci8sCv1wY2Qne1bczVZoN3n5Qw7Rpx_QnWKghGfNjU68D7J3Yfs2ikTR1W-NYC_qMK2w037saLKPiFwae3OZlQGa7B9P7Yuu6wsA=	A	1	2	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.666228+03	2026-03-20 10:47:06.840508+03	\N	inactive	\N	12	BNB Chain	100	bsc
139	0xb37010788E0F951ccc3576Bb185c23AC259becD9	gAAAAABpnWqd2hnSrJ2yOHM8pNYFEaxAXyif-XCdg_RS-__sqwGMXt4oFmslV0Plr3is20Wv_8Qdy2eeFIWnhd2AISUWJaHw8NkRi8PCN8qFWTuepZ3UxwlqTFnwaxt8_KMd_MRUUws6ejHwrP2JEQ2KweHFzUZLHblNQs6eskMx0y0nBmy_NoY=	B	1	9	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.655304+03	2026-03-20 10:47:06.840508+03	\N	inactive	\N	12	BNB Chain	100	base
78	0x2Fde057CbE256c5Cf77a0bF3457fC2fFCA70F043	gAAAAABpnWqdLQwf6LPnPIgtnxH9XiLvgJe3y7-8gJqkBGBaYN-t1BXvHuAdB_EbuC_SmIkv___zm4uZ9sXREiOQZoAFKf4RztW1ZY7ZL7XTA9ML1ulRSaig3YsTxsMhsc4YwWRY84bdGFGLTO_1WZmcb2LN7Pcp8jKiFp1HI3p-9wxOkaPXy9U=	A	1	236	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.334278+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	9	Base	89	arbitrum
86	0x26cd0DD5E268C7069483e8C1a607dC532622d61C	gAAAAABpnWqdXX-7QAwFurRLVfBJKiMXsnk6aCegmwqWEd3A3fKgjmTU-62nx-PhNHAZ6eXpVthys21bt1HEed2uWZ5WcCY7O4FJhWCpmrMx9mIYpubssmS3SeEQcLK5Wbm1cPrf_jjOaAIPWr5Q-3zEDFcZrzN9RcQqJQrmZ39TUGWtpqbaLU8=	B	1	56	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.37395+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	16	Polygon	83	arbitrum
77	0xF35910C057C7663655445cb78d3983A28C188eaE	gAAAAABpnWqde2tP7Jvg_tsy48VSVGYXtOxfJhqh5PiGLNAVEV95USLkHw9f9ASlAZJu7T0tEgK6WEPfledYOYKZ-wZ288US53S1X_HHHCdFQ8Kr4Jh9JFQ7o5diel1tBQLND8bBM7iab4jP2gtMjJ_uKpvo5PvfyeoIhL8peUY6wL007Rzime8=	C	1	450	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.329743+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	4	Polygon	82	arbitrum
71	0x4d03A80E49386c7A3cA82d41bF6641a54627fA2c	gAAAAABpnWqdNXPneM83pCcQWyUfEd1Tv-Eo7KJUPPNe6OpMyveBsw122gAvQNCy2uST12pTpQN7F4goamddrgZbizAnXJ9GjytkIy4IHC_4-Od3zs3-nZnPO2PiYYFascUb23L6yX5rnNJURLLtyLAzppJMAXbI8v7YaSSkOlAovFI0GomsRxY=	A	1	256	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.298692+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	15	BNB Chain	95	arbitrum
92	0xae8BBed706B0db3EAd8DD669Cf8C81bC79cDcCB3	gAAAAABpnWqdvrGkEfoR21Zq3yhccrs9FjaaAcQq9HzS9aIiJZ1Bw-e0G3MV52HEQplZZ8kCQeItSyH6fICth31B7g4FbFiKTqdSn4rkTte2YBjLyappeQ_MtrBaZR-LQ6zGrJF2dkjZrXBPpO0AtsooMjVQ2Z2FFC2Pwfm2PvWNl9ZC6Nw3Z1s=	B	1	196	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.402599+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	9	Base	89	optimism
132	0xFbfD8F8BcE36CB91C97Ba9917a018f9560A6212A	gAAAAABpnWqdkq1TF7ivTnAnPEYmRcQ6A51-LIDxomjQLU2HQF3XYb-Vg6r4AdSmqX-V5byLIS9G0RiPql1XUqBJIceyRobGR1H7RgMzJem94_-b-wtBeuGd_iuhWiBsCNM9NidjVUPBhYjKsAX9J_b9lm5f7O8hiM7Vb_cz5rm4CToGNHBXL44=	B	1	452	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.616926+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	12	BNB Chain	100	optimism
129	0xb7717c2c4fE5363080DDc2408Fd8D2070c58894f	gAAAAABpnWqdkj8PiG5iJuHzaGftlWZA59DI_Pn2v4COaKDxUWQ6r2MIQybEYhrIYEVB8n7ZPUAiuF5L06wUAQbRzue8Fc5N65xx_rr2yxb0lhX4pnlfrB40BqoSXdu_75ihIKhXp8G58YoMIMOE_U6s3ucsnfSt1rAmMEi2PAXFPD9-czjR0nw=	C	1	17	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.601037+03	2026-03-12 14:25:34.608624+03	\N	inactive	\N	9	Base	89	linea
124	0x77eE2026B78f1f92144fC49EE8e5fbA8d6E51d86	gAAAAABpnWqd0QAmLvRkKRfSrfiAZlBQKsSluNjF8N2Q2mT_lDH8BQpMUar-JlfUXEPb3BtGMiO2_DchyE4zLZp3iIajJb-ii4lQkQcRAhIaa9Qkp-vI-8JHe5lPqK082W_-ID6us3E5nNbltNDc-26-SQ0g3O_v3q3OXmPfhLJMSGbSAU-PU3Y=	B	1	60	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.575584+03	2026-03-12 14:25:34.61581+03	\N	inactive	\N	9	Base	89	zksync
80	0xae667016c0663EfcD6e56a0BeD47E9c431119199	gAAAAABpnWqdO2kbu-qlhQYHYrDs_nU2aJUrFoHUQ-08Wwm6rnmsw9yw6C-fbTQSj86QZPnr68H49MGIH6pRguyH_qzDo7YiTQgHvLaHpZrhencbrEcDRijGDSZzPSaOvsz8v36z2qGBNCa5jbPopVXxyDV082q5NDyeu211XPp3VM7N80lGTqg=	C	1	75	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.344364+03	2026-03-12 14:26:04.471649+03	\N	inactive	\N	12	BNB Chain	100	arbitrum_nova
156	0x1D56088663c274eeb5715D764e36fcf4A2b86229	gAAAAABpnWqdO49Hljg-5JzTXs4vdW7-eGnEKWYehx4pQJetcZ_HKtE9AgJcUSmHKlsF0U2EWErZaXqDWg6Ww0mbq1hXG8f92ZfdWYeTLA1xcmDiDVr7SWG6XE_zHqxu4BzM-ZC1VtYjmbwsP2Ot-NdMfbue1niuX6Ie_wi9L81JsPMZUA1xz58=	B	1	65	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.74996+03	2026-03-20 10:47:06.840508+03	\N	inactive	\N	3	Polygon	81	scroll
125	0x9D48d22ab0f8F98E90e8ccDF1CA75d1de6085634	gAAAAABpnWqdK1pdKhUXIRgJRa2692Ns8FZFoMANGpcYpv1tCi6uCn5_aJz8XxIxtXDq5j4k1erLZlkps1EM0PB9Qw3jdt1XQx4MYQA4Hkq_J-E2CT7j72v6E13TZI_CqQfOdTWI7pfvk5rWdbwNOmKxLzDFL1d2o8qSDZd7TP7a0JkxzYHEkLc=	B	1	26	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.581275+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	12	BNB Chain	100	zksync
150	0x79B5cA55590c9268c908190aaa419EA34541e23D	gAAAAABpnWqd2FjMMxHClaH1Ffw0Da3Xj4g9XB-7MWE8p2NpNx4nIJZvraJnTVsFPKwyASMAGeD7T8zuR2sd-Q-j8yHMDcPWxOpYNG9sanMbudwF2RBw-ureGRW01NhksA-CbrQcb1toYtbovDFbK13QfoMG_AyQ58NctLWnzF8QRMHcN1l94Vc=	B	1	80	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.71611+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	16	Polygon	83	optimism
140	0x9c9b6fce5Fe98c578E332A8C0237354507090Ce0	gAAAAABpnWqd7JNGFpYtWC_US5KNjxUl6Vt5bY9dAagXl7fLJFFV32g5lETrOBVqfWcQMGOfYtfKjUEVHA0gC_xWGwGkHOUrgcSeAmnuX7kqjUhVW1cjsvSpo4AF-AL_tJNwhIE0UIXuEcqcAem8nUotWGkRWR_5tNz9OSd0x2xGnsy0qEFE0xw=	A	1	1	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.660955+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	14	Polygon	93	optimism
102	0x7951A2DAB3bF521849c0513777d493031F7ee8DC	gAAAAABpnWqd3eELsSi9e08UoTajO_ZCJzRB17wyQYAB2kijAZA8fBnbX4Fd_vzDM9KQdmC0MtkhoyczjIQvw1t1yvxhPxdTW8U-B7JTaO-NWXqVU8vlDcXZg4CnmTgnJETg0x0qp3LoxWDg6t0pl8vyMFgNLNB0uCzGHiqoyMgMyRZGqdyTvIM=	B	1	33	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.454098+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	14	Polygon	93	optimism
121	0xEeFC44c50Da346E8298A36E9E7A342641479fFEF	gAAAAABpnWqdEFaGC_zKd0_qHIPsX3odNVOGOGN9Y28px86FYe9Htusvu63GewEj813dUxQ-tUSdLlw8vhfXrU725DJsrIVImg6nwFC5ZgsL7TXyNXgre8PRjcT8xphaT_IDHQY6NPgNo-lnQezKfnLKCyUMrBOuBXuWDVJyOQrv1diZ7dfp2N0=	A	1	32	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.560015+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	14	Polygon	93	arbitrum
158	0xf9B7b016dddBB0eaa9CE75AC78F0D87A0558C8a5	gAAAAABpnWqdfh8iaaUZN6dYY3zLO6wXhL-gMS9XiZc5C0iXv5rGTjy3UWKcsUaboWUyHJzrT_UV_WhBqsTU54PjtHpXk3OO90yFujVsGNLx_Z9JGlBYdakoEapbBDVKdYGjOPv2HSVH-BqRou8PD5Hch2ZvbrXwsxEKTyCk3MyASsEuqKT5Bi0=	B	1	79	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.760403+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	11	Polygon	94	bsc
108	0xa19a08F9422c768d6DE28cC31443Bf39cecE7D46	gAAAAABpnWqdLu5qnw7fjxs0SLLu_P3WnW_cxBbfmXdcHFZsWLy0KRnZJiB1JYNmu41I47PnuJhO7wu3nOr2bnDnM9pBS9-fIhxcCuwzbtnfgWYbp0NOtgqDllr8VTNR5sELRuEQo3JtK6fgNAaqNL_2efZmjpgueBxHJpXX3k9aCBv4QVWGDyw=	B	1	211	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.488658+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	17	Polygon	85	linea
103	0x7CbB2783F1540e213dCf53E5BEeb1c2102EBB95C	gAAAAABpnWqdgaEK_NNG_NNhkmVmDiSUyNJtVRmnQ6bfYamtaMaLW-BW8tQ4XiE9oFFoTaaBJu49TtloSbn2KWb4k5ip1wOHCjK6c_anVA5t2PClj4X1vnZUq4pU_5W3UgsKxsPwKAuxdvW46rRwvhpiLtyAdrXk3x3RoqwOi4xZ-i0OWuM_2oM=	B	1	49	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.459108+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	2	Arbitrum	84	optimism
79	0x4467EFcAB3020De031305B8C144A20e57758d482	gAAAAABpnWqdwIfYhrbniUKaj14mGZAy3RdiiGKWooxutb76ttAZ9leQzeVTrDyXNzrVBW408q1hMGbCRAgWZl-0HuOcGqfx5otQYFmQeIbGwlHNo4FJlOqVGbZvzMSJ355RcGYP6HMUwpgQfQnGoMjgAOJc4dIfxet6xWKUBsGfFyrNF3fNXZc=	C	1	449	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.339196+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	7	Polygon	90	scroll
122	0x5EeFaeD710e78A3f030C327299CA399FD3937eda	gAAAAABpnWqduTwy7qzS31zlUs1rFY4mPgjVAIJdVI9YF-52iR_HlxNaKhAlORQFq-I1fIUsUv6hNmPSK9gFKlZdmzYNtjlXEatoYGXoRiwgXx8nhLmPHR4rxX5lPIchTk-U6ZXLPHwgRoP6rMod8QU7C_2bHbtNse3_vCwZw2QNwLm5LNATpqo=	A	1	451	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.565266+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	12	BNB Chain	100	mantle
115	0x7c18513e8f8b6C6bAf6bC0B4040D57E732f9710E	gAAAAABpnWqd8eIDUvSusuL2B2_X70EauovpEnbuxSEkbPLXBhir-zksLCW0c9TLI4Daow26REWEM7FEzhsJF2Fz9PZmC9w6APzaCnhx-NLgzRZwKTjdR7dELSdazTatEAQXB-iGWKRplJs1WjNcdqb4AbPB3GGDUjYx6lJkolyBmXC8BWJ13JY=	C	1	57	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.528207+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	15	BNB Chain	95	optimism
135	0xD9df537524cFf1A5205BD0B73184c2Ce61Bc3943	gAAAAABpnWqd1Fd4cUlAiKo4zaHerfTlQO9M-3CQ_l870STTZinmq28dVbDv5QGlFjl676jm3Wg7kzf6XTPqiTacb7SojREzMbxlQgOBXzCTWRbB_QWUw6EDBUw35XqzHT7Af1hq5Ibl5wLIKOF2q12dxCS7M_QZ1RZ5Ez8ek-6O-VpQiEM_LIw=	C	1	459	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.633316+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	3	Polygon	81	unichain
75	0x9748DbD2E9c5B5A4699293F6aD41a7350801d408	gAAAAABpnWqdcTEm--HrmwQFmk9ywJucWb-QaeVxpg8dqCwgr93XDsIel3s7g4eYTc3Fo4a34WGs9EQucVg2WeIoZylrCtUzV0PG6H4utQVzcPXC7sCBC8_dgJsijfqUeuN2bjyW3S-2YFFE1WwR26GbbuHzdlE8b429RJMeNNYlTfL7_-D81YQ=	C	1	240	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.319595+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	8	Polygon	87	base
155	0x405F8cdCF7f2D9CC494084302380b73e6c0953e5	gAAAAABpnWqd5FWEv8-xukYFlLS5dx8nhW4DLLs1hpNwdA6bvLjeXkgPhah_M03eLzDQB_03rWPdVFHvVsOZ2-YBxWMr77jZ-1RmIqJClzOCmyhhe-ewuUb082XKiSld7OajjDQoMSTzcmx5U_bUXxR_uFCr8Si0KllCUr1rlDKJJSVi6877MMg=	A	1	463	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.744413+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	2	Arbitrum	84	zksync
127	0xF9F82189c549C7C43c889D31fe10F2Ad363568E6	gAAAAABpnWqdq4W9RGWTZqN8XbGt7gnXtzrisjDLACLNzdAUi28eVAt-32IdldIXoasmJf424IQn0z3eiQdLNfZLKlzGN-3RNLiEfHms_5SJqgtg8F5tolLmTgKneJv8HsHeLEexri-N32OvK-O5qs9Z5NblEz5bAlCJ5pOSqG1GF2XFsZBoLa0=	B	1	458	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.591425+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	4	Polygon	82	zksync
146	0xc4FBb2A03fAe4CbFe823b53C5C0f1cCA83244532	gAAAAABpnWqdlmTuQStxMlwGlOoCVQI-U-1fBqaw4AzWFTaiPllgRxXBhQtH9epdaTnbCuysEB7jjpuOOJVE3fwmnfhMig5LpswyTtCKa7GweYLfAH3zIJcW_jEgPOFwnDzJfYsMlADC6qT1gupBdf-WWL-MrHOWvlDjaFzCGv91mUKSCMEUVjA=	C	1	461	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.69343+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	8	Polygon	87	manta
134	0xBE580CAD83568f84F3Cc589Fc386e4Eb19Fe108e	gAAAAABpnWqdX1hpcuYBncunvAo5MetLCZkruuKaYi3lDq2Lj6ZH61Qw8yYxKtCMjzpPLNWN63-90KIDUVoup3zQF3Yomr4sg3--ViZqZDXhhaMQJxyKiOfV4fliGw1jI8Nr_6IAG8_uxtv0nTPLLe6nHtJEfFy_wf1Wu9wjmyfYKrQvdNPBHT0=	A	1	271	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.628189+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	10	Polygon	86	arbitrum_nova
112	0xAcEC26ac4c7d02e490aCEb198631F6F8D19753d9	gAAAAABpnWqdw7DiwoBjN5dTRH45Q3EfQva2tXldya091rESNZ9BUcCgNyuBubh2_5vUkawDe76TFt9UIgQdqYV9u4915NaO-365de9aCIP5op2w_hWC_rQoif-pacNte1ZRVBoZZ4YcEIHydt23Ibqs9jvh2xLbJ-M0C5EPp6WlwZB43-fZxHY=	C	1	270	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.51123+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	5	Ink	91	scroll
123	0x7D96b11047B3Cab8F6676dbbE30857166aA61463	gAAAAABpnWqdZTTgU8w9NcVEm3Ih-E57sW9vRIH2UZyEPZqC_Clep5zAc8pKdiUJ89vJiQlqI3AM55CXBZQsKK4s5Og_TdctUHwxfK-J8Gm2ZCGL4DAzdqyYkJY7Sw7hDu_7r1nP3ZfWz2HwI4HENdZ1zI5I5sRiPK2TNc3DIc-uPtkMYqeIfCQ=	C	1	53	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.57033+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	4	Polygon	82	linea
70	0x19510aFc0e1E03aC61D9C92870ded47A3123A81B	gAAAAABpnWqdzI1RIjjSHYpEoD0HK4Lj22gh3481bmoh72JqDRGQfNtCPCYmLxXYCG090oOy5dieGOUeit2BmeNaBWf2t9IuxEFnof0rs8vQWDTphBJglLx2aGJ8ndtLDuHyN2KtzP5NTQ66sNCHFTGm9pUXZ5PZtlhVAxQxNr5VRfv6MD2M4BA=	B	1	16	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.293326+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	1	MegaETH	88	arbitrum
105	0xDdd0A3b96403D4Be0B5ccd1808849cE0AA246cbF	gAAAAABpnWqdwYohwO5vF1M56HNylh2Dbpn0ZuoLGJKCFK2XP0VVrECMaR6mWbgYZXgS62Jp2sFD1AxH7OESx9pmq1hopYA44fEB-6UqVzYTOT_nCCosWEB_dVOfOgLhI-3LlY7Enqp_46iGd_ri7IbaRsBN--cCier73ww9hOwGYB7eyftQQPs=	A	1	31	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.470821+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	5	Ink	91	optimism
144	0x13383F428F6788ab83347C6183d9446fF1FdC8f5	gAAAAABpnWqdjSNhjzdyg47d4bgtAs1bRkbClAtl4o921GLtY1Wz3s7UUtiX0YJRFnNSr2UYckujHHjHnS_LSuY2EMUACZO65yN_Ddca_n0rpNQkvNZMh06UrdR28D-PjTrOnJJ7iJHOWtbo0qAAcrIgMKO9l-u8x3lkAg_zn-wZwCPjGLKTq4o=	C	1	59	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.682465+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	7	Polygon	90	arbitrum
143	0x4e5be5eDa12E261F89785A91be52F991F075d3d3	gAAAAABpnWqdUpIdeP6qTsnAs9NiJbSYDiPMNtvxpTZasrxVhVMeb6akD-nXDwG_QzRgnSKg0TLAXwgbOhWMOY8LVX54StuTSvEZh46RQQN419dYSLqDHlOr3EcedSd6Iek9hPLRapfH3eqvUASswzQGKfGrzaTKqLEuh-rjZd_mj43Hu5RKbG0=	C	1	465	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.676848+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	12	BNB Chain	100	arbitrum
109	0x929623e7321d8D0B80dC57AA19AD97a5290142a2	gAAAAABpnWqdO8-okzDJadhU7ZeiM16F66efErK4hjs2J1k9r-lTuCOIDpR9tXEWHc3LZ0Zjt3yG3o0cc6nOj9kp0cURCnYMe8B5sW8WqjqbaIihJL3_csgD9d0i7XIDDMrWOCj1SWunnrRQTQscWRpTWuWJBAbxK7DZhiow0W-1g00LVNdF9ZM=	C	1	229	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.49399+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	3	Polygon	81	bsc
69	0x38C66feE48071d872cD06D4faaFf8e2fD2054D3F	gAAAAABpnWqdRfrkQe3hMwPwlWkw0GBs651sXQ-g2o9mAeYB3yZbDjMULyJfakHSMtG8nIppjxRB6kMis4DxZctJMuv-TG9WqdPj2Rq6Yf1x_A5IGKgAKupPH1aGyLogZP4OJRWMIfkFreCBU3VRFpFL6K4WR6Ms7KRADzYJQYXmLl84izj8838=	C	1	472	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.285894+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	18	BNB Chain	96	morph
72	0xcD61A654D79AAb27Daf77b9E0471615de9629951	gAAAAABpnWqdyFP-566qKV7Xba13eu6_5lMfa_4boHAniYmHGF21NEbxbKUHmzfwEPNoflzP-1Su6BH8kPwiTjjj6_wDVE3Jj7LAbD7DjlHTU6WKmQF6jtsom7C5R7wSnzUSvfX2Y3GTDVYGd9d47W05qBeQS0pfNcizV-LZfrS_vHz4DFRzS8E=	B	1	89	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.304011+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	15	BNB Chain	95	optimism
101	0xF625B0E7A15c6490a1AeF4D9955e95A2d0dE4389	gAAAAABpnWqd9DSFtgfXctJMhVkjOVPt0k9-u_lJ38cFN7UU1PSQM2sjmWN01AvDGP-1c2V7f5I4iAJ5_4ckwYlMHMrZXpC5GcXYqPmeWJTYVXNeA9mJaQBdiRLMnxm5KMsm3r2YD_EVhMJF9ciBHQybOuVia3YVVymZG7B4gUy5t2CizeQAZvY=	C	1	58	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.449133+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	14	Polygon	93	arbitrum
90	0x1319ad348b84d069423cCf88D3073198e8f01c68	gAAAAABpnWqdugIplpoLyTnIFvdvE-p0DS6NiEpvBcr8RpcyGz8p9JRSgn9tzCz4gB5o6CibrxnozspT_38jgtivZjzx-_5EOlpDrIZUP_ATsQXiBHt_RLw7XAe95DPxAhcoLElQh7ZQPf9l9WhtQfB6ItfHMn4ghoknJaw7Qe_qvTu-XYR4tnY=	B	1	54	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.393376+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	13	Polygon	80	arbitrum
82	0x45f505b241522C8d20caEE8b934fadDa71c48fEE	gAAAAABpnWqdGhOxvkOHrGOydK0AJzqvApyVhPitvrXutt1jhcbIWCNK0UERLA4aHv5uUwCOpLwxlcaZlSi8Ru3610G3mzP3eS527rF_Y52atFnDOXDdhuaCVk3p3YUsgNwCx35SOT1i06UNfCoid8wDkRV62hwaXBdpG19oYMUoQ_xjc3Usxdo=	B	1	470	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.354422+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	10	Polygon	86	bsc
149	0x8e7FF44287f809eeb1a1d8cd41c3f373E6363D37	gAAAAABpnWqdC1d4Zdodc2a98aLGvkxmoaTNk4Y13h2Sjwlph0pZCD36hjwcv9gJaGJl3N9mmNxnfKpZdEPI6cm5W3yQt55g-hUffTJh8ja8OSRtyIqkCz6lri0rbenruiilEkb2qvuPXFYgjiMt8DXh1Af7MGUsOcv4qTmjlMx0qDYIPodmBzw=	B	1	48	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.710359+03	2026-03-20 11:25:27.223587+03	\N	inactive	\N	10	Polygon	86	base
91	0x3aB0590C7C3c74A78D9569AeE33C0712B716b3f2	gAAAAABpnWqdJAP3jDzRwWjcHyz450bacALBwrwIi6LTlj9CpI-EPl5lrofY-Slml4lSdVvAf84cqJO_rOIpyL2qORj58MySjJXY6S2d-_0l5O3_ccsl7Roaw3Pn6U5p0CZzZDdkhcCxUXLqhFVf25vs_Gon5LzNX_r1xGjm9xz9xLeUtkQqslM=	C	1	448	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.398117+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	1	MegaETH	88	unichain
153	0x53941398b353DF9B695804A675D0F2a8d71629a9	gAAAAABpnWqdZqZ5reBCDPmQn35xlyB7w3RbAK-wYqVeTZ26OhsE25rJ0J3Npp7YpOh5ZyZ5FoiUiYMEaGGw5Y-r4HkxgJWhNPkugBh8LmFr5kP567_G4DSkyZphUdmZuPejucQVThqvq00s7K9ZHHOtn3--r5Kyj2N5DfJljsCZbmdVT542SQg=	A	1	24	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.732626+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	17	Polygon	85	optimism
148	0x60CC956C78f8ed820c9Dd9A34E51fddC2E2500Aa	gAAAAABpnWqdbe2PZR8Rk-dhB7Nimm__d3qVMNZo1pXFQvPL6lxn3ffF9IVmhkeEC2MHhWOPJKo-U4sInPMeD58K0Z735aQiaScoB-W14k1BJ5VKgOWKAI4zOikReZihlL0a5bVY6i5wK-9jYW63P9m2cXRP09X2Ug75_V5X3PCGticaSCmDl7E=	B	1	55	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.704763+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	13	Polygon	80	bsc
110	0x21C3e7FE71B243b96835DA024430CC1fcf126402	gAAAAABpnWqdgbhGcvSG-umzVIoQx25-ycZGGI-yfL6afxEcMbjzrKWyf9nu2tmLP3LHoitcoR_JqYg4tyBjE-SZJ0z6UqiJwjBPsIu74K3UMCekmtMM9l4_OW1RuCd5nLcGcq8wb7_xLu5FhdNvgu_UU6qv25-sl4_sFz0HWyCpIYDj9aFCl2o=	A	1	453	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.499868+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	11	Polygon	94	linea
81	0x6ba4842E3422f7A6CdA6cb7Edc1e1652dB029ABB	gAAAAABpnWqd5P121bf9zWChmCKUw-TAToLpd2V30Zn6pWSqy0WdeX-0ALTQ3_A0HYkXX4TZLp1HizXs_1MAyeqbaT3YynjJxocQVdwTeDiSvVcBw4NXT3lKvd_g4l_x67ymihKM-y20C3ByxxhfM_xNrHW8H7UlZRr00SPuynLxh2xOYLxu8ak=	B	1	52	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.349645+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	11	Polygon	94	optimism
99	0x6b018D943F5eb5426e9327D2945786ecA4F1CD3B	gAAAAABpnWqdVIJnC4dp94mpe1dfe8pcK4j8C7qPVqWBzUGt-6lQuSqL9v8m5Jdxe6U1nPTvHa5vck-jmpAPv1Cq81j2Fg1yzw3sbQ-PumY9e13unhOjFTDveDAILbQp7sLoErDymgXip6vbSzLFnKTgYbJDLo9hWxmHQXd0Nd3_SfjIkEod_lY=	B	1	252	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.439301+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	11	Polygon	94	zksync
94	0xA2f793c08cA784eF7902c55c9f24C1F99875e612	gAAAAABpnWqdeKOTfzq_xgxQnNRX4kMUmMCet9XUTpBzZeTGvh1gH-4YYFoIlQ-AVRcgfuAgxSwAVYEOtaec6Sqv8psZsRud2RqiJBIb9d8eFQ3ufEM2Uvkoz4lPjh8PJT_pT5TLrnHXcIi10lf9VZ3egCEu25SrbJ3y5myUdXQ6c_p2p9hJsSc=	C	1	471	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.411941+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	10	Polygon	86	mantle
131	0x183a5Fe19Ef43eb6b47C01f29F27c101F1dD02CF	gAAAAABpnWqd1wop9ayBukssufd_fVb9UohSJq8HBJXmGoh_3lt2Gluko4mKQtzBL4vK1PzIqckqeOpURawAeRXxJKfEYBOEz5lEnrzrfxRxjSOofEyRe_VUD5g_YBuacuSq9j8jCBjc9C6IWDOMm2IF4lHRrBZiC_AGXaGkA_srwdM48W3UEkA=	B	1	20	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.611063+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	18	BNB Chain	96	arbitrum
104	0xD1e42eFfbe99871FA0188f7cDb22DCC6954e6039	gAAAAABpnWqdTTBLPBTnKrwq_bnlchyvEF4EccJ8jMHplOomw-ILVfcMSzOOO5uIDHhjXQUTc3cTmYc-m-Y0X49JnOt10Z7Xa70PC0-JfQnFE-5ZNWV9f_nkp-VaxBSDmui1mYzO7AxSUNNcSTqiSqw5VvcB6otZeqquepagEQjxD4jt0md0kIE=	B	1	67	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.46462+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	18	BNB Chain	96	linea
87	0x106e0d48857c3EADAFDDa9DCECF3ebB80bb05CDe	gAAAAABpnWqduayMzpP9RRjKpW62GofrpS4yplnuCQeCx3AvmjCu2q1WNpGfNKvOA8iCIsoNYNfGOtaXJmt5fCdqkqVrKZ5i2RmQLnhDxinqOL_KcamIRvfEKcpg2Z2gJky2j4a_wQKzB0fOke3-RYtLD35PYiqNlFY2Lo1V0Z7KXMSXcV2KsDA=	C	1	50	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.378599+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	5	Ink	91	base
152	0x35F8C8f40eaB2a838F56d4bFf2040a60984F01fd	gAAAAABpnWqdmb9c1Uj7Cn_oo228bV5j8xSEfCKhWwPXA-WOZPgXqJ8aGBHyUiBgnlsYw_wscPOHQqdPeIV0gk1xKEFYY1DdMGwsbVbcn_-sjRloGzAVFDItF_0CVdGYJJVvoLbktFHpQdZjm5wBzi1Ht-rUjwVQXS0FWsj9xIy424BX7ZqtJos=	B	1	456	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.727141+03	2026-03-12 14:25:34.602336+03	\N	inactive	\N	13	Polygon	80	arbitrum
89	0xB0FB517883BE4FB8c57986A616fCDf21B37E5eEb	gAAAAABpnWqdTT-DcPW9VFQhFJ4ShPT_kUUxqGnOyBZQhdYkKsncjyDIZTRGgy9FC-hI9Cc8J9xiCLM2a3wS1jA-Ut9LTzqiNPRLqHc1nELHqFzz01qo8VsmQl-t8c0T2-3BsjOg51HVI55zfLYpvtxUazOjR2EzggED7n-INrqp5BV8qwHrN1o=	C	1	19	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.38863+03	2026-03-12 14:25:34.60632+03	\N	inactive	\N	7	Polygon	90	bsc
93	0x4C84CAc44e8D2d693F63827402bF743fd92cd2e1	gAAAAABpnWqdICeeQyXaeI2IhRrfYSPPpTk60QIhwmDfq5kTVew_hUuHVEcj1TikOQx8rOO4uEnHrIOhqLthN33le69NOznjqursCmhIET3yXS-xiXl8gpHnyQzPsH4TnOTkDKHMUkmFrJOJlCBOThszMVYaXmEwOed1FRTtQ9rXBvluKIPqtwI=	B	1	93	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.406952+03	2026-03-12 14:25:34.610387+03	\N	inactive	\N	13	Polygon	80	optimism
126	0x1dDb2Bc11D4984001E6E9DADcA203966ae1cAd96	gAAAAABpnWqd-W_e-fOBFacUwS0QG6B9KqX6276Pn6lUMe_cis77gVMTZa8q3F6ZDeq8wCXA3Ey8kjso_DCq_WkSQXu0nbK9F8Ofaf0yQ6F38xC29ZaHO7hHK_Dl3EeduTfkIAkiS0aXDHCRQAoUGFXD3vlmYMTF6LcD-Sc4L1HtyjbT4Ieux_c=	C	1	467	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.586579+03	2026-03-12 14:25:34.613147+03	\N	inactive	\N	1	MegaETH	88	scroll
133	0x7Ff72EaFc5F9594C7D70e8a26bBD57D234228319	gAAAAABpnWqdqgRf2ZZv1D4UdsudaIs3_BilMJ1dJUJgyBEfrUp8E1B4-67d8wvbCMy_tuBUUdU8JBgzgOXHxghHfEs6LW_GYpQuX1iW1c2GL09Rxhkc1EMq2R61BlaDHmvMVD91LACBly-YkS5_RowvekRvwKZPsa3sPTd_JfZhCzuI_UuDMMI=	C	1	468	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.622753+03	2026-03-12 14:25:34.61444+03	\N	inactive	\N	17	Polygon	85	unichain
138	0x96141f48fd852D24DA335ca58850b4c5c54d5d98	gAAAAABpnWqd9Piuw-eRHaxt6-LC1xp_m0zI-EZXNOJyKbBwediAvQOvy2qfY0_fX3WFLdcUApGGre3GR6FCwj-RIQIcddZM_x8OTTLj6VH4x8qr9-ZN1Cg1hvA4cM3UnyyBA-7BoKVIj7J1V56Bh75Vcznr58dawNVdpaizg_a3hPByU-6xTPo=	C	1	457	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.649796+03	2026-03-12 14:25:34.61581+03	\N	inactive	\N	7	Polygon	90	zksync
157	0x72743be4399EC985b1E053869b3029CfD094ca5D	gAAAAABpnWqdQ1GyKI5pqyoDV4Ct3VJmN8V7yWZPdlLLNgwZQ2aondx3OF6PszedS0o8x6-FQrS_BTb-W4QPkDzAwegDD6M4U4LLAxjCrmbUQQRAGtNGtUadbuPy6NC_Vmnn29V81Vlq7WiGV47TUE4bWQSDx9pxx63ahEuGXflmbl2aVCBnr7g=	A	1	11	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.755299+03	2026-03-20 10:47:06.840508+03	\N	inactive	\N	8	Polygon	87	scroll
136	0x33948339Eb5c337c4364Ebdb29481484F09F2C24	gAAAAABpnWqdmbGtvW0XvhNOx-3JOC-mL8HfTKyR_BnpuxUEokpeWiem1FtqbV_VY8IbH7uL0z0pfqwPXe-djjqb0xOKHgQWdwQsnJCtFiFEJziPTSjll6e3rh0btvrnCpnmvEtitpBb0ppPYBAcuG5WoU290XdJl64T-MDFuJsz51B2llITvZM=	A	1	45	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.638703+03	2026-03-20 10:47:06.840508+03	\N	inactive	\N	17	Polygon	85	bsc
97	0xfDe65a0Ed057256517b99099A27ff99f4C744621	gAAAAABpnWqdxSw65iEPHqIu7JZienFgoH4NDdLBHGOOBpEX5nEKBLnpf16gqIV16JPx9OpXG15swQpN0gVG4oItL0QGLV-tj6s-rrHUTG62FmcJKx1HFam0B-R3C2xmgVF19FcXjfyoaoTvlvJgcpd3MRiY_cdrnEdJuauRh1Chqdk76u6iyoU=	B	1	226	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.42832+03	2026-03-20 10:47:06.840508+03	\N	inactive	\N	2	Arbitrum	84	linea
100	0xD50fA1e57267eF8db916487B24046a8f74fd5E85	gAAAAABpnWqdHXwLUocpjyNcKqrBPEbmviR80zDquBJgbwPAc64vjRWdZhL2EBVSV02QsS78p2cH-1EkGy0OPQzrDmEXpl8nientXpufTYiaZ92D56brkM7jCiguO33kyuW576ou7izKsLXBcP6o21Hntxw212yCEHygMEL1RFgHMKRJ1BX_OLc=	B	1	46	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.444341+03	2026-03-20 11:25:27.223587+03	\N	inactive	\N	6	BNB Chain	92	manta
130	0x10b812e6EBD07BE4e620959b9Eac641EafDE7436	gAAAAABpnWqdU8AgsUY0S6PLff2sxF8BMe82bAIlB9cIqeYy_8ABy1qng_Uy7Fd0FTb-E0JGBlmiz99ZRNxG6tQWud0YD1H4wOcgfTPP_jqRPZ9BE1Pouf0l5CbWZqg-7gP9ekMlC_chEI5pgxrBU2Y90turjIHey3JiASW7vuueqMQ_jWzANMc=	B	1	455	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.605766+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	16	Polygon	83	base
73	0xE78B044126B28723b7C242dcDdf776539600C73f	gAAAAABpnWqdlLQPK8zkGdGBw2QNy2CgEr52xShz0WCmqbKT1lNvaA9sD-2uE12zFw26i3pVjZdHZ6nkpf8SuS3o4bvY1xemSAlkh0Ktl1n_e5FDh7njW5rXWHNeq8nUR_eyTT3YceNYdgIjUs1yW6kVdrVpHBc96yfcGHKM9lKMzot_VdHNZY4=	B	1	214	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.309235+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	14	Polygon	93	optimism
147	0x98Dd6F2Eb0395A4AE80Fc34da4DF697a6f29D136	gAAAAABpnWqd0qrLH9l_nbjHPhWBWotnCFVpi-2VfmB7t6CSgtP0-o49I4Joxswyf_pv_9VUluPrMtShUpwiR1p8j6d8M7igM3I1MSA4-BB4S-pi4ZAap8cNwQ-CMzvZxTBb4WtwI_pmmuQL3RPQTxhOPI0Cbd_prsY7jOUcEYd5U-fgnenjk20=	B	1	260	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.699365+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	4	Polygon	82	unichain
85	0x4A6940F556B4E7dEf36C53A00Ea5Cd93B97EEE7c	gAAAAABpnWqdUR7eKVvySz63Rql0F5z-l_o6WlnEZ7XLS2kwQZOVeFu-uGDHFfCsVcad9D0TdtjDc5QVqNEVK4XdjfIkyylkZRzHDD7egdr3URshsUYme16OQpSnbGsMPt7PqoC0GwtWxW9nicbh2sOH0bcZ5Sxyd8Q14LjxmO5idBxtC8vmpLA=	B	1	201	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.369285+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	14	Polygon	93	bsc
113	0xB2178A2B1Fce69Fa16f4507F9E18c1fB9D3Fb2b5	gAAAAABpnWqdiRLrDEhdLTs6DnazNliC_sfiaN4c7WbRGOi3wa7IqltBEkmdyS9oyxn70dhPX1Zl6yMMXu9rRPqpr-lrLjDOIcG-JZmxoflPccfrYOshiXwJ9rni6QoAA5wxH3HTTMa829kK2Ie7cyllXuNKQo266KkGhH_n-Q1zVqABAoPjdEI=	C	1	237	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.516852+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	6	BNB Chain	92	arbitrum
151	0xEE48c65eFd6508CE8c6E03861a8CA36Feee40b02	gAAAAABpnWqdVzM0UQ7dR42y92s5OUigZbVS88LX9GAbXdnqjCQcTKgab4uBpcoD9NaJjd_WdyrvZC-mQzsjPwIoZpZ5lu-TauTe5-OxuqTbNVV-s4Anb7D8Za0JzO67DKNN-K74VJHYYH0Pavm--gK0DVYIp4LoBv-ybfGoGQNauchOQ0x8vLw=	B	1	447	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.721939+03	2026-03-12 14:25:34.604915+03	\N	inactive	\N	6	BNB Chain	92	base
98	0x4ED3456163DBa34422e4f4dE780B8593DD23EafC	gAAAAABpnWqdh5z5L5YyfdKBfa2B_UecPnKMAA1rThcLE-EQEnF3ALMkUafghTxwenH8DtqY_qIcPVbDO9EYUGDDiSZKbH-h8ykYqlvFco2G5w5dZLibom1rDRMGzSwgXr0D52v84j0C5tr5K-rXqMkDuuIIP6eex32T5cyodTVv3YCWvzn5ZZc=	C	1	469	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.433764+03	2026-03-12 14:25:34.612071+03	\N	inactive	\N	3	Polygon	81	polygon
114	0xC458529e3B8510B2064959EAF562B32621Bb0f2a	gAAAAABpnWqdLh85L03cXCrX83fbEip7f2t9KuX_PiYZPZCXVq_L2rknQiQBqS1odZC7jQHeJbXcx5PP6MC5_JcFiLOmmJXWT6xrzw27iSlYN3SnH_NOd4TXnyl3MqObBUer6Gq56-1FOVTbdUtpvn2BWqNYoycGHVUfzMiv52nfRalXwSaHhGg=	C	1	220	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.522305+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	10	Polygon	86	zksync
145	0xb72cc922d27Df12A32bA773B73F04B97516466B3	gAAAAABpnWqdzQhb-BccWIv7z_ffO9Hy7qrfg98Q7VOjZ7tGkTtKs1lFKKawzihXDJ0BGdOH41LnoYA3s_Y8regASk2M0-_3EuLdRfskaFj4wzB7EyMJknQ0btOdjAsf1_iK6bHRnBNMzDDFHU5Xr-PPFHiFO7jqD1Nb3e29o5_UYMbU7XYDH2A=	A	1	460	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.687805+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	17	Polygon	85	base
120	0xB605b58Cde7f1A05F69833968a963736F1AD3b98	gAAAAABpnWqdpQSoPJVG2o9XW10FxwJo7oHtpdHM4B6mdDAfKvQxEIZ_XpjZ5N22DvO3RYD0oKHS8qf5vYwVLwOGGwYZqjLkqqbGRryKq8QeL9DmDarwJoZWKn_pNxuuP-sqe56QWPQYu2S1pZ0VZ-AsbYCJVSvJCUcle8g32DczkVPq3uBWywk=	A	1	454	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.554858+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	5	Ink	91	bsc
154	0xC40b2c9B6D6D0466C37dA4AE14AaA7185831f469	gAAAAABpnWqdmzEDt7Jq_vCpQi1k5UF2vHpmdxeFedte9loJ7P-mtcM2mBZxOKa1EBn4aT8TmRG0Qp6SYx2eKtSaplpcuDVrb9hqrb-px6kHEzQ2OeNkNHWbir7cg3A-jvmF7bDrdqrmJR7aOuzyycRraGTGwwRz5bfZ7CvjDZHYJsiF9HkOq9I=	B	1	473	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.73825+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	6	BNB Chain	92	optimism
128	0x674c661591cEbDddBaBb8BfFBb8E3f25378bECf1	gAAAAABpnWqd19Zsusefy8flawIiboyTPkKdp17S4QewgnEs6g0vGd96YFUm3kQp0cWmMtdLAOzl-ZKWfKmwTeIIuL2jy6qvdWYQdYsfpA9g1a_Bs9NO2rvOiIHoQzVbnVxEUz1osOBfr7affjnu7iNjmrV0nfzqU8A75sQOS8-MDdEnwInNhkU=	B	1	227	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.596257+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	8	Polygon	87	optimism
116	0x80F6719fEa96611Ef0D9e63DdDdF933e4f48a32E	gAAAAABpnWqdVpyV0-tTw8v8AhLekHKFMz6830oiOsrH5kXYbZoZXo9QEf3XYlvhImVaiA3rDkHgezFa5884uDoH8FBYNs9mbh4TgLVEE3F4Kkie2eblZMQxa6Q6Xrgs0WG0tH-K8x-0MAF8fxu1DyDJBB3YNZ6y9SyAnd4S5WkLW8NrkItzk3c=	A	1	475	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.533047+03	2026-03-12 14:25:34.60632+03	\N	inactive	\N	15	BNB Chain	95	bsc
119	0xCE437F5Cbc092246b3887582A6F6886e09B7865E	gAAAAABpnWqd40B9MYXsftyKiUhf_kfhLwCUCTkLL9hEGBNq6fae96wxUnweZDoNaJkovB2nTUAS-JQV9N3jN2H8XpO9eRcgOwXjMeo4Qbz5KmBsRghaCaRvW_ngRbxZBDc5O04kq3BqtnxpJByqW4nubzrsL9Og2Co73xdba1otHZTRn39YXLU=	A	1	474	inactive	\N	\N	\N	0	t	\N	0.00	\N	2026-02-24 12:08:45.54971+03	2026-03-12 14:25:34.610387+03	\N	inactive	\N	4	Polygon	82	optimism
117	0x67a8f2421b7869370D89182A14f14FD16a09b040	gAAAAABpnWqdp5RfyDc03OnJpVOL5tdTXiiLE2ZYGB4zEY4UktaxhBL0MogR3mx0OShnly53pxnwDVbSKNzDO0hl4AYHIrvCwEoFalTy7AvNEgSyDpPjXEEsGBvOqarTOJfmhgwHSrxjg_InhUYgqzeHTU52o6IsPXVD1Zl5T2Hghs13JzvOKPE=	B	1	28	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.538415+03	2026-03-20 10:47:06.840508+03	\N	inactive	\N	14	Polygon	93	bsc
96	0x28Aca1F2D769E4c94cbDA8db299A29Ca10A3c11F	gAAAAABpnWqdjSPmh8oJ7TnRQDD5xtp2QAst2o8MQELPAV3LVuQtKbPfCI-D2wVRpv2rWcZZaTcEAm_SwjgFvWma01x7LAQubdSoOSsZuyb4wQSJUvHgbucBeHAEZ0uYYpyO1iiO54Kg-Hof-wnN9gjP4qzicXjvuK4wUH_P16kQMUnhYEAzE3E=	C	1	42	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.422855+03	2026-03-20 10:47:06.840508+03	\N	inactive	\N	6	BNB Chain	92	zksync
111	0x1d3B748beC68e391490959A8325156E8F2A73AD9	gAAAAABpnWqdGntFkkrVyf4LLE6_UlKEd7V9X8cgjfCmxuXTgRdDJVSNFpo7cZPxTstLFomaxT107L7Kq6MXzbvctPPPoyCcC4um4KHE9Zp3qNifwkFT7KcmkAWu-mU8N4VOIl7wmGvTDg9XKjd6AjwTF3r6XVliH29JGzVFbe-kZ6zsklbzv8M=	C	1	47	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.505479+03	2026-03-20 11:25:27.223587+03	\N	inactive	\N	4	Polygon	82	base
107	0xa89AA002FFEc15e1Cff95A60604af8f2044faDaf	gAAAAABpnWqdPFMpK67azrkff8OwzthMcCb0UPzRQHQbHjrTpBUdmSr5PCFjwd-IiRBwZ9bFpCPA9ukZjRbkx3oRWsLpG8GaJFzu899jwBTK9sPQJF3fl-1QbrpEB0ejbUPTalRReTI3rwk7lxWRM3m4TYqqK1NwHnq-HTGoWovo-5dvOHc8jyo=	B	1	466	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.482889+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	15	BNB Chain	95	arbitrum
142	0x5e885A345B6e63A3FC30226E22bCb9EC7CBE3876	gAAAAABpnWqddF5ruugpjR10JlsErUNqCw8woGRnzNCSwJwsbs1EPx0qLrPPLFlUUbQKQLg14NfZzTmN7oq92A0CYrFBC0wUFk4cLDYImoZOb0pbz0UYsfbPx--A_e4i-xEoa2iXJr71rir-8wHTnLFfdOAvbETl5W49hk_MIUyz1O4_2gExKIA=	B	1	446	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.67167+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	15	BNB Chain	95	arbitrum
95	0x926819A4608A8392CDfFe1Fd333a27e24F88981c	gAAAAABpnWqdxJ4lqF1M6sCtVlQmg5kkQyXfcM-cK7c133jzqcK96LuuX8HFJnLXmyPuwFzC8CprEthaWO3W5bLDgZ-a6VxZvnDdr29oT9dd_ga1PCM4ZVRqTQaUEqpL7oseSG8v0_NgNDsV_gxlH4ZDPm3R0aR9iRIlU4xM8ASU_ST0dFrfRfU=	B	1	39	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.418001+03	2026-03-12 14:25:34.60632+03	\N	inactive	\N	15	BNB Chain	95	bsc
88	0x168BD8De0B96f6D4AceF721DEc7eB2ae60654b39	gAAAAABpnWqdbZW7bTpgY0SGVbe1aWPNWg4VSSBs1Cerij5indEcxRREF2mXt-xajoqV2i1-6uQjTpkuLlu5CDa-yHekaGqrQMCAIXM9j3UO3la4L-iTu6uyIo7HqCYelDZCrvzPuDfHiCANiITfdcK4TPnEMXgwBAJmowstyahJuC-Sr2ccupk=	B	1	208	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.383377+03	2026-03-12 14:25:34.61444+03	\N	inactive	\N	18	BNB Chain	96	unichain
106	0x8E95a32a1d2A45CC7d1FA1495f3eFCdFAC325c77	gAAAAABpnWqd5vx_yJW32_VoHgqDepLXr5MgYFlFg0CYEADrpHR2Rl7SiVa4BgTlRYDWx0bZ2vqCU81IuPS3Us7OOHPnT8E6Za66TAnx3_osdHDRbZoveDLgIb1BOlYE_uEXbR7sEwcQXOSlIVCgyCRvjtdyWuqhPkQR3dyQ7rO7QobwpUsj5NE=	B	1	51	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.476858+03	2026-03-20 11:25:27.223587+03	\N	inactive	\N	11	Polygon	94	base
84	0x1C387e357a23A5100EE46413D762eb7F893587f6	gAAAAABpnWqdzh9SJFeY7eOWlX53ugv23zVn-qixKa4SJLiAntfxoAvzKIDuNK5ztMYBPi6c_VbReyWx45-zO6qpoUS_4kJTtYV0mBwjiOwZUVwwEqbwBk0a5FkQp0Oi28F_V6fB1JuBBMBW6_qze04KOQaVrhk4P6c351hEIJmCRUaLP3_7ys4=	B	1	462	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.364451+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	11	Polygon	94	arbitrum
76	0x70915d796a9659Ae1e733B00F87db0D37cdd75eD	gAAAAABpnWqdXvsdngqHTJAn33BPyrWz3p4OnV20-dsTUCpnmit5PqS6U3dOgDvH4iQ7C0cfhCAIMnLxCRXBthjt_2JJj2Rrtb89v5tIk0MOQEXX9oldT5YuFPKUvcUYP1sexNBF78wkvr363kfUCdJN1KCLDi_cyI7FMujBT_eZsblLNCFOV7A=	B	1	29	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.324879+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	2	Arbitrum	84	base
118	0xB1dFDF7B87B624e0b303846e93B927F5Ae0E49c8	gAAAAABpnWqdqCxGOJ898ITE89AgWfBGmhsjlWbdShhcXl3kwBQSJbPklsDr57NyG6KhXnCxXSfV687IC88pdPnCqJx8RkWXDebi63WJYe7bsLjz2_JHp92Aoni1ONUmRE_0kgWb89YomAyKK9p28J-5iA5eaDVGMm5ITJOG6reWFguhHEZEdiA=	B	1	41	inactive	\N	\N	\N	0	f	\N	0.00	\N	2026-02-24 12:08:45.543838+03	2026-03-28 20:21:04.442855+03	\N	inactive	\N	18	BNB Chain	96	bsc
\.


--
-- Data for Name: weekly_plans; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.weekly_plans (id, wallet_id, week_start_date, planned_tx_count, actual_tx_count, is_skipped, created_at) FROM stdin;
\.


--
-- Data for Name: withdrawal_plans; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.withdrawal_plans (id, wallet_id, tier, total_steps, current_step, status, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: withdrawal_steps; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.withdrawal_steps (id, withdrawal_plan_id, step_number, percentage, destination_address, status, scheduled_at, approved_at, approved_by, executed_at, tx_hash, amount_usdt, created_at) FROM stdin;
\.


--
-- Data for Name: worker_nodes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.worker_nodes (id, worker_id, hostname, ip_address, location, timezone, utc_offset, status, last_heartbeat, created_at, updated_at) FROM stdin;
2	3	master-localhost	127.0.0.1	Reykjavik, IS	Atlantic/Reykjavik	0	inactive	2026-03-24 17:45:42.958591+03	2026-02-24 12:06:13.414711+03	2026-03-28 20:21:18.517066+03
3	2	master-localhost	127.0.0.1	Reykjavik, IS	Atlantic/Reykjavik	0	inactive	2026-03-24 17:45:40.559048+03	2026-02-24 12:06:13.429051+03	2026-03-28 20:21:18.517066+03
1	1	master-localhost	127.0.0.1	Amsterdam, NL	Europe/Amsterdam	1	active	2026-03-28 20:25:35.2401+03	2026-02-24 12:06:13.404832+03	2026-03-28 20:25:35.2401+03
\.


--
-- Name: airdrop_scan_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.airdrop_scan_logs_id_seq', 2, true);


--
-- Name: airdrops_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.airdrops_id_seq', 1, false);


--
-- Name: bridge_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.bridge_history_id_seq', 1, false);


--
-- Name: cex_networks_cache_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cex_networks_cache_id_seq', 1, false);


--
-- Name: cex_subaccounts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cex_subaccounts_id_seq', 18, true);


--
-- Name: chain_aliases_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.chain_aliases_id_seq', 39, true);


--
-- Name: chain_rpc_endpoints_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.chain_rpc_endpoints_id_seq', 17, true);


--
-- Name: chain_rpc_health_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.chain_rpc_health_log_id_seq', 1, false);


--
-- Name: chain_tokens_id_seq; Type: SEQUENCE SET; Schema: public; Owner: farming_user
--

SELECT pg_catalog.setval('public.chain_tokens_id_seq', 16, true);


--
-- Name: defillama_bridges_cache_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.defillama_bridges_cache_id_seq', 1, false);


--
-- Name: discovery_failures_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.discovery_failures_id_seq', 2, true);


--
-- Name: ens_names_id_seq; Type: SEQUENCE SET; Schema: public; Owner: farming_user
--

SELECT pg_catalog.setval('public.ens_names_id_seq', 1, false);


--
-- Name: funding_chains_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.funding_chains_id_seq', 100, true);


--
-- Name: funding_withdrawals_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.funding_withdrawals_id_seq', 353, true);


--
-- Name: gas_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.gas_history_id_seq', 1, false);


--
-- Name: gas_snapshots_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.gas_snapshots_id_seq', 1, false);


--
-- Name: gitcoin_stamps_id_seq; Type: SEQUENCE SET; Schema: public; Owner: farming_user
--

SELECT pg_catalog.setval('public.gitcoin_stamps_id_seq', 1, false);


--
-- Name: lens_profiles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: farming_user
--

SELECT pg_catalog.setval('public.lens_profiles_id_seq', 1, false);


--
-- Name: news_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.news_items_id_seq', 1, false);


--
-- Name: openclaw_profiles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: farming_user
--

SELECT pg_catalog.setval('public.openclaw_profiles_id_seq', 1, false);


--
-- Name: openclaw_reputation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.openclaw_reputation_id_seq', 1, false);


--
-- Name: openclaw_task_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: farming_user
--

SELECT pg_catalog.setval('public.openclaw_task_history_id_seq', 1, false);


--
-- Name: openclaw_tasks_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.openclaw_tasks_id_seq', 1, false);


--
-- Name: personas_config_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.personas_config_id_seq', 24, true);


--
-- Name: poap_tokens_id_seq; Type: SEQUENCE SET; Schema: public; Owner: farming_user
--

SELECT pg_catalog.setval('public.poap_tokens_id_seq', 1, false);


--
-- Name: points_programs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.points_programs_id_seq', 1, false);


--
-- Name: protocol_actions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.protocol_actions_id_seq', 312, true);


--
-- Name: protocol_contracts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.protocol_contracts_id_seq', 1, false);


--
-- Name: protocol_research_pending_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.protocol_research_pending_id_seq', 3, true);


--
-- Name: protocol_research_reports_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.protocol_research_reports_id_seq', 1, false);


--
-- Name: protocols_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.protocols_id_seq', 75, true);


--
-- Name: proxy_pool_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.proxy_pool_id_seq', 475, true);


--
-- Name: research_logs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.research_logs_id_seq', 5, true);


--
-- Name: safety_gates_id_seq; Type: SEQUENCE SET; Schema: public; Owner: farming_user
--

SELECT pg_catalog.setval('public.safety_gates_id_seq', 10, true);


--
-- Name: scheduled_transactions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.scheduled_transactions_id_seq', 1, false);


--
-- Name: snapshot_events_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.snapshot_events_id_seq', 1, false);


--
-- Name: snapshot_votes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: farming_user
--

SELECT pg_catalog.setval('public.snapshot_votes_id_seq', 1, false);


--
-- Name: system_events_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.system_events_id_seq', 33, true);


--
-- Name: wallet_personas_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wallet_personas_id_seq', 196, true);


--
-- Name: wallet_points_balances_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wallet_points_balances_id_seq', 1, false);


--
-- Name: wallet_protocol_assignments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wallet_protocol_assignments_id_seq', 1, false);


--
-- Name: wallet_tokens_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wallet_tokens_id_seq', 1, false);


--
-- Name: wallet_transactions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: farming_user
--

SELECT pg_catalog.setval('public.wallet_transactions_id_seq', 1, false);


--
-- Name: wallet_withdrawal_address_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.wallet_withdrawal_address_history_id_seq', 1, false);


--
-- Name: wallets_id_seq; Type: SEQUENCE SET; Schema: public; Owner: farming_user
--

SELECT pg_catalog.setval('public.wallets_id_seq', 158, true);


--
-- Name: weekly_plans_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.weekly_plans_id_seq', 1, false);


--
-- Name: withdrawal_plans_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.withdrawal_plans_id_seq', 1, false);


--
-- Name: withdrawal_steps_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.withdrawal_steps_id_seq', 1, false);


--
-- Name: worker_nodes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.worker_nodes_id_seq', 3, true);


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

\unrestrict kfu1WL4KhTMLIaLU3T5H02IDcHZdYWjs9DGRnBM93SLVq4QX9HirgiNBv5uBTts

