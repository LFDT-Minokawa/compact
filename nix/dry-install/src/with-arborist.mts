// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// 	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Arborist, { Edge } from '@npmcli/arborist';
import { array, option, record } from 'fp-ts';
import { pipe } from 'fp-ts/lib/function.js';
import * as t from 'io-ts';

const PackageDirCodec = t.readonly(
  t.type({
    dir: t.string,
  }),
);
export type PackageDir = t.TypeOf<typeof PackageDirCodec>;

const PackageCodec = t.readonly(
  t.intersection([
    PackageDirCodec,
    t.type({
      type: t.union([t.literal('dev'), t.literal('prod')]),
    }),
  ]),
);
export type Package = t.TypeOf<typeof PackageCodec>;

const HasTarPathCodec = t.readonly(
  t.type({
    tar: t.string,
  }),
);
export type HasTarPath = t.TypeOf<typeof HasTarPathCodec>;

export const DependencyCodec = t.readonly(t.intersection([PackageCodec, HasTarPathCodec]));
export type Dependency = t.TypeOf<typeof DependencyCodec>;

const HasVersionCodec = t.readonly(t.type({
  version: t.string
}));
export type HasVersion = t.TypeOf<typeof HasVersionCodec>;
export const VersionedDependencyCodec = t.readonly(t.intersection([DependencyCodec, HasVersionCodec]));
export type VersionedDependency = t.TypeOf<typeof VersionedDependencyCodec>;

export const DepsCodec = t.readonlyArray(DependencyCodec);
export type Deps = t.TypeOf<typeof DepsCodec>;

export type NewDependencies = Record<string, VersionedDependency>;

export async function arboristDryInstall(
  dependant: PackageDir,
  dependencies: Deps,
): Promise<{
  readonly tree: Arborist;
  readonly newDependencies: NewDependencies;
}> {
  const dependantTree = new Arborist({
    path: dependant.dir,
    offline: true,
  });
  console.log(`Loading main tree from ${dependant.dir}`);
  const dependantLoaded = await dependantTree.loadVirtual();

  let newDependencies: NewDependencies = {};
  for await (const dependency of dependencies) {
    console.log(`Loading dependency tree from ${dependency.dir}`);
    const dependencyTree = await addDependency(dependency, dependantLoaded);
    newDependencies = { ...newDependencies, [dependencyTree.name]: {...dependency, version: dependencyTree.package.version! }};
  }

  console.log('Building final tree');
  await buildFinalTree(dependantTree, dependantTree.virtualTree!, newDependencies);

  return {
    tree: dependantTree,
    newDependencies,
  };
}

async function loadDependencyTree(dependency: Dependency): Promise<Arborist.Node> {
  const dependencyTree = new Arborist({
    offline: true,
    path: dependency.dir,
  });

  return await dependencyTree.loadVirtual();
}

async function addDependency(dependency: Dependency, dependantTree: Arborist.Node): Promise<Arborist.Node> {
  const dependencyLoaded = await loadDependencyTree(dependency);
  dependencyLoaded.name = dependencyLoaded.package.name!;
  // Interesting - things fail if we update package.json contents
  // Similarly - we cannot reify without `save: true`, as if arborist
  // was making sure everything is handled in the best possible way
  const targetDeps = dependency.type === 'dev' ? 'devDependencies' : 'dependencies';
  if (!dependantTree.package[targetDeps]) {
    dependantTree.package[targetDeps] = {};
  }
  dependantTree.package[targetDeps]![dependencyLoaded.package.name!] = dependency.tar;
  dependantTree.children.set(dependencyLoaded.name, dependencyLoaded);
  dependencyLoaded.parent = dependantTree;
  dependencyLoaded.root = dependantTree;
  // @ts-ignore Typings provided are for older version, there are some differences
  // eslint-disable-next-line @typescript-eslint/no-unsafe-call
  dependencyLoaded.addEdgeIn(
    new Edge({
      from: dependantTree,
      name: dependencyLoaded.package.name!,
      type: dependency.type,
      spec: dependency.tar,
    }),
  );
  return dependencyLoaded;
}

