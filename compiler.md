# Compact compiler notes

### Testing the compiler

Tests for Compact compiler can be run via the `go` script in
the compiler subdirectory:

```sh
./compiler/go
```

If all of the tests are successful, you should see output that looks
something like this

```
====================== UNIT TESTS ======================
compiling nanopass/nanopass.ss with output to obj/nanopass/nanopass.so
compiling nanopass/nanopass/language.ss with output to obj/nanopass/nanopass/language.so
... additional similar messages ...
\\\\ Starting parse-file.
//// Completed parse-file with 53/53 passing.
\\\\ Starting report-unreachable.
//// Completed report-unreachable with 9/9 passing.
... additional similar messages ...
================== END OF UNIT TESTS ===================
```

Files are recompiled only when necessary due to source-code changes,
so the number of compiling messages may change.
In particular, a run of compiler/go immediately after another run
of compiler/go should produce no compiling messages.
Also, as the compiler and test suite changes, the test groups
and number of tests will change.

If a test fails, the test will be identified in the output by group
and line number along the reason for the failure and the output
actually produced by the test.

### Coverage information

After a run of compiler/go, the directory `coverage` contains a set
of html files, one for each source file.  These display the results
of profiling the source code and are primarily useful now for
determining which parts of the compiler code are exercised by the
tests.  Code shown in grey is not exercised at all.  Code shown in
any other color is exercised (run at least once).  Code without any
coloring at all is unreachable; usually, this is just code that is
commented out but might also include code that is conditionally
omitted or present only in the compile-time environment.

## Compiler structure

The Compact compiler is structured as a series of passes, each of
which has one essential (possibly simple, possibly complex) task
to perform in translating high-level Compact code incrementally into
low-level TypeScript code and proving circuits.
The initial pass (`parse-file`) converts the characters making up
a Compact source file into an intermediate-language program that
almost exactly reflects the source program.
Each of the second and subsequent passes accepts a program in the
intermediate language of the preceding pass and produces a program
in the same or a different intermediate language that is somehow
closer to TypeScript and/or proving circuits.
Each of the two final passes also takes as input the intermediate
language of its predecessor.
The final pass `print-typescript` accepts an intermediate-language
program that is close to TypeScript in structure and generates from
it the executable TypeScript code.
Similarly, the final pass `print-zkir` accepts an
intermediate-language program that is similar in nature to a proving
circuit and generates from it the proving circuits.

