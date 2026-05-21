{
  description = "code-server: VS Code in the browser (coder/code-server).";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem
      [ "x86_64-linux" "aarch64-linux" "armv7l-linux" "x86_64-darwin" "aarch64-darwin" ]
      (system:
      let
        pin = import ./pin.nix;
        inherit (pin) version hashes;
        pkgs = import nixpkgs { inherit system; };

        # nix-system -> upstream tarball os-arch suffix.
        platformSuffix = {
          "x86_64-linux" = "linux-amd64";
          "aarch64-linux" = "linux-arm64";
          "armv7l-linux" = "linux-armv7l";
          "x86_64-darwin" = "macos-amd64";
          "aarch64-darwin" = "macos-arm64";
        };

        suffix = platformSuffix.${system};

        src = pkgs.fetchurl {
          url = "https://github.com/coder/code-server/releases/download/v${version}/code-server-${version}-${suffix}.tar.gz";
          hash = hashes.${system};
        };

        code-server = pkgs.stdenv.mkDerivation {
          pname = "code-server";
          inherit version src;

          sourceRoot = "code-server-${version}-${suffix}";

          nativeBuildInputs = [ pkgs.makeWrapper ];

          installPhase = ''
            runHook preInstall

            mkdir -p $out
            cp -r . $out/

            # Wrap the binary to find node and set up the environment
            wrapProgram $out/bin/code-server \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.nodejs ]}

            runHook postInstall
          '';

          dontFixup = true;

          meta = {
            description = "VS Code in the browser";
            homepage = "https://github.com/coder/code-server";
            mainProgram = "code-server";
            platforms = builtins.attrNames platformSuffix;
          };
        };

        update-version = pkgs.writeShellApplication {
          name = "update-version";
          text = ''exec ${./update-version.sh} "$@"'';
        };
        update-branches = pkgs.writeShellApplication {
          name = "update-branches";
          text = ''exec ${./update-branches.sh} "$@"'';
        };
      in
      {
        packages = {
          inherit code-server update-version update-branches;
          default = code-server;
        };
      });
}
