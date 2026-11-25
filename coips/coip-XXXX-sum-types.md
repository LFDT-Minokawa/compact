---
CoIP: X
Title: Sum Types: Enums with Data and Pattern Matching
Authors:
  - Joseph Denman (JosephDenman)
Status: Draft
Category: Language
Created: 2026-11-19
Requires: none
Replaces: none
---

<!--
 This file is part of Compact.
 Copyright (C) 2026 Minokawa project contributors
 SPDX-License-Identifier: Apache-2.0
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
-->

## Abstract

<!--
The abstract is a short (about 200 word) description of the issue being
addressed and the proposed solution.
-->

Compact has no sum types.  A value that is one of several alternatives
is written as a structure that holds a tag and a field for every
alternative, as the standard library's `Maybe` and `Either` are.
Nothing ties the tag to the fields, so a program or a prover can
produce values that mean nothing, and nothing checks that a program
handles every alternative.  This proposal adds sum types to Compact in
three parts:

1. enumeration variants that carry fields,
2. a `match` form that takes such values apart and is checked for
   exhaustiveness, and
3. a representation in which variants share space for fields of the
   same type, with the compiler asserting that every value which comes
   from the prover or from raw bytes is valid.

`Maybe` and `Either` become ordinary enumerations, and the compiler
declares the ledger's three sum types (`PublicAddress`,
`ShieldedRecipient`, and `TokenType`) as enumerations with the layouts
that the ledger requires.  No change to ZKIR, the virtual machine, or
the ledger is needed.  The changes to the standard library break
existing programs and are made at a language version.  Whether
`Either` should keep its current encoding is left open for review.

## Motivation

<!--
Clearly explain the problem and why the existing Compact language and tooling is
inadequate to address the problem.
-->

Compact's program-defined types are structures and enumerations, and
the values of an enumeration, such as the four values of
`enum Arrow { up, down, left, right }`, carry no data.  A type whose
values are one of several alternatives, each with its own data, must
therefore be written as a structure with a tag and a field for every
alternative.  The standard library does exactly this:

```compact
export struct Maybe<T> { is_some: Boolean; value: T; }
export struct Either<A, B> { is_left: Boolean; left: A; right: B; }
```

This encoding has five problems.

1. **Values that mean nothing.**  Nothing ties the tag to the fields.
   `Maybe<Field> { is_some: false, value: 7 }` compiles, and its value
   is not equal to `none<Field>()`.
2. **Values that the prover chooses.**  When a `Maybe<Field>` is an
   argument of an exported circuit or the result of a witness, the
   circuit constrains `is_some` to be a `Boolean` and leaves `value`
   free.  The values `{ false, 7 }` and `{ false, 8 }` are then
   different set members, map keys, and hash inputs that both read as
   "none."
3. **Alternatives that are not checked.**  A field can be read without
   testing the tag.  `l.head().value` compiles and yields a default
   value when `l` is empty, and the standard library itself reads
   `recipient.is_left ? recipient.left.bytes : recipient.right.bytes`.
4. **Ledger types that cannot be written.**  The kernel's operations
   take `Either`s in place of the ledger's own sum types for
   addresses, recipients, and token types.  The ledger's token type
   has a third alternative, for Dust, that an `Either` cannot express.
   The ledger also rejects an address, recipient, or token type whose
   unused alternative is not empty, yet a contract that passes one to
   a kernel operation compiles.
5. **Width paid for every alternative.**  An
   `Either<Bytes<32>, Bytes<32>>` carries two `Bytes<32>` values in
   every argument, transcript, ledger cell, and hash input, although
   it holds only one.

This proposal makes sum types part of the language, so that a value is
exactly one of its alternatives, the compiler checks that every
alternative is handled, and a prover cannot fill an alternative that
is not in use.  It requires no change to ZKIR, the virtual machine, or
the ledger.

## Specification

<!--
Describe the proposed solution in sufficient technical detail that it could be
implemented.  The intended behavior should be clearly described and unambiguous.
-->

The three language features are described in turn, followed by their
application to the standard library and the kernel, their treatment
outside circuits, and the proposal's limitations.

### Enumerations with Fields

An enumeration's variants may now carry fields, and an enumeration may
take generic parameters.  Here is an example.

