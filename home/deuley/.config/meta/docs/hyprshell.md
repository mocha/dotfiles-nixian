# hyprshell notes / gotchas

Hyprland launcher (Super+R → Overview → type). GTK4. Config here: `config.ron` (behavior),
`styles.css` (Catppuccin theme — see also [`theming.md`](theming.md)). Written 2026-06-20.

---

## Gotcha #1: webSearch silently does nothing without an explicit default browser

**Symptom:** the terminal action (Ctrl+t) works, but the search engines (Ctrl+s Kagi,
Ctrl+n NixOS, etc.) don't open anything. No error in the UI.

**Cause:** hyprshell's webSearch plugin resolves the browser by reading the **explicit**
`[Default Applications]` entry for `x-scheme-handler/https` in `~/.config/mimeapps.list`.
If there's no explicit entry it logs `No default browser found! (using firefox and gdbus to
open)` and falls back to a `gdbus` portal `OpenURI` call — **whose quoting is broken**
(`'%u'` → `''https://…''`, which bash collapses into an arg gdbus can't parse), so nothing
happens. Note `xdg-mime query default x-scheme-handler/https` can still *say* `firefox.desktop`
because xdg-mime falls back to the desktop file's `MimeType=` association — but hyprshell only
honors an explicit default, so that's misleading.

The terminal plugin works regardless because it finds the binary on `PATH`, a totally
different code path — that asymmetry is the tell.

**Fix:** set explicit defaults in `~/.config/mimeapps.list` under `[Default Applications]`:
```
x-scheme-handler/http=firefox.desktop
x-scheme-handler/https=firefox.desktop
text/html=firefox.desktop
```
(Also fixes link-opening system-wide for any app that was hitting the same missing default.)

**Verify:** `xdg-mime query default x-scheme-handler/https` → `firefox.desktop`.

---

## Gotcha #2: terminal is autodetected from PATH unless `default_terminal` is set

Without `default_terminal`, hyprshell searches a built-in `TERMINALS` list on `PATH` and uses
the first hit — here that was **kitty**, even though the rest of the session uses ghostty
(`~/.config/hypr/hyprland.lua` line 51, Super+Q). It logs `No default terminal found, searching
common terminals in PATH. (Set default_terminal in config…)`.

**Fix:** `config.ron` → `windows.overview.launcher.default_terminal: "ghostty"`. hyprshell builds
the command as `format!("{term} -e {run}")` — it adds `-e` itself, so the value is the **bare
binary** (`"ghostty"`, NOT `"ghostty -e"`). ghostty supports `-e`.

---

## Config structure notes (v4 RON)

- Engines: `windows.overview.launcher.plugins.websearch.engines` — list of
  `(url, name, key)`. `url` uses `{}` as the query placeholder; `key` is a single `char`
  (triggered as Ctrl+`<key>` while typing). Providing `engines` **replaces** the default list
  (Google+Wikipedia), so re-list any you want to keep.
- **`plugins` has no partial-merge:** a missing plugin field = **None = disabled** (the struct
  comment: "if some elements are missing, they should be None"). So you must list every plugin
  you want enabled, not just the one you're changing. Defaults: applications/terminal/websearch/
  path/actions on; shell/calc off.
- RON uses the **`implicit_some`** extension: write `applications: ()` (enable with defaults),
  NOT `Some(())`. The latter fails to parse.
- Validate without restarting: `hyprshell config check -c <file>` (silent = ok) and
  `hyprshell config explain -c <file>` (lists active plugins + engines by name).

---

## Styling / CSS (what the box model can and can't do)

- **Two embedded sheets define the structure**, both `var(--token, fallback)`-driven:
  `crates/launcher-lib/src/styles.css` (launcher rows) and `crates/windows-lib/src/styles.css`
  (overview/switch `.monitor`/`.workspace`/`.client`). Our `styles.css` is layered on top at GTK
  **USER** priority, so a plain class selector here overrides the app default for that class —
  and even a universal `*` selector beats the app's class rules (USER > APPLICATION regardless of
  specificity). That's the trap that made `* { font-size }` flatten the whole hierarchy. The full
  annotated widget tree lives in the header comment of `styles.css`.
- **`.launcher-item-name` does NOT inherit the row font-size** (`.launcher-item-inner`). Without an
  explicit `font-size` on `.launcher-item-name` it falls back to the tiny GTK theme default, so
  the app name renders smaller than the command — set its size directly.
