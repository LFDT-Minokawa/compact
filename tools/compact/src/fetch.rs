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

use crate::{
    CommandLineArguments, Target, compact_directory::COMPACTUP_VERSIONS_DIR,
    compiler_legacy::CompilerAsset,
};
use anyhow::{Context, Result, anyhow};
use octocrab::models::repos::Asset;
use semver::Version;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::time::sleep;

#[derive(Debug, Clone, Default, PartialEq, Deserialize, Serialize)]
pub struct MidnightArtifacts {
    pub compilers: BTreeMap<Version, MidnightCompiler>,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
struct CachedResponse {
    pub artifacts: MidnightArtifacts,
    pub cached_at: u64,
    pub rate_limit_remaining: Option<u32>,
    pub rate_limit_reset: Option<u64>,
}

const CACHE_TTL_SECONDS: u64 = 900; // 15 minutes
const MAX_RETRIES: u32 = 3;
const RETRY_BASE_DELAY_MS: u64 = 1000; // 1 second

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub struct MidnightCompiler {
    pub version: Version,
    pub x86_macos: Option<Asset>,
    pub aarch64_macos: Option<Asset>,
    pub x86_linux: Option<Asset>,
    pub aarch64_linux: Option<Asset>,
}

impl MidnightArtifacts {
    pub async fn load() -> Result<Self> {
        // Try to load from cache first
        if let Ok(cached) = load_from_cache().await {
            if is_cache_valid(&cached) {
                return Ok(cached.artifacts);
            }

            // Check if we're approaching rate limits and should use cache even if stale
            if should_use_cache_for_rate_limiting(&cached) {
                return Ok(cached.artifacts);
            }
        }

        // Cache miss or expired, fetch from GitHub with retry logic
        let octocrab_builder = octocrab::OctocrabBuilder::new();

        let octocrab = if let Ok(token) = std::env::var("GITHUB_TOKEN") {
            octocrab_builder.personal_token(token).build()?
        } else {
            octocrab_builder.build()?
        };

        let (compilers, rate_info) = load_compiler_versions_with_retry(octocrab)
            .await
            .context("Failed to load the compiler artifacts")?;

        let artifacts = Self { compilers };

        // Cache the response
        let cached_response = CachedResponse {
            artifacts: artifacts.clone(),
            cached_at: SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
            rate_limit_remaining: rate_info.0,
            rate_limit_reset: rate_info.1,
        };

        if let Err(e) = save_to_cache(&cached_response).await {
            // Don't fail the operation if caching fails, just log it
            eprintln!("Warning: Failed to cache GitHub API response: {e}");
        }

        Ok(artifacts)
    }
}

impl MidnightCompiler {
    pub fn compiler(&self, cfg: &CommandLineArguments) -> Result<CompilerAsset> {
        let asset = match cfg.target {
            Target::x86_64UnknownLinuxMusl => self.x86_linux.clone(),
            Target::Aarch64AppleDarwin => self.aarch64_macos.clone(),
            Target::x86_64AppleDarwin => self.x86_macos.clone(),
        };

        let asset =
            asset.with_context(|| anyhow!("Unsupported compiler platform: {}", cfg.target))?;

        let path = cfg
            .directory
            .join(COMPACTUP_VERSIONS_DIR)
            .join(self.version.to_string())
            .join(cfg.target.to_string());

        let compiler_asset = CompilerAsset {
            path,
            asset,
            version: self.version.clone(),
        };

        Ok(compiler_asset)
    }
}

async fn load_compiler_versions_with_retry(
    octocrab: octocrab::Octocrab,
) -> Result<(
    BTreeMap<Version, MidnightCompiler>,
    (Option<u32>, Option<u64>),
)> {
    let mut last_error = None;

    for attempt in 0..MAX_RETRIES {
        match load_compiler_versions(&octocrab).await {
            Ok((compilers, rate_info)) => return Ok((compilers, rate_info)),
            Err(e) => {
                last_error = Some(e);

                // Check if this is a rate limit error
                if attempt < MAX_RETRIES - 1 {
                    let delay = RETRY_BASE_DELAY_MS * (2_u64.pow(attempt));

                    eprintln!(
                        "GitHub API request failed (attempt {}), retrying in {}ms: {}",
                        attempt + 1,
                        delay,
                        last_error.as_ref().unwrap()
                    );

                    sleep(Duration::from_millis(delay)).await;
                }
            }
        }
    }

    Err(last_error.unwrap())
}

async fn load_compiler_versions(
    octocrab: &octocrab::Octocrab,
) -> Result<(
    BTreeMap<Version, MidnightCompiler>,
    (Option<u32>, Option<u64>),
)> {
    let releases = octocrab
        .repos("midnightntwrk", "compact")
        .releases()
        .list()
        .send()
        .await
        .with_context(|| anyhow!("Error while fetching compact releases"))?;

    // For now, we can't easily access rate limit headers from octocrab
    // We'll implement basic caching and retry logic without rate limit monitoring
    let rate_limit_remaining = None;
    let rate_limit_reset = None;

    let mut output = BTreeMap::new();

    for entry in releases {
        if entry.tag_name.contains("compactc") {
            let compiler = load_compiler_version(entry).await?;
            output.insert(compiler.version.clone(), compiler);
        }
    }

    Ok((output, (rate_limit_remaining, rate_limit_reset)))
}

async fn load_compiler_version(dir: octocrab::models::repos::Release) -> Result<MidnightCompiler> {
    let version = dir
        .tag_name
        .strip_prefix("compactc-v")
        .ok_or_else(|| anyhow!("Invalid version format: {}", dir.tag_name))?
        .parse::<Version>()
        .with_context(|| anyhow!("Failed to parse artifact version: {}", dir.tag_name))?;

    let mut x86_macos = None;
    let mut aarch64_macos = None;
    let mut x86_linux = None;
    let aarch64_linux = None;

    for asset in dir.assets {
        if asset.name.contains("aarch64-darwin") {
            aarch64_macos = Some(asset);
        } else if asset.name.contains("x86_64-apple-darwin") || asset.name.contains("x86_64-darwin")
        {
            x86_macos = Some(asset);
        } else if asset.name.contains("x86_64-unknown-linux") {
            x86_linux = Some(asset);
        }
    }

    Ok(MidnightCompiler {
        version,
        x86_macos,
        aarch64_macos,
        x86_linux,
        aarch64_linux,
    })
}

pub fn get_cache_path() -> Result<PathBuf> {
    let cache_dir = dirs::cache_dir()
        .or_else(|| std::env::temp_dir().into())
        .ok_or_else(|| anyhow!("Unable to determine cache directory"))?;

    let cache_path = cache_dir.join("compactc").join("github_cache.json");

    // Ensure cache directory exists
    if let Some(parent) = cache_path.parent() {
        std::fs::create_dir_all(parent).context("Failed to create cache directory")?;
    }

    Ok(cache_path)
}

async fn load_from_cache() -> Result<CachedResponse> {
    let cache_path = get_cache_path()?;

    if !cache_path.exists() {
        return Err(anyhow!("Cache file does not exist"));
    }

    let contents = tokio::fs::read_to_string(&cache_path)
        .await
        .context("Failed to read cache file")?;

    serde_json::from_str(&contents).context("Failed to deserialize cache file")
}

async fn save_to_cache(cached_response: &CachedResponse) -> Result<()> {
    let cache_path = get_cache_path()?;

    let contents =
        serde_json::to_string_pretty(cached_response).context("Failed to serialize cache data")?;

    tokio::fs::write(&cache_path, contents)
        .await
        .context("Failed to write cache file")?;

    Ok(())
}

fn is_cache_valid(cached: &CachedResponse) -> bool {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);

