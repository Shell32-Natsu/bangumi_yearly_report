#!/bin/bash

# Enhanced Go server runner script for bangumi yearly report
# Supports graceful shutdown, logging, and error handling

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/server.pid"
MAX_RESTARTS=${MAX_RESTARTS:-10}
RESTART_DELAY=${RESTART_DELAY:-5}

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
    
    # Clean up monitor process
    local monitor_pid_file="${SCRIPT_DIR}/monitor.pid"
    if [[ -f "${monitor_pid_file}" ]]; then
        local monitor_pid=$(cat "${monitor_pid_file}")
        if kill -0 "${monitor_pid}" 2>/dev/null; then
            log_info "Terminating monitor process (PID: ${monitor_pid})"
            kill -TERM "${monitor_pid}" 2>/dev/null || true
            sleep 2
            if kill -0 "${monitor_pid}" 2>/dev/null; then
                log_warn "Monitor didn't terminate gracefully, forcing kill"
                kill -KILL "${monitor_pid}" 2>/dev/null || true
            fi
        fi
        rm -f "${monitor_pid_file}"
    fi
    
    # Clean up server process
    if [[ -f "${PID_FILE}" ]]; then
        local pid=$(cat "${PID_FILE}")
        if kill -0 "${pid}" 2>/dev/null; then
            log_info "Terminating server process (PID: ${pid})"
            kill -TERM "${pid}" 2>/dev/null || true
            sleep 2
            if kill -0 "${pid}" 2>/dev/null; then
                log_warn "Server didn't terminate gracefully, forcing kill"
                kill -KILL "${pid}" 2>/dev/null || true
            fi
        fi
        rm -f "${PID_FILE}"
    fi
    
    # Clean up temporary monitor script
    local monitor_script="${SCRIPT_DIR}/monitor.sh"
    if [[ -f "${monitor_script}" ]]; then
        rm -f "${monitor_script}"
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

# Start the server with auto-restart monitoring
start_server() {
    cd "${SCRIPT_DIR}"
    log_info "Starting bangumi server with auto-restart monitoring..."
    
    # Create a monitoring script that will restart the server if it exits
    local monitor_script="${SCRIPT_DIR}/monitor.sh"
    cat > "${monitor_script}" << 'EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/server.pid"
MONITOR_PID_FILE="${SCRIPT_DIR}/monitor.pid"
MAX_RESTARTS=${MAX_RESTARTS:-10}
RESTART_DELAY=${RESTART_DELAY:-5}

# Store monitor PID
echo $$ > "${MONITOR_PID_FILE}"

log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${timestamp} [MONITOR] $*"
}

cleanup_monitor() {
    log "Monitor shutting down..."
    if [[ -f "${PID_FILE}" ]]; then
        local pid=$(cat "${PID_FILE}")
        if kill -0 "${pid}" 2>/dev/null; then
            log "Terminating server process (PID: ${pid})"
            kill -TERM "${pid}" 2>/dev/null || true
            sleep 2
            if kill -0 "${pid}" 2>/dev/null; then
                log "Process didn't terminate gracefully, forcing kill"
                kill -KILL "${pid}" 2>/dev/null || true
            fi
        fi
        rm -f "${PID_FILE}"
    fi
    rm -f "${MONITOR_PID_FILE}"
    exit 0
}

trap cleanup_monitor SIGTERM SIGINT SIGQUIT

restart_count=0
while true; do
    # Start the server
    cd "${SCRIPT_DIR}"
    if [[ -x "./bangumi-server" ]]; then
        ./bangumi-server &
    else
        go run main.go &
    fi
    
    server_pid=$!
    echo "${server_pid}" > "${PID_FILE}"
    
    # Wait a moment to check if the server started successfully
    sleep 2
    if kill -0 "${server_pid}" 2>/dev/null; then
        log "Server started successfully (PID: ${server_pid})"
        restart_count=0
        wait "${server_pid}" 2>/dev/null || true
        log "Server process exited"
        rm -f "${PID_FILE}"
    else
        log "Server failed to start"
        rm -f "${PID_FILE}"
    fi
    
    # Check restart limit
    ((restart_count++))
    if [[ ${restart_count} -ge ${MAX_RESTARTS} ]]; then
        log "Maximum restart attempts (${MAX_RESTARTS}) reached, giving up"
        cleanup_monitor
    fi
    
    log "Restart attempt ${restart_count}/${MAX_RESTARTS} in ${RESTART_DELAY} seconds..."
    sleep "${RESTART_DELAY}"
done
EOF
    
    chmod +x "${monitor_script}"
    
    # Start the monitor in the background
    nohup "${monitor_script}" > "${SCRIPT_DIR}/monitor.log" 2>&1 &
    local monitor_pid=$!
    
    # Wait a moment to ensure monitor started successfully
    sleep 1
    if kill -0 "${monitor_pid}" 2>/dev/null; then
        log_info "Server monitoring started successfully (Monitor PID: ${monitor_pid})"
        log_info "Monitor logs: ${SCRIPT_DIR}/monitor.log"
        return 0
    else
        log_error "Failed to start monitoring"
        return 1
    fi
}


# Main execution function
main() {
    log_info "Starting bangumi server runner"
    log_info "Script location: ${SCRIPT_DIR}"
    log_info "Max restarts: ${MAX_RESTARTS}"
    log_info "Restart delay: ${RESTART_DELAY}s"
    
    # Initialize environment
    init
    
    # Try to build the server first (optional optimization)
    build_server || log_warn "Pre-build failed, will use 'go run' instead"
    
    # Start the server with monitoring
    if start_server; then
        log_info "Server started with monitoring. Script will now exit."
        log_info "Use '$0 --stop' to stop the server and monitoring."
        exit 0
    else
        log_error "Failed to start server"
        exit 1
    fi
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
    --max-restarts NUM      Maximum number of restart attempts (default: 10)
    --restart-delay SEC     Delay between restart attempts in seconds (default: 5)
    --debug                 Enable debug logging
    --build-only            Only build the server, don't run it
    --stop                  Stop any running server instance

Environment Variables:
    MAX_RESTARTS            Maximum number of restart attempts
    RESTART_DELAY           Delay between restart attempts
    DEBUG                   Enable debug logging (true/false)

Examples:
    $0                      Start server with auto-restart monitoring
    $0 --max-restarts 5     Start with maximum 5 restart attempts
    $0 --debug              Start with debug logging enabled
    $0 --stop               Stop any running server
EOF
                exit 0
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
