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

use std::{path::PathBuf, str::FromStr, sync::Arc};

use anyhow::{Context as _, Result, anyhow, bail};
use axoupdater::AxoUpdater;
use clap::Parser;
use compact::{
    COMPACT_NAME, COMPACT_VERSION, CleanCommand, Command, CommandLineArguments, Compiler,
    FixupCommand, FormatCommand, ListCommand, SSelf, UpdateCommand,
    fetch::{self, MidnightArtifacts},
    file,
    fixup::{self, FixupStatus, fixup_file},
    formatter::{self, FormatStatus, format_file},
    http, progress,
    utils::{self, set_current_compiler},
};
use indicatif::ProgressStyle;
use tokio::task::JoinSet;

#[tokio::main]
async fn main() -> Result<()> {
    let cli = CommandLineArguments::parse();

    match &cli.command {
        Command::Check => check(&cli)
            .await
            .context("Failed to check for new versions.")?,
        Command::Update(update_command) => update(&cli, update_command)
            .await
            .context("Failed to update")?,
        Command::Format(format_command) => format(&cli, format_command).await?,
        Command::Fixup(fixup_command) => fixup(&cli, fixup_command).await?,
        Command::SSelf(sself) => match sself {
            SSelf::Check => self_check(&cli).await.context("Failed to self update")?,
            SSelf::Update => self_update(&cli).await.context("Failed to self update")?,
        },
        Command::List(list_command) => list(&cli, list_command)
            .await
            .context("Failed to list available versions")?,
        Command::Clean(clean_command) => clean(&cli, clean_command)
            .await
            .context("Failed to list available versions")?,
        Command::ExternalCommand(command) => run_external(&cli, command)
            .await
            .context("Failed to run compactc")?,
    }

    Ok(())
}

async fn self_check(cfg: &CommandLineArguments) -> Result<()> {
    let mut updater = AxoUpdater::new_for(COMPACT_NAME);

    // Set GitHub token if available to avoid rate limiting
    if let Ok(token) = std::env::var("GITHUB_TOKEN") {
        updater.set_github_token(&token);
    }

    updater
        .load_receipt()
        .context("Failed to load the release context")?;

    if !updater.is_update_needed().await? {
        // no update needed

        println!(
            "{label}: {target} -- {version} -- Up to date",
            label = cfg.style.label(),
            target = COMPACT_NAME,
            version = cfg.style.version(COMPACT_VERSION.clone()),
        );
    } else {
        let Some(latest) = updater.query_new_version().await?.cloned() else {
            bail!("Failed to query latest version")
        };

        println!(
            "{label}: {target} -- {status} -- {version}",
            label = cfg.style.label(),
            target = COMPACT_NAME,
            status = cfg.style.warn("Update available"),
            version = cfg.style.version(latest),
        );
    }

    Ok(())
}

async fn self_update(cfg: &CommandLineArguments) -> Result<()> {
    let mut updater = AxoUpdater::new_for(COMPACT_NAME);

    // Set GitHub token if available to avoid rate limiting
    if let Ok(token) = std::env::var("GITHUB_TOKEN") {
        updater.set_github_token(&token);
    }

    updater
        .load_receipt()
        .context("Failed to load the release context")?;

    if let Some(result) = updater.run().await? {
        let latest = result.new_version;

        println!(
            "{label}: {target} -- {status} -- {version}",
            label = cfg.style.label(),
            target = COMPACT_NAME,
            status = cfg.style.success("Update installed"),
            version = cfg.style.version(latest),
        );
    } else {
        println!(
            "{label}: {target} -- {version} -- Up to date",
            label = cfg.style.label(),
            target = COMPACT_NAME,
            version = cfg.style.version(COMPACT_VERSION.clone()),
        );
    }

    Ok(())
}

