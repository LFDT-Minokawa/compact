use crate::{
    compact_directory::CompactDirectory,
    console::{Icons, Style},
};
use anyhow::bail;
use clap::{Args, Parser, Subcommand, ValueEnum};
use semver::Version;
use std::{fmt, path::PathBuf, str::FromStr};

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
#[clap(propagate_version = true)]
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
pub struct CompactUpdateConfig {
    /// Set the path to the `unzip` binary
    ///
    /// By default this will be the one found in the environmnent's `PATH`. This
    /// can also be configured via an environment variable.
    #[arg(
        long,
        env = "COMPACT_UNZIP",
        global = true,
        default_value = "unzip",
        verbatim_doc_comment
    )]
    pub unzip: PathBuf,
}

/// list of available commands
#[derive(Debug, Clone, Subcommand)]
pub enum Command {
    /// Check for updates with the remote server
    Check,

    /// Update to the latest or a specific version of the Compact toolchain
    ///
    /// This is the command you use to switch from one version to another
    /// by default this will make the command switch the default compiler
    /// version to the installed one.
    ///
    /// If the compiler was already downloaded it is not downloaded again
    #[command(verbatim_doc_comment)]
    Update(UpdateCommand),

    #[command(name = "self", subcommand)]
    SSelf(SSelf),

    List(ListCommand),

    #[command(external_subcommand)]
    ExternalCommand(Vec<String>),
}

#[derive(Debug, Clone, Args)]
pub struct UpdateCommand {
    /// Set the version to install
    #[arg(id = "COMPACT_VERSION")]
    pub version: Option<Version>,

    /// Don't make the newly installed compiler the default one
    #[arg(long, default_value_t = false)]
    pub no_set_default: bool,

    #[command(flatten)]
    pub config: CompactUpdateConfig,
}

/// List available compact versions
#[derive(Debug, Clone, Args)]
pub struct ListCommand {
    /// Show installed versions
    #[arg(long, short, default_value_t = false)]
    pub installed: bool,

    #[command(flatten)]
    pub config: CompactUpdateConfig,
}

/// Commands for managing the compact tool itself
#[derive(Debug, Clone, Subcommand)]
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
    #[value(name = "aarch64-apple-darwin")]
    Aarch64AppleDarwin,
}

impl fmt::Display for Target {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Target::x86_64UnknownLinuxMusl => "x86_64-unknown-linux-musl".fmt(f),
            Target::x86_64AppleDarwin => "x86_64-apple-darwin".fmt(f),
            Target::Aarch64AppleDarwin => "x86_64-apple-darwin".fmt(f),
        }
    }
}

impl FromStr for Target {
    type Err = anyhow::Error;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "x86_64-apple-darwin" => Ok(Self::x86_64AppleDarwin),
            "aarch64-apple-darwin" => Ok(Self::Aarch64AppleDarwin),

            "x86_64-unknown-linux-musl" => Ok(Self::x86_64UnknownLinuxMusl),

            unknown => bail!("Unsupported target `{unknown}'"),
        }
    }
}