```compact
enum Order { Open, Filled(Bytes<32>, Uint<64>), Cancelled(Bytes<32>) }
enum Maybe<T> { None, Some(T) }
```

A value of type `Order` is exactly one of `Open`, `Filled` with a
`Bytes<32>` and a `Uint<64>`, and `Cancelled` with a `Bytes<32>`.  The
production for an enumeration declaration changes, and a production
for variants is added, in the notation of the Compact reference
grammar:

> _enum-declaration_ &rarr; `export`<sup>opt</sup> `enum` _enum-name_ _gparams_<sup>opt</sup> `{` _variant_ `,` ⋯¹ `,` _variant_ `,`<sup>opt</sup> `}` `;`<sup>opt</sup>
>
> _variant_ &rarr; _id_ | _id_ `(` _type_ `,` ⋯¹ `,` _type_ `,`<sup>opt</sup> `)`

A variant's fields are identified by position.  A generic enumeration
is specialized with explicit generic arguments wherever it is used, as
a generic structure is.  Two enumeration types are the same type when
they have the same name, the same variant names in the same order, and
the same field types.  An enumeration may not contain itself, directly
or indirectly, because every Compact type has a fixed size.  A
variant's **tag** is its position in the declaration, counting from 0,
as for today's enumerations, and it is never written in a program.

A value is constructed by naming a variant through its enumeration
with the new token `::` and, when the variant has fields, applying it
to their values, as in `Maybe<Field>::Some(x)`, `Maybe<Field>::None`,
and `Arrow::up`:

> _expr_ &rarr; _tref_ `::` _id_ | _tref_ `::` _id_ `(` _expr_ `,` ⋯ `,` _expr_ `,`<sup>opt</sup> `)`

The first form is required for a variant without fields and the second
for a variant with fields.  There must be one argument for each field,
the type of each argument must be a subtype of its field's type, and
the arguments are evaluated from left to right.  Generic arguments are
written on the enumeration, not on the variant.  Because `.` now
selects only a member of a value (a structure field, a ledger
operation, or a circuit of a contract), today's `Arrow.up` is a static
error, and `compact fixup` rewrites it as `Arrow::up`.

The default value `default<E>` is the first variant of `E` with
default fields.  Two values of an enumeration type are equal when they
are the same variant with equal fields.  An enumeration without fields
is exactly today's enumeration and keeps its casts to and from `Field`
and `Uint`, while an enumeration with fields has no casts.  An
enumeration value has no field access and no structure literal: it is
made by naming a variant and taken apart with `match`.

### Matching

A new form, `match`, selects one of several arms according to the
variant of a value and binds the variant's fields.  It is both an
expression, whose arms are expressions separated by commas, and a
statement, whose arms are blocks.  Here is an example of each.

```compact
export circuit callerBytes(): Bytes<32> {
  return match kernel.caller() {
    Some(Contract(c)) => c.bytes,
    Some(User(u))     => u.bytes,
    None              => default<Bytes<32>>,
  };
}

export ledger last: Bytes<32>;

export circuit record(r: ShieldedRecipient): [] {
  match disclose(r) {
    User(pk)       => { last = pk.bytes; }
    Contract(addr) => {
      assert(addr != kernel.self(), "cannot record this contract");
      last = addr.bytes;
    }
  }
}
```

The following productions are added, and `match` becomes a reserved
word:

> _expr_ &rarr; `match` _expr_ `{` _match-arm_ `,` ⋯¹ `,` _match-arm_ `,`<sup>opt</sup> `}`
>
> _stmt_ &rarr; `match` _expr_ `{` _match-block-arm_ ⋯¹ _match-block-arm_ `}`
>
> _match-arm_ &rarr; _mpattern_ `=>` _expr_
>
> _match-block-arm_ &rarr; _mpattern_ `=>` _block_
>
> _mpattern_ &rarr; _id_ | _id_ `(` _mpattern_ `,` ⋯¹ `,` _mpattern_ `,`<sup>opt</sup> `)` | `[` _mpattern_ `,` ⋯ `,` _mpattern_ `,`<sup>opt</sup> `]` | `{` _mpattern-struct-elt_ `,` ⋯ `,` _mpattern-struct-elt_ `,`<sup>opt</sup> `}`
>
> _mpattern-struct-elt_ &rarr; _id_ | _id_ `:` _mpattern_

