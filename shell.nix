{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    odin 
    clang

    gnumake42
    SDL2
    libcxx
    python311Packages.ply
    #gdb
    #gf

    tree
  ];
}