    now.saturating_sub(cached.cached_at) < CACHE_TTL_SECONDS
}

fn should_use_cache_for_rate_limiting(cached: &CachedResponse) -> bool {
    // If we have rate limit info and we're close to the limit, use cache even if stale
    if let (Some(remaining), Some(reset_time)) =
        (cached.rate_limit_remaining, cached.rate_limit_reset)
    {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        // If we have less than 10 requests remaining and reset time hasn't passed
        if remaining < 10 && now < reset_time {
            eprintln!(
                "Using cached data due to GitHub rate limit (remaining: {remaining}, resets at: {reset_time})",
            );

            return true;
        }
    }

    false
}

#[cfg(test)]
mod tests {
    use crate::fetch::load_compiler_versions;
    use octocrab::Octocrab;
    use wiremock::matchers::{method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    #[tokio::test]
    async fn test_500_response() {
        let mock_server = MockServer::start().await;

        Mock::given(method("GET"))
            .and(path("/repos/midnightntwrk/compact/releases"))
            .respond_with(ResponseTemplate::new(500).set_body_json(serde_json::json!({
                "message": "Internal server error"
            })))
            .mount(&mock_server)
            .await;

        let octocrab = Octocrab::builder()
            .base_uri(mock_server.uri())
            .unwrap()
            .build()
            .unwrap();

        let result = load_compiler_versions(&octocrab).await;
        assert!(result.is_err(), "Expected an error due to 500 status code");
        match result {
            Ok(_) => panic!(),
            Err(err) => assert_eq!(format!("{err}"), "Error while fetching compact releases"),
        }
    }

    #[tokio::test]
    async fn test_400_response() {
        let mock_server = MockServer::start().await;

        Mock::given(method("GET"))
            .and(path("/repos/midnightntwrk/compact/releases"))
            .respond_with(ResponseTemplate::new(400).set_body_json(serde_json::json!({
                "message": "Bad Request"
            })))
            .mount(&mock_server)
            .await;

        let octocrab = Octocrab::builder()
            .base_uri(mock_server.uri())
            .unwrap()
            .build()
            .unwrap();

        let result = load_compiler_versions(&octocrab).await;
        assert!(result.is_err(), "Expected an error due to 400 status code");
        match result {
            Ok(_) => panic!(),
            Err(err) => assert_eq!(format!("{err}"), "Error while fetching compact releases"),
        }
    }

    #[tokio::test]
    async fn test_404_response() {
        let mock_server = MockServer::start().await;

        Mock::given(method("GET"))
            .and(path("/repos/midnightntwrk/compact/releases"))
            .respond_with(ResponseTemplate::new(404).set_body_json(serde_json::json!({
                "message": "Does not exist"
            })))
            .mount(&mock_server)
            .await;

        let octocrab = Octocrab::builder()
            .base_uri(mock_server.uri())
            .unwrap()
            .build()
            .unwrap();

        let result = load_compiler_versions(&octocrab).await;
        assert!(result.is_err(), "Expected an error due to 404 status code");
        match result {
            Ok(_) => panic!(),
            Err(err) => assert_eq!(format!("{err}"), "Error while fetching compact releases"),
        }
    }

    #[tokio::test]
    async fn test_429_response() {
        let mock_server = MockServer::start().await;

        Mock::given(method("GET"))
            .and(path("/repos/midnightntwrk/compact/releases"))
            .respond_with(ResponseTemplate::new(429).set_body_json(serde_json::json!({
                "message": "Too many requests"
            })))
            .mount(&mock_server)
            .await;

        let octocrab = Octocrab::builder()
            .base_uri(mock_server.uri())
            .unwrap()
            .build()
            .unwrap();

        let result = load_compiler_versions(&octocrab).await;
        assert!(result.is_err(), "Expected an error due to 429 status code");
        match result {
            Ok(_) => panic!(),
            Err(err) => assert_eq!(format!("{err}"), "Error while fetching compact releases"),
        }
    }
}
