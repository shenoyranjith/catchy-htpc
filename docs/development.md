# Development

How to work on this project from a separate development machine (e.g. a
macOS laptop) against a real CachyOS test machine, without risking the
test machine's own data.

## Why a Separate Test Machine

This project installs system services, replaces system scripts, disables
the display manager, and reconfigures boot -- none of which can be
meaningfully tested by running code locally on a non-CachyOS machine.
A real (or virtual) CachyOS KDE installation is required for anything
beyond reading/reviewing code.

## Safety Net: Snapshots First

Before doing any other setup, get [Recovery](recovery-spec.md) working on
the test machine and take a snapshot. Every later step in this project
(installer, session services, MakeMKV) can be developed and tested
against that snapshot, with a guaranteed way back if something leaves the
machine unbootable:

1. Reboot into the broken state's GRUB menu -> select the last known-good
   snapshot entry.
2. Run `htpc-recovery restore <number>` to make it permanent again.

See [Recovery Specification](recovery-spec.md) for full detail.

## Syncing Code to the Test Machine

`dev/sync.sh` pushes the local working tree (including uncommitted
changes) to the test machine over SSH via `rsync`. The remote copy is
disposable -- it only exists for testing and is never a source of truth.
If the test machine gets rolled back to a snapshot, just re-run the
script.

Setup:

```
cp dev/.env.example dev/.env
```

Edit `dev/.env` with the test machine's SSH details:

```
HTPC_DEV_HOST=user@catchyos.local
HTPC_DEV_PATH=catchy-htpc-dev
```

`HTPC_DEV_PATH` is relative to the remote user's home directory. Don't
use `~` here -- `dev/.env` is sourced locally, so `~` would expand to the
local machine's home directory before `rsync` ever runs.

`dev/.env` is gitignored, so host details never get committed.

Usage:

```
dev/sync.sh
```

## Typical Workflow

1. Make changes locally.
2. `dev/sync.sh` to push them to the test machine.
3. SSH into the test machine and run/test the relevant command (e.g.
   `sudo ~/catchy-htpc-dev/bin/htpc-install`).
4. If something goes wrong badly enough, restore the pre-testing
   snapshot (see Safety Net above) and start again.
5. Once confirmed working, commit and push from the local machine as
   normal -- the test machine's copy is never the source of truth.

## A Note on Polkit and SSH

Keep an open SSH session as the target user in mind while testing
graphical, polkit-guarded actions in a live session (KDE Desktop, Steam):
it can cause `polkitd` to misattribute the active graphical session,
producing spurious repeated authentication prompts or outright denials.
See [Contributing](../CONTRIBUTING.md) for the full explanation and fix
(close the SSH session before testing).
