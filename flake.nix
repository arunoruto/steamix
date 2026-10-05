# Steamix — boot a NixOS machine straight into Steam's Gaming Mode, with a
# switchable Desktop Mode. See docs/ or https://arunoruto.github.io/steamix/.
#
# Consumers usually set `inputs.steamix.inputs.nixpkgs.follows = "nixpkgs"`,
# so the lock file here pins only what this repository builds itself: the
# VM tests, the cached packages and the docs.
{
  description = "Steamix — a SteamOS-like Gaming Mode for NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  # Steamix's binary cache, for anything built from this flake directly
  # (`nix build`, the VM tests). Nix ignores a flake's nixConfig when the flake
  # is an input, so machines importing the module get the same cache from
  # the `steamix.binaryCache.enable` option instead. The URL and key are
  # repeated in modules/nixos/default.nix; keep them in step.
  nixConfig = {
    extra-substituters = [ "https://steamix.cachix.org" ];
    extra-trusted-public-keys = [
      "steamix.cachix.org-1:RDiQCw/nTZL8BuFm4uZrKEnkCU0xJ+w7zwQ+IQBXan0="
    ];
  };

  outputs =
    { self, nixpkgs }:
    let
      # The session stack is x86_64 in practice (Steam), but nothing here is
      # arch-specific enough to hard-fail an aarch64 evaluation.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      eachSystem = nixpkgs.lib.genAttrs systems;
    in
    {
      # Steamix itself, and handheld hardware support (hardware/): one
      # module per device, `<vendor>-<model>`, plus the shared pieces.
      nixosModules = {
        default = ./modules/nixos;
        steamix = ./modules/nixos;
      }
      // import ./hardware { inherit (nixpkgs) lib; };

      # Bring-up images for the handhelds: a console system to flash to an SD
      # card and boot through ROCKNIX ABL. Build with
      # `nix build .#packages.aarch64-linux.sd-image-<device>`.
      nixosConfigurations.retroid-pocket-6 = nixpkgs.lib.nixosSystem {
        modules = [
          self.nixosModules.retroid-pocket-6
          self.nixosModules.rocknix-abl-sd-image
          ./hardware/common/bring-up.nix
        ];
      };

      # Adds steamos-manager, decky-loader and the deckyPlugins scope to pkgs —
      # which is also how the module's package options find their defaults
      # (`pkgs.steamos-manager or null`, `pkgs.decky-loader or null`).
      overlays.default = final: _prev: import ./packages { pkgs = final; };

      packages = eachSystem (
        system:
        let
          steamixPackages = import ./packages { pkgs = nixpkgs.legacyPackages.${system}; };
        in
        {
          inherit (steamixPackages) steamos-manager decky-loader rocknix-abl;
          # decky-lsfg-vk is unfree, which `nix flake check` refuses in
          # `packages`; it is in legacyPackages.<system>.deckyPlugins.
          inherit (steamixPackages.deckyPlugins) hltb-for-deck protondb-decky;
          docs-reference = nixpkgs.legacyPackages.${system}.callPackage ./packages/docs-reference.nix { };
          # The documentation site, as published to GitHub Pages.
          docs = nixpkgs.legacyPackages.${system}.callPackage ./packages/docs.nix {
            docs-reference = self.packages.${system}.docs-reference;
          };
        }
        # The handheld kernel and bring-up images, built natively.
        # (armada-firmware is left out: it is unfree, and comes with the
        # hardware modules.)
        // nixpkgs.lib.optionalAttrs (system == "aarch64-linux") {
          linux-armada = steamixPackages.linux_armada;
          sd-image-retroid-pocket-6 = self.nixosConfigurations.retroid-pocket-6.config.system.build.sdImage;
        }
        # The same image for x86_64 machines, with the kernel cross-compiled
        # (an hour, instead of many under emulation). The rest is still
        # aarch64: from cache.nixos.org, or built under binfmt emulation.
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          sd-image-retroid-pocket-6 =
            (self.nixosConfigurations.retroid-pocket-6.extendModules {
              modules = [
                (
                  { pkgs, ... }:
                  {
                    boot.kernelPackages =
                      pkgs.linuxPackagesFor
                        (import ./packages { pkgs = nixpkgs.legacyPackages.x86_64-linux.pkgsCross.aarch64-multiplatform; })
                        .linux_armada;
                  }
                )
              ];
            }).config.system.build.sdImage;
        }
      );

      formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);

      # VM tests (see tests/default.nix), x86_64-linux: Gaming Mode is
      # Steam, and Steam is x86_64 (for now).
      checks.x86_64-linux = import ./tests { pkgs = nixpkgs.legacyPackages.x86_64-linux; } // {
        # The bring-up image (kernel cross-compiled) booted in QEMU.
        boot-retroid-pocket-6 = import ./tests/boot-handheld.nix {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          image = self.packages.x86_64-linux.sd-image-retroid-pocket-6;
          name = "retroid-pocket-6";
        };
      };

      # The bring-up image, built natively, booted in QEMU. Run by CI on an
      # ARM runner.
      checks.aarch64-linux.boot-retroid-pocket-6 = import ./tests/boot-handheld.nix {
        pkgs = nixpkgs.legacyPackages.aarch64-linux;
        image = self.packages.aarch64-linux.sd-image-retroid-pocket-6;
        name = "retroid-pocket-6";
      };

      # What CI pushes to steamix.cachix.org: what a Steamix machine would
      # otherwise compile itself, because cache.nixos.org does not have it.
      # The two daemons nixpkgs does not package, and the 32-bit gamescope
      # WSI layer, which the module installs by default (`wsi.package32`) and
      # Hydra does not build. The Decky plugins are left out: they are
      # release downloads, so caching them saves nothing.
      #
      # A cache only helps a machine that asks for the exact store path, so
      # CI builds this against the nixpkgs revisions it is pinned to; see
      # docs/binary-cache.md.
      legacyPackages = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          steamixPackages = import ./packages { inherit pkgs; };
        in
        {
          # Every Decky plugin, unfree ones included:
          # `NIXPKGS_ALLOW_UNFREE=1 nix build --impure .#deckyPlugins.decky-lsfg-vk`
          inherit (steamixPackages) deckyPlugins;
        }
        // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
          cache = {
            inherit (steamixPackages) steamos-manager decky-loader;
            gamescope-wsi-32 = pkgs.pkgsi686Linux.gamescope-wsi;
          };
        }
        # Valve's native ARM64 Steam client: unfree, so not in `packages`.
        // nixpkgs.lib.optionalAttrs (system == "aarch64-linux") {
          inherit (steamixPackages) steam-arm;
        }
        # The handheld kernel: hours under emulation, so the one thing an
        # x86_64 machine building a handheld image should not build itself.
        # It is GPL-2.0, so its source goes into the cache with it (Linux's
        # tarball and Armada's kernel directory). Its firmware has no
        # licence and stays out.
        // nixpkgs.lib.optionalAttrs (system == "aarch64-linux") {
          cache = {
            linux-armada = steamixPackages.linux_armada;
            linux-armada-source-linux = steamixPackages.linux_armada.sources.linux;
            linux-armada-source-armada = steamixPackages.linux_armada.sources.armada;
          };
        }
      );

      # Room to grow, reserved rather than stubbed: Gaming Mode is a system
      # concern, but per-user pieces (Decky plugin settings, per-game
      # environment) would land here as homeModules.default.
    };
}
