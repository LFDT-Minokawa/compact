#!/usr/bin/env bash

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

set -e  # Exit on any error

# Name of the IR
IR=$1

# Name of the serialization program
SERIALIZER="serialize.ss"

# Locatino of the compiler relative to the root of the compct
# repository
COMPILER_DIR="./compiler"

# Location of the syntax generation tool relative to the root of the
# compact repository
SYNTAX_GEN_DIR="./specification/syntax-generation"

# Relative path to the root of the compact repo
COMPACT_ROOT="../../"

JSON_PATH="./specification/src/Syntax/json/$IR.json"

 
# STAGE ONE: hook the serializer into the compiler, and serialize
# (all) specified IRs to a JSON file in the corresponding directory.
# Clean up afterwards. 
#


cp ./$SERIALIZER ../../$COMPILER_DIR/$SERIALIZER
cd $COMPACT_ROOT
sed -i -e "s/IR_SYMBOL/$IR/g" $COMPILER_DIR/$SERIALIZER
nix develop -c scheme --script $COMPILER_DIR/$SERIALIZER $IR $JSON_PATH
rm $COMPILER_DIR/$SERIALIZER
rm $COMPILER_DIR/$SERIALIZER-e
cd $SYNTAX_GEN_DIR


# STAGE TWO: Generate an Agda module based on the serialized JSON
# file.

echo "" 
cabal build
echo "" 
cabal exec syntax-generation $IR 
