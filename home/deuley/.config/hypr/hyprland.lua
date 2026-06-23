-- Translated from hyprland.conf to enable the lua config manager (required by hyprshell).
-- Hyprland picks hyprland.lua over hyprland.conf when both exist.
-- Rename or delete this file to fall back to hyprland.conf.
--
-- The hardware monitor/input/gesture/device config previously lived in
-- hyprland-hardware.conf; it's inlined below because lua can't `source` hyprlang.

----------------
---- HARDWARE ----
-----------------

local builtinMonitor = {
    output   = "eDP-1",
    mode     = "preferred",
    position = "auto",
    scale    = "2",
    disabled = false,
}

-- register monitor settings on startup
hl.monitor(builtinMonitor)

function disableLaptopMonitor()
    hl.monitor({
        output = builtinMonitor.output,
        disabled = true ,
    })
end

function enableLaptopMonitor()
    hl.monitor(builtinMonitor)
    os.execute("hyprctl reload")
end

-- close lid
hl.bind("switch:on:Lid Switch", disableLaptopMonitor, { locked = true })
-- open lid
hl.bind("switch:off:Lid Switch", enableLaptopMonitor, { locked = true })

hl.config({
    input = {
        kb_layout    = "us",
        kb_variant   = "",
        kb_model     = "",
        kb_options   = "",
        kb_rules     = "",
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad = {
            natural_scroll = false,
            scroll_factor  = 0.3,
        },
    },
})

hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})


---------------------
---- MY PROGRAMS ----
---------------------

local terminal    = "ghostty"
local fileManager = "dolphin"
-- Launcher is hyprshell, registered by its own daemon on Super+R via lua eval.


-------------------
---- AUTOSTART ----
-------------------

-- hyprgrass registers the touch-gesture lua API and dispatchers.
hl.plugin.load("/etc/hypr/plugins/libhyprgrass.so")
-- TODO(hyprspace): Re-enable once the upstream lua API patch lands in the
-- packaged version. In 0.1 (current), no addLuaFunction calls exist, so
-- overview:toggle is unreachable from lua. Re-enable BOTH this load AND
-- the swipe-up gesture binding further down in the HYPRGRASS section.
-- hl.plugin.load("/etc/hypr/plugins/libhyprspace.so")

hl.on("hyprland.start", function()

    -- Polkit auth agent: surfaces GUI escalation prompts so pkexec works without
    -- a TTY. Normally pulled in by graphical-session.target under the "Hyprland
    -- (UWSM)" session, but that target stays inactive on the plain "Hyprland"
    -- session, leaving no registered agent (pkexec then falls back to the textual
    -- agent, needs /dev/tty, and dies for non-interactive callers like agents).
    -- Starting the unit here makes it present on either session; idempotent, so
    -- it's a harmless no-op when UWSM already started it.
    hl.exec_cmd("systemctl --user start hyprpolkitagent.service")

    -- Desktop shell: bar + notifications + OSD. Migrated from HyprPanel (which
    -- is deprecated upstream) to Wayle. Wayle owns org.freedesktop.Notifications,
    -- so dunst is retired (it was a dead no-op anyway — it lost the bus race to
    -- HyprPanel and exited). To roll back: comment the wayle line and restore
    -- `hl.exec_cmd("hyprpanel")`.
    -- hl.exec_cmd("dunst")
    -- hl.exec_cmd("hyprpanel")
    hl.exec_cmd("wayle shell >/tmp/wayle.log 2>&1")

    -- Power-aware idle manager. Owns hypridle's lifecycle: generates its config
    -- from the (power-profile x AC) matrix and restarts it on power changes.
    -- See ~/.config/hypr/scripts/idle-power.sh.
    hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/idle-power.sh")

    -- Wait for XWayland's socket before starting hyprshell, then start it with
    -- DISPLAY set. Otherwise hyprshell (and every app it launches) inherits an
    -- environment with no DISPLAY, so X11/XWayland apps like Steam silently fail
    -- to open a window. See hyprland.start firing before XWayland is ready.
    -- unset HL_INITIAL_WORKSPACE_TOKEN so apps hyprshell launches open on the
    -- CURRENT workspace instead of inheriting the daemon's startup workspace.
    -- (initial_workspace_tracking=1 stamps this token into the daemon at start,
    -- and every child app would otherwise inherit it and pin to workspace 1.)
    hl.exec_cmd("bash -c 'for i in $(seq 1 100); do [ -e /tmp/.X11-unix/X0 ] && break; sleep 0.1; done; export DISPLAY=:0; unset HL_INITIAL_WORKSPACE_TOKEN; exec hyprshell run'")

    -- hl.exec_cmd("hyprpaper")
    -- hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/wallpaper-loop.sh")

    -- On-screen keyboard for tablet mode. NOT autostarted: squeekboard's
    -- virtual-keyboard protocol can leave a modifier (Shift/Caps) latched on
    -- Hyprland, which makes the physical keyboard type as if shift is held
    -- (stuck caps, SUPER combos dead, punctuation shifted). Start it on demand
    -- instead via the bottom-edge swipe-up gesture / SUPER+K toggle
    -- (squeek-toggle.sh self-launches it). Revisit autostart once the latched-
    -- modifier issue is sorted.
    -- hl.exec_cmd("squeekboard")

    -- Additions for screen sharing per https://gist.github.com/brunoanc/2dea6ddf6974ba4e5d26c3139ffb7580
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")

    -- Clipboard history watcher: cliphist records every wl-clipboard selection so
    -- the clipboard picker keybind can recall earlier copies.
    hl.exec_cmd("wl-paste --watch cliphist store")

end)


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_THEME",  "WhiteSur-cursors")
hl.env("XCURSOR_SIZE",   "32")
hl.env("HYPRCURSOR_SIZE", "32")


