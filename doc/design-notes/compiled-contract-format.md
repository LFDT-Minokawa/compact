---
Title: Compiling Compact to a Portable Format
Last Meaningful Update: 17 November 2026
---

These notes capture conversations and decisions about compiling
Compact into the artifacts needed by a capsule runtime, as well as
other standardized intermediate forms.

## Design Question: "How compiled" is the executable format?

The capsule runtime specification (not yet written at this time)
requires a compiled form for Compact programs.  That form should be
the same for all implementations of the capsule runtime spec,
regardless of the runtime's implementation language.  Therefore, it is
no longer viable to compile Compact into JavaScript as the only (or
even primary) representation for execution.  Instead, there must be
some format that can be interpreted or further compiled for a variety
of execution environments, including web browsers, mobile devices, and
other hosting substrates.

Some members of the Compact team gathered to discuss this question on
22 October 2026 in Ibiza.

At first, the decision was leaning towards compiling Compact down to
the compiler's internal `Lnodisclose` language, *before the fork
between its current output targets* (ZKIR and JavaScript).  The
implication was that, by distributing compiled Compact programs in
this single intermediate format, it would be possible both to generate
ZKIR and to execute (or further compile) the programs, without having
committed to anything like our current JavaScript-focused final
representations.

As we continued to discuss the implications of following this path, it
became evident that it was the wrong decision to make, for two
reasons.

1. Good intermediate representations and good interpretation formats
   are **not** the same thing.  A good intermediate representation for
   compiled contracts might serve as a compilation target for not only
   Compact, but also for other experimental languages for smart
   contracts, also usable on the Midnight platform.  A good format for
   interpretation, on the other hand, combines compactness (for
   efficient distribution of the compiled code) with properties that
   make it relatively easy to implement a performant execution engine.
   
   Examples abound of systems that have confused the differing goals
   of these formats.  For example, JVM bytecode was designed as an
   interpretation format.  Compiled Java class files take up little
   space, and a simple JVM can execute the bytecode efficiently.
   Implementers of other programming languages have discovered,
   however, that compiling their languages for the JVM requires their
   compilers to replicate parts of the internal logic of the Java
   compiler.  Furthermore, tools that analyze JVM bytecode must first
   "decompile" it to a higher level to recover some of what has been
   compiled away already.
   
   The flip-side of the confusion is apparent when a language
   ecosystem chooses a good general intermediate representation as its
   execution format for virtual machines and the like.  In this case,
   the higher-level tooling is easy, and multiple languages can target
   the format, but simple interpreters must repeatedly recompute
   information that a compile could already have incorporated into a
   lower-level format.  Smarter execution engines compile the format
   into a lower-level form before running it, but every good
   implementation must replicate that work.
   
2. The other main outputs from compiling a Compact program, in
   addition to an artifact that allows the program's logic to be
   executed locally, are artifacts related to ZK proofs.  Each of the
   program's entry points that manipulates public state on a Midnight
   blockchain must be compiled into a representation of a logical
   *circuit*, for which proving and verifying keys are generated.  The
   lower-level aspects of the circuit-to-proof compilation are
   developed separately from the rest of the Compact compiler and
   delivered by a Midnight cryptography team.  The intermediate
   representation (IR) of compiled circuits that is used for input to
   these tools is called ZKIR.  ZKIR is jointly designed by the
   Compact maintainers and the Midnight cryptography team.
   
   If Compact programs were to be compiled into an intermediate
   representation just after `Lnodisclose`, it's true that each
   implementation of the capsule runtime could generate ZKIR from it,
   *but that would be bad*.  Each capsule runtime would need to
   replicate the ZKIR-generation logic in such a way that every
   implementation produced identical output.  Otherwise, the proving
   and verification keys for the different implementations would not
   match, even for the same Compact code and the same Compact
   compiler.
   
For these reasons, it is *better for the standard Compact compiler to
produce a pair of outputs*, as it does now: an executable
representation and the matching ZKIR.  This pair is what should be
distributed to be downloaded by implementations of the capsule
runtime.  Using the ZKIR that the Compact compiler has already
produced, each implementation of the capsule runtime will yield the
same ZK keys and produce proofs that will be accepted by the Midnight
blockchain.

With this decision, implementations of the capsule runtime are able to
omit a ZKIR compiler.

The other output, the executable format, should be portable in the
usual sense of defining a virtual machine for its execution
environment.  It should not assume that virtual machine is implemented
in any particular programming language or that it runs in a specific
context, such as a web browser.

Choosing this kind of format for distributing compiled contracts and
running them in capsules leaves unaddressed the need for a general
intermediate representation for compiled Midnight contracts.  It may
still be valuable to standardize a text or binary format at about the
level of `Lnodisclose` for use by tools that analyze Compact programs
and as a compilation target for implementations of other contract
languages that target Midnight.

These decisions leave work to be done:
- Design the combination of the capsule VM and its input programs, and
  publish their specifications.
- Design the exact packaging format for distributing the preceding
  programs and their matching ZKIR artifacts, and publish this
  specification.
- Design the external format for the general mid-level intermediate
  representation, allowing it to be written and read by the Compact
  compiler.  (Lower priority and not a prerequisite for other work
  described here.)
  
## Design Question: When are Impact/Redact operations expanded?

At the time of this writing, ledger operations (both read and write)
are left embedded in the compiled code until quite late in the
compiler pipeline(s).  For example, the final phases of the compiler use
hand-coded Impact implementations of each ledger operation.

Instead, *ledger operations should be expanded into Impact earlier*,
perhaps even prior to disclosure analysis.

Question:
- Should all data that goes into the Impact code be treated as
  publicly visible and require explicit disclosure?
  
Alternatively, expansion could happen just after disclosure analysis
if some well-known ledger operations use inputs in ways that are known
not to reveal secrets.

In any case, two new developments are affected by decisions in this
area.  First, with the planned addition of user-defined ledger types,
expressed in a slightly higher-level language than raw Impact (so that
ADTs can be implemented in terms of named variables, instead of stack
locations), the user-provided ledger operations should be compiled
into Impact at the same stage where any predefined ledger ADT
operations are expanded.

Second, local state operations are to be expressed in a state-update
language Redact, somewhat parallel to Impact.  In reality, it may be
more parallel to the higher-level-than-Impact language in which user
can implement their own ledger ADTs.  Regardless, these local state
operations should be expanded at the same stage as the Impact code.

As a result, the executable format for compiled contracts includes
embedded chunks of Impact and Redact instructions, not calls to ledger
or local ADT operations.

If a general intermediate representation for partially compiled
contracts is made available (distinct from the lower-level executable
format), it may be desirable for it to be *earlier* in the compiler
pipeline than the expansion of Impact/Redact code.  This would allow
alternative compilers to generate calls to known ADTs and to benefit
from the Compact back-end's own ADT expansion passes.  For analysis
tools, it might allow them to avoid detailed analysis of Impact code
(although they may still have to cope with user-defined ledger and
local ADTs).