Each of the intermediate languages is well-specified via a Nanopass
`define-language/pretty` declaration, all of which be found in
[compiler/langs.ss](./compiler/langs.ss).
The `define-language/pretty` syntax, defined in
[compiler/nanopass-extesnsion.ss](./compiler/nanopass-extesnsion.ss),
extends the `define-language` syntax described in 
[nanopass library](https://github.com/nanopass/nanopass-framework-scheme) 
to incorporate pretty-printer controls within the unparsed representations of
intermediate languages, which makes the test output more consistent, easier
to read, and easier to compare when changes occur.

Using the nanopass library and `define-language/pretty`, an intermediate language's
grammar can either be defined from scratch or built on top of a previously
defined intermediate language. The `language->s-expression` form can be used to print
the full definition of an intermediate language by supplying the intermediate
language name. Occasionally, this is useful for compiler and tooling engineers to see
the full description of intermediate languages that are built on top of other
intermediate languages.

One way to understand roughly *what* the compiler does without
having to understand *how* is to understand the source language and
the final intermediate languages, since *what* the compiler must do
is convert, somehow, the former to an equivalent program in
the latter.
One can understand some of *how* the compiler works by understanding
all of the intermediate languages, since this gives a picture of the
steps the compiler takes in performing the conversion, namely converting
a program in each intermediate language into an equivalent program in
its successor.

A full understanding of *how* the compiler works requires an understanding
of the passes that perform the transformations from each representation
to the next.
The first pass of the compiler, parse-file, is defined in
[compiler/parser.ss](./compiler/parser.ss)
and the remaining passes are defined in
[compiler/frontend-passes.ss](./compiler/frontend-passes.ss),
[compiler/analysis-passes.ss](./compiler/analysis-passes.ss),
[compiler/save-contract-info-passes.ss](./compiler/save-contract-info-passes.ss),
[compiler/typescript-passes.ss](./compiler/typescript-passes.ss),
[compiler/circuit-passes.ss](./compiler/circuit-passes.ss),
and
[compiler/zkir-passes.ss](./compiler/zkir-passes.ss).

As implied by the existence of two final passes, there are actually two
paths through the compiler, one leading from `parse-file` to `print-typescript`
and the other leading from `parse-file` to `print-zkir`.
The two paths share a common set of initial passes (those in frontend-passes.ss
and analysis-passes.ss).
The path from there to `print-typescript` is short, just a couple of passes
including `print-typescript` in typescript-passes.ss.
The other path, to `print-zkir` is longer and more involved and includes the
passes in circuit-passes.ss and zkir-passes.ss.

There is actually a third final pass, `save-contract-info.ss`, that runs after
the front-end and analysis passes.
As its name implies, it saves information about the contract; this information
is consumed solely by later runs of the compiler to support type-checking of
Contract declarations in the implementation of cross-contract calls.

Yet another final pass, `print-Lflattened`, is not run as part of
the compiler proper but rather used only to display in a somewhat
human readable form the output of the circuit passes for debugging
purposes.

The driver for the compiler can be found in [compiler/compactc.ss](./compiler/compactc.ss),
which processes command-line argument and uses entry points in
[compiler/passes.ss](./compiler/passes.ss) to run the passes.

The intermediate languages and passes are described in the remaining sections
of this document.

## Intermediate languages

### Lparser

This language reflects the source language on a one-to-one basis.
Every atomic bit of the program, such as a keyword, identifier, string, number,
operator, comma, or parenthesis, is represented explicitly in the language
grammar by a lexer token.
Each language form and token incorporates a Chez Scheme source object that
identifies the file and range of character positions within the file where the
corresponding source-code form originated.
Programs in the Lparser language might or might not be fully well-formed or
well-typed.

### Lsrc

This language also reflects the source language, though not quite on a one-to-one
basis (there is only one form of return statement, for example) and without all
of the constant terminals.
Each of the remaining terminals is represented not as a token but rather in some
more specific representation as a bytevector, symbol, boolean value, etc.
String expressions in the source language are represented in Lsrc by utf8-encoded
bytevectors and are considered Bytes objects.

### Lnoinclude

This language differs from Lsrc in that the include form is no longer present.

### Lsingleconst

This language differs from Lnoinclude in that the const statement only accepts
a single variable.

### Lnopattern

This language differs from Lsingleconst in that patterns are dropped from
constructor arguments, circuit arguments, const statements, and function arguments.

### Lhoisted

In the earlier languages, local variables can be defined (via `const`) anywhere
within a block.
In Lhoisted, local variables are declared instead at the top of the
block and initialized somewhere within the block via `=`.

### Lexpr

In Lsrc and Lhoisted, the bodies of circuits are formed of statements
and expressions, and values are returned from a circuit explicitly
via `return` forms.
Lexpr has no statements, just expressions.
The body of an Lexpr circuit is an expression,
and the value of the circuit is the value of the expression.
Rather than being declared at the top of each block and initialized
within the block via `=`, local variables are declared and initialized in
Lexpr via `let*`, and references to variables are valid only within the
body of the `let*`.
Local variables are still recorded at the block level so that references
that occur before assignment in the source program can be recognized as
such.

### Lnoandornot

Lnoandornot differs from the preceding language only in that the Boolean
operators `and`, `or`, and `not` are not present.

### Lpreexpend

The Lpreexpand language adds a new form, `define-adt`, to its predecessor.
`define-adt` does not reflect any source-language form but rather the result of
parsing ledger-ADT declarations in
[midnight-onchain-runtime/midnight-ledger.ss](./midnight-onchain-runtime/midnight-ledger.ss)
for use in ledger-field declarations.

### Lexpanded

The Lexpanded language is, for the most part, less complex than the
earlier languages.  In particular:

* module, import, and export declarations are no longer present
* type parameters are no longer present, and
* some defining forms are no longer present but instead exist as types:
  type definitions (as talias),
  structure definitions (tstruct),
  enum-definitions (tenum),
  contract declarations (tcontract),
  and ledger-adt definitions (tadt).

On the other hand, the function position of an Lexpanded function call, `map`
expression, or `fold` expression that does not contain an anonymous `circuit` form
contains an ordered set of possible targets for the function call rather than simply
a single function name.

Furthermore, each function, ledger field, and variable name is represented not by a
symbol but by a single instance of an `id` record, wherever the name appears, and no
variable or function name can be undefined.  Whereas in prior languages, structure
field references and enum element references share a common syntax (the `field-ref`
syntax), Lexpanded represents enum element references using a separate `enum-ref`
syntax.

### Ltypes

The Ltypes language is the first one in which all programs must be well-typed.
Each function parameter, function return value, and local variable has an
explicitly declared type, and the type of any value passed to a function,
returned from a function, or assigned to a local variable must be equivalent
to, i.e., exactly match, the declared type.
For conditional expressions in contexts where the value is actually consumed,
the types of the branches must also match exactly.
The types of every operand of a `tuple` expression must also match exactly.
In contrast with Lexpanded, the function position of each function call, `map`
expression, or `fold` expression that does not contain a `circuit` form
contains a single identifier representing a specific function.
The vector arguments to `map` and `fold` are annotated with the types of these
arguments.
The cast expressions appearing in earlier languages are replaced in Ltypes by
more specific casting expressions such as `safe-cast`, `downcast-unsigned` and `field->bytes`.
The `elt-call` syntax of earlier languages is gone and in its place are the
more specific `ledger-call` and `contract-call` forms.

Equivalence of types is defined exclusively by the following rules:

* A Boolean type is equivalent to another Boolean type.

* A Field type is equivalent to another Field type.

* A Uint type is equivalent to another Uint type if they have the same maximum value.

* A Bytes type is equivalent to another Bytes type with the same length.

* A vector type is equivalent to another vector type with the same length and element type.

* A tuple type is equivalent to another tuple type with the same number of elements
  and equivalent element types, taken in order.

* A vector type A is equivalent to a tuple type B if A has the same length
  as B has elements and A's element type is equivalent to each of B's element
  types.

* A struct type A is equivalent to another struct type B if A and B have the same name,
  A and B have and same number of elements, each element of A has the same
  name as the corresponding element of B, taken in order, and the type of
  each element of A is equivalent to the type of the correpsonding element of
  B, again taken in order.

* An enum type A is equivalent to another enum type B if A and B have the same name,
  A and B have the same number of elements, and each element of A has the same name
  as the corresponding element of B, taken in order.

* An ADT type A is equivalent to another ADT type B if A and B have the same name
  and if each generic argument of A is the same as the corresponding generic
  argument of B, taken in order.  A generic argument is the same as another generic
  argument if they are same natural number or if they are equivalent types.

* A contract A is equivalent to another contract B if A and B have the same name,
  A and B have the same number of circuits, and each circuit of A has a counterpart
  in B and vice versa, taken in any order.  A circuit is a counterpart for another
  if it has the same name, equivalent purity, equivalent argument types, and
  equivalent return types. Two circuits have equivalent purity if both are marked
  pure or neither is marked pure.

* An opaque type A is equivalent to another opaque type B if the two have the
  same name.

* Any non-nominal type alias is transparent with respect to type equivalence.
  That is, if type name A is a non-nominal alias for type T, A is treated as
  if it were T.

Any nominal type alias A for type T is equivalent only to another nominal
type same nominal type alias or
to another nominal type alias where both have the same name and are aliases for
equivalent types.

Note from the foregoing that each vector type has an equivalent tuple-type counterpart.
Specifically, a vector type with declared length `N` and element type `T` is
equivalent not only to any other vector type with declared length `N` and
element type equivalent to `T` but also to any tuple type with `N` fields, each of
which has a type equivalent to `T`.
For example, if expression `e` has type `Uint<16>`, `[e, e, e]` has tuple type
`[Uint<16>, Uint<16>, Uint<16>]`, and this is equivalent to vector type
`Vector<3, Uint<16>>`
Although every vector type corresponds to a tuple type, some tuple types do not
correspond to any vector type.
For example, tuple type `[Uint<16>, Boolean]` has no vector-type counterpart.
The motivation for this correspondence between vector types and (some) tuple types
is that there is only one creation syntax for both, i.e., `[expr, ...].`
The Compact compiler computes a tuple type from this creation syntax but allows it
to be treated as a vector if the types of the subforms are compatible, i.e., all
elements are subtypes of some one of the elements.

### Lnotundeclared

The Lnotundeclared language has no "undeclared" type.

### Loneledger

The Loneledger language has no free-standing ledger declarations and no
free-standing ledger constructor; rather, all are packaged in a single
ledger declaration.

### Lnodca

The Lnodca language differs from Ltypes in that in Lnodca the function
position of an application is a function-name, i.e., cannot be a circuit
form.
The "dca" in Lnodca stands for "direct circuit application".

### Lwithpaths0

In the Lwithpaths0 language, the layout of the public ledger is explicitly
represented in ledger declarations, and each binding is associated with an
explicit sequence of path indices from the head of the ledger to a specific
location within the ledger.

### Lwithpaths

In the Lwithpaths language, path indices are propagated to the `public-ledger`
expressions that perform ledger operations.
Instead of the original chain of ADT operations, each public-ledger form holds
a series of path indices and a single (final) ADT operation.

### Ltypescript

Ltypescript differs from Lnodca in a number of ways that make it closer in
structure to the TypeScript code that the Compact compiler produces.
In particular, it:
* declares the set of exported types at the front of the program,
* introduces type-descriptor names for ledger types,
* segregates witness and external-circuit declarations, and
* reintroduces the statement/expression dichotomy.

### Lposttypescript

Lposttypescript is similar to Lwithpaths but omits various items not needed for
circuit construction: the ledger constructor, external type definition forms, ADT runtime
ops, type aliases, and elt-ref indices.

### Lnoenums

The Lnoenums language differs from Lnodca in that enum
types and element references are not present.

### Lunrolled

The Lunrolled language differs from Lnoenums in that:

* `map` and `fold` are not present,
* the function position of a call always contains a single identifier, never
  a `circuit` form, and
* a new `flet` expression can be used to bind an identifier to a circuit
  within the body of the `flet`.

### Linlined

The Linlined language is like Lunrolled except that Linlined does
not include `flet`.

### Lnosafecast

This language differs from Linlined in that it does not have `safe-cast` expressions.

### Lnovectorref

This language differs from Lnosafecast in that it does not have `vector-ref`
`tuple-slice`, `bytes-slice`, and `vector-slice` expressions.

### Lcircuit

The Lcircuit language differs from earlier languages primarily in
the following ways:

* the subform expressions of every expression are trivial, i.e., either
  identifier references or constants (i.e., Booleans, Fields,
  or bytevectors);
* circuit bodies consist of a sequence of statements in one of two forms
  (assignment and `assert` statements) followed by a single trivial expression
  representing the return value;
* the `assignment statement` of Lcircuit replaces the `let*` expression,
  and the `assert` statement replaces the `assert` expression.
* the right-hand side of an assignment statement is the only place where a
  non-trivial expression (e.g., a function call, tuple/vector reference, `new`
  expression, or arithmetic expression) can appear;
  and
* function calls are *conditional*; that is, the function call syntax
  takes an additional boolean-typed trivial argument that determines
  whether the function call should be made or not.

A less important change is that the `if` expression is replaced by a
`select` expression in Lcircuit to emphasize that there is no short-circuiting,
or, rather, that short-circuiting is irrelevant because the arguments to a
`select` expression are all trivial.
Each `select` expressions is annotated with a flag that says whether its
value is a Boolean value.

### Lflattened

The Lflattened language is the final language of the Compact compiler.
It differs from Lcircuit in that (a) all values and types are Fields and
(b) functions can return zero or more rather than exactly one value.

Because all values and types are Fields, Lflattened has no tuple/vector or
struct creation or reference forms.

The Lflattened Field type can be declared simply as `(tfield)`, in
which case the corresponding value can take on any natural number
not greater than the maximum field value,
as `(tfield n)`, in which case the corresponding value can take on
any natural number not greater than n, or as
`(tbytes n)`, where n is a nonnegative integer less than or equal to the
number of bytes in a Field, in which case the corresponding value can
take on any natural number that fits in n bytes, i.e., not greater than
256^n.

## Passes

For most of the passes in the Compact compiler, the pass's responsibility
is to transform a given program in its input language into an
equivalent program in its output language.
In some cases, such a transformation is impossible, i.e., an
equivalent program in the output language does not exist because
the input language is more permissive, e.g., of unbound identifiers
or ill-typedness.
In these cases, the pass's responsibility is instead to produce a
comprehensible error message that identifies the relevant portion
or portions of the source code and the problem that prevents the
transformation from occurring.

For one of the passes, `optimize-circuit`,
the goal of the pass is to transform a given program in the input
language into an equivalent but smaller and/or more efficient program
in the same language.
Such passes are labeled "optimization" passes by tradition, although they
might not actually produce an optimal output program.
Indeed, an optimal program might not even exist.

Some of the passes, e.g., `report-unreachable`, `reject-duplicate-bindings`,
and `check-sealed-fields`,
transform a given program in the input language into *the same*
program in the output language, but produce an error message if the
input program is not well-formed.
These are used to check requirements of the source program that are
not reflected explicitly in the intermediate language structure.
One pass, `identify-pure-circuits`, falls into this category but also
has a side effect, namely setting the `pure` flag on the id records
representing the names of pure circuits.

Some of passes, e.g., `check-types/Linlined` and `check-types/Lflattened`,
do the same thing but to verify that earlier passes have maintained
well-typedness as well as other correctness properties.
The latter category of passes can be disabled without affecting the
compiler's output, assuming correct operation of the remaining
passes.

The final passes (`print-typescript`, `print-zkir`, `save-contract-info`,
and `print-Lflattened`) also take an input program and produce some sort
of output, but the output is not another intermediate language but rather
some final product of the compiler.

### parse-file (Source file -> Lsrc)

`parse-file` is the first pass of the Compact compiler.
It is responsible for reading the contents of a source file and
converting it into an equivalent program in the `Lsrc` language.
Like most language parsers, parse-file converts the sequence of
characters in the source file into a sequence of tokens, then groups
those tokens into the recursive structure implied by the nested
source-language forms of the source program.

The conversion of character sequences into token sequences is
performed by a hand-coded lexical analyzer (lexer), defined in:
[compiler/lexer.ss](./compiler/lexer.ss).

The tokens produced by the lexer are atomic program elements such
as identifiers, numbers, and punctuation.
The forms produced by the parser from the tokens are structured
program elements such as circuit definitions, operator applications,
and `if` expressions.

Each `token` is represented by a record that contains:
* a type, such as `id` for identifier,
* a value, such as a symbol representing the identifier's name,
* a source object representing the file and range of positions occupied
  by the token,
* a string representing the sequence of characters that comprise the
  token.
Token types are used by the parser to determine the structure of
the input, and token values either are used to further disambiguate
the structure or become terminals in the Lsrc output program.
Source objects are used to identify the span of characters occupied by each
source-language form for compile-time error messages, run-time debugging,
and profiling.

The parser is generated from a high-level specification via the
[ez-grammar package](./compiler/ez-grammar.ss)
written by Jon Rossie and Kent Dybvig.
It produces output in the `Lparser` language and converts this to
the `Lsrc` language via a helper pass `lsrc-to-lparser`.
The [Compact formatter](./compiler/format-compact.ss) uses the
alternative parser entry point `parse-file/token-stream` to obtain the
`Lparser` output and token stream.

### resolve-includes (Lsrc -> Lnoinclude)

This pass replaces `include` forms with the code from the included file.
The original `include` form also appears in the output and is eventually
consumed by `print-zkir`.

### expand-const (Lnoinclude -> Lsingleconst)

This pass expands a const statement with multiple variables into a sequence
of const statements with a single variable.

### expand-patterns (Lsingleconst -> Lnopattern)

This pass expands the patterns. A pattern is a variable, a tuple, or a struct. 
Patterns are used in arguments for constructors, circuits, functions, and const
statements.

### report-unreachable (Lnopattern -> Lnopattern)

This pass accepts a program in the Lsrc language and returns the
same program, also of course in the Lsrc language.
Its only purpose is to detect and report unreachable statements;
otherwise, it is merely the identity function for Lsrc programs.
Reporting unreachable statements gives useful feedback to the
programmer and is done early to allow subsequent passes to discard
the unreachable code.

The source code for the pass is short since it needs to deal only
with the statements in the body of a circuit definition.
It processes these statements from left-to-right and maintains an
"unreachable" flag that starts out true and becomes false only if
all paths through to a statement go through return statements.

### hoist-local-variables (Lnopattern -> Lhoisted)

This pass records the set of local variables (and their types, if
declared) declared by `const` statements contained directly within
a block in the Lhoisted language record for the block.
It detects and reports any duplicates among the variables declared
directly within each block e.g.:
```
circuit foo() : Field { const q = 10; const q = 11; return q; }
```
It also replaces the `const` forms with simple assignment forms.

The source code of this pass is short because it needs to deal
mostly with only `block` and `const` forms.
It is slightly complicated, however, because it enforces the
JavaScript/TypeScript restriction against assignment appearing in
so-called "single statement contexts", e.g., the branches of an
`if` statement:
```
circuit foo() : Field {
  if (true) const q = 10;
  return q;
}
```
It handles this with a pair of mutually recursive processors for
handling single statements and block statements along with a helper
for handling statements that are permitted in either context.

### reject-duplicate-bindings (Lhoisted -> Lhoisted)

As its name implies, the responsibility of this pass is to detect
and report multiple bindings for the same name in the same scope.
This applies to:

* type arguments for modules, functions, and structs
```text
struct S<A, A> {}
```
* parameter names within a function declaration or definition
```text
circuit C(x: Boolean, x: Field) : Boolean { return x; }
circuit C() : Uint<32> { const x = 5; const x = 6; return x; }
```
* field names within a struct definition
```text
struct S { x: Field, x: Field }
```
* element names within an enum definition
```text
enum names { bill, sally, fred, george }
```
Otherwise, this pass behaves as an identity function for programs
in Lhoisted language.

Duplicate local-variable bindings are detected by `hoist-local-variables`.
Duplicates among the bindings for module names, function names,
struct names, and enum names are detected by `expand-modules-and-types`.

### eliminate-statements (Lhoisted -> Lexpr)

This pass converts statements to expressions.
In particular, it:
* eliminates assignment (`=`) statements in favor of nested `let*` bindings e.g.:
```text
const ab1 : Boolean = a && b;
const ab2 : Boolean = a || b;
return ab1 || ab2;
```
becomes:
```scheme
(let* ([(ab1 (tboolean)) (and a b)])
  (let* ([(ab2 (tboolean)) (or a b)]) (if ab1 a ab2)))
```
* eliminates `return` statements by arranging to place the return
  expression in tail position with respect to the enclosing circuit body;
* recasts ledger field assignments (`=`, `+=`, `-=`), `assert`, `if`, and `block`
as expression equivalents.
For example:
```text
if (a) return !b || b ;
return a;
```
becomes:
```scheme
(if a (or (not b) b) a)
```

To support both the conversion of assignments to `let*` bindings and
placement of return forms in tail position, the pass processes
the statements of a block in reverse order, i.e., from
right to left, and the processor `Statement` that handles each
statement takes as an extra argument `tail`, which is a list of
processed statements to the right of the current statement.
`Statement` returns a new tail that includes the residual expression
produced from the current statement at its head.

When handling a `return` statement, `Statement` simply discards the tail and
returns a new tail containing only the expression subform of the `return`
statement.

For an `if` statement, `Statement` processes the branches with the same
input tail.
This would lead to duplication of the expressions in the tail,
except that `Statement` identifies the common tail, if any, of the
resulting branch tails, leaves it out of the branches of the 
residual `if` expression, and returns the result of adding the
residual `if` expression to the front of the common tail.

There will not be a common tail if either branch contains a `return`
statement, and despite this pass's efforts to avoid it, code duplication is
inevitable in some cases where `return` statements appear along only
one path through nested `if` expressions.
Fortunately, some of this duplication is eliminated by circuit optimization
later in the compiler.

Statement maintains a stack of block-ending tails,
which it uses when processing nested `block` statements to determine which portion
of the tail belongs to each block.
The common tail, if any, of the new tail resulting
from processing the statements in the block and the block-ending tail
is considered outside of the block.

Statement converts each assignment statement into a `let*` expression,
including in the body of the `let*` that portion of the tail that
originated from statements in the immediately enclosing block, which
it determines using the same stack of block-ending tails as is used
to handle `block` statements.

The tail from which a `let*` body is derived naturally excludes expressions
resulting from statements that precede the assignment in the block, thus
references to the assigned variable might fall outside of the `let*` body.
Per the local-variable scoping rules adopted from JavaScript/TypeScript,
these are always invalid references.
That is, while all variables declared with `const` are visible throughout
the enclosing block, references that occur before the `const` form has been
reached in the left-to-right evaluation of the statements of a block are
considered invalid.
The full set of variables declared immediately within a block is still
recorded in the residual block e.g.:
```text
{ const ab1 : Boolean = a && b;
  const ab2 : Boolean = a || b;
  if (ab1) return a;
  return ab2; }
```
becomes:
```scheme
(block
  (ab1 ab2)
  (let* ([(ab1 (tboolean)) (and a b)])
    (let* ([(ab2 (tboolean)) (or a b)]) (if ab1 a ab2))))
```

Thanks to that, invalid references can be
detected and reported as such in a downstream pass, namely
`expand-modules-and-types`.

### eliminate-boolean-connectives (Lexpr -> Lnoandornot)

This pass replaces `and`, `or`, and `not` expressions:
```text
a && b
a || b
!a
```
with equivalent `if` expressions:
```scheme
(if a b '#f)
(if a '#t b)
(if a '#f '#t)
```
This reduces the number of forms that downstream
passes must handle and simultaneously ensure that downstream passes
treat equivalent forms of expressing these operations identically.

### prepare-for-expand (Lnoandornot -> Lpreexpand)

This pass converts an Landornot program into an identical Lpreexpand.
program, merely because the next pass, `expand-modules-and-types`, needs
to be able to inject `define-adt` forms representing ledger-ADT
definitions into the standard-library module it creates, and this form
is not present in Lnoandornot. 

### expand-modules-and-types (Lpreexpand -> Lexpanded)

This pass is responsible for handling modules and imports, expanding
type-parameterized elements into ones with explicit types, connecting
identifier references to their bindings, verifying a number of
properties related to these tasks, and reporting errors when such
verification fails.  This is quite a lot of responsibility for one pass,
but the tasks are interdependent.

Some of its specific tasks are illustrated below:
* resolving identifier bindings, e.g.:
```text
circuit foo(a: Boolean) : Boolean { return a; }
```
```scheme
(circuit %foo.1 ((%a.2 (tboolean))) (tboolean)
  %a.2)
```
* expanding away module and import forms, e.g.:
```text
module M {
  export circuit foo(n: Field): Field { return n; }
}
import M;
circuit bar(m: Field): Field { return foo(m); }
```
```scheme
(circuit %foo.0 ((%n.3 (tfield))) (tfield)
  %n.3)
(circuit %bar.1 ((%m.2 (tfield))) (tfield)
  (call (fref ((%foo.0))) %m.2))
```
* resolving generic parameter references to the corresponding type
  and size arguments, e.g.:
```text
module M<T, N> {
  export ledger F: MerkleTree<N, T>;
}
import M<Field, 3>;
```
```scheme
(public-ledger-declaration %F.1 (MerkleTree 3 (tfield)))))
```
* resolving type references to fully expanded types, e.g.:
```text
enum E { red, green }
struct A { x: E }
circuit foo(a: A) : E { return a.x; }
```
```scheme
(circuit %foo.0 ((%a.1 (tstruct A (x (tenum E red green)))))
  (tfield)
  (elt-ref %a.1 x))
```
* detecting and reporting unbound identifiers, e.g.:
```text
circuit foo(b: Boolean) : Boolean { return a; }
```
```text
Exception: unbound identifier a at testfile.cp line 1, char 44
```
* detecting and reporting misused identifiers such as a struct name
used where an ordinary variable is expected
or an ordinary variable used where a type variable is expected, e.g.:
```text
struct A { x: Field }
circuit foo(a: A) : Field { return A; }
```
```text
Exception: invalid context for reference to struct name A at testfile.cp line 2, char 36
```
* detecting and reporting if a ledger constructor is declared within a module, e.g.:
```text
module M {
  ledger fld: Set<Field>;
  constructor() { fld.insert(75); }
}
```
```text
Exception: misplaced constructor: should appear only at the top level of a program
```
* replacing external contract type names with expanded contract types,, e.g.:
```text
contract C {
  circuit foo(x: Bytes<32>): [];
  pure circuit barr(): Bytes<32>;
}
ledger contract_c: C;
```
```scheme
(public-ledger-declaration %contract_c.1
  (Cell (tcontract C
          (foo ((tbytes 32)) (ttuple))
          (barr () (tbytes 32)))))
```
and
* detecting and reporting cycles involving types and/or modules, e.g.:
```text
module M1 {
  import M2;
}
module M2 {
  import M1;
}
import M1;
```
```scheme
Exception: cycle involving modules M2 and M1
```

The pass operates in two phases. The first loops through the elements of the
top-level program and of any imported modules, incrementally building up a set of
environments (nested to reflect lexical scoping structure) that map names of program
and module elements to "Info records", which are described below.  Type references
are resolved during this phase only to the extent necessary to determine the actual
generic values by which imported modules are instantiated.

The second phase processes circuits, starting with the exported circuits and
eventually processing any non-exported circuits that are reachable, directly or
indirectly, from the exported ones.  This gives rise to additional environments and
other kinds of Info records to represent variables.  Type references are resolved as
needed, e.g., within the generic parameter values of reachable functions, within
function argument and return types, or within the declared types of local variables
declared via `const` forms.

As noted, type references are processed on demand during both phases.  This allows
program elements to contain forward references to later program elements, with the
restriction that it must be possible to process module imports as they are seen
during the top-to-bottom (left-to-right) traversal of the program and module bodies.
This means the module declaration, if present in the program text, must have already
been seen and also that any struct, enum, contract, or ledger definitions whose names
are referenced in types used as generic parameters at the point of import must
already have been seen.

(This pass could work harder to avoid complaints about references to things that are
defined below where they are needed.  In particular, we could split the first phase
into two separate phases, the first handling everything but imports and the second
handling imports.  This would allow more programs to pass, but it would also result
in non-obvious successes and even less obvious failures.  We choose instead to stick
with a simple model in which a program must define modules and types above where they
are required by an `import` form.)

Each Info record provides the information necessary to process references to a
particular kind of binding.  The following Info records are produced from the
corresponding top-level and module-level defintions:

* Info-module -> type parameters + program elements + environment + ...
* Info-functions -> list of { type-parameters + program-element + environment + ... }
* Info-struct -> struct name + type params + field-names + field-types + environment
* Info-enum -> enum name + element name + element names
* Info-ledger-ADT -> adt name -> type parameters + vm-expr + adt-ops + ...
* Info-contract -> contract name + circuit names + ...
* Info-ledger -> id

These Info records are produced for the values of generic parameters:

* Info-type -> Lexpanded type
* Info-size -> nat

And these are produced to represent variable bindings:

* Info-var -> id
* Info-bogus

Info-var represents a variable that is in the scope of its definition, while
Info-bogus represents a variable that is outside of the scope.  The latter is used to
detect references to a local variable that occur before the `const` binding for that
variable.

The end result of the first and second phases is a new set of program elements in the
Lexpanded language.  This set might have fewer program elements than the incoming set
(for example, module forms, import forms, export forms, and some unreachable function
definitions will be missing), and it might have more (arising from replication of function
and ledger bindings due to multiple generic parameterizations).

The two phases together construct a worklist of the input-language forms that are to
be processed into output-language forms.  Each element of the worklist is a record
containing the program element and environment of its definition.  We arbitrarily
refer to these records as "frobs" and to the worklist as the "frob worklist".
Processing the frob worklist is the primary job of the second phase of this pass.
Frobs are not processed during the first phase because the forms contained within
them might refer to definitions that have not yet been processed.

Frobs are created during the first phase for ledger field definitions and for the
ledger constructor, if any.  Additional frobs are created during the second phase
for functions (cicuits, witnesses, and externals).

#### The first phase

During the first phase, the compiler processes the forms in the program in order from
top to bottom (left to right) and handles each kind of program element as follows:

* For module, struct, enum, contract, and ADT definitions, it creates a new Info
  record for the definition and adds to the current environment a binding for the
  name of the module, struct, enum, or ADT to the Info record.

  In addition to information about the definition itself, the Info record contains a
  reference to the current environment so that the identifiers found within the
  definition can properly be found in the environment of definition rather than the
  environment of use.  This is similar to how and why expand-time environments are
  encapsulated within syntax objects and run-time environments are encapsulated
  within procedure values to maintain scoping in languages like Scheme with lexically
  scoped syntactic extensions and first-class procedures.

* For an import form `import M` or `import M<gp, ...>`, the compiler performs the
  following steps:

  1. It finds the relevant Info structure for `M`, which is itself potentially a
     multi-step process:

     1a. If `M` is a symbol (rather than a string representing a pathname), it looks
         first for `M` in the current environment. If it finds a binding for `M` to an
         Info-module record `R`, it proceeds to step 2 with `R`.  If it finds a binding
         for `M` to some other Info record, it complains.  Otherwise it proceeds to
         step 1b.

     1b. If `M` is the name of the standard library, either (1) an Info-module
         record `R` for the standard library has already been created, in which case the
         compiler proceeds to step 2 with `R`, or (2) it creates an Info-module record
         `R` for the standard library from precompiled Lpreexpand records produced by
         running the preceding passes on the contents of
         [standard-library.ss](./compiler/standard-library.ss) and precompiled
         Lpreexpand records (specifically `define-adt` forms) produced by syntactic
         abstractions in [ledger.ss](./compiler/ledger.ss) from the ADT descriptions
         in [midnight-ledger.ss](./compiler/midnight-ledger.ss) and proceeds to step
         2 with `R`.  If `M` is not the name of the standard library, the compiler
         proceeds with step 1c.

     1c. The compiler looks for `M.compact` in the filesystem (whether `M` is a symbol
         or a string) first relative to the directory of the importing file and
         second relative to the directories in `COMPACT_PATH`.  If it finds `M.compact`
         at some path `P`, either (1) an Info record `R` for `P` already exists, in which
         case it proceeds to step 2 with `R`, or (2) it creates an Info record `R` for `P`
         (by running all of the previous passes on the contents of the file and
         processing the resulting module form) and proceeds to step 2 with `R`.

     Otherwise it complains that `M` cannot be found.  The compiler might also
     complain, of course, if the file at path `P` does not contain a well-formed
     module.

  2. The compiler processes the generic parameters `gp, ...`, if any, to
     produce a (possibly empty) list of generic values `gv, ...` (each an Info-type or
     Info-size record).  If an instance `I` of module `M` has already been created for
     `gp, ...`, it proceeds to step 3 with `I`.  If not, it creates an instance `I` of `M`
     parameterized by `gv, ...`  by processing the forms of `M` (recorded in `R`) in the
     environment of `M`'s definition (also recorded in `R`) extended with bindings for
     each of `M`'s type parameters, `gp, ...`, to the corresponding element of `gv, ...`,
     and it proceeds to step 3 with `I`.

  3. The instance `I` of `M` is a set of bindings for the exported names of `M` to
     Info records resulting from processing the forms in `M`.  The compiler adds these
     bindings to the current environment, effectively making the exported bindings of
     `M` visible in the scope of the import.

     While only the exported bindings are present in the instance `I`, the unexported
     bindings are not lost.  They are present, along with the exported bindings,
     the extended environment, which is encapsulated within the Info records created
     for each of the forms within the module.

     Of course, the compiler might complain if the number or kind of provided generic
     values does not match the generic parameters of `M` or if some issue is found
     while processing the forms of `M`.

* When the first phase encounters an export form `export { name, ... }`, the compiler
  adds `name, ...` to the set of names to be exported from the enclosing module or from
  the top level, if the `export` form appears outside of any module.  `export`
  prefixes on definitions have the same effect for the defined names.  At the end of
  this phase, the set of names collected in this manner determines the exports of the
  program or module.  Multiple exports of the same name for the same binding are treated
  as one, but multiple exports of different names to the same binding result in the
  binding being exported via more than one name.

* For the definition of a function (circuit, external circuit, or witness)
  named `F`, the first phase:
 
  - creates an id record for `F`, which provides uniqueness in case the
    names of two bindings have the same symbolic name in the same or
    different scopes,

  - creates an info-fun record containing unprocessesed function
    definition, the current environment, and other information (such as
    type-parameter names) required to consume the defined function.

  - looks for an existing binding for `F` in topmost level of the current
    environment, and

  - either (a) finds no binding for `F` there, in which case it adds to
    the environment a binding from `F` to a new Info-functions record
    containing the single info-fun record just created, (b) finds a binding
    for `F` to an existing Info-functions record, in which case it replaces
    the binding with a new binding from `F` to an Info-functions record
    containing the new info-fun record plus those that existed within the
    original Info-functions record, or (c) finds some other binding for `F`,
    in which case it complains.

  Nothing else is done with function definitions until the second phase.

* For a ledger field definition for a field named `F`, the first phase:

  - creates an id record for `F`, which provides uniqueness in case the
    names of two bindings have the same symbolic name in the same or
    different scopes,

  - creates an Info-ledger record `R` containing id and adds to the current
    environment a binding of `F` to `R`, and

  - adds a "frob" record containing the definition, the id, and the current
    environment to the frob worklist.

* For the definition of a ledger constructor, the first phase simply:

  - adds a frob containing the program element and the current environment to the
    frob worklist.

#### The second phase

In the second phase, the pass processes the frobs to produce the final output of
the pass, while:

* detecting unbound identifiers;
* detecting misused identifiers, such as struct names used as ordinary variables
  or ordinary variables used as type variables;
* detecting attempts to export two circuits with the same name from the
  top level of the program;
* replacing symbolic names for scoped identifiers with unique id records;
* setting the pure field of an id record for circuits that have been declared
  pure by the programmer;
* replacing type-variable names with the corresponding type;
* replacing type-size names with the corresponding sizes;
* replacing struct names with struct types;
* replacing external contract type names with expanded contract types;
* replacing field-refs with enum-refs when the base expr is a type-variable
  reference with type tenum;
  and
* determining and recording the set of (possibly multiple due to overloading)
  candidate function definitions at each call site.

The second phase begins by creating frobs for each of the circuits exported from the
top level of the program.  It proceeds by processing the elements of the worklist,
which might continue to grow as calls to non-exported functions are encountered during the
processing of exported functions, until the worklist is empty.  The resulting
program elements form the main part of the ouptut-language program.

A frob is processed as follows:

* For a frob containing a ledger-field definition `ledger F: T`, the compiler
  proceses `T` in the frob's environment to produce an Lexpanded type.  If this type
  is not an ADT type, it wraps the type in a Cell ADT type.  In either case, it
  records the ADT type in the resulting Lexpanded ledger-field definition.

* For a frob containing a constructor definition `constructor((x: T) ...) expr`, the
  compiler processes each argument-type `T` in the frob's environment, creates a new
  id for each `x`, and processes the body `expr` in the frob's environment extended
  with bindings for each `x` to an Info-var record containing the corresponding `id`.
  It records the resulting ids, types, and expr in the resulting Lexpanded constructor
  definition.

* For a frob containing a circuit definition `circuit((x: T) ...): T^ expr`, the
  compiler processes each argument-type `T` and the result type `T^` in the frob's
  environment, creates a new id for each `x`, and processes the body `expr` in
  the frob's environment extended with bindings for each `x` to an Info-var record
  containing the corresponding `id`.  It records the resulting ids, types, and expr
  in the resulting Lexpanded circuit definition.

* For witnesses and externals, the compiler processes the argument and return types
  and records them in the resulting Lexpanded witness and external definitions.

Processing expressions is mostly straightforward.  The interesting cases are
described below:

* For a `let*` expression `let* ((x: T) ...) expr`, the compiler processes the
  types `T` in the current environment, creates a new id for each `x`, and processes
  the body `expr` in the current environment extended with bindings for each `x`
  to an Info-var record containing the corresponding `id`.  It records the
  resulting ids, types, ane expr in the resulting Lexpanded `let*` form.

* For a variable reference `x`, the compiler looks for the closest binding of `x`
  in the environment.  If there is no such binding or it is to something other than
  an Info-var record, the compiler complains.  Otherwise it includes a reference
  to the Info-var's id record in the resulting Lexpanded var-ref form.

* For a call to a named function `F`, the compiler must determine the set of
  candidate functions in support of function overloading.  Determining which
  of the candidates should be the actual target of a call requires type inference,
  which is done by a subsequent pass, `infer-types`.

  Determining the set of candidate function definitions at a function call to F
  involves searching the entire environment, from innermost to outermost levels of
  nesting, collecting all of the function bindings for F, stopping only at
  the bottom of the environment or a non-function binding for F.  If this search turns
  up no function bindings for F, the compiler complains.  Otherwise, the compiler
  processes each of the resulting candidates as follows:

  1. If a call to the candidate with the same generic values has already been
     encountered, it records the id created during the previous encounter as a
     representative of the candidate in the output-language call syntax.

  2. Otherwise, if the generic values and kinds supplied by the call are compatible
     with the candidate's declared generic parameters, the compiler extends the
     current environment with the candidate's generic parameters bound to the call's
     generic values; adds a frob containing the candidate's definition, id, and the
     extended environment to the frob worklist; and records the id as a
     representative of the candidate in the output-language call syntax.

  3. Otherwise, it records the failure separately in the output-language call syntax
     for use by `infer-types` in reporting rejected candidates in the event that
     `infer-types` does not find any suitable candidates.

Processing types is mostly straightforward, the only complication being the
subtitution of type references with or without type arguments with actual types.
When handling a reference to a named type `A` or named type `A` with generic
arguments `A<ga, ...>`, the compiler first processes the generic arguments in the
current environment to produce (a possibly empty list of) generic values gv, ...,
then looks `A` up in the current environment.
If `A` resolves to something other than a type, the compiler complains.
Otherwise, it handles the different types as follows:

* For a struct `S<gp, ...> { x: T, ... }`, the number and kind of generic arguments
  `ga, ...`, must match `gp, ...`, and `A<ga, ...>` resolves to `tstruct<S, x: T, ...>`,
  where each `T` in the output is the result of processing the corresponding type `T`
  in the input.

* For an enum `E { x, ... }`, `gv, ...` must be empty, and `A` resolves to
  `tenum<x, ...>`.

* For a contract `C { f(x: T, ...): T^, ... }`, `gv, ...` must be empty, and `A`
  resolves to `tcontract<f, (x: T, ...), T^>` where each `T` and `T^` in the output
  is the result of processing the corresponding type `T` or `T^` in the input.

* For a ledger ADT `D<gp, ...>(op, ...)`, the number and kind of generic arguments `ga, ...`,
  must match `gp, ...`, and `A<ga, ...>` resolves to `public-adt<D, op, ...>`, where
  each `op` is the output is the result of replacing the argument and return types in
  the input `op` with the processed types.

* For all other types `T`, `gv, ...`, must be empty, and `A` resolves to `T`.

### Well, that's not quite the whole story

Although program elements are produced on demand via processing of the frob worklist,
this pass is designed to produce output with the functions appearing
in the same order as they appear in the source code.
This is accomplished by associating each Info-module and info-fun record with a sequence
number (a real number represented as a list of digits) corresponding to the position of
the module or function in the source code.
This order-conformity provides stability for comparing test outputs and makes it easier
to read the code.

To provide additional feedback to the programmer, the second phase also processes
uninstantiated modules and unreferenced functions without generic parameters to
detect any binding errors in them.  The resulting functions are passed to infer-types
(specially marked as unused) so that it can check for type errors in these functions.
It is generally impossible to type-check a module or function with generic parameters
when the generic values are not known, so this can leave some things unchecked.

Also, struct and enum definitions exported from the top level of the program also
appear in the output for eventual use by `print-typescript` in producing equivalent
TypeScript definitions.  These type definitions contain type variable references that
will become TypeScript type variables, but references to sizes, which TypeScript
doesn't recognize, are dropped.

### generate-contract-ht (Lexpanded -> Lexpanded)

This pass generates a hashtable mapping contract names to `contract-info.json`,
where the contract names are the name of the contract `C`, being compiled and
the names of all the contract type declarations in `C`. We refer to contracts
that are declared via a contract type declaration in contract `C` as
constracts `C` depends on. This hashtable is
accessed in:
- `infer-type` pass to type check the circuits of a contract implementation
  and its declaration,
- `prepare-for-typescript` pass to gather the name of witnesses declared in
  contract `C` and witnesses of all the contracts it depends on directly and
  indirectly. That is, imagine contract `C` depends on contract `B` and
  contract `B` depends on contract `A`. When compiling `C`, this pass collects
  the witness from `C`, `B`, and `A`. These witnesses are used in the generated
  TypeScript code.


### infer-types (Lexpanded -> Ltypes)

This pass infers the types of all expressions within the body of a
circuit definition from the types of the input parameters, the types
of constants, and the return types of operators, statements, witnesses,
and other circuits.
It uses this information:
* to determine types for local variables whose types were not declared;
```text
circuit foo(a: Boolean) : Field { const x = 7; if (a) return x+1; return x-1; }
```
```text
(circuit foo ((a (tboolean))) (tfield)
(let* ([(x (tfield)) '7])
  (if a (+ x '1) (- x '1))))
```
* to verify that the types of other local variables are assigned values
  that are subtypes of their declared types;
* to verify that statements, witnesses, and other circuits are passed
  only values that are subtypes of their declared argument types;
* to verify that the types of each operator's arguments are appropriate
  for the operator; and
* to verify that the value returned by the body of a circuit
  definition is a subtype of the declared return type;
```text
circuit foo(a: Field, b: Field) : Field { return a * b; }
circuit bar(x: Field) : Field { return foo(x-1, x+1); }
```
```scheme
(circuit %foo.0 ((%a.2 (tfield)) (%b.3 (tfield))) (tfield)
  (* %a.2 %b.3))
(circuit %bar.1 ((%x.4 (tfield))) (tfield)
  (call %foo.0 (- %x.4 '1) (+ %x.4 '1)))
```
* to verify that enum-ref element names and field-ref field names are
  valid for the type of enum or struct;
  and
* to select from the candidate function definitions at each function
  call site the closest enclosing function for which the argument
  types are subtypes of the declared argument types,
```text
module A {
  export witness w(a: Field): Boolean;
}
import A;
witness w(a: Field, b: Field): Boolean;
circuit foo(a : Field) : Boolean { return w(a); }
```
```scheme
(witness %w.0 ((%a.6 (tfield))) (tboolean))
(witness %w.1 ((%a.4 (tfield)) (%b.5 (tfield))) (tboolean))
(circuit %foo.2 ((%a.3 (tfield)))
  (tboolean)
  (call %w.0 %a.3))
```
* to infer the types of parameters or return type of anonymous circuits
  when they haven't been declared,
* to verify the types of parameters or/and return type of anonymous circuits
  when they have been.

Equivalence of types is discussed in the description of Ltypes.
Subtyping is defined exclusively by the following rules.

* Any type is a subtype of an equivalent type.

* A Uint type with maximum value k1 is a subtype of another Uint type with
  maximum value k2 if k1 <= k2.

* Any Uint type is a subtype of Field.

* A vector type A is a subtype of another vector type B if A and B have the smae
  length and A's element type is a subtype B's element type.

* A tuple type A is a subtype of another tuple type B if A and B have the same
  number of elements and the type of each element of A is a subtype of each element
  of B, taken in order.

* A vector type A is a subtype of a tuple type B if A has the same length
  as B has elements and A's element type is a subtype of each of B's element
  types.

* A tuple type A is a subtype of a vector type B if B has the same length as A has
  elements and each of A's element types is a subtype of B's element type.

* A contract A is a subtype of another contract B if A and B have the same name
  and each circuit of B has a counterpart in A (but not necessarily vice versa),
  taken in any order.  A circuit is a counterpart for another if it has the
  same name, equivalent purity, equivalent argument types, and equivalent return
  types. Two circuits have equivalent purity if both are marked pure or neither
  is marked pure.

A couple of implicit consequences of the rules for equivalence and subtyping
are worth making explicit:

* A nominal type alias A for type T is not a subtype of any other type, including T,
  and no other type is a subtype of A.

* Struct and enum types are also nominally typed, so a struct or enum
  type is not a subtype of any other type, and no other type is a subtype
  of it.

* Note, however, that since a non-nominal type alias A for a type T is treated
  as if it were T, A is always a subtype of T and vice versa, even if T is a
  nominal type alias, struct, or enum.

Restrictions on nominal type aliases are enforced by infer types and checked by
the check-types/Lnodca.
Most other passes "de-alias" types before inspecting them so that the aliases
do not prevent operations requiring a specific type to be handled properly when
provided with a type alias for that type.

The pass `print-typescript` replaces aliases created by type definitions exported
from the contract top level with the alias name in the generated TypeScript
type-definition file.  If it weren't for this, type aliases could be dropped from the
intermediate representation of types after `infer-types`.

This pass's handling of expressions is rather involved because
it must produce for each expression both a new expression and the new
expression's type, perform most of the checks described above,
and, when checks fail, produce appropriate error messages.
For the most part, the checks are relatively straightforward, though
tedious.

The handling of a function call, `map`, and `fold` requires finding
the argument types, then selecting a matching function from the
candidates recorded by `expand-modules-and-types`.
The argument types are the type types of the argument expressions at
the call site, or in the case of the vector arguments to `map` and
`fold`, the types of a single element of the vector arguments.
A matching function is one for which the argument types
are subtypes of the function's declared types.

The candidates recorded by expand-modules-and-types are grouped by
scope, with the innermost scope first, so the selection search
begins with the first group.
If a group contains single matching function, this function is
selected, the call is built, and the return type is the return type
of the function or, in the case of `map`, a vector type whose length
is the same as the lengths of the input vectors and whose element
type is the return type of the function.
If a group contains no matching functions, the search continues with
the next group.
If a group encountered during this process contains two or more
matching functions, an exception is raised, because there is no one
right choice.
If no matching function is found in any group, an exception is also
raised.

The handling of `if` expressions is slightly complicated.
The source language supports both `if` statements and
what we'll call `if` expressions of the form `e0 ? e1 : e2`, but
`eliminate-statements` converts occurrences of the former into
the latter, thereby losing the distinction.
The distinction is important however: while the types of the
branches of an `if` *statement* can differ arbitrarily, the
types of the branches of an `if` *expression* must match or
we won't be able to determine the type of the `if` expression
as a whole.
Noting that the value of an `if` statement is never used and
that, if the value of an `if` expression is not used, we can
safely ignore differences in the types of the branches, we
simply treat `if` expressions differently based on whether
their values are used rather than whether they started out
life as statements or expressions.
It is debatable whether this can cause some programs to type-check
when they should not, but it does not cause any program to type-check
that is not actually well-typed.
If we decide that a more pedantic approach is called for, we
can always include a flag in each `if` expression to say whether
it started out life as a statement or expression, and use that
as the basis for this pass's differing treatment.

This motivates the use of two Expression handlers in the implementation
of infer-types: `Care` and `CareNot`.
The former is called when the value of the expression is consumed,
and the latter is called when the value of the expression is not
used.
The former requires that the type of at least one branch of an `if`
be a subtype of the other, while the latter does not.

The handling of unsigned-integer arithmetic is also slightly complicated.
When two unsigned integers of types `Uint<m>` and `Uint<n>` are combined,
the result type is determined according to the following table:

| operation | result type |
|-----------|-------------|
| `+`       | `Uint<m+n>` |
| `-`       | `Uint<m>`   |
| `*`       | `Uint<m*n>` |

For `-`, `infer-types` also injects an assertion the second operand is
not greater than the first.

When one of the input types is a nominal type alias for `Uint<m>`, the other must
be the same nominal type alias, and for `+` and `*`, `infer-types` injects an
(unsafe) cast of the result to `Uint<m>`.
For `-`, `infer-types` also injects an assertion the second operand is
not greater than the first.

When one operand of of an arithmetic operation has Uint type and the other a
Field type, `infer-types` injects a casts of the Uint to Field and and otherwise
injects no other checks or casts.
(Field arithmetic wraps at run time, so there is never a need for `infer-types`
to insert checks on the inputs or casts for the result.)

The handling of external contract declarations relies on having
access to an implementation of the declared contract.
In program `t.compact` and for a declared contract `C` in `t.compact`
it conducts the following checks (`t.compact` exists in the `path` 
directory):
* does it have access to an implementation of `C`, that is, can it find
  `C.compact` in `path`? If not, it throws an error stating that the 
  compiler cannot find an implementation of `C`.
* does the `path/C/compiler/contract-info.json` exist? If so, it moves
  on to the next check. Otherwise, it throws an error asking the user
  to (re)compile `C.compact` again.
* is the time stamp of `path/C/compiler/contract-info.json` newer
  than the time stamp of `C.compact`? If so, it continues with the `infer-types`
  pass. Otherwise, it throws an error informing the user that `C.compact`
  has been updated recently but it hasn't been compiled and asks them to 
  recompile it.

After these checks, it checks that `path/C/compiler/contract-info.json` is
not malformed. Finally, it checks that for each circuit `f` declared in `C` 
within `t.compact` there exists a circuit `f` in `path/C/compiler/contract-info.json`
with matching type signature and purity. 

This pass also applies various restrictions regarding external contracts:
* exported circuits cannot return a contract type,
* exported circuits cannot have paramters of contract type,
* contract types may not appear in witness return type,
* and `default` is not defined for contract types at the moment but it will be defined later.

### remove-tundeclared (Ltypes -> Lnotundeclared)

This pass drops the `tundeclared` types from `Ltypes`.

### combine-ledger-declarations (Lnotundeclared -> Loneledger)

This pass combines all ledger field declarations and constructor into a
single ledger declaration and includes ADT name and type information.
It also inserts a ledger binding for `Kernel` which allows explicit
access to kernel operations defined in `std.compact`.

### discard-unused-functions (Loneledger -> Loneledger)

This pass discards all non-exported circuit definitions and external
functions (circuit, witness, or statement) declaration that isn't reachable
from one of the exported circuits.
The earlier pass `expand-modules-and-types` also has the same effect,
but this pass drops unreachable definitions and declarations that are
produced by `infer-types` during type parameterization.

### reject-recursive-circuits (Loneledger -> Loneledger)

TODO

### reject-multiply-defined-exports (Loneledger -> Loneledger)

This pass detects and rejects programs that have multiple exported
circuit definitions or external declarations with the same name,
since the TypeScript target does not generally support overloading.
Multiple non-exported definitions with the same name are okay, as
are non-exported definitions whose names overlap with exported or
external names, since non-exported definitions can be and are renamed
as necessary.

### recognize-let (Loneledger -> Lnodca)

This pass converts direct circuit applications into `let*` forms.
For example, it converts the `Ltypes` equivalent of the Compact statement:
```
return 1 + (circuit (x: Boolean): Field { return x == false ? n + 7 : n + 13; })(!y);
```
into the `Ltypes` equivalent of the Compact statements:
```
let x: Boolean;
return 1 + (x = !y, x == false ? n + 7 : n + 13);
```
This simplifies the code produced by this pass and `print-typescript`,
but the code produced by the downstream pass `inline-circuits` would be
the same if this pass were not run, since they have the same effect for
direct circuit applications.

### check-types/Lnodca (Lnodca -> Lnodca)

This pass type-checks programs in the Lnodca intermediate language.
It is essentially a simplified version of `infer-types` tailored to
the different output language, and it serves to verify that the
passes between the last type-check and this one have preserved
well-typedness.
It performs a few other checks as well, e.g., undefined identifier
checks, that help verify the well-formedness of the program.

At present, the compiler runs `check-types/Lnodca` after each pass
that produces an `Lnodca` program, except of course for
`check-types/Lnodca` itself.
This pass can be removed for production releases of the compiler
if desired, since it serves no purpose if the other passes are
working correctly.

### check-sealed-fields (Lnodca -> Lnodca)

This pass complains if a sealed field can be modified by an exported
circuit or any circuit that is reachable from an exported circuit. We
presently assume that no witnesses or external circuits can modify any
sealed fields.

### reject-constructor-cc-calls (Lnodca -> Lnodca)

This pass raises an exception if the constructor tries to make a contract call, either
directly or indirectly.

### identify-pure-circuits (Lnodca -> Lnodca)

This pass identifies the circuits that are pure. In particular, it
considers a circuit to be pure if it can prove, within its limited
ability, that the circuit does not touch public state, does not call
any impure circuits, and does not call any witnesses. Otherwise,
it considers a circuit to be impure. Once it verifies that a circuit
is impure it checks if the circuit has been declared pure. If so,
it throws an error.

It considers a circuit that is not declared pure and is being called
by another pure circuit pure. However, it considers circuits that are
not declared pure in a contract declaration as impure, regardless of
the implementation of the contract. 

### determine-ledger-paths (Lnodca -> Lwithpaths0)

TODO

### propagate-ledger-paths (Lwithpaths0 -> LwithPaths)

TODO

### track-witness-data (Lwithpaths -> Lwithpaths)

This pass raises an exception if it determines that the output of a witness call is
stored in the public ledger, passed as an argument to a cross-contract call, or
returned from an exported circuit.
The pass is structured as a polyvariant abstract interpreter, where each abstract
value contains the set of witnesses whose return values are contained within the
real value rather than (in most cases) the exact real value itself.
More precisely, the abstract values `abs` are as follows:
```
(Abs-boolean true? leak*)  // actual boolean values
(Abs-atomic leak*)         // any other atomic value
(Abs-multiple abs*)        // struct or tuple (one abs per field)
(Abs-single abs)           // non-empty vector (one abs for all elements)
```
For `Abs-boolean` and `Abs-atomic`, `leak*` is a list of the witnesses, each
represented as a `leak` record containing the source location of the witness's
declaration, the name of the witness, and a unique identifier used internally
for hashing.

The interpreter is guaranteed to terminate because there are a finite number
of call sites, each calling a known function, and no recursion, so each function
body is processed a fixed number of times, so the analysis is at worst `O(F*C)`,
where `F` is the number of circuits and `C` is the number of call sites.
(It's actually potentially a bit worse than that.  The pass uses a
nested list representation of environments, so a large set of local variables
can lead to some non-trivial additional overhead.)
Even if this were not the case, say if recursion were permitted, the pass avoids
processing a circuit body twice with the same list of abstract arguments;
since there are a finite number of witnesses and a finite number of slots in
each abstract value in which a list of witnesses can be held, this means there
are a finite number of lists of abstract argument with which a circuit can be
processed.
In most cases, termination will be quick; it would take some careful crafting
to get the analysis to iterate many times over the same circuit.

### save-contract-info (Lwithpaths -> Lwithpaths)

This pass generates a `contract-info.json` for the contract `C` being compiled
by Compactc. For contract `C`, this file contains the following in this order:
- the type signature of exported circuits, that
  is the name of the circuit, its purity, its arguments and its return type,
- the type signature of exercised witnesses,
- the name of contracts that have been declared in a contract type declaration
  within `C`, whether, `C` actually calls them or not.


### exported-impure-circuit-names (Lwithpaths -> *)

This pass generates a list of the exported impure circuit names of the program.

### prepare-for-typescript (Lwithpaths -> Ltypescript)

This pass converts the input program into one that is more directly
amenable to typescript generation.
In essence, it serves as a support pass for `print-typescript`, and
the conversions performed during this pass are not preserved after
`print-typescript`.

### print-typescript (Ltypescript -> Ltypescript)

This pass emits JavaScript .js files that contain code that is semantically
equivalent to the source Compact code and returns its input.
It also produces TypeScript .d.ts files and source-map .js.map files.

The structure of the code is described in detail later in this
document under the header "Generated TypeScript/JavaScript structure".

Some of the trickiest challenges for this pass are producing unique
identifier names, expanding `map` and `fold` into TypeScript
equivalents, and handling `==`, which is complicated due to the need to
implement structural equivalence.
The code for handling `let*` forms nested within expressions is also
a bit tricky, since JavaScript `let` forms cannot be nested within
expressions without the undue overhead of creating and directly calling a
circuit.

This pass takes quite a bit of care to produce readable JavaScript code
so that it is easier to understand and test.

Calls from JavaScript and TypeScript to exported Compact circuits are
supported via the `Circuits` object created at contract initialization
time by the generated JavaScript code. Each exported circuit is
represented by a field named for the exported circuit in the `Circuits`
object, and the value of the field is an ordinary JavaScript function.

Calls from Compact to JavaScript and TypeScript are supported via the
`Witnesses` object provided to the contract constructor.  The `Witnesses`
object must have one field for each of the witnesses declared in the
Compact program, and it should be a function that accepts the declared
number and types of witness arguments and returns the declared witness
return type.

The following table shows the datatype equivalencies between Compact and
JavaScript.

| Compact type     | TypeScript/JavaScript type |
|-----------------|----------------------------|
| Boolean         | boolean                    |
| Field           | bigint                     |
| Uint<0..k>      | bigint                     |
| Uint<k>         | bigint                     |
| Bytes<k>        | Uint8Array                 |
| Vector<k, type> | Array<type>                |
| Enum(f₁,...,fₘ) | enum (number)              |
| Struct          | object                     |

To make Compact fully type-safe, the JavaScript code produced by the
Compact compiler performs certain dynamic checks on any argument `x`
passed from external code to a Compact circuit and to any return-value
`x` received from an (external) witness.


| Compact type     | Generated checks                   |
|-----------------|------------------------------------|
| Boolean         | `x` is a boolean                   |
| Field           | `x` is a bigint                    |
|                 | 0 <= `x` <= `FIELD_MAX`            |
| Uint<0..k>      | `x` is a bigint                    |
|                 | 0 <= `x` <= k                      |
| Uint<k>         | `x` is a bigint                    |
|                 | 0 <= `x` <= 2^k-1
| Bytes<k>        | `x` is a Uint8Array                |
|                 | `x` has k elements                 |
| Vector<k, type> | `x` is an Array                    |
|                 | `x` has k elements                 |
|                 | each element has type `type`       |
| Enum(f₁,...,fₖ) | `x` is a number                    |
|                 | 0 <= `x` <= `k`                    |
| Struct          | `x` is an object                   |
|                 | `x` has the expected fields        |
|                 | the fields have the expected types |

The elements of Vectors and Struct arguments and return values are
recursively subjected to these checks.  As a result, repeatedly crossing
the boundary between JavaScript and Compact is expensive for large Arrays
or deeply nested structures.

The Compact compiler also generates a TypeScript type definition (dts) file
with TypeScript headers that allow for some
checks to be performed at compile time when the external code interacting
with the generated code is written in TypeScript rather than JavaScript.
Even with the external code written in TypeScript, however, TypeScript
types cannot be used to declare fixed lengths for Arrays and Uint8Arrays
and are in any case easy to circumvent with unsafe casts.

Structure types, enum types, and type aliases created by declarations
exported from the top level of a contract are replaced by the corrsponding
struct, enum, or type name in the generated type-definition file.

### drop-ledger-runtime (Lnodisclose -> Lposttypescript)

This pass is a simple one that discards things that are no longer needed after
we have emitted JavaScript code.  It discards (1) type definitions, (2) the
ledger constructor, and (3) JS runtime-only ledger operations.  It also
discards type aliases from the representation of the intermediate-language types.

This pass also translates `!=`, `<=`, `>`, and `>=` expressions to equivalent
`<` and `==` expressions:

| Lnodisclose | Lposttypescript       |
|-------------|-----------------------|
| `(!= a b)`  | `(if (== a b) #f #t)` |
| `(<= a b)`  | `(if (< b a) #f #t))` |
| `(> a b)`   | `(< b a)`             |
| `(>= a b)`  | `(if (< a b) #f #t)`  |


### replace-enums (Lposttypescript -> Lnoenums)

This pass is a nearly trivial one that simply replaces each enum-ref with the
corresponding constant and each enum type with a bounded unsigned integer type
whose bound is the enum's maximum element value.

**Compact source:**
```text
enum Name { bill, sally, fred, george }

export circuit foo(x: Name): Boolean {
  return x == Name.bill;
}
```

**Lposttypescript input:**
```scheme
(circuit %foo.0 ((%x.1 (tenum Name bill sally fred george))) (tboolean)
  (== %x.1 (enum-ref (tenum Name bill sally fred george) bill)))
```

**Lnoeunums output:**
```scheme
(circuit %foo.0 ((%x.1 (tunsigned 3))) (tboolean)
  (== %x.1 (safe-cast (tunsigned 3) (tunsigned 0) %x.1)))
```

This allows downstream passes to verify that what were formerly enum
values are in the expected range for what were formerly enum types.

### unroll-loops (Lnoenums -> Lunrolled)

This pass unrolls the loops represented by `map` and `fold` expressions.  That
is, it expands each `map` and `fold` into a sequence of applications of the
mapped or folded function.  The length of each resulting sequence of
applications is fixed because vector sizes are known at compile time.  In the
case of `map` the sequence is contained within an `Lunrolled` `tuple` form,
which creates the output vector.  In the case of `fold`, the calls are threaded
together with an accumulator, in effect, to produce the folded value.

**Compact source:**
```text
witness foo(n: Field) : Boolean;

export circuit C(v: Vector<2, Field>): Vector<2, Boolean> {
  return disclose(map(foo, v));
}
```

**Lnoenums input:**
```scheme
(witness %foo.1 ((%n.2 (tfield))) (tboolean))
(circuit %C.0 ((%v.3 (tvector 2 (tfield)))) (tvector 2 (tboolean))
  (map ((tboolean) (tvector 2 (tfield))) %foo.1 %v.3))
```

**Lunrolled output:**
```scheme
(witness %foo.1 ((%n.2 (tfield))) (tboolean))
(circuit %C.0 ((%v.3 (tvector 2 (tfield)))) (tvector 2 (tboolean))
  (let* ([(%t.4 (tvector 2 (tfield))) %v.3])
    (tuple
      (call %foo.1 (tuple-ref %t.4 0))
      (call %foo.1 (tuple-ref %t.4 1)))))
```

Compilers for general-purpose programming languages that perform loop unrolling
typically limit the unrolling to cases where the number of iterations is small,
or for large counts they unroll partially into a loop with, say, two copies of
the loop body and half the number of iterations.  The Compact compiler unrolls
loops unconditionally, which can lead to a large expansion in the size of the
output program relative to the input program, especially when `map` and `fold`
operations are nested.

This pass does one other thing.  Where a local circuit form appears in the
syntax of a function call, this pass binds a new identifier to the circuit form
using an `flet` form and places a reference to the identifier in the function
position of the call.  This is a favor for the next pass, `inline-circuits`,
which gets to treat every function call the same.  (The example below also shows
how `fold` is translated.)

**Compact source:**
```text
export circuit C(v: Vector<2, Field>): Boolean {
  return fold((b, x): Boolean => x == 0, true, v);
}
```

**Lnoenums input:**
```scheme
(circuit %C.0 ((%v.1 (tvector 2 (tfield)))) (tboolean)
  (fold
    ((tboolean) (tboolean) (tvector 2 (tfield)))
    (circuit
      ((%b.2 (tboolean)) (%x.3 (tfield))) (tboolean)
      (== %x.3 (unsigned->field 0)))
    #t
    %v.1))
```

**Lunrolled output:**
```scheme
(circuit %C.0 ((%v.1 (tvector 2 (tfield)))) (tboolean)
(flet (%circ.4
        (circuit
          ((%b.2 (tboolean)) (%x.3 (tfield))) (tboolean)
          (== %x.3 (unsigned->field 0))))
  (let* ([(%t.5 (tboolean)) #t]
         [(%t.6 (tvector 2 (tfield))) %v.1])
    (call %circ.4
      (call %circ.4 %t.5 (tuple-ref %t.6 0))
      (tuple-ref %t.6 1)))))
```

### inline-circuits (Lunrolled -> Linlined)

This pass inlines the code for circuits defined by the program at each point
where they are called within the program, leaving behind only calls to
externally defined circuits, statements, and witnesses.  To maintain the
invariant that each id record is used to represent only one variable or
function, the inlined code at each call site is a copy of the function body with
the function's parameters renamed to new ids and placed within the scope of a
`let*` expression binding the new ids to the argument expressions from the call
site.

**Compact source:**
```text
export circuit C(v: Vector<2, Field>): Boolean {
  return fold((b, x): Boolean => x == 0, true, v);
}
```

**Lunrolled input:**
```scheme
(circuit %C.0 ((%v.1 (tvector 2 (tfield)))) (tboolean)
  (flet (%circ.4
          (circuit
            ((%b.2 (tboolean)) (%x.3 (tfield))) (tboolean)
            (== %x.3 (unsigned->field 0))))
    (let* ([(%t.5 (tboolean)) #t]
           [(%t.6 (tvector 2 (tfield))) %v.1])
      (call %circ.4
        (call %circ.4 %t.5 (tuple-ref %t.6 0))
        (tuple-ref %t.6 1)))))
```

**Linlined output:**
```scheme
(circuit %C.0 ((%v.1 (tvector 2 (tfield)))) (tboolean)
  (let* ([(%t.5 (tboolean)) #t]
         [(%t.6 (tvector 2 (tfield))) %v.1])
    (let* ([(%b.7 (tboolean)) (let* ([(%b.8 (tboolean)) %t.5]
                                     [(%x.9 (tfield)) (tuple-ref %t.6 0)])
                                (== %x.9 (unsigned->field 0)))]
           [(%x.10 (tfield)) (tuple-ref %t.6 1)])
      (== %x.10 (unsigned->field 0)))))
```

Recursive functions are detected and rejected during this process; this is the
last source-program error to be detected by the compiler.

```text
export circuit isEven(n: Field) : Boolean { return (n == 0) || isOdd(n - 1); }

circuit isOdd(n: Field) : Boolean { return !isEven(n - 1); }
```

```text
Exception: inline-circuits.compact line 1, char 1:
  recursion involving isEven and isOdd at line 3, char 1
```

The definition of any function defined within a file that is inlined into
another circuit defined in the file is not included in the output.  This is a
heuristic for determining (by process of elimination) the set of functions that
should be available as entry points, and should be revisited, as it can result
in more or fewer entry points that desired.

### check-types/Linlined (Linlined -> Linlined)

This pass type-checks programs in the Linlined intermediate language.
It is essentially a simplified version of `infer-types` tailored to
the different output language, and it serves to verify that the
passes between the last type-check and this one have preserved
well-typedness.
It performs a few other checks as well, e.g., undefined identifier
checks, that help verify the well-formedness of the program.

At present, the compiler runs `check-types/Linlined` after each pass
that produces an `Linlined` program, except of course for
`check-types/Linlined` itself.
This pass can be removed for production releases of the compiler
if desired, since it serves no purpose if the other passes are
working correctly.

### drop-safe-casts (Linlined -> Lnosafecast)

This pass simply removes `safe-cast` forms from the language, replacing each
`safe-cast` form with the encapsulated expression.

### resolve-indices/simplify (Lnosafecast -> Lnovectorref)

This pass performs copy propagation and constant folding with the primary goal
of reducing non-constant vector-ref and vector-slice indices to constants and an
incidental goal of simplifying the program.
It raises an exception if it finds that a `bytes-ref`, `vector-ref`, `bytes-slice`
or `vector-slice` index cannot be reduced to a constant or if the constant is
not within range for the inferred type of the vector or slice.

The pass operates primarily over expressions using an Expression processor that
takes one argument, `ir`, representing the input expression and returns two
values: a residual expression, `expr`, and a compile-time value (CTV), `ctv`
corresponding to `expr`.
All simplification is based on `ctv`, which can take one of the following forms:

  * `(CTV-const var-name datum)`: `expr`'s value is `datum`.

  * `(CTV-tuple var-name ctv*)`: `expr`'s value is a tuple, and the CTVs of the
     tuple's elements are `ctv*`.

  * `(CTV-struct var-name elt-name* ctv*)`: `expr`'s value is a struct with
     field names `elt-name*`, and the parallel list `ctv*` contains the compile-time
     values of the struct's fields.

  * `(CTV-unknown var-name)`: `expr`'s value is not known, i.e., the compiler did not
     determine anything useful about `expr`'s value.

Variable names and CTVs have a two-way relationship that is used to support
copy propagation.  Variable names are associated with CTVs via a global
table, `var-ht`.
On the other hand, CTVs are associated with variable names via the common field
`var-name` that appears in each form of CTV shown above.

Some CTVs are not associated with any variable name, in which case the `var-name`
field holds a dummy variable name called `no-var-name` (`NVN` for short).
In fact, in most cases, a CTV is created with `var-name` = `NVN` and recreated with
a non-NVN var-name only when it turns out to be the CTV of the right-hand side
(RHS) of a `let*` binding, as described below.

The compiler creates `var-ht` mappings for the formal parameters of a circuit
before processing the body of the circuit, then destroys the mapping after
it processes the body.  For each formal parameter `x`, the mapping is from `x` to
`(CTV-unknown x)`, since nothing is known about formal parameter values.

Similarly, the compiler creates a `var-ht` mapping for the left-hand-side
(LHS) variable `x` of each `let*` binding `[x e]` before processing the remaining
bindings and body of the `let*`, then destroys the mapping after processing
the remaining bindings and body.
Assuming the CTV of the binding's RHS expression `e` is `ctv`, the mapping maps
`x` to:

  * `ctv`, if `ctv`'s `var-name` field holds a variable name that is in-scope,
     and

  * a copy of `ctv` with `var-name` = `x` otherwise.

(A variable name that is in-scope has a binding in `var-ht`, and a variable
name that is not in-scope has no binding in `var-ht`.
Thus the compiler can reliably determine if a variable is in-scope by checking
to see if it has a mapping in `var-ht`.
No `var-ht` mapping ever exists for `NVN`, so it never appears to be in-scope.)

In this manner a CTV that is the object of a current `var-ht` binding is
always associated with the in-scope base variable of a propagation chain.
For example, during the processing of `e` in the circuit definition below:

```scheme
(circuit (a)
  (let* ([b a] [c b])
    e))
```

`a`, `b`, and `c` are all mapped to `(CTV-unknown a)`, allowing the compiler to
replace references to both `b` and `c` in `e` with references to `a`.
Similarly, during the processing of e in the `let*` expression below:

```scheme
(let* ([a (quote 3)] [b a] [c b])
  e))
```

`a`, `b`, and `c` are all mapped to `(CTV-const a 3)`, allowing the compiler.to
replace references to `b` and `c` in `e` with `(quote 3)`.
In both cases, this pass retains the (now useless) bindings for `b` and `c` (and
`a` in the second example), but these bindings are discarded by the subsequent pass
`discard-useless-code`.

One can think of a CTV's var-name as a fallback option.
That is, if a CTV does not allow an expression to be replaced with a constant,
tuple element, or struct element, the fallback is to use the CTV's variable name
if it is in scope.

As illustrated above `CTV-const` can arise from quote expressions.
It can also arise from default forms; e.g., the residual expression and CTV of
`(quote 3)` are `(quote 3)` and `(CTV-const NVN 3)`, and the residual expression and
CTV of `(default Field)` are `(quote 0)` and `(CTV-const NVN 0)`.

`CTV-const` also arises via constant folding, which is enabled when a form like
`(+ e1 e2)` or `(field->bytes e)` is processed and the compile-time values of
the operands are `CTV-const`s.
For example, the residual expression and CTV of the form `(* x 2)` within
`(let* ([x 7]) (* x 2))` are `(quote 14)` and `(CTV-const NVN 14)` because x's
CTV is `(CTV-const x 7)` and `2`'s CTV is `(CTV-const NVN 2)`.

`CTV-tuple` arises from tuple and tuple slicing forms, e.g., assuming that
the CTV of `e` is (CTV-unknown NVN), the residual expression of `(tuple e 2)`
is `(tuple e 2`) and its CTV is
`(CTV-tuple NVN (CTV-unknown NVN) (CTV-const NVN 2))`.
`CTV-struct` similarly arises from structure allocation (new) forms.

