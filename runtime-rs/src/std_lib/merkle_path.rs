// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//
// Merkle path root — stdlib circuits routed via
// `stdlib-circuit-rust-path`.

/// Compact's `merkleTreePathRoot<#n, T>(path: MerkleTreePath<n, T>):
/// MerkleTreeDigest` — computes the Merkle root reachable from a
/// path. Delegates to upstream `MerklePath::root()` (see
/// midnight-transient-crypto/src/merkle_tree.rs:201). The const-generic
/// `n` (path height) is captured by the `MerklePath<T>` type via its
/// `path: Vec<MerklePathEntry>`, so the wrapper only needs `T`.
///
/// Note: generated contract code currently emits a per-contract
/// `MerkleTreePath` struct (leaf + fixed-N array of entries) rather
/// than this upstream type, so the wrapper isn't directly callable
/// from contracts today. The routing is in place for when the codegen
/// migrates to use this upstream-shaped path directly (or via a
/// conversion shim).
#[cfg(test)]
use crate::Fr;

pub fn merkle_tree_path_root<T>(
    path: midnight_transient_crypto::merkle_tree::MerklePath<T>,
) -> midnight_transient_crypto::merkle_tree::MerkleTreeDigest
where
    T: midnight_base_crypto::repr::BinaryHashRepr,
{
    path.root()
}

/// Compact's `merkleTreePathRootNoLeafHash<#n>(path: MerkleTreePath<n,
/// Bytes<32>>): MerkleTreeDigest` — like `merkle_tree_path_root` but
/// skips the leaf-hash step (the leaf is already a 32-byte digest, so
/// we just `degradeToTransient` it before folding).
///
/// Upstream `MerklePath::root()` unconditionally applies `leaf_hash`
/// to the leaf, so this variant cannot delegate to `.root()` directly
/// when the leaf is `[u8; 32]`. The body here mirrors the stdlib
/// source: degrade the raw 32-byte leaf, then fold the path entries
/// with the same combiner.
pub fn merkle_tree_path_root_no_leaf_hash(
    path: midnight_transient_crypto::merkle_tree::MerklePath<[u8; 32]>,
) -> midnight_transient_crypto::merkle_tree::MerkleTreeDigest {
    use midnight_base_crypto::hash::HashOutput;
    use midnight_transient_crypto::hash::{degrade_to_transient, transient_hash};
    use midnight_transient_crypto::merkle_tree::MerkleTreeDigest;
    MerkleTreeDigest(path.path.iter().fold(
        degrade_to_transient(HashOutput(path.leaf)),
        |acc, entry| {
            if entry.goes_left {
                transient_hash(&[acc, entry.sibling.0])
            } else {
                transient_hash(&[entry.sibling.0, acc])
            }
        },
    ))
}

/// Construct a default `MerklePath<T>` for a `T: Default`. Used by
/// test fixtures and witness implementations that need a placeholder
/// path. Upstream `MerklePath` does not impl `Default`, so codegen /
/// hand-written witnesses route default construction through this
/// helper.
pub fn default_merkle_path<T: Default>() -> midnight_transient_crypto::merkle_tree::MerklePath<T> {
    midnight_transient_crypto::merkle_tree::MerklePath {
        leaf: T::default(),
        path: Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use midnight_base_crypto::hash::HashOutput;
    use midnight_transient_crypto::hash::{degrade_to_transient, transient_hash};
    use midnight_transient_crypto::merkle_tree::{MerklePath, MerklePathEntry};

    fn entry(sibling: u64, goes_left: bool) -> MerklePathEntry {
        MerklePathEntry {
            sibling: midnight_transient_crypto::merkle_tree::MerkleTreeDigest(Fr::from(sibling)),
            goes_left,
        }
    }

    #[test]
    fn default_path_is_empty_with_a_default_leaf() {
        let p: MerklePath<[u8; 32]> = default_merkle_path();
        assert_eq!(p.leaf, [0u8; 32]);
        assert!(p.path.is_empty());
    }

    /// With no entries the fold never runs, so the root is just the degraded
    /// leaf. This is the base case the rest of the fold builds on.
    #[test]
    fn an_empty_path_roots_to_the_degraded_leaf() {
        let leaf = [3u8; 32];
        let got = merkle_tree_path_root_no_leaf_hash(MerklePath { leaf, path: vec![] });
        assert_eq!(got.0, degrade_to_transient(HashOutput(leaf)));
    }

    /// `goes_left` decides the argument order of the combiner, and getting it
    /// backwards produces a different root that still looks entirely valid.
    /// So this asserts the order explicitly, against a hand-computed hash,
    /// rather than merely that the two differ.
    #[test]
    fn goes_left_selects_the_combiner_argument_order() {
        let leaf = [1u8; 32];
        let acc = degrade_to_transient(HashOutput(leaf));
        let sib = Fr::from(99u64);

        let left = merkle_tree_path_root_no_leaf_hash(MerklePath {
            leaf,
            path: vec![entry(99, true)],
        });
        assert_eq!(
            left.0,
            transient_hash(&[acc, sib]),
            "goes_left => (acc, sibling)"
        );

        let right = merkle_tree_path_root_no_leaf_hash(MerklePath {
            leaf,
            path: vec![entry(99, false)],
        });
        assert_eq!(
            right.0,
            transient_hash(&[sib, acc]),
            "!goes_left => (sibling, acc)"
        );

        assert_ne!(left.0, right.0, "the two orders must not collide");
    }

    /// Entries fold in sequence, each consuming the previous accumulator.
    /// A fold that applied them in reverse would pass the single-entry test
    /// above and fail here.
    #[test]
    fn entries_fold_in_order() {
        let leaf = [2u8; 32];
        let acc0 = degrade_to_transient(HashOutput(leaf));
        let acc1 = transient_hash(&[acc0, Fr::from(10u64)]);
        let expected = transient_hash(&[Fr::from(20u64), acc1]);

        let got = merkle_tree_path_root_no_leaf_hash(MerklePath {
            leaf,
            path: vec![entry(10, true), entry(20, false)],
        });
        assert_eq!(got.0, expected);
    }

    /// The leaf-hashing variant must NOT agree with the no-leaf-hash one:
    /// that difference is the entire reason this module hand-writes the fold
    /// instead of delegating to upstream's `root()`.
    #[test]
    fn the_leaf_hashing_variant_differs_from_the_raw_one() {
        let leaf = [4u8; 32];
        let raw = merkle_tree_path_root_no_leaf_hash(MerklePath { leaf, path: vec![] });
        let hashed = merkle_tree_path_root(MerklePath { leaf, path: vec![] });
        assert_ne!(
            raw.0, hashed.0,
            "root() leaf-hashes; the no-leaf-hash variant degrades the leaf directly"
        );
    }
}
