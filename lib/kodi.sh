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

# Seeds favourites.xml with session-switch add-ons and disc built-ins,
# preserving any existing favourites. Idempotent: updates same-named
# entries in place and never duplicates. Play Disc / Eject Tray use
# Kodi's own PlayDVD and EjectTray() built-ins so they remain available
# under skins that hide the default disc controls.
#
# Both are called with a harmless dummy parameter ("(1)") rather than bare
# (PlayDVD) or empty parens (EjectTray()). This isn't cosmetic: Kodi's
# favourites loader (CFavouritesURL::Parse, favourites/FavouritesURL.cpp)
# rejects any non-whitelisted built-in (i.e. anything other than
# ActivateWindow/PlayMedia/RunScript/RunAddon/etc.) that has zero
# parameters, resolving it to an empty target path instead of erroring.
# Confirmed live: this silently made "Play Disc" show up but do nothing
# (empty path), and made "Eject Tray" not show up at all, since Kodi
# de-duplicates favourites by resolved path and it collided with Play
# Disc's empty one. Both built-ins ignore unrecognized params (EjectTray
# takes none; PlayDVD only special-cases "restart"), so the dummy value is
# safe and keeps the params list non-empty.
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
        "Desktop Mode=RunScript(script.htpc.desktop)" \
        "Play Disc=PlayDVD(1)" \
        "Eject Tray=EjectTray(1)"; then
        htpc_log_error "Failed to seed Kodi favourites at ${favourites_path}."
        return 1
    fi

    chown "${target_user}:${target_user}" "${favourites_path}"
    htpc_log_info "Seeded Kodi favourites for ${target_user}."
}

# Reverses htpc_kodi_addons_install.
htpc_kodi_addons_remove() {
    local target_user="$1"
    local kodi_home addons_dir name

    kodi_home="$(htpc_kodi_home "${target_user}")" || return 1
    addons_dir="${kodi_home}/addons"

    for name in "${HTPC_KODI_ADDONS[@]}"; do
        if [[ -d "${addons_dir}/${name}" ]]; then
            rm -rf "${addons_dir:?}/${name}"
            htpc_log_info "Removed Kodi add-on ${name} for ${target_user}."
        fi
    done
}

# Reverses htpc_kodi_favourites_seed: removes only the favourite entries
# this project seeds, by name, preserving anything else the target user
# has in favourites.xml. A no-op if favourites.xml doesn't exist.
htpc_kodi_favourites_remove() {
    local target_user="$1"
    local kodi_home favourites_path script

    kodi_home="$(htpc_kodi_home "${target_user}")" || return 1
    favourites_path="${kodi_home}/userdata/favourites.xml"
    script="$(htpc_favourites_script_path)"

    if [[ ! -f "${favourites_path}" ]]; then
        htpc_log_info "No favourites.xml found for ${target_user}; nothing to remove."
        return 0
    fi

    if ! python3 "${script}" --remove "${favourites_path}" \
        "Steam Gaming Mode" \
        "Desktop Mode" \
        "Play Disc" \
        "Eject Tray"; then
        htpc_log_error "Failed to remove seeded favourites from ${favourites_path}."
        return 1
    fi

    chown "${target_user}:${target_user}" "${favourites_path}"
    htpc_log_info "Removed seeded Kodi favourites for ${target_user}."
}