async fn run_external(cfg: &CommandLineArguments, arguments: &[String]) -> Result<()> {
    let mut arguments = arguments.iter();
    let Some(command) = arguments.next() else {
        bail!("Missing command, did you mean `compile'?")
    };

    match command.as_str() {
        "compile" => {
            let mut version: Option<semver::Version> = None;
            let mut args = vec![];

            for argument in arguments {
                if let Some(argument) = argument.strip_prefix('+') {
                    let argument = argument.to_owned();
                    version = Some(argument.parse().context("Invalid version format")?);
                } else {
                    args.push(argument.clone());
                }
            }

            let compiler = if let Some(version) = version {
                let target = cfg.target;

                Compiler::open(cfg, version.clone(), target)
                    .await
                    .with_context(|| anyhow!("Couldn't find compiler for {target} ({version})"))?
            } else {
                utils::get_current_compiler(cfg)
                    .await
                    .context("Failed to load current compiler.")?
                    .ok_or_else(|| anyhow!("No default compiler set"))?
            };

            compiler.invoke(args).await?;
        }
        cmd => bail!("Unknown command ({cmd}), did you mean `compile'?"),
    }

    Ok(())
}

async fn update(cfg: &CommandLineArguments, command: &UpdateCommand) -> Result<()> {
    utils::initialise_directories(cfg).await?;

    // quick initial check to if see a version is already installed
    // skipping network requests entirely
    if let Some(version) = &command.version {
        let dir = cfg
            .directory
            .versions_dir()
            .join(version.to_string())
            .join(cfg.target.to_string());

        if dir.exists() {
            let compiler = Compiler::create(cfg, version.clone(), cfg.target).await?;

            println!(
                "{label}: {target} -- {version} -- already installed",
                label = cfg.style.label(),
                target = cfg.style.target(cfg.target),
                version = cfg.style.version(version.clone()),
            );

            if !command.no_set_default {
                set_current_compiler(cfg, &compiler).await?;

                println!(
                    "{label}: {target} -- {version} -- {message}.",
                    label = cfg.style.label(),
                    target = cfg.style.target(cfg.target),
                    version = cfg.style.version(version.clone()),
                    message = cfg.style.success("default"),
                );
            }

            return Ok(());
        }
    }

    let mut artifacts = load_compilers().await?;

    let (version, artifact) = if let Some(version) = &command.version {
        artifacts
            .compilers
            .remove_entry(version)
            .ok_or_else(|| anyhow!("Couldn't find specified version"))?
    } else {
        artifacts
            .compilers
            .pop_last()
            .ok_or_else(|| anyhow!("Couldn't find specified version"))?
    };

    let target = cfg.target;

    let compiler = Compiler::create(cfg, version.clone(), target).await?;
    let zip_file = file::File::new(compiler.path_zip());

    let mut installed = false;

    if !compiler.path_compactc().is_file() {
        let compiler_asset = artifact.compiler(cfg)?;

        if !zip_file.exist() {
            let client = http::Client::new()?;

            let download_url = compiler_asset.download_url().clone();
            let download_future = client.download_to_file(download_url, zip_file);

            let dl = progress::future("Downloading artifact", download_future).await?;

            progress::progress(dl).await?;
        }

        let unzip_future = compiler_asset.unzip();

        progress::future("Unpacking compiler", unzip_future).await?;

        installed = true;
    }

    if installed {
        println!(
            "{label}: {target} -- {version} -- installed",
            label = cfg.style.label(),
            target = cfg.style.target(target),
            version = cfg.style.version(version.clone()),
        );
    } else {
        println!(
            "{label}: {target} -- {version} -- already installed",
            label = cfg.style.label(),
            target = cfg.style.target(target),
            version = cfg.style.version(version.clone()),
        );
    }

    if !command.no_set_default {
        set_current_compiler(cfg, &compiler).await?;

        println!(
            "{label}: {target} -- {version} -- {message}.",
            label = cfg.style.label(),
            target = cfg.style.target(target),
            version = cfg.style.version(version),
            message = cfg.style.success("default"),
        );
    }

    Ok(())
}

