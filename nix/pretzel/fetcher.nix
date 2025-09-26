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
  overlay = authURLs: self: super: let
    inherit (super) lib;
  in {
    # Now I need someone to help me understand how this can be done better
    # 1. npmlock2nix uses a fetchurl from nixpkgs
    # 2. apparently it's builtins.fetchurl, which uses from nix config netrc, but it's only sha256 compatible
    # 3. yarn2nix (https://github.com/input-output-hk/yarn2nix) seems to use `import <nix/fetchurl.nix>` with success though
    fetchurl = args: let
      sanitizeNixArgs = let allowedNames = ["hash" "sha256" "name" "url"]; in (args: lib.attrsets.filterAttrs (name: value: builtins.elem name allowedNames) args);
    in
      lib.trivial.pipe args [
        (args: lib.attrsets.attrByPath ["url"] "" args)
        (url: lib.lists.any (authLocation: lib.strings.hasInfix authLocation url) authURLs)
        (needsAuth:
          if needsAuth
          then import <nix/fetchurl.nix> (sanitizeNixArgs args)
          else super.fetchurl args)
      ];
  };
}