The value being matched, the **scrutinee**, may have any type except a
ledger state type.  Each pattern is matched against a value of a known
type, starting with the scrutinee:

- `_` matches any value and binds nothing.
- An identifier is a **variant pattern** when the value's type is an
  enumeration with a variant of that name.  It matches that variant,
  which must have no fields.  Any other identifier is a **variable
  pattern**, which matches any value and binds the identifier to it.
- _id_`(`_p_, ⋯`)` matches the variant _id_ when its fields match the
  patterns, one for each field.
- A tuple pattern matches a tuple or a vector element by element.  A
  structure pattern matches the fields that it names and ignores the
  others, and in it _id_ alone abbreviates _id_`:` _id_.

Variant names in patterns are not qualified: the type at a pattern's
position determines the enumeration, so nothing needs to be imported,
and two enumerations may share a variant name.  Patterns look through
type aliases, including nominal ones.  Variant patterns appear only in
`match`, and the patterns of `const` bindings and circuit parameters
are unchanged.

It is a static error if some value of the scrutinee's type matches no
arm, and the compiler reports a pattern for such a value.  It is also
a static error if an arm cannot be reached because earlier arms match
everything that its pattern matches, if a pattern binds a name twice,
or if an arm uses as a variable a name that its pattern uses as a
variant.  Finally, it is a static error if a pattern binds a variable
that its arm does not use, so that a misspelled variant name is
reported rather than silently matching every value.  A pattern that
binds nothing is written `_`.

The types of the arms of a `match` expression are related as the types
of the branches of a conditional expression are: one of them must be a
supertype of all the others, and it is the type of the expression.  In
a `match` statement, each arm is a block, and a `return` in it returns
from the enclosing circuit or constructor, as within an `if`
statement.  The scrutinee is evaluated once, the first arm whose
pattern matches it is selected, and control never falls through to
another arm.

A `match` compiles to tests on the tag and reads of fields, as the
equivalent chain of `if` forms would, so every arm is part of the
circuit, just as both branches of a conditional are.  A ledger
operation in an arm is guarded by the arm's condition, an `assert` in
an arm can fail only when that arm is selected, and the variables of
an arm that is not selected hold valid values of their types.

The tag of an enumeration with three or more variants, like the value
of an enumeration without fields, has room for numbers that name no
variant, such as 3 in an enumeration of three.  Such a value can be
neither constructed nor supplied by the prover, but a ledger cell can
hold one (see Security Implications).  When the last arm of a `match`
on such a value tests the variant, the compiler therefore asserts the
test rather than assuming it, so the `match` fails rather than running
the last arm.  A last arm that is `_` or a variable takes every value,
as written.

### Representation and Validity

Every Compact type has a fixed **layout**: the sequence of primitive
values that represents a value of the type, which is the same in a
circuit, in a ledger cell, and as the input to a hash.  An enumeration
with fields is laid out as its tag followed by its **slots**, each of
which holds one field, whole.  The slots are determined by the
declaration:

1. For each field type, the enumeration has as many slots of that type
   as the variant with the most fields of that type.
2. Each variant's fields, in order, occupy the first slot of their
   type that the variant does not already use.
3. Slots are ordered by first use, reading the variants in declaration
   order.
4. The slots that the current variant does not use hold default
   values.

Fields of the same type in different variants therefore share a slot,
and fields of different types never do.  Field types are compared as
types rather than as they are written, so that the layout of a type
depends only on the type, and a field whose type is an alias is placed
as the type that the alias stands for.  A structure in one variant
does not share a slot with the same values written as separate fields
in another.

The tag is a `Boolean` for an enumeration with two variants, `false`
for the first, and a `Uint` whose largest value is _n_ − 1 for an
enumeration with _n_ > 2 variants.  An enumeration with one variant
has no tag.  Here are some examples, with widths counted in field
elements in a circuit, where a `Bytes<32>` occupies two.

| Type | Tags | Slots, in order | Width |
|---|---|---|---|
| `Maybe<T>` | `None` 0, `Some` 1 | one `T` | as today's structure |
| `Either<Bytes<32>, Bytes<32>>` | `Right` 0, `Left` 1 | one `Bytes<32>` | 3, where today's structure has 5 |
| `Either<Bytes<32>, Field>` | `Right` 0, `Left` 1 | a `Field`, then a `Bytes<32>` | 4, as today's structure |
| `Order` | `Open` 0, `Filled` 1, `Cancelled` 2 | a `Bytes<32>`, then a `Uint<64>` | 4, where a slot for each variant would give 6 |

