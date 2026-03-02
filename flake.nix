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
          overlays = [ self.overlays.default ];
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
          qocr = final.callPackage ./qocr.nix { inherit qocrd; };
        in
        {
          inherit qocr qocrd;
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
            ];
            packages = [
              pkgs.qocr
              pkgs.qocrd
            ];
          };
        }
      );
    };
}
