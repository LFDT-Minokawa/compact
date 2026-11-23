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

//! What can be installed: the releases of `LFDT-Minokawa/compact' tagged
//! `compactc-v<version>', each with one archive per platform, named
//! `compactc_v<version>_<platform>.zip'. Every other release in that
//! repository -- dev builds, the CLI's own -- is passed over. These names are a
//! contract with the release workflows (`RELEASING.md').

use crate::{
    CommandLineArguments, Target, compact_directory::COMPACTUP_VERSIONS_DIR,
    compiler_legacy::CompilerAsset,
};
use anyhow::{Context, Result, anyhow, bail};
use reqwest::{StatusCode, Url, header};
use semver::Version;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fmt;
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::time::sleep;

/// The repository whose releases are installed, as users see it named.
pub const SOURCE: &str = "LFDT-Minokawa/compact";

/// Its releases, through GitHub's REST API.
const RELEASES_URL: &str = "https://api.github.com/repos/LFDT-Minokawa/compact/releases";

/// The tag of every toolchain build is this followed by its version.
const TAG_PREFIX: &str = "compactc-v";

/// The most GitHub serves on one page of a listing.
const PER_PAGE: u32 = 100;

/// A listing longer than this many pages is taken to be a server that never
/// stops answering `next', rather than read forever.
const MAX_PAGES: usize = 100;

const CACHE_TTL_SECONDS: u64 = 900; // 15 minutes

/// Raised whenever what the cache file holds changes shape, so that a file
/// written by another version of the CLI is fetched afresh, not misread.
const CACHE_SCHEMA: u32 = 1;

const ATTEMPTS: u32 = 3;
const RETRY_BASE_DELAY_MS: u64 = 1000; // 1 second

/// A SHA-256 digest.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Sha256(pub [u8; 32]);

impl fmt::Display for Sha256 {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for byte in self.0 {
            write!(f, "{byte:02x}")?;
        }

        Ok(())
    }
}

impl FromStr for Sha256 {
    type Err = anyhow::Error;

    /// Sixty-four hexadecimal digits.
    fn from_str(hex: &str) -> Result<Self> {
        if hex.len() != 64 || !hex.is_ascii() {
            bail!("`{hex}' is not 64 hexadecimal digits");
        }

        let mut bytes = [0u8; 32];

        for (byte, pair) in bytes.iter_mut().zip(hex.as_bytes().chunks(2)) {
            let pair = std::str::from_utf8(pair).expect("ASCII is UTF-8");
            *byte = u8::from_str_radix(pair, 16)
                .map_err(|_| anyhow!("`{hex}' is not 64 hexadecimal digits"))?;
        }

        Ok(Sha256(bytes))
    }
}

impl Serialize for Sha256 {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.collect_str(self)
    }
}

impl<'de> Deserialize<'de> for Sha256 {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        String::deserialize(deserializer)?
            .parse()
            .map_err(serde::de::Error::custom)
    }
}

/// What the release listing says an archive's digest is.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Digest {
    Sha256(Sha256),
    /// The listing gives none.
    Missing,
    /// The listing gives one this CLI cannot check, as it was given.
    Unsupported(String),
}

impl Digest {
    /// GitHub gives an asset's digest as `sha256:<hex>'.
    fn of(listed: Option<&str>) -> Self {
        match listed {
            None => Digest::Missing,
            Some(listed) => match listed.strip_prefix("sha256:").map(str::parse) {
                Some(Ok(sha256)) => Digest::Sha256(sha256),
                _ => Digest::Unsupported(listed.to_owned()),
            },
        }
    }
}

/// One platform's archive of a toolchain build.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Archive {
    pub name: String,
    pub url: Url,
    pub size: u64,
    pub digest: Digest,
}

#[derive(Debug, Clone, Default, PartialEq, Deserialize, Serialize)]
pub struct MidnightArtifacts {
    pub compilers: BTreeMap<Version, MidnightCompiler>,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
pub struct MidnightCompiler {
    pub version: Version,
    pub x86_macos: Option<Archive>,
    pub aarch64_macos: Option<Archive>,
    pub x86_linux: Option<Archive>,
    pub aarch64_linux: Option<Archive>,
}

/// Where a listing came from: a cached one may be up to a quarter of an hour
/// behind, so a version it lacks is worth fetching the listing again for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Freshness {
    Cached,
    Fetched,
}

