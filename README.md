<div align="center">

<img src="assets/banner.png" alt="Yoru Terminal" width="100%">

# Yoru Terminal

Yoru Terminal is a polished Windows Terminal setup built for people who want their command line to feel intentional. It combines Windows Terminal styling, PowerShell startup customization, Fastfetch, Starship, and custom assets into one installable package.

[![Platform](https://img.shields.io/badge/Platform-Windows_11-blue?style=for-the-badge&logo=windows)](https://github.com/microsoft/terminal)
[![Terminal](https://img.shields.io/badge/Windows_Terminal-Supported-green?style=for-the-badge&logo=windowsterminal)](https://github.com/microsoft/terminal)
[![Shell](https://img.shields.io/badge/PowerShell-7+-black?style=for-the-badge&logo=powershell)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/License-MIT-gray?style=for-the-badge)](LICENSE)

</div>

**Sumi-e Crimson** is the first pack: dark acrylic, crimson accents, dragon Fastfetch art, and a tight Starship prompt. More visual packs may show up here later—the layout isn’t locked to this one look.

---

## Preview

<div align="center">

<img src="assets/screenshots/after.png" alt="Yoru Terminal — Sumi-e Crimson" width="85%">

*Drop a PNG at `assets/screenshots/after.png` (see [assets/screenshots/README.md](assets/screenshots/README.md)).*

</div>

---

## Quick install

```powershell
irm https://raw.githubusercontent.com/tprojectzdev-sys/yoru-terminal/main/install.ps1 | iex
```

Then **close every terminal window** and open **Windows Terminal** again.

Prerequisites: **Windows Terminal** installed (Microsoft Store), and **winget** available for the default full install (App Installer).

---

## What Yoru does

| Piece | What you get |
| --- | --- |
| **Windows Terminal** | Dark theme, acrylic, **Yoru** color scheme, **0xProto Nerd Font Mono** in the template |
| **PowerShell** | Marked profile block: Starship, optional Fastfetch on startup, small helpers |
| **Fastfetch** | Layout + **dragon** ASCII (`dragon.txt`) |
| **Starship** | Minimal prompt with crimson accent |
| **Installer** | One command; backs up before overwriting; can install missing tools via winget |

---

## What gets changed

On your machine, the installer touches:

- **Windows Terminal** — `settings.json` under your Windows Terminal package (replaced after backup).
- **PowerShell** — a **block** appended to the **current** host `$PROFILE` (existing lines above the block stay).
- **Fastfetch** — `%USERPROFILE%\.config\fastfetch\` (`config.jsonc`, `dragon.txt`).
- **Starship** — `%USERPROFILE%\.config\starship\starship.toml`.

**Rollback modes** also clean **both** standard profile paths under your **Documents** folder (`PowerShell\` and `WindowsPowerShell\`). See `install.ps1` or [repo-structure.md](repo-structure.md) for exact paths.

---

## Included files (repo)

| Path | Role |
| --- | --- |
| `terminal/settings.json` | Windows Terminal defaults + **Yoru** scheme |
| `powershell/profile.ps1` | Block appended to your profile |
| `fastfetch/config.jsonc` | Fastfetch layout |
| `fastfetch/dragon.txt` | Dragon art for Fastfetch |
| `starship/starship.toml` | Starship config |

---

## Safety

- **Backups** are written next to files being replaced: `*.yoru-backup-*.bak` (restore points), plus `*.yoru-session-*.bak` / `*.yoru-hard-reset-*.bak` for other operations (see [repo-structure.md](repo-structure.md)).
- **Profile:** Yoru **appends** a marked block; it does not wipe your whole profile.
- **Tools:** Uninstall / hard reset **do not** remove PowerShell, Windows Terminal, Fastfetch, Starship, or fonts.
- **Audit:** Everything the script applies lives in this repo; read `install.ps1` before you run a remote one-liner.

---

## Installation

### Default (remote)

1. Run the [Quick install](#quick-install) line in PowerShell.
2. Restart Windows Terminal.
3. If something looks off, clone the repo and run diagnostics (next section).

### Diagnostics

The one-liner always runs **full** install; it cannot pass flags. To run **Doctor**, use a clone or a saved script:

```powershell
git clone https://github.com/tprojectzdev-sys/yoru-terminal.git
cd yoru-terminal
.\install.ps1 -Doctor
```

Or: `.\doctor.ps1`

### Other modes (local script only)

| Mode | Command |
| --- | --- |
| Full (default locally) | `.\install.ps1` or `.\install.ps1 -Full` |
| Configs only (no winget) | `.\install.ps1 -Minimal` |
| Restore install-time backups | `.\install.ps1 -Restore` |
| Remove Yoru files + restore Terminal from backup | `.\install.ps1 -Uninstall` |
| Strip Yoru profile blocks + delete `settings.json` (defaults return) | `.\install.ps1 -HardReset` |

**Hard reset from download (no clone):**

```powershell
$tmp = "$env:TEMP\yoru-install.ps1"
Invoke-WebRequest "https://raw.githubusercontent.com/tprojectzdev-sys/yoru-terminal/main/install.ps1" -OutFile $tmp
pwsh -NoProfile -ExecutionPolicy Bypass -File $tmp -HardReset
```

Wrappers: `doctor.ps1`, `restore.ps1`, `uninstall.ps1`, `hardreset.ps1`.

### Manual install

If you prefer not to run the script:

1. Install **Windows Terminal**, **PowerShell 7**, **Fastfetch**, and **Starship** yourself (winget is fine).
2. Copy `terminal/settings.json` into your Terminal **Open JSON file** workflow (merge carefully), or replace after backing up.
3. Copy `fastfetch/*` to `%USERPROFILE%\.config\fastfetch\`.
4. Copy `starship/starship.toml` to `%USERPROFILE%\.config\starship\`.
5. Append the repo’s `powershell/profile.ps1` to your `$PROFILE` inside the installer’s markers (`# YORU_TERMINAL_PROFILE_BLOCK` through `# YORU_TERMINAL_PROFILE_BLOCK_END`), or read `install.ps1` / run it once to avoid mistakes.

---

## Troubleshooting

| Issue | Try |
| --- | --- |
| `winget` not found | Install **App Installer** from the Store. |
| No Terminal `settings.json` | Open Windows Terminal once, then re-run the installer. |
| `{powershell-guid}` still in JSON | Run `.\install.ps1 -Full` or `-Minimal` from a clone. |
| Just installed PowerShell 7 | Close all terminals, open a **PowerShell 7** tab once, re-run the installer so the profile GUID matches. |
| Dragon shows raw `$1` | Repo uses `logo.type` `"file"` in `config.jsonc`; keep that if you edit. |
| Wrong backup keeps restoring | Use `-HardReset` or pick the right `*.yoru-backup-*.bak` manually. |

For issues, paste output from `.\install.ps1 -Doctor` when you can.

---

## Customization

- **Transparency / acrylic** — `useAcrylic`, `opacity` in the Terminal profile section of `settings.json`.
- **Colors** — `schemes` → **Yoru** in `terminal/settings.json`.
- **Dragon** — edit `fastfetch/dragon.txt` or paths in `fastfetch/config.jsonc`.
- **Prompt** — `starship/starship.toml`.

Re-run `.\install.ps1 -Minimal` from a clone to push repo copies back to your user config paths (backup first).

---

## Roadmap

- More terminal style packs (layout is ready; **Sumi-e Crimson** ships first).
- Installer and docs stay beginner-safe and backup-first.

---

## Repo layout

```text
yoru-terminal/
├── assets/
├── fastfetch/
├── powershell/
├── starship/
├── terminal/
├── install.ps1
├── repo-structure.md
├── README.md
├── doctor.ps1
├── restore.ps1
├── uninstall.ps1
└── hardreset.ps1
```

---

## Credits

- [Windows Terminal](https://github.com/microsoft/terminal)
- [Fastfetch](https://github.com/fastfetch-cli/fastfetch)
- [Starship](https://starship.rs/)
- [Nerd Fonts](https://www.nerdfonts.com/)
