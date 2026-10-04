# Decky LSFG-VK: Lossless Scaling frame generation managed from Gaming Mode's
# Quick Access menu, with per-game profiles.
#
# The plugin ships its own lsfg-vk build, which its "Install lsfg-vk" button
# unpacks into the user's home, and it validates every settings change by
# running that build's lsfg-vk-cli. Those binaries are made for ordinary
# distributions and do not start on NixOS, so two things are repaired here:
#
#   - the backend runs a copy of lsfg-vk-cli patched for NixOS, referenced
#     from this package, so it always exists and never goes stale;
#   - the archive's UI becomes a launcher for the bundled Qt 6 UI patched
#     against nixpkgs' Qt and wrapped with its plugin paths.
#
# The layers themselves stay exactly as upstream built them: they are loaded
# into games, under Steam's runtime, as on any other distribution.
{
  lib,
  stdenv,
  buildDeckyPlugin,
  autoPatchelfHook,
  qt6,
  libGL,
}:
let
  upstream = buildDeckyPlugin {
    pname = "decky-lsfg-vk";
    version = "0.14.4";
    owner = "xXJSONDeruloXx";
    asset = "Decky.LSFG-VK.zip";
    hash = "sha256-IS/5+1tiSGYwIXtlcZ0aq5gNjC3HNUQ4pfU5vOJXadQ=";
  };

  archiveName = "lsfg-vk-2.0.0.tar.xz";

  # The bundled lsfg-vk, with its two programs patched to run on NixOS.
  payload = stdenv.mkDerivation {
    pname = "decky-lsfg-vk-payload";
    inherit (upstream) version;

    src = "${upstream}/decky-lsfg-vk/bin/${archiveName}";
    dontUnpack = true;

    __structuredAttrs = true;
    strictDeps = true;

    nativeBuildInputs = [
      autoPatchelfHook
      qt6.wrapQtAppsHook
    ];
    buildInputs = [
      (lib.getLib stdenv.cc.cc)
      qt6.qtbase
      qt6.qtdeclarative
      libGL
    ];

    # Only the two programs are patched, by hand below; the layers must stay
    # untouched for the games that load them.
    dontAutoPatchelf = true;
    dontWrapQtApps = true;
    dontPatchELF = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      tar -xJf "$src" -C "$out"
      runHook postInstall
    '';

    postFixup = ''
      autoPatchelf "$out/bin"
      wrapQtApp "$out/bin/lsfg-vk-ui"
    '';
  };
in
upstream.overrideAttrs (old: {
  postInstall = (old.postInstall or "") + ''
    dir="$out/decky-lsfg-vk"

    # The archive the plugin installs from, rebuilt from the payload. Left
    # uncompressed so Nix sees the store paths inside it and keeps them; the
    # installer opens it with tarfile's "r:*", whatever the extension says.
    work=$(mktemp -d)
    cp -r ${payload}/. "$work/"
    chmod -R u+w "$work"
    tar --format=gnu -C "$work" -cf "$dir/bin/${archiveName}" \
      ./bin/lsfg-vk-cli ./bin/lsfg-vk-ui \
      ./lib/liblsfg-vk-layer.so ./lib/liblsfg-vk-layer.x86.so \
      ./share/vulkan/implicit_layer.d/VkLayer_LSFGVK_frame_generation.json \
      ./share/vulkan/implicit_layer.d/VkLayer_LSFGVK_frame_generation.x86.json \
      ./share/applications/gay.pancake.lsfg-vk-ui.desktop \
      ./share/icons/hicolor/256x256/apps/gay.pancake.lsfg-vk-ui.png

    substituteInPlace "$dir/py_modules/lsfg_vk/runtime_service.py" \
      --replace-fail \
        'self.cli_path = self.local_bin_dir / CLI_FILENAME' \
        'self.cli_path = Path("${payload}/bin/lsfg-vk-cli")'
  '';

  passthru = old.passthru // {
    inherit payload;
  };

  meta = old.meta // {
    description = "Decky plugin for Lossless Scaling frame generation through lsfg-vk";
    homepage = "https://github.com/xXJSONDeruloXx/decky-lsfg-vk";
    # The plugin is BSD-3-Clause; the lsfg-vk build it carries is
    # CC BY-NC-ND 4.0, which is neither free nor redistributable.
    license = with lib.licenses; [
      bsd3
      cc-by-nc-nd-40
    ];
    platforms = [ "x86_64-linux" ];
  };
})