/// The platform in an archive's name, which is not the target's own name for
/// Intel macOS (`x86_64-darwin', not `x86_64-apple-darwin').
pub fn archive_platform(target: Target) -> &'static str {
    match target {
        Target::x86_64UnknownLinuxMusl => "x86_64-unknown-linux-musl",
        Target::Aarch64UnknownLinuxMusl => "aarch64-unknown-linux-musl",
        Target::x86_64AppleDarwin => "x86_64-darwin",
        Target::Aarch64AppleDarwin => "aarch64-darwin",
    }
}

fn archive_name(version: &Version, target: Target) -> String {
    format!("compactc_v{version}_{}.zip", archive_platform(target))
}

impl MidnightArtifacts {
    /// What can be installed, from the cache when it is under a quarter of an
    /// hour old, and otherwise from GitHub.
    pub async fn load() -> Result<(Self, Freshness)> {
        let cache = cache_path()?;

        if let Some(artifacts) = load_from_cache(&cache, RELEASES_URL, SystemTime::now()).await {
            return Ok((artifacts, Freshness::Cached));
        }

        Ok((Self::fetch().await?, Freshness::Fetched))
    }

    /// What can be installed, from GitHub, whatever the cache holds.
    pub async fn fetch() -> Result<Self> {
        let source = Url::parse(RELEASES_URL).expect("the release listing's URL is valid");
        let token = std::env::var("GITHUB_TOKEN").ok();
        let client = client()?;

        let compilers = load_compiler_versions(&client, &source, token.as_deref())
            .await
            .with_context(|| anyhow!("Failed to read the releases of {SOURCE}"))?;

        let artifacts = Self { compilers };

        if let Err(e) = save_to_cache(&cache_path()?, RELEASES_URL, &artifacts).await {
            // The listing is in hand; a cache that cannot be written only costs
            // the next command a fetch.
            eprintln!("Warning: Failed to cache the release listing: {e:#}");
        }

        Ok(artifacts)
    }
}

impl MidnightCompiler {
    pub fn archive(&self, target: Target) -> Option<&Archive> {
        match target {
            Target::x86_64UnknownLinuxMusl => self.x86_linux.as_ref(),
            Target::Aarch64UnknownLinuxMusl => self.aarch64_linux.as_ref(),
            Target::Aarch64AppleDarwin => self.aarch64_macos.as_ref(),
            Target::x86_64AppleDarwin => self.x86_macos.as_ref(),
        }
    }

    pub fn compiler(&self, cfg: &CommandLineArguments) -> Result<CompilerAsset> {
        let archive = self
            .archive(cfg.target)
            .cloned()
            .with_context(|| anyhow!("Unsupported compiler platform: {}", cfg.target))?;

        let path = cfg
            .directory
            .join(COMPACTUP_VERSIONS_DIR)
            .join(self.version.to_string())
            .join(cfg.target.to_string());

        Ok(CompilerAsset {
            path,
            archive,
            version: self.version.clone(),
        })
    }
}

/// A release as GitHub lists it; only what is read here.
#[derive(Debug, Deserialize)]
struct ListedRelease {
    tag_name: String,
    draft: bool,
    assets: Vec<ListedAsset>,
}

#[derive(Debug, Deserialize)]
struct ListedAsset {
    name: String,
    size: u64,
    digest: Option<String>,
    browser_download_url: Url,
}

fn client() -> Result<reqwest::Client> {
    reqwest::ClientBuilder::new()
        .user_agent(concat!(
            env!("CARGO_PKG_NAME"),
            "/",
            env!("CARGO_PKG_VERSION")
        ))
        .build()
        .context("Failed to create HTTP Client")
}

/// Every toolchain build in the release listing at `source'.
async fn load_compiler_versions(
    client: &reqwest::Client,
    source: &Url,
    token: Option<&str>,
) -> Result<BTreeMap<Version, MidnightCompiler>> {
    compilers_of(fetch_listing(client, source, token).await?)
}

