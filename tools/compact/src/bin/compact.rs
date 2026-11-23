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

use std::{
    path::{Path, PathBuf},
    str::FromStr,
    sync::Arc,
};

use anyhow::{Context as _, Result, anyhow, bail};
use axoupdater::AxoUpdater;
use clap::Parser;
use compact::{
    COMPACT_NAME, COMPACT_VERSION, CleanCommand, Command, CommandLineArguments, CompileCommand,
    Compiler, CompilerAsset, FixupCommand, FormatCommand, ListCommand, SSelf, UpdateCommand,
    VersionSpec,
    catalog::{Catalog, Channel, Standing},
    fetch::{self, Freshness, MidnightArtifacts},
    file,
    fixup::{self, FixupStatus, fixup_file},
    formatter::{self, FormatStatus, format_file},
    http, is_corrupt_archive, progress,
    utils::{self, set_current_compiler},
};
use indicatif::ProgressStyle;
use tokio::task::JoinSet;

#[tokio::main]
async fn main() -> Result<()> {
    let cli = CommandLineArguments::parse();

    match &cli.command {
        Command::Check(_) => check(&cli)
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
        Command::Compile(compile_command) => compile(&cli, compile_command)
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

async fn compile(cfg: &CommandLineArguments, command: &CompileCommand) -> Result<()> {
    let mut version: Option<semver::Version> = None;
    let mut args = vec![];

    for argument in &command.args {
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

    Ok(())
}

async fn update(cfg: &CommandLineArguments, command: &UpdateCommand) -> Result<()> {
    utils::initialise_directories(cfg).await?;

    // quick initial check to see if an exact version is already installed,
    // skipping network requests entirely (only works for exact versions)
    if let Some(VersionSpec::Exact(version)) = &command.version {
        let dir = cfg
            .directory
            .versions_dir()
            .join(version.to_string())
            .join(cfg.target.to_string());

        // A version counts as installed only when the compiler binary itself is
        // there. A previous run whose extraction failed leaves the directory
        // behind holding nothing but `artifact.zip'; treating that as installed
        // skips re-extraction and reports success for a broken install.
        if dir.join("compactc").is_file() {
            let compiler = Compiler::create(cfg, version.clone(), cfg.target).await?;

            println!(
                "{label}: {target} -- {version} -- already installed",
                label = cfg.style.label(),
                target = cfg.style.target(cfg.target),
                version = cfg.style.version_in_channel(version.clone()),
            );

            if !command.no_set_default {
                set_current_compiler(cfg, &compiler).await?;

                println!(
                    "{label}: {target} -- {version} -- {message}.",
                    label = cfg.style.label(),
                    target = cfg.style.target(cfg.target),
                    version = cfg.style.version_in_channel(version.clone()),
                    message = cfg.style.success("default"),
                );
            }

            return Ok(());
        } else if dir.exists() {
            // The directory survives a failed extraction. Say so, rather than
            // silently re-downloading, so the earlier failure is accounted for.
            println!(
                "{label}: {target} -- {version} -- {message}",
                label = cfg.style.label(),
                target = cfg.style.target(cfg.target),
                version = cfg.style.version(version.clone()),
                message = cfg
                    .style
                    .warn("previous installation is incomplete, reinstalling"),
            );
        }
    }

    let (artifacts, freshness) = load_compilers().await?;
    let mut catalog = Catalog::from(artifacts);

    // A cached listing can be up to a quarter of an hour old, and a version
    // published since -- a candidate, typically, asked for by name as soon as
    // it is announced -- is not in it. An exact version the cache lacks is
    // looked for again in a listing fetched now.
    if let (Some(spec @ VersionSpec::Exact(_)), Freshness::Cached) = (&command.version, freshness)
        && catalog.resolve(spec).is_err()
    {
        catalog = Catalog::from(fetch_compilers().await?);
    }

    let (version, artifact) = match &command.version {
        Some(spec) => catalog.resolve(spec)?,
        None => {
            let (latest, artifact) = catalog
                .releases()
                .latest()
                .ok_or_else(|| anyhow!("No versions available"))?;

            if let Some(default) = candidate_default_newer_than(cfg, latest).await {
                println!(
                    "{label}: {target} -- {version} -- {message}",
                    label = cfg.style.label(),
                    target = cfg.style.target(default.target()),
                    version = cfg.style.version_in_channel(default.version().clone()),
                    message = cfg.style.warn(format!(
                        "newer than the latest release, {latest}, so kept as the default"
                    )),
                );
                println!(
                    "{label}: run `compact update {latest}' to switch to the latest release.",
                    label = cfg.style.label(),
                );

                return Ok(());
            }

            (latest.clone(), artifact.clone())
        }
    };

    let target = cfg.target;

    let compiler = Compiler::create(cfg, version.clone(), target).await?;

    let mut installed = false;

    if !compiler.path_compactc().is_file() {
        let compiler_asset = artifact.compiler(cfg)?;

        download_and_install(cfg, &version, &compiler_asset, &compiler.path_zip()).await?;

        installed = true;
    }

    if installed {
        println!(
            "{label}: {target} -- {version} -- installed",
            label = cfg.style.label(),
            target = cfg.style.target(target),
            version = cfg.style.version_in_channel(version.clone()),
        );
    } else {
        println!(
            "{label}: {target} -- {version} -- already installed",
            label = cfg.style.label(),
            target = cfg.style.target(target),
            version = cfg.style.version_in_channel(version.clone()),
        );
    }

    if !command.no_set_default {
        set_current_compiler(cfg, &compiler).await?;

        println!(
            "{label}: {target} -- {version} -- {message}.",
            label = cfg.style.label(),
            target = cfg.style.target(target),
            version = cfg.style.version_in_channel(version),
            message = cfg.style.success("default"),
        );
    }

    Ok(())
}

/// The default compiler, when it is a release candidate newer than `latest',
/// the latest release. A plain `compact update' leaves such a default where
/// it is rather than move it backwards to that release.
///
/// A default that cannot be read -- a link to a compiler that is gone, say --
/// is no candidate to keep, and replacing it is what `compact update' has
/// always done, so it is not an error here.
async fn candidate_default_newer_than(
    cfg: &CommandLineArguments,
    latest: &semver::Version,
) -> Option<Compiler> {
    let Ok(Some(default)) = utils::get_current_compiler(cfg).await else {
        return None;
    };

    (Standing::of(default.version(), latest) == Standing::CandidateAhead).then_some(default)
}

/// Fetch the archive unless it is already here, check it against the size and
/// SHA-256 the release listing gives, then unpack it.
///
/// An archive that is not as listed, or cannot be read, is discarded and
/// fetched once more. The archive is otherwise reused whenever it is on disk,
/// so a damaged one would fail every retry in exactly the same way and leave
/// deleting it by hand as the only way forward -- which is the shape of the
/// failure reported in issue #739. Only the archive's own faults are retried: a
/// full disk or a permission error is reported as it happens, because fetching
/// the file again would not help. An archive the listing gives no SHA-256 for
/// is not fetched at all.
async fn download_and_install(
    cfg: &CommandLineArguments,
    version: &semver::Version,
    compiler_asset: &CompilerAsset,
    zip_path: &Path,
) -> Result<()> {
    compiler_asset.sha256()?;

    if !file::File::new(zip_path.to_path_buf()).exist() {
        download_archive(compiler_asset, zip_path).await?;
    }

    let Err(error) = progress::future("Unpacking compiler", compiler_asset.install()).await else {
        return Ok(());
    };

    if !is_corrupt_archive(&error) {
        return Err(error);
    }

    println!(
        "{label}: {target} -- {version} -- {message}",
        label = cfg.style.label(),
        target = cfg.style.target(cfg.target),
        version = cfg.style.version(version.clone()),
        message = cfg
            .style
            .warn("downloaded archive is damaged, downloading it again"),
    );

    utils::remove_file_if_exists(zip_path)
        .await
        .with_context(|| anyhow!("Failed to discard the damaged archive `{zip_path:?}'"))?;

    download_archive(compiler_asset, zip_path).await?;

    progress::future("Unpacking compiler", compiler_asset.install()).await
}

async fn download_archive(compiler_asset: &CompilerAsset, zip_path: &Path) -> Result<()> {
    let client = http::Client::new()?;

    let download_url = compiler_asset.download_url().clone();
    let download_future =
        client.download_to_file(download_url, file::File::new(zip_path.to_path_buf()));

    let dl = progress::future("Downloading artifact", download_future).await?;

    progress::progress(dl).await?;

    Ok(())
}

async fn format(cfg: &CommandLineArguments, command: &FormatCommand) -> Result<()> {
    let bin = cfg.directory.bin_dir().join("format-compact");

    if !bin.exists() {
        bail!(
            "formatter not available - please install a compiler version that includes format-compact"
        )
    }

    if command.version || command.language_version {
        let flag = if command.version {
            "--version"
        } else {
            "--language-version"
        };

        let output = tokio::process::Command::new(&bin)
            .arg(flag)
            .output()
            .await
            .context("Failed to invoke format-compact")?;

        if output.status.success() {
            print!("{}", String::from_utf8_lossy(&output.stdout));
        } else {
            eprint!("{}", String::from_utf8_lossy(&output.stderr));
            bail!("format-compact {flag} failed");
        }
        return Ok(());
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

    if command.version || command.language_version {
        let flag = if command.version {
            "--version"
        } else {
            "--language-version"
        };

        let output = tokio::process::Command::new(&bin)
            .arg(flag)
            .output()
            .await
            .context("Failed to invoke fixup-compact")?;

        if output.status.success() {
            print!("{}", String::from_utf8_lossy(&output.stdout));
        } else {
            eprint!("{}", String::from_utf8_lossy(&output.stderr));
            bail!("fixup-compact {flag} failed");
        }
        return Ok(());
    }

    let mut join_set = JoinSet::new();

    let bin = Arc::new(bin);
    let check_mode = command.check;
    let update_uint_ranges = command.update_uint_ranges;
    let vscode = command.vscode;

    for file_path in &command.files {
        let path = PathBuf::from_str(file_path).unwrap();

        if path.is_dir() {
            for path in fixup::compact_files_excluding_gitignore(&path) {
                let bin = Arc::clone(&bin);
                join_set.spawn(async move {
                    fixup_file(&bin, check_mode, path, update_uint_ranges, vscode).await
                });
            }
        } else {
            let bin = Arc::clone(&bin);
            join_set.spawn(async move {
                fixup_file(&bin, check_mode, path, update_uint_ranges, vscode).await
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
            FixupStatus::Diff(diff) => {
                eprintln!("{}:", cfg.style.version_raw(path.display()));
                eprintln!("{diff}");
                something_failed = true;
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

/// What can be installed, from the cache while it is fresh.
async fn load_compilers() -> Result<(MidnightArtifacts, Freshness)> {
    with_spinner(MidnightArtifacts::load()).await
}

/// What can be installed, fetched now whatever the cache holds.
async fn fetch_compilers() -> Result<MidnightArtifacts> {
    with_spinner(MidnightArtifacts::fetch()).await
}

async fn with_spinner<T>(load: impl Future<Output = Result<T>>) -> Result<T> {
    let pb = indicatif::ProgressBar::new_spinner();

    pb.set_style(ProgressStyle::default_spinner().tick_chars(" ▏▎▍▌▋▊▉█"));

    pb.enable_steady_tick(std::time::Duration::from_millis(30));

    pb.set_message("Fetching information from server");

    let loaded = load.await.with_context(|| {
        anyhow!("Failed to query backend services to collect the latest artifacts")
    })?;

    pb.finish_and_clear();

    Ok(loaded)
}

async fn check(cfg: &CommandLineArguments) -> Result<()> {
    utils::initialise_directories(cfg).await?;

    let current_compiler = utils::get_current_compiler(cfg)
        .await
        .context("Failed to get the current compiler")?;

    let catalog = Catalog::from(load_compilers().await?.0);

    let Some((latest_version, _)) = catalog.releases().latest() else {
        bail!("No version available")
    };

    // The line naming the latest release, when there is something to say
    // about it: an update to it, or a candidate default ahead of it.
    let latest_line: Option<&str>;

    if let Some(compiler) = current_compiler {
        let target = compiler.target();
        let version = compiler.version().clone();
        let status = match Standing::of(&version, latest_version) {
            Standing::UpdateAvailable => {
                latest_line = Some("Latest version available");
                cfg.style.warn("Update Available")
            }
            Standing::CandidateAhead => {
                latest_line = Some("Latest release");
                cfg.style.warn("Ahead of the latest release")
            }
            Standing::UpToDate => {
                latest_line = None;
                cfg.style.success("Up to date")
            }
        };

        println!(
            "{label}: {target} -- {status} -- {version}",
            label = cfg.style.label(),
            target = cfg.style.target(target),
            version = cfg.style.version_in_channel(version),
        );
    } else {
        latest_line = Some("Latest version available");

        println!(
            "{label}: {message}.",
            label = cfg.style.label(),
            message = cfg.style.warn("no version installed"),
        );
    }

    if let Some(latest_line) = latest_line {
        println!(
            "{label}: {latest_line}: {version}.",
            label = cfg.style.label(),
            version = cfg.style.version(latest_version.clone()),
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

                // A directory whose name is not a version is listed as it
                // always was, unlabelled.
                let channel = match semver::Version::parse(&display_name) {
                    Ok(version) if Channel::of(&version) == Channel::Candidate => {
                        format!(" {}", cfg.style.warn("(release candidate)"))
                    }
                    _ => String::new(),
                };

                if current_compiler
                    .as_ref()
                    .map(|c| c.version().to_string() == display_name)
                    .unwrap_or_default()
                {
                    println!(
                        "{} {}{}",
                        console::Style::new().cyan().dim().apply_to(cfg.icons.arrow),
                        cfg.style.version_raw(display_name).bold(),
                        channel
                    );
                } else {
                    println!(
                        "{}{}{}",
                        if is_current_compiler_set_at_all {
                            "  "
                        } else {
                            ""
                        },
                        cfg.style.version_raw(display_name).bold(),
                        channel
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
        let catalog = Catalog::from(load_compilers().await?.0);

        println!(
            "{label}: {message}\n",
            label = cfg.style.label(),
            message = cfg.style.artifact("available versions")
        );

        let mut versions: Vec<_> = catalog.releases().iter().collect();

        if command.pre {
            versions.extend(catalog.candidates().iter());
        }

        // Newest first, which puts each candidate just below the release it
        // was for, since semver orders `0.36.0-rc.1' before `0.36.0'.
        versions.sort_by(|(a, _), (b, _)| b.cmp(a));

        for (version, compiler) in versions {
            let channel = match Channel::of(version) {
                Channel::Release => String::new(),
                Channel::Candidate => {
                    let label = match catalog.superseded_by(version) {
                        Some(release) => {
                            format!("(release candidate, superseded by {release})")
                        }
                        None => "(release candidate)".to_owned(),
                    };

                    format!(" {}", cfg.style.warn(label))
                }
            };

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
                .map(|c| c.version() == version)
                .unwrap_or_default()
            {
                println!(
                    "{} {}{} - {}",
                    console::Style::new().cyan().dim().apply_to(cfg.icons.arrow),
                    cfg.style.version(version.clone()).bold(),
                    channel,
                    available_platforms
                );
            } else {
                println!(
                    "{}{}{} - {}",
                    if is_current_compiler_set_at_all {
                        "  "
                    } else {
                        ""
                    },
                    cfg.style.version(version.clone()).bold(),
                    channel,
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
        // the older CLI's cache too, which this one leaves alone otherwise
        for cache_path in [fetch::cache_path()?, fetch::legacy_cache_path()?] {
            utils::remove_file_if_exists(&cache_path).await?;

            println!(
                "{label}: {message} {version}",
                label = cfg.style.label(),
                message = cfg.style.error("removed"),
                version = cfg.style.version_raw(cache_path.display()).italic().dim()
            );
        }
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

        // The current version's own directory and no other: a name that merely
        // contains it, `0.36.0-rc.0' beside `0.36.0', is another version. With
        // no default there is nothing to single out, and every version is kept,
        // as it has always been.
        let keep_entry =
            command.keep_current && (current_version.is_empty() || display_name == current_version);

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
