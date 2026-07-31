# MakeMKV / Blu-ray & UHD Blu-ray Playback Specification

Optional add-on. Enables Kodi's built-in disc player to decrypt and play
Blu-ray and UHD Blu-ray discs, by installing MakeMKV alongside the
open-source disc-handling libraries Kodi already links against, and
ensuring the kernel module MakeMKV needs to see the optical drive is
loaded. Confirmed working end-to-end on this project's own test machine:
once installed, Kodi's normal disc playback (Videos -> Play disc, or
auto-play on insert if that Kodi setting is enabled) picks up MakeMKV
automatically, decrypting as it plays. No Kodi-side configuration,
add-on, or manual library symlinking is required beyond the install
steps below.

Executable:

bin/htpc-makemkv-setup

## Scope

Not part of the core appliance: this is a media-playback feature, not
session-switching infrastructure, so it lives in its own standalone
script rather than as a mandatory [Installer Specification](installer-spec.md) step. It is offered
as an opt-in prompt at the end of the installer, and can also be run on its own at any time:

```
sudo bin/htpc-makemkv-setup
```

Safe to rerun.

## What It Installs

1. **Build packages**: gcc, make, pkgconf, qt5-base, ffmpeg, openssl,
   zlib, expat -- everything needed to compile MakeMKV from source.
2. **MakeMKV itself**, built from source in two parts, matching how
   Arch's own official `makemkv` AUR package builds it:
   - `makemkv-oss` (open source): `./configure --prefix=/usr && make && make install`.
   - `makemkv-bin` (proprietary decryption engine): installed after
     interactive EULA acceptance, via a pre-seeded `tmp/eula_accepted`
     flag file (the same non-interactive mechanism the AUR PKGBUILD
     uses) followed by `make install`.
3. **Runtime packages**: libbluray, libaacs -- the open-source libraries
   Kodi's disc player already links against for disc/AACS handling.
   `libbdplus` is intentionally omitted: it is AUR-only, and MakeMKV's
   own decryption engine already covers BD+ (and AACS), which is the
   whole reason this project builds MakeMKV.
4. **The `sg` kernel module**: MakeMKV talks to the optical drive over
   `/dev/sg*` (SCSI generic), which isn't loaded by default. Loaded
   immediately via `modprobe sg` and persisted across reboots via
   `/etc/modules-load.d/sg.conf`.

## Source Provenance

The official makemkv.com download domain is down at the time of writing.
Rather than depend on a third-party mirror's continued uptime, both
source tarballs are vendored directly in this repo, at:

```
vendor/makemkv/makemkv-oss-1.18.4.tar.gz
vendor/makemkv/makemkv-bin-1.18.4.tar.gz
vendor/makemkv/eula_en_linux.txt
```

They were obtained from a GitHub mirror (`abanta1/makemkv-gui` releases,
v1.18.4) and their sha256 checksums verified to be byte-identical to the
ones in Arch's official `makemkv` AUR package (same version, actively
maintained) before vendoring. `bin/htpc-makemkv-setup` re-verifies these
checksums (pinned in the script) every run before extracting, so any
accidental modification of the vendored files is caught.

Redistributing both files unmodified, as done here, is explicitly
permitted by their licenses:

- `makemkv-oss` is GPL/LGPL-licensed.
- `makemkv-bin`'s own EULA (vendor/makemkv/eula_en_linux.txt) states:
  "You are allowed to redistribute the Software in its original
  unmodified form."

If a newer version is needed once the official domain returns, replace
the vendored files with the new version's tarballs, update
`HTPC_MAKEMKV_VERSION` and the two sha256 constants in
`bin/htpc-makemkv-setup`, and re-verify against the current AUR PKGBUILD
(https://aur.archlinux.org/packages/makemkv) first.

## Idempotency

If `makemkvcon` and `makemkv` are already on PATH, the build/install step
is skipped entirely (remove both binaries to force a rebuild). The
runtime packages and `sg` module setup always run and are safe to repeat.

## Registration

MakeMKV must be registered for disc decryption (and therefore Kodi
playback) to work. `bin/htpc-makemkv-setup` handles this as part of its
normal flow:

1. Prompt for a registration key (paid key, or the free beta key from
   the MakeMKV forum), unless `HTPC_MAKEMKV_KEY` is already set in the
   environment.
2. Refuse to register while an optical disc is loaded. Live testing
   found registration fails with a disc in the drive; the script detects
   media via `/dev/sr*` size, offers to eject, and waits until the tray
   is empty.
3. Write `app_Key = "<key>"` into the target user's
   `~/.MakeMKV/settings.conf` (created if missing, owned by that user,
   mode 0600). This is preferred over `makemkvcon reg`, which is
   unreliable on Linux and often reports "Key not found or invalid"
   even for a valid key.

Whitespace is stripped from the pasted key (paste often introduces a
trailing newline/space that makes an otherwise-valid key look invalid).
Re-running with a key already present asks before replacing it.

## Out of Scope

- **Rip-to-file workflows.** Only direct disc-in-drive playback through
  Kodi is covered; ripping to a library file is a separate, unrelated
  workflow (`makemkvcon mkv ...`) left entirely to the user if they want
  it.
- **Disc autoplay UX.** Whether inserting a disc starts playback
  automatically is controlled by Kodi's own settings, not this project.
- **Uninstallation.** Not wired into [Uninstaller Specification](uninstaller-spec.md). To revert
  manually: remove `/usr/bin/makemkv*` and the libraries `make install`
  placed under `/usr/lib`/`/usr/share` (no `make uninstall` target
  exists), remove `/etc/modules-load.d/sg.conf`, and remove the
  libbluray/libaacs packages if desired.
