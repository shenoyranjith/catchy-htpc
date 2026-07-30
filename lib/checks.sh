#!/usr/bin/env bash
# System verification checks. Requires lib/log.sh to be sourced first.

htpc_os_release_value() {
    local key="$1"

    awk -F= -v key="${key}" \
        '$1 == key { val = $2; gsub(/^"|"$/, "", val); print val; exit }' \
        /etc/os-release
}

htpc_verify_cachyos() {
    local os_id os_id_like

    if [[ ! -r /etc/os-release ]]; then
        htpc_log_error "Cannot read /etc/os-release; unable to verify CachyOS."
        return 1
    fi

    os_id="$(htpc_os_release_value ID)"
    os_id_like="$(htpc_os_release_value ID_LIKE)"

    if [[ "${os_id}" == "cachyos" || "${os_id_like}" == *cachyos* ]]; then
        htpc_log_info "Verified CachyOS (ID=${os_id})."
        return 0
    fi

    htpc_log_error "This system does not appear to be CachyOS (ID=${os_id})."
    return 1
}

htpc_verify_btrfs() {
    local root_fstype

    if ! command -v findmnt >/dev/null 2>&1; then
        htpc_log_error "findmnt not found; cannot verify the root filesystem."
        return 1
    fi

    root_fstype="$(findmnt --noheadings --output FSTYPE --target /)"

    if [[ "${root_fstype}" != "btrfs" ]]; then
        htpc_log_error "Root filesystem is '${root_fstype}', not btrfs."
        return 1
    fi

    htpc_log_info "Verified root filesystem is btrfs."
    return 0
}
