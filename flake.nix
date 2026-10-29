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
    onchain-runtime-v4 = {
      # dependency for Compact runtime release
      url = "github:midnightntwrk/midnight-ledger/ledger-9.1.0.0-rc.3";
    };
    zkir-v3 = {
      # zkir-v3 key-generation binary for v3 IR format
      url = "github:midnightntwrk/midnight-zkir/zkir-3.1.0-rc.1"; # zkir-v3
      inputs.nixpkgs.follows = "nixpkgs-zkir";
    };
    zkir-v3-wasm = {
      # zkir-v3-wasm for test-center v3 support
      url = "github:midnightntwrk/midnight-zkir/zkir-3.1.0-rc.1";
    };
    n2c.url = "github:nlewo/nix2container";
    chez-exe.url = "github:tkerber/chez-exe";

    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    # The release ships both zkir binaries for x86_64-darwin but nixpkgs-unstable dropped that
    # platform, so they are built from 26.05, which supports it until the end of 2026.
    nixpkgs-zkir.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    utils.url = "github:numtide/flake-utils";
    inclusive.url = "github:input-output-hk/nix-inclusive";
    npmlock2nix = {
      url = "github:nix-community/npmlock2nix";
      flake = false;
    };
  };

  outputs = {
    self,
    onchain-runtime-v4,
    zkir-v3,
    zkir-v3-wasm,
    nixpkgs,
    utils,
    inclusive,
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
        libcrypto = if isDarwin then null else "${pkgs.openssl.out}/lib/libcrypto.so";
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
            # compact-runtime is published under the @midnight-ntwrk scope, but its nix-provided
            # dependencies live under @midnightntwrk, so the parent directory must be created explicitly.
            mkdir -p node_modules/@midnight-ntwrk
            cp -r ${self.packages.${system}.runtime.package}/lib/node_modules/@midnight-ntwrk/compact-runtime node_modules/@midnight-ntwrk/compact-runtime
            chown $USER -R node_modules
            chmod u+w -R node_modules
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
        # The target built by packages.compactc and used by the dev shells.
        default-compactc-target = "ocrt-4_0-zkir-3_1";

        # Other targets in compiler/targets/ are built with packages.compactc-<target>, which
        # are generated for every target below.
        targets = builtins.attrNames
          (pkgs.lib.filterAttrs (name: type: type == "directory") (builtins.readDir ./compiler/targets));

        # A target ocrt-<M>_<m>-zkir-<N>_<n> needs
        # the inputs onchain-runtime-v<M> and zkir-v<N>, providing M.m and N.n, and an
        # input is there for a target.
        input-names = builtins.attrNames inputs;
        ocrt-inputs = builtins.filter (n: builtins.match "onchain-runtime-v[0-9]+" n != null) input-names;
        zkir-inputs = builtins.filter (n: builtins.match "zkir-v[0-9]+" n != null) input-names;
        # the major.minor of "4.0.0-rc.3"
        major-minor = version:
          let m = builtins.match "([0-9]+)\\.([0-9]+)\\..*" version;
          in if m == null then "(unreadable version ${version})" else "${builtins.elemAt m 0}.${builtins.elemAt m 1}";
        ocrt-input-version = n: major-minor inputs.${n}.packages.${system}.onchain-runtime-wasm.version;
        zkir-input-version = n: major-minor inputs.${n}.packages.${system}.zkir.version;
        parse-target = target: builtins.match "ocrt-([0-9]+)_([0-9]+)-zkir-([0-9]+)_([0-9]+)" target;

        target-input-problems =
          let
            parsed = builtins.filter (t: parse-target t != null) targets;
            part = target: i: builtins.elemAt (parse-target target) i;
            ocrt-of = target: { major = part target 0; version = "${part target 0}.${part target 1}"; };
            zkir-of = target: { major = part target 2; version = "${part target 2}.${part target 3}"; };
            # what a target needs from the inputs of one kind
            problems-of-kind = { kind, prefix, inputs-of-kind, input-version, of }:
              builtins.concatMap (target:
                let
                  need = of target;
                  name = "${prefix}${need.major}";
                in
                  if !(builtins.elem name inputs-of-kind)
                  then [ "target ${target} needs the flake input ${name}, which provides ${kind} ${need.major}.x, but flake.nix has none (it has: ${builtins.concatStringsSep ", " inputs-of-kind})" ]
                  else if input-version name != need.version
                  then [ "target ${target} is for ${kind} ${need.version} but the flake input ${name} provides ${input-version name}" ]
                  else []
              ) parsed
              ++ builtins.concatMap (name:
                if builtins.any (target: "${prefix}${(of target).major}" == name) parsed
                then []
                else [ "the flake input ${name} is used by no target in compiler/targets/ (the targets are: ${builtins.concatStringsSep ", " targets})" ]
              ) inputs-of-kind;
          in
            builtins.concatMap (target: [ "compiler/targets/${target} is not named like a target, ocrt-<major>_<minor>-zkir-<major>_<minor>" ])
              (builtins.filter (t: parse-target t == null) targets)
            ++ problems-of-kind { kind = "on-chain runtime"; prefix = "onchain-runtime-v"; inputs-of-kind = ocrt-inputs; input-version = ocrt-input-version; of = ocrt-of; }
            ++ problems-of-kind { kind = "ZKIR"; prefix = "zkir-v"; inputs-of-kind = zkir-inputs; input-version = zkir-input-version; of = zkir-of; };

        target-inputs-checked =
          if target-input-problems == []
          then true
          else throw ''
            The targets of compiler/targets/ and the flake inputs of flake.nix do not agree:
            ${builtins.concatStringsSep "\n" (map (p: "  - " + p) target-input-problems)}
            A target ocrt-<M>_<m>-zkir-<N>_<n> needs the flake inputs onchain-runtime-v<M> (providing
            on-chain runtime <M>.<m>) and zkir-v<N> (providing ZKIR <N>.<n>), and every such input is
            for a target.  See "Names that must agree" in compiler.md.
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
        let
          # packages.compactc-<target> and packages.compactc-binary-<target> for every
          # target, generated so that the name of a package cannot differ from the
          # target it builds.  The default target's are the default packages.
          target-packages = builtins.listToAttrs (builtins.concatMap (target: [
            {
              name = "compactc-${target}";
              value = if target == default-compactc-target
                then outputs.packages.compactc
                else outputs.lib.compactc-for-target target;
            }
            {
              name = "compactc-binary-${target}";
              value = if target == default-compactc-target
                then outputs.packages.compactc-binary
                else outputs.lib.compactc-binary-for-target target;
            }
          ]) targets);

          outputs = rec {
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
              "@midnightntwrk/onchain-runtime-v4" = let
                pkg = onchain-runtime-v4.packages.${system}.onchain-runtime-wasm;
              in {
                tarPath = "${pkg}/lib/midnight-onchain-runtime-v4-${pkg.version}.tgz";
                libPath = "${pkg}/lib/node_modules/@midnightntwrk/onchain-runtime-v4";
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
              "@midnightntwrk/zkir-v3" = let
                pkg = zkir-v3-wasm.packages.${system}.zkir-wasm;
              in {
                tarPath = "${pkg}/lib/midnight-zkir-v3-${pkg.version}.tgz";
                libPath = "${pkg}/lib/node_modules/@midnightntwrk/zkir-v3";
              };
            };
          };

          packages.compactc-no-runtime = packages.compactc.overrideAttrs (oldAttrs: {
            NODE_PATH = "";
            buildInputs = [
              pkgs.nodejs
              pkgs.typescript
              chez
            ];
            checkPhase = "";
          });

          packages.compactc = pkgs.stdenv.mkDerivation {
            name = "compactc";
            version = "0.35.109"; # NB: also update compiler-version in compiler/compiler-version.ss
            src = inclusive.lib.inclusive ./. [
              ./compiler
              ./examples
              ./flake.nix
              ./runtime/extract-version.ss
              ./runtime/package.json
              ./srcMaps
              ./test-center
              ./third_party/compiler
            ];

            CHEZSCHEMELIBDIRS = "compiler::obj/${default-compactc-target}:compiler/targets/${default-compactc-target}::obj/${default-compactc-target}:third_party/compiler::obj/third_party/compiler:${nanopass}::obj/nanopass:${rough-draft}/src::obj/rough-draft:srcMaps::obj/srcMaps::obj/${default-compactc-target}";
            COMPACT_LIBCRYPTO = libcrypto;

            NODE_PATH = "${packages.runtime.node-modules}/node_modules";

            buildInputs = [
              pkgs.nodejs
              pkgs.nodePackages.typescript
              packages.runtime.package
              packages.runtime.node-modules
              chez
            ] ++ pkgs.lib.optional (!isDarwin) pkgs.openssl;

            buildPhase = ''
              mkdir -p obj/${default-compactc-target}
              sed -e 's;/usr/bin/env .*;'`command -v scheme`' --program;' compiler/compactc.ss > obj/${default-compactc-target}/compactc.ss
              sed -e 's;/usr/bin/env .*;'`command -v scheme`' --program;' compiler/format-compact.ss > obj/${default-compactc-target}/format-compact.ss
              sed -e 's;/usr/bin/env .*;'`command -v scheme`' --program;' compiler/fixup-compact.ss > obj/${default-compactc-target}/fixup-compact.ss
              patchShebangs --host .

              scheme -q << END
                (reset-handler abort)
                (optimize-level 2)
                (compile-imported-libraries #t)
                (generate-wpo-files #t)
                (generate-inspector-information #f)
                (compile-profile #f)
                (compile-program "obj/${default-compactc-target}/compactc.ss" "obj/${default-compactc-target}/compactc.so")
                (compile-program "obj/${default-compactc-target}/format-compact.ss" "obj/${default-compactc-target}/format-compact.so")
                (compile-program "obj/${default-compactc-target}/fixup-compact.ss" "obj/${default-compactc-target}/fixup-compact.so")
                (compile-whole-program "obj/${default-compactc-target}/compactc.wpo" "obj/compactc")
                (compile-whole-program "obj/${default-compactc-target}/format-compact.wpo" "obj/format-compact")
                (compile-whole-program "obj/${default-compactc-target}/fixup-compact.wpo" "obj/fixup-compact")
              END
            '';

            # check if the code was build correctly
            checkPhase = ''
              cp -r ${packages.runtime.node-modules}/node_modules node_modules
              chmod -R +rw node_modules
              mkdir -p node_modules/@midnight-ntwrk
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

          # compactc built for a target in compiler/targets/ (see compiler.md, "Adding a
          # target").  The target is chosen by the target directory on the library path,
          # so this only differs from packages.compactc in that path.  The packages
          # packages.compactc-<target> are generated from this, for every directory in
          # compiler/targets/, below.
          lib.compactc-for-target = target: packages.compactc.overrideAttrs (oldAttrs: {
            name = "compactc-${target}";
            CHEZSCHEMELIBDIRS = builtins.replaceStrings [default-compactc-target] [target] oldAttrs.CHEZSCHEMELIBDIRS;
          });

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
              ./compiler
              ./examples
              ./flake.nix
              ./runtime/extract-version.ss
              ./runtime/package.json
              ./srcMaps
              ./test-center
              ./third_party/compiler
            ];

            CHEZSCHEMELIBDIRS = "compiler::obj/${default-compactc-target}:compiler/targets/${default-compactc-target}::obj/${default-compactc-target}:third_party/compiler::obj/third_party/compiler:${nanopass}::obj/nanopass:${rough-draft}/src::obj/rough-draft:srcMaps::obj/srcMaps::obj/${default-compactc-target}";

            buildInputs = [
              chez-exe
            ] ++ platformSpecificInputs;

            buildPhase = ''
              mkdir -p obj/${default-compactc-target}

              sed -e 's;/usr/bin/env .*;'`command -v scheme`' --program;' compiler/compactc.ss > obj/${default-compactc-target}/compactc.ss
              sed -e 's;/usr/bin/env .*;'`command -v scheme`' --program;' compiler/format-compact.ss > obj/${default-compactc-target}/format-compact.ss
              sed -e 's;/usr/bin/env .*;'`command -v scheme`' --program;' compiler/fixup-compact.ss > obj/${default-compactc-target}/fixup-compact.ss

              compile-chez-program --optimize-level 2 obj/${default-compactc-target}/compactc.ss
              compile-chez-program --optimize-level 2 obj/${default-compactc-target}/format-compact.ss
              compile-chez-program --optimize-level 2 obj/${default-compactc-target}/fixup-compact.ss
            '';

            installPhase = ''
              mkdir -p $out/bin

              for exe in compactc format-compact fixup-compact; do
                cp "obj/${default-compactc-target}/$exe" $out/bin
                chmod +x "$out/bin/$exe"
              done
            '' + (if isDarwin then ''
              for exe in compactc format-compact fixup-compact; do
                install_name_tool -change ${pkgs.darwin.libiconv}/lib/libiconv.2.dylib /usr/lib/libiconv.2.dylib "$out/bin/$exe"
              done
            '' else "");
          };

          # The upstream zkir-v3 package produces bin/zkir (same name as
          # zkir v2).  Wrap it so the binary is available as bin/zkir-v3,
          # which is the name the compiler invokes.
          packages.zkir-v3-bin = pkgs.runCommand "zkir-v3-bin" {} ''
            mkdir -p $out/bin
            ln -s ${zkir-v3.packages.${system}.zkir}/bin/zkir $out/bin/zkir-v3
          '';

          packages.compactc-binaryWrapperScript-nixos = pkgs.writeShellScriptBin "run-compactc" ''
            PATH=${pkgs.lib.makeBinPath [ packages.compactc-binary-nixos packages.zkir-v3-bin ]} \
            compactc $@
          '';

          packages.compactc-binary = pkgs.stdenv.mkDerivation {
            name = "compactc-binary-dist";
            version = "0.0.1";
            src = packages.compactc-binary-nixos;

            installPhase = ''
              mkdir -p $out/bin $out/lib
              cp bin/compactc $out/bin
              mv $out/bin/compactc $out/bin/compactc.bin
              cp ${zkir-v3.packages.${system}.zkir}/bin/zkir $out/lib/zkir-v3

              chmod +w $out/lib/zkir-v3

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
            '' + (if isDarwin then ''
              install_name_tool -change ${inputs.zkir-v3.inputs.nixpkgs.legacyPackages.${system}.darwin.libiconv}/lib/libiconv.2.dylib /usr/lib/libiconv.2.dylib "$out/lib/zkir-v3"
            '' else "");

            dontFixup = true;
          };

          # The release binary (see packages.compactc-binary) built for a target in
          # compiler/targets/.  The release workflows build packages.compactc-binary-<target>
          # for every directory in compiler/targets/; those packages are generated from
          # this, below.
          lib.compactc-binary-for-target = target: packages.compactc-binary.overrideAttrs (oldAttrs: {
            name = "compactc-binary-dist-${target}";
            src = packages.compactc-binary-nixos.overrideAttrs (nixosAttrs: {
              name = "compactc-binary-nixos-${target}";
              CHEZSCHEMELIBDIRS = builtins.replaceStrings [default-compactc-target] [target] nixosAttrs.CHEZSCHEMELIBDIRS;
            });
          });

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
                  zkir-v3-bin
                ]}"
              ];
            };
            layers = [
              (nix2container.buildLayer {
                deps = [
                  compactc
                  zkir-v3-bin
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
              CHEZSCHEMELIBDIRS = "${nanopass}::obj/nanopass:${rough-draft}/src::obj/rough-draft:srcMaps::obj/srcMaps:compiler::obj/${default-compactc-target}:compiler/targets/${default-compactc-target}::obj/${default-compactc-target}:third_party/compiler::obj/third_party/compiler";

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
              packages.zkir-v3-bin
              packages.compact-vscode-extension
            ];
          };

          packages.default = packages.all;

          devShells.default = pkgs.mkShell {
            inputsFrom = with packages; [compactc];
            packages = [
              pkgs.git
              pkgs.nodejs
              pkgs.yarn
              pkgs.alejandra
              packages.runtime.package
              packages.runtime.node-modules
              packages.test-center.package
              packages.test-center.node-modules
            ];
            shellHook = combined-shell-hook;

            DEFAULTCOMPACTCTARGET = "${default-compactc-target}";
            CHEZSCHEMELIBDIRS = "compiler::obj/${default-compactc-target}:compiler/targets/${default-compactc-target}::obj/${default-compactc-target}:third_party/compiler::obj/third_party/compiler:${nanopass}::obj/nanopass:${rough-draft}/src::obj/rough-draft:srcMaps::obj/srcMaps";
            COMPACT_LIBCRYPTO = libcrypto;
            WASM_BINDGEN_WEAKREF = 1;
            WASM_BINDGEN_EXTERNREF = 1;
          };

          devShells.with-zkir = packages.runtime.mkShell {
            inputsFrom = with packages; [compactc];
            packages = [
              pkgs.git
              pkgs.nodejs
              pkgs.yarn
              pkgs.binaryen
              packages.runtime.package
              packages.runtime.node-modules
              packages.test-center.package
              packages.test-center.node-modules
              packages.zkir-v3-bin
            ];
            shellHook = combined-shell-hook;

            CHEZSCHEMELIBDIRS = "compiler::obj/${default-compactc-target}:compiler/targets/${default-compactc-target}::obj/${default-compactc-target}:third_party/compiler::obj/third_party/compiler:${nanopass}::obj/nanopass:${rough-draft}/src::obj/rough-draft:srcMaps::obj/srcMaps";
            COMPACT_LIBCRYPTO = libcrypto;
          };

          devShells.compiler = pkgs.mkShell {
            inputsFrom = with packages; [compactc];
            packages = [
              pkgs.git
              packages.compactc
              pkgs.yarn
              packages.zkir-v3-bin
            ];

            CHEZSCHEMELIBDIRS = "compiler::obj/${default-compactc-target}:compiler/targets/${default-compactc-target}::obj/${default-compactc-target}:third_party/compiler::obj/third_party/compiler:${nanopass}::obj/nanopass:${rough-draft}/src::obj/rough-draft:srcMaps::obj/srcMaps";
            COMPACT_LIBCRYPTO = libcrypto;
          };
          devShells.test-contracts = pkgs.mkShell {
            inputsFrom = with packages; [compactc];
            packages = [
              packages.compactc
              packages.runtime.package
              pkgs.yarn
              packages.zkir-v3-bin
            ];

            COMPACT_RUNTIME_PKG = "${packages.runtime.package}/lib/node_modules/@midnight-ntwrk/compact-runtime";
            CHEZSCHEMELIBDIRS = "compiler::obj/${default-compactc-target}:compiler/targets/${default-compactc-target}::obj/${default-compactc-target}:third_party/compiler::obj/third_party/compiler:${nanopass}::obj/nanopass:${rough-draft}/src::obj/rough-draft:srcMaps::obj/srcMaps";
            COMPACT_LIBCRYPTO = libcrypto;
          };

          devShells.runtime = packages.runtime.mkShell {
            packages = [
              pkgs.git
              pkgs.nodejs
              pkgs.chez
            ];
            shellHook = runtime-shell-hook;
          };

          devShells.dapp = packages.runtime.mkShell {
            packages = [
              pkgs.git
              packages.compactc
              packages.runtime.package
              packages.runtime.node-modules
              packages.zkir-v3-bin
              pkgs.nodejs
              pkgs.yarn
            ];
            shellHook = runtime-shell-hook;
          };

          formatter = pkgs.alejandra;
          };
        in
          outputs // { packages = outputs.packages // target-packages; }
    );
}