`CTV-unknown` arises only when none of the other options is appropriate.

The CTV of `(seq e1 ... en-1 en)` is CTV value of `en`, and the CTV
of `(let* (binding ...) e)` is the CTV of `e`.
Thus, the CTV corresponding to an expression expr might be a `CTV-constant`,
`CTV-tuple`, or `CTV-struct` even if expr is not a `quote`, `tuple`, or `new` form.
For example, the CTVs of:

```scheme
(seq <any expr> (quote 15))
(let* (<any binding> ...) (quote 15))
```

are both `(CTV-const NVN 15)`.

The CTV `(if e0 e1 e2)` depends on the compile-time values of `e0`, `e1`, and `e2`:
if `e0`'s compile-time value is `(CTV-const <x or NVN> b)` the residual expression and
CTV of the `if` expression are (1) the residual expression and CTV of `e1`, if `b`
is #t, or (2) the residual expression and CTV of `e2`, if `b` is `#f`. In all other
cases, the residual expression is `(if e0^ e1^ e2^)`, where `e0^`, `e1^`, and `e2^`
are the residual expressions of `e0`, `e1`, and `e2`.  If the CTVs of `e1` and `e2`
are the same, the CTV of the `if` expression is the common CTV of `e1` and `e2`.
Otherwise, the CTV of the `i`f expression is `(CTV-unknown NVN)`.

