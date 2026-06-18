# On-demand dev builds of the Compact toolchain

The `On-demand dev publish of compact toolchain` workflow
(`.github/workflows/dev-publish.yml`) produces installable compactc + runtime
artifacts for any branch or commit, without cutting a tagged release. It exists
so downstream consumers (midnight-js, midnight-node, compact-js,
midnight-toolkit) can pin a dev coordinate instead of cloning this repo and
Nix-building compactc on every CI run.

## What it produces

| Artifact          | Coordinate                                                         | Where                                              |
| ----------------- | ----------------------------------------------------------------- | -------------------------------------------------- |
| compact-runtime   | `@midnight-ntwrk/compact-runtime@<base>-dev.<sha>`                 | GitHub Packages npm, scope `@midnight-ntwrk`       |
| compactc binary   | release tag `compactc-dev-<sha>` (assets per architecture)        | GitHub prerelease on `LFDT-Minokawa/compact`       |

`<base>` is the current `version` from `runtime/package.json`; `<sha>` is the
full 40-char commit SHA (`git rev-parse HEAD`) of the resolved ref -- full, not
abbreviated, so the coordinate is unambiguous and cannot collide.

The runtime is published under npm dist-tag `dev`, so it never moves `latest`.
The binary release is flagged `prerelease`, so it never becomes "Latest release".

## Trigger contract

- **How:** Actions tab -> "On-demand dev publish of compact toolchain" -> Run
  workflow. Manual (`workflow_dispatch`) only -- no push/PR/schedule trigger.
- **Who:** anyone with write access to this repository.
- **Inputs:**
  - `branch` (required) -- branch or ref to build and publish from.
  - `publish_runtime` (default true) -- publish the runtime npm package.
  - `publish_compiler` (default true) -- publish the compactc binary prerelease.
  - `include_linux_arm` (default true), `include_macos_arm` (default false),
    `include_macos_intel` (default false) -- extra binary targets. Linux x86_64
    is always built and is the gate for publishing the binary prerelease.

## How to consume

Runtime (downstream `package.json`), pin the exact dev version:

```jsonc
"@midnight-ntwrk/compact-runtime": "0.16.101-dev.<full-commit-sha>"
```

with an `.npmrc` mapping the scope to GitHub Packages:

```
@midnight-ntwrk:registry=https://npm.pkg.github.com/
//npm.pkg.github.com/:_authToken=${NODE_AUTH_TOKEN}
```

compactc binary, download the per-arch asset from the
`compactc-dev-<sha>` prerelease, e.g.:

```
gh release download compactc-dev-<full-commit-sha> \
  --repo LFDT-Minokawa/compact \
  --pattern 'compactc_dev-<full-commit-sha>_x86_64-unknown-linux-musl.zip'
```

## Retention policy

Dev builds are convenience artifacts, not supported releases.

- **npm:** `*-dev.*` versions are published under dist-tag `dev` only. They are
  immutable (a given `dev.<sha>` cannot be republished) and remain resolvable
  for pinning. Old dev versions should be pruned to the most recent ~30 / ~30
  days; GitHub Packages does not expire npm versions automatically, so this is a
  manual/scheduled cleanup (tracked as a fast-follow; not wired up by this
  workflow).
- **binary:** `compactc-dev-*` prereleases follow the same intent -- keep the
  most recent handful, delete older ones. They are excluded from "Latest
  release" by the `prerelease` flag.

Treat any `dev.<sha>` coordinate as "valid until pruned." For anything that must
stay resolvable long-term, promote it to a real tagged release via the existing
`internal-release` / `public-release` workflows.

## Relationship to the release workflows

- `internal-release.yml` / `public-release.yml` -- the supported, versioned
  release path (tag-driven, build all four platforms, GitHub releases on the
  `midnight-ntwrk/artifacts` + public repos). Unchanged.
- `dev-publish.yml` -- this on-demand path. Reuses the same reusable building
  blocks (`release-build.yml`, `release-test.yml`) for the binary, and the same
  `nix build .#runtime.forPublish` derivation for the runtime, so it does not
  fork the build logic.
