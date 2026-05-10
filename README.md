# 夜 yoru terminal

Dark. Quiet. Precise.

![preview](assets/preview.png)

## What's included

- Fastfetch config with colored dragon ASCII
- Windows Terminal color scheme (Yoru palette)
- Starship prompt — minimal, single-line
- PowerShell profile
- One-command installer

## Requirements

- Windows 10 or 11
- PowerShell 7+
- winget (included on Windows 11; Windows 10: [App Installer](https://apps.microsoft.com/detail/9nblggh4nns1) from the Microsoft Store)
- [0xProto Nerd Font Mono](https://github.com/ryanoasis/nerd-fonts/releases) (or substitute in `terminal/settings.json`)

## Install

```powershell
irm https://raw.githubusercontent.com/tprojectzdev-sys/yoru-terminal/main/install.ps1 | iex
```

Replace `OWNER` with your GitHub username before sharing.

## Manual setup

- [fastfetch/config.jsonc](fastfetch/config.jsonc) — copy to `%USERPROFILE%\.config\fastfetch\config.jsonc` (and place [fastfetch/dragon.txt](fastfetch/dragon.txt) beside it)
- [starship/starship.toml](starship/starship.toml) — copy to `%USERPROFILE%\.config\starship\starship.toml`
- [terminal/settings.json](terminal/settings.json) — merge into Windows Terminal’s `settings.json` (see installer for the usual path under `LocalState`)
- [powershell/profile.ps1](powershell/profile.ps1) — copy to your PowerShell `$PROFILE` path

## Themes

More themes coming. Contributions welcome.

MIT
