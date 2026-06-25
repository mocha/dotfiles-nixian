# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
    # Visage face authentication — built from our fork pinned to an exact rev
    # (mocha/visage @ nixos-hermetic-build) rather than a local checkout, so the
    # build is reproducible from first principles. That branch is the upstream
    # PR branch (feat/hp-omnibook-x-flip: HP OmniBook X Flip IR-camera support;
    # the reset_on_close quirk in contrib/hw/30c9-0120.toml drives this laptop's
    # Luxvisions camera) plus one commit adding the hermetic Nix build (ort
    # load-dynamic + ORT_DYLIB_PATH, rustPlatform.bindgenHook).
    # To bump: push the branch, then update rev + sha256 below
    # (`nix-prefetch-url --unpack <archive-url>`). See docs/visage.md.
    "${builtins.fetchTarball {
      url = "https://github.com/mocha/visage/archive/c9bd3e8770dd1a2c52bbb97bcef637b60b6fc04b.tar.gz";
      sha256 = "18qcfrz291hg2q5wwqxg45yibpprnxvb60254jkzj8fp5d754b58";
    }}/packaging/nix/module.nix"
  ];

  # --- Visage face authentication ---------------------------------------------
  services.visage = {
    enable = true;
    camera = "/dev/video2";   # HP IR Camera (Luxvisions 30c9:0120)
    pam.enable = false;       # PAM wired explicitly below for precise scope
    # Anti-spoof liveness: genuine still-face attempts on this camera score
    # ~0.5 eye-displacement; upstream's 0.8 default rejected them. 0.3 passes a
    # real (near-still) face while still rejecting a static photo (~0.0).
    liveness.minDisplacement = 0.3;
  };

  # The module's systemd hardening drops ALL capabilities, but the IR-emitter
  # UVC ioctl (UVCIOC_CTRL_QUERY) needs CAP_SYS_ADMIN. Add it back for visaged.
  systemd.services.visaged.serviceConfig = {
    CapabilityBoundingSet = lib.mkForce [ "CAP_SYS_ADMIN" ];
    AmbientCapabilities = [ "CAP_SYS_ADMIN" ];
  };

  # Face auth tried before password (password always falls through via
  # default=ignore — cannot lock out). Scoped to terminal sudo, pkexec/polkit
  # prompts, and the hyprlock lock screen. The ly boot greeter is intentionally
  # left password-only.
  security.pam.services =
    let visageRule = {
          order = 900;
          control = "[success=done default=ignore]";
          modulePath = "${config.services.visage.package}/lib/security/pam_visage.so";
        };
    in {
      sudo.rules.auth.visage       = visageRule;
      "polkit-1".rules.auth.visage = visageRule;
      hyprlock.rules.auth.visage   = visageRule;
    };
  # --- end Visage -------------------------------------------------------------

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Firefox/Chromium screen sharing via xdg-desktop-portal: programs.hyprland wraps
  # Hyprland with cap_sys_nice (for SCHED_RR), and NixOS's security.wrapper raises it
  # into the AMBIENT capability set, so every client Hyprland launches (firefox,
  # wayle, hyprshell, ...) inherits cap_sys_nice. A process holding a capability the
  # tracer lacks cannot be ptrace-read, so the capless xdg-desktop-portal can't open
  # the caller's /proc/PID/root to identify it and refuses ScreenCast with
  # "AccessDenied: Unable to open /proc/PID/root" (no source picker ever appears).
  # Dropping the cap makes clients introspectable again -> screen sharing works.
  # Cost: Hyprland can't self-assign SCHED_RR (it warns and runs at normal priority).
  security.wrappers.Hyprland.capabilities = lib.mkForce "";


  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;
  #boot.kernelPackages = pkgs.linuxPackages_testing;

  # Keep boot/console quiet so kernel warnings (e.g. the missing TAS2783
  # smart-amp firmware "Failed to read fw binary 8EA4-2-*.bin" lines) don't
  # paint over the ly login TUI. Messages still land in `journalctl -k`.
  # consoleLogLevel 3 hides KERN_ERR(3)/WARNING(4) from the console.
  boot.consoleLogLevel = 3;
  boot.kernelParams = [ "quiet" ];

  # Networking
  networking.hostName = "nixian";
  # networking.useNetworkd = true;
  # networking.useDHCP = false;
  # networking.wireless.iwd.enable = true; # Generic dbus wifi manager
  # networking.wireless.enable = true; # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true; # Wireless via networkmanager

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  # services.displayManager.sddm.enable = true;
  # services.desktopManager.plasma6.enable = true;

  programs.uwsm.enable = true;
  services.displayManager.ly.enable = true;

  services.hardware.bolt.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # upowerd — battery state for status bars (hyprpanel/astal-battery).
  services.upower.enable = true;

  # power-profiles-daemon — backs the balanced/performance/power-saver
  # switcher in hyprpanel's energy dropdown.
  services.power-profiles-daemon.enable = true;

  # fwupd — firmware updates via LVFS (HP is a well-supported vendor).
  # The module pulls in the daemon (fwupd.service), polkit rules, and LVFS
  # metadata config; the fwupdmgr client lands on PATH. Just adding the
  # package gives a client with no daemon -> "Failed to connect to daemon".
  services.fwupd.enable = true;

  # Daily firmware-update notifier. services.fwupd already gives us
  # fwupd-refresh.timer (keeps LVFS metadata fresh) but nothing tells us when an
  # update is actually published. This adds the missing piece: refresh, check,
  # and fire a desktop notification only when a device has a pending update.
  # Passive by design — it never flashes anything (firmware updates can need a
  # reboot / AC power and some are one-way; keep a human in the loop). Runs as a
  # user unit so notify-send reaches the running notification daemon (wayle).
  # It also drops a local mbox mail (see /var/mail spool below) so zsh's
  # "You have mail" reminds us in every new terminal until we read it.
  systemd.user.services.fwupd-update-check = {
    description = "Check for available firmware updates and notify";
    serviceConfig.Type = "oneshot";
    script = ''
      fwupdmgr=${config.services.fwupd.package}/bin/fwupdmgr
      jq=${pkgs.jq}/bin/jq
      notify=${pkgs.libnotify}/bin/notify-send
      date=${pkgs.coreutils}/bin/date
      flock=${pkgs.util-linux}/bin/flock
      mbox=/var/mail/deuley

      # Keep metadata fresh; tolerate being offline or already-up-to-date.
      "$fwupdmgr" refresh --no-unreported-check >/dev/null 2>&1 || true

      # get-updates exits 0 only when at least one device has a published update.
      if "$fwupdmgr" get-updates --no-unreported-check >/dev/null 2>&1; then
        json=$("$fwupdmgr" get-updates --json --no-unreported-check 2>/dev/null || true)
        names=$(printf '%s' "$json" | "$jq" -r \
          '[.Devices // [] | .[] | select(has("Releases")) | .Name] | join(", ")' 2>/dev/null)
        [ -n "$names" ] || names="see 'fwupdmgr get-updates'"

        # Desktop notification (wayle).
        "$notify" -u normal -a fwupd -i software-update-available \
          "Firmware updates available" \
          "$names
Run 'fwupdmgr update' to install."

        # Also drop a local mbox mail so the shell's "You have mail" reminds us
        # in every new terminal until we read it (mail/mailx clears it). Single
        # append under flock; body has no line starting with "From " so the mbox
        # stays valid.
        {
          "$flock" -x 9 2>/dev/null && {
            printf 'From fwupd@${config.networking.hostName} %s\n' "$("$date" '+%a %b %e %H:%M:%S %Y')"
            printf 'From: fwupd notifier <fwupd@${config.networking.hostName}>\n'
            printf 'To: deuley@${config.networking.hostName}\n'
            printf 'Subject: Firmware updates available (%s)\n' "$("$date" +%F)"
            printf 'Date: %s\n' "$("$date" -R)"
            printf '\n'
            printf 'fwupd found firmware updates pending on:\n    %s\n\n' "$names"
            printf 'Review:   fwupdmgr get-updates\n'
            printf 'Install:  fwupdmgr update   (may need a reboot / AC power)\n'
            printf '\n'
          } >&9
        } 9>>"$mbox"
      fi
    '';
  };

  systemd.user.timers.fwupd-update-check = {
    description = "Daily firmware-update check";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;          # catch up if the laptop was off/asleep at fire time
      RandomizedDelaySec = "1h";  # don't hit LVFS at exactly midnight
    };
  };

  # Local mail spool for the fwupd notifier's "You have mail" reminders.
  # Pre-create /var/mail and deuley's empty mbox so the user service can append
  # to it and zsh has a stable $MAIL to watch. Owned by deuley so the user-level
  # service can write without elevation.
  systemd.tmpfiles.rules = [
    "d /var/mail 0775 root root -"
    "f /var/mail/deuley 0600 deuley users -"
  ];

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Pull claude-code from sadjow/claude-code-nix instead of nixpkgs so we
  # track upstream releases within ~1h of publish (nixpkgs lags by weeks).
  # `main` is the always-latest branch — the repo's CI auto-bumps it
  # whenever Anthropic ships a new claude-code. Refetched on rebuild
  # once the tarball TTL (~1h) expires.
  nix.settings = {
    # Modern `nix` CLI + flake commands (nix shell/run/develop, flake-based
    # installs). Declared here — not in ~/.config/nix/nix.conf — so the
    # capability is reproducible and survives a from-scratch rebuild.
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [ "https://claude-code.cachix.org" ];
    trusted-public-keys = [
      "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
    ];
  };

  nixpkgs.overlays = [
    # sadjow/claude-code-nix is flake-only (no default.nix), so we can't
    # import its overlay directly without enabling flakes. Instead, call
    # its package.nix in our own overlay — same end result.
    (final: prev: {
      claude-code = prev.callPackage (
        builtins.fetchTarball {
          url = "https://github.com/sadjow/claude-code-nix/archive/refs/heads/main.tar.gz";
        }
        + "/package.nix"
      ) { };
    })

    # << WORKAROUND >>
    # Workaround for hyprgrass issues
    (final: prev: {
      # nixpkgs' wf-touch links tests against -ldoctest, but modern doctest
      # is header-only and ships no shared library. Disable the test build.
      wf-touch = prev.wf-touch.overrideAttrs (old: {
        mesonFlags = (old.mesonFlags or [ ]) ++ [ "-Dtests=disabled" ];
        doCheck = false;
      });

      # Pin hyprgrass to current main: the nixpkgs snapshot is from 2025-10-08
      # and predates upstream's hyprland 0.55.x compat fixes (landed 2026-06-11).
      hyprlandPlugins = prev.hyprlandPlugins // {
        hyprgrass = prev.hyprlandPlugins.hyprgrass.overrideAttrs (old: {
          version = "unstable-2026-06-11";
          src = prev.fetchFromGitHub {
            owner = "horriblename";
            repo = "hyprgrass";
            rev = "51b27422c65ee2636aa3b7664b41f9221295f708";
            hash = "sha256-xZYSKhlFtPTHyWTplInw1jPi3e7sIekAIS7JqvAag5I=";
          };
        });
      };
    })

    # HyprPanel notification icons: apps (Ghostty, and thus Claude Code's
    # notifications) send their icon as a freedesktop icon *name* in the
    # `image-path` hint, but HyprPanel's notification Image box only knows how
    # to load a real file path via CSS `url()`, so an icon-name renders as a
    # blank square. Make the Image box fall back to resolving the name through
    # GTK's themed-icon lookup (same as the header icon already does).
    (final: prev: {
      hyprpanel = prev.hyprpanel.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace src/components/notifications/Image/index.tsx \
            --replace-fail \
              'if (notification.appIcon && !isAnImage(notification.appIcon)) {' \
              'if ((notification.appIcon || notification.image) && !isAnImage(notification.appIcon || notification.image)) {' \
            --replace-fail \
              'icon={notification.appIcon}' \
              'icon={notification.appIcon || notification.image}'
        '';
      });
    })
  ];

  # Stage hyprland plugins at stable /etc paths so `hyprctl plugin load`
  # has predictable filenames across rebuilds. The plugin packages output
  # `<store>/lib/lib<name>.so` but nothing links it into a discoverable path.
  environment.etc."hypr/plugins/libhyprgrass.so".source =
    "${pkgs.hyprlandPlugins.hyprgrass}/lib/libhyprgrass.so";
  environment.etc."hypr/plugins/libhyprspace.so".source =
    "${pkgs.hyprlandPlugins.hyprspace}/lib/libhyprspace.so";

  # Rootless containers (whisper-npu server) run under podman.
  virtualisation.podman.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.deuley = {
    isNormalUser = true;
    description = "deuley";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    subUidRanges = [ { startUid = 100000; count = 65536; } ];
    subGidRanges = [ { startGid = 100000; count = 65536; } ];
    linger = true;
    packages = with pkgs; [
      kdePackages.dolphin # file manager
      kdePackages.kwalletmanager # GUI to view/delete KWallet secrets (e.g. stale smb guest creds)
      kdePackages.kwallet # kwalletd6 daemon + DBus activation (org.kde.kwalletd6) so the wallet can start on demand
      mtr 		          # modern tracert
      eza 		          # modern ls
      nfs-utils
      nix-search
      gparted

      # general
      spotify
      slack             # slack
      signal-desktop    # signal
      halloy            # irc
      playerctl 	      # MPRIS control for XF86Audio{Next,Prev,Play,Pause}
      loupe 		        # image viewer
      vlc               # videolan

      claude-code 	# sandbrain
      zed-editor 	# zeditor
      ghostty 		# terminal emulator
      nil 		# nix lsp
      jq 		# json renderer
      glow 		# markdown renderer
      crush 		# ai harness
      _1password-cli
      obsidian

      iio-sensor-proxy

      moonlight-qt

      # hyprland - general
      hyprshell 	# launcher
      wayle 		# statusbar/shell (bar+notifications+osd); migrated to this from hyprpanel
      ashell 		# statusbar (older fallback)
      hyprpanel 	# statusbar (deprecated upstream; kept as rollback during wayle migration)
      hyprsysteminfo 	# sysinfo
      awww 		# wallpaper daemon -- wayle renders backgrounds by shelling out to swww/awww; previously only on PATH via hyprpanel's deps
      # fwupd client lands on PATH via services.fwupd.enable (see below); don't list the package directly or you get a client with no daemon
      mailutils         # `mail` reader for the local fwupd-notifier spool (/var/mail/deuley)

      # hyprland - tabletmode
      hyprlandPlugins.hyprgrass # touch utils
      glm # [hyprgrass dep]
      hyprlandPlugins.hyprspace # overview
      squeekboard # virtual keyboard

      # hyprland - system
      hyprshutdown # graceful shutdowns
      soteria # polkit auth agent (GTK4) — replaced hyprpolkitagent so the dialog inherits the same GTK/Catppuccin/Monoflow look as wayle + hyprshell
      hyprtoolkit # theme utilities
      hyprland-qt-support
      hyprgraphics

      brightnessctl # util for brightness control
      upower # power mgmt
      wifitui # wifi manager

      # screenshots
      grim # wayland screenshot grabber
      slurp # region selector (pipe into grim -g)
      wl-clipboard # wl-copy/wl-paste for clipboard capture

      # screen sharing: pipewire/wireplumber come from services.pipewire and
      # xdg-desktop-portal-hyprland from programs.hyprland -- no extra pkgs needed.

    ];

    shell = pkgs.zsh;

  };

  # Install programs.
  programs.hyprland.enable = true; # hyprrr
  programs.hyprland.withUWSM = true;
  # launch via uwsm so graphical-session.target
  # activates (else hyprpolkitagent et al. never
  # autostart). Pick the "Hyprland (UWSM)" session
  # at login; ly remembers it.
  programs.iio-hyprland.enable = true; # auto-rotate output
  programs.hyprlock.enable = true; # lockscreen

  # Polkit auth agent — surfaces auth prompts as a GUI dialog so pkexec
  # (and any other polkit client) works outside of a TTY.
  #   soteria is a GTK4 agent, so its dialog follows the GTK theme + default
  #   font (Catppuccin + Monoflow) exactly like wayle/hyprshell — no Qt theming
  #   gymnastics. Replaced hyprpolkitagent (QtQuick, layout baked into its QML,
  #   no padding control), which is why the qt6ct/qqc2 scoping below is gone.
  #   NOTE: soteria reads XDG_SESSION_ID from its environment, which the systemd
  #   --user manager does NOT carry (only the login session does). So it's
  #   launched from hyprland.lua (exec, full session env) like wayle — a systemd
  #   user service crash-loops with "Could not get XDG session id".

  # Qt theming → Catppuccin Mocha.
  #   platformTheme "kde" pulls plasma-integration — the KDE QPA bridge that maps
  #   the kdeglobals color scheme onto the Qt palette (incl. light view text).
  #   This is the piece qt6ct never did for KDE apps (Dolphin rendered dark-on-dark).
  #   style "kvantum" renders widgets; with plasma-integration supplying the palette,
  #   text/bg should both be Catppuccin. (kdePackages.breeze is installed too so the
  #   style can be A/B'd live via QT_STYLE_OVERRIDE if Kvantum still mis-renders.)
  qt = {
    enable = true;
    platformTheme = "kde";
    style = "kvantum";
  };


  systemd.user.services.whisper-npu = {
    description = "Whisper NPU server (rootless podman, model kept warm)";
    wantedBy = [ "default.target" ];
    after = [ "default.target" ];
    unitConfig.ConditionUser = "deuley";
    # Rootless podman execs `newuidmap`/`newgidmap` by name to set up the uid/gid map, and
    # those are setuid wrappers that live only in /run/wrappers/bin — which is in the user's
    # login PATH but NOT in a systemd --user unit's minimal PATH. Without this the container
    # fails with "newuidmap: executable file not found in $PATH" (exit 125). crun/conmon/pasta
    # are resolved via containers.conf, so the uid-map helpers are the only PATH dependency.
    path = [ "/run/wrappers" ];
    serviceConfig = {
      ExecStartPre = "-${pkgs.podman}/bin/podman rm -f whisper-server";
      ExecStart = ''
        ${pkgs.podman}/bin/podman run --rm --replace --name whisper-server \
          -v %h/.whisper/models:/root/.whisper/models \
          -p 127.0.0.1:8009:5000 \
          --security-opt seccomp=unconfined --ipc=host --group-add keep-groups \
          --device=/dev/dri --device=/dev/accel/accel0 \
          localhost/whisper-npu-ptl:local
      '';
      ExecStop = "${pkgs.podman}/bin/podman stop -t 10 whisper-server";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  programs.firefox.enable = true;
  programs.steam.enable = true;
  programs.git.enable = true;
  programs.htop.enable = true;
  programs.tmux.enable = true;
  programs._1password.enable = true;
  programs._1password-gui.enable = true;
  programs.zsh = {
    enable = true;
    # Watch the local mail spool so the fwupd notifier's mbox drops surface as
    # "You have new mail" on each new interactive shell (MAILCHECK already 60).
    interactiveShellInit = ''
      export MAIL="/var/mail/$USER"
    '';
    autosuggestions.enable = true;
    autosuggestions.highlightStyle = "fg=8";
    enableCompletion = true;
    enableBashCompletion = true;
    histSize = 2000;
    ohMyZsh = {
      enable = true;
      theme = "af-magic";
      plugins = [
        "git"
        "z"
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    kitty
    iwd
    wtype
    cliphist
    fuzzel
    rofimoji # emoji/unicode picker; drives fuzzel + wtype (Super+. keybind)
    qalculate-qt # scientific calculator GUI (themes via Kvantum/Qt stack)
    (callPackage ./pkgs/dictation { })
    (callPackage ./pkgs/hyprsaver { }) # Wayland screensaver, driven by hypridle (see ./pkgs/hyprsaver)
    adwaita-icon-theme # freedesktop symbolic icons (hyprpanel etc.)
    hicolor-icon-theme # base theme everything else inherits from

    # Catppuccin Mocha theming (Qt + GTK)
    (catppuccin-kvantum.override {
      accent = "mauve";
      variant = "mocha";
    }) # Kvantum theme for Qt-Widgets
    # (qt6ct / qqc2-desktop-style / catppuccin-qt5ct removed — they existed only to
    #  theme the QtQuick hyprpolkitagent dialog, now replaced by GTK soteria.)
    (catppuccin-gtk.override {
      accents = [ "mauve" ];
      variant = "mocha";
    }) # GTK3/4 theme (catppuccin-mocha-mauve-standard)
    kdePackages.breeze # KDE-native Qt style — full KColorScheme support; A/B alternative to Kvantum for Dolphin
  ];

  fonts.packages = with pkgs; [
    font-awesome
    nerd-fonts.fira-code
    nerd-fonts.droid-sans-mono
    # Monoflow — personally licensed; OTFs live in ./fonts/monoflow
    (runCommandLocal "monoflow" { } ''
      install -Dm644 ${./fonts/monoflow}/*.otf -t $out/share/fonts/opentype
    '')
  ];

  # Make Monoflow the OS-wide default for every generic family. Without this,
  # `monospace` resolved to DejaVu Sans Mono and `sans-serif` to a system
  # fallback — so apps that don't name a font explicitly (most of them) never
  # picked up Monoflow. DejaVu stays as the fallback for glyphs Monoflow lacks.
  fonts.fontconfig.defaultFonts = {
    monospace = [ "Monoflow" "DejaVu Sans Mono" ];
    sansSerif = [ "Monoflow" "DejaVu Sans" ];
    serif     = [ "Monoflow" "DejaVu Serif" ];
  };

  # Bluetooth
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        Experimental = true;
      };
    };
  };

  # Tilt sensor
  hardware.sensor.iio.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  services.hypridle.enable = true; # idle daemon

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.11"; # Did you read the comment?

}
