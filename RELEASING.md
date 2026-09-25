# Releasing Compact

How to cut, validate and publish a release of the Compact toolchain, the runtime, and
the `compact` tool.

This document lives in the repository so that a change to a release workflow and the
change to its documentation can arrive in the same pull request. If you alter anything
under `.github/workflows/` that a releaser touches, update this file alongside it.

**Contents**

1. [Before you start](#1-before-you-start)
2. [Releasing the toolchain](#2-releasing-the-toolchain)
3. [Releasing compact-runtime](#3-releasing-compact-runtime)
4. [Releasing the compact tool](#4-releasing-the-compact-tool)
5. [Docs on their own](#5-docs-on-their-own)
6. [Versioning](#6-versioning)
7. [Undoing a release](#7-undoing-a-release)
8. [Reference: the workflows](#8-reference-the-workflows)
9. [Reference: internal release, every field](#9-reference-internal-release-every-field)
10. [Reference: public release, every field](#10-reference-public-release-every-field)
11. [Reference: what version a build reports](#11-reference-what-version-a-build-reports)
12. [When a step fails](#12-when-a-step-fails)

---

## 1. Before you start

### What you need

- Write access to `LFDT-Minokawa/compact`: releasing is dispatching its workflows, and
  a CLI release pushes a tag to it.
- Read access to `midnight-ntwrk/artifacts`, to see internal releases land.
- The workflows authenticate with organisation secrets, so no personal token is needed.
- Access to the internal release-coordination channel — where you find role-holders and
  announce the release. This document names roles; when you do not know who holds one,
  ask there.

### What you are releasing

A Compact release is three separate artifacts that are versioned and published
independently. Knowing which one you are dealing with prevents most of the confusion in
this document.

| Artifact | Version lives in | Published to |
| -------- | ---------------- | ------------ |
| **compactc**, the compiler (the toolchain) | `compiler/compiler-version.ss`, `flake.nix` | GitHub releases, three repositories (below) |
| **compact-runtime** | `runtime/package.json` | npm, via GitHub Packages first |
| **compact**, the CLI (the launcher people install) | `Cargo.toml`, `[workspace.package]` | GitHub releases, by pushing a tag |

The Compact language is versioned too (`compiler/language-version.ss`), but it is not
an artifact: it ships inside the compiler. Its version appears in release titles, in
the published version table, and in `pragma language_version`.

Every toolchain release passes through some or all of three repositories.

| Repository | Who can see it | What lands there |
| ---------- | -------------- | ---------------- |
| `midnight-ntwrk/artifacts` | Midnight, internal | Every internal release. This is the store the public release is later copied *from*. |
| `LFDT-Minokawa/compact` | Public — this is the source repository | Candidates, published as **prereleases** — publicly visible. Public releases as full releases. Also where all the tags live. |
| `midnightntwrk/compact` | Public | Public releases only. **This is the one the `compact` tool reads**, so a build that is not here cannot be installed with `compact update`. |

Because `compact update` only ever looks at `midnightntwrk/compact`, and only public
releases go there, **release candidates cannot be installed with the `compact` tool**.
Whoever is validating a candidate gets it from the internal store or from
the release page and unpacks it themselves.

### The one structural rule

**The public release copies a build; it never makes one.** Only the internal release
workflow compiles anything; the public release workflow takes an internal release's four
archives and republishes those exact bytes. Therefore the release you ship has to be
*built* as the release: candidates first, then one more internal run at the final
version — no `-rc` — tested like any other, and that build is what you promote. What
ships is then exactly what was built and validated as the release, and the version the
binary reports matches the tag on it.

Each internal build stamps its tag and commit into the compiler
(`scripts/stamp-compiler-version.sh`, run by `release-build.yml`) and then asserts that
the binary inside the zip it is about to upload reports the stamped line — so an
unstamped or mis-stamped binary fails the build rather than shipping.

The whole process, in outline:

1. Make sure the work is finished and the versions on the branch are the ones you
   intend to release (§2, steps 1–4).
2. Build an internal release candidate. This compiles four platforms and publishes them
   internally.
3. Hand it to QA. If they find something, fix it and cut another candidate. Repeat.
4. When QA is happy, build the final version internally — the same commit — then
   promote it.
5. Merge back, and update the things that reference the version you just shipped.

Nothing in that list happens on its own. Every publishing step is a person opening a
workflow in the Actions tab and filling in a form; no release triggers the next one, and
no pushed tag starts a **toolchain** release — the CLI is the one exception (§4). The
one automatic build in this area is unrelated to releasing: the internal release
workflow also runs every twelve hours, builds and tests `main` on three platforms — it
skips Intel macOS — and publishes nothing. It exists to catch breakage early, and it
also exercises the version stamp and its assertion on every run. If you get an alert
about it, that is what failed.

---

## 2. Releasing the toolchain

This is the main procedure. Steps 1 and 2 begin a day or two before you cut anything.

### Step 1 — Clear the work out of the way

Every issue going into the release is on the
[release toolchain train project](https://github.com/orgs/LFDT-Minokawa/projects/3).
Walk the board and act on each column:

| Column | What to do |
| ------ | ---------- |
| **Done** / **Ready for release** | Nothing. It is in. |
| **In QA** / **Ready for QA** | Ask the QA lead to prioritise testing and resolution. |
| **In progress** | Ask the assignee for a completion date. If it must ship in this release, wait for it. If it cannot land in time, move it to the next release cycle — agree that with the issue owner rather than deciding alone. |

### Step 2 — Chase the release notes

Ask whoever owns release notes for this release. If the final text is not ready, that
does not block you — assemble a first draft
from the raw changelog entries and use that. You will replace it before the final
public release (step 8).

### Step 3 — Put up a version-bump pull request against `main`

Bump each version that has actually changed, then regenerate the docs that embed them.

| File | Holds |
| ---- | ----- |
| `compiler/compiler-version.ss` | the compactc version |
| `compiler/language-version.ss` | the language version |
| `flake.nix` | the compactc version again — CI checks the two agree |
| `runtime/package.json` | the runtime version |
| `CHANGELOG.md` | the entry for this release |

Only bump what changed: a version ending `.0` — say a runtime at `0.15.0` — means that
component has not changed since the last release, so leave it alone; a version shaped
`0.15.10x` *has* changed, and you bump it to the next release version (`0.16.0`). The
same rule applies to the compiler and the language; §6 explains the two-track scheme.

Then, inside a nix shell, regenerate the version strings embedded in the documentation
and include the result in the same commit:

```
./compiler/go
```

Include `doc/release-notes/toolchain-<x.y.z>.md` in the same pull request, where
`x.y.z` is the compactc version you are releasing — final text if you have it, the
changelog-derived draft if you do not
([an example of a changelog-derived draft](https://github.com/LFDT-Minokawa/compact/commit/ae3b368c81342bac6af1166f7cb5463ea830f585#diff-71a4eb231313b3431fd3f3270f259dbadf8bafdaa403215baa6ec0c9dc0d1ba9)).
The internal release fails without this file
unless you turn its release-notes input off (§9).

### Step 4 — Merge `main` into `release/midnight`

It should merge cleanly. **Do not squash** — this must be a real merge commit, because
squashing breaks the relationship between the two branches and makes the merge back in
step 9 painful.

This merge is also what carries the release tooling itself — the workflows, the stamp
script, the compiler's version plumbing — onto the branch you are about to release
from, so a fix to any of them reaches the release by the same route as the code.

### Step 5 — Build a release candidate

Run [**Internal release of compact toolchain**](https://github.com/LFDT-Minokawa/compact/actions/workflows/internal-release.yml) with a version ending `-rc.0`, from
`release/midnight`. §9 documents every field. Two of them deserve attention here:

- GitHub's own **Use workflow from** selector picks which ref the workflow *definition*
  comes from; the **Branch to use for release** input picks what gets built. Keep both
  on the branch you are releasing, so the tooling and the source agree.
- **The version you type must match the source.** The build stamps the release name
  into the compiler, and it refuses if the `x.y.z` part of your tag disagrees with
  `compiler/compiler-version.ss` on the branch being built. Typing `v0.35.0-rc.0` when
  the source says `0.34.1` fails with:

  ```
  ::error::tag v0.35.0-rc.0 is 0.35.0 but compiler/compiler-version.ss says 0.34.1
  ```

  That is the check doing its job, not a broken workflow. Fix step 3 and run again.

Use the same branch for every run in this release, including the final build in step 8.
After step 4 the two branches hold the same *content*, but step 4 makes a merge commit,
so they are different commits — and the commit is part of what the binary reports. The
run resolves your branch to one commit up front and then builds, tests and tags that
exact commit, so a push to the branch mid-run cannot change what you get; the branch
you pick still decides which commit that is.

If the runtime also needs releasing, the candidates have to be interleaved in a
particular order — see "Releasing the runtime alongside" below before you start.

### Step 6 — Announce it

Post in the internal release-coordination channel so other teams can find the
candidate. Include the tag and both locations:

- [LFDT-Minokawa/compact releases](https://github.com/LFDT-Minokawa/compact/releases)
- [midnight-ntwrk/artifacts releases](https://github.com/midnight-ntwrk/artifacts/releases)

### Step 7 — Ask QA to validate it, and iterate

If QA finds a problem, decide whether it must be fixed in this release. If it must, fix
it and cut `-rc.1`, then go back to QA. If it can wait, note it in the release notes
and carry on.

QA can confirm what they are testing: `compactc --version` reports the exact release it
was built from — for example `0.34.1-rc.2 (a1b2c3d4e 2026-09-10)`. The version-and-
suffix must be the candidate you announced, and the parenthesised commit must be the
commit the run tagged:

```
git rev-parse 'v0.34.1-rc.2^{commit}' | cut -c1-9
```

If either does not match, they are not holding the build you cut — something went wrong
upstream of the testing.

### Step 8 — Build the final release, then promote it

Two runs, in this order, plus one check between them.

First, settle the release notes: if you have been using a changelog-derived draft,
replace it with the final text now — this is the last moment before the notes become
public.

Then run [**Internal release of compact toolchain**](https://github.com/LFDT-Minokawa/compact/actions/workflows/internal-release.yml) again, with the version and **no
suffix** — `v0.34.1`. The promoting workflow copies bytes and never compiles, so the
release has to be built *as* the release; the public workflow refuses a version with a
prerelease identifier for exactly this reason.

**Check the final is the same commit QA approved.** The approved candidate reported,
say, `0.34.1-rc.2 (a1b2c3d4e 2026-09-10)`; the final build must report
`0.34.1 (a1b2c3d4e 2026-09-10)` — the same commit and date, only the suffix gone. A
different commit means the branch moved after QA signed off, and the build is not what
they approved: stop and find out what landed. The internal run builds and tests the
final on all four platforms exactly as it does a candidate, but it is not the artifact
QA validated — same source, different stamp, different bytes — so this commit check is
the link between the two. The old process had QA validate after every
release, the final included; the commit check plus a smoke of one downloaded artifact —
`compactc --version` and one `--skip-zk` compile — costs minutes, and whether QA
repeats full validation on top is the team's call.

Then run [**Public release of compact toolchain**](https://github.com/LFDT-Minokawa/compact/actions/workflows/public-release.yml), giving it that same version. §10
documents every field. It checks that the internal release exists with all four
architectures and that its binary reports this version and the released commit, then
republishes those archives to the two public repositories.

### Step 9 — Merge `release/midnight` back into `main`

This should also be clean. If it is not, say in the pull request body what conflicted
and how you resolved it, so the reviewer knows what to look at.

### Step 10 — Point the `compact` tool's tests at the new release

You can do this in the same pull request as step 9. In
`tools/compact/tests/common/mod.rs`:

| Constant | Set to |
| -------- | ------ |
| `LATEST_COMPACTC_VERSION` | the compactc version you just published |
| `PREVIOUS_COMPACTC_VERSION` | the compactc version before it |

Leave `COMPACT_VERSION` and `PREVIOUS_COMPACT_VERSION` alone — those are the `compact`
CLI's own versions and belong to §4, not here.

Expect to re-record some fixtures. The tool's tests compare against recorded output,
and some of that output names versions. `output/list/std_latest_selected.txt` is the
usual one. `output/compile/compact_help.txt` is a copy of the *installed* compactc's
help text, so it moves with `LATEST_COMPACTC_VERSION` and never ahead of it — the
tool's tests run the installed release, so a fixture recorded from unreleased compactc
fails against it. Update it when the constant crosses a release that changed the
command line.

Expect some of the tool's tests to fail on the pull request that moves these
constants. The tool compares recorded output, and a stamped compiler prints more than
the version — `compact … compile --version` gives `0.34.1 (a1b2c3d4e 2026-09-10)`,
commit and date included — so any recording that embeds compiler output goes stale when
the release it points at changes. The failing test's diff shows the exact line the new
release prints. If you need it from git instead: the nine-character commit is a plain
truncation (`git rev-parse 'v0.34.1^{commit}' | cut -c1-9` — not `--short=9`, which git
lengthens when the short form is ambiguous), and the date is
`git show -s --format=%cs 'v0.34.1^{commit}'`.

### Step 11 — Check whether the CLI needs a release too

The `compact` CLI is versioned and released separately (§4), and it is easy to forget
that a fix merged weeks ago is still unreleased. Compare the version under
`[workspace.package]` in the top-level `Cargo.toml` against the newest `compact-v*`
tag: if the `Cargo.toml` version is ahead, there are merged changes nobody can install
yet.

Releasing the CLI is quick and independent of the toolchain, so it can also be done
immediately after any fix worth shipping — this step is the backstop for when that has
not happened, not a replacement for it.

### Step 12 — You are done

Check that the release is visible on
[midnightntwrk/compact](https://github.com/midnightntwrk/compact/releases), since that
is where `compact update` will look for it, and that its binary answers for itself:
download one archive and run `compactc --version` — it must print the version you
released, with the commit from step 8.

### Releasing the runtime alongside

If the runtime is changing in this release too, the two cannot simply be released
together. **The runtime has to reach its final version before compactc does**, because
compactc's final build must be built against a runtime that is publicly installable,
and npm will not serve a prerelease to the projects that consume it.

That forces a sequence of rounds. Taking a runtime going to `0.1.0` and a compactc
going to `0.3.0`:

| Round | Release | Then |
| ----- | ------- | ---- |
| **1** | `compact-runtime 0.1.0-rc.0`<br>`compactc 0.3.0-rc.0` | QA validates |
| **2** | `compact-runtime 0.1.0` — final<br>`compactc 0.3.0-rc.1` | QA validates again — compactc has been rebuilt against the released runtime |
| **3** | `compactc 0.3.0` — final: an internal run at `v0.3.0`, then promote it | QA checks the final too — step 8's commit check at minimum — then announce |

Round 3 is the two runs from step 8, not one: the internal build at `v0.3.0` and then
the promotion of it.

If QA rejects a round, you have the same choice as in step 7: fix it and repeat that
round with the next candidate number, or record the issue in the release notes and
proceed to the next round.

---

## 3. Releasing compact-runtime

The runtime is an npm package. The release workflow publishes it to GitHub Packages,
and a promotion workflow pushes it from there to public npm — so a release is: put the
right version on the branch, run the workflow, promote, verify.

Two rules before anything else:

- **Never publish an internal version publicly.** The runtime follows the two-track
  versioning in §6, so a version shaped `0.x.10y` is a development version and must not
  reach the public registry.
- Every release, internal or public, needs an entry in the dependency compatibility
  matrix, recording which ledger and onchain-runtime versions this runtime was built
  against. Ask in the internal release-coordination channel where the current
  compatibility matrix lives.

### The procedure

1. If the ledger dependencies are changing, update them first — see
   ["When the ledger dependencies change"](#when-the-ledger-dependencies-change) below.
2. Set the version in `runtime/package.json` on `release/midnight`, which should be
   sitting at `x.y.0`: `0.9.0-rc.0` for a candidate, `0.9.0` for the final. Run
   `npm install` in `runtime/` so the lock file matches, and commit.
3. Run [Release publish of compact-runtime](https://github.com/LFDT-Minokawa/compact/actions/workflows/release-runtime.yml)
   with that branch — its only input. It builds `nix build .#runtime.forPublish` from
   the branch's committed state and publishes the result to
   [GitHub Packages](https://github.com/midnight-ntwrk/artifacts/pkgs/npm/compact-runtime);
   confirm the version appears there. It derives the npm dist-tag from the version's
   suffix — `rc`, `beta`, `alpha`, any other suffix `prerelease`, none `latest` — which
   is the rule the public republisher applies too, and it refuses a version containing
   `-dev.` or `+`.
4. Promote it: run the
   [push-npm-package](https://github.com/midnight-ntwrk/artifacts/actions/workflows/push-npm-package.yml)
   workflow in `midnight-ntwrk/artifacts`. Give the version **without** a leading `v` —
   `1.2.3-rc.0`, not `v1.2.3-rc.0`.
5. Check it landed on
   [npm](https://www.npmjs.com/package/@midnight-ntwrk/compact-runtime?activeTab=versions).

Releases come from `release/midnight`, because that is the only branch that carries
release-shaped versions — `main` holds the `x.y.10z` development shapes (§6). The one
exception is a maintenance release of a superseded line, cut from a branch off the old
release commit; the runtime gets no git tag, so that commit is the one where
`runtime/package.json` last carried the old version, and the workflow's branch input
accepts such a branch.

There is deliberately no by-hand `npm publish` here. The workflow builds from a
committed state, strips the package's build scripts before publishing, and derives the
dist-tag; `npm publish` from a working tree does none of that, so the two paths can
ship different bytes under the same version. If the workflow itself is broken, fix it —
every step it performs is written in `release-runtime.yml`.

### When the ledger dependencies change

The runtime pulls `zkir` and `onchain-runtime` from the ledger. Both are declared in
`flake.nix`:

```nix
inputs = {
  zkir = {
    url = "github:midnightntwrk/midnight-ledger-prototype/ledger-5.0.0";
    inputs.compactc.follows = "";
    inputs.zkir.follows = "zkir";
  };
  onchain-runtime = {
    url = "github:midnightntwrk/midnight-ledger-prototype/ledger-5.0.0";
    inputs.compactc.follows = "";
    inputs.zkir.follows = "zkir";
  };
```

Point both at the ledger tag you need. Three things differ between an internal ledger
version and a public one:

| | Internal ledger version | Public ledger version |
| --- | --- | --- |
| The ledger tag in `flake.nix` | carries `-alpha`, `-beta` or `-rc` | carries no suffix |
| `@midnight-ntwrk/onchain-runtime` in `runtime/package.json` | leave it — npm cannot see internal releases, so nix supplies the right one from the URL above | set it to the matching public version |
| `@midnight-ntwrk:registry=…` in `~/.npmrc` | irrelevant | must be **absent**, so `npm install` resolves the dependency from public npm rather than GitHub Packages |

Then, either way:

1. Run `npm install` in `runtime/` for the lock file.
2. From the repository root:

   ```
   nix flake update
   nix flake metadata
   nix build .#runtime.forPublish
   ```

   The ledger commit `nix flake metadata` prints must match the tag you asked for;
   `git show-ref -s <ledger-tag>` in the ledger repository gives the hash to compare
   against. If `nix flake update` fails with a cargo authorisation error, put the
   commit hash in `flake.nix` instead of the tag.
3. Confirm the built package carries the dependency you wanted — read it out of
   `result/lib/node_modules/@midnight-ntwrk/compact-runtime/package.json` — and commit.

A dependency change is a change, so bump the runtime version with it: `x.y.0` becomes
`x.y.100`, and `x.y.10z` increments `z` (§6). The release-shaped version is then set in
step 2 of the procedure above.

## 4. Releasing the compact tool

The `compact` CLI — the launcher users install, in `tools/compact` — is versioned and
released separately from the compiler, and it is the one release here that is triggered
by pushing a tag.

### Step 1 — Bump the version

Branch off `main`. Raise the version under `[workspace.package]` in the top-level
`Cargo.toml`, run `cargo check` inside a `nix develop` shell to refresh `Cargo.lock`,
and add an entry to `tools/compact/CHANGELOG.md`.

### Step 2 — Get it reviewed and merged into `main`

### Step 3 — Open an issue for the release notes

Devtools release notes live in `midnightntwrk/midnight-docs`. File the issue and assign
it to someone.

### Step 4 — Tag and push

```
git tag compact-vX.Y.Z
git push origin compact-vX.Y.Z
```

Pushing the tag is what starts the release. CI builds, tests, and publishes the
binaries to
[midnightntwrk/compact releases](https://github.com/midnightntwrk/compact/releases).
Check your version appears there.

### Step 5 — Point the tests at the version you just published

In `tools/compact/tests/common/mod.rs`, in a follow-up pull request:

| Constant | Set to |
| -------- | ------ |
| `COMPACT_VERSION` | the CLI version you just published |
| `PREVIOUS_COMPACT_VERSION` | the CLI version before it |

These are the CLI's own versions. The `*_COMPACTC_*` constants are the compiler's and
belong to §2 step 10.

---

## 5. Docs on their own

Documentation can go to `midnight-docs` without a toolchain release. Run
[**Copy Compact docs to midnight-docs**](https://github.com/LFDT-Minokawa/compact/actions/workflows/copy-docs.yml), choosing the branch to generate from (`main` or
`release/midnight`) and the base branch in `midnight-docs`; the description field
becomes the pull request's title, and a draft flag holds it open. One run copies the
language reference set, the standard library pages, the tooling usage pages, the ledger
ADT (both published copies), and the compact-runtime API reference, as a single pull
request on `midnightntwrk/midnight-docs`. Generating the API reference builds the
runtime, so the runtime must build on the chosen branch even for a docs-only update.

[**Copy release notes to midnight-docs**](https://github.com/LFDT-Minokawa/compact/actions/workflows/copy-release-notes.yml) does the same for the release-notes pages, and
additionally wants the toolchain version. It downloads that version's published build to
read the language version off it, so it runs only for a toolchain that was actually
released. Keep the two as separate pull requests — the docs team has asked that documentation and release notes arrive as two
separate pull requests, which is also why the public release workflow opens two.

---

## 6. Versioning

Development and release branches use different version shapes, because the release
branch batches many development versions into one release.

| Where | Shape | Example |
| ----- | ----- | ------- |
| Development branch | `x.y.10z` | `compactc 0.19.101` |
| Release branch | `x.y.0` | `compactc 0.20.0` |

So a component sitting at `x.y.0` has not changed since the last release; one at
`x.y.10z` has. That is the rule behind "only bump what changed" in §2 step 3. After a
release, the next change on the development branch moves to `0.20.100` — the hundreds
restart; they do not continue from the release number.

Patch releases are releases and take the release shape: `0.31.1` was one. The two
shapes above are development versus released, not minor versus patch.

### Internal releases from a long-running feature branch

When a feature lives on its own branch and needs an installable build, the version must
never describe different code in development than in the released artifact. Given a
feature branch whose compiler version is `x.y.10z` and a feature called `a-b-c`, the
tag shape is:

```
vx.y.10z-rc.0-a-b-c
```

The triple is the *feature branch's own* committed version, not main's: the build reads
`compiler/compiler-version.ss` from the branch it is building and refuses any tag whose
triple disagrees, so naming main's version here fails every build job. The leading `v`
is required by the workflow's format check.

**No workflow can run this tag today, so pick one of three routes:**

- **On-demand dev publish** takes an arbitrary branch, but it ignores any version you
  have in mind: it computes its own coordinate, publishes `compactc-dev-<commit>` as a
  prerelease, and the binary reports `x.y.10z-dev (<commit> <date>)`. If a pinnable
  installable build is all you need, this is the answer, and the tag shape above never
  comes into it.
- **Internal release** refuses the branch: its `branch` input is a two-option choice —
  `main` or `release/midnight`. To use it anyway, add the feature branch to the
  `options:` list in `internal-release.yml` *on the feature branch itself* and dispatch
  the workflow from that branch — the form is built from the ref you dispatch from, so
  `main` needs no change.
- Or widen the choice on `main` in a reviewed PR, if feature-branch releases are going
  to recur.

Either internal-release route then takes the `vx.y.10z-rc.0-a-b-c` tag shape above, and
`compactc --version` reports the full tag and the commit, so it matches the artifact
someone is holding rather than just the numbers in the source. If you need to know
which feature build somebody has, ask them for that string.

---

## 7. Undoing a release

### An internal toolchain release

An internal run leaves **three** things behind, and two tag shapes: a plain
`v<version>` git tag, and GitHub releases named `compactc-v<version>`. All of it has to
go, or the leftovers will look like a real candidate:

- Delete the release from
  [midnight-ntwrk/artifacts](https://github.com/midnight-ntwrk/artifacts/releases). It
  is tagged `compactc-v<version>`.
- For a candidate, delete the prerelease from
  [LFDT-Minokawa/compact](https://github.com/LFDT-Minokawa/compact/releases). The
  workflow creates it as a draft and then immediately un-drafts it, so it is publicly
  visible. A final version does not get one.
- Delete **both** tags from
  [LFDT-Minokawa/compact](https://github.com/LFDT-Minokawa/compact/tags): `v<version>`
  and, for a candidate, `compactc-v<version>`.

Re-running instead of undoing: the tag step never pushes a tag that already exists —
one already on the run's own commit is skipped — so a run that failed *after* the push
can be re-run without tripping over its own tag. That is all the skip does. Releases
here are immutable, so a *completed* run cannot be re-dispatched at the same version:
the release step cannot replace the existing release's assets, and deleting the
release does not free its tag name for reuse. Undoing removes the misleading
leftovers, but the version number is spent — continue with the next candidate number.

### An internal npm package

Find the version in
[GitHub Packages](https://github.com/midnight-ntwrk/artifacts/pkgs/npm/compact-runtime/versions)
and delete it there.

### An internal docker image

Find the tag in
[the container registry](https://github.com/midnight-ntwrk/artifacts/pkgs/container/compactc/versions)
and delete it there.

### A public npm package

Ask SRE, and know the constraints:

- You have **72 hours** from publication. After that it cannot be removed.
- If the package you want to delete is tagged `latest`, you must publish something else
  as `latest` first — npm will not let you remove the current `latest`.

---

## 8. Reference: the workflows

All of these live under Actions in `LFDT-Minokawa/compact`. The first block are the
ones you start by hand; the second are called by them and never run directly.

| Workflow | Use it when | Result |
| -------- | ----------- | ------ |
| [**Internal release of compact toolchain**](https://github.com/LFDT-Minokawa/compact/actions/workflows/internal-release.yml) (`internal-release.yml`) | Any build of the toolchain: a candidate, an alpha or beta, a throwaway for testing, **or the final build that gets promoted**. | Builds four platforms, tests them, pushes the tag, publishes to the internal store. A candidate is also published on `LFDT-Minokawa/compact`; a final version is not, leaving that to the promoting workflow. |
| [**Public release of compact toolchain**](https://github.com/LFDT-Minokawa/compact/actions/workflows/public-release.yml) (`public-release.yml`) | The final internal build exists and QA has signed off. | Republishes that build's archives to the two public repositories, and can open the docs and release-notes pull requests. |
| [**Release publish of compact-runtime**](https://github.com/LFDT-Minokawa/compact/actions/workflows/release-runtime.yml) (`release-runtime.yml`) | You need to publish the runtime and the version in `runtime/package.json` is already correct on the branch. | Builds and publishes the runtime package to GitHub Packages (§3 — npmjs.org is a further step). |
| [**Copy Compact docs to midnight-docs**](https://github.com/LFDT-Minokawa/compact/actions/workflows/copy-docs.yml) (`copy-docs.yml`) | You want the language reference, API docs, grammar and so on updated without doing a release. | Opens a pull request on `midnight-docs`. |
| [**Copy release notes to midnight-docs**](https://github.com/LFDT-Minokawa/compact/actions/workflows/copy-release-notes.yml) (`copy-release-notes.yml`) | You want just the release-notes pages updated without doing a release. | Opens a separate pull request on `midnight-docs`. |
| [**On-demand dev publish**](https://github.com/LFDT-Minokawa/compact/actions/workflows/dev-publish.yml) (`dev-publish.yml`) | Somebody needs an installable build of a branch that is not a release at all. | Publishes `compactc-dev-<commit>` as a prerelease reporting `x.y.10z-dev (<commit> <date>)`, and optionally the runtime as a `dev` package. Not part of releasing; `doc/dev-builds.md` covers coordinates, consumption and retention. |
| [**Compact Tool Release**](https://github.com/LFDT-Minokawa/compact/actions/workflows/compact-release.yml) (`compact-release.yml`) | Never by hand. It fires on every pull request, and when you push a `compact-v*` tag (§4). | Builds and publishes the `compact` CLI binaries. The tag filter dist generates for it matches every `compact`-prefixed tag, so `compactc-*` and `compact-vsc-plugin-*` are excluded from it explicitly — without those exclusions a toolchain or plugin release starts a run of this workflow that can only fail. |

Called by the above, never dispatched by hand: `release-build.yml` (one platform's
build — stamps the version into the compiler before `nix build` and refuses to upload a
zip whose binary does not report the stamped line), `release-test.yml` (one platform's
tests against the built zip), `check-docs.yml`, `generate-docs.yml`, and
`compute-release-notes.yml` (turns the release-notes file into the `midnight-docs`
branch, and writes the language version into the published version table).

The docs team has asked that documentation and release notes arrive as **two separate
pull requests**; the public release workflow can open both, and the two standalone
copy workflows exist for when you need one without the other.

---

## 9. Reference: internal release, every field

[Run the workflow](https://github.com/LFDT-Minokawa/compact/actions/workflows/internal-release.yml).

**Use workflow from** — GitHub's own selector for which ref the workflow definition
comes from. Keep it on the branch you are releasing (§2 step 5).

**Toolchain version** *(required)* — `v0.34.1-rc.0` for a candidate, or `v0.34.1` with
no suffix for the final build that will be promoted. The `x.y.z` part must equal the
version committed in `compiler/compiler-version.ss` on the branch being built, or the
build fails — see §2 step 5. The suffix must be a valid semver prerelease: dot-separated
identifiers, each alphanumeric or a number without a leading zero. `-rc.0`, `-beta.1`
and `-test.0` work; a space, a quote or a missing `-` fails this workflow's format
check, and `-rc.00` or `-rc.` fails the stamp script (§12).

A run with no suffix skips publishing to `LFDT-Minokawa/compact`, leaving that to the
public release workflow, which would otherwise collide with it.

**Branch to use for release** — `main` or `release/midnight`; the input is a two-option
choice, so nothing else can be picked (§6 covers feature branches). Default
`release/midnight`. The run resolves this to one commit up front; everything is built,
tested and tagged at that commit.

**Include MacOS Intel build** — leave enabled for anything real. Default on. Turn it
off only when testing the workflow itself: it is by far the slowest build, and the wait
is not worth it if you are not testing that platform. A build without it **cannot be
promoted to a public release**, which requires all four architectures.

**Include release notes in artifact zip files** — puts the release-notes file inside
each archive. Default on. Requires `doc/release-notes/toolchain-<x.y.z>.md` to exist on
the branch. If it does not, the build fails and takes the rest of the run with it — so
either add the file in §2 step 3 or turn this off.

**Create branch with documentation in midnight-docs** — opens a documentation pull
request on `midnight-docs`, as a **draft**, because the docs usually change again
before release. Default on.

**Branch to merge with in midnight-docs** — the base branch for that pull request.
Default `main`. Only matters if the previous field is on.

**Draft PR description for docs** — the title of the documentation pull request.
Default "Compact toolchain docs copied to midnight-docs".

Clean up after test builds: a throwaway internal release still creates a tag and
published artifacts, and left behind they can be mistaken for real candidates — so once
one has served its purpose, delete both (§7).

---

## 10. Reference: public release, every field

[Run the workflow](https://github.com/LFDT-Minokawa/compact/actions/workflows/public-release.yml).
Only after the final internal release exists and QA has signed off.

**Use workflow from** — which ref the workflow definition comes from.

**Internal version** *(required)* — the final internal release you are promoting,
`v0.34.1`, with **no** prerelease identifier; the workflow rejects `-rc.N`, because
promotion copies bytes and a candidate's bytes report a candidate version. It must
already exist in `midnight-ntwrk/artifacts` with all four architectures:
`aarch64-unknown-linux-musl`, `x86_64-unknown-linux-musl`, `aarch64-darwin`,
`x86_64-darwin`. The workflow checks this first and stops if any are missing. It then
downloads one archive and checks `compactc --version` names this version and the
commit the internal run tagged `vX.Y.Z` — a rebuilt or replaced artifact fails here
instead of shipping. The public version is this same string — nothing is stripped or
renamed.

There is no language-version field, because that same archive supplies it: the workflow
reads `compactc --language-version` from the promoted binary and puts the answer in both
release titles and in the `midnight-docs` version table, so the published language
version is what the shipped compiler enforces rather than what somebody typed.

**Branch to use for release notes and docs** — `main` or `release/midnight`. Default
`release/midnight`. The release notes and docs are read from this branch, resolved to
one commit at the start of the run. The `compactc-vX.Y.Z` tag this workflow creates on
`LFDT-Minokawa/compact` does not follow the branch at all: it lands on the commit the
internal run tagged `vX.Y.Z` — the commit that was built — so the two tags always name
the same commit, and a push during promotion changes nothing about what ships or where
the tag points.

**No release notes** — default off. Turn it on only to publish without notes; the
release body will be empty. With it off, `doc/release-notes/toolchain-<x.y.z>.md` must
exist on the chosen branch.

**Create branch with documentation in midnight-docs** — opens the documentation pull
request. Default on.

**Branch to merge with in midnight-docs** — base branch for the documentation pull
request. Default `main`.

**PR description for docs** — the title of the documentation pull request.

**Create branch for release notes in midnight-docs** — opens a **second, separate**
pull request for the release-notes pages. Default on. The docs team wants these kept
apart from the documentation pull request.

**Branch to merge with in midnight-docs** — base branch for the release-notes pull
request. Default `main`. This is a different field from the identically-named one
above — check you are filling in the right one.

**PR description for release notes** — the title of the release-notes pull request.

---

## 11. Reference: what version a build reports

`compactc --version` reports the release it was built from, not just the three numbers
in the source. This is how you confirm that the thing installed somewhere is the thing
you think it is.

| Build | Reports |
| ----- | ------- |
| A working tree, nothing stamped | `0.34.1-dev` |
| Release candidate `v0.34.1-rc.2` | `0.34.1-rc.2 (a1b2c3d4e 2026-09-10)` |
| Scheduled build, or a dev publish | `0.34.1-dev (1a2b3c4d5 2026-09-10)` |
| Final internal release `v0.34.1` | `0.34.1 (a1b2c3d4e 2026-09-10)` |
| Public release, promoted from it | `0.34.1 (a1b2c3d4e 2026-09-10)` |

If a public release ever reports `-rc.N`, something went wrong: it would mean a
candidate was promoted rather than a final internal build — which the public release
workflow refuses, so it should not be reachable. The version on the binary and the
version on the tag are expected to agree.

**The version and the commit are two things, and they stay two things.** The version is
what you pin against, and it is what goes into `contract-info.json` and
`contract-manifest.json` under `compiler-version`. The commit is reported beside it, in
parentheses, and appears in those files as its own `compiler-commit` field. Keeping it
out of the version number is deliberate: semver build metadata is not reliably ignored
when versions are compared, so a tool that parses `0.34.1+ga1b2c3d4e` reads a
*different version* from `0.34.1`, while `0.34.1 (a1b2c3d4e 2026-09-10)` is
unambiguously the same version, precisely identified. `rustc --version` has this shape
for the same reason.

A build that nothing stamped has no commit to report and prints just the version — a
local `nix build` cannot know which commit it is.

`compactc --version --verbose` prints each thing as its own field, so a script can read
one without parsing it out of the other, and adds the language and runtime versions so
that a bug report needs one command rather than three:

```
release:          0.34.1-rc.2
commit-hash:      a1b2c3d4e5f60718293a4b5c6d7e8f9012345678
commit-date:      2026-09-10
language-version: 0.26.0
runtime-version:  0.19.101
```

**The one-line form abbreviates the commit to nine characters; the verbose form and
`contract-info.json` keep all forty.** That split is `rustc`'s: the short form is for
reading, the full one for pasting into a `git` command or an API call. The build is
stamped with the whole hash — `scripts/stamp-compiler-version.sh` refuses anything
shorter — and the compiler shortens it itself, by plain truncation. (So when you need
the short form from git, truncate: `git rev-parse '<tag>^{commit}' | cut -c1-9`.
`git rev-parse --short=9` lengthens an ambiguous abbreviation and can disagree.)

The set of fields does not change with how the compiler was built. A build with no
commit recorded — anything not produced by a release run — reports
`commit-hash: unknown` and `commit-date: unknown` rather than dropping the lines, so a
script reading one of them always gets an answer. `rustc -vV` does the same.

The prerelease identifier is reported but never compared, so a candidate satisfies
exactly the same `pragma compiler_version` constraints as the release it is a candidate
for. Contracts that build against `0.34.1` build against `0.34.1-rc.2`.

Builds that are not releases are marked `-dev`, and that is what
`compiler/version-config.ss` carries when committed — so a build nothing stamped says
so, rather than reporting a clean release number it has no claim to. It matters most
because dev publishes are installable: `-dev` sorts below every release of the same
triple, so an external semver-aware version check that wanted a release fails instead
of passing. `compactc` itself does not check — it never compares the part after the
numbers — so a `-dev` build satisfies the same `pragma compiler_version` constraints as
the release.

The one inconsistency a user can notice: the launcher names installed versions after
tags, so `compact list --installed` says `0.34.1` while that compiler's own
`compact compile --version` says `0.34.1 (a1b2c3d4e 2026-09-10)`. Nothing compares the
two, so nothing breaks.

---

## 12. When a step fails

Errors you can meet, what each one means, and what to do. The workflow annotations
carry these exact strings.

| Message | Cause | Action |
| ------- | ----- | ------ |
| `version must be v*.*.* or v*.*.*-<prerelease> (e.g. v1.2.3, v1.2.3-rc.1)` | The typed version fails the format check: missing the leading `v`, or the suffix has characters outside `[0-9A-Za-z.-]` or no leading `-`. | Retype it (§9). |
| `tag v0.35.0-rc.0 is 0.35.0 but compiler/compiler-version.ss says 0.34.1` | The tag's triple disagrees with the version committed on the branch being built. | Fix the version-bump PR (§2 step 3) or the typed version, and run again. |
| `tag … has a suffix that is not a valid semver prerelease identifier` | e.g. `-rc.00` (leading zero), `-rc.` (trailing dot), or a suffix without its leading `-`. | Rename: `-`, then dot-separated identifiers, numbers without leading zeros. |
| `Release notes file 'doc/release-notes/toolchain-x.y.z.md' not found on branch` | The notes file was never committed (§2 step 3). | Add it, or turn the release-notes input off for a throwaway build. |
| `built compiler reports '<got>', expected '<expected>'` | The build did not pick up the stamp, or the stamp script and the compiler disagree about the output format. Nothing has been published — this check runs before upload. | Do not ship. Same version but different commit length means `${COMMIT:0:9}` in the script has drifted from `short-commit-length` in `program-common.ss`; a clean `x.y.z-dev` on a release tag means the stamped file never reached the nix build — investigate before rerunning. |
| `… is not the version-config library; refusing to overwrite it` | The stamp script was pointed at a file that is not `compiler/version-config.ss` — it writes that file whole, so it refuses any other target. | Fix the path it was invoked with; the workflow's own invocation cannot hit this. |
| `tag v0.34.1 already exists at <commit A>, but this build is <commit B>` | The same version was dispatched again after the branch moved, so the tag names a different commit than this build. | A plain re-run of a failed run is safe — same commit, the tag step skips itself. For a new commit: bump the candidate number, or undo the old release first (§7). |
| `Internal release 'compactc-v0.34.1' not found in midnight-ntwrk/artifacts` | Promoting a version that was never built internally. | Run the internal release at exactly that version first (§2 step 8). |
| `No asset found containing architecture 'x86_64-darwin'` | The internal run skipped the Intel macOS build. | Re-run the internal release with **Include MacOS Intel build** on. |
| `internal_version must be a final release matching v*.*.*` | A candidate was offered for promotion. | Cut the final internal build first; promotion copies bytes and never rebuilds. |
| A **Compact Tool Release** run appears and fails right after you tag | Its tag filter has lost the `!compactc-*` exclusion, most likely to a regenerated `compact-release.yml` — dist writes that filter from `tag-namespace` and the exclusions are hand-added. | Nothing was published: dist stops at the plan step, because it reads the text after the namespace as a version. Restore both exclusions under `on.push.tags` (§8). |
| `no v0.34.1 tag on LFDT-Minokawa/compact; the internal release workflow pushes it` | The version being promoted was never built by the internal release workflow, or its tag was deleted. | Cut the final internal release first (§2 step 8); §7 covers recreating what a deleted release leaves behind. |
| `promoted binary reports '…', expected '…'` | The artifacts-store release at this tag no longer matches the `vX.Y.Z` commit — usually a re-run replaced the bytes after QA signed off. | Do not promote. Rebuild the final at the released commit, or work out what replaced the assets (§7). |
| `compactc --language-version reports '…', which is not x.y.z` | The binary printed something other than a bare triple, so either the archive does not hold compactc or the flag's output format moved. | Do not promote. Check what the archive contains, then `print-language-version` in `compiler/program-common.ss`. |
| `no compactc-v0.34.1 release in midnight-ntwrk/artifacts; the language version is read from that build` | **Copy release notes to midnight-docs** was given a toolchain version that was never published. | Correct the version, or cut the release first — that workflow reads the language version off the build, so it cannot run ahead of one. |
| The `compact` tool's tests fail after `LATEST_COMPACTC_VERSION` moved | Recorded outputs embed what the compiler prints, and a stamped compiler prints version, commit and date — which change with the release. | Re-record from the failing test's diff (§2 step 10). |
| `commit '…' is not a full 40-character hash` / `commit date '…' is not YYYY-MM-DD` | The stamp script was run by hand with the wrong arguments. | Pass `git rev-parse HEAD` and `git show -s --format=%cs HEAD`; the compiler derives the short form itself. |
