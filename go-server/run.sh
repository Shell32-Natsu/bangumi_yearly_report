#!/bin/bash

# Enhanced Go server runner script for bangumi yearly report
# Supports graceful shutdown, logging, and error handling

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/server.pid"
MAX_RESTARTS=${MAX_RESTARTS:-10}
RESTART_DELAY=${RESTART_DELAY:-5}
ENABLE_AUTO_RESTART=${ENABLE_AUTO_RESTART:-true}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}"
}

log_info() {
    log "${GREEN}INFO${NC}" "$@"
}

log_warn() {
    log "${YELLOW}WARN${NC}" "$@"
}

log_error() {
    log "${RED}ERROR${NC}" "$@"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        log "${BLUE}DEBUG${NC}" "$@"
    fi
}

# Initialize environment
init() {
    # Check if Go is installed
    if ! command -v go &> /dev/null; then
        log_error "Go is not installed or not in PATH"
        exit 1
    fi
    
    # Check if main.go exists
    if [[ ! -f "${SCRIPT_DIR}/main.go" ]]; then
        log_error "main.go not found in ${SCRIPT_DIR}"
        exit 1
    fi
    
    # Check if config.txt exists
    if [[ ! -f "${SCRIPT_DIR}/config.txt" ]]; then
        log_warn "config.txt not found in ${SCRIPT_DIR}"
        log_info "The Go server may fail to start without proper configuration"
    fi
    
    log_info "Initialization complete"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    if [[ -f "${PID_FILE}" ]]; then
        local pid=$(cat "${PID_FILE}")
        if kill -0 "${pid}" 2>/dev/null; then
            log_info "Terminating server process (PID: ${pid})"
            kill -TERM "${pid}" 2>/dev/null || true
            sleep 2
            if kill -0 "${pid}" 2>/dev/null; then
                log_warn "Process didn't terminate gracefully, forcing kill"
                kill -KILL "${pid}" 2>/dev/null || true
            fi
        fi
        rm -f "${PID_FILE}"
    fi
}

# Signal handlers
handle_signal() {
    log_info "Received signal, shutting down..."
    cleanup
    exit 0
}

# Build the Go application
build_server() {
    log_info "Building Go server..."
    cd "${SCRIPT_DIR}"
    if go build -o bangumi-server main.go; then
        log_info "Build successful"
        return 0
    else
        log_error "Build failed"
        return 1
    fi
}

# Start the server
start_server() {
    cd "${SCRIPT_DIR}"
    log_info "Starting bangumi server..."
    
    # Start the server in background and capture PID
    if [[ -x "./bangumi-server" ]]; then
        ./bangumi-server 2>&1 &
    else
        go run main.go 2>&1 &
    fi
    
    local server_pid=$!
    echo "${server_pid}" > "${PID_FILE}"
    
    # Wait a moment to check if the server started successfully
    sleep 2
    if kill -0 "${server_pid}" 2>/dev/null; then
        log_info "Server started successfully (PID: ${server_pid})"
        return 0
    else
        log_error "Server failed to start"
        rm -f "${PID_FILE}"
        return 1
    fi
}

# Wait for server to exit
wait_for_server() {
    if [[ -f "${PID_FILE}" ]]; then
        local pid=$(cat "${PID_FILE}")
        log_info "Waiting for server process (PID: ${pid}) to exit..."
        wait "${pid}" 2>/dev/null || true
        rm -f "${PID_FILE}"
    fi
}

# Main execution function
main() {
    local restart_count=0
    
    log_info "Starting bangumi server runner"
    log_info "Script location: ${SCRIPT_DIR}"
    log_info "Auto-restart: ${ENABLE_AUTO_RESTART}"
    log_info "Max restarts: ${MAX_RESTARTS}"
    log_info "Restart delay: ${RESTART_DELAY}s"
    
    # Set up signal handlers
    trap handle_signal SIGTERM SIGINT SIGQUIT
    
    # Initialize environment
    init
    
    # Try to build the server first (optional optimization)
    build_server || log_warn "Pre-build failed, will use 'go run' instead"
    
    while true; do
        # Start the server
        if start_server; then
            restart_count=0
            wait_for_server
            log_warn "Server process exited"
        else
            log_error "Failed to start server"
        fi
        
        # Check if auto-restart is disabled
        if [[ "${ENABLE_AUTO_RESTART}" != "true" ]]; then
            log_info "Auto-restart is disabled, exiting"
            break
        fi
        
        # Check restart limit
        ((restart_count++))
        if [[ ${restart_count} -ge ${MAX_RESTARTS} ]]; then
            log_error "Maximum restart attempts (${MAX_RESTARTS}) reached, giving up"
            exit 1
        fi
        
        log_info "Restart attempt ${restart_count}/${MAX_RESTARTS} in ${RESTART_DELAY} seconds..."
        sleep "${RESTART_DELAY}"
    done
    
    log_info "Server runner stopped"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                cat << EOF
Usage: $0 [OPTIONS]

Options:
    --help, -h              Show this help message
    --no-restart            Disable automatic restart on failure
    --max-restarts NUM      Maximum number of restart attempts (default: 10)
    --restart-delay SEC     Delay between restart attempts in seconds (default: 5)
    --debug                 Enable debug logging
    --build-only            Only build the server, don't run it
    --stop                  Stop any running server instance

Environment Variables:
    MAX_RESTARTS            Maximum number of restart attempts
    RESTART_DELAY           Delay between restart attempts
    ENABLE_AUTO_RESTART     Enable/disable auto-restart (true/false)
    DEBUG                   Enable debug logging (true/false)

Examples:
    $0                      Start server with default settings
    $0 --no-restart         Start server without auto-restart
    $0 --max-restarts 5     Start with maximum 5 restart attempts
    $0 --debug              Start with debug logging enabled
    $0 --stop               Stop any running server
EOF
                exit 0
                ;;
            --no-restart)
                ENABLE_AUTO_RESTART=false
                shift
                ;;
            --max-restarts)
                MAX_RESTARTS="$2"
                shift 2
                ;;
            --restart-delay)
                RESTART_DELAY="$2"
                shift 2
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            --build-only)
                init
                build_server
                exit $?
                ;;
            --stop)
                cleanup
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    parse_args "$@"
    main
fi