- **`transform: scale()` DOES shrink `.client-image`** (the switch/overview app icons). The icon's
  pixel size is set in Rust from a hardcoded auto-fit formula (`calc_image_size: box/1.6 - 20`),
  so `width`/`min-*` can't cap it (they're floors) — but a CSS transform scales the rendered glyph
  within its box. (An earlier "transform is ignored" conclusion was a false negative from the
  stale reload above, NOT a GTK limitation — verify icon/CSS changes only after a real restart.)
- **What still needs a fork (not CSS):** stacking name *above* command — the row is a fixed
  horizontal `GtkBox` with a 45px height in `result.rs`, and GTK4 CSS can't reorient a box. Same
  for changing that box's height. Would need a patch + Nix overlay (see plugin note below).

## Gotcha #3: fonts "exploded after a reboot" — monitor scale changed 1 → 2

**Symptom:** every font in hyprshell (AND the wayle bar, AND other GTK apps) doubled in size
after a reboot, as if edits reverted. It looked app-specific but hit everything at once.

**Real cause — a deliberate config change, not flakiness:** the monitor scale was raised from
`1` to `2` in `~/.config/hypr/hyprland.lua` (the `hl.monitor{ scale = "2" }` block, ~line 17;
the archived `hyprland.lua.bak` still shows `scale = "1"`). Hyprland only applies the new scale
on the next reboot, so the doubling showed up "after a reboot."

**Why it doubled rather than just changed:** the panel is **2880×1800**. At scale 1 it renders
at native density → everything tiny, so app fonts had been **inflated** to stay readable. At
scale 2 (logical 1440×900 — the correct HiDPI setup) GTK renders those already-inflated fonts at
2×. So the giant text is the old scale-1 font sizes shown through the new 2x scale.

**Resolution: keep scale 2** (right for this panel) and bring each app's fonts back down to
normal — they were sized for the tiny scale-1 world. All sizes in `styles.css` are now picked
for how they look *at 2x* (≈half what you'd write at 1x).

**A second, separate trap made tuning miserable:** hot-reload was silently dead, so edits sat
un-read and we tuned against a frozen render (see "Operating the daemon"). **Always restart the
daemon and re-test before trusting a size — never judge against a hot-reload.**

**Verify scale:** `hyprctl monitors -j | grep -E 'name|scale|width'` → eDP-1, 2880×1800, 2.00.

## Operating the daemon

- Launched by `~/.config/hypr/hyprland.lua` via `hyprshell run` with `DISPLAY=:0` set (so it
  reads X dconf/XSettings for the GTK theme — see theming.md gotcha #9).
- **Hot-reload exists but is UNRELIABLE — always restart to be sure.** The daemon logs
  `Starting hyprshell css reload listener` (and a config one) at startup, so edits *sometimes*
  re-render live. But it goes stale silently: a saved change shows "nothing changed" and you
  chase a phantom CSS bug that's really just an un-reloaded file. **After editing config.ron or
  styles.css, restart the daemon** and re-test — don't trust the live reload.
- **Restarting is booby-trapped — kill by PID:**
    - `pkill -f 'hyprshell run'` **kills your own shell**: `-f` matches full command lines, and
      the pkill command line itself contains the string `hyprshell run`, so it self-matches.
    - `pkill -x hyprshell` **silently misses it**: the process `comm` differs from the cmdline,
      so the exact-name match finds nothing (and reports success).
    - Reliable: `kill $(pgrep -f 'hyprshell run' | head -1)` (the daemon's the lone match besides
      your shell), confirm it's gone, then relaunch:
      `setsid bash -c 'export DISPLAY=:0; unset HL_INITIAL_WORKSPACE_TOKEN; exec hyprshell run' &`
    - A stale instance makes the relaunch fail with `Error: Daemon already running` — make sure
      the old PID is actually dead first.
- Default stdout/stderr is `/dev/null`. To debug, relaunch with `-v` and redirect:
  `… exec hyprshell run -v >/tmp/hyprshell.log 2>&1`. The search/terminal plugins log the exact
  command they run at DEBUG.
- **No external plugin API** — plugins are compiled-in Rust (`crates/launcher-lib/src/plugins/`).
  New functionality (e.g. auto web-search fallback when no app matches) means forking + a Nix
  overlay, like the hyprgrass override.
