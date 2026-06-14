{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
  source,
  upstream ? null,
}:
let
  packages = {
    darwin = stdenvNoCC.mkDerivation {
      pname = "brave";
      inherit (source) version;

      src = fetchurl {
        inherit (source.src.${stdenvNoCC.hostPlatform.system}) url hash;
      };

      nativeBuildInputs = [ _7zz ];

      # The dmg may contain a nested HFS+/APFS image; extract that too.
      unpackPhase = ''
        runHook preUnpack

        7zz x -y -snld "$src" >/dev/null
        inner=$(find . -maxdepth 1 \( -name '*.hfs' -o -name '*.apfs' \) -print -quit)
        if [ -n "$inner" ]; then
          7zz x -y -snld "$inner" >/dev/null
          rm "$inner"
        fi

        runHook postUnpack
      '';

      sourceRoot = ".";

      # Do not touch anything inside the .app bundle; it would break codesigning.
      dontPatchShebangs = true;

      installPhase = ''
        runHook preInstall

        app=$(find . -maxdepth 3 -name 'Brave Browser.app' -print -quit)
        [ -n "$app" ] || { echo "Brave Browser.app not found in dmg"; exit 1; }

        mkdir -p "$out/Applications"
        cp -R "$app" "$out/Applications/"

        mkdir -p "$out/bin"
        cat > "$out/bin/brave" <<EOF
        #!/bin/sh
        exec "$out/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" "\$@"
        EOF
        chmod +x "$out/bin/brave"

        runHook postInstall
      '';

      meta = {
        description = "Privacy-oriented browser for Desktop and Laptop computers";
        homepage = "https://brave.com";
        license = lib.licenses.mpl20;
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        platforms = [
          "aarch64-darwin"
          "x86_64-darwin"
        ];
        mainProgram = "brave";
      };
    };

    # On Linux, reuse the nixpkgs derivation (which wires up all the
    # runtime dependencies) and only bump version/src.
    linux = upstream.overrideAttrs (_: {
      inherit (source) version;
      src = fetchurl {
        inherit (source.src.${stdenvNoCC.hostPlatform.system}) url hash;
      };
    });
  };
in
if stdenvNoCC.hostPlatform.isDarwin then
  packages.darwin
else if stdenvNoCC.hostPlatform.isLinux then
  packages.linux
else
  throw "brave: unsupported platform ${stdenvNoCC.hostPlatform.system}"
