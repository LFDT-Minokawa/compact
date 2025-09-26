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
  lib,
  npmlock2nix,
  dry-install
}: let
  overlay = self: super: {
    npmlock2nix = self.callPackage npmlock2nix {
      pkgs = self;
    };
    nodejs-16_x = super.nodejs;
  };
  loadPackageMeta = {src}: let
    packageJson = lib.importJSON (src + "/package.json");
    packageName = packageJson.name;
    packageVersion = packageJson.version;
    tarName = lib.trivial.pipe packageName [
      (name: builtins.replaceStrings ["@" "/"] ["" "-"] packageName)
      (name: name + "-" + packageVersion)
      (withDashes: withDashes + ".tgz")
    ];
    binsToInstall =
      if (packageJson ? bin) && builtins.isString (packageJson.bin)
      then [
        {
          name = lib.trivial.pipe packageName [(builtins.split "/") (lib.lists.last)];
          path = packageJson.bin;
        }
      ]
      else [];
  in {
    inherit tarName binsToInstall;
    name = packageName;
    version = packageVersion;
    json = packageJson;
    nixDependencies =
      if packageJson ? nixDependencies
      then packageJson.nixDependencies
      else [];
    nixDevDependencies =
      if packageJson ? nixDevDependencies
      then packageJson.nixDevDependencies
      else [];
  };
  mkPackage = {
    pkgs,
    src,
    nixDependenciesMap ? {},
    overrideBuildAttrs ? { common = lib.trivial.id; package = lib.trivial.id; tests = lib.trivial.id; lints = lib.trivial.id; }
  }: let
    inherit (pkgs) nodejs;
    overriders = lib.trivial.pipe ["common" "package" "tests" "lints"] [
      (builtins.map (name: let fn = lib.attrsets.attrByPath [name] (lib.trivial.id) overrideBuildAttrs; in {
        inherit name;
        value = fn;
      }))
      (builtins.listToAttrs)
    ];
    npml = pkgs.npmlock2nix;
    node-modules-attrs = {
      inherit nodejs;
      src =
        (lib.sources.cleanSourceWith {
          inherit src;
          filter = let
            allowedFiles = ["package.json" "package-lock.json"];
            checkPath = path: lib.lists.any (allowed: lib.strings.hasSuffix allowed path) allowedFiles;
          in (path: type: checkPath path);
        })
        .outPath;
    };
    packageMeta = loadPackageMeta {
      inherit (node-modules-attrs) src;
    };
    installBins = let
      installBin = {
        name,
        path,
      }: "ln -s  $targetDir/${path} $out/bin/${name}";
    in
      lib.trivial.pipe packageMeta.binsToInstall [(map installBin) (lib.strings.intersperse "\n") (lib.strings.concatStrings)];
    raw-node-modules = lib.trivial.pipe (npml.v2.node_modules node-modules-attrs) [(original: original // {packagesPublishFile = original.packagesfile;})];
    patched-node-modules = pkgs.stdenv.mkDerivation (final: let
      collectDeps = type: list:
        lib.trivial.pipe list [
          (depNames: lib.attrsets.attrVals depNames nixDependenciesMap)
          (map (pkg: {
            inherit type;
            dir = pkg.libPath;
            tar = pkg.tarPath;
          }))
        ];
      deps = lib.trivial.pipe [] [
        (deps: deps ++ (collectDeps "dev" packageMeta.nixDevDependencies))
        (deps: deps ++ (collectDeps "prod" packageMeta.nixDependencies))
        (builtins.toJSON)
        (pkgs.writeText "deps.json")
      ];
    in {
      name = packageMeta.name + "_" + packageMeta.version + "_" + "node_modules";
      src = node-modules-attrs.src;
      buildInputs = [ dry-install ];
      buildPhase = ''
        NODE_ENV='dev'
        echo '${deps}'
        install -m 666 ${raw-node-modules.packagesfile} ./package.json
        install -m 666 ${raw-node-modules.lockfile} ./package-lock.json
        HOME=. dry-install --to $(pwd) --deps ${deps}
        HOME=. npm ci --ignore-scripts
      '';
      installPhase = ''
        mkdir -p $out
        cp -r ./* $out/
      '';
      passthru = {
        packagesfile = final.finalPackage + "/package.json";
        packagesPublishFile = final.finalPackage + "/package-publish.json";
        lockfile = final.finalPackage + "/package-lock.json";
      };
    });
    # In this way dry-install itself can be built with pretzel
    node-modules = (
      if (packageMeta.nixDependencies == [] && packageMeta.nixDevDependencies == [])
      then raw-node-modules
      else patched-node-modules
    );
    shellHook = npml.v2.internal.add_node_modules_to_cwd node-modules "symlink";
    package = pkgs.stdenv.mkDerivation (final: let
      libPath = final.finalPackage + "/lib/node_modules/" + packageMeta.name;
      buildDefinition = {
        inherit src;

        name = lib.strings.sanitizeDerivationName "${packageMeta.name}_${packageMeta.version}";

        propagatedBuildInputs = [nodejs];

        configurePhase = shellHook;

        installPhase = ''
          targetDir="$out/lib/node_modules/${packageMeta.name}"
          mkdir -p $targetDir
          mkdir -p $out/bin
          cp ./${packageMeta.tarName} $out/lib
          rm -rf ./.npm
          rm -rf ./${packageMeta.tarName}
          cp -r . $targetDir
          cp ${node-modules.packagesfile} $targetDir/package.json
          cp ${node-modules.lockfile} $targetDir/package-lock.json
          ${installBins}
        '';

        buildPhase = ''
          cp -f ${node-modules.lockfile} package-lock.json
          cp -f ${node-modules.packagesfile} package.json
          HOME=. npm --ddd --offline pack
        '';

        passthru = {
          inherit libPath node-modules;
          packageName = packageMeta.name;
          tarPath = final.finalPackage + "/lib/" + packageMeta.tarName;
          lockFile = libPath + "/package-lock.json";
          packageFile = libPath + "/package.json";
        };
      };
    in
      lib.trivial.pipe buildDefinition [
        (overriders.common)
        (overriders.package)
      ]);
    forPublish = pkgs.stdenv.mkDerivation {
      inherit src;
      name = lib.strings.sanitizeDerivationName "${packageMeta.name}_${packageMeta.version}_publish";
      buildInputs = [package node-modules];
      installPhase = ''
        targetDir="$out/lib/node_modules/${packageMeta.name}"
        mkdir -p $targetDir

        # https://superuser.com/questions/26586/copy-directory-contents-using-cp-command
        cp -r ${package.libPath}/. $targetDir
        cp -f ${node-modules.packagesPublishFile} $targetDir/package.json
      '';
    };
    tests = lib.trivial.pipe {
      inherit src;
      name = lib.strings.sanitizeDerivationName "${packageMeta.name}_${packageMeta.version}_tests";
      buildInputs = [nodejs];
      configurePhase = shellHook;
      installPhase = ":";
      buildPhase = ''
        mkdir -p $out/log
        HOME=. npm run test
      '';

      passthru = {
        inherit node-modules;
        packageName = packageMeta.name;
      };
    } [
      (overriders.common)
      (overriders.tests) 
      (pkgs.stdenv.mkDerivation)
    ];
    lints = lib.trivial.pipe {
      inherit src;
      name = lib.strings.sanitizeDerivationName "${packageMeta.name}_${packageMeta.version}_lints";
      buildInputs = [nodejs];
      configurePhase = shellHook;
      installPhase = ":";
      buildPhase = ''
        mkdir -p $out/log
        HOME=. npm run lint
      '';
      passthru = {
        inherit node-modules;
        packageName = packageMeta.name;
      };
    } [
      (overriders.common)
      (overriders.lints) 
      (pkgs.stdenv.mkDerivation)
    ];
  in {
    inherit node-modules nodejs package lints tests forPublish;
    checked = pkgs.symlinkJoin {
      name = lib.strings.sanitizeDerivationName "${packageMeta.name}_${packageMeta.version}_checked";
      paths = [package lints tests];
      passthru = {
        inherit node-modules;
        inherit (package) tarPath lockFile packageFile libPath;
        packageName = packageMeta.name;
      };
    };
    meta = packageMeta.json;
    mkShell = args:
      pkgs.mkShell (args
        // {
          packages = [nodejs] ++ (lib.attrsets.attrByPath ["packages"] [] args);
          buildInputs = [node-modules] ++ (lib.attrsets.attrByPath ["buildInputs"] [] args);
          shellHook = shellHook + (lib.attrsets.attrByPath ["shellHook"] "" args);
        });
  };
in {
  inherit mkPackage overlay;
}
