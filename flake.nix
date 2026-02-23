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
      ...
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
        rust_toolchain_esp = fenix.packages.${system}.combine [
          pkgs.rust-esp
          pkgs.rust-src-esp
        ];

        # Toolchain dependencies used in both devShell and Docker image
        devDeps = with pkgs; [
          rust_toolchain_esp
          esp-idf-s3-minimal.tools.xtensa-esp-elf
          esp-idf-s3-minimal.tools.esp32ulp-elf
          esp-idf-s3-minimal.tools.xtensa-esp-elf-gdb
          espflash
          gitMinimal
        ];
      in
      {
        formatter = pkgs.nixpkgs-fmt;

        # Development shell for local use
        devShells.default = pkgs.mkShell {
          name = "Development environment for ESP32S3";
          nativeBuildInputs = devDeps;
        };

        # Docker image build
        packages.dockerImage = pkgs.dockerTools.buildLayeredImage {
          name = "ghcr.io/alignof/esp32s3_led_blink";
          tag = "latest";
          maxLayers = 100; # Merge small layers to improve performance

          contents = devDeps ++ [
            pkgs.coreutils
            pkgs.stdenv.cc

            # Utilities required for VSCode dev container support
            pkgs.gnutar
            pkgs.gzip
            pkgs.gnused
            pkgs.gnugrep
            pkgs.stdenv.cc.cc.lib

            # Minimal system basics
            pkgs.dockerTools.usrBinEnv
            pkgs.dockerTools.binSh
            # pkgs.dockerTools.fakeNss
          ];

          fakeRootCommands = ''
            mkdir -p -m 0777 ./tmp

            mkdir -p ./etc/ssl/certs
            cp ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt ./etc/ssl/certs

            echo "root:x:0:0:root:/root:/bin/sh" > ./etc/passwd
            echo "root:x:0:" > ./etc/group

            # Dynamic linker configuration for standard paths
            echo "/lib" > ./etc/ld.so.conf
            echo "/usr/lib" >> ./etc/ld.so.conf

            mkdir -p ./lib64
            ln -sf ${pkgs.glibc}/lib/ld-linux-x86-64.so.2 ./lib64/ld-linux-x86-64.so.2

            mkdir -p ./lib
            ln -sf ${pkgs.glibc}/lib/* ./lib/
            ln -sf ${pkgs.stdenv.cc.cc.lib}/lib/libstdc++.so* ./lib/
            ln -sf /lib ./usr/lib

            # Handle ldconfig for applications that expect it
            touch ./etc/ld.so.cache
            if [ -f ./bin/ldconfig ]; then
              mv ./bin/ldconfig ./bin/ldconfig.real
              echo '#!/bin/sh' > ./bin/ldconfig
              echo 'exec /bin/ldconfig.real -C /etc/ld.so.cache "$@"' >> ./bin/ldconfig
              chmod +x ./bin/ldconfig
            fi

            mkdir -p ./sbin
            ln -sf /bin/ldconfig ./sbin/ldconfig
          '';

          config = {
            Cmd = [ "/bin/sh" ];
            Env = [
              "PATH=/bin:/usr/bin:/sbin"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "LD_LIBRARY_PATH=/lib:/usr/lib:${pkgs.stdenv.cc.cc.lib}/lib"
            ];
            WorkingDir = "/work";
          };
        };
      }
    );
}
