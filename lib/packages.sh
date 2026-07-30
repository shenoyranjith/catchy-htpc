#!/usr/bin/env bash
# Helpers for installing packages via pacman. Requires lib/log.sh.

htpc_package_installed() {
    local package="$1"
    pacman -Qi -- "${package}" >/dev/null 2>&1
}

htpc_packages_install() {
    local packages=("$@")
    local missing=()
    local package

    for package in "${packages[@]}"; do
        if ! htpc_package_installed "${package}"; then
            missing+=("${package}")
        fi
    done

    if [[ "${#missing[@]}" -eq 0 ]]; then
        htpc_log_info "All required packages already installed: ${packages[*]}"
        return 0
    fi

    htpc_log_info "Installing packages: ${missing[*]}"
    pacman -S --needed --noconfirm -- "${missing[@]}"
}