/// The toolchain builds among `listing': its published releases tagged
/// `compactc-v<version>'. A draft is not published, and any other tag is
/// someone else's release. A `compactc-v' tag that does not name a version is
/// a release published in breach of the naming, and an error, since what it
/// was meant to offer cannot be known.
fn compilers_of(listing: Vec<ListedRelease>) -> Result<BTreeMap<Version, MidnightCompiler>> {
    let mut compilers = BTreeMap::new();

    for release in listing {
        if release.draft {
            continue;
        }

        let Some(version) = release.tag_name.strip_prefix(TAG_PREFIX) else {
            continue;
        };

        let version = Version::parse(version).with_context(|| {
            anyhow!(
                "The release tagged `{}' in {SOURCE} does not name a version",
                release.tag_name
            )
        })?;

        if !version.build.is_empty() {
            bail!(
                "The release tagged `{}' in {SOURCE} has build metadata, which no toolchain version carries",
                release.tag_name
            );
        }

        let mut assets: BTreeMap<String, ListedAsset> = release
            .assets
            .into_iter()
            .map(|asset| (asset.name.clone(), asset))
            .collect();

        let mut take = |target| {
            assets
                .remove(&archive_name(&version, target))
                .map(|asset| Archive {
                    name: asset.name,
                    url: asset.browser_download_url,
                    size: asset.size,
                    digest: Digest::of(asset.digest.as_deref()),
                })
        };

        let compiler = MidnightCompiler {
            version: version.clone(),
            x86_macos: take(Target::x86_64AppleDarwin),
            aarch64_macos: take(Target::Aarch64AppleDarwin),
            x86_linux: take(Target::x86_64UnknownLinuxMusl),
            aarch64_linux: take(Target::Aarch64UnknownLinuxMusl),
        };

        if compilers.insert(version.clone(), compiler).is_some() {
            bail!("{SOURCE} has more than one release of {version}");
        }
    }

    Ok(compilers)
}

/// Every release at `source', page by page.
async fn fetch_listing(
    client: &reqwest::Client,
    source: &Url,
    token: Option<&str>,
) -> Result<Vec<ListedRelease>> {
    let mut page = source.clone();
    page.query_pairs_mut()
        .append_pair("per_page", &PER_PAGE.to_string());

    let mut next = Some(page);
    let mut listing = Vec::new();
    let mut pages = 0;

    while let Some(url) = next {
        pages += 1;

        if pages > MAX_PAGES {
            bail!("The release listing ran past {MAX_PAGES} pages");
        }

        let response = get_with_retries(client, &url, token).await?;
        next = next_page(response.headers())?;

        let releases: Vec<ListedRelease> = response
            .json()
            .await
            .with_context(|| anyhow!("Failed to read the release listing at `{url}'"))?;

        listing.extend(releases);
    }

    Ok(listing)
}

/// The page after this one, from the `Link' header GitHub pages a listing
/// with: `<url>; rel="next", <url>; rel="last"'.
fn next_page(headers: &header::HeaderMap) -> Result<Option<Url>> {
    let Some(link) = headers.get(header::LINK) else {
        return Ok(None);
    };

    let link = link
        .to_str()
        .context("The listing's `Link' header is not text")?;

    for entry in link.split(',') {
        let mut parts = entry.split(';').map(str::trim);

        let Some(target) = parts
            .next()
            .and_then(|target| target.strip_prefix('<'))
            .and_then(|target| target.strip_suffix('>'))
        else {
            bail!("The listing's `Link' header is not as GitHub writes it: `{link}'");
        };

        if parts.any(|parameter| parameter == "rel=\"next\"") {
            return Url::parse(target)
                .map(Some)
                .with_context(|| anyhow!("The listing's next page is not a URL: `{target}'"));
        }
    }

    Ok(None)
}

/// A GET of one page of the listing. A failure to connect or an error on
/// GitHub's side is tried again, twice, after a pause; anything else is
/// reported at once. GitHub signals its rate limit with 403 or 429 and no
/// requests remaining, which is said in so many words.
async fn get_with_retries(
    client: &reqwest::Client,
    url: &Url,
    token: Option<&str>,
) -> Result<reqwest::Response> {
    let mut attempt = 1;

    loop {
        let mut request = client
            .get(url.clone())
            .header(header::ACCEPT, "application/vnd.github+json")
            .header("X-GitHub-Api-Version", "2022-11-28");

        if let Some(token) = token {
            request = request.bearer_auth(token);
        }

        let failure = match request.send().await {
            Ok(response) if response.status().is_success() => return Ok(response),
            Ok(response) if response.status().is_server_error() => {
                anyhow!("GitHub answered {} for `{url}'", response.status())
            }
            Ok(response) => return Err(refusal(response, url).await),
            Err(error) => anyhow::Error::new(error).context(format!("Failed to reach `{url}'")),
        };

        if attempt == ATTEMPTS {
            return Err(failure);
        }

        let delay = RETRY_BASE_DELAY_MS * 2_u64.pow(attempt - 1);

        eprintln!(
            "GitHub API request failed (attempt {attempt}), retrying in {delay}ms: {failure:#}"
        );

        sleep(Duration::from_millis(delay)).await;
        attempt += 1;
    }
}

