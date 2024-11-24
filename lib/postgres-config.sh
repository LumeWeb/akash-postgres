#!/bin/bash

# Prevent multiple inclusion
[ -n "${POSTGRES_CONFIG_SOURCED}" ] && return 0
declare -g POSTGRES_CONFIG_SOURCED=1

source "${LIB_PATH}/core/logging.sh"
source "${LIB_PATH}/core/constants.sh"

# Generate optimized PostgreSQL configurations based on available resources
generate_postgres_configs() {
    # Detect environment and resources
    local in_kubernetes=0
    local env_type="Standard"
    local mem_source="System Memory"
    local cpu_source="System CPU"
    
    # Kubernetes detection
    if [ -f "/var/run/secrets/kubernetes.io/serviceaccount/namespace" ]; then
        in_kubernetes=1
        env_type="Kubernetes"
        log_info "Detected Kubernetes environment"
        
        # Get namespace
        local k8s_namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
        log_info "Kubernetes Namespace: $k8s_namespace"
    fi

    # Memory detection
    local mem_bytes
    local mem_mb
    if [ $in_kubernetes -eq 1 ] && [ -f "/sys/fs/cgroup/memory/memory.limit_in_bytes" ]; then
        mem_source="Kubernetes cgroup limit"
        mem_bytes=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)
        # Convert to MB and apply 85% limit for k8s overhead
        mem_mb=$((mem_bytes / 1024 / 1024 * 85 / 100))
        log_info "Memory Source: Kubernetes cgroup limit (85% allocation)"
    else
        mem_bytes=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
        mem_mb=$((mem_bytes / 1024))
        log_info "Memory Source: System memory (100% allocation)"
    fi

    if [ -z "$mem_mb" ] || [ "$mem_mb" -eq 0 ]; then
        log_error "Could not determine system memory"
        return 1
    fi

    # CPU detection
    local cpu_cores
    if [ $in_kubernetes -eq 1 ] && [ -f "/sys/fs/cgroup/cpu/cpu.cfs_quota_us" ]; then
        cpu_source="Kubernetes CPU quota"
        local cpu_quota=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us)
        local cpu_period=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us)
        
        if [ $cpu_quota -gt 0 ]; then
            cpu_cores=$((cpu_quota / cpu_period))
            log_info "CPU Cores (from quota): $cpu_cores"
        else
            cpu_cores=$(nproc)
            log_info "CPU Cores (from nproc): $cpu_cores"
        fi
    else
        cpu_cores=$(nproc)
        log_info "CPU Cores (from system): $cpu_cores"
    fi

    if [ -z "$cpu_cores" ] || [ "$cpu_cores" -eq 0 ]; then
        log_error "Could not determine CPU cores"
        return 1
    fi

    # Log configuration detection
    log_info "Environment Configuration Detected:"
    log_info "--------------------------------"
    log_info "Environment Type: $env_type"
    log_info "Memory Source: $mem_source"
    log_info "Total Memory: ${mem_mb}MB"
    log_info "CPU Source: $cpu_source"
    log_info "CPU Cores: $cpu_cores"
    log_info "--------------------------------"

    # Calculate key memory settings
    local shared_buffers=$((mem_mb * 25 / 100))  # 25% of total memory
    local effective_cache_size=$((mem_mb * 75 / 100))  # 75% of total memory
    local maintenance_work_mem=$((mem_mb * 5 / 100))  # 5% of total memory
    local work_mem=$((mem_mb * 1 / 100))  # 1% of total memory per connection

    # Setup logging configuration
    if ! setup_logging; then
        log_error "Failed to setup logging configuration"
        return 1
    fi

    # Generate configuration file
    local config_file="${PGDATA}/postgresql.conf"
    
    cat > "$config_file" << EOF
# Connection Settings
listen_addresses = '*'
port = ${POSTGRES_PORT:-5432}
max_connections = $((mem_mb / 4))  # Roughly 4MB per connection

# Memory Settings
shared_buffers = ${shared_buffers}MB
effective_cache_size = ${effective_cache_size}MB
maintenance_work_mem = ${maintenance_work_mem}MB
work_mem = ${work_mem}MB
huge_pages = try
temp_buffers = 16MB

# Background Writer
bgwriter_delay = 200ms
bgwriter_lru_maxpages = 100
bgwriter_lru_multiplier = 2.0

# WAL Settings
wal_level = replica
wal_buffers = 16MB
checkpoint_completion_target = 0.9
max_wal_size = 1GB
min_wal_size = 80MB

# Query Planner
random_page_cost = 1.1
effective_io_concurrency = 200
default_statistics_target = 100

# Parallel Query
max_worker_processes = $cpu_cores
max_parallel_workers_per_gather = $((cpu_cores / 2))
max_parallel_workers = $cpu_cores
parallel_leader_participation = on



# Autovacuum
autovacuum = on
autovacuum_max_workers = $((cpu_cores / 2))
autovacuum_naptime = 1min
autovacuum_vacuum_threshold = 50
autovacuum_vacuum_scale_factor = 0.05
autovacuum_analyze_threshold = 50
autovacuum_analyze_scale_factor = 0.05

# Client Connection Defaults
timezone = 'UTC'
lc_messages = 'en_US.utf8'
lc_monetary = 'en_US.utf8'
lc_numeric = 'en_US.utf8'
lc_time = 'en_US.utf8'

# SSL Configuration
ssl = off
#ssl_cert_file = 'server.crt'
#ssl_key_file = 'server.key'
EOF

    # Set proper permissions
    chmod 600 "$config_file"
    
    # Create pg_hba.conf for authentication
    cat > "${PGDATA}/pg_hba.conf" << EOF
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all            all                                     trust
host    all            all             127.0.0.1/32           scram-sha-256
host    all            all             ::1/128                scram-sha-256
host    all            all             0.0.0.0/0              scram-sha-256
EOF

    chmod 600 "${PGDATA}/pg_hba.conf"

    log_info "PostgreSQL configuration generated successfully"
    return 0
}
