#!/bin/bash

# Prevent multiple inclusion
[ -n "${CORE_CONSTANTS_SOURCED}" ] && return 0
declare -g CORE_CONSTANTS_SOURCED=1

# PostgreSQL timeouts and retry settings
declare -gr PG_START_TIMEOUT=30
declare -gr PG_MAX_RETRIES=5
declare -gr PG_CONNECT_TIMEOUT=10

# File paths
declare -gr CONFIG_DIR="/etc/postgresql"
declare -gr PG_LOG_DIR="/var/log/postgresql"
declare -gr DATA_DIR="${PGDATA:-/var/lib/postgresql/data}"
declare -gr RUN_DIR="/var/run/postgresql"
