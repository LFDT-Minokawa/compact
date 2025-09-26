use std::{io::ErrorKind, path::Path};

use crate::{compiler::Compiler, CommandLineArguments, Target};
use anyhow::{anyhow, ensure, Context, Result};
use semver::Version;
use tokio::fs;

async fn initialise_directory(path: impl AsRef<Path>) -> Result<()> {
    let path = path.as_ref();

    if !path.is_dir() {
        fs::create_dir_all(&path)
            .await
            .with_context(|| anyhow!("Failed to create compact directory: {path:?}",))?
    }

    Ok(())
}

pub async fn initialise_directories(cfg: &CommandLineArguments) -> Result<()> {
    let bin_dir = cfg.directory.bin_dir();
    let versions_dir = cfg.directory.versions_dir();

    initialise_directory(bin_dir).await?;
    initialise_directory(versions_dir).await?;

    Ok(())
}

#[cfg(unix)]
pub async fn set_current_compiler(
    cfg: &CommandLineArguments,
    compiler: &Compiler,
) -> Result<Compiler> {
    let source = compiler.path_compactc().to_path_buf();
    let target = cfg.directory.bin_dir().join("compactc");

    if target.is_symlink() {
        fs::remove_file(&target)
            .await
            .with_context(|| anyhow!("Failed to remove previous symlink {target:?}"))?;
    }

    fs::symlink(&source, &target).await.with_context(|| {
        anyhow!(
            "Failed to create symlink from {target:?} {arrow} {source:?}",
            arrow = console::Emoji::new("→", "to")
        )
    })?;

    let new = get_current_compiler(cfg)
        .await?
        .ok_or_else(|| anyhow!("Failed to validate installed default compiler"))?;

    ensure!(
        new.version() == compiler.version(),
        "Installation failed, the default compiler is still set to older version {}",
        new.version()
    );

    Ok(new)
}

pub async fn get_current_compiler(cfg: &CommandLineArguments) -> Result<Option<Compiler>> {
    let bin = cfg.directory.bin_dir().join("compactc");

    let file = match fs::read_link(&bin).await {
        Ok(file) => {
            ensure!(file.is_file(), "Expecting a file: `{file:?}'");
            file
        }
        Err(error) if error.kind() == ErrorKind::NotFound => {
            return Ok(None);
        }
        reason => reason.with_context(|| anyhow!("Failed to read symbolic link: `{bin:?}'"))?,
    };

    // we expect the path to have a precise construction
    // <compact_directory> / versions / <version> / <target> / compactc

    let parent = file
        .parent()
        .ok_or_else(|| anyhow!("Couldn't read target parent directory ({file:?})"))?
        .to_path_buf();
    let target: Target = parent
        .file_name()
        .ok_or_else(|| anyhow!("Couldn't extract the target parent directory ({parent:?})"))?
        .to_string_lossy()
        .parse()
        .with_context(|| anyhow!("Couldn't parse the target parent directory ({parent:?})"))?;

    let parent = parent
        .parent()
        .ok_or_else(|| anyhow!("Couldn't read version parent directory ({parent:?})"))?
        .to_path_buf();
    let version: Version = parent
        .file_name()
        .ok_or_else(|| anyhow!("Couldn't extract the version parent directory ({parent:?})"))?
        .to_string_lossy()
        .parse()
        .with_context(|| anyhow!("Couldn't parse the version parent directory ({parent:?})"))?;

    Compiler::open(cfg, version, target).await.map(Some)
}
