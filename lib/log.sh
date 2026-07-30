#!/usr/bin/env bash
# Shared logging helpers. Logs to stdout/stderr and to journald via logger(1),
# per technical-design.md's "Log all session transitions using journald".

htpc_log() {
    local level="$1"
    shift
    local message="$*"

    case "${level}" in
        ERROR|WARN)
            printf '[%s] %s\n' "${level}" "${message}" >&2
            ;;
        *)
            printf '[%s] %s\n' "${level}" "${message}"
            ;;
    esac

    if command -v logger >/dev/null 2>&1; then
        logger -t cachyos-htpc -- "${level}: ${message}" || true
    fi
}

htpc_log_info()  { htpc_log "INFO" "$@"; }
htpc_log_warn()  { htpc_log "WARN" "$@"; }
htpc_log_error() { htpc_log "ERROR" "$@"; }
