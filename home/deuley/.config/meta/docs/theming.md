# Theming architecture (Hyprland on NixOS)

How the desktop theme is wired together. Goal: **Catppuccin Mocha (mauve accent)** everywhere.
Written 2026-06-20 after a long debugging session — the point of this file is to
**shortcut re-investigation**, so it leads with the root causes that wasted the most time.

Config is split across two places:
- **System** — `/etc/nixos/configuration.nix` (root-owned; edit a copy + `pkexec cp` back, then `nixos-rebuild`).
- **User** — `~/.config/*` and `~/.local/share/*` (hand-written; no home-manager).

---

## TL;DR — which toolkit uses which mechanism

| App type | Examples | Style/render | Colors come from |
|---|---|---|---|
| **Qt-Widgets** | Dolphin, moonlight-qt | Kvantum (`QT_STYLE_OVERRIDE=kvantum`) | **plasma-integration** maps `kdeglobals` → Qt palette |
| **GTK (polkit)** | soteria (polkit dialog) | GTK theme | catppuccin-gtk theme + GTK default font (Monoflow) |
| **GTK 3/4** | Firefox, file dialogs | `gtk-theme-name` (but see gotcha #9) | catppuccin-gtk theme |
| **GTK launcher** | hyprshell | catppuccin-gtk theme + custom `styles.css` | dconf `gtk-theme` + hyprshell CSS tokens |
| **Notifications** | — | hyprpanel built-in daemon | hyprpanel config (Catppuccin) |

The single most important fact: **KDE/Qt-Widgets apps color from plasma-integration (the `kde`
platform theme) — do NOT set `qt6ct`/`qt5ct` globally or it fights Kvantum and breaks Dolphin.**
See "Root causes" below. (The polkit dialog used to be the awkward exception here as a QtQuick app;
it's now GTK soteria and just follows the GTK theme.)

---

## Root causes / gotchas (read this first next time)

1. **KDE apps (Dolphin) need `plasma-integration`.** They color their palette from `kdeglobals`
   via `KColorScheme`, but in a non-Plasma session *nothing applies it to the Qt palette* unless
   the **`kde` platform theme** (plasma-integration / `KDEPlasmaPlatformTheme6.so`) is installed.
   Without it: Kvantum paints dark backgrounds but view-item text stays dark → **dark-on-dark**.
   `qt6ct` does NOT do this bridge for KDE apps. → Fix: `qt.platformTheme = "kde"`.

2. **A global `QT_QPA_PLATFORMTHEME=qt5ct` (qt6ct) breaks Dolphin** — it forces a palette that fights
   Kvantum. That's why qt6ct is **scoped to the polkit agent only** (systemd drop-in), never global.

3. **`kdeglobals` `ColorScheme=Name` needs the matching `Name.colors` file installed**, or
   `KColorSchemeManager` falls back to Breeze. Ours lives at
   `~/.local/share/color-schemes/CatppuccinMochaMauve.colors`.

4. **`pathsToLink` doesn't link `/share/Kvantum`, `/share/qt6ct`, `/share/qt5ct`** (but *does* link
   `/share/themes`, which is why GTK "just worked"). So the Kvantum theme and qt color schemes are
   **copied into `~/.config`** rather than referenced from the system profile. (Alternative would be
   adding those dirs to `environment.pathsToLink`.)

5. **The polkit dialog is a QtQuick app.** A plain white box = the bare `"Basic"` QtQuick style
   (no `QT_QUICK_CONTROLS_STYLE` set). It needs a style AND a palette source.

6. **`graphical-session.target` is only active in the UWSM session.** Log into **"Hyprland (UWSM)"**
   at the `ly` greeter, not plain "Hyprland". In the plain session the target is dead, so
   `hyprpolkitagent` (and other graphical user services) never autostart — and `pkexec` then falls
   back to a TTY agent and fails with "Error opening current controlling terminal". `ly` remembers
   the last choice, so picking UWSM once is enough.

7. **qt6ct's plugin registers under BOTH `qt5ct` and `qt6ct` keys**, so `QT_QPA_PLATFORMTHEME=qt5ct`
   correctly loads qt6ct for Qt6 apps. (Nixpkgs `qt.platformTheme` enum key is `qt5ct`, not `qtct`.)

8. **Hyprland window opacity** (active vs inactive) is separate from KDE and can wash out contrast —
   don't confuse it with the KDE inactive-color-effect.

9. **`dconf` overrides `gtk-3.0/4.0/settings.ini` for GTK theme/icon/font.** GTK reads the
   `org.gnome.desktop.interface` keys (via gsettings/dconf) at *higher* priority than `settings.ini`.
   Our `settings.ini` said `catppuccin-mocha-mauve-standard` but dconf `gtk-theme` was a stale
   **`Nordic`** — so GTK4 apps actually rendered Nordic, silently. Found via hyprshell logging
   `Using theme: Some("Nordic")`. Fix: `dconf write /org/gnome/desktop/interface/gtk-theme "'catppuccin-mocha-mauve-standard'"`.
   Check all three sources are consistent: `dconf read .../gtk-theme`, the two `settings.ini`, and
   `~/.config/xsettingsd/xsettingsd.conf` (`Net/ThemeName`; only matters if xsettingsd runs — it
   currently doesn't, but it was also stale-Nordic and is now fixed). `gsettings` CLI may report
   "no schema" in a bare shell even though dconf holds the value — trust `dconf dump`.

---

## Qt-Widgets (Dolphin, etc.) — the main event

**System** (`configuration.nix`):
```nix
qt = {
  enable = true;
  platformTheme = "kde";    # plasma-integration: kdeglobals → Qt palette  (THE fix for KDE apps)
  style = "kvantum";        # Kvantum widget rendering
};
```
Sets `QT_QPA_PLATFORMTHEME=kde` + `QT_STYLE_OVERRIDE=kvantum` globally.

**User config:**
- `~/.config/kdeglobals` — Catppuccin Mocha Mauve color scheme (the palette source). `[General] ColorScheme=CatppuccinMochaMauve`.
- `~/.local/share/color-schemes/CatppuccinMochaMauve.colors` — named scheme so KColorScheme resolves it.
- `~/.config/Kvantum/kvantum.kvconfig` → `theme=catppuccin-mocha-mauve`
- `~/.config/Kvantum/catppuccin-mocha-mauve/` — theme files (copied from the `catppuccin-kvantum` override).

**Packages:** `catppuccin-kvantum` (override accent=mauve variant=mocha), `qt.style="kvantum"` pulls the
Kvantum engine, `platformTheme="kde"` pulls plasma-integration + kio + systemsettings.
`kdePackages.breeze` was added only to A/B styles — Kvantum won, so it can be removed.

---

## Polkit dialog (soteria — GTK4)

**Replaced hyprpolkitagent (QtQuick) with `soteria` (2026-06-23.)** The old QtQuick dialog
was over-wide, had no internal padding (layout baked into its QML), and needed a whole Qt-scoping
contraption (qt6ct + qqc2-desktop-style + a per-service `UnsetEnvironment=QT_STYLE_OVERRIDE`).
soteria is GTK4, so it just follows the **GTK theme + GTK default font** like wayle/hyprshell —
dark Catppuccin surface, mauve accent, rounded, Monoflow. All the Qt scoping (and the
`qt6ct`/`qqc2-desktop-style`/`catppuccin-qt5ct` packages) was deleted.

- **Package:** `soteria`. No systemd unit and no config file needed (default config is fine;
  optional `~/.config/soteria/config.toml` exists if you ever want to tweak it).
- **GOTCHA — launch from the compositor, not a systemd user service.** soteria reads
  `XDG_SESSION_ID` from its env. The systemd `--user` manager does **not** carry that var (only
  the login session does), so a user service crash-loops: `Error: Could not get XDG session id`.
  It's started from `~/.config/hypr/hyprland.lua` (`hl.exec_cmd("soteria …")`) inside the
  `hyprland.start` handler — same pattern as wayle — which runs in the full session env. Don't
  "promote" it back to a systemd unit without exporting `XDG_SESSION_ID` to the user manager first.
- **Window identity** (Hyprland window rules): class `gay.vaskel.soteria`, title `Authorize`.
- **Theming source:** GTK theme via dconf `gtk-theme` (catppuccin-mocha-mauve-standard) + the
  GTK default font (Monoflow, see Fonts below). The mauve window border / rounding come from the
  Hyprland decoration config, like every other window.

---

## Fonts — Monoflow everywhere

Goal: **Monoflow** (personally-licensed, OTFs in `/etc/nixos/fonts/monoflow`) as the single UI font,
proportional and monospace alike. It's set at three layers because each toolkit resolves fonts
differently — miss one and that toolkit silently falls back:

1. **NixOS / fontconfig** (`configuration.nix`): `fonts.fontconfig.defaultFonts.{monospace,sansSerif,serif}
   = [ "Monoflow" "DejaVu …" ]`. Without this, generic `monospace` resolved to **DejaVu Sans Mono**
   and `sans-serif` to a system fallback — so anything not naming a font explicitly never got Monoflow.
   Verify: `fc-match monospace` / `sans-serif` / `serif` should all say Monoflow.
2. **GTK** (dconf wins — gotcha #9): `org.gnome.desktop.interface` `font-name` / `monospace-font-name` /
   `document-font-name` = `Monoflow 10`; keep `~/.config/gtk-3.0/4.0/settings.ini` `gtk-font-name` in sync.
3. **Qt-Widgets** (`~/.config/kdeglobals` `[General]`): `font`/`fixed`/`menuFont`/`toolBarFont`/
   `smallestReadableFont = Monoflow,…` (plasma-integration reads these for KDE/Qt apps).

Running GTK/Qt apps must be **restarted** to pick up a font change. wayle already names Monoflow in
its own `config.toml` (`font-sans`/`font-mono`); soteria/hyprshell inherit it via the GTK layer.

## GTK (Firefox, GTK file dialogs)

`~/.config/gtk-3.0/settings.ini` and `gtk-4.0/settings.ini`:
```
gtk-theme-name=catppuccin-mocha-mauve-standard
```
Package: `catppuccin-gtk` (override accents=[mauve] variant=mocha). Resolves via `/share/themes`
(which *is* in pathsToLink). GTK4/libadwaita apps may ignore the theme — would need `gtk.css`
copied into `~/.config/gtk-4.0/` if a stubborn one shows up.

---

## hyprshell (launcher / overview / alt-tab switcher — GTK4)

The launcher (Super+R → Overview, then type). GTK4 app, so it follows the **GTK theme** above
(its base widgets) **plus** a custom stylesheet for its own widgets.

- **Base theme:** read from dconf `gtk-theme` (gotcha #9). hyprshell logs the resolved name at
  startup (`Using theme: Some(...)`) — a fast way to confirm the GTK theme actually in effect.
- **Custom CSS:** `~/.config/hyprshell/styles.css` (default `--css-file` path). hyprshell layers it
  *on top* of its compiled-in stylesheet at GTK user priority, and the built-in rules read all colors
  from `var(--token, fallback)` custom properties — so retheming = redefine those tokens (set on `*`
  so the "other menu" popover, a separate surface, gets them too) plus a few explicit refinements.
  Ours is Catppuccin Mocha + mauve; the key fix was `--border-color-active` (was a harsh red).
- **Config:** `~/.config/hyprshell/config.ron` (keybinds/behavior only, no colors).
- **It only reads CSS at startup-ish.** A running daemon started *before* the file existed never
  picks it up — restart it. There IS a css reload listener once running, but don't trust it after the
  fact; just restart: the lua launcher runs `hyprshell run` (see `~/.config/hypr/hyprland.lua`, which
  sets `DISPLAY=:0` — that's why it reads X **dconf/XSettings** for the GTK theme).
- **Validate CSS offline:** `nix-shell -p gjs gtk4 --run 'gjs check.js'` with a `Gtk.CssProvider`
  + `parsing-error` handler beats restarting the daemon to find a typo. GTK4 ≥4.16 supports `var()`.
- **Triggering it for a screenshot is hard:** Super+R is a `__lua` bind (lua config manager);
  `hyprctl dispatch` and `wtype` both failed to fire it. Just open it by hand to verify.

---

## Notifications

- **dunst removed** from packages — hyprpanel's built-in daemon owns `org.freedesktop.Notifications`.
  (There's still an `exec-once = dunst` in the hypr config; it's a harmless no-op once the package is gone —
  drop it when the lua migration touches that file.)
- `~/.config/hyprpanel/config.json`:
  - `theme.notification.enableShadow = true`  ← the margin is gated behind this
  - `theme.notification.shadowMargins = "2.5rem 2.5rem 2.5rem 2.5rem"`  (gap from screen corner)
  - `notifications.spacing = "0.5rem"`
- Check who owns the bus: `busctl --user status org.freedesktop.Notifications`

---

## Session launch / autostart

- `programs.hyprland.withUWSM = true` (note: it only flips `uwsm.enable`, already on; both session
  entries still exist).
- **Always log into "Hyprland (UWSM)"** at `ly` → activates `graphical-session.target` →
  `hyprpolkitagent` and other graphical user services autostart. See gotcha #6.

---

## Testing techniques

- **Trigger a polkit prompt (uncached, real auth):** `systemctl restart systemd-timesyncd.service`
  — harmless and always prompts. Do NOT use idempotent `timedatectl set-*` no-ops (they skip polkit)
  or repeated `pkexec` (auth is cached `auth_admin_keep` ~5 min).
- **Screenshot:** `grim ~/shot.png` (full), `grim -g "$(slurp)" ~/shot.png` (region).
  Crop one window: `grim -g "$(hyprctl clients -j | jq -r '.[]|select(.class|test("dolphin";"i"))|"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"')" ~/win.png`
- **Sample a pixel:** `nix-shell -p imagemagick --run 'magick shot.png -format "%[pixel:u.p{X,Y}]" info:'`
  (the `gm` on this box is shadowed and doesn't work for this).
- Dolphin is single-instance (D-Bus); `dolphin &` raises the existing window. `pkill -x dolphin` first
  for a clean relaunch with new env.

---

## File map

| Path | Purpose |
|---|---|
| `/etc/nixos/configuration.nix` | `qt.*`, `fonts.fontconfig.defaultFonts`, theme/font packages, `soteria`, `withUWSM` |
| `~/.config/hypr/hyprland.lua` | launches `soteria` (polkit agent) + wayle in the `hyprland.start` handler |
| `~/.config/kdeglobals` | Catppuccin KColorScheme + Qt-Widgets font (`font`/`fixed`/… = Monoflow) |
| `~/.local/share/color-schemes/CatppuccinMochaMauve.colors` | named scheme for KColorScheme resolution |
| `~/.config/Kvantum/{kvantum.kvconfig, catppuccin-mocha-mauve/}` | Kvantum widget theme |
| `~/.config/gtk-3.0/settings.ini`, `gtk-4.0/settings.ini` | GTK theme + `gtk-font-name` (but dconf wins — gotcha #9) |
| dconf `org.gnome.desktop.interface` | GTK theme/icon/font *actually* in effect (overrides settings.ini) |
| `~/.config/xsettingsd/xsettingsd.conf` | XSettings theme name (only if xsettingsd runs; keep in sync) |
| `~/.config/hyprshell/styles.css` | hyprshell launcher/overview Catppuccin CSS (overrides + tokens) |
| `~/.config/hyprshell/config.ron` | hyprshell keybinds/behavior (no colors) |
| `~/.config/hyprpanel/config.json` | bar + notification theming |