Because a slot holds a value of one type whatever the tag, an arm that
is not selected still reads values of its fields' types, no read of a
field needs a check, and the layout uses only the primitive types that
exist today.  The order of the slots cannot be observed in the
language.

A value is **valid** when its tag names a variant, the slots that its
variant does not use hold default values, and every enumeration value
within its fields is valid.  Validity matters because `==`, hashing,
and ledger keys see every slot: a value with a stray value in an
unused slot reads as its variant, but it is not equal to the valid
value and it hashes differently.  A value reaches a circuit in five
ways, and each keeps it valid.

1. **The program builds it.**  Construction yields only valid values.
2. **The prover supplies it**, as an argument of an exported circuit
   or of the constructor, as the result of a witness, or as the result
   of a call to another contract.  The compiler asserts validity at
   each of these points.  A tag that names no variant fails the check
   that its type already has, and the assertions that unused slots
   hold defaults are new.
3. **`deserialize` builds it** from bytes, which can be any bytes, and
   the compiler asserts the validity of the result.
4. **An Impact program builds it**, as the kernel's `caller` and a
   `List`'s `head` do.  (Impact is the language of the ledger's
   virtual machine.)  The compiler's definitions of these operations
   build only valid values.
5. **It is read from the ledger.**  Nothing is checked at the read, as
   for every other type today, because a ledger cell holds what a
   proven circuit, the constructor, or the ledger itself wrote.

### The Standard Library and the Kernel

The standard library's `Maybe` and `Either` become enumerations:

```compact
export enum Maybe<T> { None, Some(T) }
export enum Either<L, R> { Right(R), Left(L) }
```

`Maybe` keeps the layout of today's structure, with `is_some` as its
tag and `value` as its one slot.  `Either` does not: its two fields
share a slot when they have the same type, and otherwise the field of
`Right` comes first.  `Either` declares `Right` first so that its tag
still means "is left" and its default value is still a `Right`.
Whether `Either` should instead keep its current bytes is discussed
under Rationale.  The circuits `some`, `none`, `left`, and `right`
remain, as wrappers around the variants, and four new circuits,
`isSome`, `isNone`, `isLeft`, and `isRight`, test which variant a
value is, as in `isSome<Field>(m)`.

The ledger fixes the bytes of three sum types: the tag, followed by
one slot for each variant that has a field, in the reverse of the
order in which the variants are declared.  The language cannot express
that layout, so the compiler declares these types, as it already
declares the ledger's other types.  In every other respect they are
enumerations:

```compact
enum PublicAddress { User(UserAddress), Contract(ContractAddress) }
enum ShieldedRecipient { Contract(ContractAddress), User(ZswapCoinPublicKey) }
enum TokenType { Shielded(Bytes<32>), Unshielded(Bytes<32>), Dust }
```

They replace the `Either`s that stand for them today, with the same
bytes.  `kernel.caller()` returns a `Maybe<PublicAddress>`, and the
kernel's token and coin operations, the native `createZswapOutput`,
the standard library's token circuits, and the recipient fields of the
standard events use these types where they used an `Either`.  The
Impact code of these operations is unchanged, because `Maybe`, the
only enumeration that Impact code builds, keeps its layout: the tag
leads, so `Some(x)` is the constant 1 followed by `x`, the one slot
holds a `T` as the ledger supplies it, and the all-default value is
the valid variant `None`.

### Code Outside Circuits

**Host code.**  An enumeration value crosses to and from host code
(witnesses, the callers of circuits, and readers of the ledger) as its
layout.  How a host language presents such values is a matter for that
language's code generator and is not part of this proposal.  Because
host code acts for the prover, what it passes into a circuit is
checked for validity.  The TypeScript presentation of the reference
implementation is described under Implementation.

**Contract info.**  `contract-info.json` describes an enumeration with
fields by its layout, as a structure of the tag and the slots, and it
also records each variant's name, tag, and field types and the slots
that each field occupies, so that a host can present variants without
the source program.

**Contract calls.**  Enumeration values pass between contracts by
their layouts, and the caller asserts the validity of a result,
because the callee is not trusted.

