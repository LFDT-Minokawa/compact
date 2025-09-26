use std::fmt;

use console::{Emoji, StyledObject};
use semver::Version;

use crate::Target;

#[derive(Debug, Clone)]
pub struct Style {
    version: console::Style,
    target: console::Style,
    artifact: console::Style,

    label: console::Style,
    success: console::Style,
    warning: console::Style,
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