async fn format(cfg: &CommandLineArguments, command: &FormatCommand) -> Result<()> {
    let bin = cfg.directory.bin_dir().join("format-compact");

    if !bin.exists() {
        bail!("formatter not available")
    }

    let mut join_set = JoinSet::new();

    let bin = Arc::new(bin);
    let check_mode = command.check;

    for file_path in &command.files {
        let path = PathBuf::from_str(file_path).unwrap();

        if path.is_dir() {
            for path in formatter::compact_files_excluding_gitignore(&path) {
                let bin = Arc::clone(&bin);

                join_set.spawn(async move { format_file(&bin, check_mode, path).await });
            }
        } else {
            let bin = Arc::clone(&bin);

            join_set.spawn(async move { format_file(&bin, check_mode, path).await });
        }
    }

    let mut something_failed = false;

    while let Some(result) = join_set.join_next().await {
        let Ok(file_result) = result else {
            something_failed = true;

            continue;
        };

        let Ok((path, message, style)) = file_result else {
            something_failed = true;

            continue;
        };

        match style {
            FormatStatus::Error => {
                eprintln!(
                    "{}: {}",
                    cfg.style.version_raw(path.display()),
                    cfg.style.error(message)
                );

                something_failed = true;
            }
            FormatStatus::Success if command.verbose => {
                println!(
                    "{}: {}",
                    cfg.style.version_raw(path.display()),
                    cfg.style.success(message)
                );
            }
            FormatStatus::Warn if command.verbose => {
                println!(
                    "{}: {}",
                    cfg.style.version_raw(path.display()),
                    cfg.style.warn(message)
                );
            }
            FormatStatus::Diff(diff) => {
                eprintln!("{}:", cfg.style.version_raw(path.display()));
                eprintln!("{diff}");
                something_failed = true;
            }
            _ => (),
        }
    }

    if something_failed {
        bail!("formatting failed")
    } else {
        Ok(())
    }
}

async fn fixup(cfg: &CommandLineArguments, command: &FixupCommand) -> Result<()> {
    let bin = cfg.directory.bin_dir().join("fixup-compact");

    if !bin.exists() {
        bail!(
            "fixup tool not available - please install a compiler version that includes fixup-compact"
        )
    }

    if !command.in_place && command.files.len() > 1 {
        eprintln!(
            "{}: Multiple files specified without --in-place flag. Output will be concatenated to stdout.",
            cfg.style.warn("Warning")
        );
    }

    let mut join_set = JoinSet::new();

    let bin = Arc::new(bin);
    let update_uint_ranges = command.update_uint_ranges;
    let vscode = command.vscode;
    let in_place = command.in_place;

    for file_path in &command.files {
        let path = PathBuf::from_str(file_path).unwrap();

        if path.is_dir() {
            if !in_place {
                bail!("Directory processing requires --in-place flag");
            }
            for path in fixup::compact_files_excluding_gitignore(&path) {
                let bin = Arc::clone(&bin);
                join_set.spawn(async move {
                    fixup_file(&bin, path, update_uint_ranges, vscode, in_place).await
                });
            }
        } else {
            let bin = Arc::clone(&bin);
            join_set.spawn(async move {
                fixup_file(&bin, path, update_uint_ranges, vscode, in_place).await
            });
        }
    }

    let mut something_failed = false;

    while let Some(result) = join_set.join_next().await {
        let Ok(file_result) = result else {
            something_failed = true;
            continue;
        };

        let Ok((path, message, status)) = file_result else {
            something_failed = true;
            continue;
        };

        match status {
            FixupStatus::Error => {
                eprintln!(
                    "{}: {}",
                    cfg.style.version_raw(path.display()),
                    cfg.style.error(message)
                );
                something_failed = true;
            }
            FixupStatus::Success if command.verbose => {
                println!(
                    "{}: {}",
                    cfg.style.version_raw(path.display()),
                    cfg.style.success(message)
                );
            }
            FixupStatus::Unchanged if command.verbose => {
                println!(
                    "{}: {}",
                    cfg.style.version_raw(path.display()),
                    cfg.style.warn(message)
                );
            }
            FixupStatus::Output(content) => {
                print!("{}", content);
            }
            _ => (),
        }
    }

    if something_failed {
        bail!("fixup failed")
    } else {
        Ok(())
    }
}

async fn load_compilers() -> Result<MidnightArtifacts> {
    let pb = indicatif::ProgressBar::new_spinner();

    pb.set_style(ProgressStyle::default_spinner().tick_chars(" ▏▎▍▌▋▊▉█"));

    pb.enable_steady_tick(std::time::Duration::from_millis(30));

    pb.set_message("Fetching information from server");

    let artifacts = fetch::MidnightArtifacts::load().await.with_context(|| {
        anyhow!("Failed to query backend services to collect the latest artifacts")
    })?;

    pb.finish_and_clear();

    Ok(artifacts)
}

