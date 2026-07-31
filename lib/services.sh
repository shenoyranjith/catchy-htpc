#!/usr/bin/env bash
# Installs and manages the htpc-*.service systemd units defined in
# session-services-spec.md. Requires lib/log.sh and lib/backup.sh.

HTPC_SYSTEMD_DIR="/etc/systemd/system"
HTPC_SERVICE_UNITS=(htpc-kodi.service htpc-steam.service htpc-desktop.service)
HTPC_BIN_DIR="/usr/local/bin"
HTPC_POLKIT_RULES_DIR="/etc/polkit-1/rules.d"
HTPC_POLKIT_RULE_NAME="49-htpc-switch.rules"
HTPC_STEAMOS_SESSION_SELECT_PATH="/usr/bin/steamos-session-select"
HTPC_ENVIRONMENT_D_PATH="/etc/environment.d/90-cachyos-htpc.conf"

htpc_unit_template_dir() {
    cd "$(dirname "${BASH_SOURCE[0]}")/../systemd" && pwd
}

htpc_polkit_rule_template_dir() {
    cd "$(dirname "${BASH_SOURCE[0]}")/../polkit" && pwd
}

htpc_switch_source_path() {
    printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/htpc-switch"
}

htpc_steamos_session_select_source_path() {
    printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" && pwd)/htpc-steamos-session-select"
}

# Installs a unit file from systemd/<name> into /etc/systemd/system/<name>,
# substituting __HTPC_USER__ for the given target user. Idempotent: only
# writes and reloads systemd if the rendered file actually differs from
# what is already installed.
htpc_service_install() {
    local name="$1" target_user="$2"
    local template_dir template dest tmp

    template_dir="$(htpc_unit_template_dir)"
    template="${template_dir}/${name}"
    dest="${HTPC_SYSTEMD_DIR}/${name}"

    if [[ ! -f "${template}" ]]; then
        htpc_log_error "No template found for ${name} at ${template}."
        return 1
    fi

    tmp="$(mktemp)"
    sed "s/__HTPC_USER__/${target_user}/g" "${template}" > "${tmp}"

    if [[ -f "${dest}" ]] && cmp -s "${tmp}" "${dest}"; then
        rm -f "${tmp}"
        htpc_log_info "${name} already installed and up to date."
        return 0
    fi

    install -m 0644 "${tmp}" "${dest}"
    rm -f "${tmp}"
    systemctl daemon-reload

    htpc_log_info "Installed ${name} for user ${target_user}."
}

# Reverses htpc_service_install: stops (if running), disables, and removes
# a previously installed htpc-*.service unit file. Idempotent: a no-op if
# the unit was never installed.
htpc_service_uninstall() {
    local name="$1"
    local dest="${HTPC_SYSTEMD_DIR}/${name}"

    if [[ ! -f "${dest}" ]]; then
        htpc_log_info "${name} not installed; nothing to remove."
        return 0
    fi

    systemctl disable --now "${name}" 2>/dev/null || true
    rm -f "${dest}"
    systemctl daemon-reload
    htpc_log_info "Removed ${name}."
}

# Masks a systemd --user unit for a target user by symlinking it to
# /dev/null under that user's own systemd user config directory. This
# works without needing an active session for the user (unlike
# `systemctl --user mask`, which requires a running user instance),
# making it safe to run from a root install script. Idempotent.
htpc_user_unit_mask() {
    local unit="$1" target_user="$2"
    local home user_systemd_dir mask_path

    home="$(getent passwd "${target_user}" | cut -d: -f6)"
    if [[ -z "${home}" ]]; then
        htpc_log_error "Could not determine home directory for user ${target_user}."
        return 1
    fi

    user_systemd_dir="${home}/.config/systemd/user"
    mask_path="${user_systemd_dir}/${unit}"

    if [[ -L "${mask_path}" ]] && [[ "$(readlink "${mask_path}")" == "/dev/null" ]]; then
        htpc_log_info "${unit} already masked for ${target_user}."
        return 0
    fi

    install -d -o "${target_user}" -g "${target_user}" -m 0755 "${home}/.config" "${home}/.config/systemd" "${user_systemd_dir}"
    ln -sf /dev/null "${mask_path}"

    htpc_log_info "Masked ${unit} for user ${target_user}."
}

