# Recovery Specification

Executable:

htpc-recovery

Implements the Btrfs snapshot and restore mechanism referenced by [Installer Specification](installer-spec.md)'s Snapshot Behaviour section. bin/htpc-install calls the same underlying functions directly; htpc-recovery exists so this mechanism can be exercised and tested independently.

## Layout Requirement

Snapshots must live in a dedicated top-level subvolume (@snapshots), a sibling of the root subvolume (@), not nested inside it.

This is required because restoring a snapshot replaces the @ subvolume entirely. If snapshots lived inside @, they would be destroyed at the exact moment they are needed.

htpc-recovery creates this layout automatically if it does not already exist, deriving its mount options from the existing root entry rather than hardcoding them, so compression, SSD, and discard settings stay correct for the underlying hardware.

CachyOS ships with snapper already configured by default, using the standard nested layout, frequently with real history already in it (an install-time baseline, pacman pre/post snapshots, etc.). If found, htpc-recovery moves it to become the top-level subvolume rather than starting over. Within a single btrfs filesystem this is a metadata-only rename, so no snapshot data is copied or touched; existing history is preserved exactly as-is.

## Why snapper's built-in rollback is not used

CachyOS mounts root using an explicit subvolume name (subvol=/@) in /etc/fstab. Snapper's built-in `rollback` command works by changing the Btrfs default subvolume, which has no effect when an explicit subvol= is set in fstab; the fstab entry always wins at boot. htpc-recovery performs the subvolume swap directly instead.

## Bootloader detection

Snapshot boot-menu integration depends on the active bootloader. `htpc_bootloader_detect` (lib/bootloader.sh) prefers the currently running loader from `bootctl` / `efibootmgr`, then falls back to config-file presence. Supported values:

- **Limine** -- CachyOS default on many current installs
- **GRUB** -- still common on older or explicitly chosen installs

CachyOS machines may have both package families installed after a migration; only the detected active bootloader's sync daemon and overlay hook are enabled. The other family's unit is disabled when present so the two do not fight.

## Commands

- htpc-recovery setup
- htpc-recovery create
- htpc-recovery status
- htpc-recovery restore <number>
- htpc-recovery list-backups
- htpc-recovery delete-backup <name>

## setup

Shared on every bootloader:

- Installs snapper and inotify-tools.
- Creates the @snapshots top-level subvolume and mounts it at /.snapshots, if not already present.
- Creates the snapper "root" configuration.

Then, based on detection:

### Limine

- Installs limine-snapper-sync and limine-mkinitcpio-hook.
- Ensures the writable-snapshot overlay hook in mkinitcpio: `sd-btrfs-overlayfs` when HOOKS use systemd, otherwise `btrfs-overlayfs`. Removes a leftover `grub-btrfs-overlayfs` hook if present, then regenerates via `limine-mkinitcpio` when available.
- Enables limine-snapper-sync.service and runs `limine-snapper-sync` so Limine's Snapshots menu stays up to date.
- Disables grub-btrfsd.service if it is present.

### GRUB

- Installs grub-btrfs.
- Adds the grub-btrfs-overlayfs hook to mkinitcpio (removing Limine overlay hooks if present) and regenerates the initramfs, so snapshots are bootable and writable when selected from GRUB.
- Enables grub-btrfsd, so GRUB's snapshot menu stays up to date automatically.
- Disables limine-snapper-sync.service if it is present.

## create

- Finds any previous installer snapshot, identified by a description prefix.
- Asks whether to replace it, if one exists.
- Creates a new snapshot and prints its number.

## restore <number>

Makes an existing snapshot the new permanent root, replacing the current one.

1. Warns if not currently booted into a snapshot. Recovering from within a snapshot boot, selected from the Limine or GRUB snapshot menu, is safer, since the real root subvolume is not live in that case. Proceeding from a normal boot is still supported, since a monitor or boot menu may not always be reachable; recovery may need to happen over SSH instead.
2. Renames the current root subvolume to `@.broken-<timestamp>` rather than deleting it immediately.
3. Creates a writable copy of the chosen snapshot as the new root subvolume.
4. Regenerates bootloader snapshot entries only when run from a normal boot (`grub-mkconfig` on GRUB; `limine-snapper-sync` / `limine-update` on Limine). From within a snapshot boot, `/boot` is not writable, and regeneration is not needed anyway: the normal boot entry boots by subvolume name (`@`), not a hardcoded path, so it picks up the restored content automatically.
5. Instructs the user to reboot and select the normal boot entry.

This never deletes the previous state automatically. It is kept as a `@.broken-<timestamp>` subvolume until removed explicitly, so a bad restore can itself still be inspected or reversed manually.

## list-backups / delete-backup

- list-backups shows any `@.broken-*` subvolumes left behind by restore.
- delete-backup removes one by name, to reclaim disk space once the restored system is confirmed stable.

## Requirements

- All operations that modify the subvolume layout back up /etc/fstab before editing it.
- Never deletes the previous root subvolume automatically; it is always preserved as a backup until the user removes it explicitly.
- Mount options for new subvolumes are derived from the existing root fstab entry, never hardcoded, so they match the actual hardware (compression, SSD/discard flags, etc.).
