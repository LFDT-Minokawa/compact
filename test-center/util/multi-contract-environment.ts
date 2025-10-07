import * as runtime from '@midnight-ntwrk/compact-runtime';
import {sampleCoinPublicKey} from "./rand.js";

export type ContractModule = {
    readonly contractId: string;
    readonly contractReferenceLocationsSet: runtime.ContractReferenceLocationsSet;
    readonly executables: (witnessSets: any) => runtime.Executables;
    readonly ledgerStateDecoder: (state: runtime.StateValue) => any;
};

export type ContractConfig<TModule extends ContractModule = ContractModule> = {
    readonly module: TModule;
    readonly constructorArgs?: (deployedContracts: Record<string, runtime.ContractAddress>) => any[];
    readonly witnessSets?: any;
    readonly initialPrivateState?: any;
};

export type DeployedContract = {
    readonly address: runtime.ContractAddress;
    readonly coinPublicKey: string;
    readonly exec: runtime.Executables;
    readonly constructorResult: runtime.ConstructorResult<any>;
};

export type MultiContractEnvironment = {
    readonly deployedContracts: Record<string, DeployedContract>;
    readonly initialLedgerStates: Record<string, runtime.StateValue>;
    readonly initialPrivateStates: Record<string, any>;
};

function topologicalSort(
    contractConfigs: Record<string, ContractConfig>
): string[] {
    const graph = new Map<string, Set<string>>();
    const inDegree = new Map<string, number>();

    for (const [contractId, config] of Object.entries(contractConfigs)) {
        if (!graph.has(contractId)) {
            graph.set(contractId, new Set());
            inDegree.set(contractId, 0);
        }

        const deps = Object.keys(config.module.contractReferenceLocationsSet || {});
        for (const depId of deps) {
            if (depId !== contractId && contractConfigs[depId]) {
                graph.get(contractId)!.add(depId);
                inDegree.set(depId, (inDegree.get(depId) || 0) + 1);
            }
        }
    }

    const queue: string[] = [];
    for (const [contractId, degree] of inDegree.entries()) {
        if (degree === 0) {
            queue.push(contractId);
        }
    }

    const sorted: string[] = [];
    while (queue.length > 0) {
        const current = queue.shift()!;
        sorted.push(current);

        for (const neighbor of graph.get(current) || []) {
            const newDegree = inDegree.get(neighbor)! - 1;
            inDegree.set(neighbor, newDegree);
            if (newDegree === 0) {
                queue.push(neighbor);
            }
        }
    }

    if (sorted.length !== Object.keys(contractConfigs).length) {
        throw new Error('Circular dependency detected in contract configurations');
    }

    return sorted;
}

export function multiContractEnv(
    contractConfigs: Record<string, ContractConfig>,
    witnessSets: runtime.WitnessSets
): MultiContractEnvironment {

    const sortedContractIds = topologicalSort(contractConfigs).reverse();

    const deployedContracts: Record<string, DeployedContract> = {};
    const deployedAddresses: Record<string, runtime.ContractAddress> = {};

    for (const contractId of sortedContractIds) {
        const config = contractConfigs[contractId];
        const coinPublicKey = sampleCoinPublicKey();
        const address = runtime.sampleContractAddress();

        const exec = config.module.executables(witnessSets);

        const args = config.constructorArgs
            ? config.constructorArgs(deployedAddresses)
            : [];

        const constructorResult = exec.stateConstructor(
            runtime.createConstructorContext(coinPublicKey, config.initialPrivateState),
            ...args
        );

        deployedContracts[contractId] = {
            address,
            coinPublicKey,
            exec,
            constructorResult,
        };

        deployedAddresses[contractId] = address;
    }

    const initialLedgerStates: Record<string, any> = {};
    const initialPrivateStates: Record<string, any> = {};

    for (const [contractId, deployed] of Object.entries(deployedContracts)) {
        initialLedgerStates[deployed.address] = deployed.constructorResult.currentContractState.data;
        initialPrivateStates[deployed.address] = deployed.constructorResult.currentPrivateState;
    }

    return {
        deployedContracts,
        initialLedgerStates,
        initialPrivateStates,
    };
}

export function createInitialContext(
    contractId: string,
    circuitId: string,
    env: MultiContractEnvironment
): runtime.CircuitContext<any> {
    const deployed = env.deployedContracts[contractId];
    if (!deployed) {
        throw new Error(`Contract ${contractId} not found in deployed contracts`);
    }
    return runtime.createCircuitContext(
        contractId,
        circuitId,
        deployed.address,
        deployed.coinPublicKey,
        env.initialLedgerStates,
        env.initialPrivateStates
    );
}
