#!/bin/bash
set -eo pipefail
shopt -s nullglob

source ./paths.sh
source "${LIB_PATH}/core/logging.sh"
source "${LIB_PATH}/postgres-config.sh"
source "${LIB_PATH}/cleanup-functions.sh"

# Set up cleanup trap
trap cleanup SIGTERM SIGINT EXIT

# Main entrypoint logic
main() {
    # Environment setup
    HOST=${HOST:-localhost}
    PORT=${POSTGRES_PORT:-5432}
    NODE_ID="${HOSTNAME:-$(hostname)}:${PORT}"

    # Check if command starts with an option
    if [ "${1:0:1}" = '-' ]; then
        set -- postgres "$@"
    fi

    # Check for help flags
    for arg; do
        case "$arg" in
            --help|--version|-V)
                exec "$@"
                ;;
        esac
    done

    if [ "$1" = 'postgres' ]; then
        exec "${LIB_PATH}/standalone-start.sh" "$@"
    fi

    # If we got here, just execute the command
    exec "$@"
}

main "$@"
