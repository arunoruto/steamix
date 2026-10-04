# Steamix

Steamix turns a NixOS machine into a Steam machine: it boots
straight into Steam's **Gaming Mode** (the gamescope-driven Deck UI), and the
"Switch to Desktop" button in Steam's power menu drops you into a regular
desktop session — with an icon there to return to Gaming Mode, just like
SteamOS.

It is deliberately *not* [Jovian-NixOS](https://github.com/Jovian-Experiments/Jovian-NixOS).
Jovian ships Valve's full stack (powerbuttond, the vendor gamescope-session,
Deck hardware support) and is the right choice for an actual Steam Deck.
Steamix instead builds the parts a PC needs: a gamescope session modelled on
Valve's, a session switcher, and a login loop on greetd or SDDM. It is aimed
at ordinary PCs used as living-room machines, and leans on upstream nixpkgs'
gamescope and Steam rather than Valve's patched builds.

## Design

Steamix is mechanism only:

- the module touches plain `pkgs`, plain `lib` and upstream NixOS options,
  so it evaluates against a bare nixpkgs;
- all policy (which host, which user, which desktop session) stays with the
  consumer's configuration;
- the packages nixpkgs does not have (SteamOS Manager, Decky Loader and the
  `deckyPlugins` scope) come from the flake's `overlays.default`, and the
  module's package options find them there.

## Usage

Add the flake and import the module and its overlay:

```nix
{
  inputs.steamix = {
    url = "github:arunoruto/steamix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # in a NixOS configuration:
  imports = [ inputs.steamix.nixosModules.default ];

  config = {
    nixpkgs.overlays = [ inputs.steamix.overlays.default ];

    steamix = {
      enable = true;
      user = "alice";
      desktopSession = "plasma";
    };
    # the desktop session itself still comes from your own config:
    services.desktopManager.plasma6.enable = true;
  };
}
```

Requirements and expectations:

- A GPU with working Vulkan (gamescope requires it). AMD is the best-tested
  family for gamescope — it is what SteamOS runs on.
- The desktop session must be a **Wayland** session; X11 sessions are out of
  scope.
- `steamix.autoStart` (the default) logs `steamix.user` in **without a
  password prompt**, console-style — treat the machine like a game console,
  not a multi-user workstation. Screen lockers of the desktop session still
  work once switched.
- Steam itself is unfree; `nixpkgs.config.allowUnfree` (or an equivalent
  predicate) must permit it.

HDR, VRR and the performance overlay are on by default and need no
configuration — see [Options](./options.md#display-features). Resolution,
refresh rate and anything else gamescope takes go through
`steamix.gamescope.args` (one list element per argv entry):

```nix
steamix.gamescope.args = [
  "--output-width"
  "3840"
  "--output-height"
  "2160"
];
```

See [How it works](./how-it-works.md) for the mechanism and its failure
modes, [Options](./options.md) for the reference, and
[Hardware setup & tuning](./hardware-and-tuning.md) for the checklist that
makes the machine actually good — nixos-facter, nixos-hardware, gamescope
display tuning, controllers. [Roadmap](./roadmap.md) is where the project is
headed and why.
