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
