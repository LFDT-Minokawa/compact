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

/* eslint-disable @typescript-eslint/restrict-template-expressions */
import { expect, jest } from '@jest/globals';
import { Logger } from 'tslog';

jest.setTimeout(180_000);

const log = new Logger({ name: 'Jest' });

beforeEach(() => {
  log.info(`Running test: ${expect.getState().currentTestName}`);
});

afterEach(() => {
  log.info(`Finished test: ${expect.getState().currentTestName}}`);
});
