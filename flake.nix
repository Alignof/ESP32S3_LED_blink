{
  description = "A flake for ESP32S3 and build Docker environment";

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

        # Combine Rust ESP toolchain and source
        rust_toolchain_esp =
          with fenix.packages.${system};
          combine [
            pkgs.rust-esp
            pkgs.rust-src-esp
          ];

        # Toolchain dependencies
        devDeps = with pkgs; [
          rust_toolchain_esp
          espflash
          esp-dev.packages.${system}.esp-idf-xtensa
          git
          cacert
        ];
      in
      {
        formatter = pkgs.nixpkgs-fmt;

        # Development shell
        devShells.default = pkgs.mkShell {
          name = "Development environment for ESP32S3";
          nativeBuildInputs = devDeps;
        };

        # Docker image build
        packages.dockerImage = pkgs.dockerTools.buildLayeredImage {
          name = "ghcr.io/alignof/esp32s3_led_blink";
          tag = "latest";
          contents = devDeps ++ [
            pkgs.bashInteractive
            pkgs.coreutils
            pkgs.stdenv.cc
            pkgs.binutils
          ];
          extraCommands = "mkdir -m 0777 tmp";

          config = {
            Cmd = [ "${pkgs.bashInteractive}/bin/bash" ];
            Env = [
              "PATH=/bin:/usr/bin:${
                pkgs.lib.makeBinPath (
                  devDeps
                  ++ [
                    pkgs.bashInteractive
                    pkgs.coreutils
                    rust_toolchain_esp
                  ]
                )
              }"
              "USER=root"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ];
            WorkingDir = "/work";
          };
        };
      }
    );
}
