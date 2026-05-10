# Contributing

Thanks for helping improve Yoru Terminal.

## Report issues

Use [GitHub Issues](https://github.com/tprojectzdev-sys/yoru-terminal/issues) and pick the closest template. If you cloned the repo, run `.\install.ps1 -Doctor` (or `.\doctor.ps1`) and paste the output — it saves a lot of back-and-forth.

## Submit improvements

- Fork, branch, and open a PR with a short description of **what** changed and **why**.
- Keep PRs focused (installer vs docs vs templates) so review stays easy.
- Avoid bundling unrelated refactors with a bugfix.

## Test installer changes

From a clone of your branch:

```powershell
cd yoru-terminal
pwsh -NoProfile -File .\install.ps1 -Doctor
pwsh -NoProfile -File .\install.ps1 -Minimal   # or -Full
pwsh -NoProfile -File .\install.ps1 -Restore
pwsh -NoProfile -File .\install.ps1 -Uninstall
pwsh -NoProfile -File .\install.ps1 -HardReset
```

Use `-Minimal` when you already have dependencies and only need to validate config copy logic. Use a VM or disposable user profile when exercising `-Restore` / `-Uninstall` if possible.

## PowerShell style

- Target **Windows PowerShell 5.1** and **PowerShell 7+** unless a change truly requires 7-only APIs (avoid that when possible).
- Prefer `LiteralPath` for user file paths.
- Use `$ErrorActionPreference = 'Stop'` at the script entry; handle expected errors explicitly.
- Keep output calm: section headers, `[ok]` / `[warn]` / `[missing]` / `[fix]` for diagnostics, dim paths on their own lines.

## Rules (non-negotiable)

1. **Never overwrite user config without a timestamped backup** beside the original (same directory), except when creating a new file where none existed.
2. **Theme and visual changes stay modular** — do not entangle future themes with installer internals; keep Sumi-e Crimson assets as the reference pack unless the project explicitly adds another pack.
3. **Public-facing scripts must be beginner-safe** — clear messages, predictable defaults, no surprise deletes, and an obvious restore/uninstall story.
