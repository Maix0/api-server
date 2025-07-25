{
  description = "A basic flake with a shell";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    naersk.url = "github:nix-community/naersk";
  };
  outputs = {
    self,
    nixpkgs,
    flake-utils,
    rust-overlay,
    naersk,
    ...
  } @ inputs:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [(import rust-overlay)];
      };
      packageIf = name: packageDef:
        if builtins.hasAttr name inputs
        then [(packageDef inputs.${name})]
        else [];
      buildRustToolchain = toolchainDef:
        if builtins.isString toolchainDef
        then let
          split = pkgs.lib.strings.splitString "/" toolchainDef;
          toolchainType =
            if (builtins.length split) > 3
            then throw "You can only specify a single version using `{type}/{version}/{profile}`"
            else if (builtins.length split) >= 1
            then builtins.elemAt split 0
            else throw "You must specify at least a toolchain version with this format `{type}/{version}/{profile}`";
          toolchainVersion =
            if (builtins.length split) > 3
            then throw "You can only specify a single version using `{type}/{version}/{profile}`"
            else if (builtins.length split) >= 2
            then builtins.elemAt split 1
            else "latest";
          toolchainProfile =
            if (builtins.length split) > 3
            then throw "You can only specify a single version using `{type}/{version}/{profile}`"
            else if (builtins.length split) >= 3
            then builtins.elemAt split 2
            else "default";
        in
          buildRustToolchain {
            toolchain = toolchainType;
            version = toolchainVersion;
            profile = toolchainProfile;
          }
        else if builtins.isAttrs toolchainDef
        then
          if toolchainDef.toolchain == "stable"
          then pkgs.rust-bin.stable.${toolchainDef.version}.${toolchainDef.profile}.override (builtins.removeAttrs toolchainDef ["toolchain" "version" "profile"])
          else if toolchainDef.toolchain == "beta"
          then pkgs.rust-bin.beta.${toolchainDef.version}.${toolchainDef.profile}.override (builtins.removeAttrs toolchainDef ["toolchain" "version" "profile"])
          else if toolchainDef.toolchain == "nightly"
          then
            if toolchainDef.version == "latest"
            then pkgs.rust-bin.selectLatestNightlyWith (toolchain: toolchain.${toolchainDef.profile}.override (builtins.removeAttrs toolchainDef ["toolchain" "version" "profile"]))
            else pkgs.rust-bin.nightly.${toolchainDef.version}.${toolchainDef.profile}.override (builtins.removeAttrs toolchainDef ["toolchain" "version" "profile"])
          else throw "toolchain version isn't valid (not 'stable' or 'beta' or 'nightly')"
        else throw "toolchainDef isn't a string or an attr describing the toolchain";
      rust_dev = (buildRustToolchain "stable/latest/default").override {
        targets = ["wasm32-unknown-unknown" "x86_64-unknown-linux-gnu"];
      };
      naersk' = pkgs.callPackage naersk {
        cargo = rust_dev;
        rustc = rust_dev;
      };
    in {
      packages = with pkgs; rec {
        raw = naersk'.buildPackage {
          name = "akm-raw";
          src = ./.;
        };

        data = stdenv.mkDerivation {
          inherit (raw) version;
          pname = "akm-data";
          src = ./.;
          dontBuild = "true";
          installPhase = ''
            mkdir -p "$out/share"
            cp -r ./static    $out/share/static;
            cp -r ./templates $out/share/templates;
          '';
        };

        full = stdenv.mkDerivation {
          inherit (raw) version;
          pname = "akm-full";
          src = raw;
          dontBuild = "true";
          installPhase = ''
            mkdir -p "$out/bin"

            ln -s ${raw}/bin/akm "$out/bin/akm.unwrapped";

            cat <<EOF >"$out/bin/akm"
            #! ${runtimeShell}

            export STATIC_DIR="${data}/share/static";
            export TEMPLATE_DIR="${data}/share/templates";
            exec "$out/bin/akm.unwrapped"
            EOF
            chmod +x $out/bin/akm
          '';
        };
        default = full;
      };

      devShell = pkgs.mkShell {
        packages = with pkgs;
          [
            rust_dev
            mold
            openssl
            pkg-config
            sqlite-interactive
            sqlx-cli
            wasm-bindgen-cli_0_2_100
            wasm-pack
            readline
          ]
          ++ (packageIf "cargo-semver-checks" (p: p.packages.${system}.default))
          ++ (packageIf "cargo-workspace" (p: p.packages.${system}.default));

        shellHook = ''
          export RUST_STD="${rust_dev}/share/doc/rust/html/std/index.html"
          export DATABASE_URL="sqlite://./db.sqlite"
        '';
      };
    });
}
