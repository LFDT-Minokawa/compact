// SPDX-License-Identifier: Apache-2.0
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
