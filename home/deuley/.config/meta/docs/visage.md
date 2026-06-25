# Visage — face authentication (Windows-Hello-equivalent)

Face unlock for **sudo, pkexec/polkit, and the hyprlock lock screen** on nixian.
Built on [sovren-software/visage](https://github.com/sovren-software/visage)
(Rust PAM daemon, SCRFD face detection + ArcFace recognition via ONNX), with
local patches to support this laptop's IR camera and to build hermetically on
NixOS. Leads with the gotchas that cost the most time.

## TL;DR / daily use
- It just works: trigger sudo/pkexec or lock with hyprlock, **look at the camera**.
  Password is always the fallback (face auth can never lock you out).
- It only authenticates when you're **actually in front of the camera**. "It's
  flaky" almost always means the capture fired at an empty chair — not hardware.
- Enrolled models live per-user. Re-enroll: `sudo visage enroll` (see gotchas).

## Where everything lives
| Thing | Location |
|---|---|
| Build source (deployed) | `mocha/visage` fork, **pinned by rev+sha256** in `configuration.nix` (branch `nixos-hermetic-build`) — not the local checkout |
| Local dev checkout | `~/code/visage`. Branches: `feat/hp-omnibook-x-flip` = the upstream PR (pristine); `nixos-hermetic-build` = that PR + the hermetic-Nix-build commit (what we deploy); `feat/hp-omnibook-30c9-0120` = older local branch |
| NixOS module import | `configuration.nix` → `builtins.fetchTarball` of the pinned rev → `…/packaging/nix/module.nix` |
| Daemon | `visaged.service` (systemd, **runs as root**, system D-Bus) |
| ONNX models (~182 MB) | `/var/lib/visage/models/` (`det_10g.onnx`, `w600k_r50.onnx`) |
| Encrypted face DB | `/var/lib/visage/faces.db` |
| PAM wiring | `security.pam.services.{sudo,polkit-1,hyprlock}` in `configuration.nix` |

The config block also: pins `camera = "/dev/video2"`, sets
`liveness.minDisplacement = 0.3`, and re-adds `CAP_SYS_ADMIN` to the (otherwise
all-caps-stripped) hardened systemd unit — the emitter ioctl needs it.

## The camera + IR emitter (the hard-won part)
The IR camera is a **Luxvisions Innotech composite USB cam, VID:PID `30c9:0120`**:
- `/dev/video0,1` = RGB ("HP 5MP Camera"); `/dev/video2,3` = **IR** ("HP IR Camera",
  GREY 480×480, `uvcvideo` driver — *not* IPU6, so V4L2/UVC tools work).
- The IR **emitter** is off by default. It's enabled via a UVC extension-unit
  control (`UVCIOC_CTRL_QUERY`): **unit 14, selector 6, len 9**, GUID
  `0f3f95dc-2632-4c4e-92c9-a04782f43bc8` (the Windows-Hello IR-control unit).
  - **on** = `[1,3,3,0,0,0,0,0,0]` (the control's MAX)
  - **off** = `[1,3,1,0,0,0,0,0,0]` (default; an all-zero "off" is rejected ERANGE)

Two non-obvious behaviours this camera has (and how the patch handles them):
1. **The control resets the instant its fd closes, and only re-lights on a fresh
   open→set edge.** So `ir_emitter.rs` opens a fresh fd in `activate()`, holds it
   through the capture, and closes it in `deactivate()`. (A single fd held for the
   whole daemon life lights only the *first* capture, then stays "stuck on" and
   never re-fires — that's the "degrades over time" bug we chased.)
2. **`UVCIOC_CTRL_QUERY` needs CAP_SYS_ADMIN** — a device ACL is not enough. The
   daemon runs as root with `CAP_SYS_ADMIN` in its bounding+ambient sets.

## Local patches vs upstream (in `~/code/visage`)
- `contrib/hw/30c9-0120.toml` + `quirks.rs`: the quirk above; `quirks.rs` also
  gains an optional `off_bytes` field (all-zero off is rejected by this camera).
- `ir_emitter.rs`: the open-per-capture fd lifecycle (gotcha #1).
- `packaging/nix/default.nix` + `Cargo.toml`: build hermetically (committed on
  `nixos-hermetic-build`) — `rustPlatform.bindgenHook` (libclang for
  `v4l2-sys-mit`) and **ort `load-dynamic`** (the default binary download and
  `ORT_STRATEGY=system` both fail in the sandbox; ort rc.11 won't link nixpkgs
  onnxruntime 1.24.4). `visaged` is wrapped with `ORT_DYLIB_PATH`; the PAM cdylib
  is installed from `target/<triple>/release`. Note: `load-dynamic` +
  `default-features = false` **drops the openssl/native-tls download stack** from
  `Cargo.lock` (adds `libloading`), so no `openssl` build input is needed.
- `rate_limiter.rs` (local-only): MAX_FAILURES 5→10, lockout 300s→30s. **Not in
  the deployed build** — it lives only on `feat/hp-omnibook-30c9-0120`, so the
  current pinned build runs upstream's stricter 5 / 300s. Re-apply as a commit on
  `nixos-hermetic-build` if the strict default locks face auth too easily.

The hardware + hermetic-build changes are upstream-PR-worthy. To bump the pinned
build: commit to `nixos-hermetic-build`, push, then update the rev + sha256 in
`configuration.nix` (`nix-prefetch-url --unpack <github-archive-url>`).

## Operating procedures
```sh
visage discover                 # list cameras + quirk status (no daemon needed)
visage verify                   # test your face (any user; needs daemon)
visage status                   # daemon status (open to all)
sudo visage enroll --user $USER --label default   # enroll — SEE GOTCHA below
sudo visage list  --user $USER  # list enrolled models (root-only)
sudo visage remove <ID> --user $USER
journalctl -u visaged.service -f   # live logs (a verify logs similarity + liveness)
```

### Tuning (in `configuration.nix` `services.visage`)
- `liveness.minDisplacement` (default upstream 0.8 → we use **0.3**): anti-spoof
  via eye-landmark movement between frames. Genuine still-face scores ~0.5; a
  static photo ~0.0. 0.8 rejected real attempts; 0.3 keeps spoof protection.
- `similarityThreshold` (default 0.40): match cutoff. Our scores run ~0.5–0.97
  with the 3-model gallery; single-model matches were borderline.
- Multiple models = a **gallery**. We enrolled `default`/`alt1`/`alt2`; PAM matches
  against the best of all of them. Enroll a few poses for reliability.

## Gotchas (ranked by pain)
1. **Enroll as the right user.** Under `sudo`/`pkexec`, `$USER` is `root`, so
   `visage enroll` without `--user you` enrolls a model for **root** by mistake.
   Always `sudo visage enroll --user <you>`. Enroll/list/remove are root-only
   (D-Bus policy); verify/status are open to all.
2. **`nixos-rebuild` restarts polkit → de-registers soteria.** After any rebuild,
   pkexec/sudo password-*fallback* breaks until soteria is relaunched (it doesn't
   re-register itself). This matters more now: when face fails and falls through to
   password, a dead soteria makes pkexec *hang*. Relaunch it (kill the real proc —
   its comm is `.soteria-wrappe`, so `pkill -x soteria` MISSES it — then
   `setsid -f soteria`). See [`polkit.md`](polkit.md).
3. **Face auth adds a ~10 s capture attempt to every pkexec/sudo** before falling
   to password. When you pose, it's instant; when you don't, you wait then type a
   password.
4. **Camera pinned to `/dev/video2`.** If USB enumeration ever reorders the nodes,
   update `services.visage.camera` (a udev `by-id` symlink would make it robust).

## Rebuilding / updating
The system builds from the working tree at `~/code/visage` (whatever branch is
checked out — keep `feat/hp-omnibook-30c9-0120` checked out). To pull upstream
changes later, rebase the branch and `nixos-rebuild switch`. If the patches merge
upstream, switch the module's `src` to a pinned `fetchFromGitHub` and drop the
local checkout.
