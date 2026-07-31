#!/usr/bin/env bash
# Installs the Kodi Program Add-ons and seeds favourites.xml for the target
# user. See kodi-addon-spec.md and installer-spec.md. Requires lib/log.sh.

HTPC_KODI_ADDONS=(script.htpc.steam script.htpc.desktop)

htpc_kodi_addons_source_dir() {
    cd "$(dirname "${BASH_SOURCE[0]}")/../kodi-addons" && pwd
}

htpc_favourites_script_path() {
    printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/htpc_favourites.py"
}

# Prints the target user's Kodi home directory (~/.kodi).
htpc_kodi_home() {
    local target_user="$1"
    local home
    home="$(getent passwd "${target_user}" | cut -d: -f6)"
    if [[ -z "${home}" ]]; then
        htpc_log_error "Could not determine home directory for user ${target_user}."
        return 1
    fi
    printf '%s/.kodi\n' "${home}"
}

# Installs the Steam Gaming Mode and Desktop Mode Program add-ons into the
# target user's Kodi addons directory. Always re-copies (these are
# project-managed files the user is not expected to edit), then fixes
# ownership.
htpc_kodi_addons_install() {
    local target_user="$1"
    local kodi_home addons_dir source_dir name

    kodi_home="$(htpc_kodi_home "${target_user}")" || return 1
    addons_dir="${kodi_home}/addons"
    source_dir="$(htpc_kodi_addons_source_dir)"

    install -d -o "${target_user}" -g "${target_user}" -m 0755 \
        "${kodi_home}" "${addons_dir}"

    for name in "${HTPC_KODI_ADDONS[@]}"; do
        if [[ ! -d "${source_dir}/${name}" ]]; then
            htpc_log_error "No add-on source found at ${source_dir}/${name}."
            return 1
        fi
        rm -rf "${addons_dir:?}/${name}"
        cp -a "${source_dir}/${name}" "${addons_dir}/${name}"
        chown -R "${target_user}:${target_user}" "${addons_dir}/${name}"
        htpc_log_info "Installed Kodi add-on ${name} for ${target_user}."
    done
}

# Seeds favourites.xml with entries launching both add-ons, preserving any
# existing favourites. Idempotent: never duplicates entries it already
# added on a prior run.
htpc_kodi_favourites_seed() {
    local target_user="$1"
    local kodi_home favourites_path script

    kodi_home="$(htpc_kodi_home "${target_user}")" || return 1
    favourites_path="${kodi_home}/userdata/favourites.xml"
    script="$(htpc_favourites_script_path)"

    install -d -o "${target_user}" -g "${target_user}" -m 0755 \
        "${kodi_home}/userdata"

    if ! python3 "${script}" "${favourites_path}" \
        "Steam Gaming Mode=RunScript(script.htpc.steam)" \
        "Desktop Mode=RunScript(script.htpc.desktop)"; then
        htpc_log_error "Failed to seed Kodi favourites at ${favourites_path}."
        return 1
    fi

    chown "${target_user}:${target_user}" "${favourites_path}"
    htpc_log_info "Seeded Kodi favourites for ${target_user}."
}
