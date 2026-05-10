# Yoru Terminal — repo structure (internal)

## Files

| Path | Role |
|------|------|
| `install.ps1` | Winget dependency checks (Full), copies configs, font notice, timestamped backups, modes: `-Full`, `-Minimal`, `-Doctor`, `-Restore`, `-Uninstall`. Local clone uses files next to script instead of raw GitHub. |
| `doctor.ps1` / `restore.ps1` / `uninstall.ps1` | Thin wrappers forwarding to `install.ps1`. |
| `fastfetch/dragon.txt` | Multi-color ASCII logo; Fastfetch `$1`–`$4` placeholders (not `${1}` — see wiki). |
| `fastfetch/config.jsonc` | Fastfetch layout, Yoru logo colors, modules, separator, footer line. |
| `starship/starship.toml` | Single-line Starship prompt; directory, git, `›` character. |
| `terminal/settings.json` | Windows Terminal global + profile defaults, **Yoru** color scheme. |
| `powershell/profile.ps1` | Starship init, `STARSHIP_CONFIG`, conditional fastfetch, aliases, `Clear-Host`. |
| `README.md` | Public overview and install instructions. |
| `repo-structure.md` | This reference. |

## Copy targets (installer / docs)

| Repo file | Target on user machine |
|-----------|-------------------------|
| `fastfetch/dragon.txt` | `%USERPROFILE%\.config\fastfetch\dragon.txt` |
| `fastfetch/config.jsonc` | `%USERPROFILE%\.config\fastfetch\config.jsonc` |
| `starship/starship.toml` | `%USERPROFILE%\.config\starship\starship.toml` |
| `terminal/settings.json` | `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` (or first matching `Microsoft.WindowsTerminal_*` package `LocalState\settings.json` if that folder is absent) |
| `powershell/profile.ps1` | `$PROFILE` for the host that loads it (typically **CurrentUserCurrentHost**; e.g. `Documents\PowerShell\Microsoft.PowerShell_profile.ps1` for PS 7) |

Backups from `install.ps1`:

| Pattern | Use |
|---------|-----|
| `*.yoru-backup-*.bak` | Install-time restore points; **`-Restore`** and **`-Uninstall`** (WT) use these only. |
| `*.yoru-session-*.bak` | Pre-restore / pre-uninstall snapshot; not picked as “latest” for restore. |
| `*.yoru-hard-reset-*.bak` | **`-HardReset`** only. |

## Variables and placeholders to update

| Location | What to change |
|----------|----------------|
| `README.md`, `install.ps1` (comment + `$RepoRawBase`), remote install one-liner | `OWNER` → GitHub user or org (`github.com/OWNER/yoru-terminal`). |
| `terminal/settings.json` | `{powershell-guid}` → real profile GUID; match `defaultProfile` and the profile entry in `profiles.list`. |
| `terminal/settings.json` | `profiles.defaults.font.face` if not using 0xProto Nerd Font Mono. |
| `fastfetch/config.jsonc` | `logo.source` uses `%USERPROFILE%/.config/fastfetch/dragon.txt` for Windows env expansion (`~` only on Fastfetch v2.41+). |
| `powershell/profile.ps1` | `$env:STARSHIP_CONFIG` default: `$HOME\.config\starship\starship.toml` — change if you relocate the file. |
| `powershell/profile.ps1` | Fastfetch `--config` path: `$HOME\.config\fastfetch\config.jsonc` — change if relocated. |
| `powershell/profile.ps1` | Comment footer `github.com/OWNER/yoru-terminal` → real repo URL. |
| Runtime | `%USERPROFILE%` / `$HOME` — used by configs and profile; no edit unless you intentionally hardcode paths. |

## Assets (referenced, not yet in tree)

| Path | Notes |
|------|------|
| `assets/preview.png` | Referenced by `README.md`; add when a screenshot exists. |