async fn check(cfg: &CommandLineArguments) -> Result<()> {
    utils::initialise_directories(cfg).await?;

    let current_compiler = utils::get_current_compiler(cfg)
        .await
        .context("Failed to get the current compiler")?;

    let mut artifacts = load_compilers().await?;

    let Some((latest_version, _)) = artifacts.compilers.pop_last() else {
        bail!("No version available")
    };

    let show_latest: bool;

    if let Some(compiler) = current_compiler {
        let target = compiler.target();
        let version = compiler.version().clone();
        let status = if version >= latest_version {
            show_latest = false;
            cfg.style.success("Up to date")
        } else {
            show_latest = true;
            cfg.style.warn("Update Available")
        };

        println!(
            "{label}: {target} -- {status} -- {version}",
            label = cfg.style.label(),
            target = cfg.style.target(target),
            version = cfg.style.version(version),
        );
    } else {
        show_latest = true;

        println!(
            "{label}: {message}.",
            label = cfg.style.label(),
            message = cfg.style.warn("no version installed"),
        );
    }

    if show_latest {
        println!(
            "{label}: Latest version available: {version}.",
            label = cfg.style.label(),
            version = cfg.style.version(latest_version),
        );
    }

    Ok(())
}

async fn list(cfg: &CommandLineArguments, command: &ListCommand) -> Result<()> {
    let current_compiler = utils::get_current_compiler(cfg)
        .await
        .context("Failed to get the current compiler")?;

    let is_current_compiler_set_at_all = current_compiler.is_some();

    if command.installed {
        utils::initialise_directories(cfg).await?;

        println!(
            "{label}: {message}\n",
            label = cfg.style.label(),
            message = cfg.style.artifact("installed versions")
        );

        let dir = cfg.directory.versions_dir();

        let mut entries = tokio::fs::read_dir(&dir)
            .await
            .context("Failed to load installed versions")?;

        let mut all_entries = Vec::new();
        while let Some(entry) = entries
            .next_entry()
            .await
            .context("Failed to load next version entry")?
        {
            all_entries.push(entry);
        }

        all_entries.sort_by(|a, b| {
            let name_a = a
                .file_name()
                .to_str()
                .map(|l| l.to_string())
                .unwrap_or_default();

            let name_b = b
                .file_name()
                .to_str()
                .map(|l| l.to_string())
                .unwrap_or_default();

            // Try to parse as semver, fall back to string comparison
            match (
                semver::Version::parse(&name_a),
                semver::Version::parse(&name_b),
            ) {
                (Ok(v_a), Ok(v_b)) => v_b.cmp(&v_a),
                (Ok(_), Err(_)) => std::cmp::Ordering::Less, // Valid semver comes first
                (Err(_), Ok(_)) => std::cmp::Ordering::Greater, // Valid semver comes first
                (Err(_), Err(_)) => name_b.cmp(&name_a),     // Fall back to string comparison
            }
        });

        let mut total = 0;

        for entry in all_entries {
            let path = entry.path();

            if path.is_dir() {
                let display_name = path.file_name().unwrap().to_string_lossy();

                if current_compiler
                    .as_ref()
                    .map(|c| c.version().to_string() == display_name)
                    .unwrap_or_default()
                {
                    println!(
                        "{} {}",
                        console::Style::new().cyan().dim().apply_to(cfg.icons.arrow),
                        cfg.style.version_raw(display_name).bold()
                    );
                } else {
                    println!(
                        "{}{}",
                        if is_current_compiler_set_at_all {
                            "  "
                        } else {
                            ""
                        },
                        cfg.style.version_raw(display_name).bold()
                    );
                }

                total += 1;
            }
        }

        if total == 0 {
            println!(
                "{}",
                cfg.style
                    .error("no versions available on this machine")
                    .bold()
            );

            println!(
                "{}: {}",
                console::Style::new().italic().cyan().dim().apply_to("try"),
                console::Style::new().bold().apply_to("compact update")
            );
        }
    } else {
        let artifacts = load_compilers().await?;

        println!(
            "{label}: {message}\n",
            label = cfg.style.label(),
            message = cfg.style.artifact("available versions")
        );

        for (version, compiler) in artifacts.compilers.into_iter().rev() {
            let available_platforms = [
                compiler
                    .x86_macos
                    .as_ref()
                    .map(|_| cfg.style.artifact("x86_macos").yellow().to_string()),
                compiler
                    .aarch64_macos
                    .as_ref()
                    .map(|_| cfg.style.artifact("aarch64_macos").yellow().to_string()),
                compiler
                    .x86_linux
                    .as_ref()
                    .map(|_| cfg.style.artifact("x86_linux").yellow().to_string()),
                compiler
                    .aarch64_linux
                    .as_ref()
                    .map(|_| cfg.style.artifact("aarch64_linux").yellow().to_string()),
            ]
            .into_iter()
            .flatten()
            .collect::<Vec<String>>()
            .join(", ");

            if current_compiler
                .as_ref()
                .map(|c| c.version() == &version)
                .unwrap_or_default()
            {
                println!(
                    "{} {} - {}",
                    console::Style::new().cyan().dim().apply_to(cfg.icons.arrow),
                    cfg.style.version(version).bold(),
                    available_platforms
                );
            } else {
                println!(
                    "{}{} - {}",
                    if is_current_compiler_set_at_all {
                        "  "
                    } else {
                        ""
                    },
                    cfg.style.version(version).bold(),
                    available_platforms
                );
            }
        }
    }

    Ok(())
}

