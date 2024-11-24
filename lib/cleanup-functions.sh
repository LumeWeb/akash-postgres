#!/bin/bash

# Cleanup function to stop PostgreSQL and cleanup resources
cleanup() {
    local err=$?
    
    # Stop log monitoring
    if [ -f "${PG_LOG_DIR}/postgresql.log.monitor.pid" ]; then
        kill $(cat "${PG_LOG_DIR}/postgresql.log.monitor.pid") 2>/dev/null || true
        rm -f "${PG_LOG_DIR}/postgresql.log.monitor.pid"
    fi
    
    # Stop PostgreSQL if running
    if [ -f "${PGDATA}/postmaster.pid" ]; then
        pg_ctl stop -D "$PGDATA" -m fast || true
    fi
    
    # Cleanup any temporary files
    rm -f /tmp/.s.PGSQL.* 2>/dev/null || true
    
    exit $err
}
