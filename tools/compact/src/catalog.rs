// This file is part of Compact.
// Copyright (C) 2026 Minokawa project contributors
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

//! What a release source offers, each version in its channel: releases,
//! which `compact update' may choose by itself, and release candidates, which
//! it installs only when named by their exact version.

use crate::{
    VersionSpec,
    fetch::{MidnightArtifacts, MidnightCompiler},
};
use anyhow::{Result, anyhow};
use semver::Version;
use std::collections::BTreeMap;

/// Whether a version is a release or a release candidate.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Channel {
    Release,
    Candidate,
}

impl Channel {
    /// A candidate's version has a prerelease part (`0.36.0-rc.0'), a
    /// release's does not. Any suffix counts, not only `rc', because the
    /// internal release workflow publishes every suffixed version as a
    /// candidate.
    pub fn of(version: &Version) -> Self {
        if version.pre.is_empty() {
            Channel::Release
        } else {
            Channel::Candidate
        }
    }
}

/// The released versions. Only these answer a specifier other than an exact
/// version, so a candidate cannot be chosen without being named.
#[derive(Debug)]
pub struct Releases(BTreeMap<Version, MidnightCompiler>);

/// The release candidates, installed only by their exact version.
#[derive(Debug)]
pub struct Candidates(BTreeMap<Version, MidnightCompiler>);

/// Everything a release source offers, split by channel.
#[derive(Debug)]
pub struct Catalog {
    releases: Releases,
    candidates: Candidates,
}

impl From<MidnightArtifacts> for Catalog {
    fn from(artifacts: MidnightArtifacts) -> Self {
        let (candidates, releases) = artifacts
            .compilers
            .into_iter()
            .partition(|(version, _)| Channel::of(version) == Channel::Candidate);

        Self {
            releases: Releases(releases),
            candidates: Candidates(candidates),
        }
    }
}

impl Catalog {
    pub fn releases(&self) -> &Releases {
        &self.releases
    }

    pub fn candidates(&self) -> &Candidates {
        &self.candidates
    }

    /// The compiler a version specifier names. An exact version is looked up
    /// in its own channel, so a candidate is found only by its exact version;
    /// `0.36' and `0' name the newest matching release and never a candidate,
    /// which is what the release notes promise of `compact update 0.36'.
    pub fn resolve(&self, spec: &VersionSpec) -> Result<(Version, MidnightCompiler)> {
        let found = match spec {
            VersionSpec::Exact(version) => match Channel::of(version) {
                Channel::Release => self.releases.0.get_key_value(version),
                Channel::Candidate => self.candidates.0.get_key_value(version),
            },
            VersionSpec::Partial { .. } | VersionSpec::Major { .. } => {
                self.releases.newest_matching(spec)
            }
        };

        match (found, spec) {
            (Some((version, compiler)), _) => Ok((version.clone(), compiler.clone())),
            (None, VersionSpec::Exact(version)) => Err(anyhow!("Couldn't find version {version}")),
            (None, _) => Err(anyhow!("No version matching {spec} found")),
        }
    }

    /// The release a candidate was a candidate for, once it has shipped: the
    /// release with the candidate's major, minor and patch. A candidate whose
    /// release never shipped (`0.33.0-rc.2') has none.
    pub fn superseded_by(&self, candidate: &Version) -> Option<&Version> {
        let release = Version::new(candidate.major, candidate.minor, candidate.patch);

        self.releases
            .0
            .get_key_value(&release)
            .map(|(version, _)| version)
    }
}

impl Releases {
    /// The newest release, which is what `compact update' installs when no
    /// version is given.
    pub fn latest(&self) -> Option<(&Version, &MidnightCompiler)> {
        self.0.last_key_value()
    }

    pub fn iter(&self) -> impl DoubleEndedIterator<Item = (&Version, &MidnightCompiler)> {
        self.0.iter()
    }

    fn newest_matching(&self, spec: &VersionSpec) -> Option<(&Version, &MidnightCompiler)> {
        self.0
            .iter()
            .rev()
            .find(|(version, _)| spec.matches(version))
    }
}

impl Candidates {
    pub fn iter(&self) -> impl DoubleEndedIterator<Item = (&Version, &MidnightCompiler)> {
        self.0.iter()
    }
}

