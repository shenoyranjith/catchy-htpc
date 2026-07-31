#!/usr/bin/env bash
# Disables and masks whichever display manager is configured, recording its
# prior state so the uninstaller can restore it. No display manager is used
# by this project; see session-services-spec.md. Requires lib/log.sh and
# lib/install_record.sh.
#
# The specific unit is discovered at runtime via display-manager.service
# (the standard systemd alias) rather than hardcoded, since it varies by
# CachyOS install (this project was originally written assuming sddm.service,
# but plasmalogin.service is what CachyOS KDE actually ships and enables).

# Prints the actual unit backing display-manager.service, or empty if none
# is configured (e.g. a previous run already disabled it, removing the
# display-manager.service alias entirely). Checking LoadState first matters:
# systemctl show on a unit name that doesn't exist at all still succeeds and
# echoes that same name back as Id, rather than returning empty -- without
# this check, a rerun would try (and fail) to disable a literal unit named
# "display-manager.service".
htpc_display_manager_current() {
    local load_state

    load_state="$(systemctl show -p LoadState --value display-manager.service 2>/dev/null || true)"
    if [[ "${load_state}" != "loaded" ]]; then
        return 0
    fi

    systemctl show -p Id --value display-manager.service 2>/dev/null || true
}

# Disables and masks the current display manager unit, recording its unit
# name and prior enabled/disabled state to the installation record.
# Idempotent.
#
# Deliberately does not stop the unit now (only disables + masks it so it
# won't start on the *next* boot): the installer is typically run from
# within a live graphical session driven by this very display manager, and
# stopping it immediately would kill that session -- and the installer
# script itself -- mid-run. See installer-spec.md's "Prompt for reboot".
htpc_display_manager_disable_and_record() {
    local unit prior_state

    unit="$(htpc_display_manager_current)"

    if [[ -z "${unit}" ]]; then
        if [[ -n "$(htpc_install_record_get DISPLAY_MANAGER_UNIT)" ]]; then
            htpc_log_info "No active display manager; already disabled by a previous run."
        else
            htpc_log_info "No display manager configured; nothing to disable."
        fi
        return 0
    fi

    prior_state="$(systemctl is-enabled "${unit}" 2>/dev/null || echo "unknown")"

    systemctl disable "${unit}"
    systemctl mask "${unit}"

    htpc_install_record_set "DISPLAY_MANAGER_UNIT" "${unit}"
    htpc_install_record_set "DISPLAY_MANAGER_PRIOR_STATE" "${prior_state}"

    htpc_log_info "Disabled and masked ${unit} (was ${prior_state}) for the next boot."
}

# Reverses htpc_display_manager_disable_and_record: unmasks the recorded
# display manager unit and restores its prior enabled/disabled state.
# Only acts on the exact "enabled"/"disabled" values recorded by
# htpc_display_manager_disable_and_record; any other recorded value (e.g.
# "static", or "unknown" from a systemctl failure at install time) is left
# unmasked but not automatically enabled/disabled, since guessing intent
# from an ambiguous prior state is worse than asking the admin to check.
htpc_display_manager_restore() {
    local unit prior_state

    unit="$(htpc_install_record_get DISPLAY_MANAGER_UNIT)"
    if [[ -z "${unit}" ]]; then
        htpc_log_info "No display manager was recorded; nothing to restore."
        return 0
    fi

    prior_state="$(htpc_install_record_get DISPLAY_MANAGER_PRIOR_STATE)"
    systemctl unmask "${unit}" 2>/dev/null || true

    case "${prior_state}" in
        enabled)
            systemctl enable "${unit}"
            htpc_log_info "Unmasked and re-enabled ${unit}."
            ;;
        disabled)
            systemctl disable "${unit}" 2>/dev/null || true
            htpc_log_info "Unmasked ${unit} (was already disabled before install)."
            ;;
        *)
            htpc_log_warn "Unmasked ${unit}, but its prior state ('${prior_state}') was not one this can restore automatically; check 'systemctl status ${unit}' manually."
            ;;
    esac
}
