# System management — operating procedures

Home base for managing deuley's NixOS / Hyprland laptop (hostname **nixian**).
Start Claude sessions here (`cd ~/.config/meta && claude`) so this file loads as
project context. This is the *how we operate* file; durable facts live in the
memory system and deep references live in [`docs/`](docs/).

## The machine
- NixOS on an HP OmniBook X Flip 14" 2-in-1 (board 8EA4). Hostname `nixian`.
- Hyprland (Wayland) via uwsm + ly. **No home-manager** — user configs are
  hand-written under `~/.config/`.

## Making changes safely

### System config (`/etc/nixos/`)
- One root-owned file does most of the work: `/etc/nixos/configuration.nix`
  (plus `hardware-configuration.nix`, `pkgs/`, `fonts/`).
- The Edit tool **cannot write root-owned files**. Workflow: copy the file to a
  writable spot (e.g. scratchpad), edit the copy, then install it with a backup:
  ```
  pkexec cp -a /etc/nixos/configuration.nix /etc/nixos/configuration.nix.bak-<desc>
  pkexec cp <edited-copy> /etc/nixos/configuration.nix
  pkexec nixos-rebuild switch
  ```
- **Always snapshot before risky edits** (the `.bak-<desc>` convention above).
  Roll back via NixOS generations if a switch goes wrong.

### Elevation
- Use **`pkexec`, never `sudo`** — agent sessions have no tty for sudo's askpass.
  hyprpolkitagent surfaces the GUI auth prompt.

### Dotfiles (tracking config in git)
- Bare-repo pattern: **git-dir `~/.dotfiles`, work-tree `/`**. Driver is the `dot`
  alias/function in `~/.zshrc`.
- Track a file: `dot add <path>`. Pretty status: `dot` (no args). Commit: `dot commit`.
- **Keep `~/.dotfiles/` a pure git-dir** — don't store tracked content inside it.
  Tracked files live at their real paths in the work-tree (e.g. `~/.config/...`,
  `/etc/nixos/...`). This `meta/` dir is the home for setup-related docs.
- Nothing is auto-committed; staging is left for deuley to review and commit.

## Hyprland gotcha
- The Hyprland config is **lua** (`~/.config/hypr/hyprland.lua`). Under lua,
  `hyprctl dispatch` needs `hl.dsp.*` syntax; a plain `dispatch workspace N`
  silently no-ops.

## Where things live
- **`~/.config/meta/`** (here) — operating procedures (this file) + `docs/`.
- **[`docs/`](docs/)** — deep-dive references that shortcut re-investigation
  (see [`docs/README.md`](docs/README.md)).
- **Memory system** — `~/.claude/projects/-home-deuley/memory/` holds atomic,
  durable facts/gotchas and is auto-loaded every session (index: `MEMORY.md`).
  Prefer it for new facts; use `docs/` for long-form reference.

## Docs index
- [`docs/theming.md`](docs/theming.md) — how the Catppuccin Mocha (mauve) theme
  is wired across Qt-Widgets / QtQuick / GTK / Kvantum; leads with root-cause gotchas.
- [`docs/hyprshell.md`](docs/hyprshell.md) — hyprshell launcher (Super+R) notes & gotchas.