`CTV-tuple` and `CTV-struct` CTVs are forms of partially static structures
(compile-time representations of structures, some of whose parts may be known
and some of whose parts may be unknown at compile time).  `CTV-tuple` CTVs are
used to simplify `tuple-ref` forms, and `CTV-struct` forms are used to simplify
`elt-ref` forms.  For example, the residual expression and CTV of
`(elt-ref x b)` in:

```scheme
(let ([x (new (tstruct S (a Field) (b Field)) 7 11)])
  (elt-ref x b))
```

are `(quote 11)` and `(CTV-const NVN 11)`.

`vector-ref` forms, which have non-constant indices, must be replaced by equivalent
`tuple-ref` forms, which have constant indices.
Similarly, `bytes-ref`, which can have non-constant indices in the input, must be
eplaced by equivlaent `bytes-ref` forms in the output, which have constant indices.
`bytes-slice`, `tuple-slice`, and `vector-slice` forms must be replaced by equivalent
sequences of `bytes-ref` or `tuple-ref` forms.
When this pass encounters a reference or slice form with a non-constant index, it
processes the index expression to obtain a residual index expresison and a CTV.
It raises an exception if the CTV is not a `CTV-const`.
It also raises an exception if the datum inside the CTV-const is not in range
for the reference or slice.

