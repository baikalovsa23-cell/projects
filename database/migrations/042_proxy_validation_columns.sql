-- Migration: Add proxy validation columns to proxy_pool table
-- Version: 042
-- Description: Adds fields for proxy validation tracking

-- Add validation_status column
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'proxy_pool' AND column_name = 'validation_status') THEN
        ALTER TABLE proxy_pool ADD COLUMN validation_status VARCHAR(20) DEFAULT 'unknown';
    END IF;
END $$;

-- Add last_validated_at column
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'proxy_pool' AND column_name = 'last_validated_at') THEN
        ALTER TABLE proxy_pool ADD COLUMN last_validated_at TIMESTAMPTZ;
    END IF;
END $$;

-- Add validation_error column
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'proxy_pool' AND column_name = 'validation_error') THEN
        ALTER TABLE proxy_pool ADD COLUMN validation_error TEXT;
    END IF;
END $$;

-- Add response_time_ms column
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'proxy_pool' AND column_name = 'response_time_ms') THEN
        ALTER TABLE proxy_pool ADD COLUMN response_time_ms INTEGER;
    END IF;
END $$;

-- Add detected_ip column
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'proxy_pool' AND column_name = 'detected_ip') THEN
        ALTER TABLE proxy_pool ADD COLUMN detected_ip VARCHAR(45);
    END IF;
END $$;

-- Add detected_country column
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_name = 'proxy_pool' AND column_name = 'detected_country') THEN
        ALTER TABLE proxy_pool ADD COLUMN detected_country VARCHAR(2);
    END IF;
END $$;

-- Create index for validation queries
DROP INDEX IF EXISTS idx_proxy_pool_validation;
CREATE INDEX idx_proxy_pool_validation ON proxy_pool(validation_status, is_active);

-- Verify columns were added
SELECT column_name, data_type, is_nullable, column_default 
FROM information_schema.columns 
WHERE table_name = 'proxy_pool' 
AND column_name IN ('validation_status', 'last_validated_at', 'validation_error', 
                    'response_time_ms', 'detected_ip', 'detected_country')
ORDER BY column_name;
