// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// 	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

mod command_line_arguments;
mod compact_directory;
mod compiler;
mod compiler_legacy;
mod console;
pub mod fetch;
pub mod file;
pub mod fixup;
pub mod formatter;
pub mod http;
pub mod progress;
pub mod utils;

pub use self::{
    command_line_arguments::{
        CheckCommand, CleanCommand, Command, CommandLineArguments, CompactUpdateConfig,
        FixupCommand, FormatCommand, ListCommand, SSelf, Target, UpdateCommand,
    },
    compact_directory::CompactDirectory,
    compiler::Compiler,
};
use semver::Version;
use std::sync::LazyLock;

pub const COMPACT_NAME: &str = env!("CARGO_PKG_NAME");
pub static COMPACT_VERSION: LazyLock<Version> = LazyLock::new(|| {
    env!("CARGO_PKG_VERSION")
        .parse()
        .expect("CARGO_PKG_VERSION failed to parse properly. This is a bug and should be reported.")
});
