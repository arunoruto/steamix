# The documentation site: the pages in docs/ plus the option reference
# generated from the module, rendered with mdBook.
{
  lib,
  stdenvNoCC,
  mdbook,
  docs-reference,
}:
stdenvNoCC.mkDerivation {
  pname = "steamix-docs";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./..;
    fileset = lib.fileset.unions [
      ../book.toml
      ../docs
    ];
  };

  __structuredAttrs = true;
  strictDeps = true;

  nativeBuildInputs = [ mdbook ];

  buildPhase = ''
    runHook preBuild

    # Generated from the option declarations, so not part of the source tree
    # (see .gitignore).
    mkdir -p docs/reference
    cp ${docs-reference}/*.md docs/reference/

    mdbook build --dest-dir "$out"

    runHook postBuild
  '';

  dontInstall = true;

  meta = {
    description = "Steamix documentation";
    homepage = "https://arunoruto.github.io/steamix/";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
