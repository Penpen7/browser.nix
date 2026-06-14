{
  description = "Nix overlay providing up-to-date browsers (Brave, Google Chrome)";

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
      overlays.default = final: prev: {
        brave = final.callPackage ./pkgs/brave.nix {
          source = sources.brave;
          upstream = prev.brave;
        };
        google-chrome = final.callPackage ./pkgs/google-chrome.nix {
          source = sources.google-chrome;
          upstream = prev.google-chrome;
        };
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
          meta.description = "Update sources.json to the latest stable Brave and Google Chrome";
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
