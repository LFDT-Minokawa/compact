# Compact runtime library

This API provides runtime primitives used by Compact's TypeScript output, both
for use by the compiler output directly, and to utilise it or reproduce its
behaviour. This API re-exports a number of items from
`@midnight-ntwrk/onchain-runtime`, and wraps others in a more TypeScript-friendly
API. Key parts of the API are:

- {@link setNetworkId}, required to ensure the right network is being targeted
- {@link CircuitContext}, and {@link CircuitResults} part of the input and
  output definition of all circuits
- {@link WitnessContext}, part of the input definition of all circuits
- Built-in functions:
  - Hashing/commitment
    - {@link transientHash}
    - {@link transientCommit}
    - {@link persistentHash}
    - {@link persistentCommit}
    - {@link degradeToTransient}
  - Elliptic curve
    - {@link ecAdd}
    - {@link ecMul}
    - {@link ecMulGenerator}
    - {@link hashToCurve}
- {@link ContractState}, encapsulating the entirety of a smart contract's
  on-chain state
- {@link StateValue}, encoding data a contract maintains on-chain
- {@link QueryContext}, providing an annotated view into the contract state,
  against which on-chain VM programs can be run
- {@link CompactType}, providing a runtime representation of basic Compact
  datatypes
- Various TypeScript types matching same-named Compact types
