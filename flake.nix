{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    {
      self,
      systems,
      nixpkgs,
      ...
    }:
    let
      eachSystem = nixpkgs.lib.genAttrs (import systems);
      pkgsBySystem = eachSystem (
        system:
        import nixpkgs {
          inherit system;
          overlays = [
            self.overlays.default
          ];
        }
      );
    in
    {
      packages = eachSystem (
        system:
        let
          pkgs = pkgsBySystem.${system};
        in
        {
          inherit (pkgs) qocr qocrd;
          default = pkgs.qocr;
        }
      );
      overlays.default =
        final: prev:
        let
          qocrd = final.python3.pkgs.callPackage ./qocrd.nix { };
          quickshell = (
            prev.quickshell.overrideAttrs (old: {
              buildInputs = (builtins.filter (x: x != final.jemalloc) old.buildInputs) ++ [
                final.qt6.qtwebengine
              ];
              cmakeFlags = (old.cmakeFlags or [ ]) ++ [
                (final.lib.cmakeBool "USE_JEMALLOC" false)
              ];
              patches = (old.patches or [ ]) ++ [ ./quickshell.patch ];
            })
          );
          qocr = final.callPackage ./qocr.nix { inherit qocrd quickshell; };
        in
        {
          inherit qocr qocrd quickshell;
        };
      devShells = eachSystem (
        system:
        let
          pkgs = pkgsBySystem.${system};
        in
        {
          default = pkgs.mkShell {
            inputsFrom = [
              pkgs.qocr
              pkgs.qocrd
              pkgs.quickshell
            ];
            packages = [
              pkgs.qocr
              pkgs.qocrd
              pkgs.quickshell
            ];
          };
        }
      );
    };
}
