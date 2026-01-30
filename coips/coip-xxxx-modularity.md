---
COIPID: XXXX
Title: Modular Organization of Compact Standard Library
Authors: Bob Blessing-Hartley <@bobblessing-hartley> Kevin Millikin<@kmillikin>
Status: Proposed
Category: Core
Created: 2026-01-28
Requires: None
Replaces: None
---

## Abstract

This COIP proposes restructuring the Compact language standard library from a single monolithic `CompactStandardLibrary` module into a modular organization with domain-specific modules (`CompactCore`, `CompactCrypto`, `CompactCoins`). The proposal leverages existing selective import infrastructure (added September 2025) to enable developers to import only the primitives relevant to their contracts. This change reduces namespace pollution (currently 57 mandatory imports), improves code clarity, aligns Compact with industry standards (Circom, Cairo, Noir, Leo, ZoKrates all use modular libraries), and directly addresses the architectural requirements for ECDSA and other signature verification primitives. The migration will maintain full backward compatibility through a dual-import strategy spanning 18+ months.

## Motivation

### Current Problems

The Compact standard library currently requires developers to import all 57 primitives regardless of need:

```compact
import CompactStandardLibrary;  // All-or-nothing: 57 items

// Even simple contracts import everything:
circuit computeHash(data: Bytes<32>): Bytes<32> {
    return persistentHash(data);  // Only uses 1 of 57 imports
}
```

This creates several problems:

1. **Namespace Pollution**: Every contract reserves 57 names (Bytes, Vector, Coins, Dust, persistentHash, ecAdd, etc.), preventing developers from using these identifiers even when the primitives are unused.
2. **Conceptual Conflation**: Three unrelated domains are mixed in one import:
   - Generic collections (Bytes, Vector, Field) - 9 items
   - Cryptographic primitives (persistentHash, ecAdd, ecMul) - 16 items
   - Token/coin management (Coins, Dust, Zswap) - 32 items
3. **Developer Confusion**: Contracts cannot signal their domain through imports. A cryptographic contract looks identical to a token contract from the import statement.
5. **Industry Misalignment**: All major ZK languages use modular standard libraries:
   - Circom: `include "circomlib/circuits/poseidon.circom"`
   - Cairo: `from starkware.cairo.common.hash import hash2`
   - Noir: `use dep::std::hash::pedersen_hash`
   - Leo: `import std.crypto.pedersen`
   - ZoKrates: `import "hashes/sha256/512bit" as sha256`

### Use Cases Enabled

**Contract Domain Clarity**:
```compact
// Before: Unclear what this contract does
import CompactStandardLibrary;

// After: Clear cryptographic focus
import CompactCrypto;
```

**Reduced Namespace Pollution**:
```compact
// After: Only 16 crypto names reserved (vs. 57 total)
import CompactCrypto;

type Data = { ... };  // "Data" now available (previously reserved)
```

**Ethereum Interoperability** (ECDSA example):

```compact
import CompactCrypto;  // Dedicated crypto library now exists

circuit verifyEthIdentity(
    address: Bytes<20>,
    message: Bytes<32>,
    signature: Bytes<65>
): Bool {
    return verify_ecdsa_secp256k1(address, message, signature);
}
```

**Selective Dependencies**:
```compact
// Token contracts only import token primitives
import CompactCoins;

// Crypto contracts only import crypto primitives
import CompactCrypto;

// Both if needed
import CompactCrypto;
import CompactCoins;
```

### Benefits for Midnight Ecosystem

- **Developer Experience**: 60-80% reduction in namespace pollution for focused contracts
- **Code Clarity**: Import statements signal contract purpose
- **Documentation**: API reference naturally organized by domain
- **Ecosystem Growth**: Enables future third-party library ecosystem
- **Competitive Position**: Aligns with industry standards, improves adoption
- **Feature Delivery**: Accelerates future cryptographic primitives and other third party libraries

## Specification

### Phase 1: Three-Module Organization (Tier 1)

Split `CompactStandardLibrary` into three domain-specific modules:

#### CompactCore Module

**File**: /compiler/standard-library-core.compact`

**Exports** (9 items):
```compact
export module CompactCore {
    // Generic types
    export type Bytes<#n>;
    export type Vector<#n, T>;
    export type Field;
    export type Curve;

