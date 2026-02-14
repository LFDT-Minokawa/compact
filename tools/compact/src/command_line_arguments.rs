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

use crate::{
    compact_directory::CompactDirectory,
    console::{Icons, Style},
};
use anyhow::bail;
use clap::{Args, Parser, Subcommand, ValueEnum};
use semver::Version;
use std::{fmt, str::FromStr};

const ADDITIONAL_HELP: &str = r###"
Additional Commands:

* `compile [+VERSION] [ARGS...]': call the compiler for the given `VERSION'.

Usage examples:

  `compact compile source/path target/path`

  `compact compile +0.21.0 --help`

"###;

/// The Compact command-line tool provides a set of utilities for Compact smart
/// contract development.
#[derive(Debug, Clone, Parser)]
#[clap(version)]
#[command(after_help = ADDITIONAL_HELP)]
pub struct CommandLineArguments {
    /// Set the target
    ///
    /// This option exists to allow testing different configurations. We do not
    /// recommend changing it.
    #[arg(value_enum, long, hide = true, default_value_t)]
    pub target: Target,

    /// Set the compact artifact directory
    ///
    /// By default this will be `$HOME/.compact`. The directory will be created
    /// if it does not exist. This can also be configured via an environment
    /// variable.
    #[arg(
        long,
        env = "COMPACT_DIRECTORY",
        global = true,
        default_value_t,
        verbatim_doc_comment
    )]
    pub directory: CompactDirectory,

    #[command(subcommand)]
    pub command: Command,

    #[arg(skip)]
    pub style: Style,

    #[arg(skip)]
    pub icons: Icons,
}

#[derive(Debug, Clone, Args)]
pub struct CompactUpdateConfig {}

/// list of available commands
#[derive(Debug, Clone, Subcommand)]
pub enum Command {
    /// Check for updates with the remote server
    Check(CheckCommand),

    /// Update to the latest or a specific version of the Compact toolchain
    ///
    /// This is the command you use to switch from one version to another
    /// by default this will make the command switch the default compiler
    /// version to the installed one.
    ///
    /// If the compiler was already downloaded it is not downloaded again
    #[command(verbatim_doc_comment)]
    Update(UpdateCommand),

    Format(FormatCommand),

    Fixup(FixupCommand),

    List(ListCommand),

    Clean(CleanCommand),

    #[command(name = "self", subcommand)]
    SSelf(SSelf),

    #[command(external_subcommand)]
    ExternalCommand(Vec<String>),
}

/// Check for updates with the remote server
#[derive(Debug, Clone, Args)]
#[command(version)]
pub struct CheckCommand {}

#[derive(Debug, Clone, Args)]
#[command(version)]
pub struct UpdateCommand {
    /// Version to install, e.g. 0.29 or 0.29.0
    #[arg(id = "COMPACT_VERSION")]
    pub version: Option<VersionSpec>,

    /// Don't make the newly installed compiler the default one
    #[arg(long, default_value_t = false)]
    pub no_set_default: bool,

    #[command(flatten)]
    pub config: CompactUpdateConfig,
}

/// A version specifier that is either an exact semver version or a
/// partial `major.minor` prefix that resolves to the latest patch.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VersionSpec {
    Exact(Version),
    Partial { major: u64, minor: u64 },
}

impl VersionSpec {
    /// True when this is an exact `major.minor.patch` specifier.
    pub fn as_exact(&self) -> Option<&Version> {
        match self {
            VersionSpec::Exact(v) => Some(v),
            VersionSpec::Partial { .. } => None,
        }
    }

    /// True when `version` matches this specifier.
    pub fn matches(&self, version: &Version) -> bool {
        match self {
            VersionSpec::Exact(v) => v == version,
            VersionSpec::Partial { major, minor } => {
                version.major == *major && version.minor == *minor
            }
        }
    }
}

impl FromStr for VersionSpec {
    type Err = semver::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        if let Ok(version) = Version::parse(s) {
            return Ok(VersionSpec::Exact(version));
        }

        // Try parsing as "major.minor"
        let parts: Vec<&str> = s.split('.').collect();
        if parts.len() == 2 {
            if let (Ok(major), Ok(minor)) = (parts[0].parse::<u64>(), parts[1].parse::<u64>()) {
                return Ok(VersionSpec::Partial { major, minor });
            }
        }

        // Fall back to semver error for the original input
        Version::parse(s).map(VersionSpec::Exact)
    }
}

impl fmt::Display for VersionSpec {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            VersionSpec::Exact(v) => v.fmt(f),
            VersionSpec::Partial { major, minor } => {
                write!(f, "{major}.{minor}")
            }
        }
    }
}

/// Format compact files
#[derive(Debug, Clone, Args)]
pub struct FormatCommand {
    /// Files to format
    #[clap(default_value = ".")]
    pub files: Vec<String>,

    /// Check if inputs are formatted without changing them
    #[clap(short, long)]
    pub check: bool,

    /// Print each file seen by the formatter
    #[clap(short, long)]
    pub verbose: bool,

    /// Print the toolchain version
    #[clap(short = 'V', long)]
    pub version: bool,

