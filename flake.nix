{
  description = "Reusable profile generation library for Nix flakes";

  outputs = {self}: {
    lib = {
      pkgs,
      lib ? pkgs.lib,
    }:
      import ./lib.nix {inherit pkgs lib;};
  };
}
