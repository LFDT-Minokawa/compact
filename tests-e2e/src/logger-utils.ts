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

import * as path from 'node:path';
import pinoPretty from 'pino-pretty';
import pino, { Logger } from 'pino';

export const currentDir = path.resolve(new URL(import.meta.url).pathname, '..');
const logDir = path.resolve(currentDir, '..', 'logs', 'tests');
const defaultLogName = `compiler_${new Date().toISOString()}.log`;

const level = 'info';

export const createLogger = (fileName: string = defaultLogName, dir: string = logDir): pino.Logger => {
    const logPath = path.resolve(dir, fileName);
    const prettyStream: pinoPretty.PrettyStream = pinoPretty({
        colorize: true,
        sync: true,
    });
    const prettyFileStream: pinoPretty.PrettyStream = pinoPretty({
        colorize: false,
        sync: true,
        append: true,
        mkdir: true,
        destination: logPath,
    });
    return pino(
        {
            level,
            depthLimit: 20,
        },
        pino.multistream([
            { stream: prettyStream, level },
            { stream: prettyFileStream, level },
        ]),
    );
};

export const logger: Logger = createLogger('compiler.log');
