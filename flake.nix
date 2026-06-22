{
  description = "Elixir Development";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-compat = {
      url = "github:NixOS/flake-compat";
      flake = false;
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      flake-utils,
      ...
    }:
    let
      systems = with flake-utils.lib.system; [
        x86_64-linux
      ];
    in
    flake-utils.lib.eachSystem systems (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        beamPkgs = pkgs.beamMinimal29Packages;
        commonPkgs = with pkgs; [
          beamPkgs.elixir_1_20
          beamPkgs.hex
          beamPkgs.expert
          mix2nix
        ];
      in
      {
        devShells = {
          default = pkgs.mkShell {
            packages =
              with pkgs;
              [
                inotify-tools
              ]
              ++ commonPkgs;
            shellHook = ''
              # Set up `mix` to save dependencies to the local directory
              mkdir -p .nix-mix
              mkdir -p .nix-hex
              export MIX_HOME=$PWD/.nix-mix
              export HEX_HOME=$PWD/.nix-hex
              export PATH=$MIX_HOME/bin:$PATH
              export PATH=$HEX_HOME/bin:$PATH

              # Beam-specific
              export LANG=en_US.UTF-8
              export ERL_AFLAGS="-kernel shell_history enabled"
            '';
          };
        };
      }
    );
}
