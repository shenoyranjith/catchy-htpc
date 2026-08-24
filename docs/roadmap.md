# Roadmap

## Phase 1

- [x] [Recovery](recovery-spec.md)
- [x] [Installer](installer-spec.md)
- [x] [Session Manager](session-manager-spec.md)
- [x] Kodi boot
- [x] Steam transition
- [x] Desktop transition
- [x] Desktop shortcuts (KDE Desktop -> Kodi/Steam, see [Session Services Specification](session-services-spec.md))
- [x] Logging (journald throughout, via lib/log.sh and htpc-switch's own logger calls)
- [x] [Uninstaller](uninstaller-spec.md)

## Phase 2

- [x] [MakeMKV / Blu-ray & UHD Blu-ray playback](makemkv-spec.md) (optional add-on)
- [x] NVIDIA: Steam Gaming Mode without gamescope (folded into the KDE Desktop session; gamescope has a confirmed upstream Steam-overlay display-corruption regression on current NVIDIA driver branches -- see "Steam Gaming Mode" in [Session Services Specification](session-services-spec.md))
