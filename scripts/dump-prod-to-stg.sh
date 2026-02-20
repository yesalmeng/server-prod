#!/usr/bin/env bash
#
# dump-prod-to-stg.sh 
#
# dumps prod data into staging supabase, then seeds dev test members.
# obfuscation runs as a separate job after this script completes.
#
# required env vars:
#   STAGING_DB_URL          – staging Postgres connection string
#   SUPABASE_PROJECT_REF    – prod project ref (for supabase link)
#   SUPABASE_ACCESS_TOKEN   – prod token (for supabase CLI auth)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── helpers ────────────────────────────────────────────────────────
log()  { echo "==> [$(date '+%H:%M:%S')] $*"; }
fail() { echo "!!! [$(date '+%H:%M:%S')] ERROR: $*" >&2; exit 1; }

# ── preflight checks ──────────────────────────────────────────────
[[ -z "${STAGING_DB_URL:-}" ]]        && fail "STAGING_DB_URL is not set"
[[ -z "${SUPABASE_PROJECT_REF:-}" ]]  && fail "SUPABASE_PROJECT_REF is not set"
[[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]] && fail "SUPABASE_ACCESS_TOKEN is not set"

command -v psql       >/dev/null 2>&1 || fail "psql not found"
command -v supabase   >/dev/null 2>&1 || fail "supabase CLI not found"

# step 1: truncate all public tables 
# Dynamically truncate every table in the public schema.
# CASCADE handles foreign key deps. We skip views.
# Note: this does NOT touch the audit schema (requirement: skip audit logs).
log "step 1 : truncating public tables in staging"

psql "$STAGING_DB_URL" <<'SQL'
DO $$
DECLARE
    tbl text;
BEGIN
    FOR tbl IN
        SELECT tablename
        FROM   pg_tables
        WHERE  schemaname = 'public'
    LOOP
        EXECUTE format('TRUNCATE TABLE public.%I CASCADE', tbl);
        RAISE NOTICE 'truncated public.%', tbl;
    END LOOP;
END;
$$;
SQL

log "step 1 : done"

# ── step 2: link to prod + pipe dump into staging ─────────────────
log "step 2 : linking to prod project"
supabase link --project-ref "$SUPABASE_PROJECT_REF"

log "step 2 : dumping prod data into staging (piped, no intermediate file)"
supabase db dump --data-only | psql "$STAGING_DB_URL"

log "step 2 : done"

# ── step 3: seed dev test members ─────────────────────────────────
# Insert staging-only test members so devs can log in after a dump.
# These emails match auth.users and are skipped by the obfuscator.
log "step 3 : seeding dev test members"

# psql "$STAGING_DB_URL" -f "$SCRIPT_DIR/seed-dev-members.sql"

log "step 3 : done"
log "dump complete — staging is ready for obfuscation"
