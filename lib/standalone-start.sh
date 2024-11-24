#!/bin/bash
set -e

source "${LIB_PATH}/core/logging.sh"
source "${LIB_PATH}/core/log-config.sh"
source "${LIB_PATH}/postgres-config.sh"

log_info "Starting PostgreSQL in standalone mode..."

# Set role for this instance
ROLE="standalone"

# Initialize database if needed
initialize_database() {
    if [ -f "$PGDATA/PG_VERSION" ]; then
        log_info "Using existing PostgreSQL database"
        return 0
    fi

    log_info "Initializing PostgreSQL database cluster..."
    
    # Validate PGDATA path
    if [ -z "$PGDATA" ]; then
        log_error "PGDATA environment variable is not set"
        return 1
    fi
    
    # Create PGDATA directory with proper permissions
    if ! mkdir -p "$PGDATA"; then
        log_error "Failed to create PGDATA directory: $PGDATA"
        return 1
    fi
    
    if ! chown postgres:postgres "$PGDATA"; then
        log_error "Failed to set PGDATA ownership"
        return 1
    fi
    
    if ! chmod 700 "$PGDATA"; then
        log_error "Failed to set PGDATA permissions"
        return 1
    fi

    # Clear existing invalid cluster if present
    if [ -d "$PGDATA" ] && [ ! -f "$PGDATA/PG_VERSION" ]; then
        log_info "Removing invalid PostgreSQL data directory..."
        if ! rm -rf "$PGDATA"/*; then
            log_error "Failed to clean PGDATA directory"
            return 1
        fi
    fi

    # Initialize the database with proper error handling
    if ! initdb --username=postgres --pwfile=<(echo "$POSTGRES_PASSWORD"); then
        log_error "Database initialization failed"
        return 1
    fi

    # Generate optimized configuration after initialization
    if ! generate_postgres_configs; then
        log_error "Failed to generate PostgreSQL configurations"
        return 1
    fi

    log_info "Database initialization completed successfully"
    return 0
}

# Run initialization
if ! initialize_database; then
    log_error "Database initialization failed"
    exit 1
fi

# Handle password setup
if [ -z "${POSTGRES_PASSWORD}" ] && [ -z "${POSTGRES_HOST_AUTH_METHOD}" ]; then
    log_error "No password has been set for the PostgreSQL superuser. You must:"
    log_error "  - set POSTGRES_PASSWORD"
    log_error "  - set POSTGRES_HOST_AUTH_METHOD=trust to allow passwordless connections"
    exit 1
fi

# Start PostgreSQL
log_info "Starting PostgreSQL server..."

# Configure initial password if needed
configure_password() {
    if [ ! -n "${POSTGRES_PASSWORD}" ]; then
        log_info "No password specified, skipping password configuration"
        return 0
    fi

    if [ -f "${PGDATA}/.password_set" ]; then
        log_info "Password already configured"
        return 0
    fi

    log_info "Configuring initial PostgreSQL password..."

    # Create a temporary password file
    local temp_pass_file=$(mktemp)
    echo "${POSTGRES_PASSWORD}" > "$temp_pass_file"
    chmod 600 "$temp_pass_file"

    # Start PostgreSQL with temporary config
    postgres -c authentication_timeout=60 & 
    local PG_PID=$!

    # Wait for PostgreSQL to be ready with timeout
    local start_time=$(date +%s)
    while ! pg_isready -q -h localhost; do
        if [ $(($(date +%s) - start_time)) -gt ${PG_START_TIMEOUT} ]; then
            kill $PG_PID 2>/dev/null
            rm -f "$temp_pass_file"
            log_error "Timeout waiting for PostgreSQL to start"
            return 1
        fi
        sleep 1
    done

    # Set password with proper error handling and verification
    if ! psql -v ON_ERROR_STOP=1 --username postgres <<-EOSQL
        BEGIN;
        ALTER USER postgres PASSWORD '${POSTGRES_PASSWORD}';
        COMMIT;
EOSQL
    then
        kill $PG_PID 2>/dev/null
        rm -f "$temp_pass_file"
        log_error "Failed to set PostgreSQL password"
        return 1
    fi

    # Verify password was set correctly
    if ! PGPASSFILE="$temp_pass_file" psql -w -U postgres -c "SELECT 1" >/dev/null 2>&1; then
        kill $PG_PID 2>/dev/null
        rm -f "$temp_pass_file"
        log_error "Password verification failed"
        return 1
    fi

    # Cleanup temporary password file
    rm -f "$temp_pass_file"

    # Mark password as set atomically
    if ! touch "${PGDATA}/.password_set"; then
        kill $PG_PID 2>/dev/null
        log_error "Failed to mark password as configured"
        return 1
    fi

    # Stop temporary instance gracefully
    if ! pg_ctl stop -D "$PGDATA" -m fast -t 30; then
        kill -9 $PG_PID 2>/dev/null
        log_error "Failed to stop temporary PostgreSQL instance"
        return 1
    fi

    wait $PG_PID 2>/dev/null
    log_info "Password configuration completed successfully"
    return 0
}

# Configure password
if ! configure_password; then
    log_error "Password configuration failed"
    exit 1
fi

# Wait for PostgreSQL to be ready
wait_for_postgres() {
    local -r max_attempts=${PG_START_TIMEOUT:-30}
    local -r check_interval=1
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if pg_isready -h localhost -p "${POSTGRES_PORT:-5432}" >/dev/null 2>&1; then
            log_info "PostgreSQL is ready"
            return 0
        fi
        
        log_info "Waiting for PostgreSQL to start (attempt $attempt/$max_attempts)..."
        sleep $check_interval
        attempt=$((attempt + 1))
    done

    log_error "PostgreSQL failed to start after $max_attempts seconds"
    return 1
}

# Start PostgreSQL and wait for it to be ready
postgres &
PG_PID=$!

if ! wait_for_postgres; then
    log_error "Failed to start PostgreSQL"
    kill $PG_PID 2>/dev/null
    exit 1
fi

# Keep running until signal received
wait $PG_PID