**The virtual machine.**  Only a circuit can match.  Impact code can
build an enumeration value and compare one with a constant, but it
cannot branch on a tag inside a ledger cell.

### Limitations

Some limitations of this proposal are intrinsic to Compact, some are
deliberate choices, and some are deferred to later proposals.

1. Variants share space only for fields of the same type.  This is a
   choice, which keeps each slot to one type and the layout to four
   rules (see Rejected Ideas).
2. Every arm of a `match` is in the circuit, so a `match` costs the
   sum of its arms.  Doing the arms' common work once, or producing
   one circuit for each variant when the tag is public, is left to
   later work.
3. The ledger's three enumerations keep a slot for each variant,
   because the ledger fixes their bytes.
4. A tagged structure that a program declares today cannot in general
   be redeclared as an enumeration with the same bytes, as `Either`
   shows.
5. Generic arguments are written wherever a generic enumeration's
   variant is constructed, as they are at every generic call today,
   although patterns need none.  Inference of generic arguments is a
   separate proposal, and adding it later breaks nothing.
6. Several features are deferred: `if` with a pattern, literal
   patterns, conditions on arms, variants with named fields, variants
   that only their own module can construct, and methods on
   enumerations.

## Rationale

<!--
Explain the design decisions that were made and the reasons behind them.
-->

The main design decisions, and the reasons for them, are these.

- **Extending `enum`.**  Today's enumeration is exactly a sum type
  whose variants have no fields, so extending it introduces no second
  kind of enumeration.
- **`::` for variants.**  A variant is a name inside a type, whereas
  `.` selects a member of a value.  The draft proposal for first-class
  ledger types already writes `Tr::op(p, …)`.  Unlike Rust, Compact
  needs no second `::` before generic arguments in an expression,
  because it already reads `name<…>` there as generic arguments.
- **Shared slots of one type.**  An enumeration holds one variant at a
  time, but its value travels whole.  Sharing slots among fields of
  the same type costs nothing: no read needs a check, the layout uses
  existing primitive types, and the virtual machine can build it.
- **Whole fields.**  Keeping each field whole means that the layout is
  one rule, that a structure or vector has the same bytes wherever it
  sits, that generated host code and contract info stay the size of
  the declaration, and that an enumeration inside a variant is valid
  to an arm that is not selected.
- **Tags as positions.**  A number that no program can read does not
  belong in a type.
- **No host language in the design.**  A value is defined by its
  layout and by what a circuit can do with it.  A host language
  without sum types adopts a convention for them, and the language
  does not narrow to fit one.
- **Static exhaustiveness.**  Adding a variant to an enumeration
  should break every `match` that did not anticipate it.

### The Encoding of `Either`

`Either` is the only type that has values on chain today and whose
bytes the layout rules change: `Maybe` keeps its bytes under the
rules, the ledger's enumerations keep theirs because the compiler
declares them, and every other enumeration with fields is new.
Whether an existing type should follow the rules or keep its bytes is
a decision for the reviewers of this proposal.  The proposal as
written follows the rules.

Today's structure is laid out as `is_left`, `left`, `right`.  Under
the rules, the field of `Right` comes first, and the field of `Left`
shares its slot when the two have the same type.  `Left(5)` in an
`Either<Uint<8>, Uint<16>>` is therefore `1, 0, 5` where today it is
`1, 5, 0`.  When the two types differ, the two layouts have the same
length and the fields trade places, so a value written under one is
read under the other as a different value whenever each field is also
a valid value of the type that it is read as: `Left(5)` written by an
older contract is, to a newer one, `Left(0)` with a stray 5 in the
slot of `Right`.

Three options were considered.

1. **Follow the rules** (proposed).  `Either` is an ordinary
   enumeration in the library, declared as any program could declare
   it.
2. **Keep the bytes.**  The compiler declares `Either` with the layout
   of the ledger's enumerations, which with `Right` declared first is
   today's structure for every `L` and `R`.
3. **Add a new name.**  `Either` remains a structure, deprecated, and
   the library gains a general-purpose sum beside it.

