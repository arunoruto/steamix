#!/usr/bin/env python3
"""Pin steam-arm to Valve's current ARM64 Steam client and runtime.

Reads Valve's ARM64 client manifest (the public beta channel Valve's ARM
devices use) for its version and the seed package, and the Steam Runtime's
public beta for the ARM64 runtime, and writes sources.json next to this
file. Both carry SHA-256 hashes Valve publishes, so nothing is downloaded
to hash it.

    ./update.py
"""

import json
import pathlib
import re
import urllib.request

CHANNEL = "steamdeck_publicbeta"
MANIFEST = f"https://client-update.steamstatic.com/steam_client_{CHANNEL}_linuxarm64"
RUNTIME = "https://repo.steampowered.com/steamrt3c/images"
RUNTIME_FILE = "steam-runtime-steamrt-arm64.tar.xz"
# The package with the client's own updater, which installs the rest.
SEED = "bins_linuxarm64_linuxarm64"


def get(url):
    with urllib.request.urlopen(url) as response:
        return response.read().decode()


def main():
    manifest = get(MANIFEST)
    version = re.search(r'"version"\s+"(\d+)"', manifest).group(1)
    blocks = dict(re.findall(r'"([a-z0-9_]+)"\s*\{([^{}]*)\}', manifest))
    seed = dict(re.findall(r'"([^"\n]+)"\s+"([^"\n]+)"', blocks[SEED]))

    runtime_version = get(f"{RUNTIME}/latest-public-beta/VERSION.txt").strip()
    sums = get(f"{RUNTIME}/{runtime_version}/SHA256SUMS")
    runtime_sha256 = re.search(rf"^([0-9a-f]{{64}}) \*{re.escape(RUNTIME_FILE)}$", sums, re.M).group(1)

    sources = {
        "client": {
            "version": version,
            "channel": CHANNEL,
            "seed": {"file": seed["file"], "sha256": seed["sha2"]},
        },
        "runtime": {"version": runtime_version, "sha256": runtime_sha256},
    }
    path = pathlib.Path(__file__).with_name("sources.json")
    path.write_text(json.dumps(sources, indent=2) + "\n")
    print(f"client {version}, runtime {runtime_version}")


if __name__ == "__main__":
    main()
