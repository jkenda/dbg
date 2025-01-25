{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    odin 

    gnumake42
    SDL2
    libcxx
    python311Packages.ply

    tree
  ];
}

