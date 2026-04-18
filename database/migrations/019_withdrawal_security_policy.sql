-- ============================================================================
-- Withdrawal Security Policy — Authorized Address Enforcement
-- ============================================================================
-- Migration: 019
-- Purpose: Enforce withdrawal only to authorized addresses (funding source)
-- Date: 2026-02-26
-- Risk Level: CRITICAL SECURITY (prevents accidental fund loss)
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Add authorized_withdrawal_address to wallets table
-- ============================================================================

-- Add column
ALTER TABLE wallets
ADD COLUMN authorized_withdrawal_address VARCHAR(42);

-- Add format constraint
ALTER TABLE wallets
ADD CONSTRAINT check_authorized_address_format
    CHECK (authorized_withdrawal_address IS NULL OR authorized_withdrawal_address ~* '^0x[a-fA-F0-9]{40}$');

-- Add burn address protection
ALTER TABLE wallets
ADD CONSTRAINT check_authorized_not_burn_address
    CHECK (
        authorized_withdrawal_address IS NULL OR
        authorized_withdrawal_address NOT IN (
            '0x0000000000000000000000000000000000000000',
            '0x000000000000000000000000000000000000dead',
            '0xdead000000000000000042069420694206942069'
        )
    );

-- Create index for lookups
CREATE INDEX idx_wallets_authorized_withdrawal 
    ON wallets(authorized_withdrawal_address);

-- Comments
COMMENT ON COLUMN wallets.authorized_withdrawal_address IS 
    '🔒 CRITICAL SECURITY: Only address allowed for withdrawals from this wallet.
     Set automatically during funding (from CEX subaccount withdrawal_address).
     Prevents accidental loss of funds to burn addresses or wrong destinations.
     NULL = wallet not yet funded / address not set.
     
     Security Policy:
     - Set by funding engine when wallet receives funds from CEX
     - Cannot be changed without human approval (Telegram confirmation)
     - All withdrawal plans MUST use this address (enforced by code)
     - Provides defense in depth against bugs and typos';


-- ============================================================================
-- 2. Create audit trail for address changes
-- ============================================================================

