# docs — system reference library

Deep-dive docs that exist to **shortcut re-investigation**. Each one leads with
the root causes that wasted the most time. Linked from [`../CLAUDE.md`](../CLAUDE.md).

- [`theming.md`](theming.md) — desktop theming architecture: Catppuccin Mocha
  (mauve accent) across Qt-Widgets, QtQuick, GTK, Kvantum, notifications. Explains
  which toolkit uses which mechanism and why setting colors globally breaks things.
- [`hyprshell.md`](hyprshell.md) — hyprshell launcher (Super+R): webSearch default-browser
  gotcha, daemon operation/reload, scaling, theming hooks.

Conventions:
- Filenames are lowercase, topic-based.
- Keep facts atomic and put durable one-liners in the memory system
  (`~/.claude/projects/-home-deuley/memory/`); use these files for the long form.
