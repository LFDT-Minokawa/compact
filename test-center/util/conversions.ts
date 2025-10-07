import {ContractAddress, encodeContractAddress} from '@midnight-ntwrk/compact-runtime';

export const toEncodedContractAddress = (rawAddress: ContractAddress) => ({
    bytes: encodeContractAddress(rawAddress),
});