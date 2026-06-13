{
  description = "Nix overlay providing up-to-date browsers (Brave, Google Chrome) for macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems =
        f:
        lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              config.allowUnfree = true; # for google-chrome
              overlays = [ self.overlays.default ];
            }
          )
        );
      sources = builtins.fromJSON (builtins.readFile ./sources.json);
    in
    {
      overlays.default =
        final: prev:
        if prev.stdenv.hostPlatform.isDarwin then
          {
            brave = final.callPackage ./pkgs/brave.nix { source = sources.brave; };
            google-chrome = final.callPackage ./pkgs/google-chrome.nix {
              source = sources.google-chrome.darwin;
            };
          }
        else
          {
            # On Linux, reuse the nixpkgs derivations (which wire up all the
            # runtime dependencies) and only bump version/src.
            brave = prev.brave.overrideAttrs (old: {
              inherit (sources.brave) version;
              src = final.fetchurl {
                inherit (sources.brave.src.${prev.stdenv.hostPlatform.system}) url hash;
              };
            });
            google-chrome = prev.google-chrome.overrideAttrs (old: {
              inherit (sources.google-chrome.linux) version;
              src = final.fetchurl {
                inherit (sources.google-chrome.linux.src) url hash;
              };
            });
          };

      packages = forAllSystems (
        pkgs:
        let
          # google-chrome has no aarch64-linux build
          hasChrome = lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.google-chrome;
        in
        {
          inherit (pkgs) brave;
          default = pkgs.buildEnv {
            name = "browsers";
            paths = [ pkgs.brave ] ++ lib.optional hasChrome pkgs.google-chrome;
          };
        }
        // lib.optionalAttrs hasChrome { inherit (pkgs) google-chrome; }
      );

      apps = forAllSystems (pkgs: {
        update = {
          type = "app";
          program = lib.getExe (
            pkgs.writeShellApplication {
              name = "update-browsers";
              runtimeInputs = [
                pkgs.curl
                pkgs.jq
              ];
              text = builtins.readFile ./scripts/update.sh;
            }
          );
        };
      });
    };
}
