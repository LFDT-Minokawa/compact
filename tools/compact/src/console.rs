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

use std::fmt;

use console::{Emoji, StyledObject};
use semver::Version;

use crate::Target;

#[derive(Debug, Clone)]
pub struct Style {
    version: console::Style,
    target: console::Style,
    artifact: console::Style,

    pub label: console::Style,
    success: console::Style,
    warning: console::Style,
    error: console::Style,
}

#[derive(Clone)]
pub struct Icons {
    pub arrow: console::Emoji<'static, 'static>,
}

impl Default for Style {
    fn default() -> Self {
        Self {
            version: console::Style::new().cyan().bold(),
            target: console::Style::new().white().bold(),
            artifact: console::Style::new().italic(),

            label: console::Style::new().magenta().bold(),
            success: console::Style::new().green().bold(),
            warning: console::Style::new().yellow(),
            error: console::Style::new().red(),
        }
    }
}
impl Style {
    pub fn label(&self) -> StyledObject<&'static str> {
        self.label.apply_to("compact")
    }

    pub fn artifact<D>(&self, artifact: D) -> StyledObject<D> {
        self.artifact.apply_to(artifact)
    }

    pub fn target(&self, target: Target) -> StyledObject<Target> {
        self.target.apply_to(target)
    }

    pub fn version(&self, version: Version) -> StyledObject<Version> {
        self.version.apply_to(version)
    }

    pub fn version_raw<D>(&self, message: D) -> StyledObject<D> {
        self.version.apply_to(message)
    }

    pub fn success<D>(&self, message: D) -> StyledObject<D> {
        self.success.apply_to(message)
    }

    pub fn warn<D>(&self, message: D) -> StyledObject<D> {
        self.warning.apply_to(message)
    }

    pub fn error<D>(&self, val: D) -> StyledObject<D> {
        self.error.apply_to(val)
    }
}

impl Default for Icons {
    fn default() -> Self {
        Self {
            arrow: Emoji::new("→", "->"),
        }
    }
}

impl fmt::Debug for Icons {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Icons").finish_non_exhaustive()
    }
}