| | 1. Follow the rules | 2. Keep the bytes | 3. Add a new name |
|---|---|---|---|
| Stored `Either`s and hashes of them, across the change | can be misread without an error | unaffected | unaffected |
| Width when `L` and `R` are the same type | the tag and one of them | the tag and both, as today | as today, until `Either` is removed |
| Problems 2 and 3 of Motivation, for `Either` | removed | removed | remain while the structure does |
| Source changes | field reads become `match` or `isLeft` | as option 1 | none until `Either` is removed |
| Changing course later | adopting option 2 is a second break | adopting option 1 is this break, with more contracts deployed | removing the structure breaks source, never bytes |

For following the rules: the language has one way to lay out an
enumeration, and the library's sum is the one that a programmer would
write.  The types whose bytes matter most to deployed contracts, the
kernel's recipients, addresses, and token types, keep their bytes as
the ledger's enumerations, and 70 of the 84 calls of `left` and
`right` in the repository's Compact sources before this change build
one of them.  The break is also cheapest now, since its cost rises
with every contract deployed.

For keeping the bytes: a value that changes meaning without an error
is the worst way for an incompatibility to appear, and it falls on the
authors who do the ordinary thing, recompiling with the current
compiler and replacing a contract's keys.  How many deployed contracts
store or hash an `Either` is not known, and the extra width is paid
only by an `Either` whose two sides have the same type.  Against it,
the compiler would declare a generic type for which the ledger gives
no reason, and the library's sum would be laid out differently from
every enumeration that a program declares, permanently.  Against a new
name, the library would have two general-purpose sums, one of which
keeps the faults that this proposal removes.

If the rules are followed, three measures limit the damage.  An honest
client already refuses a call between contracts that disagree about
the encoding (see Backwards Compatibility).  The compiler could warn,
for the releases around the change, about a ledger field whose type
contains an `Either`, although this warning is not yet implemented.
And the release notes should say that such values may be misread, not
merely that they are incompatible, and should name the three cases
listed under Backwards Compatibility.

## Backwards Compatibility

<!--
Describe how the proposed solution affects existing systems, applications, and
users.  Is it a breaking change?
-->

This proposal is a breaking change, made at a language version.

`match` becomes a reserved word, and `::` becomes a token.  The new
forms do not parse today, so no existing program changes meaning.
Selecting an element of an enumeration with a dot, as in `Arrow.up`,
becomes a static error, and `compact fixup` rewrites it as
`Arrow::up`.

Calls of `some`, `none`, `left`, and `right` keep compiling.  Reads of
the fields `is_some`, `value`, `is_left`, `left`, and `right`, and
structure literals of `Maybe` and `Either`, stop compiling.  A read of
`.is_some` or `.is_left` becomes a call of `isSome` or `isLeft`, and
the other reads are rewritten with `match`.  A read of `.value` with
no test of `is_some` beside it has no mechanical rewrite, which is the
point of the change.  Where the kernel and the standard library took
an `Either`, a value built with `left` or `right` is rebuilt by naming
its variant:

| Today | Under this proposal |
|---|---|
| `left<ZswapCoinPublicKey, ContractAddress>(pk)` | `ShieldedRecipient::User(pk)` |
| `right<ZswapCoinPublicKey, ContractAddress>(addr)` | `ShieldedRecipient::Contract(addr)` |
| `left<ContractAddress, UserAddress>(addr)` | `PublicAddress::Contract(addr)` |
| `right<ContractAddress, UserAddress>(addr)` | `PublicAddress::User(addr)` |
| `left<Bytes<32>, Bytes<32>>(color)`, as a token type | `TokenType::Unshielded(color)` |
| `right<Bytes<32>, Bytes<32>>(color)`, as a token type | `TokenType::Shielded(color)` |
| `kernel.caller().is_some` | `isSome<PublicAddress>(kernel.caller())` |

The layouts of `Maybe` and of the ledger's three enumerations are
unchanged, so state on chain that holds them remains readable.  A
ledger cell written before the change may hold an invalid `Maybe` if a
contract built one by hand, and it reads as it does today.  The layout
of `Either` changes, as Rationale describes.  A deployed contract is
not affected and need not be recompiled, but three things are affected
wherever code compiled before the change meets code compiled after it:

1. a contract that stores an `Either` and is upgraded in place with
   the newer compiler, which compiles without a diagnostic and reads
   the cells that it already has under the new layout;
2. a call that passes an `Either` between a contract compiled before
   the change and one compiled after it; and
