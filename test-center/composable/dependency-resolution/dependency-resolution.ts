describe('Dependency resolution with contracts A-E', () => {
    const witnessSets = {} as const;

    const contractConfigs: Record<string, util.ContractConfig> = {
        A: {
            module: contractCodeA,
            witnessSets: {}
        },
        C: {
            module: contractCodeC,
            witnessSets: {}
        },
        B: {
            module: contractCodeB,
            constructorArgs: (deployed: Record<string, runtime.ContractAddress>) => [
                util.toEncodedContractAddress(deployed.A),
                util.toEncodedContractAddress(deployed.C),
            ],
            witnessSets: {}
        },
        D: {
            module: contractCodeD,
            constructorArgs: (deployed: Record<string, runtime.ContractAddress>) => [
                util.toEncodedContractAddress(deployed.A),
                util.toEncodedContractAddress(deployed.C),
            ],
            witnessSets: {}
        },
        E: {
            module: contractCodeE,
            constructorArgs: (deployed: Record<string, runtime.ContractAddress>) => [
                util.toEncodedContractAddress(deployed.B),
                util.toEncodedContractAddress(deployed.D),
            ],
            witnessSets: {}
        },
    };

    const env = util.multiContractEnv(contractConfigs, witnessSets);

    test('All contracts are deployed in correct order', () => {
        expect(Object.keys(env.deployedContracts)).toContain('A');
        expect(Object.keys(env.deployedContracts)).toContain('B');
        expect(Object.keys(env.deployedContracts)).toContain('C');
        expect(Object.keys(env.deployedContracts)).toContain('D');
        expect(Object.keys(env.deployedContracts)).toContain('E');
    });

    test('Contract A has correct initial ledger state', () => {
        const aDeployed = env.deployedContracts.A;
        const aLedgerState = contractCodeA.ledgerStateDecoder(aDeployed.constructorResult.currentContractState.data);
        expect(aLedgerState.c).toBe(0n);
    });

    test('Contract C has correct initial ledger state', () => {
        const cDeployed = env.deployedContracts.C;
        const cLedgerState = contractCodeC.ledgerStateDecoder(cDeployed.constructorResult.currentContractState.data);
        expect(cLedgerState.c).toBe(0n);
    });

    test('Contract B references A and C correctly', () => {
        const bDeployed = env.deployedContracts.B;
        const bLedgerState = contractCodeB.ledgerStateDecoder(bDeployed.constructorResult.currentContractState.data);

        expect(runtime.decodeContractAddress(bLedgerState.a.bytes)).toBe(env.deployedContracts.A.address);
        expect(runtime.decodeContractAddress(bLedgerState.c.bytes)).toBe(env.deployedContracts.C.address);
    });

    test('Contract D references A and C correctly', () => {
        const dDeployed = env.deployedContracts.D;
        const dLedgerState = contractCodeD.ledgerStateDecoder(dDeployed.constructorResult.currentContractState.data);

        expect(runtime.decodeContractAddress(dLedgerState.a.bytes)).toBe(env.deployedContracts.A.address);
        expect(runtime.decodeContractAddress(dLedgerState.c.bytes)).toBe(env.deployedContracts.C.address);
    });

    test('Contract E references B and D correctly', () => {
        const eDeployed = env.deployedContracts.E;
        const eLedgerState = contractCodeE.ledgerStateDecoder(eDeployed.constructorResult.currentContractState.data);

        expect(runtime.decodeContractAddress(eLedgerState.b.bytes)).toBe(env.deployedContracts.B.address);
        expect(runtime.decodeContractAddress(eLedgerState.d.bytes)).toBe(env.deployedContracts.D.address);
    });

    test('contractDependencies extracts all dependencies from E', () => {
        const eDeployed = env.deployedContracts.E;
        const eLedgerState = runtime.readQueryContext(
            util.createInitialContext('E', 'up', env),
            eDeployed.address
        ).state;

        const dependencies = runtime.contractDependencies(
            eDeployed.exec.contractReferenceLocations,
            eLedgerState
        );

        expect(dependencies.size).toBe(2);
        const depAddresses = Array.from(dependencies).map(d => d.address);
        expect(depAddresses).toContain(env.deployedContracts.B.address);
        expect(depAddresses).toContain(env.deployedContracts.D.address);
    });

    test('Can execute circuit on contract E', () => {
        const context = util.createInitialContext('E', 'up', env);
        const result = env.deployedContracts.E.exec.impureCircuits.up(context, 5n);
        expect(result).toBeDefined();
    });

    test('Contract E.up increments counters in A and C through B and D', () => {
        const context = util.createInitialContext('E', 'up', env);
        const result = env.deployedContracts.E.exec.impureCircuits.up(context, 10n);

        const aAddress = env.deployedContracts.A.address;
        const cAddress = env.deployedContracts.C.address;

        const aLedgerState = contractCodeA.ledgerStateDecoder(
            runtime.readQueryContext(result.context, aAddress).state
        );
        const cLedgerState = contractCodeC.ledgerStateDecoder(
            runtime.readQueryContext(result.context, cAddress).state
        );

        expect(aLedgerState.c).toBe(20n);
        expect(cLedgerState.c).toBe(20n);
    });

    test('Recursive dependency resolution works for contract E', () => {
        const resolvedStates = util.resolveContractDependencies(
            env.deployedContracts.E.exec.contractReferenceLocationsSet,
            env.deployedContracts.E.exec.contractId,
            env.deployedContracts.E.address,
            env.initialLedgerStates
        );
        const AAddress = env.deployedContracts.A.address;
        const BAddress = env.deployedContracts.B.address;
        const CAddress = env.deployedContracts.C.address;
        const DAddress = env.deployedContracts.D.address;
        const EAddress = env.deployedContracts.E.address;

        expect(resolvedStates).toHaveProperty(AAddress);
        expect(resolvedStates[AAddress].encode()).toEqual(env.initialLedgerStates[AAddress].encode());

        expect(resolvedStates).toHaveProperty(BAddress);
        expect(resolvedStates[BAddress].encode()).toEqual(env.initialLedgerStates[BAddress].encode());

        expect(resolvedStates).toHaveProperty(CAddress);
        expect(resolvedStates[CAddress].encode()).toEqual(env.initialLedgerStates[CAddress].encode());

        expect(resolvedStates).toHaveProperty(DAddress);
        expect(resolvedStates[DAddress].encode()).toEqual(env.initialLedgerStates[DAddress].encode());

        expect(resolvedStates).toHaveProperty(EAddress);
        expect(resolvedStates[EAddress].encode()).toEqual(env.initialLedgerStates[EAddress].encode());
    });
});
