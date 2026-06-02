// SPDX-License-Identifier: Apache-2.0
//
// Typed builders for Op programs. Two builders — OpProgramVerify and
// OpProgramGather — corresponding to the two ResultMode flavours the
// codegen emits (Verify for mutating circuits, Gather for ledger view
// reads).
//
// Each builder method is a thin wrapper around constructing the
// corresponding `Op<M, D>` variant. The builder also covers the most
// common path shape — a single-element path keyed by a u8-aligned
// index — via `idx_at_index` for readability.
//
// Build with `.build()` to obtain a `Vec<Op<M, D>>` ready to pass to
// `query_for_verify` / `query_for_read`.

use crate::{
    AlignedValue, Array, DefaultDB, Key, Op, ResultModeGather, ResultModeVerify, StateValue, DB,
};

/// Builder for `Vec<Op<ResultModeVerify, D>>` — used by mutating circuits.
pub struct OpProgramVerify<D: DB = DefaultDB> {
    ops: Vec<Op<ResultModeVerify, D>>,
}

impl<D: DB> OpProgramVerify<D> {
    /// Start an empty `OpProgramVerify` builder.
    pub fn new() -> Self {
        Self { ops: Vec::new() }
    }

    /// Generic `idx` with an explicit path.
    pub fn idx(mut self, cached: bool, push_path: bool, path: Vec<Key>) -> Self {
        self.ops.push(Op::Idx {
            cached,
            push_path,
            path: Array::from(path),
        });
        self
    }

    /// Common case: single-element path indexing into an Array by u8 index.
    pub fn idx_at_index(self, idx: u8, push_path: bool) -> Self {
        self.idx(false, push_path, vec![Key::Value(AlignedValue::from(idx))])
    }

    /// `addi` — add the immediate value to the top of the stack.
    pub fn addi(mut self, immediate: u32) -> Self {
        self.ops.push(Op::Addi { immediate });
        self
    }

    /// `ins` — pop the top `n` stack values and insert them into the
    /// container at depth `n` (a Map / Set / Array / MerkleTree write).
    /// `cached` controls whether the write should be marked cached for
    /// witness-side reads.
    pub fn ins(mut self, cached: bool, n: u8) -> Self {
        self.ops.push(Op::Ins { cached, n });
        self
    }

    /// `push` — pushes a `StateValue` onto the VM stack. The `storage` flag
    /// distinguishes pushes that introduce new storage cells (the value being
    /// written, `storage = true`) from pushes that supply path keys or
    /// container shapes (`storage = false`). Mirrors the
    /// `(push [storage ...] [value ...])` vminstruction emitted for ADT
    /// `write` ops in compact's vm-code (see midnight-ledger.ss).
    pub fn push(mut self, storage: bool, value: StateValue<D>) -> Self {
        self.ops.push(Op::Push { storage, value });
        self
    }

    /// `dup` — duplicate the value at depth `n` (0 = top of stack). Emitted by
    /// MerkleTree / HistoricMerkleTree `insert` vm-code when the same
    /// container needs to appear in two stack positions before successive
    /// `ins` ops update the tree and its first-free index / history map.
    pub fn dup(mut self, n: u8) -> Self {
        self.ops.push(Op::Dup { n });
        self
    }

    /// `root` — replace the top-of-stack `BoundedMerkleTree` with its
    /// digest (root hash). Used by HistoricMerkleTree `insert` to derive the
    /// key for the history map entry that records the just-updated tree's
    /// root.
    pub fn root(mut self) -> Self {
        self.ops.push(Op::Root);
        self
    }

    /// Consume the builder and return the assembled op vector ready to
    /// pass to [`crate::query_for_verify`].
    pub fn build(self) -> Vec<Op<ResultModeVerify, D>> {
        self.ops
    }
}

impl<D: DB> Default for OpProgramVerify<D> {
    fn default() -> Self {
        Self::new()
    }
}

/// Builder for `Vec<Op<ResultModeGather, D>>` — used by ledger view reads.
pub struct OpProgramGather<D: DB = DefaultDB> {
    ops: Vec<Op<ResultModeGather, D>>,
}

impl<D: DB> OpProgramGather<D> {
    /// Start an empty `OpProgramGather` builder.
    pub fn new() -> Self {
        Self { ops: Vec::new() }
    }

    /// `dup` — duplicate the value at depth `n` (0 = top of stack).
    pub fn dup(mut self, n: u8) -> Self {
        self.ops.push(Op::Dup { n });
        self
    }

    /// Generic `idx` with an explicit path.
    pub fn idx(mut self, cached: bool, push_path: bool, path: Vec<Key>) -> Self {
        self.ops.push(Op::Idx {
            cached,
            push_path,
            path: Array::from(path),
        });
        self
    }

    /// Common case: single-element path indexing into an Array by u8 index.
    pub fn idx_at_index(self, idx: u8, push_path: bool) -> Self {
        self.idx(false, push_path, vec![Key::Value(AlignedValue::from(idx))])
    }

    /// `push` — pushes a `StateValue` onto the VM stack. Mirrors the
    /// `OpProgramVerify::push` method but for read paths. Used by ADT
    /// read-with-arg vm-code (Set.member, HistoricMerkleTree.checkRoot,
    /// Map.member, …) where the read takes a runtime value.
    pub fn push(mut self, storage: bool, value: StateValue<D>) -> Self {
        self.ops.push(Op::Push { storage, value });
        self
    }

    /// `member` — replaces the top two stack values (a container and a key)
    /// with a boolean indicating membership. Emitted by Set.member and
    /// HistoricMerkleTree.checkRoot vm-code.
    pub fn member(mut self) -> Self {
        self.ops.push(Op::Member);
        self
    }

    /// `eq` — replaces the top two stack values with a boolean indicating
    /// equality. Emitted by MerkleTree.checkRoot's `(root) (push rt) (eq)`
    /// sequence.
    pub fn eq(mut self) -> Self {
        self.ops.push(Op::Eq);
        self
    }

    /// `root` — replaces the top-of-stack `BoundedMerkleTree` with its
    /// digest. Emitted by MerkleTree.checkRoot before the `eq`.
    pub fn root(mut self) -> Self {
        self.ops.push(Op::Root);
        self
    }

    /// `popeq` for read paths. In `ResultModeGather`, `ReadResult` is `()`.
    pub fn popeq(mut self, cached: bool) -> Self {
        self.ops.push(Op::Popeq { cached, result: () });
        self
    }

    /// Consume the builder and return the assembled op vector ready to
    /// pass to [`crate::query_for_read`].
    pub fn build(self) -> Vec<Op<ResultModeGather, D>> {
        self.ops
    }
}

impl<D: DB> Default for OpProgramGather<D> {
    fn default() -> Self {
        Self::new()
    }
}
