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

use crate::{CommandLineArguments, Target, compact_directory::COMPACTUP_VERSIONS_DIR};
use anyhow::{Context, Result, anyhow, bail, ensure};
use semver::Version;
use std::{
    ffi::OsStr,
    path::{Path, PathBuf},
    process::Stdio,
};
use tokio::{fs, process::Command};

pub struct Compiler {
    version: Version,
    target: Target,
    dir: PathBuf,
    bin: PathBuf,
}

impl Compiler {
    pub fn path_zip(&self) -> PathBuf {
        self.dir.join("artifact.zip")
    }

    pub fn path_lib(&self) -> PathBuf {
        self.dir.join("lib")
    }

    pub fn path_zkir_pp(&self) -> PathBuf {
        self.dir.join("public_params.bin")
    }

    pub fn path_compactc(&self) -> &Path {
        self.bin.as_path()
    }

    pub fn path_format_compact(&self) -> PathBuf {
        self.dir.join("format-compact")
    }

    pub fn path_fixup_compact(&self) -> PathBuf {
        self.dir.join("fixup-compact")
    }

    pub async fn create(
        cfg: &CommandLineArguments,
        version: Version,
        target: Target,
    ) -> Result<Self> {
        let dir = cfg
            .directory
            .versions_dir()
            .join(version.to_string())
            .join(target.to_string());

        let bin = dir.join("compactc");

        fs::create_dir_all(&dir)
            .await
            .with_context(|| anyhow!("Failed to create directory `{dir:?}'"))?;

        Ok(Self {
            version,
            target,
            dir,
            bin,
        })
    }

    pub async fn open(
        cfg: &CommandLineArguments,
        version: Version,
        target: Target,
    ) -> Result<Self> {
        let dir = cfg
            .directory
            .join(COMPACTUP_VERSIONS_DIR)
            .join(version.to_string())
            .join(target.to_string());

        let bin = dir.join("compactc");

        ensure!(dir.is_dir(), "Directory does not exist: `{dir:?}'");
        ensure!(bin.is_file(), "Binary file not found: `{bin:?}'");

        Ok(Self {
            version,
            target,
            dir,
            bin,
        })
    }

    pub fn version(&self) -> &Version {
        &self.version
    }

    pub fn target(&self) -> Target {
        self.target
    }

    pub async fn invoke<I, S>(&self, args: I) -> Result<()>
    where
        I: IntoIterator<Item = S>,
        S: AsRef<OsStr>,
    {
        let program = self.path_compactc();
        let cwd = ".";

        let mut cmd = Command::new(program);

        // execute the unzip command in the artifact directory
        cmd.current_dir(cwd);

        cmd.args(args);

        // inherit the standard output
        cmd.stdout(Stdio::inherit());

        // inherit the sandard error output
        cmd.stderr(Stdio::inherit());

        // inherit the sandard input
        cmd.stdin(Stdio::inherit());

        let mut child = cmd.spawn().context("Failed to spawn compactc command")?;

        let status = child
            .wait()
            .await
            .context("Failed to execute the compactc command")?;
        if !status.success() {
            if let Some(code) = status.code() {
                // It was requested that the behaviour of the compact tool
                // reflects the behaviour of the compiler toolchain, so in
                // order to do that we propagate the exit code all the way
                std::process::exit(code)
            } else {
                bail!("compiler toolchain was terminated by a signal")
            }
        } else {
            Ok(())
        }
    }
}