    /// Print the language version
    #[clap(long)]
    pub language_version: bool,
}

/// Apply fixup transformations to compact files
#[derive(Debug, Clone, Args)]
pub struct FixupCommand {
    /// Files or directories to fixup
    #[clap(default_value = ".")]
    pub files: Vec<String>,

    /// Check if inputs need fixup without changing them
    #[clap(short, long)]
    pub check: bool,

    /// Adjust Uint range endpoints
    #[clap(long = "update-Uint-ranges")]
    pub update_uint_ranges: bool,

    /// Format error messages as single line (for VS Code extension)
    #[clap(long)]
    pub vscode: bool,

    /// Print verbose output
    #[clap(short, long)]
    pub verbose: bool,

    /// Print the toolchain version
    #[clap(short = 'V', long)]
    pub version: bool,

    /// Print the language version
    #[clap(long)]
    pub language_version: bool,
}

/// List available compact versions
#[derive(Debug, Clone, Args)]
#[command(version)]
pub struct ListCommand {
    /// Show installed versions
    #[arg(long, short, default_value_t = false)]
    pub installed: bool,
}

/// Remove all compact versions
#[derive(Debug, Clone, Args)]
#[command(version)]
pub struct CleanCommand {
    /// Keep the version currently in use
    #[arg(long, short, default_value_t = false)]
    pub keep_current: bool,

    /// Also remove the cache directory
    #[arg(long, default_value_t = false)]
    pub cache: bool,
}

/// Commands for managing the compact tool itself
#[derive(Debug, Clone, Subcommand)]
#[command(version)]
pub enum SSelf {
    /// Check for updates to the compact tool itself
    Check,
    /// Update to the latest version of the tool itself
    Update,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, ValueEnum)]
#[allow(non_camel_case_types)]
pub enum Target {
    #[cfg_attr(all(target_os = "linux", target_arch = "x86_64"), default)]
    #[value(name = "x86_64-unknown-linux-musl")]
    x86_64UnknownLinuxMusl,

    #[cfg_attr(all(target_os = "macos", target_arch = "x86_64"), default)]
    #[value(name = "x86_64-apple-darwin")]
    x86_64AppleDarwin,

    #[cfg_attr(all(target_os = "macos", target_arch = "aarch64"), default)]
    #[value(name = "aarch64-darwin")]
    Aarch64AppleDarwin,
}

impl fmt::Display for Target {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Target::x86_64UnknownLinuxMusl => "x86_64-unknown-linux-musl".fmt(f),
            Target::x86_64AppleDarwin => "x86_64-apple-darwin".fmt(f),
            Target::Aarch64AppleDarwin => "aarch64-darwin".fmt(f),
        }
    }
}

impl FromStr for Target {
    type Err = anyhow::Error;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "x86_64-apple-darwin" => Ok(Self::x86_64AppleDarwin),
            "aarch64-darwin" => Ok(Self::Aarch64AppleDarwin),

            "x86_64-unknown-linux-musl" => Ok(Self::x86_64UnknownLinuxMusl),

            unknown => bail!("Unsupported target `{unknown}'"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_exact_version() {
        let spec: VersionSpec = "0.29.0".parse().unwrap();
        assert_eq!(spec, VersionSpec::Exact(Version::new(0, 29, 0)));
        assert_eq!(spec.to_string(), "0.29.0");
    }

    #[test]
    fn parse_partial_version() {
        let spec: VersionSpec = "0.29".parse().unwrap();
        assert_eq!(
            spec,
            VersionSpec::Partial {
                major: 0,
                minor: 29
            }
        );
        assert_eq!(spec.to_string(), "0.29");
    }

    #[test]
    fn parse_invalid_version() {
        assert!("bob".parse::<VersionSpec>().is_err());
        assert!("".parse::<VersionSpec>().is_err());
        assert!("abc.def".parse::<VersionSpec>().is_err());
    }

    #[test]
    fn exact_matches_itself() {
        let spec = VersionSpec::Exact(Version::new(0, 29, 1));
        assert!(spec.matches(&Version::new(0, 29, 1)));
        assert!(!spec.matches(&Version::new(0, 29, 0)));
        assert!(!spec.matches(&Version::new(0, 28, 1)));
    }

    #[test]
    fn partial_matches_any_patch() {
        let spec = VersionSpec::Partial {
            major: 0,
            minor: 29,
        };
        assert!(spec.matches(&Version::new(0, 29, 0)));
        assert!(spec.matches(&Version::new(0, 29, 1)));
        assert!(spec.matches(&Version::new(0, 29, 99)));
        assert!(!spec.matches(&Version::new(0, 28, 0)));
        assert!(!spec.matches(&Version::new(1, 29, 0)));
    }

    #[test]
    fn as_exact_returns_version_for_exact() {
        let v = Version::new(1, 2, 3);
        let spec = VersionSpec::Exact(v.clone());
        assert_eq!(spec.as_exact(), Some(&v));
    }

    #[test]
    fn as_exact_returns_none_for_partial() {
        let spec = VersionSpec::Partial { major: 1, minor: 2 };
        assert_eq!(spec.as_exact(), None);
    }
}
