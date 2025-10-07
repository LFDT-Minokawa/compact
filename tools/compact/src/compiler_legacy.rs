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

use anyhow::{Context, Result, anyhow};
use reqwest::Url;
use semver::Version;
use std::{path::PathBuf, process::Stdio};
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

    pub async fn unzip(&self) -> Result<()> {
        let cwd = &self.path;

        let mut cmd = Command::new("unzip");

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
                .with_context(|| anyhow!("Command=unzip CWD={cwd:?}"))
                .context("artifact Extraction failed")
        } else {
            Ok(())
        }
    }
}
