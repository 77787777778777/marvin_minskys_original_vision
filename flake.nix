# The Framework -- a Minsky-frames text adventure in Tcl, served as WASM.
#
# Pinned to a cached nixpkgs revision (the system flake's rev) so tcl and
# node come straight from the binary cache: nothing here builds from source.
{
  description = "The Framework: a text adventure assembled entirely from Minsky frames (AIM-306), playable in a terminal or a browser via Feather WASM";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/c4013e501c048ae7c4a8940c92837636042bf6c3";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # nix develop -- tclsh for the native game, node for the WASM test
      # harness and the static server.
      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.tcl pkgs.nodejs ];
      };

      packages.${system} = rec {
        # The game itself, runnable from anywhere:
        #   nix run .#framework        -- native terminal play
        framework = pkgs.stdenvNoCC.mkDerivation {
          name = "framework-game";
          src = self;
          nativeBuildInputs = [ pkgs.makeWrapper ];
          dontBuild = true;
          installPhase = ''
            mkdir -p $out/share/framework $out/bin
            cp adventure.tcl frames.tcl engine.tcl cache.tcl shims.tcl world.tcl README.md \
              $out/share/framework/
            substituteInPlace $out/share/framework/adventure.tcl \
              --replace "#!/usr/bin/env tclsh" "#!${pkgs.tcl}/bin/tclsh"
            chmod +x $out/share/framework/adventure.tcl
            makeWrapper $out/share/framework/adventure.tcl $out/bin/framework
          '';
          passthru.web = web-dist;
        };

        # The browser build: Feather WASM + the same core Tcl the native
        # game runs (index.html fetches frames/engine/cache/shims/world
        # from its own directory), plus the host-driven entry point.
        web-dist = pkgs.stdenvNoCC.mkDerivation {
          name = "framework-web";
          src = self;
          dontBuild = true;
          installPhase = ''
            mkdir -p $out/game
            cp web/*.js web/*.wasm web/*.html $out/
            cp web/game/game.tcl $out/game/
            cp frames.tcl engine.tcl cache.tcl shims.tcl world.tcl $out/
          '';
        };

        default = framework;
      };

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.framework}/bin/framework";
      };
    };
}
