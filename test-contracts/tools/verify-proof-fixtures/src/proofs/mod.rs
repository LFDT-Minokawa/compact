// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! The inner statements the `stdlib/verify_proof/` fixtures verify.
//!
//! Each is a midnight-zk relation exposing `Circuit`, `instance()` and
//! `witness()`. Adding one means a module here and a line in `generate_all`.

use std::path::Path;

pub mod basic;

/// Rebuilds every inner proof into `out_dir`, one bundle per circuit.
pub fn generate_all(out_dir: &Path) {
    crate::generate::<basic::Circuit>("basic", out_dir, &basic::instance(), basic::witness());
}
