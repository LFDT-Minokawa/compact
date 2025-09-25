use anyhow::{anyhow, bail, Context as _, Result};
use axoupdater::AxoUpdater;
use clap::Parser;
use compact::{
    fetch::{self, MidnightArtifacts},
    file, http, progress,
    utils::{self, set_current_compiler},
    Command, CommandLineArguments, Compiler, ListCommand, SSelf, UpdateCommand, COMPACT_NAME,
    COMPACT_VERSION,
};
use indicatif::ProgressStyle;

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
        Command::SSelf(sself) => match sself {
            SSelf::Check => self_check(&cli).await.context("Failed to self update")?,
            SSelf::Update => self_udpate(&cli).await.context("Failed to self update")?,
        },
        Command::List(list_command) => list(&cli, list_command)
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
    }

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

    Ok(())
}

async fn self_udpate(cfg: &CommandLineArguments) -> Result<()> {
    let mut updater = AxoUpdater::new_for(COMPACT_NAME);

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
        let compiler_asset = artifact.compiler(cfg);

        if !zip_file.exist() {
            let client = http::Client::new()?;

            let download_url = compiler_asset.download_url().clone();
            let download_future = client.download_to_file(download_url, zip_file);

            let dl = progress::future("Downloading artifact", download_future).await?;

            progress::progress(dl).await?;
        }

        let unzip_future = compiler_asset.unzip(&command.config.unzip);

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

    if command.installed {
        println!(
            "{label}: {message}\n",
            label = cfg.style.label(),
            message = cfg.style.artifact("installed versions")
        );

        let dir = cfg.directory.versions_dir();

        let mut entries = tokio::fs::read_dir(&dir)
            .await
            .context("Failed to load installed versions")?;

        while let Some(entry) = entries
            .next_entry()
            .await
            .context("Failed to load next version entry")?
        {
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
                        cfg.icons.arrow,
                        cfg.style.version_raw(display_name).bold()
                    );
                } else {
                    println!("  {}", cfg.style.version_raw(display_name).bold());
                }
            }
        }
    } else {
        let artifacts = load_compilers().await?;

        println!(
            "{label}: {message}\n",
            label = cfg.style.label(),
            message = cfg.style.artifact("available versions")
        );

        for (version, _) in artifacts.compilers {
            if current_compiler
                .as_ref()
                .map(|c| c.version() == &version)
                .unwrap_or_default()
            {
                println!("{} {}", cfg.icons.arrow, cfg.style.version(version).bold());
            } else {
                println!("  {}", cfg.style.version(version).bold());
            }
        }
    }

    Ok(())
}