EXAMPLE.  Consider:

```scheme
(let* ([y (let* ([x (tuple (call) (quote 7) (public-ledger))]) (var-ref x))]
       [z (seq (call) (var-ref y))])
  (tuple
    (tuple-ref (var-ref z) 0)
    (vector-ref (var-ref v) (tuple-ref (var-ref z) 1))))
```

where `(call)` is shorthand for a witness or external circuit call and
`(public-ledger)` is shorthand for a call to a public-ledger ADT operation, the
contents of both of which are omitted for brevity.
We'll assume that the CTV of `(var-ref v)` is `(CTV-unknown v)` and that its type
is a vector with 10 elements.

Here are the residual expressions, CTVs, and variable mappings that arise as
this expression is processed:

  * The residual expression of `(call)` is `(call)`, and its CTV is
    `(CTV-unknown NVN)`.

  * The residual expression of `(quote 7)` is `(quote 7)`, and its CTV is
    `(CTV-const NVN)`.

  * The residual expression of `(public-ledger)` is `(public-ledger)`, and its
    CTV is `(CTV-unknown NVN)`.

  * The residual expression of `(tuple (call) (quote 7) public-ledger)` is
    `(tuple (call) (quote 7) public-ledger)` and its CTV is
    `(CTV-tuple NVN (CTV-unknown NVN) (CTV-const NVN 7) (CTV-unknown NVN))`.

  * `x` is mapped to `(CTV-tuple x (CTV-unknown NVN) (CTV-const NVN 7) (CTV-unknown NVN))`,
    i.e., the CTV of the `tuple` form with NVN replaced by `x`.

  * The residual expression of `(var-ref x)` is `(var-ref x)`, and its CTV is
    `(CTV-tuple x (CTV-unknown NVN) (CTV-const NVN 7) (CTV-unknown NVN))`.

  * The residual expression of the inner `let*` is
    `(let* ([x (tuple (call) (quote 7) (public-ledger))]) (var-ref x))`,
    and its CTV is the CTV of `(var-ref x)`, i.e.,
    `(CTV-tuple x (CTV-unknown NVN) (CTV-const NVN 7) (CTV-unknown NVN))`.

  * `y` is mapped to the CTV
    `(CTV-tuple y (CTV-unknown NVN) (CTV-const NVN 7) (CTV-unknown NVN))`.
    The CTV's var-name is `y` rather than `x` because `x` is no longer in-scope
    (its mapping is no longer contained in `var-ht`).

  * The residual expression of `(var-ref y)` is `(var-ref y)` and its CTV is
    `(CTV-tuple y (CTV-unknown NVN) (CTV-const NVN 7) (CTV-unknown NVN))`.

  * The residual expression of `(seq (call) (var-ref y))` is
    `(seq (call) (var-ref y))` and its CTV is the CTV of `(var-ref y)`, i.e.,
    `(CTV-tuple y (CTV-unknown NVN) (CTV-const NVN 7) (CTV-unknown NVN))`.

  * `z` is mapped to the CTV
    `(CTV-tuple y (CTV-unknown NVN) (CTV-const NVN 7) (CTV-unknown NVN))`.
    The CTV's var-name has not be replaced by `z` because `y` is still in-scope.

  * For both occurrences of `(var-ref z)`, the residual expression is `(var-ref y)`
    and the CTV is 
    `(CTV-tuple y (CTV-unknown NVN) (CTV-const NVN 7) (CTV-unknown NVN))`.

  * The residual expression of `(tuple-ref (var-ref z) 0)` is
    `(tuple-ref (var-ref y) 0)` and its CTV is (CTV-unknown NVN).
    Although z's CTV has some information about the tuple, it doesn't have
    information about the first element.

  * The residual expression of `(tuple-ref (var-ref z) 1)` is
    `(seq (tuple-ref (var-ref y) 1) (quote 7))` and its CTV is `(CTV-const NVN 7)`.
    `z`'s CTV tells the compiler that the second tuple element is the constant
    `7`, and the compiloer retains the residual expression of the original expression
    for its effects.  (In this case, the residual expression doesn't have any
    effects, but checking for and discarding useless code is not this pass's job
    but rather the job of the subsequent pass discard-useless-bindings.)

  * The residual expression of `(var-ref v)` is `(var-ref v)` and its CTV is
    `(CTV-unknown NVN)`, as assumed.

  * The residual expression of the `vector-ref` form is
    `(let* ([t (var-ref v)]) (tuple-ref (var-ref y) 1) (tuple-ref t 7))`.
    `(var-ref v)` and `(tuple-ref (var-ref y) 1)` are preserved for their effects,
    and the `let*` is introduced to preserve left-to-right order of evaluation.
    If the `vector-ref` index had not reduced to a constant, or the constant
    was greater than or equal to `10` (the assumed length of the vector for
    this example), the pass would have raised an exception to that effect.
    The CTV is `(CTV-unknown NVN)` since nothing is known about the contents
    of the vector.

