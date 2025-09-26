use anyhow::{anyhow, Context, Result};
use reqwest::Url;
use semver::Version;
use std::{
    path::{Path, PathBuf},
    process::Stdio,
};
use tokio::process::Command;

pub struct CompilerAsset {
    pub path: PathBuf,
    pub asset: octocrab::models::repos::Asset,
    pub version: Version,
}

impl CompilerAsset {
    fn path_zip(&self) -> PathBuf {
        self.path.join("artifact.zip")
    }
    fn path_compactc(&self) -> PathBuf {
        self.path.join("compactc")
    }

    pub fn exist(&self) -> bool {
        self.path_compactc().is_file()
    }

    pub fn download_url(&self) -> &Url {
        &self.asset.browser_download_url
    }

    pub async fn unzip(&self, program: impl AsRef<Path>) -> Result<()> {
        let program = program.as_ref();
        let cwd = &self.path;

        let mut cmd = Command::new(program);

        // execute the unzip command in the artifact directory
        cmd.current_dir(cwd);
        cmd.arg(self.path_zip());

        // capture the StdOut and StdErr
        cmd.stdout(Stdio::piped());
        cmd.stderr(Stdio::piped());

        // don't allow StdIn, we don't have anything to pass in the standard
        // input and we don't want it to be inherited
        cmd.stdin(Stdio::null());

        let child = cmd
            .spawn()
            .context("Failed to spawn artifact extraction command")?;

        let output = child
            .wait_with_output()
            .await
            .context("Failed to execute the artifact extraction command")?;
        let status = output.status;
        if !status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            Err(anyhow!("Stderr: {stderr}"))
                .with_context(|| anyhow!("Status: {status}"))
                .with_context(|| anyhow!("Command={program:?} CWD={cwd:?}"))
                .context("artifact Extraction failed")
        } else {
            Ok(())
        }
    }
}