    // Builders
    export type VectorBuilder<#n, T>;
    export circuit newVectorBuilder<#n, T>(): VectorBuilder<n, T>;
    export circuit pushVectorBuilder<#n, T>(
        builder: VectorBuilder<n, T>,
        item: T
    ): VectorBuilder<n, T>;
    export circuit buildVector<#n, T>(
        builder: VectorBuilder<n, T>
    ): Vector<n, T>;

    // Data structure primitives
    export circuit concat<#n, #m>(
        v1: Bytes<n>,
        v2: Bytes<m>
    ): Bytes<n + m>;
}
```

#### CompactCrypto Module

**File**: /compiler/standard-library-crypto.compact`

**Exports** (16 items):
```compact
export module CompactCrypto {
    // Hashing
    export circuit persistentHash<A>(value: A): Bytes<32>;
    export circuit transientHash<A>(value: A): Field;
    export circuit degradeToTransient<A>(value: A): Field;
    export circuit upgradeFromTransient<A>(value: Field): A;

    // Commitment
    export circuit persistentCommit<A>(value: A): Bytes<32>;
    export circuit transientCommit<A>(value: A): Field;

    // Elliptic Curve Operations
    export circuit ecAdd(p1: Curve, p2: Curve): Curve;
    export circuit ecMul(scalar: Field, point: Curve): Curve;
    export circuit ecMulGenerator(scalar: Field): Curve;
    export circuit hashToCurve<A>(value: A): Curve;
    export circuit nativePointX(point: Curve): Field;
    export circuit nativePointY(point: Curve): Field;
    export circuit constructNativePoint(x: Field, y: Field): Curve;

    // Merkle Trees
    export circuit merkle_<ProofSize>(/* ... */): Bool;
    export circuit createMerkleTree<#n, A>(/* ... */): MerkleTree;

    // Future: ECDSA (addresses PRD requirement)
    export circuit verify_ecdsa_secp256k1(
        pubkey: Bytes<33>,
        message: Bytes<32>,
        signature: Bytes<64>
    ): Bool;
}
```

#### CompactCoins Module

**File**: `/compiler/standard-library-coins.compact`

**Exports** (32 items):
```compact
export module CompactCoins {
    // Shielded Tokens
    export type Coins<A>;
    export type Dust<A>;
    export type ZswapInput<A>;
    export type ZswapOutput<A>;
    export circuit createZswapInput<A>(/* ... */): ZswapInput<A>;
    export circuit createZswapOutput<A>(/* ... */): ZswapOutput<A>;

    // Unshielded Tokens
    export type UnshieldedTokens<#n, A>;
    export circuit createUnshieldedTokens<#n, A>(/* ... */): UnshieldedTokens<n, A>;

    // Time-locked Functions
    export circuit waitUntil<A>(/* ... */): A;

    // Witness/Oracle Functions
    export witness ownPublicKey(): PublicKey;

    // ... (28 more coin/token-related exports)
}
```

#### Backward Compatibility Re-export

**File**: `/compiler/standard-library.compact` (modified)

```compact
// Deprecated: Use specific modules instead
export module CompactStandardLibrary {
    // Re-export everything from all modules
    export * from CompactCore;
    export * from CompactCrypto;
    export * from CompactCoins;
}
```

### Import Syntax

**New Contracts** (Recommended):
```compact
import CompactCore;      // Generic types and builders
import CompactCrypto;    // Cryptographic primitives
import CompactCoins;     // Token/coin management

circuit myContract() {
    let hash = persistentHash(data);  // From CompactCrypto
    let coins = Coins.empty();        // From CompactCoins
}
```

**Selective Imports** (Also Supported):
```compact
import { persistentHash, ecAdd } from CompactCrypto;
import { Coins, Dust } from CompactCoins;

circuit myContract() {
    let hash = persistentHash(data);
}
```

**Legacy Contracts** (Deprecated but Functional):
```compact
import CompactStandardLibrary;  // Still works, imports all 57 items
// Warning: CompactStandardLibrary is deprecated. Use specific modules.
```

### Compiler Changes

**File**: `/compiler/analysis-passes.ss`

