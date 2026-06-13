{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
  source,
}:

stdenvNoCC.mkDerivation {
  pname = "google-chrome";
  inherit (source) version;

  src = fetchurl {
    inherit (source.src) url hash;
  };

  nativeBuildInputs = [ _7zz ];

  # The src is a crx3 update package (zip with a header, 7zz handles it)
  # containing a dmg, which may itself contain a nested HFS+/APFS image.
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
}
