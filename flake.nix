{
  description = "A flake for ESP32S3";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    esp-dev = {
      url = "github:mirrexagon/nixpkgs-esp-dev";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      fenix,
      esp-dev,
    }:
    {
      overlays.default = import ./nix/overlay.nix;

    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [
          fenix.overlays.default
          esp-dev.overlays.default
          self.overlays.default
        ];

        pkgs = import nixpkgs { inherit system overlays; };
        rust_toolchain_esp =
          with fenix.packages.${system};
          combine [
            pkgs.rust-esp
            pkgs.rust-src-esp
          ];

      in
      {
        # Defines a development shell named 'default'
        formatter = pkgs.nixpkgs-fmt;
        devShells.default = pkgs.mkShell {
          name = "Development environment for ESP32S3";
          nativeBuildInputs = with pkgs; [
            # rust
            rust_toolchain_esp

            # esp
            espflash
            esp-dev.packages.${system}.esp-idf-esp32s3
          ];
        };
      }
    );
}
