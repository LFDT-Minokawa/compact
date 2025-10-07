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

use anyhow::{Context as _, Result, anyhow, bail, ensure};
use bytes::{Buf, BufMut, BytesMut};
use std::{
    ffi::OsStr,
    path::{Path, PathBuf},
};
use tokio::io::{AsyncReadExt as _, AsyncWriteExt as _, BufReader, BufWriter};

use super::progress::{HasLength, HasProgress, Poll};

#[derive(Debug, Clone)]
pub struct File {
    path: PathBuf,
}

pub struct Writer {
    written: u64,
    writter: BufWriter<tokio::fs::File>,
}

pub struct Reader {
    read: u64,
    reader: BufReader<tokio::fs::File>,
}

pub struct Copy {
    reader: Reader,
    writer: Writer,
}

impl Reader {
    fn new(reader: tokio::fs::File) -> Self {
        Self {
            read: 0,
            reader: BufReader::new(reader),
        }
    }

    pub async fn size(&self) -> Result<u64> {
        let metadata = self.reader.get_ref().metadata().await?;
        Ok(metadata.len())
    }

    pub async fn read(&mut self, into: &mut impl BufMut) -> Result<u64> {
        let written = self.reader.read_buf(into).await?;
        self.read += written as u64;

        Ok(written as u64)
    }
}

impl Writer {
    fn new(writter: tokio::fs::File) -> Self {
        Self {
            written: 0,
            writter: BufWriter::new(writter),
        }
    }

    pub fn written(&self) -> u64 {
        self.written
    }

    /// write the given bytes to the underlying writter
    ///
    pub async fn write(&mut self, bytes: &mut impl Buf) -> Result<u64> {
        let written = self.writter.write_buf(bytes).await?;
        self.writter.flush().await?;
        self.written += written as u64;

        Ok(written as u64)
    }
}

impl File {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Self { path: path.into() }
    }

    pub(crate) fn file_name(&self) -> Option<&OsStr> {
        self.path.file_name()
    }

    pub(crate) fn to_partial_file(&self) -> Result<Self> {
        if let Some(ext) = self.path.extension() {
            ensure!(ext != "partial")
        }
        let Some(mut filename) = self.path.file_name().map(|f| f.to_os_string()) else {
            bail!("not a file: `{}'", self.path.display())
        };
        filename.push(".partial");
        let partial = self.path.with_file_name(filename);

        Ok(Self { path: partial })
    }

    pub fn directory(&self) -> Option<&Path> {
        self.path.parent()
    }

    pub fn exist(&self) -> bool {
        self.path.is_file()
    }

    /// get the current size of the file
    pub async fn size(&self) -> Result<u64> {
        let reader = self.reader().await?;
        reader.size().await
    }

    /// open a file for readonly
    pub async fn reader(&self) -> Result<Reader> {
        tokio::fs::OpenOptions::new()
            .read(true)
            .write(false)
            .open(&self.path)
            .await
            .with_context(|| anyhow!("Failed to open file `{}'", self.path.display()))
            .map(Reader::new)
    }

    pub async fn writer(&self, create: bool, truncate: bool) -> Result<Writer> {
        tokio::fs::OpenOptions::new()
            .create(create)
            .read(false)
            .write(true)
            .truncate(truncate)
            .append(!truncate)
            .open(&self.path)
            .await
            .with_context(|| anyhow!("Failed to open file `{}'", self.path.display()))
            .map(Writer::new)
    }

    pub async fn rename(&mut self, to: impl AsRef<Path>) -> Result<()> {
        let to = to.as_ref();
        tokio::fs::rename(&self.path, to)
            .await
            .with_context(|| anyhow!("Failed to rename file to `{to:?}'"))?;
        self.path = to.to_path_buf();
        Ok(())
    }

    pub async fn copy(&self, to: File) -> Result<Copy> {
        let reader = self.reader().await?;
        let writer = to.writer(true, true).await?;

        Ok(Copy::new(reader, writer))
    }
}

impl Copy {
    fn new(reader: Reader, writer: Writer) -> Self {
        Self { reader, writer }
    }

    pub async fn total_length(&self) -> Result<u64> {
        self.reader.size().await
    }

    pub fn written(&self) -> u64 {
        self.writer.written
    }

    pub async fn step(&mut self) -> Result<u64> {
        let mut buffer = BytesMut::new();
        let read = self.reader.read(&mut buffer).await?;

        while buffer.has_remaining() {
            self.writer.write(&mut buffer).await?;
        }

        Ok(read)
    }
}

impl HasProgress for Copy {
    type Output = ();
    fn msg(&self) -> impl Into<std::borrow::Cow<'static, str>> {
        "Copying file"
    }

    async fn tick(&mut self) -> Result<Poll<Self::Output>> {
        let processed = self.step().await?;

        Ok(if processed != 0 {
            Poll::Continue
        } else {
            Poll::Done(())
        })
    }
}

impl HasLength for Copy {
    fn expected_length(&self) -> Option<u64> {
        futures::executor::block_on(async { self.reader.size().await }).ok()
    }
    fn current_length(&self) -> u64 {
        self.written()
    }
}

impl AsRef<Path> for File {
    fn as_ref(&self) -> &Path {
        self.path.as_path()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn partial() {
        let original = File::new("file.txt");
        let partial = original.to_partial_file().unwrap();

        assert_eq!(partial.path.to_string_lossy(), "file.txt.partial");
        assert!(partial.to_partial_file().is_err());

        let original = File::new("file");
        let partial = original.to_partial_file().unwrap();

        assert_eq!(partial.path.to_string_lossy(), "file.partial");
    }
}
