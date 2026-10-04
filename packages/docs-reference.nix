# Generated Steamix documentation: the option reference, built from the
# option descriptions in modules/nixos, so it cannot drift from the module
# the way a hand-written page does.
#
# Steamix writes to far too much of NixOS (display managers, PAM, polkit,
# systemd, sysctl, ...) to evaluate against a shim declaring just those
# options, so the module system's unmatched-definition check is switched off
# instead. Only `options.steamix` is rendered, and the config side is never
# forced, so nothing outside the option declarations has to resolve.
{
  lib,
  pkgs,
  runCommand,
  nixosOptionsDoc,
}:
let
  repoRoot = toString ./.. + "/";
  repoUrl = "https://github.com/arunoruto/steamix/blob/main";

  evaluated = lib.evalModules {
    modules = [
      ../modules/nixos
      { _module.check = false; }
    ];
    specialArgs = { inherit pkgs; };
  };

  # Link each option back to the file that declares it.
  transformOptions =
    option:
    option
    // {
      declarations = map (
        declaration:
        let
          # Modules imported as a directory declare their options against the
          # directory; point at the file that actually holds them.
          path =
            if builtins.pathExists (declaration + "/default.nix") then
              "${toString declaration}/default.nix"
            else
              toString declaration;
          subPath = lib.removePrefix repoRoot path;
        in
        {
          name = subPath;
          url = "${repoUrl}/${subPath}";
        }
      ) option.declarations;
    };

  body =
    (nixosOptionsDoc {
      options.steamix = evaluated.options.steamix;
      inherit transformOptions;
    }).optionsCommonMark;

  page = runCommand "steamix-options.md" { } ''
    {
      printf '%s\n\n' '# Option reference'
      printf '%s\n\n' ${lib.escapeShellArg ''
        Every `steamix.*` option, generated from the declarations in
        `steamix/modules/nixos`. The [Options](../options.md) page is the curated
        tour — what to reach for and why; this page is the complete,
        cannot-drift listing.
      ''}
      cat ${body}
    } > $out
  '';
in
runCommand "steamix-reference" { } ''
  mkdir -p $out
  cp ${page} $out/options.md
''
