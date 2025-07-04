{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    odin 
    clang

    git
    
    gnumake42
    SDL2
    glfw
    libcxx
    python311Packages.ply
    #gdb
    #gf

    tree
  ];
}

