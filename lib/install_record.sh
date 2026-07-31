#!/usr/bin/env bash
# Reads and writes the installation record used by the uninstaller. See
# "Installation Record" in installer-spec.md. Requires lib/log.sh.
#
# A simple KEY=VALUE file. Values must not contain newlines; that's the
# only constraint, since every recorded value (a username, a unit name, a
# space-separated package list, a snapshot name) fits it comfortably.

HTPC_INSTALL_RECORD_PATH="/var/lib/cachyos-htpc/install-record"

htpc_install_record_exists() {
    [[ -f "${HTPC_INSTALL_RECORD_PATH}" ]]
}

# Idempotently sets KEY=VALUE in the install record, creating the record
# (and its parent directory) if needed, and replacing any existing line
# for that key rather than duplicating it.
htpc_install_record_set() {
    local key="$1" value="$2"
    local record="${HTPC_INSTALL_RECORD_PATH}"

    install -d -m 0755 "$(dirname "${record}")"
    touch "${record}"

    if grep -q "^${key}=" "${record}"; then
        sed -i "s|^${key}=.*|${key}=${value}|" "${record}"
    else
        printf '%s=%s\n' "${key}" "${value}" >> "${record}"
    fi
}

# Prints the value for KEY from the install record, or nothing if the
# record or the key doesn't exist.
htpc_install_record_get() {
    local key="$1"
    local record="${HTPC_INSTALL_RECORD_PATH}"

    if [[ ! -f "${record}" ]]; then
        return 0
    fi
    sed -n "s|^${key}=||p" "${record}" | tail -n1
}

# Merges the given items into a space-separated list value for KEY,
# preserving whatever was already recorded by a prior run instead of
# overwriting it -- important for values like "packages installed by the
# installer", which must keep accumulating correctly across reruns even
# once earlier-installed packages no longer show up as newly missing.
# De-duplicates; items must not themselves contain spaces.
htpc_install_record_append_unique() {
    local key="$1"
    shift
    local existing combined

    existing="$(htpc_install_record_get "${key}")"
    # shellcheck disable=SC2086 # intentional word-splitting of a space-separated list
    combined="$(printf '%s\n' ${existing} "$@" | awk 'NF' | sort -u | tr '\n' ' ')"
    combined="${combined% }"

    htpc_install_record_set "${key}" "${combined}"
}

# Removes the install record file entirely, and its parent directory too
# if that's now empty. Called at the end of uninstallation, once every
# value that needs to be read from it (target user, recorded packages,
# etc.) has already been captured.
htpc_install_record_remove() {
    local record="${HTPC_INSTALL_RECORD_PATH}" dir

    dir="$(dirname "${record}")"
    rm -f "${record}"
    rmdir "${dir}" 2>/dev/null || true

    htpc_log_info "Removed installation record."
}