3. a hash or commitment over an `Either` that was computed before the
   change and is recomputed after it.

The client refuses the second.  The other two are not certain to fail:
where `L` and `R` differ in type, the two layouts have the same
length, and one value can be read as another.

Before a cross-contract call, the client compares the signature that
the caller declares with the signature that the callee's module
carries, including the names of the fields of structures.  The
structures that represent these types have new field names (`is_some`
and `value` become `tag` and `s0`, for example), so a call that passes
a `Maybe`, an `Either`, or one of the ledger's three enumerations
between a contract compiled before the change and one compiled after
it is refused, even where the bytes are unchanged.  Both contracts
must be compiled on the same side of the change.

The validity assertions add constraints to every circuit that takes
one of these types from the prover, so the verifier keys of such
circuits change.  Host code that handles any of these types changes
with them, including TypeScript witnesses, circuit callers, ledger
readers, and the runtime's recipient helpers (see Implementation).

## Security Implications

<!--
Analyze the potential security implications of the proposed change.  Are there
any new attack vectors or vulnerabilities introduced?  How will they be
mitigated.
-->

- **Invalid values.**  Today a prover can present a `Maybe` or an
  `Either` whose unused field is arbitrary.  The validity assertions
  remove that possibility for every enumeration, and a token type or
  recipient with both slots filled can no longer be passed to the
  kernel.
- **Ledger reads.**  A circuit trusts a ledger cell to hold what was
  written to it, which is today's rule for every type.  That leaves
  two sources of invalid values: cells written before the change, and
  the initial state, which the deployer chooses, because no circuit
  proves the constructor.  A value with a stray value in an unused
  slot reads as its variant, but it is not equal to the valid value
  and it hashes differently.  A tag that names no variant makes a
  `match` fail.
- **Disclosure.**  A ledger operation in an arm discloses which arm
  ran, as one under an `if` does.  The compiler's analysis of witness
  data follows the tag and each variant's fields as it follows the
  fields of a structure.
- **Arms that are not selected.**  Such an arm reads the present
  variant's slots at its own fields' types, but its assertions and
  ledger operations are guarded and its results discarded, so it can
  neither fail nor reveal anything, as the branch of an `if` that is
  not taken cannot.
- **Two encodings of `Either`.**  Across the change, an honest client
  refuses a call that passes an `Either`, but a stored `Either` and a
  recomputed hash over one are reinterpreted without any error (see
  Backwards Compatibility).

## How to Teach This

<!--
Explain how to teach users, including both new and experienced ones, how to use
the CoIP in their own work.
-->

An enumeration value is exactly one of its variants, and `match` says
what happens for each, as in Rust, Swift, and the ML family.  Two
facts are specific to circuits.  First, every arm is in the circuit,
whichever arm runs, so a `match` costs the sum of its arms.  Second, a
value has room for the fields of every variant at once, except that
fields of the same type in different variants share room, so an
enumeration whose variants hold different types is a wide value.
`Maybe` and `Either` are the natural first examples, and the migration
guide is a table from each field read to the library circuit or
`match` that replaces it.

## Implementation

<!--
Discuss how the proposed change could be implemented.  What parts of the Compact
toolchain or the blockchain environment will need to be modified?  What are the
dependencies, if any?

Provide a link to a reference implementation, if there is one, and describe any
limitations.
-->

The changes to the grammar have already been described in the
Specification section.  The type checker instantiates enumerations as
it instantiates generic structures, types the construction forms and
`match`, resolves the names in patterns, and checks exhaustiveness and
reachability with Maranget's algorithm.  A pass directly after it
compiles each `match` to tests on the tag and reads of fields.  The
analysis of witness data then follows each variant's fields
separately, before the layout is applied, since variants that share a
slot would otherwise look to it like one value.  Finally, one pass
inserts the validity assertions, and the next assigns slots and
rewrites each enumeration with fields as a structure of a tag and
slots.  This is the only implementation of the layout, and it runs
before the compiler produces host code, contract info, and circuits.
The compiler's remaining changes are these.

