---
Title: Rules for Contract Operations
Last Meaningful Update: 8 October 2026
---

These notes capture some conversations about the operations performed
*on* contracts.  In other words, these are truths about deploying and
attaching to contracts in the context of the capsule runtime, not
about calling the publicly advertised functions (circuits) of those
contracts.

## Deploy

1. Instantiate contract ledger state fields with default values.
2. Execute constructor code *locally* to arrive at initial ledger state.
3. Create deploy transaction, which
   - creates a record of the contract on-chain, at a specific address
   - sets the initial ledger state for the contract to be the result
     of step 2
   - sets the verifier keys for each public entry point (exported
     circuit) of the contract
   - does something to set the executable code for the contract

**Notes:**
- Constructors can have parameters.
- No Impact VM code is executed to deploy a contract.  Impact
  instructions are about changes to ledger state, and there are not
  state deltas in contract deployment.  The result of the local
  execution of the constructor produced an initial public state, and
  it is simply installed.
- No capsule for a contract is necessary during its deployment,
  because deploying a contract does not execute it.  This implies that
  local state fields are not in scope in a contract's constructor and
  that the capsule context API is unavailable.
- If the deployer wishes to use the contract immediately after
  deploying it, the deployer attaches to it, using the same attachment
  code as any other user.

## Attach

1. If the attachment is initiated by a DApp, prompt for an account to use.
   If the attachment is initiated by a cross-contract call, use the
   account under which the caller is being executed.
2. If no capsule exists for the given account and contract address:
   1. ensure that the current version of the contract code is present
   2. instantiate contract local state fields with default values
   3. read contract ledger state, saving the block ID at which that
      state is current
   4. execute local state initializer code, with the following in
      scope
      - ledger fields, holding the values found in the preceding step,
        with only read operations available
      - local fields, holding default values at the start of the
        initializer, with read and write operations available
      - context API
3. If, on the other hand, a capsule already exists for the given
   account and contract address:
   1. process relevant transactions since detachment, including
      upgrades, running event handlers if any are defined for the
      contract (see Event Handing, below)

## Event Handling

Both ledger and local fields are in scope in event handlers, as is the
context API.  Ledger fields are read-only, and the values seen by the
code are those present at the block where the event was generated.
Local fields are read-write. The capsule runtime captures transcripts
of local state and context interactions and associates them with the
blockchain transactions that triggered them, so that replay is possible
and deterministic.

The "normal" kinds of events witnessed by a capsule are
circuit-execution transactions, which may cause local state updates.
Another kind of event is a contract upgrade, which may cause the
installation of new capsule code and corresponding transformation of
local state.
