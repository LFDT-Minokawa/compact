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
    /// container at depth `n` (a Map / Set / Array / `MerkleTree` write).
    /// `cached` controls whether the write should be marked cached for
    /// witness-side reads.
    pub fn ins(mut self, cached: bool, n: u8) -> Self {
        self.ops.push(Op::Ins { cached, n });
        self
    }

    /// `rem` — remove the top stack value's key from the container below
    /// it on the stack (Set.remove / Map.remove). Mirrors the
    /// `(rem [cached ...])` vminstruction emitted for ADT `remove` ops.
    #[allow(clippy::should_implement_trait)]
    pub fn rem(mut self, cached: bool) -> Self {
        self.ops.push(Op::Rem { cached });
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
    /// `MerkleTree` / `HistoricMerkleTree` `insert` vm-code when the same
    /// container needs to appear in two stack positions before successive
    /// `ins` ops update the tree and its first-free index / history map.
    pub fn dup(mut self, n: u8) -> Self {
        self.ops.push(Op::Dup { n });
        self
    }

    /// `root` — replace the top-of-stack `BoundedMerkleTree` with its
    /// digest (root hash). Used by `HistoricMerkleTree` `insert` to derive the
    /// key for the history map entry that records the just-updated tree's
    /// root.
    pub fn root(mut self) -> Self {
        self.ops.push(Op::Root);
        self
    }

    /// `lt` — pop the top two stack values and push the boolean result of
    /// `top-1 < top`. Emitted by the bounded-index variants of `MerkleTree` /
    /// `HistoricMerkleTree` `insert*Index*` vm-code (`insertIndex`,
    /// `insertHashIndex`, `insertIndexDefault`) where the post-insert
    /// first-free index is `max(old_first_free, index + 1)` — implemented
    /// as a compare-then-branch on the VM stack.
    pub fn lt(mut self) -> Self {
        self.ops.push(Op::Lt);
        self
    }

    /// `branch` — skip the next `skip` instructions if the top-of-stack
    /// boolean is `true`. Emitted by the bounded-index `MerkleTree` /
    /// `HistoricMerkleTree` `insert*Index*` vm-code (alongside `jmp`) to
    /// pick between the new and old first-free index after the `lt`.
    pub fn branch(mut self, skip: u32) -> Self {
        self.ops.push(Op::Branch { skip });
        self
    }

    /// `jmp` — unconditionally skip the next `skip` instructions. Pairs
    /// with `branch` in the bounded-index `insert*Index*` vm-code; on the
    /// taken-branch side, `jmp` over the `swap`/`pop` cleanup that the
    /// fallthrough side runs.
    pub fn jmp(mut self, skip: u32) -> Self {
        self.ops.push(Op::Jmp { skip });
        self
    }

    /// `swap` — swap the top of stack with the value at depth `n+1`.
    /// Emitted by the bounded-index `insert*Index*` vm-code's cleanup
    /// arm when the supplied index is *not* greater than the current
    /// first-free counter, so the old counter has to be moved back to
    /// the top before the matching `pop` discards the speculative
    /// `index + 1` value.
    pub fn swap(mut self, n: u8) -> Self {
        self.ops.push(Op::Swap { n });
        self
    }

    /// `pop` — discard the top of stack. Emitted by both arms of the
    /// bounded-index `insert*Index*` vm-code to drop the loser of the
    /// `max(old_first_free, index + 1)` comparison once the winner has
    /// been positioned for the `ins` that follows.
    pub fn pop(mut self) -> Self {
        self.ops.push(Op::Pop);
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

    /// `size` — replace the top-of-stack container (Map / Set / List /
    /// Array) with a `Cell(u64)` holding its element count. Emitted by the
    /// read-no-arg ADT ops `Set.size`, `Set.isEmpty`, `Map.size`,
    /// `Map.isEmpty`.
    pub fn size(mut self) -> Self {
        self.ops.push(Op::Size);
        self
    }

    /// `type` — replace the top-of-stack `StateValue` with a `Cell` whose
    /// 1-byte payload tags the value's shape (Null=0, Cell=1, Map=2, …).
    /// Emitted by `List.isEmpty` to detect the `Null` sentinel at the head
    /// of an empty cons list.
    pub fn type_(mut self) -> Self {
        self.ops.push(Op::Type);
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