async fn clean(cfg: &CommandLineArguments, command: &CleanCommand) -> Result<()> {
    utils::initialise_directories(cfg).await?;

    if command.cache {
        let cache_path = fetch::get_cache_path()?;

        utils::remove_file_if_exists(&cache_path).await?;

        println!(
            "{label}: {message} {version}",
            label = cfg.style.label(),
            message = cfg.style.error("removed"),
            version = cfg.style.version_raw(cache_path.display()).italic().dim()
        );
    }

    let versions_dir = cfg.directory.versions_dir();
    let sym_bin = cfg.directory.bin_dir().join("compactc");

    let mut entries = tokio::fs::read_dir(&versions_dir)
        .await
        .context("Failed to load installed versions")?;

    println!(
        "{label}: {message}",
        label = cfg.style.label(),
        message = cfg.style.artifact("removing versions")
    );

    let (_, current_version) = utils::read_parent_name_from_link(&sym_bin)
        .await
        .unwrap_or_default();

    if !command.keep_current {
        utils::remove_file_if_exists(&sym_bin).await?;

        let format_bin = cfg.directory.bin_dir().join("format-compact");
        let fixup_bin = cfg.directory.bin_dir().join("fixup-compact");

        utils::remove_file_if_exists(&format_bin).await?;
        utils::remove_file_if_exists(&fixup_bin).await?;
    }

    let mut all_entries = Vec::new();
    while let Some(entry) = entries
        .next_entry()
        .await
        .context("Failed to load next version entry")?
    {
        all_entries.push(entry);
    }

    all_entries.sort_by(|a, b| {
        let name_a = a
            .file_name()
            .to_str()
            .map(|l| l.to_string())
            .unwrap_or_default();

        let name_b = b
            .file_name()
            .to_str()
            .map(|l| l.to_string())
            .unwrap_or_default();

        // Try to parse as semver, fall back to string comparison
        match (
            semver::Version::parse(&name_a),
            semver::Version::parse(&name_b),
        ) {
            (Ok(v_a), Ok(v_b)) => v_b.cmp(&v_a),
            (Ok(_), Err(_)) => std::cmp::Ordering::Less, // Valid semver comes first
            (Err(_), Ok(_)) => std::cmp::Ordering::Greater, // Valid semver comes first
            (Err(_), Err(_)) => name_b.cmp(&name_a),     // Fall back to string comparison
        }
    });

    for entry in all_entries {
        let path = entry.path();

        let display_name = path
            .file_name()
            .and_then(|l| l.to_str())
            .map(|l| l.to_string())
            .unwrap_or_default();

        let keep_entry = command.keep_current && display_name.contains(&current_version);

        if !keep_entry && path.is_dir() {
            tokio::fs::remove_dir_all(&path)
                .await
                .context("Failed to remove version")?;

            println!(
                "{label}: {message} {version}",
                label = cfg.style.label(),
                message = cfg.style.error("removed"),
                version = cfg.style.version_raw(display_name).italic().dim()
            );
        } else if path.is_file() {
            tokio::fs::remove_file(path)
                .await
                .context("Failed to remove unknown file")?;
        } else {
            println!(
                "{label}: {message} {version}",
                label = cfg.style.label(),
                message = cfg.style.success("kept"),
                version = cfg.style.version_raw(display_name).italic().dim()
            );
        }
    }

    Ok(())
}
