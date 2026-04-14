# Compact

[![Compiler CI](https://img.shields.io/github/actions/workflow/status/LFDT-Minokawa/compact/build-compiler.yml?label=compiler%20CI)](https://github.com/LFDT-Minokawa/compact/actions/workflows/build-compiler.yml)
[![compact CLI CI](https://img.shields.io/github/actions/workflow/status/LFDT-Minokawa/compact/compact-test.yml?label=compact%20CLI%20CI)](https://github.com/LFDT-Minokawa/compact/actions/workflows/compact-test.yml)
[![compact CLI release](https://img.shields.io/github/v/release/midnightntwrk/compact?filter=compact-*&label=compact%20CLI)](https://github.com/midnightntwrk/compact/releases)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](./LICENSE)

This is the home of **Compact**. This project integrates with the [Midnight Network](https://midnight.network). It contains the language documentation, formal specification, compiler, runtime libraries, CLI tooling, and editor extensions.

> **Note:** Development takes place under the [LFDT-Minokawa](https://github.com/LFDT-Minokawa) GitHub organization, which is the [Linux Foundation Decentralized Trust](https://www.lfdecentralizedtrust.org/) project for Compact. Public releases are published to [midnightntwrk/compact](https://github.com/midnightntwrk/compact).

## What Is Compact?

Compact is a smart contract language that makes it straightforward to write programs that combine public and private computation, with the compiler handling the complexity of generating zero-knowledge proofs. You write what looks like a normal program in a TypeScript-like syntax, and the compiler splits it into on-chain, off-chain, and ZK components automatically.

A Compact contract operates across three contexts at once:

- **`ledger` fields** declare public state that lives on chain
- **`circuit` functions** define operations that are proven correct via zero-knowledge proofs -- they can read and update ledger state, perform assertions, and call witnesses
- **`witness` declarations** are callbacks into TypeScript code running on the user's local machine, providing private inputs (like secret keys) without ever exposing them on chain

The key idea: you write a single program that freely mixes public ledger operations with private data from witnesses. The compiler figures out what needs to be proven in zero-knowledge and what needs to be published on chain. Private data stays private by default -- the compiler rejects any program that would put witness-derived data on the ledger unless the developer explicitly wraps it in `disclose()`, making accidental data leaks a compile-time error rather than a runtime surprise.

Here's a concrete example -- a contract where a user can lock a value that only they can unlock, using a secret key that never leaves their machine (from [Writing a contract](./doc/writing.mdx)):

```compact
import CompactStandardLibrary;

enum State { UNSET, SET }

export ledger authority: Bytes<32>;    // public: the key-holder's identity
export ledger value: Uint<64>;         // public: the locked value
export ledger state: State;            // public: whether the lock is set
export ledger round: Counter;          // public: prevents cross-transaction linking

witness secretKey(): Bytes<32>;        // private: runs locally in TypeScript

circuit publicKey(round: Field, sk: Bytes<32>): Bytes<32> {
  return persistentHash<Vector<3, Bytes<32>>>(
           [pad(32, "midnight:examples:lock:pk"), round as Bytes<32>, sk]);
}

export circuit set(v: Uint<64>): [] {
  assert(state == State.UNSET);        // ensure we don't overwrite an existing lock
  const sk = secretKey();              // fetch the secret key locally
  const pk = publicKey(round, sk);     // derive a public key (inside the ZK proof)
  authority = disclose(pk);            // explicitly publish the public key
  value = disclose(v);                 // explicitly publish the value
  state = State.SET;
}

export circuit clear(): [] {
  assert(state == State.SET);          // ensure there's a lock to clear
  const sk = secretKey();              // fetch the secret key again
  const pk = publicKey(round, sk);     // re-derive the public key
  assert(authority == pk);             // prove we hold the key, without revealing it
  state = State.UNSET;                 // clear the lock
  round.increment(1);                  // rotate round so the next public key differs
}
```

The `set` circuit takes private data, derives a public key, and explicitly discloses it to the ledger. The `clear` circuit proves the caller holds the matching secret key -- all without ever putting the secret key on chain. The `round` counter is included in the key derivation and incremented on each `clear`, so the same secret key produces a different `authority` value next time -- without this, an observer could see the same `authority` appearing across transactions and link them to the same user. The ZK proof handles the rest.

The Compact compiler produces JavaScript/TypeScript for transaction construction (with type definitions and source maps), zero-knowledge circuits (`.zkir`) compiled into proving and verifier keys, and a JSON contract info file describing the contract's interface.

For a full walkthrough, see [Writing a contract](./doc/writing.mdx). For the complete language specification, see the [language reference](./doc/lang-ref.mdx).

## Installation

Install the `compact` CLI, which manages the Compact toolchain:

```sh
curl --proto '=https' --tlsv1.2 -LsSf https://github.com/midnightntwrk/compact/releases/latest/download/compact-installer.sh | sh
```

Then install the latest compiler toolchain:

```sh
compact update
```

### Supported Platforms

| Platform | Architecture |
|----------|-------------|
| macOS | Apple Silicon (aarch64), Intel (x86_64) |
| Linux | x86_64, aarch64 |

### Keeping Up to Date

```sh
compact self update   # update the compact CLI itself
compact update        # update the compiler toolchain
```

## Quick Start

A minimal Compact contract ([`examples/counter.compact`](./examples/counter.compact)):

```compact
import CompactStandardLibrary;

export ledger round: Counter;

export circuit increment(): [] {
  round.increment(1);
}
```

Compile it:

```sh
compact compile examples/counter.compact output/
```

Use `--skip-zk` to skip proof key generation for faster iteration during development:

```sh
compact compile --skip-zk examples/counter.compact output/
```

### Managing Compiler Versions

```sh
compact update 0.29.0              # install a specific version
compact list                       # list available versions
```

## Documentation

- [Writing a contract](./doc/writing.mdx) -- introductory walkthrough
- [Language reference](./doc/lang-ref.mdx) -- complete language specification
- [API documentation](./doc/api/)
- [Examples](./examples/)
- [Midnight developer docs](https://docs.midnight.network/)

## Editor Support

- [VS Code extension](./editor-support/vsc/)
- [Vim](./editor-support/vim/)

## Repository Structure

```
compiler/         Compact compiler (Scheme, built with Chez Scheme via Nix)
tools/compact/    CLI tool for managing the toolchain (Rust)
specification/    Formal specification (Agda)
doc/              Language reference and documentation
runtime/          TypeScript runtime libraries
editor-support/   VS Code and Vim extensions
examples/         Example Compact contracts
```

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines on how to build the compiler and CLI from source, run tests, and submit pull requests.

## License

This project is licensed under [Apache-2.0](./LICENSE).