CREATE TABLE wallet_withdrawal_address_history (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER REFERENCES wallets(id) ON DELETE CASCADE NOT NULL,
    old_address VARCHAR(42),
    new_address VARCHAR(42) NOT NULL CHECK (new_address ~* '^0x[a-fA-F0-9]{40}$'),
    changed_by VARCHAR(100) NOT NULL,  -- 'system' or operator username
    change_reason TEXT NOT NULL,
    approval_status VARCHAR(50) DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected')),
    approved_by VARCHAR(100),
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_withdrawal_address_history_wallet 
    ON wallet_withdrawal_address_history(wallet_id);

CREATE INDEX idx_withdrawal_address_history_created 
    ON wallet_withdrawal_address_history(created_at DESC);

CREATE INDEX idx_withdrawal_address_history_approval 
    ON wallet_withdrawal_address_history(approval_status);

-- Comments
COMMENT ON TABLE wallet_withdrawal_address_history IS 
    'Complete audit trail for all changes to authorized_withdrawal_address.
     Every change requires:
     - Reason (mandatory text field)
     - Changed by (system or operator username)
     - Approval workflow (for manual changes)';

COMMENT ON COLUMN wallet_withdrawal_address_history.changed_by IS 
    'Who initiated the change:
     - "system" = Automatic during funding setup
     - "operator_username" = Manual change (emergency only)';

COMMENT ON COLUMN wallet_withdrawal_address_history.change_reason IS 
    'Mandatory reason for change:
     - "Initial funding setup from CEX subaccount" (system)
     - "Cold wallet compromised, changing to backup" (manual)
     - "Correcting incorrect initial address" (manual)';


-- ============================================================================
-- 3. Create trigger to auto-populate history
-- ============================================================================

CREATE OR REPLACE FUNCTION log_authorized_withdrawal_address_change()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS trigger_log_authorized_withdrawal_address ON wallets;
CREATE TRIGGER trigger_log_authorized_withdrawal_address
    AFTER INSERT OR UPDATE OF authorized_withdrawal_address ON wallets
    FOR EACH ROW
    EXECUTE FUNCTION log_authorized_withdrawal_address_change();

COMMENT ON FUNCTION log_authorized_withdrawal_address_change() IS 
    'Trigger function to automatically log all changes to authorized_withdrawal_address.
     Creates audit trail entry in wallet_withdrawal_address_history.';


-- ============================================================================
-- 4. Create function to validate withdrawal destination
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_withdrawal_destination(
    p_wallet_id INTEGER,
    p_destination_address VARCHAR
) RETURNS TABLE (
    is_valid BOOLEAN,
    error_message TEXT,
    authorized_address VARCHAR
) AS $$
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
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_withdrawal_destination(INTEGER, VARCHAR) IS 
    'Validates that withdrawal destination matches wallet authorized_withdrawal_address.
     Used by withdrawal orchestrator before creating withdrawal plans.
     
     Returns:
     - is_valid: TRUE if destination matches authorized address
     - error_message: Reason if validation failed
     - authorized_address: What the authorized address is (for logging)';


-- ============================================================================
-- 5. Create view for security monitoring
-- ============================================================================

CREATE OR REPLACE VIEW wallet_withdrawal_security_status AS
SELECT 
    w.id AS wallet_id,
    w.address AS wallet_address,
    w.tier,
    w.status AS wallet_status,
    w.authorized_withdrawal_address,
    w.last_funded_at,
    CASE 
        WHEN w.authorized_withdrawal_address IS NULL THEN 'NOT_SET'
        WHEN w.authorized_withdrawal_address IN (
            '0x0000000000000000000000000000000000000000',
            '0x000000000000000000000000000000000000dead',
            '0xdead000000000000000042069420694206942069'
        ) THEN 'BURN_ADDRESS_DANGER'
        ELSE 'OK'
    END AS security_status,
    (
        SELECT COUNT(*)
        FROM wallet_withdrawal_address_history wwah
        WHERE wwah.wallet_id = w.id
    ) AS address_change_count,
    (
        SELECT MAX(wwah.created_at)
        FROM wallet_withdrawal_address_history wwah
        WHERE wwah.wallet_id = w.id
    ) AS last_address_change_at
FROM wallets w
ORDER BY w.id;

COMMENT ON VIEW wallet_withdrawal_security_status IS 
    'Security monitoring view for authorized withdrawal addresses.
     Flags:
     - NOT_SET: Wallet not yet funded or address not configured
     - BURN_ADDRESS_DANGER: CRITICAL - authorized address is burn address (should never happen)
     - OK: Normal state';


-- ============================================================================
-- 6. Create function to get funding source address для wallet
-- ============================================================================

CREATE OR REPLACE FUNCTION get_wallet_funding_source_address(p_wallet_id INTEGER)
RETURNS VARCHAR(42) AS $$
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
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_wallet_funding_source_address(INTEGER) IS 
    'Returns the CEX subaccount withdrawal address that originally funded this wallet.
     This is the address that should be set as authorized_withdrawal_address.
     Returns NULL if wallet not funded yet.';


-- ============================================================================
-- 7. Create procedure to initialize authorized addresses for existing funded wallets
-- ============================================================================

CREATE OR REPLACE PROCEDURE initialize_authorized_withdrawal_addresses()
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

COMMENT ON PROCEDURE initialize_authorized_withdrawal_addresses() IS 
    'One-time migration procedure to populate authorized_withdrawal_address for existing funded wallets.
     Looks up CEX subaccount that funded each wallet and sets it as authorized address.
     Run after migration to fix existing wallets.';


-- ============================================================================
-- 8. Security validation function
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_all_authorized_addresses()
RETURNS TABLE (
    wallet_id INTEGER,
    wallet_address VARCHAR,
    issue_type VARCHAR,
    issue_description TEXT
) AS $$
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
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_all_authorized_addresses() IS 
    'Security audit function. Returns all wallets with authorized address  issues.
     Run periodically to detect configuration drift or security violations.';


COMMIT;

-- ============================================================================
-- Post-migration actions (run manually if wallets already funded)
-- ============================================================================

-- Initialize authorized addresses for existing funded wallets
-- (Uncomment and run manually after migration if you have existing funded wallets)
-- CALL initialize_authorized_withdrawal_addresses();


-- ============================================================================
-- Verification queries (run after migration)
-- ============================================================================

-- Check 1: Column added
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'wallets'
  AND column_name = 'authorized_withdrawal_address';

-- Check 2: History table created
SELECT table_name
FROM information_schema.tables
WHERE table_name = 'wallet_withdrawal_address_history';

-- Check 3: Trigger created
SELECT trigger_name, event_manipulation, action_timing
FROM information_schema.triggers
WHERE trigger_name = 'trigger_log_authorized_withdrawal_address';

-- Check 4: Functions created
SELECT routine_name, routine_type
FROM information_schema.routines
WHERE routine_name IN (
    'validate_withdrawal_destination',
    'get_wallet_funding_source_address',
    'validate_all_authorized_addresses',
    'log_authorized_withdrawal_address_change'
)
ORDER BY routine_name;

-- Check 5: View created
SELECT table_name
FROM information_schema.views
WHERE table_name = 'wallet_withdrawal_security_status';

-- Check 6: Run security validation (should return 0 rows if all OK)
SELECT * FROM validate_all_authorized_addresses();
