#!/bin/bash

# Prevent multiple inclusion
[ -n "${LOG_CONFIG_SOURCED}" ] && return 0
declare -g LOG_CONFIG_SOURCED=1

source "${LIB_PATH}/core/constants.sh"
source "${LIB_PATH}/core/logging.sh"

# Logging configuration
declare -gr LOG_ROTATION_AGE="1d"
declare -gr LOG_ROTATION_SIZE="100MB"
declare -gr LOG_MAX_FILES=10
declare -gr LOG_LINE_PREFIX='%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '

# Configure PostgreSQL logging
setup_logging() {
    local log_dir="${PGDATA}/log"
    
    # Ensure log directory exists with proper permissions
    if ! mkdir -p "$log_dir"; then
        log_error "Failed to create log directory: $log_dir"
        return 1
    fi
    
    if ! chmod 700 "$log_dir"; then
        log_error "Failed to set log directory permissions"
        return 1
    fi
    
    if ! chown postgres:postgres "$log_dir"; then
        log_error "Failed to set log directory ownership"
        return 1
    fi

    # Generate logging configuration
    cat >> "${PGDATA}/postgresql.conf" << EOF

# Logging Configuration
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_rotation_age = ${LOG_ROTATION_AGE}
log_rotation_size = ${LOG_ROTATION_SIZE}
log_truncate_on_rotation = on
log_min_duration_statement = 1000
log_line_prefix = '${LOG_LINE_PREFIX}'
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0
log_autovacuum_min_duration = 0
log_error_verbosity = verbose
log_statement = 'ddl'

# File retention
log_file_mode = 0600
log_timezone = 'UTC'
EOF

    log_info "Logging configuration completed successfully"
    return 0
}

# Start log monitoring
start_log_monitor() {
    local log_file="${PGDATA}/log/postgresql.log"
    local monitor_pid_file="${PGDATA}/log/monitor.pid"
    
    # Stop existing monitor if running
    if [ -f "$monitor_pid_file" ]; then
        kill $(cat "$monitor_pid_file") 2>/dev/null || true
        rm -f "$monitor_pid_file"
    fi
    
    # Start new monitor
    monitor_log "$log_file" "$monitor_pid_file"
    
    log_info "Log monitoring started"
    return 0
}

# Cleanup old log files
cleanup_logs() {
    local log_dir="${PGDATA}/log"
    local max_files=${LOG_MAX_FILES}
    
    # Keep only the most recent files
    if [ -d "$log_dir" ]; then
        ls -t "$log_dir"/postgresql-*.log | tail -n +$((max_files + 1)) | xargs -r rm --
        log_info "Old log files cleaned up"
    fi
    
    return 0
}