# Reverses htpc_user_unit_mask: removes the /dev/null mask symlink for the
# given systemd --user unit, if present. Only removes it if it is still
# exactly the mask this project created, so it never clobbers something
# else. Idempotent.
htpc_user_unit_unmask() {
    local unit="$1" target_user="$2"
    local home mask_path

    home="$(getent passwd "${target_user}" | cut -d: -f6)"
    if [[ -z "${home}" ]]; then
        htpc_log_error "Could not determine home directory for user ${target_user}."
        return 1
    fi

    mask_path="${home}/.config/systemd/user/${unit}"

    if [[ -L "${mask_path}" ]] && [[ "$(readlink "${mask_path}")" == "/dev/null" ]]; then
        rm -f "${mask_path}"
        htpc_log_info "Unmasked ${unit} for ${target_user}."
    else
        htpc_log_info "${unit} was not masked for ${target_user}; nothing to unmask."
    fi
}

# Installs bin/htpc-switch to /usr/local/bin so it's on PATH for Kodi
# add-ons, the replaced steamos-session-select wrapper, and manual use.
# Idempotent.
htpc_switch_install() {
    local script dest

    script="$(htpc_switch_source_path)"
    dest="${HTPC_BIN_DIR}/htpc-switch"

    if [[ ! -f "${script}" ]]; then
        htpc_log_error "htpc-switch script not found at ${script}."
        return 1
    fi

    if [[ -f "${dest}" ]] && cmp -s "${script}" "${dest}"; then
        htpc_log_info "htpc-switch already installed and up to date."
        return 0
    fi

    install -m 0755 "${script}" "${dest}"
    htpc_log_info "Installed htpc-switch to ${dest}."
}

# Reverses htpc_switch_install.
htpc_switch_uninstall() {
    local dest="${HTPC_BIN_DIR}/htpc-switch"

    if [[ -f "${dest}" ]]; then
        rm -f "${dest}"
        htpc_log_info "Removed ${dest}."
    fi
}

# Installs a polkit rule granting the target user passwordless start/stop/
# restart of only the three htpc-*.service units, substituting
# __HTPC_USER__. Idempotent.
htpc_polkit_rule_install() {
    local target_user="$1"
    local template_dir template dest tmp

    template_dir="$(htpc_polkit_rule_template_dir)"
    template="${template_dir}/htpc-switch.rules"
    dest="${HTPC_POLKIT_RULES_DIR}/${HTPC_POLKIT_RULE_NAME}"

    if [[ ! -f "${template}" ]]; then
        htpc_log_error "No polkit rule template found at ${template}."
        return 1
    fi

    tmp="$(mktemp)"
    sed "s/__HTPC_USER__/${target_user}/g" "${template}" > "${tmp}"

    if [[ -f "${dest}" ]] && cmp -s "${tmp}" "${dest}"; then
        rm -f "${tmp}"
        htpc_log_info "polkit rule already installed and up to date."
        return 0
    fi

    install -m 0644 "${tmp}" "${dest}"
    rm -f "${tmp}"
    htpc_log_info "Installed polkit rule for user ${target_user} at ${dest}."
}

# Reverses htpc_polkit_rule_install.
htpc_polkit_rule_uninstall() {
    local dest="${HTPC_POLKIT_RULES_DIR}/${HTPC_POLKIT_RULE_NAME}"

    if [[ -f "${dest}" ]]; then
        rm -f "${dest}"
        htpc_log_info "Removed polkit rule ${dest}."
    fi
}

# Replaces gamescope-session-cachyos's steamos-session-select with a thin
# wrapper that redirects Steam's own session-switching UI actions to
# htpc-switch instead of its SDDM-oriented autologin logic. The original is
# preserved via htpc_backup_file so the uninstaller can restore it.
# Idempotent. Note: since this file is owned by the gamescope-session-cachyos
# package, a future package update may silently overwrite it back to
# upstream; re-run this after updating that package.
htpc_steamos_session_select_install() {
    local script dest

    script="$(htpc_steamos_session_select_source_path)"
    dest="${HTPC_STEAMOS_SESSION_SELECT_PATH}"

    if [[ ! -f "${script}" ]]; then
        htpc_log_error "steamos-session-select wrapper not found at ${script}."
        return 1
    fi

    if [[ ! -f "${dest}" ]]; then
        htpc_log_error "No existing steamos-session-select found at ${dest}; is gamescope-session-cachyos installed?"
        return 1
    fi

    if cmp -s "${script}" "${dest}"; then
        htpc_log_info "steamos-session-select already replaced with the htpc wrapper."
        return 0
    fi

    htpc_backup_file "${dest}"
    install -m 0755 "${script}" "${dest}"
    htpc_log_info "Replaced ${dest} with the htpc-switch wrapper."
}

