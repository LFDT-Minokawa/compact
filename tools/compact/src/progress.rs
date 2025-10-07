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

use std::borrow::Cow;

use anyhow::Result;
use futures::Future;
use indicatif::{ProgressBar, ProgressFinish, ProgressStyle};

pub enum Poll<T> {
    Done(T),
    Continue,
}

#[allow(async_fn_in_trait)]
pub trait HasProgress {
    type Output;
    fn msg(&self) -> impl Into<Cow<'static, str>>;
    async fn tick(&mut self) -> Result<Poll<Self::Output>>;
}

pub trait HasLength: HasProgress {
    fn expected_length(&self) -> Option<u64>;
    fn current_length(&self) -> u64;
}

impl<TASK: HasProgress> HasProgress for &mut TASK {
    type Output = TASK::Output;
    fn msg(&self) -> impl Into<Cow<'static, str>> {
        <TASK as HasProgress>::msg(*self)
    }
    async fn tick(&mut self) -> Result<Poll<Self::Output>> {
        <TASK as HasProgress>::tick(*self).await
    }
}

const PROGRESS_TEMPLATE: &str =
    "[{elapsed_precise}] [{bar:40.cyan/blue}] {msg} {bytes}/{total_bytes} ({bytes_per_sec}, {eta})";
const SPINNER_TEMPLATE: &str = "[{elapsed_precise}] {spinner} {msg}";
const INDICATIF_LENGTH: u64 = 100;

pub async fn future<F, O>(msg: impl Into<Cow<'static, str>>, task: F) -> Result<O>
where
    F: Future<Output = Result<O>>,
{
    let style = ProgressStyle::default_spinner().template(SPINNER_TEMPLATE)?;
    let progress = ProgressBar::new_spinner()
        .with_style(style)
        .with_finish(ProgressFinish::AndClear);
    progress.enable_steady_tick(std::time::Duration::from_millis(200));

    progress.set_message(msg);

    let output = task.await;

    if output.is_err() {
        progress.abandon();
    } else {
        progress.finish_using_style()
    }

    output
}

pub async fn progress<TASK: HasLength>(mut task: TASK) -> Result<TASK::Output> {
    let style = ProgressStyle::default_bar().template(PROGRESS_TEMPLATE)?;
    let progress = ProgressBar::new(INDICATIF_LENGTH)
        .with_style(style)
        .with_finish(ProgressFinish::AndClear);

    progress.set_message(task.msg());

    if let Some(total) = task.expected_length() {
        progress.set_length(total);
    }

    loop {
        match task.tick().await {
            Err(error) => {
                progress.abandon();
                return Err(error);
            }
            Ok(Poll::Continue) => {
                progress.set_position(task.current_length());
                continue;
            }
            Ok(Poll::Done(t)) => {
                progress.finish_using_style();
                return Ok(t);
            }
        }
    }
}