async function buildFinalTree(
  arboristRoot: Arborist,
  virtualTree: Arborist.Node,
  newDependencies: NewDependencies,
  attemptsLeft: number = 2,
): Promise<void> {
  try {
    await arboristRoot.buildIdealTree({
      preferDedupe: true,
      prune: true,
    });
  } catch (e) {
    const invalidEdges = getInvalidEdges(arboristRoot.idealTree, newDependencies);
    if (attemptsLeft > 0) {
      console.warn('Found issues with dependency tree, trying to fix them');
      console.log(
        'Invalid edges',
        invalidEdges.map((e) => ({
          name: e.invalidEdge.name,
          from: e.invalidEdge.from?.name,
          to: e.invalidEdge.to?.name,
        })),
      );
      await fixInvalidEdges(arboristRoot, virtualTree, invalidEdges);
      return await buildFinalTree(arboristRoot, virtualTree, newDependencies, attemptsLeft - 1);
    } else if (invalidEdges.length === 0) {
      console.log('Looks like all issues were addressed, proceeding');
    } else {
      throw new Error('Could not resolve all dependencies within the tree', { cause: e });
    }
  }
}

function getInvalidEdges(
  tree: Arborist.Node | null | undefined,
  newDependencies: NewDependencies,
): Array<{ dependency: Dependency | null; invalidEdge: Edge }> {
  return pipe(
    newDependencies,
    record.toEntries,
    array.chain(([name, dependency]) => {
      const childNode = tree?.children.get(name);
      const allEdges: Map<string, Edge> = pipe(
        option.fromNullable(childNode),
        option.map(getEdgesOut),
        option.getOrElse(() => new Map<string, Edge>()),
      );
      return Array.from(allEdges.values())
        .filter((edge: Edge): boolean => !edge.valid)
        .map((edge) => ({
          dependency,
          invalidEdge: edge,
        }));
    }),
  );
}

function getEdgesOut(tree: Arborist.Node): Map<string, Edge> {
  return tree.edgesOut as unknown as Map<string, Edge>;
}

// Let's try to forcefully rewire edges arborist is complaining about
// Most probably arborist just relies on access to network to resolve potential conflicts
async function fixInvalidEdges(
  root: Arborist,
  virtualTree: Arborist.Node,
  invalidEdges: Array<{ dependency: Dependency | null; invalidEdge: Edge }>,
) {
  for await (const { dependency, invalidEdge } of invalidEdges) {
    const freshDependencyTree = dependency ? await loadDependencyTree(dependency) : virtualTree;
    const resolvedEdge = getEdgesOut(freshDependencyTree).get(invalidEdge.name)!;
    const newTo = resolvedEdge.to!;
    const { type, name } = invalidEdge;
    const from = invalidEdge.from!;
    const to = invalidEdge.to!;
    // @ts-ignore Typings provided are for older version, there are some differences
    // eslint-disable-next-line @typescript-eslint/no-unsafe-call
    invalidEdge.detach();
    from.parent?.children.delete(name);
    to.parent = null;

    from.children.set(name, newTo);
    newTo.parent = from;
    const targetDeps: 'devDependencies' | 'optionalDependencies' | 'peerDependencies' | 'dependencies' =
      type === 'dev'
        ? 'devDependencies'
        : type === 'optional'
        ? 'optionalDependencies'
        : type === 'peer'
        ? 'peerDependencies'
        : 'dependencies';
    from.package[targetDeps]![newTo.package.name!] = newTo.resolved!;

    // @ts-ignore Typings provided are for older version, there are some differences
    // eslint-disable-next-line @typescript-eslint/no-unsafe-call
    newTo.addEdgeIn(
      new Edge({
        from,
        name,
        type,
        spec: '',
      }),
    );
  }

  root.virtualTree = root.idealTree;
  root.idealTree = null;
}
