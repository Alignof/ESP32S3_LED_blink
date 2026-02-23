# Ákos Nádudvari
# https://github.com/akosnad/nix-esp32-bare-metal-template

final: prev: {
  rust-esp = prev.callPackage ./rust-esp.nix { };
  rust-src-esp = prev.callPackage ./rust-src-esp.nix { };

  esp-idf-s3-minimal = prev.esp-idf-xtensa.override {
    toolsToInclude = [
      "xtensa-esp-elf"
      "esp32ulp-elf"
      "xtensa-esp-elf-gdb"
    ];
  };
}
