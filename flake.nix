{
  description = "code-server: VS Code in the browser (coder/code-server).";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-lib = {
      url = "github:jgus/flake-lib/v1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, flake-lib }:
    let
      pin = import ./pin.nix;
      inherit (pin) version;
      # The orchestrator's version-only placeholder pin carries no `hashes` (update-version fills it),
      # so default to {} — the flake must still evaluate enough to expose update-version/update-branches.
      hashes = pin.hashes or { };
      source = { type = "github"; owner = "coder"; repo = "code-server"; };

      # nix-system -> upstream tarball os-arch suffix. Static union of every target code-server has shipped.
      platformSuffix = {
        "x86_64-linux" = "linux-amd64";
        "aarch64-linux" = "linux-arm64";
        "armv7l-linux" = "linux-armv7l";
        "x86_64-darwin" = "macos-amd64";
        "aarch64-darwin" = "macos-arm64";
      };
    in
    # Iterate the static platform union so update-version/update-branches always exist (the orchestrator
    # calls them against a hash-less placeholder pin). `code-server` itself is exposed only for the
    # platforms the pinned release actually shipped — upstream drops/adds targets (armv7l gone in 4.123.0).
    flake-utils.lib.eachSystem (builtins.attrNames platformSuffix)
      (system:
      let
        pkgs = import nixpkgs { inherit system; };
        suffix = platformSuffix.${system};

        src = pkgs.fetchurl {
          url = "https://github.com/coder/code-server/releases/download/v${version}/code-server-${version}-${suffix}.tar.gz";
          hash = hashes.${system} or "";
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
            platforms = builtins.attrNames hashes;
          };
        };

      in
      {
        # code-server only for platforms present in the pin; scripts always (the orchestrator needs them).
        packages =
          pkgs.lib.optionalAttrs (hashes ? ${system}) {
            inherit code-server;
            default = code-server;
          }
          // {
            # Bespoke build (per-platform prebuilt tarball) + bespoke update-version (prefetches the
            # platform matrix into a keyed hash table); only the per-version-branch orchestrator is shared.
            update-version = pkgs.writeShellApplication {
              name = "update-version";
              text = ''exec ${./update-version.sh} "$@"'';
            };
            update-branches = flake-lib.lib.mkUpdateBranches {
              inherit pkgs source;
              pinSchema = "version-only";
            };
          };
      });
}
