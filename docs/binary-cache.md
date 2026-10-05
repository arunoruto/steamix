# Binary cache

Steamix has its own binary cache at
[steamix.cachix.org](https://steamix.cachix.org), so a Steamix machine
downloads what it would otherwise compile:

| Package | Why it is not on cache.nixos.org |
|---------|----------------------------------|
| SteamOS Manager | not in nixpkgs |
| Decky Loader | not in nixpkgs |
| 32-bit gamescope WSI layer | in nixpkgs, but Hydra does not build it; the module installs it by default (`steamix.gamescope.wsi.package32`) |
| `linux-armada` (aarch64) | the [handheld](./handhelds.md) kernel, not in nixpkgs; built natively on GitHub's ARM runners, so an x86_64 machine building a handheld image does not compile it under emulation. It is GPL-2.0, so its corresponding source is served with it: Armada's kernel directory (the patches, device trees and config) from this cache, Linux's tarball from cache.nixos.org, which already has it, and the build recipe is this repository. |

The Decky plugins are not cached: they are release downloads, so a cache
would save nothing. Nor is anything that may not be redistributed: the handheld
firmware (`armada-firmware`) has no licence at all, which is also why the
kernel's source in the cache is Armada's kernel directory rather than the
whole repository, and the Decky LSFG-VK plugin carries lsfg-vk under
CC BY-NC-ND. The handheld SD images contain the firmware, so they are
never cached either: build them yourself.

## Using it

Machines that import the module get it from `steamix.binaryCache.enable`,
which is on by default and adds the cache and its key to `nix.settings`,
next to `cache.nixos.org`:

```nix
steamix.binaryCache.enable = true; # the default
```

It asks for no trust beyond what importing the module already does: the
module runs as root, and the cache is signed with a key pinned in it. Set it
to `false` to build everything yourself.

Building Steamix's flake directly (`nix build`, the VM tests) uses the same
cache through the flake's `nixConfig`, if `accept-flake-config` is on. Nix
ignores that setting when Steamix is a flake input, which is why the module
option exists. The URL and key, if you want to add them by hand:

```text
https://steamix.cachix.org
steamix.cachix.org-1:RDiQCw/nTZL8BuFm4uZrKEnkCU0xJ+w7zwQ+IQBXan0=
```

## When it helps

A cache only serves the exact store path a machine asks for, and that path
depends on the whole nixpkgs it was built against. CI builds the cached set
against three nixpkgs revisions:

| Name | Revision |
|------|----------|
| `locked` | `nixos-unstable` at the revision Steamix's `flake.lock` pins |
| `unstable` | the current `nixos-unstable` channel head |
| `stable` | the current `nixos-26.05` channel head |

It rebuilds them daily, so a machine whose own lock follows either channel
and was bumped recently asks for paths that are already there. A machine on
an older revision builds locally, exactly as it would without the cache.

## How it is filled

The Cache workflow runs on `main` after CI passes, and daily. For each
revision it builds the flake's `cache` set, pushes those outputs and their
runtime closures (Cachix skips anything `cache.nixos.org` has, so in practice
one path per package), and pins each as `<package>-<revision>`, keeping
three revisions, so the free tier's garbage collection never evicts what
machines are using. Build-only paths, such as fetched sources and Decky's
pnpm dependencies, are never pushed.

It pushes with an auth token stored as the repository secret
`STEAMIX_CACHIX_AUTH_TOKEN`. Without the secret the job still builds, and
skips the push with a notice.

To see what would be pushed:

```sh
nix eval .#cache --apply builtins.attrNames
```