**Function**: `expand-modules-and-types

**Current Logic**:
```scheme
;; Special case for standard library (remove this)
(if (equal? module-name "CompactStandardLibrary")
    (load-precompiled-stdlib)  ; All-or-nothing
    (process-selective-imports))  ; Works for user modules
```

**Updated Logic**:
```scheme
;; Treat all modules uniformly
(process-selective-imports)  ; Works for stdlib and user modules
```

**Additional Changes**:
1. Parse `standard-library-core.compact`, `standard-library-crypto.compact`, `standard-library-coins.compact` at compiler startup
2. Maintain `standard-library.compact` as re-export for backward compatibility
3. Add deprecation warnings for `CompactStandardLibrary` import (Phase 2)

**Estimated Changes**: 50-100 lines of Scheme code

### Native Entry Declarations

**File**: /compiler/midnight-natives.ss`

**No changes required** - Native declarations remain centralized:

```scheme
;; These stay in one place
(declare-native-entry external persistentHash [A] /* ... */)
(declare-native-entry external ecAdd [] /* ... */)
;; ... all 57 native declarations
```

Module organization is a **compile-time abstraction** - runtime bindings are unaffected.

### Runtime Bindings

**File**: `/runtime/src/built-ins.ts`

**No changes required** - Runtime stays as single class:

```typescript
export class CompactRuntime {
    persistentHash(value: any): Uint8Array { /* ... */ }
    ecAdd(p1: CurvePoint, p2: CurvePoint): CurvePoint { /* ... */ }
    // ... all 57 methods remain in one class
}
```

Module organization is transparent to the runtime.

### Phase 2: Fine-Grained Modules (Tier 2) - Future Work

**Proposed Structure** (not part of initial COIP):

```
CompactCore
├── Types
└── Builders

CompactCrypto
├── Hashing
├── EllipticCurve
├── Commitment
└── MerkleTree

CompactCoins
├── Shielded
└── Unshielded
```

**Import Example**:
```compact
import { persistentHash } from CompactCrypto.Hashing;
import { ecAdd, ecMul } from CompactCrypto.EllipticCurve;
```

This deeper modularization would be proposed in a future COIP after Tier 1 proves successful.

## Rationale

### Why This Approach?

**1. Leverage Existing Infrastructure**

Selective import functionality already exists (added September 2025, commit d05dc8da) and works perfectly for user modules:

```compact
// This works today
import { Circuit } from UserModule;
```

The infrastructure is **proven and stable** - we're just applying it to the standard library.

**2. Minimal Risk**

- Compiler changes: 50-100 lines of code
- No changes to native declarations (privacy/disclosure tracking unaffected)
- No changes to runtime bindings
- Module organization is compile-time only (no runtime overhead)
- Backward compatibility via re-exports (no breaking changes)

**3. Immediate Value**

- Accelerates introduction of new Crypto primitices  (enables `CompactCrypto` module)
- 60-80% reduction in namespace pollution for focused contracts
- Aligns with industry standards (competitive necessity)
- Improves developer onboarding (clearer domain boundaries)

**4. Incremental Path**

Phase 1 (Tier 1) provides immediate benefits with low risk. Phase 2 (Tier 2) can follow once Tier 1 proves successful. No need for big-bang refactoring.

### Alternatives Considered

**Alternative 1: Keep Monolithic Library**

 **Rejected**

- Continues namespace pollution
- Blocks ECDSA PRD delivery
- Out of alignment with industry (Circom, Cairo, Noir, Leo all modular)
- Developer dissatisfaction (evidence of workarounds in codebase)

**Alternative 2: Fine-Grained Modules (8-10 modules) Immediately**

**Deferred to Phase 2**

- Higher implementation risk (6-8 weeks vs. 3-4 weeks)
- More invasive changes to compiler
- Can iterate after Tier 1 success

**Alternative 3: Namespace-Based Organization (e.g., `Compact.Crypto.*`)**

**Rejected**

