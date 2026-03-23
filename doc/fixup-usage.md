Compact Fixup Manual Page
============================

NAME
====

fixup-compact

OVERVIEW
========

The Compact fixup takes as input a Compact source program in a specified source
file, attempts to update it to account for recent changes in the Compact
language, formats it, and writes the updated and reformatted program to a
specified file.  If such a file is not specified, it writes the updated and
formatted prgram to standard output.

SYNOPSYS
========

**fixup-compact** _flag_ **...**... _sourcepath_ _targetpath_

DESCRIPTION
===========

The flags _flag_ **...** are optional.  They are described under FLAGS later in
this document.

_sourcepath_ should identify a file containing a Compact source program, and
_targetpath_ should identify an existing target file in which the updated and 
formatted program is to be written.  _targetpath_ may be an existing file, in
which case the file will be replaced with the formatted program.  _targetpath_
may be the same as _sourcepath_,  in which case the source program is replaced
with the updated and reformatted equivalent.  Though we recommend that you
direct the output to a different file and compare it with the original, to
verify that the changes make sense. 

FLAGS
=====

The following flags, if present, affect the fixup tool's behavior as follows:

**--help**

prints help text and exits.

**--version**

prints the compiler version and exits.

**--language-version**

prints the language version and exits.

**--vscode**

causes error messages to be printed on a single line so they are rendered
properly within the VS Code extension for Compact.

EXAMPLES
========

Assuming **src/test.compact** contains a well-formed Compact program

```
fixup-compact src/test.compact
```

prints the updated and formatted program of **src/test.compact** to standard
output.

Assuming that **fixed** is an existing directory

```
fixup-compact src/test.compact fixed/test.compact
```

writes the updated and formatted program to **fixed/test.compact**.  If the
**fixed** directory does not exist the fixup tool complains that it cannot
create the output file.

Alternatively, 

```
fixup-compact src/test.compact src/test.compact
```

rewrites the updated and formatted program to **src/test.compact**.

Assuming **src/test.compact** contains an ill-formed Compact program

```
fixup-compact src/test.compact
```

throws an exception with the error that causes the Compact program in 
**src/test.compact** not to compile.
