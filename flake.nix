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
          esp-idf-xtensa
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

          contents =
            devDeps
            ++ (builtins.attrValues pkgs.esp-idf-xtensa.tools)
            ++ [
              pkgs.coreutils
              pkgs.stdenv.cc

              # for VScode dev container
              pkgs.gnutar
              pkgs.gzip
              pkgs.gnused
              pkgs.gnugrep
              pkgs.stdenv.cc.cc.lib
              pkgs.glibc.bin

              # Minimal system basics
              pkgs.dockerTools.usrBinEnv
              pkgs.dockerTools.binSh
              pkgs.dockerTools.caCertificates
              pkgs.dockerTools.fakeNss
            ];

          fakeRootCommands = ''
            mkdir -p -m 0777 ./tmp
            mkdir -p ./etc

            echo "/lib" > ./etc/ld.so.conf
            echo "/usr/lib" >> ./etc/ld.so.conf

            mkdir -p ./lib64
            ln -sf ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 ./lib64/ld-linux-x86-64.so.2

            mkdir -p ./lib
            ln -sf ${pkgs.glibc}/lib/* ./lib/
            ln -sf ${pkgs.stdenv.cc.cc.lib}/lib/libstdc++.so* ./lib/
            ln -sf /lib ./usr/lib

            touch ./etc/ld.so.cache
            mv ./bin/ldconfig ./bin/ldconfig.real
            echo '#!/bin/sh' > ./bin/ldconfig
            echo 'exec /bin/ldconfig.real -C /etc/ld.so.cache "$@"' >> ./bin/ldconfig
            chmod +x ./bin/ldconfig

            mkdir -p ./sbin
            ln -sf /bin/ldconfig ./sbin/ldconfig
          '';

          config = {
            Cmd = [ "/bin/sh" ];
            Env = [
              "PATH=/bin:/usr/bin:/sbin"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "COREUTILS=${pkgs.coreutils}"
              "LD_LIBRARY_PATH=/lib:/usr/lib:${pkgs.stdenv.cc.cc.lib}/lib"
              "LIBCLANG_PATH=${pkgs.libclang.lib}/lib/"
            ];
            WorkingDir = "/work";
          };
        };

      }
    );
}
