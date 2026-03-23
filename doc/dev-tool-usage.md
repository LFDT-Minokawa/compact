Compact Command-Line Tool Manual Page
============================

NAME
====

Compact command-line tool

OVERVIEW
========

The Compact command-line tool provides a set of utilities for Compact smart
contract development.

SYNOPSYS
========

**compact** _options_ **...**
**compact** _command_ _options_ **..**

DESCRIPTION
===========

The options _options_ are optional. They are described under OPTIONS later in
this document.

The Compact command-line tool takes a _command_. This command is the program
that the tool runs. Supporting commands are listed below and the more
complicated ones are explained in details under the command name:

**check**

Checks for updates with the remote server and exits.

**update**

Updates to the latest or a specific version of the Compact toolchain and exits.

**compile**

Compiles a Compact source code, potentially by using a specific version of the
compiler and exits.

**format**

Formats compact files and exits.

**fixup**

Applies fixup transformations to compact files and exits.

**list**

Lists available compact versions and exits.

**clean**

Removes all compact versions and exits.

**self**

Commands for managing the compact tool itself.

**help**

Prints the help of the command-line tool or the given subcommand(s) and exits.

OPTIONS 
=======

The following options are available for all commands, and if present, they
affect the tool's behavior as follows:

**--directory _directorypath_**

Sets the compact artifact directory and exits.

By default this will be `$HOME/.compact`. The directory will be created if it
does not exist. This can also be configured via an environment variable.
          
[env: COMPACT_DIRECTORY=]
[default: /Users/username/.compact]

**--help**

Prints help (see a summary with '-h') and exits.

**--version**

Prints version and exits.

CHECK
=====

Synopsys: **compact** **check** _option_

This command checks for updates of the Compact toolchain on the remote server. 

Assuming there are not versions of the Compact toolchain installed running

```
compact check
```

results in

```
compact: no version installed.
compact: Latest version available: 0.28.0.
```

where **0.28.0** is the latest available Compact toolchain version on the remote
server. 

However, assuming that the previous version of the Compact toolchain is
installed running

```
compact check
```

results in 

```
compact: aarch64-darwin -- Update Available -- 0.26.0
compact: Latest version available: 0.28.0.
```

where **0.26.0** is the installed version and **0.28.0** is the latest available
version of the Compact toolchain. The command **update** can be used to update
to this version. **aarch64-darwin** spits out the chosen binary of the Compact
toolchain for your machine's architecture.

The options in OPTIONS can be used with this command. **--directory
_directorypath_** and **--version** behave the same as not using a command
(**compact-check** does not have a different version than **compact**), but
**--help** prints the help text for this command and not **compact**.

UPDATE
======

Synopsys: **compact** **update** _option_ _compactversion_

This command updates to the latest version of the Compact toolchain if no
version is specified, otherwise, it updates to the specified version of the
Compact toolchain _compactversion_.

Upon switching from one version to another, by default this command switches the
default compiler version to the installed one. This can be overwritten by
**--no-set-default** option.

If the compiler was already downloaded it is not downloaded again.

Options: **--no-set-default**
         Doesn't set the newly installed compiler the default one

Assuming the lastest Compact toolchain on the remote server is **0.28.0** and
the last time you updated your Compact toolchain was to **0.26.0** running

```
compact update
```

results in

```
compact: aarch64-darwin -- 0.28.0 -- installed
compact: aarch64-darwin -- 0.28.0 -- default.
```

Now after updating to the latest version running

```
compact update
```

results in 

```
compact: aarch64-darwin -- 0.28.0 -- already installed
compact: aarch64-darwin -- 0.28.0 -- default.
```

However, running 

```
compact update --no-set-default 
```

results in

```
compact: aarch64-darwin -- 0.28.0 -- already installed
```

Now switching to an older version can be achieved by running

```
compact update 0.26.0
```

which results in

```
compact: aarch64-darwin -- 0.26.0 -- already installed
compact: aarch64-darwin -- 0.26.0 -- default.
```

But the default can stay unchanged by running

```
compact update --no-set-default 0.26.0
```

which results in

```
compact: aarch64-darwin -- 0.26.0 -- already installed
```

The options in OPTIONS can be used with this command. **--directory
_directorypath_** and **--version** behave the same as not using a command
(**compact-update** does not have a different version than **compact**), but
**--help** prints the help text for this command and not **compact**.

COMPILE
=======

Synopsys: **compact** **compile** _+version_ _option_ _sourcepath_ _targetpath_

