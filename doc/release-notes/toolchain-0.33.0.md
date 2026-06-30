# Compact toolchain 0.33.0

- **Date**: 2026-06-30
- **Language version:** 0.25.0
- **Compact runtime version:** 0.18.0
- **Environment**: to-be-filled. For the full compatibility matrix, see the [release notes overview](https://docs.midnight.network/relnotes/overview)

## High-level summary

Version 0.33.0 of the Compact toolchain has to-be-filled.  You can update to this version with `compact update` (as long as it is the most recent version) or `compact update 0.33`.

## Audience

These release notes are intended for Compact smart contract developers and for DApp developers who use the Compact runtime.

## What changed


## New features


### Contract to contract calls


### Emitting events

**Description**: There is a new expression form `emit(e)` that takes a standard event and appends the emitted 
events, in order of evaluation, to the enclosing exported circuit's context, where it can be read from
TypeScript via the `events` field of `CircuitContext`.

The Compact standard library defines the standard event types. 

The type of every `emit` form is `[]`.

Evaluation of `emit(e)` proceeds by evaluating `e`, computing its canonical
byte encoding, and emitting a structured `VersionedLogItem` with three fields:
- `version`, the event format version (presently `1`),
- `eventType`, identifying the declared event type by its tag, and
- `data`, containing the byte encoding.

The canonical byte encoding of an event is created via the equivalent of
`serialize<T, #n>`.
A generic `serialize` circuit is defined in the Compact standard library
along with a `deserialize` counterpart.

## Improvements


## Deprecations


## Breaking changes


## Fixed defect list
