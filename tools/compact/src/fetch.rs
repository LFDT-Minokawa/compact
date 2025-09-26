use crate::{
    compact_directory::COMPACTUP_VERSIONS_DIR, compiler_legacy::CompilerAsset,
    CommandLineArguments, Target,
};
use anyhow::{anyhow, bail, Context, Result};
use octocrab::models::repos::Asset;
use semver::Version;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Default, PartialEq, Deserialize, Serialize)]
pub struct MidnightArtifacts {
    pub compilers: BTreeMap<Version, MidnightCompiler>,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub struct MidnightCompiler {
    pub version: Version,
    pub macos: Asset,
    pub linux: Asset,
}

impl MidnightArtifacts {
    pub async fn load() -> Result<Self> {
        let compilers = load_compiler_versions()
            .await
            .context("Failed to load the compiler artifacts")?;

        Ok(Self { compilers })
    }
}

impl MidnightCompiler {
    pub fn compiler(&self, cfg: &CommandLineArguments) -> CompilerAsset {
        let asset = match cfg.target {
            Target::x86_64UnknownLinuxMusl => self.linux.clone(),
            Target::Aarch64AppleDarwin => self.macos.clone(),
            Target::x86_64AppleDarwin => self.macos.clone(),
        };

        let path = cfg
            .directory
            .join(COMPACTUP_VERSIONS_DIR)
            .join(self.version.to_string())
            .join(cfg.target.to_string());

        CompilerAsset {
            path,
            asset,
            version: self.version.clone(),
        }
    }
}

async fn load_compiler_versions() -> Result<BTreeMap<Version, MidnightCompiler>> {
    let octocrab = octocrab::instance();

    let releases = octocrab
        .repos("midnightntwrk", "compact")
        .releases()
        .list()
        .send()
        .await
        .with_context(|| anyhow!("Error while fetching compact releases"))?;

    let mut output = BTreeMap::new();

    for entry in releases {
        let compiler = load_compiler_version(entry).await?;

        output.insert(compiler.version.clone(), compiler);
    }

    Ok(output)
}

async fn load_compiler_version(dir: octocrab::models::repos::Release) -> Result<MidnightCompiler> {
    let version = dir
        .tag_name
        .strip_prefix("compactc-v")
        .ok_or_else(|| anyhow!("Invalid version format: {}", dir.tag_name))?
        .parse::<Version>()
        .with_context(|| anyhow!("Failed to parse artifact version: {}", dir.tag_name))?;

    let mut macos = None;
    let mut linux = None;

    for asset in dir.assets {
        if asset.name.contains("apple-darwin") {
            macos = Some(asset);
        } else if asset.name.contains("linux") {
            linux = Some(asset);
        } else {
            bail!("Unsupported compiler platform: {}", asset.name)
        }
    }

    let macos = macos.ok_or_else(|| anyhow!("Expecting a MacOS platform version"))?;
    let linux = linux.ok_or_else(|| anyhow!("Expecting a Linux platform version"))?;

    Ok(MidnightCompiler {
        version,
        macos,
        linux,
    })
}
