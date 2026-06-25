# docs — system reference library

Deep-dive docs that exist to **shortcut re-investigation**. Each one leads with
the root causes that wasted the most time. Linked from [`../CLAUDE.md`](../CLAUDE.md).

- [`theming.md`](theming.md) — desktop theming architecture: Catppuccin Mocha
  (mauve accent) across Qt-Widgets, QtQuick, GTK, Kvantum, notifications. Explains
  which toolkit uses which mechanism and why setting colors globally breaks things.
- [`hyprshell.md`](hyprshell.md) — hyprshell launcher (Super+R): webSearch default-browser
  gotcha, daemon operation/reload, scaling, theming hooks.
- [`polkit.md`](polkit.md) — the polkit auth agent (soteria): what's supposed to run, why
  hyprpolkit was removed, and the three gotchas (needs `XDG_SESSION_ID`, one-agent-per-session,
  silent de-registration after every `nixos-rebuild`) + how to recover `pkexec`.
- [`power-thermal.md`](power-thermal.md) — what manages CPU frequency/power/heat (intel_pstate
  HWP + firmware DPTF + power-profiles-daemon) and why we deliberately *don't* run thermald;
  includes the Panther Lake (CPUID 0xCC) thermald-≥2.5.9 gotcha.
- [`visage.md`](visage.md) — face authentication (Windows-Hello-style) for sudo/pkexec/hyprlock:
  the Luxvisions 30c9:0120 IR-emitter quirk, the patched fork at `~/code/visage`, the hermetic
  Nix build, and the enroll/liveness/rate-limit gotchas (incl. "it only works when you're
  actually in front of the camera").

Conventions:
- Filenames are lowercase, topic-based.
- Keep facts atomic and put durable one-liners in the memory system
  (`~/.claude/projects/-home-deuley/memory/`); use these files for the long form.
