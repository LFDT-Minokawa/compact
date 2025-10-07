# Formal Specification of Compact 

This directory contains the formal specification of the Compact
language, written in Agda.


## Build Instructions 

Instructions for how to check and build the specification as well as
the syntax generation tool locally are outlined below. 

### Checking the Agda spec 

The specification has been developed using the latest version of Agda
(see https://agda.readthedocs.io/):

```
% agda --version
Agda version 2.7.0.1
```

Instructions for installing Agda can be found here:
https://agda.readthedocs.io/en/v2.7.0.1/getting-started/installation.html.

NOTE: While installation through package managers such as apt or
Homebrew is possible, they tend to keep older versions of Agda. Given
Agda’s lax attitude towards backward compatibility, it is likely that
the spec will NOT typecheck with older versions of Agda. Install Agda
using cabal to avoid this problem.

To typecheck the specification, run the following command from within
the directory specification:

```
% agda -v 2 src/Overview.agda
<OUTPUT> 
```

The flag `-v 2` runs the compiler with verbosity level 2, such that
the compiler outputs some info about which modules (and dependencies)
it is checking. Remove (or adjust to 1) to suppress this output.

The specification depends on several libraries, as specified in the
file specification/.agda-lib (below). These must be installed before
the specification can be checked.

```
name: compact-specification
depend:
  standard-library
  standard-library-classes
  iog-prelude
include: src
```

Agda’s standard library is maintained by its community, and can be
found (alongside installation instructions) here:
https://github.com/agda/agda-stdlib.

The standard-library-classes and iog-prelude libraries are maintained
internally by IOG’s Formal Methods division, and can be found in the
following locations:

standard-libary-classes: https://github.com/agda/agda-stdlib-classes
iog-prelude: https://github.com/input-output-hk/iog-agda-prelude

For details on library management in Agda, check out the following
page of Agda’s documentation: Library Management — Agda 2.7.0.1
documentation.

### Compiling the transpilation tool 

The Haskell tool that generates the Agdas definition of the compiler’s
internal syntax is kept in the directory
specification/syntax-generation. To build the tool requires the
following versions of GHC (https://www.haskell.org/ghc/) and Cabal
(https://www.haskell.org/cabal/):

```
% cabal --version
cabal-install version 3.10.3.0
compiled using version 3.10.3.0 of the Cabal library
```

```
% ghc --version
The Glorious Glasgow Haskell Compilation System, version 9.4.8
```

NB: this is not the latest version of GHC. Some packages it depends on
are not compatible with the newest releases. I recommend using GHCup
(https://www.haskell.org/ghcup/) for managing GHC installs.

To compile the tool, run

```
% cabal build 
<OUTPUT> 
```

from within the directory: `specification/syntax-generation`.


### Syntax Transpilation 

We force synchronization between the compiler's internal definition of
the language and the specification in a 2-step process. First, we
generate an (untyped) syntax definition in Agda from the compiler, for
which we then employ some reflection in Agda to ensure that the typing
relations we define for this syntax adequatly cover the extracted
syntax.

Extracting the compiler's internal syntax to Agda proceeds as follows:

A small scheme snippet (not part of this PR) converts the desired
Nanopass IR to an S-expression, and serializes it to a JSON format
(examples under `src/Syntax/json/`).  The Haskell tool (IR.hs)
consumes this (serialized) S-expression, and converts it to an
internal representation of the grammar.  This internal representation
is then output as an Agda file containing several mutually-recursive
data types (examples under src/Syntax/Generated).

The final generated Agda file then serves as the foundation of the
static semantic spec. As part of the formal spec, we employ the
meta-program defined in src/Semantics/Static/Coverage.agda to ensure
that the defined typing relations adequately cover all parts of the
generated syntax.

The syntax generation process, as well as automatic specification
checking can and should be an (optional) part of the compiler
build. This will be part of a separate PR.  Formal Spec

## Formal Spec

The formal spec itself only consists of 3 relevant files:

1. `src/Syntax/Generated/Lsrc.agda`, containing the
   automatically-generated Agda representation of the compiler's
   internal syntax,

2. `src/Semantics/Static/Lsrc-Typing`.lagda.md, containing a static
   semantic specification of all type-level objects in Compact, 

3. `src/Semantics/Static/Lsrc.lagda.md`, containing a static semantic
   specification of all term-level objects in Compact.

Additionally, the specification relies on Agda's standard library and
several other internal libraries maintained withing IOG formal
methods. If you're intending to try and check the spec yourself (which
I think would be awesome), do let me know if you struggle with these
dependencies or need help otherwise.

We inherit the name Lsrc from the implementation of compactc, it is
the first intermediate representation that the compiler operates on,
i.e., the source program without any transformations applied.

Both Agda files contain some prose to go along with the definitions
(which I imagine are somewhat dense and technical if you're not
accustomed to reading Agda). Still they are both quite big so we could
consider factoring some definitions out into separate files.  What
Next?

# #What's Next? 

The spec is not a 100% finished (you'll find many todo's littered
throughout). These will have to be addressed over time, though I
believe none of them will fundamentally (or even substantially) change
the specification.

I would like merge this PR and develop the build automation in
parallel, in order to achieve automated synchronization as soon as
possible, in light of the quick evolution of Compact.# Static Semantic
Specification
