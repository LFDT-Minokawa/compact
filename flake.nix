# This file is part of Compact.
# Copyright (C) 2025 Midnight Foundation
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# 	http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

{
  description = "Compact Compiler";

  # IOG's public binary cache
  nixConfig = {
    extra-substituters = "https://cache.iog.io";
    extra-trusted-public-keys = ["hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="];
  };

  inputs = {
    zkir = {
      # dependency for compact-runtime release
      # this is using a commit hash to pull in the correct zkir version from ledger-6.0.0-alpha.3 release
      # if for releasing the runtime, running nix flake update causes errors for autherization of cargo, use
      # the commit hash instead of the tag for this.
      # NOTE: if this is an internal release (uses -alpha, -beta, or -rc) do NOT update the package.json in runtime
      # since npm can only access public releases. For the compact-runtime release nix will pull in the correct
      # version from this url.
      url = "github:midnightntwrk/midnight-ledger/ledger-6.1.0-alpha.5";
      inputs.zkir.follows = "zkir";
    };
    onchain-runtime-v1 = {
      # dependency for compact-runtime release
      # all notes for the zkir input applies to onchain-runtime input too.
      url = "github:midnightntwrk/midnight-ledger/ledger-6.1.0-alpha.5";
      inputs.zkir.follows = "zkir";
    };
    zkir-wasm = {
      # dependency for test-center
      url = "github:midnightntwrk/midnight-ledger/ledger-6.1.0-alpha.5";
      inputs.zkir.follows = "zkir";
    };
    n2c.url = "github:nlewo/nix2container";
    chez-exe.url = "github:tkerber/chez-exe";

    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
    inclusive.url = "github:input-output-hk/nix-inclusive";
    npmlock2nix = {
      url = "github:nix-community/npmlock2nix";
      flake = false;
    };

    midnight-contracts = {
      url = "github:midnightntwrk/midnight-contracts/unshielded-tokens";
      flake = false;
    };
  };

  outputs = {
    self,
    zkir,
    onchain-runtime-v1,
    zkir-wasm,
    nixpkgs,
    utils,
    inclusive,
    midnight-contracts,
    chez-exe,
    npmlock2nix,
    ...
  } @ inputs:
    utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system}.extend (final: prev: {
          # hack to get npmlock2nix working, by pretending we're using an old
          # node version
          nodejs-16_x = final.nodejs;
          nodejs = final.nodejs_latest;
        });
        isDarwin = pkgs.lib.hasSuffix "-darwin" system;
        chez = if isDarwin then pkgs.chez.override {
          stdenv = pkgs.llvmPackages_18.stdenv;
        } else pkgs.chez;
        sources = (import ./_sources/generated.nix) {inherit (pkgs) fetchgit fetchurl fetchFromGitHub;};
        nanopass = sources.nanopass.src;
        rough-draft = sources.rough-draft.src;
        runtime-version = (__fromJSON (__readFile ./runtime/package.json)).version;
        vscode-extension-version = (__fromJSON (__readFile ./editor-support/vsc/compact/package.json)).version;
        nix2container = inputs.n2c.packages.${system}.nix2container;
        chez-exe = inputs.chez-exe.packages.${system}.default;
        runtime-shell-hook =
          ''
            rm node_modules -rf
            cp -r ${self.packages.${system}.runtime.node-modules}/node_modules node_modules
            chown $USER -R node_modules
            chmod u+w -R node_modules
            cp -r ${self.packages.${system}.runtime.package}/lib/node_modules/@midnight-ntwrk/compact-runtime node_modules/@midnight-ntwrk/compact-runtime
            chown $USER -R node_modules
            chmod u+w -R node_modules
            ln -sfn ${midnight-contracts} test-center/midnight-contracts
          '';
        test-center-shell-hook =
          ''
            # Set up test-center node_modules
            if [ -d test-center ]; then
              rm -rf test-center/node_modules
              cp -r ${self.packages.${system}.test-center.node-modules}/node_modules test-center/node_modules
              chown $USER -R test-center/node_modules
              chmod u+w -R test-center/node_modules
            fi
          '';
        combined-shell-hook =
          ''
            ${runtime-shell-hook}
            ${test-center-shell-hook}
          '';
        platformSpecificInputs = {
          x86_64-darwin = [ pkgs.darwin.libiconv ];
          x86_64-linux = [ pkgs.musl ];
          aarch64-darwin = [ pkgs.darwin.libiconv ];
          aarch64-linux = [ pkgs.musl ];
        }.${system};
        pretzel-js = (import nix/pretzel/js.nix) {
          inherit (nixpkgs) lib;
          inherit npmlock2nix;
          dry-install = self.packages.${system}.pretzel-dry-install;
        };
        dry-install = pretzel-js.mkPackage {
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ pretzel-js.overlay ];
          };
          src = nix/dry-install;
        };
      in
        rec {
          lib.pretzel-js = pretzel-js;
          overlays.pretzel-fetcher = (import pretzel/fetcher.nix).overlay;
          overlays.pretzel-js = lib.pretzel-js.overlay;
          packages.pretzel-dry-install = dry-install.package;
          packages.runtime = let
            inclusive-src = inclusive.lib.inclusive ./. [
              ./runtime
              ./compiler/json.ss
              ./compiler/utils.ss
              ./compiler/field.ss
              ./third_party/compiler/state-case.ss
            ];
          in lib.pretzel-js.mkPackage {
            pkgs = import nixpkgs {
              inherit system;
              overlays = [overlays.pretzel-js];
            };
            #name = "compact-runtime";
            #version = runtime-version;
            src = "${inclusive-src}/runtime";
            overrideBuildAttrs = {
              common = pkgs.lib.trivial.id;
              package = oldAttrs: oldAttrs // {
                buildInputs = [ chez ];
                CHEZSCHEMELIBDIRS = "${inclusive-src}/compiler:${inclusive-src}/third_party/compiler";
              };
              tests = pkgs.lib.trivial.id;
              lints = pkgs.lib.trivial.id;
            };

            nixDependenciesMap = {
              "@midnight-ntwrk/onchain-runtime-v1" = let
                pkg = onchain-runtime-v1.packages.${system}.onchain-runtime-wasm;
              in {
                tarPath = "${pkg}/lib/midnight-onchain-runtime-v1-${pkg.version}.tgz";
                libPath = "${pkg}/lib/node_modules/@midnight-ntwrk/onchain-runtime-v1";
              };
            };
          };

          packages.test-center = lib.pretzel-js.mkPackage {
            pkgs = import nixpkgs {
              inherit system;
              overlays = [overlays.pretzel-js];
            };
            src = ./test-center;

            nixDependenciesMap = {
              "@midnight-ntwrk/zkir-v2" = let
                pkg = zkir-wasm.packages.${system}.zkir-wasm;
              in {
                tarPath = "${pkg}/lib/midnight-zkir-v2-${pkg.version}.tgz";
                libPath = "${pkg}/lib/node_modules/@midnight-ntwrk/zkir-v2";
              };
            };
          };

          packages.compactc-no-runtime = packages.compactc.overrideAttrs (oldAttrs: {
            NODE_PATH = "";
            buildInputs = [
              pkgs.nodejs
              pkgs.nodePackages.typescript
              chez
            ];
            checkPhase = "";
          });

          packages.compactc = pkgs.stdenv.mkDerivation {
            name = "compactc";
            version = "0.27.105"; # NB: also update compiler-version in compiler/compiler-version.ss
            src = inclusive.lib.inclusive ./. [
              ./test-center
              ./compiler
              ./third_party/compiler
              ./examples
              ./srcMaps
              ./runtime/extract-version.ss
              ./runtime/package.json
            ];

            CHEZSCHEMELIBDIRS = "compiler::obj/compiler:third_party/compiler::obj/third_party/compiler:${nanopass}::obj/nanopass:${rough-draft}/src::obj/rough-draft:srcMaps::obj/srcMaps::obj/compiler";

            NODE_PATH = "${packages.runtime.node-modules}/node_modules";

            buildInputs = [
              pkgs.nodejs
              pkgs.nodePackages.typescript
              packages.runtime.package
              packages.runtime.node-modules
              chez
            ];

            buildPhase = ''
              mkdir -p obj/compiler
              sed -e 's;/usr/bin/env .*;'`command -v scheme`' --program;' compiler/compactc.ss > obj/compiler/compactc.ss
              sed -e 's;/usr/bin/env .*;'`command -v scheme`' --program;' compiler/format-compact.ss > obj/compiler/format-compact.ss
              sed -e 's;/usr/bin/env .*;'`command -v scheme`' --program;' compiler/fixup-compact.ss > obj/compiler/fixup-compact.ss
              patchShebangs --host .
              ln -sfn ${midnight-contracts} test-center/midnight-contracts

              scheme -q << END
                (reset-handler abort)
                (optimize-level 2)
                (compile-imported-libraries #t)
                (generate-wpo-files #t)
                (generate-inspector-information #f)
                (compile-profile #f)
                (compile-program "obj/compiler/compactc.ss" "obj/compiler/compactc.so")
                (compile-program "obj/compiler/format-compact.ss" "obj/compiler/format-compact.so")
                (compile-program "obj/compiler/fixup-compact.ss" "obj/compiler/fixup-compact.so")
                (compile-whole-program "obj/compiler/compactc.wpo" "obj/compactc")
                (compile-whole-program "obj/compiler/format-compact.wpo" "obj/format-compact")
                (compile-whole-program "obj/compiler/fixup-compact.wpo" "obj/fixup-compact")
              END
            '';

            # check if the code was build correctly
            checkPhase = ''
              cp -r ${packages.runtime.node-modules}/node_modules node_modules
              chmod -R +rw node_modules
              cp -r ${packages.runtime.package}/lib/node_modules/@midnight-ntwrk/compact-runtime node_modules/@midnight-ntwrk/compact-runtime
              ./compiler/go
              ./srcMaps/test.sh
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp obj/compactc $out/bin
              cp obj/format-compact $out/bin
              cp obj/fixup-compact $out/bin
              chmod +x $out/bin/compactc
              chmod +x $out/bin/format-compact
              chmod +x $out/bin/fixup-compact
            '';
          };

          packages.compactc-binary-nixos = let
            linking-pkgs = if pkgs.lib.hasSuffix "linux" system then pkgs.pkgsMusl else pkgs;
            platformSpecificInputs = with linking-pkgs; {
              x86_64-darwin = [ darwin.libiconv ];
              x86_64-linux = [ ];
              aarch64-darwin = [ darwin.libiconv ];
              aarch64-linux = [ ];
            }.${system};
          in linking-pkgs.stdenv.mkDerivation {
            name = "compactc-binary-nixos";
            version = "0.0.1";
            src = inclusive.lib.inclusive ./. [
              ./test-center
              ./compiler
              ./third_party/compiler
              ./examples
              ./srcMaps
              ./runtime/extract-version.ss
              ./runtime/package.json
            ];

            CHEZSCHEMELIBDIRS = "compiler::obj/compiler:third_party/compiler::obj/third_party/compiler:${nanopass}::obj/nanopass:${rough-draft}/src::obj/rough-draft:srcMaps::obj/srcMaps::obj/compiler";

            buildInputs = [
              chez-exe
            ] ++ platformSpecificInputs;

            buildPhase = ''
              mkdir -p obj/compiler

              sed -e 's;/usr/bin/env .*;'`command -v scheme`' --program;' compiler/compactc.ss > obj/compiler/compactc.ss
              sed -e 's;/usr/bin/env .*;'`command -v scheme`' --program;' compiler/format-compact.ss > obj/compiler/format-compact.ss
              sed -e 's;/usr/bin/env .*;'`command -v scheme`' --program;' compiler/fixup-compact.ss > obj/compiler/fixup-compact.ss

              compile-chez-program --optimize-level 2 obj/compiler/compactc.ss
              compile-chez-program --optimize-level 2 obj/compiler/format-compact.ss
              compile-chez-program --optimize-level 2 obj/compiler/fixup-compact.ss
            '';

            installPhase = ''
              mkdir -p $out/bin

              for exe in compactc format-compact fixup-compact; do
                cp "obj/compiler/$exe" $out/bin
                chmod +x "$out/bin/$exe"
              done
            '';
          };

          packages.compactc-binaryWrapperScript-nixos = pkgs.writeShellScriptBin "run-compactc" ''
            PATH=${pkgs.lib.makeBinPath [ packages.compactc-binary-nixos zkir.packages.${system}.zkir ]} \
            compactc $@
          '';

          packages.compactc-binary = pkgs.stdenv.mkDerivation {
            name = "compactc-binary-dist";
            version = "0.0.1";
            srcs = packages.compactc-binary-nixos;

            installPhase = ''
              mkdir -p $out/bin $out/lib
              cp bin/compactc $out/bin
              mv $out/bin/compactc $out/bin/compactc.bin
              cp ${zkir.packages.${system}.zkir}/bin/zkir $out/lib/zkir

              chmod +w $out/lib/zkir

              touch $out/bin/compactc
              chmod +x $out/bin/compactc

              cat <<EOF > $out/bin/compactc
              #!/usr/bin/env bash
              thisdir="\$(cd \$(dirname \$0) ; pwd -P)"
              PATH="\$thisdir:\$PATH"
              exec "\$thisdir/compactc.bin" "\$@"
              EOF

              for exe in format-compact fixup-compact; do
                cp "bin/$exe" $out/bin
                chmod +x "$out/bin/$exe"
              done
            '';

            dontFixup = true;
          };

          packages.compactc-oci = with pkgs // packages; nix2container.buildImage {
            name = "compactc";
            tag = compactc.version;
            copyToRoot = [
              # When we want tools in /, we need to symlink them in order to
              # still have libraries in /nix/store. This behavior differs from
              # dockerTools.buildImage but this allows to avoid having files
              # in both / and /nix/store.
              (pkgs.buildEnv {
                name = "root";
                paths = [
                  bashInteractive
                  coreutils
                ];
                pathsToLink = [ "/bin" ];
              })
            ];

            config = {
              entrypoint = [ "${bashInteractive}/bin/bash" "-c" ];
              Cmd = [ "${compactc}/bin/compactc" ];
              Env = [
                "PATH=${pkgs.lib.makeBinPath [
                  compactc
                  zkir.packages.${system}.zkir
                ]}"
              ];
            };
            layers = [
              (nix2container.buildLayer {
                deps = [
                  compactc
                  zkir.packages.${system}.zkir
                ];
              })
            ];
          };

          packages.compact-vscode-extension-node-modules = pkgs.mkYarnModules {
            pname = "compact-vscode-extension-node-modules";
            version = vscode-extension-version;
            packageJSON = ./editor-support/vsc/compact/package.json;
            yarnLock = ./editor-support/vsc/compact/yarn.lock;
          };

          packages.compact-vscode-extension =
            pkgs.lib.customisation.overrideDerivation (pkgs.stdenv.mkDerivation rec {
              pname = "compact-vscode-extension";
              version = vscode-extension-version;
              src = ./editor-support/vsc/compact;
              buildInputs = with pkgs; [
                nodejs
                yarn
              ];
              nativeBuildInputs = [
                 chez
                 packages.compactc
              ];

              TEST_COMPACT_PATH = ./test-center/compact/test.compact;
              CHEZSCHEMELIBDIRS = "${nanopass}::obj/nanopass:${rough-draft}/src::obj/rough-draft:srcMaps::obj/srcMaps:compiler::obj/compiler:third_party/compiler::obj/third_party/compiler";

              buildPhase = ''
                ln -s ${packages.compact-vscode-extension-node-modules}/node_modules
              '';

              doCheck = true;

              checkPhase = ''
                echo Get compiler
                mkdir -p tmp/obj
                cp -R ${packages.compactc.src}/* tmp
                cd tmp

                echo Export current keywords
                scheme --program ./compiler/export-keywords.ss $(pwd)/../tests/resources/keywords.json
                cat $(pwd)/../tests/resources/keywords.json
                cd ..

                echo Run unit tests
                yarn run --offline test --ci --reporters=jest-silent-reporter --reporters=summary
              '';

            installPhase = ''
              mkdir -p $out
              yarn build
              yarn vsce package --yarn -o $out
            '';
          })
           (drv: {
              extensionFile = drv.outPath + "/compact-${drv.version}.vsix";
            });

          packages.test-src-maps = pkgs.lib.customisation.overrideDerivation (pkgs.stdenv.mkDerivation {
            pname = "compact-source-maps-tests";
            version = vscode-extension-version;
            src = ./test-src-maps;
            buildInputs = with pkgs; [
              nodejs
              yarn
            ];

            buildPhase = ''
              yarn --offline build
            '';

            doCheck = true;

            checkPhase = ''
              yarn run --offline test
            '';

            installPhase = ''
              mkdir -p $out
              touch $out/ok
            '';
          });

          packages.all = pkgs.symlinkJoin {
            name = "compact-all";
            meta.mainProgram = "compactc";
            paths = [
              packages.compactc
              zkir.packages.${system}.zkir
              packages.compact-vscode-extension
            ];
          };

          packages.default = packages.all;

          devShells.default = pkgs.mkShell {
            inputsFrom = with packages; [compactc];
            packages = [
              pkgs.nodejs
              pkgs.yarn
              pkgs.alejandra
              packages.runtime.package
              packages.runtime.node-modules
              packages.test-center.package
              packages.test-center.node-modules
            ];
            shellHook = combined-shell-hook;

            CHEZSCHEMELIBDIRS = "compiler::obj/compiler:third_party/compiler::obj/third_party/compiler:${nanopass}::obj/nanopass:${rough-draft}/src::obj/rough-draft:srcMaps::obj/srcMaps";
            WASM_BINDGEN_WEAKREF = 1;
            WASM_BINDGEN_EXTERNREF = 1;
          };

          devShells.with-zkir = packages.runtime.mkShell {
            inputsFrom = with packages; [compactc];
            packages = [
              pkgs.nodejs
              pkgs.yarn
              pkgs.binaryen
              packages.runtime.package
              packages.runtime.node-modules
              packages.test-center.package
              packages.test-center.node-modules
              zkir.packages.${system}.zkir
            ];
            shellHook = combined-shell-hook;

            CHEZSCHEMELIBDIRS = "compiler::obj/compiler:third_party/compiler::obj/third_party/compiler:${nanopass}::obj/nanopass:${rough-draft}/src::obj/rough-draft:srcMaps::obj/srcMaps";
          };

          devShells.compiler = pkgs.mkShell {
            inputsFrom = with packages; [compactc];
            packages = [
              packages.compactc
              pkgs.yarn
              zkir.packages.${system}.zkir
            ];

            CHEZSCHEMELIBDIRS = "compiler::obj/compiler:third_party/compiler::obj/third_party/compiler:${nanopass}::obj/nanopass:${rough-draft}/src::obj/rough-draft:srcMaps::obj/srcMaps";
          };

          devShells.runtime = packages.runtime.mkShell {
            packages = [
              pkgs.nodejs
              pkgs.chez
            ];
            shellHook = runtime-shell-hook;
          };

          devShells.dapp = packages.runtime.mkShell {
            packages = [
              packages.compactc
              packages.runtime.package
              packages.runtime.node-modules
              zkir.packages.${system}.zkir
              pkgs.nodejs
              pkgs.yarn
            ];
            shellHook = runtime-shell-hook;
          };

          formatter = pkgs.alejandra;
        }
    );
}