/// Where the default compiler stands against the latest release.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Standing {
    /// The latest release, or a release newer than it.
    UpToDate,
    /// Older than the latest release; a candidate whose release has since
    /// shipped is here too, since `0.36.0-rc.1' precedes `0.36.0'.
    UpdateAvailable,
    /// A candidate newer than every release. A plain `compact update' keeps
    /// it rather than move the default backwards to the latest release.
    CandidateAhead,
}

impl Standing {
    pub fn of(default: &Version, latest_release: &Version) -> Self {
        if default < latest_release {
            Standing::UpdateAvailable
        } else {
            match Channel::of(default) {
                Channel::Release => Standing::UpToDate,
                Channel::Candidate => Standing::CandidateAhead,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_compiler(version: Version) -> MidnightCompiler {
        MidnightCompiler {
            version,
            x86_macos: None,
            aarch64_macos: None,
            x86_linux: None,
            aarch64_linux: None,
        }
    }

    fn make_catalog(versions: &[&str]) -> Catalog {
        let compilers = versions
            .iter()
            .map(|v| {
                let version = Version::parse(v).unwrap();
                (version.clone(), make_compiler(version))
            })
            .collect();

        Catalog::from(MidnightArtifacts { compilers })
    }

    fn resolve(catalog: &Catalog, spec: &str) -> Result<Version> {
        catalog
            .resolve(&spec.parse().unwrap())
            .map(|(version, _)| version)
    }

    fn versions<'a>(
        iter: impl Iterator<Item = (&'a Version, &'a MidnightCompiler)>,
    ) -> Vec<String> {
        iter.map(|(version, _)| version.to_string()).collect()
    }

    #[test]
    fn a_prerelease_part_makes_a_candidate() {
        for candidate in [
            "0.36.0-rc.0",
            "0.36.0-beta.1",
            "0.36.0-test.0",
            "0.36.100-rc.0-a-b-c",
        ] {
            assert_eq!(
                Channel::of(&Version::parse(candidate).unwrap()),
                Channel::Candidate,
                "{candidate}"
            );
        }

        assert_eq!(
            Channel::of(&Version::parse("0.36.0").unwrap()),
            Channel::Release
        );
    }

    #[test]
    fn versions_are_split_by_channel() {
        let catalog = make_catalog(&["0.35.0", "0.36.0-rc.0", "0.35.0-rc.1", "0.34.0"]);

        assert_eq!(versions(catalog.releases().iter()), ["0.34.0", "0.35.0"]);
        assert_eq!(
            versions(catalog.candidates().iter()),
            ["0.35.0-rc.1", "0.36.0-rc.0"]
        );
    }

    #[test]
    fn resolve_exact_version_found() {
        let catalog = make_catalog(&["0.28.0", "0.29.0", "0.29.1"]);
        assert_eq!(resolve(&catalog, "0.29.0").unwrap(), Version::new(0, 29, 0));
    }

    #[test]
    fn resolve_exact_version_not_found() {
        let catalog = make_catalog(&["0.28.0", "0.29.0"]);
        let err = resolve(&catalog, "0.30.0").unwrap_err();
        assert_eq!(err.to_string(), "Couldn't find version 0.30.0");
    }

    #[test]
    fn resolve_partial_picks_latest_patch() {
        let catalog = make_catalog(&["0.28.0", "0.29.0", "0.29.1", "0.29.2", "0.30.0"]);
        assert_eq!(resolve(&catalog, "0.29").unwrap(), Version::new(0, 29, 2));
    }

    #[test]
    fn resolve_partial_single_patch() {
        let catalog = make_catalog(&["0.28.0", "0.29.0"]);
        assert_eq!(resolve(&catalog, "0.29").unwrap(), Version::new(0, 29, 0));
    }

    #[test]
    fn resolve_partial_not_found() {
        let catalog = make_catalog(&["0.28.0", "0.29.0"]);
        let err = resolve(&catalog, "0.30").unwrap_err();
        assert_eq!(err.to_string(), "No version matching 0.30 found");
    }

    #[test]
    fn resolve_major_picks_latest() {
        let catalog = make_catalog(&["0.28.0", "0.29.0", "0.29.1", "1.0.0", "1.1.0", "1.1.1"]);
        assert_eq!(resolve(&catalog, "1").unwrap(), Version::new(1, 1, 1));
    }

    #[test]
    fn resolve_major_single_version() {
        let catalog = make_catalog(&["0.28.0", "1.0.0"]);
        assert_eq!(resolve(&catalog, "1").unwrap(), Version::new(1, 0, 0));
    }

    #[test]
    fn resolve_major_not_found() {
        let catalog = make_catalog(&["0.28.0", "0.29.0"]);
        let err = resolve(&catalog, "1").unwrap_err();
        assert_eq!(err.to_string(), "No version matching 1 found");
    }

    #[test]
    fn a_candidate_is_found_by_its_exact_version() {
        let catalog = make_catalog(&["0.35.0", "0.36.0-rc.0", "0.36.0-rc.1"]);

        assert_eq!(
            resolve(&catalog, "0.36.0-rc.0").unwrap(),
            Version::parse("0.36.0-rc.0").unwrap()
        );
        assert_eq!(
            resolve(&catalog, "0.36.0-rc.2").unwrap_err().to_string(),
            "Couldn't find version 0.36.0-rc.2"
        );
    }

    #[test]
    fn a_partial_or_major_specifier_never_resolves_to_a_candidate() {
        // Each of these candidates outranks 0.36.0 or 0.35.0 in semver's
        // order, and the feature-branch build outranks the 0.36.0 release
        // itself.
        let catalog = make_catalog(&[
            "0.35.0",
            "0.36.0-rc.2",
            "0.36.0-test.0",
            "0.36.100-rc.0-a-b-c",
        ]);

        assert_eq!(
            resolve(&catalog, "0.36").unwrap_err().to_string(),
            "No version matching 0.36 found"
        );
        assert_eq!(resolve(&catalog, "0").unwrap(), Version::new(0, 35, 0));
        assert_eq!(resolve(&catalog, "0.35").unwrap(), Version::new(0, 35, 0));
    }

    #[test]
    fn the_latest_release_is_never_a_candidate() {
        let catalog = make_catalog(&["0.34.0", "0.35.0", "0.36.0-rc.0", "0.36.100-rc.0-a-b-c"]);

        let (latest, _) = catalog.releases().latest().unwrap();
        assert_eq!(latest, &Version::new(0, 35, 0));
    }

    #[test]
    fn no_release_means_no_latest_even_with_candidates() {
        let catalog = make_catalog(&["0.36.0-rc.0"]);

        assert!(catalog.releases().latest().is_none());
    }

    #[test]
    fn a_candidate_is_superseded_once_its_release_ships() {
        let catalog = make_catalog(&[
            "0.34.0",
            "0.35.0",
            "0.35.0-rc.1",
            "0.33.0-rc.2",
            "0.36.0-rc.0",
        ]);

        let superseded_by = |candidate: &str| {
            catalog
                .superseded_by(&Version::parse(candidate).unwrap())
                .cloned()
        };

        assert_eq!(superseded_by("0.35.0-rc.1"), Some(Version::new(0, 35, 0)));
        assert_eq!(superseded_by("0.35.0-rc.0"), Some(Version::new(0, 35, 0)));
        assert_eq!(superseded_by("0.36.0-rc.0"), None);
        // 0.33.0 never shipped; the next release is not its release.
        assert_eq!(superseded_by("0.33.0-rc.2"), None);
    }

    #[test]
    fn standing_against_the_latest_release() {
        let standing = |default: &str| {
            Standing::of(&Version::parse(default).unwrap(), &Version::new(0, 35, 0))
        };

        assert_eq!(standing("0.35.0"), Standing::UpToDate);
        assert_eq!(standing("0.34.0"), Standing::UpdateAvailable);
        // A candidate for the latest release, or for one before it, is
        // behind that release.
        assert_eq!(standing("0.35.0-rc.1"), Standing::UpdateAvailable);
        assert_eq!(standing("0.33.0-rc.2"), Standing::UpdateAvailable);
        // A candidate for a release still to come is ahead of the latest.
        assert_eq!(standing("0.36.0-rc.0"), Standing::CandidateAhead);
        assert_eq!(standing("0.35.1-rc.0"), Standing::CandidateAhead);
    }
}