-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in  = 6,
        gaps_out = 10,
        border_size = 2,
        col = {
            -- active_border   = { colors = {"rgba(203,166,247,0.8)", "rgba(244,166,247,0.8)"}, angle = 20 },
            active_border   = { colors = { "rgb(141,60,238)", "rgb(235,96,241)" }, angle = 20 },
            inactive_border = { colors = { "rgb(121,26,235)", "rgb(56,10,111)"  }, angle = 20 },
        },
        resize_on_border        = true,
        extend_border_grab_area = 10,
        allow_tearing           = false,
        layout                  = "dwindle",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,
        active_opacity   = 1.0,
        inactive_opacity = 0.8,
        shadow = {
            enabled      = true,
            range        = 10,
            render_power = 2,
            color        = "rgba(0,0,0,.6)",
        },
        blur = {
            enabled  = true,
            size     = 6,
            passes   = 3,
            -- vibrancy = 0.1696,
            vibrancy = 1,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = false,
    },
})

-- Animation curves
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1} } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}    } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1} } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}  } })

hl.animation({ leaf = "global",        enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",        enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",       enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",     enabled = true, speed = 4.1,  bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut",    enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",        enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",       enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",          enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",        enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",      enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor",    enabled = true, speed = 7,    bezier = "quick" })

-- Smart gaps: drop gaps/borders/rounding when only one window on these workspace patterns.
-- These were broken in the .conf (used lua syntax without hl. prefix); now properly wired.
hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
hl.window_rule({
    name = "no-gaps-wtv1-border",
    match = { float = false, workspace = "w[tv1]" },
    border_size = 0,
})
hl.window_rule({
    name = "no-gaps-wtv1-round",
    match = { float = false, workspace = "w[tv1]" },
    rounding = 0,
})
hl.window_rule({
    name = "no-gaps-f1-border",
    match = { float = false, workspace = "f[1]" },
    border_size = 0,
})
hl.window_rule({
    name = "no-gaps-f1-round",
    match = { float = false, workspace = "f[1]" },
    rounding = 0,
})


------------------
---- HYPRGRASS ----
------------------

-- Plugin options and binds wrapped in pcall so a missing/unloaded plugin
-- doesn't kill the whole config eval. (In particular, --verify-config does
-- not actually load .so plugins, so the hyprgrass lua namespace isn't
-- registered at verify time.)
pcall(function()
    hl.config({
        plugin = {
            hyprgrass = {
                sensitivity                 = 4.0,
                long_press_delay            = 400,
                resize_on_border_long_press = true,
                edge_margin                 = 10,
            },
        },
    })
end)

