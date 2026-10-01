# Verifier key template

One real compiled verifier key. `TestChain.deploy` copies it, replaces its last 32 bytes with a
digest of the compiled contract and the circuit within it, and installs the result — so two
deployments of one contract carry the same keys, two circuits never do, and every run produces the
same ones.

**These are not the keys of the contracts under test**, and cannot be: the suite compiles with
`skip-zk`, so `compactc` writes no `keys/` and every generated module's own `expectedVk` is `{}`.
The harness supplies both the bytes on the chain side and the fingerprints on the module side. A
green key-agreement test says the runtime compares fingerprints correctly. It says nothing about
whether `compactc` computes them correctly — that is what the `expectedVk` test in `tests-e2e` is
for.

## Why a real key rather than invented bytes

Only the envelope matters, and only the harness's copy of it would be at risk of being wrong.

`ContractOperation.verifierKey` checks that the data begins with `midnight:`, that the
colon-separated tag is one it knows (`verifier-key[v6]` or `[v7]`), and that the SCALE-compact
length prefix covers exactly the bytes that follow — over-run and under-run are both rejected. It
then stores the payload without parsing it (`transient-crypto/src/proofs.rs:414`). Nothing parses it
afterwards on any path this harness reaches: `force_init` runs only from `VerifierKey::verify`, and
proof checking here goes through `zkir` with its own key material.

So arbitrary bytes in a correct envelope would work. Keeping a real key and overwriting its tail
gets the same freedom without this repo holding a second copy of the ledger's serialization format:
the tag and the prefix are whatever `compactc` and the ledger agreed on, the length never changes so
the prefix stays true, and the bytes replaced are far enough from the front to be payload.

## Provenance

`template.verifier` is `compactc` output for `debug-test/src/contract.compact`, `gen/keys/ledgerCalls.verifier`.

To replace it, compile any contract without `--skip-zk` and copy one `keys/*.verifier` here. Copy it
as a binary; a textual copy silently mangles the length prefix and the ledger then reports `out of
range for u32`.