- Doesn't match Compact's existing module syntax
- Would require new language features (namespaces don't exist)
- Higher complexity than leveraging existing selective imports

**Alternative 4: Per-Primitive Modules (57 modules)**

**Rejected**

- Excessive granularity (57 imports for comprehensive contracts)
- Cognitive overhead (which module has `ecAdd`?)
- No other ZK language goes this fine-grained

### Design Decisions

**Three Modules (Not Two or Four)**

- **Core**: Generic types used by all contracts (Bytes, Vector, Field)
- **Crypto**: Domain-specific for cryptographic operations
- **Coins**: Domain-specific for token/value management

This balances granularity with simplicity. Most contracts import 1-2 modules, not all 3.

**Module Naming Convention**

`Compact<Domain>` format:
- Consistent with existing `CompactStandardLibrary`
- Clear ownership (Compact = official, first-party)
- Enables future third-party libraries (`@community/EthereumBridge`)

**Re-export for Backward Compatibility**

Maintaining `CompactStandardLibrary` as a re-export ensures:
- Zero breaking changes on day one
- Gradual migration (18+ month timeline)
- Confidence in ecosystem stability

## Backwards Compatibility Assessment

### Zero Breaking Changes

**Day 1 (COIP Implementation)**:
- All existing contracts continue to work unchanged
- `import CompactStandardLibrary;` remains valid
- No recompilation required

**Months 1-12 (Adoption Period)**:
- New contracts encouraged to use modular imports
- Existing contracts can migrate at their own pace
- No warnings or deprecation notices yet

**Months 13-18 (Deprecation Period)**:
- Compiler emits warnings for `CompactStandardLibrary` import:
  ```
  Warning: CompactStandardLibrary is deprecated.
  Migrate to: import CompactCore; import CompactCrypto; import CompactCoins;
  ```
- Migration tool available: `compactc migrate --stdlib-split mycontract.compact`
- Documentation updated with migration guide

**Month 19+ (Optional Removal)**:
- Community vote on whether to remove `CompactStandardLibrary` entirely
- If removed, contracts must migrate (breaking change requires hard fork coordination)
- **Recommendation**: Keep indefinitely if migration adoption <80%

### Hard Fork Required?

**No** - This is a compiler/language change, not a protocol change:
- Compiled contracts produce identical ZKIR circuits
- No changes to transaction format
- No changes to ledger state
- No changes to consensus rules

**Deployment**: Standard compiler release (no network coordination needed)

### Migration Path

**Automated Migration Tool**:

```bash
compactc migrate --stdlib-split mycontract.compact
```

**Before**:
```compact
import CompactStandardLibrary;

circuit myContract() {
    let hash = persistentHash(data);
    let coins = Coins.empty();
}
```

**After**:
```compact
import CompactCrypto;
import CompactCoins;

circuit myContract() {
    let hash = persistentHash(data);
    let coins = Coins.empty();
}
```

**Manual Migration** (for complex contracts):
1. Identify which primitives are used (`grep` for function names)
2. Determine which modules are needed:
   - Uses `persistentHash`, `ecAdd`, etc. → `import CompactCrypto;`
   - Uses `Coins`, `Dust`, etc. → `import CompactCoins;`
   - Uses `Bytes`, `Vector`, etc. → `import CompactCore;`
3. Replace `import CompactStandardLibrary;` with specific imports
4. Test contract compilation and behavior

### Ecosystem Impact

**Official Examples** (`/examples/`):

- Migrated as part of COIP implementation
- Serve as reference for community contracts

**Partner Contracts**:
- No immediate action required
- Migration guide provided
- Support available during adoption period

**Third-Party Libraries**:
- User-defined modules unaffected (already use selective imports)
- Future libraries can depend on specific stdlib modules

### Tooling Impact

**Compiler**:
- Supports both old and new import styles
- Deprecation warnings configurable (off by default initially)

**IDE/Editor Support**:
- Auto-import suggestions updated to recommend modular imports
- Syntax highlighting unchanged (existing module syntax)

**Documentation**:
- API reference split by module (improves organization)
- Migration guide added
- Tutorial examples updated

## Security Considerations

### Privacy/Disclosure Tracking

**Risk**: Modularization breaks privacy analysis (disclosure tracking)

**Mitigation**:
- Native declarations remain centralized in `midnight-natives.ss`
- Disclosure metadata (`(discloses "...")`) is coupled to native declarations, not module organization
- Module splits are compile-time abstraction (no runtime impact)
- Disclosure tracking logic in `analysis-passes.ss` reads from native declarations (unchanged)

**Validation**:
- Comprehensive test suite for privacy analysis (all examples)
- Pre-release validation on testnet contracts
- Security review of `analysis-passes.ss` changes

**Conclusion**: No impact on privacy guarantees

### Circuit Security

**Risk**: Module organization introduces circuit-level vulnerabilities

**Mitigation**:
- Generated ZKIR circuits are **identical** regardless of import style
- Compiler produces same circuit for `import CompactStandardLibrary;` vs. `import CompactCrypto;`
- Module organization is compile-time only (no circuit changes)

**Validation**:
- Diff ZKIR output before/after migration (should be identical)
- Circuit equivalence testing on all examples

**Conclusion**: No impact on circuit security

### Supply Chain Security

**Risk**: Malicious module injection

**Mitigation**:
- All three modules (`CompactCore`, `CompactCrypto`, `CompactCoins`) are **first-party** (maintained by Midnight)
- Shipped with compiler (not external dependencies)
- Same trust model as current `CompactStandardLibrary`

**Future Consideration** (Phase 4 - Third-Party Libraries):
- Package signature verification
- Dependency auditing tooling
- Curated library registry
- (Out of scope for this COIP)

**Conclusion**: No change to trust model

### New Attack Vectors

**Considered**:
1. **Namespace confusion**: Developer imports wrong module, uses incorrect primitive
   - Mitigation: Compiler errors for undefined functions, clear documentation
2. **Module substitution**: Attacker provides fake `CompactCrypto` module
   - Mitigation: Compiler only loads modules from trusted compiler installation directory
3. **Partial import vulnerabilities**: Developer forgets to import required module
   - Mitigation: Compile-time error (function not found)

**Conclusion**: No new attack vectors introduced

### Audit Requirements

**Compiler Changes**:
- Internal code review of `analysis-passes.ss` modifications
- Test suite validation (privacy, circuit equivalence, functionality)
- No external audit required (low-risk language feature)

**Documentation**:
- Security team review of migration guide
- Ensure no misleading guidance about module boundaries

## Implementation

### Components Modified

**1. Compact Compiler** (`/compiler/`)

**Files Created**:
- `standard-library-core.compact` (new, ~100 lines)
- `standard-library-crypto.compact` (new, ~150 lines)
- `standard-library-coins.compact` (new, ~250 lines)

**Files Modified**:
- `standard-library.compact` (change exports to re-exports from 3 modules)
- `analysis-passes.ss` (remove stdlib special case, ~50-100 lines changed)

**Files Unchanged**:
- `midnight-natives.ss` (native declarations stay centralized)
- `parsing.ss` (import syntax already supports selective imports)
- `standard-library-aliases.ss` (naming conventions unchanged)

**2. Runtime** (`/runtime/`)

**Files Unchanged**:
- `src/built-ins.ts` (single runtime class remains, no changes)

**3. Examples** (`/examples/`)

**Files Modified**: All example contracts updated to use modular imports
- `election.compact`
- `zerocash.compact`
- `curvepoint/examples.compact`
- `modules/selective_examples.compact`
- ~15 example files total

**4. Documentation** (`/doc/`)

**Files Created**:
- `stdlib-migration-guide.md` (new)
- `api/CompactCore/README.md` (new)
- `api/CompactCrypto/README.md` (new)
- `api/CompactCoins/README.md` (new)

**Files Modified**:
- `api/CompactStandardLibrary/README.md` (add deprecation notice, link to migration guide)
- `compiler-usage.md` (update import examples)
- Tutorial/getting-started guides

### Implementation Timeline

**Week 1: Preparation**
- Create `standard-library-{core,crypto,coins}.compact` files
- Copy exports from `standard-library.compact` to respective modules
- Update `standard-library.compact` to re-export from modules

**Week 2: Compiler Changes**
- Modify `expand-modules-and-types` in `analysis-passes.ss`
- Remove stdlib special case
- Test module loading at compiler startup

**Week 3: Testing**
- Unit tests for selective imports (stdlib modules)
- Integration tests (compile all examples with new imports)
- Regression tests (verify ZKIR output unchanged)
- Privacy analysis tests (verify disclosure tracking works)

**Week 4: Documentation & Migration**
- Migrate all examples to modular imports
- Write migration guide
- Update API reference (split by module)
- Update tutorials

**Week 5: Beta Release**
- Release to partners for validation
- Gather feedback
- Fix issues

**Week 6: Stable Release**
- Incorporate feedback
- Final testing
- Release compiler version with modular stdlib

### Dependencies

**Internal**:
- Compact compiler (version ≥1.X where selective imports exist)
- No changes to `midnight-ledger`, `midnight-node`, or other components

**External**:
- None (self-contained language feature)

### Team Allocation

**Compiler Engineer**: 1 FTE for 6 weeks (4 weeks implementation + 2 weeks beta/release)

**Technical Writer**: 0.5 FTE for 2 weeks (documentation and migration guide)

**QA Engineer**: 0.5 FTE for 2 weeks (testing and validation)

**Total Effort**: ~8 person-weeks

## Testing

### Test Categories

**1. Unit Tests** (Compiler)

**Selective Import Parsing**:
```scheme
;; analysis-passes.ss tests
(test "parse stdlib module imports"
  (expand-modules-and-types '(import CompactCrypto))
  => (module-binding "CompactCrypto" (exports ...)))

(test "parse selective imports from stdlib"
  (expand-modules-and-types '(import { persistentHash } from CompactCrypto))
  => (binding "persistentHash" ...))

(test "backward compat: CompactStandardLibrary still works"
  (expand-modules-and-types '(import CompactStandardLibrary))
  => (module-binding "CompactStandardLibrary" (all-exports)))
```

**Module Loading**:
```scheme
(test "load core module"
  (load-stdlib-module "CompactCore")
  => (module (exports (type Bytes) (type Vector) ...)))

(test "load crypto module"
  (load-stdlib-module "CompactCrypto")
  => (module (exports (circuit persistentHash) ...)))
```

**2. Integration Tests** (Example Contracts)

**Compile with Modular Imports**:
```bash
# All examples should compile with new imports
for example in examples/*.compact; do
  compactc "$example" output/ || exit 1
done
```

**Circuit Equivalence**:
```bash
# Verify ZKIR output identical before/after migration
compactc examples/election.compact old-output/ --before-migration
compactc examples/election.compact new-output/ --after-migration
diff old-output/election.zkir new-output/election.zkir  # Should be identical
```

**Selective Import Combinations**:
```compact
// Test 1: Single module
import CompactCrypto;
circuit test1() { persistentHash(...); }

// Test 2: Multiple modules
import CompactCrypto;
import CompactCoins;
circuit test2() { persistentHash(...); Coins.empty(); }

// Test 3: Selective from single module
import { persistentHash, ecAdd } from CompactCrypto;
circuit test3() { persistentHash(...); ecAdd(...); }

// Test 4: Backward compat
import CompactStandardLibrary;
circuit test4() { persistentHash(...); Coins.empty(); }
```

**3. Regression Tests** (Privacy & Disclosure)

**Disclosure Tracking**:
```compact
import CompactCrypto;

circuit test_disclosure() {
    let hash = persistentHash(secret);
    // Privacy analysis should still detect:
    // "hash discloses a hash of secret"
}
```

Verify disclosure metadata correctly propagates through modular imports.

**Privacy Analysis**:
```bash
# All examples should pass privacy analysis
compactc --check-privacy examples/*.compact
```

**4. Performance Tests**

**Compilation Time**:
```bash
# Measure before/after migration
time compactc examples/zerocash.compact output/
# Should have <5% regression (ideally no change)
```

**Memory Usage**:
```bash
# Monitor compiler memory during module loading
/usr/bin/time -v compactc examples/*.compact output/
```

**5. Backward Compatibility Tests**

**Old Import Style**:
```compact
import CompactStandardLibrary;  // Must still work
```

**Mixed Styles** (if contracts include modules using different styles):
```compact
// Contract A (old style)
import CompactStandardLibrary;

// Contract B (new style)
import CompactCrypto;

// Both should interoperate via compiled artifacts
```

**6. Migration Tool Tests**

**Automated Migration**:
```bash
compactc migrate --stdlib-split examples/election.compact

# Verify output:
# - Imports changed to modular
# - Code unchanged
# - Contract compiles successfully
```

**Edge Cases**:
- Contracts with no stdlib imports (should be unchanged)
- Contracts with user module imports (should handle correctly)
- Contracts with comments near import statements (preserve comments)

### Test Environments

**1. Local Development**:
- Compiler test suite (Scheme tests in `/tests/`)
- Example compilation
- Manual validation

**2. CI/CD Pipeline**:
- Automated test suite on every commit
- Performance regression gates
- Example compilation verification

**3. Testnet**:
- Deploy migrated example contracts
- Verify on-chain behavior identical
- Stress test with partner contracts

**4. Partner Validation**:
- Beta release to select partners
- Real-world contract migration
- Feedback collection

### Acceptance Criteria

**All tests pass**:

- Unit tests (compiler)
- Integration tests (examples)
- Regression tests (privacy)
- Performance tests (no >5% regression)

**Backward compatibility maintained**:

- `import CompactStandardLibrary;` still works
- Existing compiled contracts unchanged

**Examples migrated**:

- All 15+ examples use modular imports
- All compile successfully
- Generated circuits identical to pre-migration

**Documentation complete**:

- Migration guide written
- API reference split by module
- Tutorials updated

**Partner validation**:

- At least 3 partners test migration
- Zero blocking issues reported

## Copyright Waiver

All contributions (code and text) submitted in this COIP are licensed under the Apache License, Version 2.0. By submitting this COIP, the author agrees to the Midnight Foundation Contributor License Agreement, which includes the assignment of copyright for contributions to the Foundation.

---

## Appendix A: Example Migration

### Before (Current)

```compact
import CompactStandardLibrary;

circuit verifyIdentity(
    ethAddress: Bytes<20>,
    message: Bytes<32>,
    signature: Bytes<65>
): Bool {
    // Uses crypto primitives only
    let messageHash = persistentHash(message);
    return verify_ecdsa_secp256k1(ethAddress, messageHash, signature);
}
```

**Issues**:
- Imports 57 items (only uses 2)
- Unclear that this is a cryptographic contract
- 57 names reserved in namespace

### After (Proposed)

```compact
import CompactCrypto;

circuit verifyIdentity(
    ethAddress: Bytes<20>,
    message: Bytes<32>,
    signature: Bytes<65>
): Bool {
    // Clear crypto focus from imports
    let messageHash = persistentHash(message);
    return verify_ecdsa_secp256k1(ethAddress, messageHash, signature);
}
```

**Benefits**:
- Imports 16 items (only crypto primitives)
- Clear domain focus
- 16 names reserved (vs. 57)

### Selective Import Alternative

```compact
import { persistentHash, verify_ecdsa_secp256k1 } from CompactCrypto;

circuit verifyIdentity(
    ethAddress: Bytes<20>,
    message: Bytes<32>,
    signature: Bytes<65>
): Bool {
    let messageHash = persistentHash(message);
    return verify_ecdsa_secp256k1(ethAddress, messageHash, signature);
}
```

**Benefits**:
- Imports 2 items (only what's used)
- Maximum clarity
- 2 names reserved (vs. 57)

## Appendix B: Module Contents Reference

### CompactCore (9 items)

**Types**: Bytes, Vector, Field, Curve
**Builders**: VectorBuilder, newVectorBuilder, pushVectorBuilder, buildVector
**Operations**: concat

### CompactCrypto (16 items)

**Hashing**: persistentHash, transientHash, degradeToTransient, upgradeFromTransient
**Commitment**: persistentCommit, transientCommit
**Elliptic Curve**: ecAdd, ecMul, ecMulGenerator, hashToCurve, nativePointX, nativePointY, constructNativePoint
**Merkle Trees**: merkle_*, createMerkleTree
**Future**: verify_ecdsa_secp256k1 (ECDSA PRD)

### CompactCoins (32 items)

**Shielded Types**: Coins, Dust, ZswapInput, ZswapOutput
**Shielded Operations**: createZswapInput, createZswapOutput, (20+ more)
**Unshielded Types**: UnshieldedTokens, UnshieldedTokensBuilder
**Unshielded Operations**: createUnshieldedTokens, (8+ more)
**Witness**: ownPublicKey, waitUntil

## Appendix C: Related Work

