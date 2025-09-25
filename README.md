# Compactc circut compiler

A [nanopass](https://nanopass.org) framework compiler for cryptographic circuits. Currently targeting [Plonk](https://github.com/ZK-Garage/plonk) from a restricted front-end language.

[ABNF syntax](./doc/highlevel.abnf) for parser and lexer.

Examples:

- [election](./examples/election.compact)
- [zerocash](./examples/zerocash.compact)
- [tiny](./examples/tiny.compact)

## Publishing and credentials

### Credentials

TODO: Add proper guide for Github accounts instead of old deprecated nexus guide.

### Note about permissions

If you have installed nix in a single-user mode, then using `chmod 600` for
`~/.netrc` file should be fine, however if you have installed nix in a
multi-user mode, then you need to make sure that both your user and nix build
agents can access `/etc/nix/netrc` file.

One approach is to make the file read-writeable for `root` group, and readable for
`wheel` group, but you need to ensure that your user is in `wheel` group.

First, check if your user is in wheel group, by using `groups`: the output should contain `wheel`:

```sh
$ groups
users wheel
```

Then, you can change the ownership of `/etc/nix/netrc` to `root:wheel`

```sh
$ sudo chown root:wheel /etc/nix/netrc
```

and change its permissions to `640`

```sh
$ sudo chmod 640 /etc/nix/netrc
```

finally, you can verify if ownership and permissions were set correctly

```sh
ls -l /etc/nix/netrc
-rw-r----- 1 root wheel 261 Nov  8 15:42 /etc/nix/netrc
```

the above can be understood as

- `rw-` permissions for `root` user,
- `r--` permissions for `wheel` group, and
- `---` permissions for everyone else.

## reproducible development environment

We require [nix](https://nixos.org) >= 2.7, with [flakes
enabled](https://nixos.wiki/wiki/Flakes).

```sh
nix develop
```

## Running tests

We currently _only_ support the reproducible environment in `nix develop .#default` for
running tests. Once the dev environment has been entered, simply run:

```sh
./compiler/go
```

Executing tests generate profile output with `hot spots` information in [./coverage/profile.html](./coverage/profile.html).
You can treat details for each file as `test coverage`.

- re-run tests whenever source file changes (with exec time)

```sh
find . -type f -name "*.ss" | entr ./compiler/go
find . -type f -name "*.ss" | entr time ./compiler/go
```

## nix build

To build locally using [nix](https://nixos.org/guides/nix-pills/):

```sh
nix build
```

or to show output:

```sh
nix log
```

To run the same tests as CI:

```sh
nix build -L
```

plus follow the instructions for running the E2E and debug tests (below).

## E2E tests

To execute e2e tests, either inside a nix shell or outside of it, run:

```shell
sh ./run-e2e-tests.sh
```

## debug tests

To execute debug test, either inside a nix shell or outside of it, run:

```shell
sh ./run-debug-test.sh
```

## Building from source code

Example building using nix to build and add compactc to the system path:

```sh
nix build
export PATH=$(pwd)/result/bin:$PATH
compactc
```

You could alternatively use `compiler` nix shell:

```sh
nix build
nix develop .#compiler
compactc
```

## Running compiler

To compile a file `FILE` and produce:

- circuit definitions (\*.zkir)
- code for private state and transition functions
- template for definitions

```sh
compactc FILE OUT-DIR
```

for example:

```sh
compactc ./examples/election.compact ./examples/
```

or to have smart contract code in separate files

```sh
compactc ./examples/zerocash.compact ./examples/zerocash
```

The compiler takes the following arguments:

- `--vscode`, omitting newlines from error messages, so that they are rendered
properly within the VS Code extension for Compact.
- `--trace-passes`, outputting intermediate representations for debugging
  purposes.
- `--skip-zk`, omitting the generation of prover and verifier keys, the
  dominant time cost in compilation.
- `--no-communications-commitment`, omitting the contract communications
  commitment which enables data integrity for contract-to-contract calls.

## Dependencies

If you need library for Chez Scheme, add entry to [nvfetcher.toml](nvfetcher.toml)
and run [nvfetcher](https://github.com/berberman/nvfetcher) e.g.

```sh
nix run github:berberman/nvfetcher
```

## User documentation

### Release

#### get compactc.zip for required platform

##### Linux-release:

Get the compactc.zip from linux-release for linux and windows wsl:
https://github.com/midnightntwrk/compactc/releases/tag/linux-release

##### MacOS-release:

Get the compactc.zip from macos-release for macos:
https://github.com/midnightntwrk/compactc/releases/tag/macos-release

##### Direct usage -- compile a contract

```
unzip compactc.zip
mkdir output
./run-compactc.sh /path/to/contract.compact output
# inspect output folder
```

##### System wide installation -- compile a contract

```
unzip compactc.zip
# needs to be root
./install.sh

cd ..

mkdir output
# compactc is now available on $PATH
compactc /path/to/contract.compact output
```

### Docker

#### get compactc image

Replace 'registry' with one of [Docker registries](#docker-registries)

```
docker login registry

docker pull registry/compactc:0.0.1
```

#### compile compactc smart contract using compact compiler

Note: absolute paths are necessary
Replace 'registry' with one of [Docker registries](#docker-registries)

```
PATH_TO_COMPACTC_REPO=$PWD
docker run -v $PATH_TO_COMPACTC_REPO/examples/zerocash.compact:/zerocash.compact -v $PATH_TO_COMPACTC_REPO/tmp:/tmp registry/compactc:0.0.1 "compactc zerocash.compact /tmp"
```

#### debug or run container interactively

Replace 'registry' with one of [Docker registries](#docker-registries)

```
docker run -dit registry/compactc:0.0.1 bash
# get container-id, it's also returned from previous cmd
docker ps
docker exec -it container-id bash
```

## Docker registries

github registry = ghcr.io/midnight-ntwrk/

public dockerhub =

## Generate/update API documentation

To install [Typedoc](https://typedoc.org/), from the appropriate project's directory (`midnight-onchain-runtime` or `runtime`) execute:

```sh
npm i
```

To update documentation for `midnight-onchain-runtime`, from the project's directory execute:

```sh
npm run generate-docs-midnight-onchain-runtime
```

To update documentation for `runtime`, from the project's directory execute:

```sh
npm run generate-docs-runtime
```

### Test report

Test report after test execution is visible in **console** and also as:
  - [HTML Report](./tests-e2e/reports/test-report.html)
  - [Markdown Report](./tests-e2e/reports/test-report.md)
  - [JUnit Report](./tests-e2e/reports/test-report.xml)

### Test logs

Logs are present in [./tests-e2e/logs/tests](./tests-e2e/logs/tests)
