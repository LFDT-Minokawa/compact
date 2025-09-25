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
    file::{File, Writer},
    progress::{HasLength, HasProgress, Poll},
};
use anyhow::{Context, Result, anyhow};
use bytes::{Buf, Bytes};
use futures::{Stream, StreamExt as _};
use reqwest::{IntoUrl, header};
use serde::de::DeserializeOwned;
use std::pin::Pin;

const APP_USER_AGENT: &str = concat!(env!("CARGO_PKG_NAME"), "/", env!("CARGO_PKG_VERSION"),);

/// handle HTTP client requests
pub struct Client {
    client: reqwest::Client,
}

pub struct Download {
    content_length: Option<u64>,
    downloaded: u64,
    content: Pin<Box<dyn Stream<Item = Result<Bytes>>>>,
}

pub struct DownloadToFile {
    download: Download,
    file: File,
    partial_file: File,
    partial_writer: Writer,
    written: u64,
}

impl DownloadToFile {
    async fn new(client: &Client, url: impl IntoUrl, file: File) -> Result<Self> {
        let partial_file = file.to_partial_file()?;

        let partial_size = partial_file.size().await.ok();

        let written = partial_size.unwrap_or_default();
        let download = client.download(url, partial_size).await?;

        let partial_writer = partial_file.writer(true, false).await?;

        Ok(Self {
            download,
            file,
            partial_file,
            partial_writer,
            written,
        })
    }

    pub fn content_length(&self) -> Option<u64> {
        self.download.content_length()
    }

    pub fn downloaded(&self) -> u64 {
        self.written
    }

    pub async fn step(&mut self) -> Result<Option<()>> {
        if let Some(mut chunk) = self.download.next().await? {
            while chunk.has_remaining() {
                self.written += self.partial_writer.write(&mut chunk).await?;
            }
            Ok(Some(()))
        } else {
            self.partial_file.rename(&self.file).await?;

            Ok(None)
        }
    }
}

impl HasLength for DownloadToFile {
    fn current_length(&self) -> u64 {
        self.written
    }

    fn expected_length(&self) -> Option<u64> {
        self.download.content_length()
    }
}

impl HasProgress for DownloadToFile {
    type Output = File;

    fn msg(&self) -> impl Into<std::borrow::Cow<'static, str>> {
        format!(
            "Downloading {:?}",
            self.file
                .file_name()
                .expect("Downloading a file should always be to a file with a filename")
        )
    }

    async fn tick(&mut self) -> Result<Poll<Self::Output>> {
        if let Some(mut chunk) = self.download.next().await? {
            while chunk.has_remaining() {
                self.written += self.partial_writer.write(&mut chunk).await?;
            }
            Ok(Poll::Continue)
        } else {
            self.partial_file.rename(&self.file).await?;

            Ok(Poll::Done(self.file.clone()))
        }
    }
}

impl Download {
    fn new(
        content_length: Option<u64>,
        content: impl Stream<Item = Result<Bytes>> + 'static,
        downloaded: u64,
    ) -> Self {
        Self {
            content_length,
            downloaded,
            content: Box::pin(content),
        }
    }

    /// return the number of bytes already processed so far
    #[inline]
    pub fn downloaded(&self) -> u64 {
        self.downloaded
    }

    /// return the potential number of bytes expected to download
    ///
    /// It is possible this value is not available because the server
    /// didn't return it.
    #[inline]
    pub fn content_length(&self) -> Option<u64> {
        self.content_length
    }

    pub async fn next(&mut self) -> Result<Option<Bytes>> {
        let Some(result) = self.content.next().await else {
            return Ok(None);
        };

        let bytes = result.context("Failed to download anymore bytes")?;

        self.downloaded += bytes.len() as u64;
        Ok(Some(bytes))
    }
}

impl Client {
    pub fn new() -> Result<Self> {
        let client = reqwest::ClientBuilder::new()
            .gzip(true)
            .user_agent(APP_USER_AGENT)
            .build()
            .context("Failed to create HTTP Client")?;
        Ok(Self { client })
    }

    pub async fn download_to_file<U>(&self, url: U, file: File) -> Result<DownloadToFile>
    where
        U: IntoUrl,
    {
        DownloadToFile::new(self, url, file).await
    }

    pub async fn download<U>(&self, url: U, from: Option<u64>) -> Result<Download>
    where
        U: IntoUrl,
    {
        let raw_url = url.as_str().to_owned();

        self.download_(url, from)
            .await
            .with_context(|| anyhow!("Error with Download request to: `{raw_url}'"))
    }

    async fn download_<U>(&self, url: U, from: Option<u64>) -> Result<Download>
    where
        U: IntoUrl,
    {
        let raw_url = url.as_str().to_owned();
        let url = url
            .into_url()
            .with_context(|| anyhow!("Not a valid URL: {raw_url}"))?;
        let mut request = self.client.get(url.clone());
        let downloaded = if let Some(from) = from {
            request = request.header(header::RANGE, format!("bytes={from}-"));
            from
        } else {
            0
        };
        let request = request.build().context("Failed to create HTTP request")?;

        let response = self
            .client
            .execute(request)
            .await
            .context("Failed to execute HTTP Get request")?
            .error_for_status()
            .context("HTTP Get request returned error")?;

        let content_length = response.content_length().map(|c| downloaded + c);
        let content_download = response
            .bytes_stream()
            .map(move |v| v.with_context(|| anyhow!("Error while receiving bytes from `{url}'")));

        Ok(Download::new(content_length, content_download, downloaded))
    }

    pub async fn get_json<O, U>(&self, url: U) -> Result<O>
    where
        U: IntoUrl,
        O: DeserializeOwned,
    {
        let raw_url = url.as_str().to_owned();

        self.get_json_(url)
            .await
            .with_context(|| anyhow!("Error with HTTP GET request to: `{raw_url}'"))
    }

    #[inline]
    async fn get_json_<O, U>(&self, url: U) -> Result<O>
    where
        U: IntoUrl,
        O: DeserializeOwned,
    {
        let request = self
            .client
            .get(url)
            .header("Accept", "application/json")
            .build()
            .context("Failed to create HTTP request")?;

        let response = self
            .client
            .execute(request)
            .await
            .context("Failed to execute HTTP Get request")?
            .error_for_status()
            .context("HTTP Get request returned error")?;

        response
            .json()
            .await
            .context("Failed to decode the JSON response body")
    }
}
