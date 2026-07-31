#!/usr/bin/env bash
# Shared logging helpers. Logs to stderr and to journald via logger(1), per
# technical-design.md's "Log all session transitions using journald".
#
# Always stderr, even for INFO: several functions in this codebase (e.g.
# htpc_snapshot_create) both log progress *and* return a value by printing
# it to stdout for callers to capture via command substitution. Logging to
# stdout would corrupt that return value with human-readable log text.

htpc_log() {
    local level="$1"
    shift
    local message="$*"

    printf '[%s] %s\n' "${level}" "${message}" >&2

    if command -v logger >/dev/null 2>&1; then
        logger -t cachyos-htpc -- "${level}: ${message}" || true
    fi
}

htpc_log_info()  { htpc_log "INFO" "$@"; }
htpc_log_warn()  { htpc_log "WARN" "$@"; }
htpc_log_error() { htpc_log "ERROR" "$@"; }
