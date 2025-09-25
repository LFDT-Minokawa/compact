use std::{
    fmt,
    ops::Deref,
    path::{Path, PathBuf},
    str,
};

const COMPACTUP_BIN_DIR: &str = "bin";
pub const COMPACTUP_VERSIONS_DIR: &str = "versions";

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct CompactDirectory(PathBuf);

impl CompactDirectory {
    pub fn bin_dir(&self) -> PathBuf {
        self.0.join(COMPACTUP_BIN_DIR)
    }

    pub fn versions_dir(&self) -> PathBuf {
        self.0.join(COMPACTUP_VERSIONS_DIR)
    }
}

impl fmt::Display for CompactDirectory {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.display().fmt(f)
    }
}

impl str::FromStr for CompactDirectory {
    type Err = <PathBuf as str::FromStr>::Err;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        PathBuf::from_str(s).map(Self)
    }
}

impl Default for CompactDirectory {
    fn default() -> Self {
        dirs::home_dir()
            .map(|home| home.join(".compact"))
            .map(Self)
            .expect(
                r###"User system does not contain the expected environment variables.\
            Possible error: Missing $HOME."###,
            )
    }
}

impl AsRef<Path> for CompactDirectory {
    fn as_ref(&self) -> &Path {
        self.0.as_path()
    }
}

impl Deref for CompactDirectory {
    type Target = Path;
    fn deref(&self) -> &Self::Target {
        self.0.as_path()
    }
}
