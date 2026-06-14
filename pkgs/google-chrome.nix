{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
  source,
  upstream ? null,
}:
let
  # source is sources.google-chrome; pick the right platform entry
  platformSource =
    if stdenvNoCC.hostPlatform.isDarwin then source.darwin
    else if stdenvNoCC.hostPlatform.isLinux then source.linux
    else throw "google-chrome: unsupported platform ${stdenvNoCC.hostPlatform.system}";
  packages = {
    # The src is a crx3 update package (zip with a header, 7zz handles it)
    # containing a dmg, which may itself contain a nested HFS+/APFS image.
    darwin = stdenvNoCC.mkDerivation {
      pname = "google-chrome";
      inherit (platformSource) version;

      src = fetchurl {
        inherit (platformSource.src) url hash;
      };

      nativeBuildInputs = [ _7zz ];

      unpackPhase = ''
        runHook preUnpack

        7zz x -y -snld "$src" >/dev/null
        while inner=$(find . -maxdepth 1 \( -name '*.dmg' -o -name '*.hfs' -o -name '*.apfs' \) -print -quit); [ -n "$inner" ]; do
          7zz x -y -snld "$inner" >/dev/null
          rm "$inner"
        done

        runHook postUnpack
      '';

      sourceRoot = ".";

      # Do not touch anything inside the .app bundle; it would break codesigning.
      dontPatchShebangs = true;

      installPhase = ''
        runHook preInstall

        app=$(find . -maxdepth 3 -name 'Google Chrome.app' -print -quit)
        [ -n "$app" ] || { echo "Google Chrome.app not found in dmg"; exit 1; }

        mkdir -p "$out/Applications"
        cp -R "$app" "$out/Applications/"

        mkdir -p "$out/bin"
        cat > "$out/bin/google-chrome" <<EOF
        #!/bin/sh
        exec "$out/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "\$@"
        EOF
        chmod +x "$out/bin/google-chrome"

        runHook postInstall
      '';

      meta = {
        description = "Freeware web browser developed by Google";
        homepage = "https://www.google.com/chrome/";
        license = lib.licenses.unfree;
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        platforms = [
          "aarch64-darwin"
          "x86_64-darwin"
        ];
        mainProgram = "google-chrome";
      };
    };

    # On Linux, reuse the nixpkgs derivation (which wires up all the
    # runtime dependencies) and only bump version/src.
    linux = upstream.overrideAttrs (_: {
      inherit (platformSource) version;
      src = fetchurl {
        inherit (platformSource.src) url hash;
      };
    });
  };
in
if stdenvNoCC.hostPlatform.isDarwin then
  packages.darwin
else if stdenvNoCC.hostPlatform.isLinux then
  packages.linux
else
  throw "google-chrome: unsupported platform ${stdenvNoCC.hostPlatform.system}"