The example as a whole residualizes to:

```scheme
(let* ([y (let* ([x (tuple (call) (quote 7) (public-ledger))]) (var-ref x))]
       [z (seq (call) (var-ref y))])
  (tuple
    (tuple-ref (var-ref y) 0)
    (let* ([t (var-ref v)]) (tuple-ref (var-ref y) 1) (tuple-ref t 7))))
```
and it's CTV is `(CTV-tuple NVN (CTV-unknown NVN) (CTV-unknown NVN))`.
The binding for `z` remains even though `z` is not referenced; this is removed
by discard-unused-code along with the effect-free exprs in effect contexts.

As noted above, the pass sometimes produces `seq`s with effect-free expressions
in effect contexts, and it sometimes leaves behind unreferenced `let*` bindings.
Discarding these is the job of the subsequent pass discard-useless-code.

This pass also currently converts `let*` expressions with multiple bindings
into nested `let*` expressions each with a single binding, because doing so
turns out to be easier.

### discard-useless-code (Lnovectorref -> Lnovectorref)

This pass is an optimization pass and is thus optional.
It drops useless code, i.e., code that may be reachable but has no impact on
the outputs or effects of the program.
In particular, it drops bindings for unreferenced variables, side-effect-free
right-hand sides of dropped bindings, and side-effect-free expressions appearing
in all but the last subform of a `seq` expression.
To make the output more readable, it combines nested `let*` expressions
and nested `seq` expressions.

The pass operates over expressions with an `Expression` processor that accepts
two arguments: the input expression `ir` and an `effect?` flag saying whether `ir`
is used only for effect.
For each kind of expression it returns three values: output form `expr`, a `pure?` flag,
and an `idset`.