This command compiles the Compact source program in _sourcepath_ using the
specified Compact toolchain version _version_ if it exits. If a version is not
specified the defualt version of the Compact toolchain installed is picked. The
_option_ can be one of the flags accepted by the Compact compiler and the
_targetpath_ specifies the target directory for the outputs of the compiler.
Visit [the compiler usepage](compiler-usage.md) for a more detailed explanation
of how to use it.

The options in OPTIONS can be used with this command. **--directory
_directorypath_** behaves the same as not using a command, but **--version**
prints the version of the Compact toolchain and not of **compact** and
**--help** prints the help text for this command and not **compact**.
`compact compile --help` takes the help text from the compiler directly.

FORMAT
======

Synopsys: **compact** **format** _option_ _files_

The options in OPTIONS can be used with this command. **--directory
_directorypath_** behaves the same as not using a command, but **--version**
prints the version of the Compact toolchain and not of **compact** and
**--help** prints the help text for this command and not **compact**, however,
`compact format --help` does not take the help text from the formatter tool.

FIXUP
=====

Synopsys: **compact** **fixup** _option_ _files_

The options in OPTIONS can be used with this command. **--directory
_directorypath_** behaves the same as not using a command, but **--version**
prints the version of the Compact toolchain and not of **compact** and
**--help** prints the help text for this command and not **compact**, however,
`compact fixup --help` does not take the help text from the fixup tool.

LIST
====

Synopsys: **compact** **list** _option_

This command lists available Compact toolchain versions on the remote server if
no option is set, otherwise, it lists the locally installed versions of the
Compact toolchain when the **--installed** option is set.

Assuming that the latest available Compact toolchain version is **0.28.0** on
the remote server running 

```
compact list
```

results in

```
compact: available versions

→ 0.28.0 - x86_macos, aarch64_macos, x86_linux
  0.26.0 - x86_macos, aarch64_macos, x86_linux
  0.25.0 - x86_macos, aarch64_macos, x86_linux
  0.24.0 - x86_macos, aarch64_macos, x86_linux
  0.23.0 - aarch64_macos, x86_linux
  0.22.0 - x86_macos, x86_linux
```

Assuming that locally versions **0.26.0** and **0.28.0** have been installed
running

```
compact list --installed
```

results in

```
compact: installed versions

→ 0.28.0
  0.26.0
```

The right arrow indicates what version is set to be used by the Compact
command-line tool unless a version is specified.

The options in OPTIONS can be used with this command. **--directory
_directorypath_** and **--version** behave the same as not using a command
(**compact-list** does not have a different version than **compact**), but
**--help** prints the help text for this command and not **compact**.

CLEAN
=====

Synopsys: **compact** **clean** _option_

This command removes all local versions of the Compact toolchain if no option is
set. When **--cache** is set it also removes the cache directory. When
**--keep-current** is set it keeps the version of the Compact toolchain that is
set to be the default.

Assuming that versions **0.26.0** and **0.28.00** of the Compact toolchain are
locally installed running

```
compact clean --cache
```

results in 

```
compact: removed /Users/username/Library/Caches/compactc/github_cache.json
compact: removing versions
compact: removed 0.28.0
compact: removed 0.26.0
```

Now running 

```
compact list --installed
```

results in 

```
compact: installed versions

no versions available on this machine
try: compact update
```

Now running

```
compact update
compact update 0.26.0
compact clean --keep-current
```

results in

```
compact: removing versions
compact: removed 0.28.0
compact: kept 0.26.0
```

The options in OPTIONS can be used with this command. **--directory
_directorypath_** and **--version** behave the same as not using a command
(**compact-clean** does not have a different version than **compact**), but
**--help** prints the help text for this command and not **compact**.

SELF
====

Synopsys: **compact** **self** _option_ _subcommand_

Manages the Compact command-line tool itself.

Running 

```
compact self check
```

checks if a newer version of the Compact command-line tool is available or not.
Assuming the latest version of the Compact command-line tool is **0.4.0** and it
is already installed this results in

```
compact: compact -- 0.4.0 -- Up to date
```

However, if the latest version of the Compact command-line tool is not installed
the command above results in

```
??
```

Running 

```
compact self update
```

updates the Compact command-line tool to the latest version.

The options in OPTIONS can be used with this command. **--directory
_directorypath_** and **--version** behave the same as not using a command
(**compact-self** does not have a different version than **compact**), but
**--help** prints the help text for this command and not **compact**.
