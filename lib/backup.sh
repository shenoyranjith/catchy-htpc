#!/usr/bin/env bash
# Helper for safely backing up configuration files before modifying them.
# Requires lib/log.sh to be sourced first.

htpc_backup_file() {
    local path="$1"
    local backup="${path}.htpc-backup"

    if [[ ! -f "${path}" ]]; then
        return 0
    fi

    if [[ -f "${backup}" ]]; then
        htpc_log_info "Backup already exists for ${path}; leaving it in place."
        return 0
    fi

    cp -a -- "${path}" "${backup}"
    htpc_log_info "Backed up ${path} to ${backup}."
}
