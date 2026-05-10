# Changelog

All notable changes to this project are documented in this file.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-05-10

### Added

- **Initial public release** — Sumi-e Crimson pack: Windows Terminal JSON, Fastfetch + dragon, Starship, PowerShell profile block.
- **Installer improvements** — clearer sections, final summary, dependency checks, dim paths, subtle download spinner.
- **Backup support** — timestamped `*.yoru-backup-*.bak` beside `settings.json` and `$PROFILE`; `-Restore` for latest backups.
- **Diagnostics** — `-Doctor` / `doctor.ps1` with `[ok]` / `[warn]` / `[missing]` / `[fix]`.
- **Uninstall** — `-Uninstall` / `uninstall.ps1`; optional `-KeepWindowsTerminalSettingsOnUninstall`; cleans **both** Documents profile paths; pre-uninstall copies use `yoru-session` (not picked by `-Restore`).
- **Hard reset** — `-HardReset` / `hardreset.ps1`: strip Yoru blocks on both standard profile paths; delete Windows Terminal `settings.json` for default regeneration; backups use `yoru-hard-reset`.
- **Restore** — uses only `yoru-backup` files; restores **both** standard profile paths when backups exist; `yoru-session` / `yoru-hard-reset` excluded from “latest” selection.
- **Install modes** — `-Full` (default), `-Minimal` (configs only).
- **Local clone installs** — copy from disk when `install.ps1` sits next to `terminal\settings.json`.
- **README** — quick install, paths, safety, troubleshooting, FAQ, known issues, screenshots layout.
- **Issue templates** — installation, visual, bug, feature.
- **CONTRIBUTING.md** — how to report, test, and PowerShell rules.
- **Markers** in bundled configs for safer uninstall (Fastfetch comment, Starship comment, profile `BEGIN` / `END`).