The `pure?` flag is true if `expr` is free of effects, and `idset` is the set of
variables that occur free in `expr`.  When `pure?` is true, `expr` is discarded if
its value isn't used.
Similarly, when a `let*`-bound variable `var` is not in the `idsets` of the
right-hand sides of subsequent `let*` bindings or the `let*` body, the binding
is dropped.
The input `effect?` flag is used when building `seq` expressions to avoid polluting idsets.

### reduce-to-circuit (Lnovectorref -> Lcircuit)

This pass is responsible for making the transformation from an
arbitrarily nested expression language with calls and asserts
appearing at any level of nesting into one in which the calls and
asserts appear only at the top level of a program and in which all
expressions are unnested, i.e., all subexpressions are atomic
(trivial) expressions like constants and variable references.

Because evaluation of an `assert` expression can depend on the
position of the `assert` within a nested set of conditionals,
this pass replaces the `assert` test with one that not only
reflects the original `assert` test but also the logical
combination of tests from the nested conditionals that it was
nested within.
The evaluation of a `call` expression can also depend on the position
of the `call` within a nested set of conditionals, so this pass
adds to each call a condition that determines whether the call
should actually be made.
This condition is the logical combination of tests from the nested
conditionals.

For example,
```scheme
(if e1
    (if e2
        (call e3)
        (assert e4 "oops"))
    (ttuple))
```
translates to, in effect:
```scheme
(call (and e1 e2) e3)
(assert
  (or
    (not
      (and e1
           (not e2)))
    e4)
  "oops")
```
The actual translation is more involved, since nontrivial expressions
can appear only on the right-hand-side of an assignment and since
the output language contains only one boolean operator, `select`.
Thus multiple new assignments of temporary values is generally
required.
For example, assuming a, b, c, d, and e are variable references:
```scheme
(if a
    (if (== b c)
        (call (+ d 2))
        (assert e "oops"))
    (ttuple))
```
might be translated to:
```scheme
(= t0 (== b c))
(= t1 (+ d 2))
(= t2 (select a t0 #f))    ; (and a t0), i.e., (and a (== b c))
(call t2 t1)
(= t3 (select t0 #f #t))   ; (not t0), i.e., (not (== b c))
(= t4 (select a t3 #f))    ; (and a t3), i.e., (and a (not (== b c)))
(= t5 (select t4 #f #t))   ; (not t4), i.e., (not (and a (not (== b c))))
(= t6 (select t5 #t e))    ; (or t5 e), i.e., (or (not (and a (not (== b c)))) e)
(assert t6 "oops")
```
The actual code typically contains extra temporaries because temporaries
representing both sides of each conditional are eagerly created to
keep the code for this pass simple.
The upcoming pass `optimize-circuit` eliminates bindings for these
temporaries if they turn out to be unnecessary, though in the long
run, we should determine whether the unnecessary bindings for
temporaries introduced by this pass cause enough compile-time
overhead to justify making this pass a bit more complicated and not
generate the extra temporaries.

Most of the work of this pass is performed by `Statement` and `Rhs`
processors.

#### Statement

`Statement` is initially called to process the body of a circuit.
It accept an input-language expression and produces a
sequence of output-language statements.
More precisely, `Statement` accepts three arguments:
* an input-language expression,
* an expression representing the nested set of tests controlling
the evaluation of the expression (the `controlling test`), and
* a list of statements that should follow the statements for the current
expression.
It returns one value, a list of statements starting with those
produced for the current expression and continuing with those that
follow.

For each `assert` expression, `Statement` produces an `assert`
statement with a new test representing the logical composition of
the controlling test and the `assert` expression's own test, using
the `Triv` helper (described later) to ensure that the resulting
test is trivial (i.e., a constant or variable reference).

For each `if` expression, `Statement` reduces the test to a trivial
expression then combines this with the controlling test to produce
new controlling tests for the two branches of the `if`.
Because in this context the value of the `if` expression is not used,
no `select` form is generated and added to list of statements as it
would be for an `if` expression that is used.

For each `let*` expression, `Statement` splices together the result
of calling the `Rhs` processor on each right-hand-side expression
to produce a sequence of statements creating the bindings of the
`let*`, and this sequence is added to the front of the result of
calling `Statement` recursively on the `let*` body.

`Statement` processes for each `seq` expression the result of
splicing together the statements produced for each `seq` subexpression.

Finally, `Statement` uses the `Triv` helper to transform any other
expression, which must represent a return value for the circuit, into
a single trivial expression representing this return value.

#### Rhs

`Rhs`, like `Statement`, converts expressions into sequences of
statements, but it always produces at the head of the list of
statements an assignment for the corresponding `let*` binding.
It accepts four arguments:
* an input-language expression,
* a controlling test,
* a bool? flag that says whether this expression's type is boolean, and
* a continuation `k`.
The continuation `k` accepts an output-language Rhs expression and
returns a list of statements with the requested assignment at its
head.
`Rhs` returns a list of statements.

`Rhs` handles `assert` in a manner similar to `Statement`, except
that it invokes `k` on the trivial value 0 to create the requested
assignment and following statements.

`Rhs` handles `seq` much as does `Statement` except that it
recursively invokes `Rhs` to process the last subexpression of
the `seq` expression.

`Rhs` also handles `if` much as does `Statement` except that it
produces a `select` statement to replace the `if` expression, which
it passes to `k`.
The `select` statement is labeled with the `bool?` flag mark it
as either boolean-valued or not boolean-valued for the benefit of
downstream passes.

`Rhs` uses `Triv` to convert the argument expressions of a `call`
into trivial expressions, then passes `k` the result of reconstructing
the call with the controlling test and the trivial argument
expressions.

`Rhs` handles variable references simply by passing `k` the variable
reference.

`Rhs` similarly handles most constants simply by passing `k` the constant.

`Rhs` uses `Triv` to convert the operands of operators such as
`+`, `==`, `new`, `elt-ref`, and `vector` into Trivial expressions,
then passes `k` the result of rebuilding the operator call with
these trivial expressions as its operands.

#### Triv

The `Triv` helper is responsible for binding temporaries when necessary
so that all operand and argument subexpressions are trivial.
It accepts an input-language expression, a controlling test, a `bool?` flag,
and a continuation `k`.
It returns a list of statements.
It borrows `Rhs` from `let*`, passing it the input-language expression,
controlling test, `bool?` flag, and a continuation `k^`.
When `Rhs` eventually invokes `k^` with a new Rhs expression, `k^` does
one of two things depending on whether the new Rhs expression is trivial.
If so, it merely passes `k` the new trivial Rhs expression.
If not, it generates a temporary and adds the result of assigning
that temporary to the Rhs expression to the front of the list
produced by passing `k` a reference to the temporary.

### flatten-datatypes (Lcircuit -> Lflattened)

This pass is responsible for making sure that every argument value, every
variable value, and every return value fits in a Field.

Existing Field values and types are left alone.

Each Boolean constant is converted into the Field value 0 or 1, and Boolean
types `(tboolean)` are converted to the bounded Field type `(tfield 1)`.

```text
circuit foo(b: Boolean, x: Field): Boolean {
  return true;
}
```

```scheme
(circuit %foo.0 ((%b.1 (tfield 1)) (%x.2 (tfield)))
  ((tfield 1))
  (1))
```

Bytes constants are chunked into sets of Field values in little-endian
order, with a whole number of bytes in each chunk.
The first chunk holds at least one of the bytes, and the remaining
chunks each hold the maximum number of bytes that fit in a Field.
Bytes types are chunked similarly so for any type `(tbyte n)` in the
output to the pass, n is less than or equal to the maximum number of
bytes that fit in a Field.
A single local variable or function parameter bound to a bytes value
in the input is bound to zero or more variables or parameters in the
output depending on the number of chunks required to represent the
type of the variable or parameter.
A single return value bound to a bytes value is similarly replaced by
zero or more values.
```text
circuit foo(a: Bytes<30>, b: Bytes<31>, c : Bytes<32>, d : Bytes<33>) : Bytes<40> {
  return '1234567890123456789012345678901234567890';
}
```
```scheme
(circuit %foo.0 (
      (%a.1 (tbytes 30))
      (%b.10 (tbytes 0)) (%b.9 (tbytes 31))
      (%c.8 (tbytes 1)) (%c.7 (tbytes 31))
      (%d.6 (tbytes 2)) (%d.5 (tbytes 31)))
    ((tbytes 9) (tbytes 31))
  (889566821702876541746 
   86908332635947936520937639616427602624961814622853568299663208045469708849))
```
The pass never produces a bytes value holding zero bytes or a type
`(tbyte 0)`; instead, `Bytes<0>` values and variables are effectively
eliminated.

Each tuple or vector type is also converted into a sequence of types, nominally
one per element, though since vector elements can also be tuples, vectors, structs,
or bytes, the actual number of elements might differ from the number
of elements.
For example, for a vector consisting of 10 empty bytes objects, the
sequence of types is empty.
More commonly, the sequence will be as long as or longer than the
vector length.
For example, for a vector consisting of 3 elements, each of
which requires two Fields to represent, the sequence will have 6
elements.
```text
circuit foo() : Vector<3, Vector<2, Field>> {
  return [[1, 2], [3, 4], [5, 6]];
}
```
```scheme
(circuit %foo.0
    ()
    ((tfield) (tfield) (tfield) (tfield) (tfield) (tfield))
  (1 2 3 4 5 6))
```
Because vector lengths can be arbitrary, the sequence can be arbitrarily
long, though because vector lengths are always known at compile
time, the sequence of output types can also always be constructed
at compile time.
This contraction or, more commonly, expansion of vector types means
that the number of function parameters, function return values, and
local variables might contract or expand as well.
For example, a function accepting or returning a vector consisting
of 10 bytes elements, each of which requires two Fields to represent
will accept 20 arguments or return 20 return values in place of the
original one.

### check-types/Lflattened (Lflattened -> Lflattened)

This pass type-checks programs in the `Lflattened` intermediate language.
It serves a similar purpose to and is run by the compiler in the same
manner as `check-types/Lnodca` and `check-types/Linlined`.
It can also be removed for production releases of the compiler if desired.

### optimize-circuit (Lflattened -> Lflattened)

This pass performs a set of optimizations that shorten and simplify
the code and potentially make the resulting circuit smaller and
easier to prove.
These optimizations include:

* copy propagation, e.g.,
```scheme
(= x 3), (= y x), (+ y 4) -> (= x 3), (= y x) (+ 3 4)
```
* constant folding, e.g.,
```scheme
(= a (+ 3 4)) -> (= a 7)
```
* partial folding, e.g.,
```scheme
(+ x 0) -> x
```
* unreferenced binding elimination, e.g.,
```scheme
(= x 3), (= y x), (+ 3 4) -> (+ 3 4)
```
```scheme
(= x (+ a b)), 7 -> 7
```
* common-subexpression elimination, e.g.:
```scheme
(= x (+ a b)), (= y (+ a b)), (= z (* x y)) -> (= x (+ a b)), (= z (* x x))
```
* special-case simplifications, e.g.,
```scheme
(select (select x 0 1) 0 1) -> x
```
```scheme
(select x x (select x 1 0)) -> 1
```
* elimination of asserts that are known to never fail, e.g.:
```scheme
(assert 1 "oops"), 5 -> 5
```
* elimination of calls that are known to never be enabled, e.g.:
```scheme
(=* (x) (call foo 0 a b)), 5 -> 5
```

Most of these optimizations can lead to opportunities for others, and this pass
is structured to take advantage of this potential cascading of optimization
without the need for additional runs of the pass.
For example, copy propagation always produces an unreferenced binding that
can be eliminated, useless code elimination can also produce unreferenced
bindings that can be eliminated, constant folding can lead to opportunities
for copy propagation, copy propagation and constant folding can lead to
asserts that can never fail, and common-subexpression elimination can lead to
opportunities for useless binding elimination, partial folding, and further
common-subexpression elimination.

`optimize-circuit` processes the statements in a circuit definition body first
from right-to-left (FWD) then reprocesses them from left-to-right (BWD).
The FWD phase populates a set of hashtables mapping variables to
trivial expressions, variables to nontrivial but pure expressions, and
nontrivial but pure expressions to variables.
The FWD phase uses the information in this hashtable to propagate copies,
perform common subexpression elimination, perform special-case simplifications,
and eliminate asserts that can never fail.
The FWD phase also does constant folding and partial folding.

The BWD phase populates an additional hashtable that records for each
variable whether it is referenced in the final output code.
It uses this information to eliminate bindings of unreferenced variables
to pure expressions.
In dropping pure expressions, it might prevent some variables that appear
in the dropped expressions from being marked referenced and hence lead to
additional dropped bindings.
A binding for any call whose condition is (or optimizes to) 0 is dropped.
In this case, none of the variables should be referenced, and the pass
verifies this.
Bindings for other calls are left intact even if some or even all
of the bound variables are unreferenced, because calls might lead to
side effects (e.g., failing asserts) and cannot be eliminated.

### print-Lflattened (Lflattened -> Lflattened)

This pass merely prints an `Lflattened` program in a more human readable
style and serves both to allow programmers to understand the final output
of the compiler more readily and also as an example for how similar
passes could be written to produce output in some other language, e.g.,
a language for proving circuits.
The pass must process every form in the input language but, even so,
there is nothing complicated about it.

### print-zkir (Lflattened -> Lflattened)

This pass prints zkir code equivalent to the input Lflattened program.

## Generated TypeScript/JavaScript structure

The Compact compiler is unusual in that generates code at two levels:
application-level code for programming applications and circuit-level
code for proving and verifying contracts.

This section describes the structure of former, which is essentially
TypeScript code split into its constituent parts, a 
TypeScript declaration (`.d.ts`) file and a JavaScript implementation
(`.js`) file.
We have three reasons for preferring this structure over what would almost
be an equivalent TypeScript (`.ts`) file:

1. The JavaScript file can be consumed directly by a JavaScript implementation,
   with no need to involve TypeScript compilation.
2. The split allows TypeScript to perform complete compile time checks
   when given the opportunity while allowing the JavaScript implementation
   code to perform run-time checks that are not possible at the TypeScript
   level without giving up some TypeScript type checking.  To be precise,
   it allows the TypeScript code to declare the expected number and types
   of arguments to a Compact circuit, while also allowing the JavaScript code
   to verify that the expected number and types of arguments were actually
   received.
