export const isMacOS = (): boolean => {
    return process.platform === 'darwin';
};

export const isRelease = (): boolean => {
    return process.env['RELEASE'] === 'true';
};
