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

use std::{
    path::{Path, PathBuf},
    process::Stdio,
};

use anyhow::{Context as _, Result};
use console::{Color, style};
use similar::{ChangeTag, TextDiff};

#[derive(Debug)]
pub enum FormatStatus {
    Error,
    Success,
    Warn,
    Diff(String),
}

pub async fn format_file(
    bin: &Path,
    check: bool,
    path: PathBuf,
) -> Result<(PathBuf, &'static str, FormatStatus)> {
    let original_file = tokio::fs::read_to_string(&path)
        .await
        .context("reading original source file for comparison")?;

    let args = if check {
        vec![&path]
    } else {
        vec![&path, &path]
    };

    let mut cmd = tokio::process::Command::new(bin);
    let output = cmd
        .args(args)
        .stdout(Stdio::piped())
        .output()
        .await
        .context("Failed to spawn format-compact command")?;

    let command_success = output.status.success();

    if !command_success {
        return Ok((path, "failed", FormatStatus::Error));
    }

    let formatted_output = if check {
        String::from_utf8(output.stdout).context("reading formatter output")?
    } else {
        tokio::fs::read_to_string(&path)
            .await
            .context("reading source file after format")?
    };

    if formatted_output != original_file {
        if check {
            let comparison = diff_file(&original_file, &formatted_output);
            Ok((path, "", FormatStatus::Diff(comparison)))
        } else {
            Ok((path, "formatted", FormatStatus::Success))
        }
    } else {
        Ok((path, "unchanged", FormatStatus::Warn))
    }
}

pub fn compact_files_excluding_gitignore(dir: &Path) -> impl Iterator<Item = PathBuf> + '_ {
    ignore::WalkBuilder::new(dir)
        .follow_links(true)
        .require_git(false)
        .build()
        .filter_map(Result::ok)
        .filter(|e| e.file_type().map(|t| t.is_file()).unwrap_or(false))
        .map(ignore::DirEntry::into_path)
        .filter(move |d| d.extension().map(|e| e == "compact").unwrap_or_default())
}

pub fn diff_file(original: &str, formatted: &str) -> String {
    let diff = TextDiff::from_lines(original, formatted);
    let mut result = String::new();

    for (i, group) in diff.grouped_ops(3).iter().enumerate() {
        if i > 0 {
            result.push_str(&format!("{}\n", style("---").dim()));
        }

        for op in group {
            for change in diff.iter_changes(op) {
                let (sign, color, line_no) = match change.tag() {
                    ChangeTag::Delete => ("-", Color::Magenta, change.old_index()),
                    ChangeTag::Insert => ("+", Color::Cyan, change.new_index()),
                    ChangeTag::Equal => (" ", Color::White, change.old_index()),
                };

                if let Some(line_no) = line_no {
                    result.push_str(&format!(
                        "{}",
                        style(format!(
                            "{}{:4} | {}{}",
                            sign,
                            line_no + 1,
                            sign,
                            change.value()
                        ))
                        .fg(color)
                    ));
                }
            }
        }
    }

    result
}
