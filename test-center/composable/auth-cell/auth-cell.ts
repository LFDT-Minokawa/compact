type AuthCellPS = {
  sk: Uint8Array;
  privateField: bigint;
}

function assertIsAuthCellPS(x: unknown): asserts x is AuthCellPS {
  if (!(typeof x === 'object' && x !== null && x !== undefined && 'sk' in x && x.sk instanceof Uint8Array && 'privateField' in x && typeof x.privateField === 'bigint')) {
    throw new Error(`Not AuthCell private state: ${x}`);
  }
}

describe('\'AuthCellUser\' works as expected', () => {
  const initialAuthCellPS = {
    sk: util.getRandomBytes(32),
    privateField: 1n,
  };

  const witnessSets = {
    [contractCodeAuthCell.contractId]: {
      getSk(context: runtime.WitnessContext<any, AuthCellPS>): readonly [AuthCellPS, Uint8Array] {
        return [context.privateState, context.privateState.sk];
      },
      setPrivateField(context: runtime.WitnessContext<any, AuthCellPS>, newField: bigint): readonly [AuthCellPS, []] {
        return [{ ...context.privateState, privateField: newField }, []];
      },
    },
  } as const;

  const contractConfigs: Record<string, util.ContractConfig> = {
    AuthCell: {
      module: contractCodeAuthCell,
      constructorArgs: () => [1n],
      witnessSets,
      initialPrivateState: initialAuthCellPS,
    },
    AuthCellUser: {
      module: contractCodeAuthCellUser,
      constructorArgs: (deployed: Record<string, runtime.ContractAddress>) => [
        util.toEncodedContractAddress(deployed.AuthCell),
      ],
      witnessSets: {},
    },
  };

  const env = util.multiContractEnv(contractConfigs, witnessSets);
  const authCellAddress = env.deployedContracts.AuthCell.address;
  const authCellUserAddress = env.deployedContracts.AuthCellUser.address;
  const authCellUserExec = env.deployedContracts.AuthCellUser.exec;
  const initialAuthCellUserContext = util.createInitialContext('AuthCellUser', 'useAuthCell', env);

  test('\'contractDependencies\' extracts \'AuthCell\' address from \'AuthCellUser\' ledger state', () => {
    const currentLedgerState = runtime.readQueryContext(initialAuthCellUserContext, authCellUserAddress).state;
    const dependencies = runtime.contractDependencies(authCellUserExec.contractReferenceLocations, currentLedgerState);
    expect(dependencies.size).toEqual(1);
    const depAddresses = Array.from(dependencies).map(d => d.address);
    expect(depAddresses[0]).toEqual(authCellAddress);
  });

  test('\'useAuthCell\' results in the correct proof data trace', () => {
    const context1 = authCellUserExec.impureCircuits.useAuthCell(initialAuthCellUserContext, 2n).context;
    expect(context1.proofDataTrace.length).toEqual(3);
    // TODO: Enable again after Parisa finishes ZKIR generation
    // expect(context1.currentQueryContext.effects.claimedContractCalls.length).toEqual(2);
  });

  test('\'useAuthCell\' results in the correct stack frame', () => {
    const context1 = authCellUserExec.impureCircuits.useAuthCell(initialAuthCellUserContext, 2n).context;
    expect(context1.contractId).toEqual(contractCodeAuthCellUser.contractId);
    expect(context1.circuitId).toEqual('useAuthCell');
    expect(context1.contractAddress).toEqual(authCellUserAddress);
    expect(context1.initialQueryContext.address).toEqual(authCellUserAddress);
    const initialLedgerState = runtime.readQueryContext(initialAuthCellUserContext, authCellUserAddress).state;
    expect(contractCodeAuthCellUser.ledgerStateDecoder(initialAuthCellUserContext.currentQueryContext.state)).toEqual(contractCodeAuthCellUser.ledgerStateDecoder(initialLedgerState));
    expect(context1.currentQueryContext.address).toEqual(authCellUserAddress);
    const currentLedgerState = runtime.readQueryContext(context1, authCellUserAddress).state;
    expect(contractCodeAuthCellUser.ledgerStateDecoder(context1.currentQueryContext.state)).toEqual(contractCodeAuthCellUser.ledgerStateDecoder(currentLedgerState));
  });

  test('\'useAuthCell\' results in the correct circuit return value', () => {
    expect(authCellUserExec.impureCircuits.useAuthCell(initialAuthCellUserContext, 2n).result).toEqual(1n);
  });

  test('\'useAuthCell\' results in the correct private states', () => {
    const context1 = authCellUserExec.impureCircuits.useAuthCell(initialAuthCellUserContext, 2n).context;

    const authCellPS = runtime.readPrivateState(context1, authCellAddress);
    assertIsAuthCellPS(authCellPS);
    const initialAuthCellPS = runtime.readPrivateState(initialAuthCellUserContext, authCellAddress);
    assertIsAuthCellPS(initialAuthCellPS);
    expect(authCellPS.sk).toEqual(initialAuthCellPS.sk);
    expect(authCellPS.privateField).toEqual(3n);

    const authCellUserPS = runtime.readPrivateState(context1, authCellUserAddress);
    expect(authCellUserPS).toBeUndefined();
  });

  test('\'useAuthCell\' results in the correct ledger states', () => {
    const context1 = authCellUserExec.impureCircuits.useAuthCell(initialAuthCellUserContext, 2n).context;

    const currentAuthCellLedgerState = runtime.readQueryContext(context1, authCellAddress).state;
    const authCellLS = contractCodeAuthCell.ledgerStateDecoder(currentAuthCellLedgerState);
    expect(authCellLS.publicField).toEqual(3n);

    const currentAuthCellUserLedgerState = runtime.readQueryContext(context1, authCellUserAddress).state;
    const authCellUserLS = contractCodeAuthCellUser.ledgerStateDecoder(currentAuthCellUserLedgerState);
    expect(runtime.decodeContractAddress(authCellUserLS.authCell.bytes)).toEqual(authCellAddress);
  });
});