pcall(function()
    -- 3-finger down → close active window
    hl.plugin.hyprgrass.bind {
        pattern = { kind = "swipe", fingers = 3, direction = "down" },
        action  = hl.dsp.window.close(),
    }
    -- -- 3-finger up → launcher
    -- hl.plugin.hyprgrass.bind {
    --     pattern = { kind = "swipe", fingers = 3, direction = "up" },
    --     action  = hl.dsp.exec_cmd( hyprshell??? ),
    -- }
    -- Left edge swipe right → previous workspace
    hl.plugin.hyprgrass.bind {
        pattern = { kind = "edge", origin = "left", direction = "right" },
        action  = hl.dsp.focus({ workspace = "e-1" }),
    }
    -- Right edge swipe left → next workspace
    hl.plugin.hyprgrass.bind {
        pattern = { kind = "edge", origin = "right", direction = "left" },
        action  = hl.dsp.focus({ workspace = "e+1" }),
    }
    -- 3-finger long-press → drag active window (recovers what was lost in hyprlang)
    hl.plugin.hyprgrass.bind {
        pattern = { kind = "longpress", fingers = 3 },
        action  = hl.dsp.window.drag(),
        mouse   = true,
    }
    -- Bottom edge swipe up → toggle the on-screen keyboard (tablet mode)
    hl.plugin.hyprgrass.bind {
        pattern = { kind = "edge", origin = "down", direction = "up" },
        action  = hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/squeek-toggle.sh"),
    }
end)


---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "SUPER"

hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
-- hl.bind(mainMod .. " + M", hl.dsp.exit())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
-- Super+R is registered by hyprshell's daemon via lua eval (hyprshell run).
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
-- Toggle the on-screen keyboard (non-touch fallback for the bottom-edge swipe).
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/squeek-toggle.sh"))

-- Dictation toggle. The HP Assistant/Copilot button sends SUPER+SHIFT+F23 (the keymap
-- labels it XF86Assistant at the shifted level, but Hyprland matches the base keysym F23).
hl.bind("SUPER + SHIFT + F23", hl.dsp.exec_cmd("dictation-toggle"))
hl.bind(mainMod .. " + SHIFT + D", hl.dsp.exec_cmd("DICTATION_NOPASTE=1 dictation-toggle"))
-- Clipboard/transcript history picker (SUPER+V is window-float toggle, so SHIFT+V):
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd("sh -c 'cliphist list | fuzzel --dmenu --with-nth 2 | cliphist decode | wl-copy'"))

-- Move focus with mainMod + arrows
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Workspaces 1-10 (key 0 maps to workspace 10)
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Cycle workspaces: scroll wheel or Mod+Alt+arrow
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + ALT + left",  hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + ALT + right", hl.dsp.focus({ workspace = "e+1" }))

-- Mouse drag/resize
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- VT switching
hl.bind("CTRL + ALT + F1", hl.dsp.exec_cmd("chvt 1"))
hl.bind("CTRL + ALT + F2", hl.dsp.exec_cmd("chvt 2"))
hl.bind("CTRL + ALT + F3", hl.dsp.exec_cmd("chvt 3"))
hl.bind("CTRL + ALT + F4", hl.dsp.exec_cmd("chvt 4"))
hl.bind("CTRL + ALT + F5", hl.dsp.exec_cmd("chvt 5"))
hl.bind("CTRL + ALT + F6", hl.dsp.exec_cmd("chvt 6"))

-- Function keys
-- locked = works while screen locked, repeating = autorepeats on hold

    -- Media Keys (F1 -> F5)
    hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
    hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
    hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
    hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true })
    hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })

    -- Hardware keys (F6 -> F11)
    -- F6???
    -- F7???
    hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl set 16+"),                  { locked = true, repeating = true })
    hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -n1 set 16-"),                  { locked = true, repeating = true })
    -- F10???
    hl.bind("XF86Launch2", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/rotate-display")) -- Cycle display rotation (laptop bezel/rotate-lock key)
