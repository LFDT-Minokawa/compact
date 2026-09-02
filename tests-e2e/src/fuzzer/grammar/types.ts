// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/*
 * The shape of the grammar.
 */

/** A single piece of a production: either literal output or a nonterminal name. */
export type Token = string;

/** One way to expand a production: a sequence of tokens. */
export type Alternative = Token[];

/**
 * A production's alternatives. Most are `Alternative[]`; the keyword lists are a
 * flat `Token[]`, which the generator returns from without recursing.
 */
export type Production = (Alternative | Token)[];

export type Grammar = Record<string, Production>;