/// The error for an answer GitHub will give again if asked again.
async fn refusal(response: reqwest::Response, url: &Url) -> anyhow::Error {
    let status = response.status();
    let headers = response.headers();

    let exhausted = headers
        .get("x-ratelimit-remaining")
        .and_then(|remaining| remaining.to_str().ok())
        == Some("0");

    if exhausted && (status == StatusCode::FORBIDDEN || status == StatusCode::TOO_MANY_REQUESTS) {
        let resets_in = headers
            .get("x-ratelimit-reset")
            .and_then(|reset| reset.to_str().ok())
            .and_then(|reset| reset.parse::<u64>().ok())
            .and_then(|reset| {
                let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_secs();
                Some(reset.saturating_sub(now).div_ceil(60))
            });

        return match resets_in {
            Some(minutes) => anyhow!(
                "GitHub's API rate limit is used up for the next {minutes} minute(s); \
                 setting GITHUB_TOKEN to a GitHub token raises it"
            ),
            None => anyhow!(
                "GitHub's API rate limit is used up; setting GITHUB_TOKEN to a GitHub token raises it"
            ),
        };
    }

    #[derive(Deserialize)]
    struct Message {
        message: String,
    }

    match response.json::<Message>().await {
        Ok(Message { message }) => anyhow!("GitHub answered {status} for `{url}': {message}"),
        Err(_) => anyhow!("GitHub answered {status} for `{url}'"),
    }
}

/// The cache file. The CLI before this one cached a listing of
/// `midnightntwrk/compact' in `github_cache.json', beside this file; it is
/// neither read nor written here, since that CLI still reads it and must not
/// find release candidates there.
pub fn cache_path() -> Result<PathBuf> {
    Ok(cache_dir()?.join("releases-LFDT-Minokawa-compact.json"))
}

/// The older CLI's cache file, which `compact clean --cache' removes too.
pub fn legacy_cache_path() -> Result<PathBuf> {
    Ok(cache_dir()?.join("github_cache.json"))
}

fn cache_dir() -> Result<PathBuf> {
    let cache_dir = dirs::cache_dir()
        .or_else(|| std::env::temp_dir().into())
        .ok_or_else(|| anyhow!("Unable to determine cache directory"))?;

    Ok(cache_dir.join("compactc"))
}

#[derive(Debug, Deserialize, Serialize)]
struct CachedListing {
    schema: u32,
    source: String,
    cached_at: u64,
    compilers: BTreeMap<Version, MidnightCompiler>,
}

/// The cached listing of `source', if there is one younger than the cache's
/// lifetime. Anything else -- no file, a file another CLI wrote, an old one --
/// means fetching the listing, which is where the truth is.
async fn load_from_cache(path: &Path, source: &str, now: SystemTime) -> Option<MidnightArtifacts> {
    let contents = tokio::fs::read_to_string(path).await.ok()?;
    let cached: CachedListing = serde_json::from_str(&contents).ok()?;
    let now = now.duration_since(UNIX_EPOCH).ok()?.as_secs();

    let fresh = cached.schema == CACHE_SCHEMA
        && cached.source == source
        && cached.cached_at <= now
        && now - cached.cached_at < CACHE_TTL_SECONDS;

    fresh.then_some(MidnightArtifacts {
        compilers: cached.compilers,
    })
}