# Reverses htpc_steamos_session_select_install: restores the original
# script from the .htpc-backup copy made before replacing it (see
# htpc_backup_file), if one is present. Idempotent.
htpc_steamos_session_select_restore() {
    local dest="${HTPC_STEAMOS_SESSION_SELECT_PATH}"
    local backup="${dest}.htpc-backup"

    if [[ ! -f "${backup}" ]]; then
        htpc_log_info "No backup found for ${dest}; leaving it as-is (may not have been replaced, or was already restored)."
        return 0
    fi

    mv -f "${backup}" "${dest}"
    htpc_log_info "Restored original ${dest} from backup."
}

# Installs a systemd environment.d drop-in disabling the AT-SPI
# accessibility bridge (NO_AT_BRIDGE=1) for the target user's systemd --user
# manager. See session-services-spec.md "Accessibility Bridge" for why this
# exists: Environment= on the htpc-*.service units only affects the
# directly-exec'd process (kodi-standalone / start-gamescope-session /
# startplasma-wayland) itself, but D-Bus-activated helpers -- notably
# at-spi2-registryd, which both Steam's Qt UI and Plasma trigger -- get
# their environment from the user manager's own default environment
# instead, which only environment.d controls. Confirmed live: setting
# NO_AT_BRIDGE on the units alone did not stop new at-spi2-registryd
# instances from leaking (one per session start, never cleaned up again
# until reboot) on every switch into Steam or Desktop.
htpc_environment_no_at_bridge_install() {
    local target_user="$1"
    local content="NO_AT_BRIDGE=1"

    if [[ -f "${HTPC_ENVIRONMENT_D_PATH}" ]] && grep -qx "${content}" "${HTPC_ENVIRONMENT_D_PATH}"; then
        htpc_log_info "environment.d NO_AT_BRIDGE already installed."
    else
        install -d -m 0755 "$(dirname "${HTPC_ENVIRONMENT_D_PATH}")"
        printf '%s\n' "${content}" > "${HTPC_ENVIRONMENT_D_PATH}"
        htpc_log_info "Installed ${HTPC_ENVIRONMENT_D_PATH}."
    fi

    # environment.d is normally only read once, at the user manager's own
    # startup. Our sessions all share one long-lived manager across
    # switches rather than a fresh one per login (see
    # session-services-spec.md), so without this, the drop-in would not
    # take effect until the user's very next full login (e.g. after a
    # reboot). daemon-reload re-runs systemd's environment generators
    # against the already-running manager, so it takes effect immediately
    # instead.
    #
    # runuser alone does not set XDG_RUNTIME_DIR, so `systemctl --user`
    # would otherwise silently look for (and fail to find) a manager under
    # root's own runtime dir instead of the target user's.
    local uid
    uid="$(id -u "${target_user}" 2>/dev/null)" || uid=""
    if [[ -n "${uid}" ]] && runuser -u "${target_user}" -- env "XDG_RUNTIME_DIR=/run/user/${uid}" systemctl --user daemon-reload 2>/dev/null; then
        htpc_log_info "Reloaded ${target_user}'s systemd --user environment."
    else
        htpc_log_warn "Could not reload ${target_user}'s systemd --user manager (no active session?); it will pick up NO_AT_BRIDGE on next login instead."
    fi
}

# Reverses htpc_environment_no_at_bridge_install.
htpc_environment_no_at_bridge_uninstall() {
    local target_user="$1"

    if [[ ! -f "${HTPC_ENVIRONMENT_D_PATH}" ]]; then
        htpc_log_info "${HTPC_ENVIRONMENT_D_PATH} not present; nothing to remove."
        return 0
    fi

    rm -f "${HTPC_ENVIRONMENT_D_PATH}"
    htpc_log_info "Removed ${HTPC_ENVIRONMENT_D_PATH}."

    local uid
    uid="$(id -u "${target_user}" 2>/dev/null)" || uid=""
    if [[ -n "${uid}" ]] && runuser -u "${target_user}" -- env "XDG_RUNTIME_DIR=/run/user/${uid}" systemctl --user daemon-reload 2>/dev/null; then
        htpc_log_info "Reloaded ${target_user}'s systemd --user environment."
    else
        htpc_log_warn "Could not reload ${target_user}'s systemd --user manager (no active session?); NO_AT_BRIDGE will remain set until next login."
    fi
}

# Prints the currently active htpc-*.service unit, if any. Empty output
# means no session is currently active.
htpc_service_active() {
    local unit
    for unit in "${HTPC_SERVICE_UNITS[@]}"; do
        if systemctl is-active --quiet "${unit}"; then
            printf '%s\n' "${unit}"
            return 0
        fi
    done
}
