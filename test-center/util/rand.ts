export const getRandomBytes = (size: number): Uint8Array => {
    const randomBytes = new Uint8Array(size);
    crypto.getRandomValues(randomBytes);
    return randomBytes;
};

export const sampleCoinPublicKey = () =>
    Buffer.from(getRandomBytes(32)).toString('hex');
