mod command_line_arguments;
mod compact_directory;
mod compiler;
mod compiler_legacy;
mod console;
pub mod fetch;
pub mod file;
pub mod http;
pub mod progress;
pub mod utils;

pub use self::{
    command_line_arguments::{
        Command, CommandLineArguments, CompactUpdateConfig, ListCommand, SSelf, Target,
        UpdateCommand,
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