- **TypeScript.**  A value of an enumeration with fields is presented
  as a union with one member for each variant: `{ tag: 'V' }` for a
  variant without fields, `{ tag: 'V', value: x }` for a variant with
  one field, and `{ tag: 'V', values: [x, y] }` for a variant with
  more.  A `Maybe<T>`, for example, is
  `{ tag: 'None' } | { tag: 'Some', value: T }`.  An exported
  enumeration is exported as its union, with its type parameters.  The
  generated code converts between the union and the layout wherever a
  value crosses, and it rejects any value that is not a member of the
  union, including one written as the representing structure.  The
  runtime's `Recipient` becomes the union for `ShieldedRecipient`.
- **Contract info.**  `contract-info.json` gains an `enums` entry that
  records, for each enumeration with fields that the contract uses,
  its representing structure and each variant's name, tag, field
  types, and slots.
- **The ledger's enumerations.**  They are declared beside the
  ledger's other types, in place of the `Either`s that stand for them
  today, and `UnshieldedRecipient` remains an alias of
  `PublicAddress`.

A reference implementation is in progress on the branch
`JosephDenman/sum-types`.  It has not been reviewed or merged.

## Rejected Ideas

<!--
Describe other ideas that were considered and explain why they were ultimately
not adopted.
-->

Several alternatives to the layout, the syntax, and the overall design
were considered.

### Other Layouts

- **A slot for every variant.**  This is the layout of the ledger's
  own sum types, and it would keep the bytes of `Either`, but a value
  is then as wide as all of its variants together.
- **A tag and room for the largest variant.**  This is narrower when
  variants hold different types, but a slot then holds values of
  different types under different tags.  Every read would need a check
  or a selection, and an arm that is not selected would see values
  that are not of its fields' types.
- **Fields taken apart,** so that variants share room for parts of the
  same primitive type, as GHC's unboxed sums do.  This is narrower
  when a structure in one variant overlaps separate fields in another,
  but the layout then needs a second notion beside the field, a vector
  becomes a slot for each element in host code and contract info, and
  a nested enumeration needs a special case to stay valid in an arm
  that is not selected.  A program that wants the overlap can give
  both variants the same field types.
- **An invalid field value reused as the tag** (a niche).  The virtual
  machine cannot build such a value, and the layout would depend on
  the field's type.

### Other Syntax

- **Tags written in the declaration,** as in
  `Left(A) = 1, Right(B) = 0`.  This puts a number that no program can
  read into a type, which Rust allows only under a `repr` attribute.
- **A dot for variants,** as in `Maybe<Field>.Some(x)`.  No program
  would have to change, but `.` would keep two meanings, as it would
  if both spellings were accepted permanently.
- **A leading dot on variants in patterns,** as in
  `.Some(.Contract(c))`.  This is unambiguous without types, but the
  rule against unused variables already catches the mistake that it
  guards against.
- **`switch` and `case`.**  Both words are reserved, but they promise
  C's statement, with fall-through and no bindings.
- **A test without bindings as syntax,** as in `m is Some`.  This
  reserves a word for what a library circuit already does.

### Other Designs

- **Structure fields that exist only for one tag value.**  These would
  keep every existing field read compiling, and so they would keep the
  unchecked read.
- **A new kind of declaration.**  This would give Compact two kinds of
  enumeration.
- **`new type` as an enumeration with one variant.**  A nominal alias
  keeps the operations of the type that it renames, so two `Feet`
  values can be added, and a wrapper does not.  The nominal alias
  remains the way to declare a distinct kind of number.
- **Checking values read from the ledger.**  This would add
  constraints to every read, for values that only a proven circuit,
  the constructor, or the ledger could have written.

## References

<!--
Link to relevant related work, such as research papers or similar features in
other contexts.
-->

- *The Rust Reference*, the chapters on enumerations and patterns.
- Luc Maranget, *Warnings for Pattern Matching*, Journal of Functional
  Programming, 2007.
- Luc Maranget, *Compiling Pattern Matching to Good Decision Trees*,
  ML Workshop, 2008.
- *GHC User's Guide*, the section on unboxed sums.
- CoIP draft, *First-Class Ledger Types: Shapes, Places, and
  Operations*.

## Acknowledgements

<!--
Acknowledge non-authors who helped with the CoIP.
-->

To be added.

## Copyright

This CoIP is licensed under
[Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## Footnotes

<!--
If necessary, include footnotes in the CoIP text using GitHub's footnote
syntax[^1].  Keep the footnote heading at the bottom of the document.

[^1]: See the [GitHub Markdown guide](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#footnotes).
-->
