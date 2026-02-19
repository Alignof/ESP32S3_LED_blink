# Ákos Nádudvari
# https://github.com/akosnad/nix-esp32-bare-metal-template

final: prev: {
  rust-esp = prev.callPackage ./rust-esp.nix { };
  rust-src-esp = prev.callPackage ./rust-src-esp.nix { };
}
