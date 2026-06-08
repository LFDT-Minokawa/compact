# Compact Test Contracts

This package contains self-contained Compact semantic fixtures. Each fixture
directory owns its Compact source and the tests that declare whether that source
should pass or fail at compile time or runtime.

## Fixture Layout

```text
test-contracts/
  primitives/
    bytes/
      slice/
        basic/
          bytes_slice_basic.compact
          compile.pass.test.ts
          runtime.pass.test.ts
```

Test expectations are intentionally visible from file names:

- Compile pass: `compile.pass.test.ts` expects the colocated `.compact` file to compile.
- Compile fail: `compile.fail.test.ts` expects the colocated `.compact` file to fail compilation.
- Runtime pass: `runtime.pass.test.ts` expects the generated contract to execute successfully.
- Runtime fail: `runtime.fail.test.ts` expects runtime execution to throw.

Each fixture directory must contain exactly one `.compact` file. Runtime tests
require a matching `compile.pass.test.ts` file in the same fixture directory.

## Execution Model

Vitest only loads `compact-test-orchestrator.test.ts`. That orchestrator
discovers fixture files, registers compile tests, and lets each runtime test
await its own cached compile prerequisite before importing generated artifacts.

This keeps compilation visible as part of the test suite while allowing runtime
tests to type against generated `Contract` imports for hover and
go-to-definition. Fixtures under a `slow/` path segment still run by default,
but their compile work runs exclusively so expensive proving-key generation does
not race other compiler jobs.

## Compile Tests

Compile tests export metadata through `defineCompileTest`:

```ts
import { defineCompileTest } from '@test/compact-test';

export default defineCompileTest(import.meta.url);
```

For compile-fail fixtures, include the diagnostic that proves the expected
failure happened:

```ts
export default defineCompileTest(import.meta.url, {
    expectedError: /expected tuple\/vector spread expression/,
});
```

## Runtime Tests

Runtime tests statically import the generated contract path for their fixture
and export metadata through `defineRuntimeTest`:

```ts
import { expect } from 'vitest';

import type { Contract } from './.build/contract/index.js';
import {
    createTestContract,
    defineRuntimeTest,
} from '@test/compact-test';

export default defineRuntimeTest<typeof Contract>(import.meta.url, (Contract) => {
    const { contract, ctx } = createTestContract(Contract);
    const result = contract.circuits.bytes_slice_basic(ctx).result;

    expect(Array.from(result)).toEqual([5]);
});
```

The generated type import is valid during local typechecking because
`yarn lint` prepares runtime fixture artifacts before running
`tsc --noEmit`. Runtime execution imports the generated `Contract` value from
the fixture `.build/` directory after the matching compile test has completed,
then passes it to the fixture callback.

## Generated Artifacts

The runner writes generated output under each fixture's local `.build/`
directory. It removes stale output before compiling each selected fixture, then
reuses that output for the matching runtime test.

After the suite finishes, artifacts for selected fixtures whose tests passed are
deleted. Artifacts for fixtures with unexpected failures are preserved for
debugging, including failed runtime imports, failed runtime assertions, and
unexpected compile results. Expected failures that pass, such as
`compile.fail.test.ts`, are cleaned up like any other passing fixture.

Set `COMPACT_TEST_KEEP_ARTIFACTS=1` to preserve passing fixture artifacts during
local debugging:

```sh
COMPACT_TEST_KEEP_ARTIFACTS=1 yarn test primitives/bytes/slice/basic/runtime.pass.test.ts
```

## Commands

Run from this package directory:

```sh
corepack yarn install --immutable
yarn lint
yarn test
yarn test primitives/bytes/slice/basic/runtime.pass.test.ts
```

`yarn test` runs all fixtures. Non-option arguments are treated as
fixture or test-file path filters. Selecting a runtime test also selects its
compile prerequisite, so a runtime-only filtered run still compiles the fixture
inside Vitest before importing the generated contract value.

The package links `@midnight-ntwrk/compact-runtime` to `../runtime`, so the
runtime must be built locally before fixtures run. The easiest local command
from the repository root is:

```sh
./test-contracts/test.sh
```

That wrapper builds `runtime`, installs this package with Corepack/Yarn, and
runs the fixtures with the Nix-built `compactc` compiler. Compile hang
protection is owned by Vitest and CI through `testTimeout` in
`vitest.config.ts`. `yarn lint` prepares generated imports with `--skip-zk`;
`yarn test` uses full compiler runs so compile tests still cover proving-key
generation.
