#!/usr/bin/env bash
# Toggle the squeekboard on-screen keyboard for tablet mode.
#
# Quit-on-hide, by design: squeekboard's Wayland virtual-keyboard can leave a
# modifier (Shift/Caps) latched on Hyprland. While the process lives, that latch
# bleeds into the PHYSICAL keyboard — stuck caps, dead SUPER combos, shifted
# punctuation — even when the OSK window is hidden. So "hide" = fully quit;
# destroying the virtual keyboard device releases any latch.
#
# Detection is via the DBus name sm.puri.OSK0, NOT pgrep: NixOS wraps the
# binary, so the process comm is ".squeekboard-wr" and `pgrep -x squeekboard`
# never matches (which made every press only ever launch, never dismiss).
#
# Wired to the bottom-edge swipe-up gesture and SUPER+K in hyprland.lua, and to
# the keyboard button in the Wayle bar.
set -euo pipefail

DEST=sm.puri.OSK0
OBJ=/sm/puri/OSK0

if busctl --user status "$DEST" >/dev/null 2>&1; then
    # Running → quit it (releases any latched modifier). Kill the exact process
    # that owns the OSK bus name; fall back to a pattern kill if we can't read it.
    pid=$(busctl --user status "$DEST" 2>/dev/null | awk -F= '/^PID=/{print $2; exit}')
    if [ -n "${pid:-}" ]; then
        kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
    else
        pkill -f squeekboard 2>/dev/null || true
    fi
    exit 0
fi

# Not running → launch and show.
squeekboard >/dev/null 2>&1 &
for _ in $(seq 1 50); do
    busctl --user status "$DEST" >/dev/null 2>&1 && break
    sleep 0.1
done
busctl --user call "$DEST" "$OBJ" "$DEST" SetVisible b true 2>/dev/null || true