3. By producing JavaScript directly, the compiler can (and does) also produce
   a source-map (`.map`) file for use in debugging.  If we left this up to
   the TypeScript compiler to produce from generated TypeScript code, the
   "source" references would be to the generated TypeScript code rather than
   to the Compact source code.

The structure is described by means of the code generated for the example
program `examples/tiny.compact`, reproduced below stripped of its comments:

```
export {Maybe}
export {set, get, clear}

import CompactStandardLibrary;

enum STATE { unset, set }

  export ledger authority: Bytes<32>;
  export ledger value: Field;
  export ledger  state: STATE;
constructor(value: Field) {
  const sk = private$secret_key();
  authority = public_key(sk);
  value = value;
  state = STATE.set;
}

witness private$secret_key(): Bytes<32>;

circuit set(new_value: Field): [] {
  assert state == STATE.unset "set: attempted to overwrite recorded value";
  const sk = private$secret_key();
  const apk = public_key(sk);
  authority = apk;
  value = new_value;
  state = STATE.set;
}

circuit get(): Maybe<Field> {
  return state == STATE.set ? some<Field>(value) : none<Field>();
}

circuit clear(): [] {
  assert state == STATE.set "clear: no value is currently recorded";
  const sk = private$secret_key();
  const apk = public_key(sk);
  assert apk == authority "clear: attempted clear without proper authorization";
  authority = default<Bytes<32>>;
  value = default<Field>;
  state = STATE.unset;
}

circuit public_key(sk: Bytes<32>): Bytes<32> {
  return persistent_hash(pad(32, "lares:tiny:pk:"), sk);
}
```

For this program, the compiler produces the following TypeScript declaration
(`.d.ts`) file:

```
import type * as __compactRuntime from '@midnight-ntwrk/compact-runtime';

export type Maybe<a> = { is_some: boolean; value: a };

export interface Witnesses {
  private$secret_key(): Uint8Array;
}

export type Circuits = {
  set(value: bigint): [];
  get(): Maybe<bigint>;
  clear(): [];
};

export declare class Contract<W extends Witnesses = Witnesses> {
  publicState: __compactRuntime.ContractState;
  witnesses: W;
  circuits: Circuits;
  constructor(witnesses: W, value: bigint);
  finalize(): __compactRuntime.Transcript;
}
```

The structure of every `.d.ts` file produced by the Compact compiler is similar:

1. The first, `import` line is standard boilerplate to connect with the runtime.
2. Declarations of exported types, in this case `Maybe`, come next.
3. A declaration of the `Witness` interface with one entry for each witness that
   is both declared and used by the Compact input program, in this case
   just `private$secrete_key`.
4. A declaration of the `Circuits` types, with one entry for each circuit exported
   by the Compact input program, in this case `set`, `get`, and `clear`.
5. A declaration of the `Contract` class.

The `Contract` class always declares the five fields shown in the example:

* `publicState` holds the public state of the contract, which is of a
  type declared by the run time;
* `witnesses` holds the witnesses, which is generally an extension of
  the Witnesses type, i.e., it can contain witness functions not used
  by the code and/or state variables;
* `circuits` holds an instance of the `Circuits` class;
* `constructor` holds the class constructor, the first argument of
  which is always the witnesses and the remainder of which are those
  the ledger constructor in the input Compact program is declared to
  take, in this case `value`.
* `finalize`, a function that the run time calls to finalize a
  transaction.

The compiler also produces a JavaScript implementation (`.js`) file, which we
will take in parts.

The first part imports the run time and verifies that the compiler's idea of
version and maximum field value are in sync with the run time's.

```
'use strict';
const __compactRuntime = require('@midnight-ntwrk/compact-runtime');
if (__compactRuntime.versionString !== '0.3.0-a5f2494')
  throw new __compactRuntime.CompactError(`Version mismatch: compiled code expects '0.3.0-a5f2494', runtime is ${__compactRuntime.versionString}`);
{ const MAX_FIELD = 115792089237316195423570985008687907853269984665640564039457584007913129639747n;
  if (__compactRuntime.MAX_FIELD !== MAX_FIELD)
     throw new __compactRuntime.CompactError(`compiler thinks maximum field value is ${MAX_FIELD}; run time thinks it is ${__compactRuntime.MAX_FIELD}`)
}
```

The next part creates type descriptors used to convert between Compact values and
Ledger values.


```
const _descriptor_0 = new __compactRuntime.CompactTypeEnum(1, 1);

const _descriptor_1 = new __compactRuntime.CompactTypeField();

const _descriptor_2 = new __compactRuntime.CompactTypeBytes(32);
```

The fourth and final part defines the `Contract` class.

```
class Contract {
```

We'll consider the parts of the `Contract` class in turn.  Along the way, we'll
see the how the five public components of the `Contract` class are created, along
with a number of private instance variables and methods that support them.

The first part of the `Contract` class defines the instance variables used by
a contract instance, and in the case of `witnesses`, accessible outside of the
instance.

```
  witnesses;
  #context;
  #transcript;
```

The second defines the `Contract` constructor, which is defined with
a rest interface to that the constructor can verify that the expected
number of arguments has been received, which JavaScript does not verify.
The use of a rest interface here does not interfere with TypeScript's
ability to verify at compile time the number and types of the arguments
passed into the constructor from TypeScript consumers, since TypeScript
has access to the TypeScript declaration (`.d.ts`) file shown earlier.
In this way, we get compile-time type checking when possible and run-time
type checking for cases where compile-time checking is inhibited for
whatever reason.


```
  constructor(...args) {
```

The first several lines of the constructor extract the arguments from the
rest argument and verify that the constructor has received the expected
number and types of arguments.

```
    if (args.length !== 2)
      throw new __compactRuntime.CompactError(`Contract constructor: expected 2 arguments, received ${args.length}`);
    const witnesses = args[0];
    const value = args[1];
    if (typeof(witnesses) !== 'object')
      throw new __compactRuntime.CompactError('first (witnesses) argument to Contract constructor is not an object');
    if (typeof(witnesses.private$secret_key) !== 'function')
      throw new __compactRuntime.CompactError('first (witnesses) argument to Contract constructor does not contain a function-valued field named private$secret_key');
    if (!(typeof(value) === 'bigint' && value >= 0 && value <= __compactRuntime.MAX_FIELD))
      __compactRuntime.type_error('Contract constructor',
                                  'argument 1',
                                  'tiny.compact line 12, char 3',
                                  'Field',
                                  value)
    this.witnesses = witnesses;
```

The next several lines allocate and the public state and initialize its fields to
null values, using the descriptors defined earlier to convert the Compact values to
ledger values.


```
    const state = new __compactRuntime.ContractState();
    state.setField('authority',
                   __compactRuntime.AdtState.freshCell(_descriptor_2.toValue(new Uint8Array(32))));
    state.setField('value',
                   __compactRuntime.AdtState.freshCell(_descriptor_1.toValue(0n)));
    state.setField('state',
                   __compactRuntime.AdtState.freshCell(_descriptor_0.toValue(0)));
    this.#context = new __compactRuntime.QueryContext(state, new Uint8Array(32));
    this.#transcript = [];
```

The next part of the `Contract` constructor are generated from the source-code
ledger constructor.  We see our first call to a witness, by way of the wrapper
function `_private$secret_key_0`, and queries to set perform application-specific
initialization of the fields of the ledger.
Any transcript created during initialization is discarded.

```
    const sk = this.#_private$secret_key_0();
    this.#query({ query: 'write',
                  field: 'authority',
                  valueType: _descriptor_2.alignment() },
                _descriptor_2.toValue(this.#_public_key_0(sk)));
    this.#query({ query: 'write',
                  field: 'value',
                  valueType: _descriptor_1.alignment() },
                _descriptor_1.toValue(value));
    this.#query({ query: 'write',
                  field: 'state',
                  valueType: _descriptor_0.alignment() },
                _descriptor_0.toValue(1));
    this.#transcript = [];
```

The next part of the `Contract` constructor creates the `circuits` object with
it's three fields (in this case) implementing the three exported circuits in the
Compact source file.
Each is a wrapper that simply checks the number and types of its arguments
before deferring to a private helper to do the actual work of the circuit.
Structuring the code in this manner has a couple of benefits:
* argument count and type verification is performed only on entry from outside,
  and not when one Compact circuit calls another, which is guaranteed to be safe
  by the Compact type checker.
* the original names of Compact circuits appear in the target code only as method names,
  thus avoiding the potential for name conflicts with other parts of the generated
  code.

```
    this.circuits = {
      set: (...args_0) => {
        if (args_0.length !== 1)
          throw new __compactRuntime.CompactError(`set: expected 1 argument, received ${args_0.length}`);
        const value_0 = args_0[0];
        if (!(typeof(value_0) === 'bigint' && value_0 >= 0 && value_0 <= __compactRuntime.MAX_FIELD))
          __compactRuntime.type_error('set',
                                      'argument 1',
                                      'tiny.compact line 22, char 1',
                                      'Field',
                                      value_0)
        return this._set_0(value_0);
      },
      get: (...args_0) => {
        if (args_0.length !== 0)
          throw new __compactRuntime.CompactError(`get: expected 0 arguments, received ${args_0.length}`);
        return this._get_0();
      },
      clear: (...args_0) => {
        if (args_0.length !== 0)
          throw new __compactRuntime.CompactError(`clear: expected 0 arguments, received ${args_0.length}`);
        return this._clear_0();
      }
    }
  }
```

We have reached the end of the `Contract` constructor and continue to discuss
the remainder of the `Contract` class.

The next few lines are boilerplate code appearing in every `Contract` and define
a getter and setter for the public state.

```
  get publicState() {
      return this.#context.state;
  }
  set publicState(state) {
      this.#context = new __compactRuntime.QueryContext(state, new Uint8Array(32));
  }
```

The next part of the `Contract` class implement the circuits defined in the Compact
source file (or, in the case of `some`, `none`, and `persistent_hash`, in the included
file `std.compact`).
This includes the actual implementations of the exported circuits whose wrappers
are defined in the `circuits` object.
For the most part, the code is effectively a straightforward translation of the source-code
circuit definitions.
Of note, however, is the definition of `_private$secret_key_0`, which is a wrapper for
the `private$secret_key` witness.
Similarly to wrappers for external circuits in the `circuit` object, each of which
which check its argument types, each wrapper for a witness checks its return type.

```
  _some_0(value) { return { is_some: true, value: value }; }
  _none_0() { return { is_some: false, value: 0n }; }
  _persistent_hash_0(x, y) {
    return _descriptor_2.fromValue(__compactRuntime.persistentHash(_descriptor_2.toValue(x),
                                                                  _descriptor_2.toValue(y)));
  }
  _private$secret_key_0() {
    const result = this.witnesses.private$secret_key();
    if (!(result.buffer instanceof ArrayBuffer && result.BYTES_PER_ELEMENT === 1 && result.length === 32))
      __compactRuntime.type_error('private$secret_key',
                                  'return value',
                                  'tiny.compact line 20, char 1',
                                  'Bytes<32>',
                                  result)
    return result;
  }
  _set_0(value) {
    __compactRuntime.assert(_descriptor_0.fromValue(this.#query({ query: 'read',
                                                                 field: 'state',
                                                                 valueType: _descriptor_0.alignment() },
                                                               []).value)
                           ===
                           0,
                           'set: attempted to overwrite recorded value');
    const sk = this._private$secret_key_0();
    const apk = this._public_key_0(sk);
    this.#query({ query: 'write',
                  field: 'authority',
                  valueType: _descriptor_2.alignment() },
                _descriptor_2.toValue(apk));
    this.#query({ query: 'write',
                  field: 'value',
                  valueType: _descriptor_1.alignment() },
                _descriptor_1.toValue(value));
    this.#query({ query: 'write',
                  field: 'state',
                  valueType: _descriptor_0.alignment() },
                _descriptor_0.toValue(1));
  }
  _get_0() {
    if (_descriptor_0.fromValue(this.#query({ query: 'read',
                                              field: 'state',
                                              valueType: _descriptor_0.alignment() },
                                            []).value)
        ===
        1)
    {
      return this._some_0(_descriptor_1.fromValue(this.#query({ query: 'read',
                                                                field: 'value',
                                                                valueType: _descriptor_1.alignment() },
                                                              []).value));
    } else {
      return this._none_0();
    }
  }
  _clear_0() {
    __compactRuntime.assert(_descriptor_0.fromValue(this.#query({ query: 'read',
                                                                 field: 'state',
                                                                 valueType: _descriptor_0.alignment() },
                                                               []).value)
                           ===
                           1,
                           'clear: no value is currently recorded');
    const sk = this._private$secret_key_0();
    const apk = this._public_key_0(sk);
    __compactRuntime.assert(this.#_equal_0(apk,
                                          _descriptor_2.fromValue(this.#query({ query: 'read',
                                                                                field: 'authority',
                                                                                valueType: _descriptor_2.alignment() },
                                                                              []).value)),
                           'clear: attempted clear without proper authorization');
    this.#query({ query: 'write',
                  field: 'authority',
                  valueType: _descriptor_2.alignment() },
                _descriptor_2.toValue(new Uint8Array(32)));
    this.#query({ query: 'write',
                  field: 'value',
                  valueType: _descriptor_1.alignment() },
                _descriptor_1.toValue(0n));
    this.#query({ query: 'write',
                  field: 'state',
                  valueType: _descriptor_0.alignment() },
                _descriptor_0.toValue(0));
  }
  _public_key_0(sk) {
    return this._persistent_hash_0(new Uint8Array([108, 97, 114, 101, 115, 58, 116, 105, 110, 121, 58, 112, 107, 58, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
                                    sk);
  }
```

The penultimate part of the `Contract` class defines helpers the compiler generates to
implement `map` and `fold` operators and to implement `==` on nested structures.


```
  _equal_0(x0, y0) {
    if (!x0.every((x, i) => y0[i] === x)) return false;
    return true;
  }
```

The last few lines of the `Contract` class are boilerplate code appearing
in every `Contract` and define the private `query` operator the public
`finalize` operator.


```
  #query(ty, args) {
    const res = this.#context.query(ty, args);
    this.#context = res[0];
    this.#transcript.push([ty, args, [...res[1].value]]);
    return res[1];
  }
  finalize() {
    const res = this.#transcript;
    this.#transcript = [];
    return res;
  }
}
```

And finally, the last few lines of the generated JavaScript implementation
file establish `Contract` as the single export and record the name of
the generated source-map file.

```
exports.Contract = Contract;
//# sourceMappingURL=index.js.map
```
