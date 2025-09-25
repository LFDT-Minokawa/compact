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

export type Support = {
  patterns: Pattern[];
};

export type Keywords = {
  patterns: Pattern[];
};

export type Strings = {
  name: string;
  begin: string;
  end: string;
  patterns: Pattern[];
};

export type CaptureValues = {
  name: string;
};

export type Captures = {
  item: CaptureValues[];
};

export type Numbers = {
  patterns: Pattern[];
};

export type Pattern = {
  captures?: Record<string, { name: string }>;
  match?: string;
  name?: string;
  begin?: string;
  beginCaptures?: Record<string, { name: string }>;
  end?: string;
  endCaptures?: Record<string, { name: string }>;
};

export type Patterns = {
  include: string;
};

export type Comments = {
  patterns: Pattern[];
};

export type Repository = {
  support: Support;
  keywords: Keywords;
  strings: Strings;
  numbers: Numbers;
  comments: Comments;
};

export type Definitions = {
  $schema: string;
  name: string;
  patterns: Patterns[];
  repository: Repository;
  scopeName: string;
};

// eslint-disable-next-line @typescript-eslint/no-unused-vars
type Capture = Record<string, { name: string }>;