/// Written beside the cache and renamed over it, so that a reader never sees
/// half a file.
async fn save_to_cache(path: &Path, source: &str, artifacts: &MidnightArtifacts) -> Result<()> {
    let cached = CachedListing {
        schema: CACHE_SCHEMA,
        source: source.to_owned(),
        cached_at: SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs(),
        compilers: artifacts.compilers.clone(),
    };

    if let Some(parent) = path.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .context("Failed to create cache directory")?;
    }

    let contents =
        serde_json::to_string_pretty(&cached).context("Failed to serialize cache data")?;

    let mut partial = path.as_os_str().to_owned();
    partial.push(".partial");
    let partial = PathBuf::from(partial);

    tokio::fs::write(&partial, contents)
        .await
        .context("Failed to write cache file")?;
    tokio::fs::rename(&partial, path)
        .await
        .context("Failed to replace cache file")?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::{Value, json};
    use wiremock::matchers::{header as has_header, method, path, query_param};
    use wiremock::{Match, Mock, MockServer, Request, ResponseTemplate};

    const DIGEST: &str = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";

    fn asset(name: &str) -> Value {
        json!({
            "name": name,
            "size": 3,
            "digest": format!("sha256:{DIGEST}"),
            "browser_download_url": format!("https://example.com/download/{name}"),
        })
    }

    /// A release with an archive for each of `platforms', as the release
    /// workflows name them.
    fn release(tag: &str, platforms: &[&str]) -> Value {
        let version = tag.strip_prefix("compactc-v").unwrap_or("0.0.0");

        json!({
            "tag_name": tag,
            "draft": false,
            "prerelease": tag.contains('-'),
            "assets": platforms
                .iter()
                .map(|platform| asset(&format!("compactc_v{version}_{platform}.zip")))
                .collect::<Vec<_>>(),
        })
    }

    const ALL: [&str; 4] = [
        "x86_64-darwin",
        "aarch64-darwin",
        "x86_64-unknown-linux-musl",
        "aarch64-unknown-linux-musl",
    ];

    fn listing(releases: Vec<Value>) -> Vec<ListedRelease> {
        serde_json::from_value(Value::Array(releases)).unwrap()
    }

    fn versions(compilers: &BTreeMap<Version, MidnightCompiler>) -> Vec<String> {
        compilers.keys().map(Version::to_string).collect()
    }

    async fn server() -> (MockServer, Url) {
        let server = MockServer::start().await;
        let source = Url::parse(&format!(
            "{}/repos/LFDT-Minokawa/compact/releases",
            server.uri()
        ))
        .unwrap();
        (server, source)
    }

    async fn load(
        source: &Url,
        token: Option<&str>,
    ) -> Result<BTreeMap<Version, MidnightCompiler>> {
        load_compiler_versions(&client().unwrap(), source, token).await
    }

    #[test]
    fn only_published_compactc_v_releases_are_toolchain_builds() {
        let mut draft = release("compactc-v0.37.0-rc.0", &ALL);
        draft["draft"] = json!(true);

        let compilers = compilers_of(listing(vec![
            release("compactc-v0.36.1", &ALL),
            release("compactc-v0.36.0-rc.1", &ALL),
            release(
                "compactc-dev-41751b10a19d45060ae1d128036370eefdf041d6",
                &ALL,
            ),
            release("compact-v0.6.0", &[]),
            release("v0.30.0-rc.1", &ALL),
            draft,
        ]))
        .unwrap();

        assert_eq!(versions(&compilers), ["0.36.0-rc.1", "0.36.1"]);
    }

    #[test]
    fn a_compactc_v_tag_that_is_not_a_version_is_an_error() {
        let error = compilers_of(listing(vec![
            release("compactc-v0.36.1", &ALL),
            release("compactc-v0.36", &ALL),
        ]))
        .unwrap_err();

        assert_eq!(
            error.to_string(),
            "The release tagged `compactc-v0.36' in LFDT-Minokawa/compact does not name a version"
        );
    }

    #[test]
    fn a_version_with_build_metadata_is_an_error() {
        let error = compilers_of(listing(vec![release("compactc-v0.36.1+abc", &ALL)])).unwrap_err();

        assert!(error.to_string().contains("build metadata"), "{error}");
    }

    #[test]
    fn archives_are_found_by_their_exact_names() {
        let mut build = release("compactc-v0.36.1", &["aarch64-darwin"]);
        let assets = build["assets"].as_array_mut().unwrap();
        // near misses: another version, another archive format, a checksum
        // file, and the name the CLI gives an Intel Mac rather than the archive
        assets.push(asset("compactc_v0.36.0_x86_64-darwin.zip"));
        assets.push(asset("compactc_v0.36.1_x86_64-unknown-linux-musl.tar.gz"));
        assets.push(asset(
            "compactc_v0.36.1_aarch64-unknown-linux-musl.zip.sha256",
        ));
        assets.push(asset("compactc_v0.36.1_x86_64-apple-darwin.zip"));

        let compilers = compilers_of(listing(vec![build])).unwrap();
        let compiler = &compilers[&Version::new(0, 36, 1)];

        assert_eq!(
            compiler
                .aarch64_macos
                .as_ref()
                .map(|archive| archive.name.as_str()),
            Some("compactc_v0.36.1_aarch64-darwin.zip")
        );
        assert_eq!(compiler.x86_macos, None);
        assert_eq!(compiler.x86_linux, None);
        assert_eq!(compiler.aarch64_linux, None);
    }

    #[test]
    fn each_platform_is_its_own_archive() {
        let compilers = compilers_of(listing(vec![release("compactc-v0.36.1", &ALL)])).unwrap();
        let compiler = &compilers[&Version::new(0, 36, 1)];

        for (target, name) in [
            (
                Target::x86_64AppleDarwin,
                "compactc_v0.36.1_x86_64-darwin.zip",
            ),
            (
                Target::Aarch64AppleDarwin,
                "compactc_v0.36.1_aarch64-darwin.zip",
            ),
            (
                Target::x86_64UnknownLinuxMusl,
                "compactc_v0.36.1_x86_64-unknown-linux-musl.zip",
            ),
            (
                Target::Aarch64UnknownLinuxMusl,
                "compactc_v0.36.1_aarch64-unknown-linux-musl.zip",
            ),
        ] {
            let archive = compiler.archive(target).unwrap();
            assert_eq!(archive.name, name);
            assert_eq!(
                archive.url.as_str(),
                format!("https://example.com/download/{name}")
            );
            assert_eq!(archive.size, 3);
            assert_eq!(archive.digest, Digest::Sha256(DIGEST.parse().unwrap()));
        }
    }

    #[test]
    fn digests_are_read_as_github_writes_them() {
        assert_eq!(
            Digest::of(Some(&format!("sha256:{DIGEST}"))),
            Digest::Sha256(DIGEST.parse().unwrap())
        );
        assert_eq!(Digest::of(None), Digest::Missing);
        assert_eq!(
            Digest::of(Some("sha512:abcd")),
            Digest::Unsupported("sha512:abcd".to_owned())
        );
        assert_eq!(
            Digest::of(Some("sha256:abcd")),
            Digest::Unsupported("sha256:abcd".to_owned())
        );
        assert_eq!(
            DIGEST.parse::<Sha256>().unwrap().to_string(),
            DIGEST,
            "a digest is written as it was read"
        );
        assert!(DIGEST.to_uppercase().parse::<Sha256>().is_ok());
        assert!(format!("{}g", &DIGEST[1..]).parse::<Sha256>().is_err());
    }

    #[test]
    fn two_releases_of_one_version_are_an_error() {
        let error = compilers_of(listing(vec![
            release("compactc-v0.36.1", &ALL),
            release("compactc-v0.36.1", &ALL),
        ]))
        .unwrap_err();

        assert_eq!(
            error.to_string(),
            "LFDT-Minokawa/compact has more than one release of 0.36.1"
        );
    }

    #[test]
    fn the_next_page_is_read_from_the_link_header() {
        let mut headers = header::HeaderMap::new();
        headers.insert(
            header::LINK,
            "<https://api.github.com/repositories/1/releases?per_page=100&page=2>; rel=\"next\", \
             <https://api.github.com/repositories/1/releases?per_page=100&page=3>; rel=\"last\""
                .parse()
                .unwrap(),
        );

        assert_eq!(
            next_page(&headers).unwrap().unwrap().as_str(),
            "https://api.github.com/repositories/1/releases?per_page=100&page=2"
        );

        headers.insert(
            header::LINK,
            "<https://api.github.com/repositories/1/releases?per_page=100&page=1>; rel=\"prev\""
                .parse()
                .unwrap(),
        );
        assert_eq!(next_page(&headers).unwrap(), None);

        assert_eq!(next_page(&header::HeaderMap::new()).unwrap(), None);
    }

    /// wiremock answers with the first mock mounted that matches, and the
    /// first page's mock matches every page, so the later page is mounted
    /// first.
    #[tokio::test]
    async fn every_page_is_read() {
        let (server, source) = server().await;

        Mock::given(method("GET"))
            .and(path("/repos/LFDT-Minokawa/compact/releases"))
            .and(query_param("per_page", "100"))
            .and(query_param("page", "2"))
            .respond_with(
                ResponseTemplate::new(200)
                    .set_body_json(json!([release("compactc-v0.31.0", &ALL)])),
            )
            .mount(&server)
            .await;

        Mock::given(method("GET"))
            .and(path("/repos/LFDT-Minokawa/compact/releases"))
            .and(query_param("per_page", "100"))
            .respond_with(
                ResponseTemplate::new(200)
                    .insert_header(
                        "link",
                        format!("<{source}?per_page=100&page=2>; rel=\"next\"").as_str(),
                    )
                    .set_body_json(json!([release("compactc-v0.36.1", &ALL)])),
            )
            .mount(&server)
            .await;

        assert_eq!(
            versions(&load(&source, None).await.unwrap()),
            ["0.31.0", "0.36.1"]
        );
    }

    #[tokio::test]
    async fn the_token_is_sent_when_there_is_one() {
        let (server, source) = server().await;

        Mock::given(method("GET"))
            .and(has_header("authorization", "Bearer a-token"))
            .and(has_header("accept", "application/vnd.github+json"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!([])))
            .expect(1)
            .mount(&server)
            .await;

        load(&source, Some("a-token")).await.unwrap();
    }

    struct NoAuthorization;

    impl Match for NoAuthorization {
        fn matches(&self, request: &Request) -> bool {
            !request.headers.contains_key("authorization")
        }
    }

    #[tokio::test]
    async fn no_token_is_sent_when_there_is_none() {
        let (server, source) = server().await;

        Mock::given(method("GET"))
            .and(NoAuthorization)
            .respond_with(ResponseTemplate::new(200).set_body_json(json!([])))
            .expect(1)
            .mount(&server)
            .await;

        load(&source, None).await.unwrap();
    }

    #[tokio::test]
    async fn an_error_on_githubs_side_is_tried_again() {
        let (server, source) = server().await;

        Mock::given(method("GET"))
            .respond_with(
                ResponseTemplate::new(200)
                    .set_body_json(json!([release("compactc-v0.36.1", &ALL)])),
            )
            .mount(&server)
            .await;

        Mock::given(method("GET"))
            .respond_with(ResponseTemplate::new(502))
            .up_to_n_times(1)
            .with_priority(1)
            .mount(&server)
            .await;

        assert_eq!(versions(&load(&source, None).await.unwrap()), ["0.36.1"]);
    }

    #[tokio::test]
    async fn an_error_on_githubs_side_every_time_is_reported() {
        let (server, source) = server().await;

        Mock::given(method("GET"))
            .respond_with(ResponseTemplate::new(500))
            .expect(3)
            .mount(&server)
            .await;

        let error = load(&source, None).await.unwrap_err();
        assert!(
            error
                .to_string()
                .starts_with("GitHub answered 500 Internal Server Error"),
            "{error}"
        );
    }

    #[tokio::test]
    async fn a_refusal_is_reported_at_once_with_githubs_message() {
        for status in [400, 401, 404] {
            let (server, source) = server().await;

            Mock::given(method("GET"))
                .respond_with(
                    ResponseTemplate::new(status).set_body_json(json!({ "message": "Not Found" })),
                )
                .expect(1)
                .mount(&server)
                .await;

            let error = load(&source, None).await.unwrap_err();
            assert!(error.to_string().contains(&status.to_string()), "{error}");
            assert!(error.to_string().ends_with(": Not Found"), "{error}");
        }
    }

    #[tokio::test]
    async fn the_rate_limit_is_named_with_the_way_round_it() {
        for status in [403, 429] {
            let (server, source) = server().await;
            let reset = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs()
                + 600;

            Mock::given(method("GET"))
                .respond_with(
                    ResponseTemplate::new(status)
                        .insert_header("x-ratelimit-remaining", "0")
                        .insert_header("x-ratelimit-reset", reset.to_string().as_str())
                        .set_body_json(json!({ "message": "API rate limit exceeded" })),
                )
                .expect(1)
                .mount(&server)
                .await;

            let error = load(&source, None).await.unwrap_err().to_string();
            assert!(
                error.contains("rate limit is used up for the next 10 minute(s)"),
                "{error}"
            );
            assert!(error.contains("GITHUB_TOKEN"), "{error}");
        }
    }

    #[tokio::test]
    async fn a_forbidden_answer_with_requests_left_is_not_the_rate_limit() {
        let (server, source) = server().await;

        Mock::given(method("GET"))
            .respond_with(
                ResponseTemplate::new(403)
                    .insert_header("x-ratelimit-remaining", "59")
                    .set_body_json(json!({ "message": "Resource not accessible" })),
            )
            .mount(&server)
            .await;

        let error = load(&source, None).await.unwrap_err().to_string();
        assert!(error.ends_with(": Resource not accessible"), "{error}");
    }

    #[tokio::test]
    async fn a_listing_that_is_not_releases_is_an_error() {
        let (server, source) = server().await;

        Mock::given(method("GET"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({ "not": "a list" })))
            .mount(&server)
            .await;

        let error = load(&source, None).await.unwrap_err();
        assert!(
            error
                .to_string()
                .starts_with("Failed to read the release listing"),
            "{error}"
        );
    }

    #[tokio::test]
    async fn a_listing_that_never_ends_is_an_error() {
        let (server, source) = server().await;
        let next = format!("<{source}?per_page=100&page=2>; rel=\"next\"");

        Mock::given(method("GET"))
            .respond_with(
                ResponseTemplate::new(200)
                    .insert_header("link", next.as_str())
                    .set_body_json(json!([])),
            )
            .mount(&server)
            .await;

        let error = load(&source, None).await.unwrap_err();
        assert_eq!(error.to_string(), "The release listing ran past 100 pages");
    }

    fn artifacts(versions: &[&str]) -> MidnightArtifacts {
        let releases = versions
            .iter()
            .map(|version| release(&format!("compactc-v{version}"), &ALL))
            .collect();

        MidnightArtifacts {
            compilers: compilers_of(listing(releases)).unwrap(),
        }
    }

    #[tokio::test]
    async fn the_cache_returns_what_was_saved_while_it_is_fresh() {
        let directory = tempfile::tempdir().unwrap();
        let file = directory.path().join("nested").join("cache.json");
        let saved = artifacts(&["0.36.1", "0.37.0-rc.0"]);

        save_to_cache(&file, RELEASES_URL, &saved).await.unwrap();

        let now = SystemTime::now();
        assert_eq!(load_from_cache(&file, RELEASES_URL, now).await, Some(saved));

        let later = now + Duration::from_secs(CACHE_TTL_SECONDS + 1);
        assert_eq!(load_from_cache(&file, RELEASES_URL, later).await, None);

        assert_eq!(
            load_from_cache(&file, "https://example.com/elsewhere", now).await,
            None,
            "a listing of another repository is not this one"
        );

        let names: Vec<_> = std::fs::read_dir(file.parent().unwrap())
            .unwrap()
            .map(|entry| entry.unwrap().file_name())
            .collect();
        assert_eq!(names, ["cache.json"], "nothing is left beside the cache");
    }

    #[tokio::test]
    async fn a_cache_this_cli_did_not_write_is_not_read() {
        let directory = tempfile::tempdir().unwrap();
        let file = directory.path().join("cache.json");
        let now = SystemTime::now();

        assert_eq!(load_from_cache(&file, RELEASES_URL, now).await, None);

        // the older CLI's `github_cache.json', shaped as it wrote it
        std::fs::write(
            &file,
            json!({
                "artifacts": { "compilers": {} },
                "cached_at": now.duration_since(UNIX_EPOCH).unwrap().as_secs(),
                "rate_limit_remaining": null,
                "rate_limit_reset": null,
            })
            .to_string(),
        )
        .unwrap();
        assert_eq!(load_from_cache(&file, RELEASES_URL, now).await, None);

        save_to_cache(&file, RELEASES_URL, &artifacts(&["0.36.1"]))
            .await
            .unwrap();
        let mut cached: Value =
            serde_json::from_str(&std::fs::read_to_string(&file).unwrap()).unwrap();
        cached["schema"] = json!(CACHE_SCHEMA + 1);
        std::fs::write(&file, cached.to_string()).unwrap();
        assert_eq!(load_from_cache(&file, RELEASES_URL, now).await, None);

        std::fs::write(&file, "{ not json").unwrap();
        assert_eq!(load_from_cache(&file, RELEASES_URL, now).await, None);
    }

    /// Every release offered has all four platforms; one that lacked an
    /// archive for the machine would be refused by name rather than install
    /// another platform's.
    #[test]
    fn a_platform_without_an_archive_is_refused() {
        use clap::Parser as _;

        let compilers = compilers_of(listing(vec![release(
            "compactc-v0.36.1",
            &[
                "aarch64-darwin",
                "x86_64-darwin",
                "aarch64-unknown-linux-musl",
            ],
        )]))
        .unwrap();
        let compiler = &compilers[&Version::new(0, 36, 1)];
        let directory = tempfile::tempdir().unwrap();

        let cfg = CommandLineArguments::try_parse_from([
            "compact",
            "--directory",
            directory.path().to_str().unwrap(),
            "--target",
            "x86_64-unknown-linux-musl",
            "list",
        ])
        .unwrap();

        let error = compiler.compiler(&cfg).err().unwrap();
        assert_eq!(
            error.to_string(),
            "Unsupported compiler platform: x86_64-unknown-linux-musl"
        );
    }

    #[test]
    fn the_cache_files_are_apart() {
        assert_ne!(cache_path().unwrap(), legacy_cache_path().unwrap());
        assert_eq!(
            cache_path().unwrap().parent(),
            legacy_cache_path().unwrap().parent()
        );
    }
}
