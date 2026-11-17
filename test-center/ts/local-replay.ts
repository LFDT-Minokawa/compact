// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
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

// The randomized replay test (plan §4.3; V1, widened). Tier 1 claims that applying a call's record
// to a capsule is re-executing the call there whenever the fold accepts. A call is prepared against
// one capsule and its record folded onto another; re-execution is the same call run on the fold's
// capsule with the same arguments, ledger state and host answers, as tier 2 will run it. Whenever
// the fold accepts, the two agree in local state, local record, public transcript, private inputs,
// host outputs and result; whenever it refuses, re-execution records something else; and every
// record replays onto the capsule it was made on. LOCAL_REPLAY_SEED and LOCAL_REPLAY_ROUNDS widen
// the search.

const DICE = 'test:oracle/dice@1.0.0';
const COIN = '0'.repeat(64);
const SEED = Number(process.env.LOCAL_REPLAY_SEED ?? 20261005);
const ROUNDS = Number(process.env.LOCAL_REPLAY_ROUNDS ?? 3);

type World = { readonly ledger: runtime.ChargedState; readonly local: runtime.StateValue };
type Move = { readonly circuit: string; readonly args: readonly unknown[]; readonly answers: readonly bigint[] };
// a capsule reached from another by the moves that landed; a move that faults does not land
type Reached = { readonly world: World; readonly landed: readonly Move[] };
type Ran = { readonly result: unknown; readonly record: runtime.CallProofData; readonly after: World };
type Draw = { readonly int: (n: number) => number; readonly u: (n: number) => bigint };

// small domains, so that calls collide on keys and leaves
const ARGS: Record<string, (d: Draw) => unknown[]> = {
  note: (d) => [d.u(6)],
  forget: (d) => [d.u(6)],
  score: (d) => [d.u(6), d.u(10)],
  spend: (d) => [1n + d.u(3)],
  spendLevel: () => [],
  walk: () => [],
  push: (d) => [d.u(6)],
  pop: () => [],
  plant: (d) => [d.u(6), d.int(2) === 0],
  prove: (d) => [d.u(4), d.u(6)],
  find: (d) => [d.u(6)],
  seal: () => [],
  gamble: () => [],
  raise: () => [],
  fire: () => [],
  stamp: () => [],
  post: (d) => [d.u(6)],
  book: (d) => [d.u(4)],
  purge: (d) => [d.u(7)],
  decay: () => [],
  drain: () => [],
  wipe: (d) => [d.u(4)],
  census: () => [],
};

// capsules are built favouring the calls that fill containers and spend counters, so walks, trees
// and underflows have something to find
const WEIGHTS: Record<string, number> = { note: 3, plant: 3, push: 2, score: 2, book: 2, spend: 3, spendLevel: 2 };

// for each circuit that observes local state beyond the local constructor's guard, calls that
// change what it observes, so that some folds are refused for its own observations
const RIVALS: Record<string, (args: readonly unknown[], d: Draw) => [string, unknown[]][]> = {
  forget: ([k]) => [['note', [k]], ['forget', [k]], ['wipe', [0n]]],
  score: ([k], d) => [['score', [k, 1n + d.u(9)]], ['decay', []], ['wipe', [1n]]],
  spend: () => [['spend', [2n]]],
  spendLevel: (_, d) => [['raise', []], ['post', [d.u(6)]], ['spend', [2n]]],
  walk: (_, d) => [['note', [d.u(6)]], ['score', [d.u(6), 1n + d.u(9)]], ['push', [d.u(6)]], ['raise', []]],
  pop: (_, d) => [['push', [d.u(6)]], ['pop', []], ['drain', []], ['wipe', [2n]]],
  plant: (_, d) => [['plant', [d.u(6), false]]],
  prove: (_, d) => [['plant', [d.u(6), false]], ['wipe', [3n]]],
  find: ([leaf]) => [['plant', [leaf, false]], ['wipe', [3n]]],
  seal: (_, d) => [['plant', [d.u(6), false]], ['wipe', [3n]]],
  gamble: (_, d) => [['raise', []], ['post', [d.u(6)]]],
  fire: () => [['gamble', []], ['fire', []]],
  stamp: (_, d) => [['raise', []], ['post', [d.u(6)]]],
  post: ([x]) => [['note', [x]], ['forget', [x]]],
  book: ([k]) => [['book', [k]]],
  purge: (_, d) => [['note', [d.u(6)]], ['forget', [d.u(6)]]],
  decay: (_, d) => [['score', [d.u(6), 1n + d.u(9)]]],
  drain: (_, d) => [['push', [d.u(6)]], ['pop', []], ['raise', []]],
  census: (_, d) => [['note', [d.u(6)]], ['score', [d.u(6), 1n + d.u(9)]], ['push', [d.u(6)]], ['spend', [2n]]],
};

// JSON with bigints and bytes spelled out, so records, transcripts and results compare as text
const canon = (x: unknown): string =>
  JSON.stringify(x, (_, v) =>
    typeof v === 'bigint'
      ? `${v}n`
      : v instanceof Uint8Array
        ? Array.from(v, (b) => b.toString(16).padStart(2, '0')).join('')
        : v,
  ) ?? 'undefined';

// the stretch of two renderings around their first difference
const around = (a: string, b: string): [string, string] => {
  let i = 0;
  while (i < a.length && a[i] === b[i]) i++;
  const from = Math.max(0, i - 80);
  const cut = (s: string) => `${from > 0 ? '…' : ''}${s.slice(from, i + 240)}${s.length > i + 240 ? '…' : ''}`;
  return [cut(a), cut(b)];
};

const show = (moves: readonly Move[]): string =>
  moves.map((m) => `${m.circuit}(${m.args.map(String).join(', ')})`).join(' ') || '(none)';

const digest = (sv: runtime.StateValue): string => runtime.stateValueDigest(sv);

test('the fold accepts exactly the records re-execution reproduces, and then agrees with it', async () => {
  // mulberry32, so a failure names the seed that reproduces it
  let state = SEED;
  const random = (): number => {
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const draw: Draw = { int: (n) => Math.floor(random() * n), u: (n) => BigInt(Math.floor(random() * n)) };
  const names = Object.keys(ARGS);
  const pool = names.flatMap((n) => Array<string>(WEIGHTS[n] ?? 1).fill(n));
  const move = (circuit: string, args: readonly unknown[] = ARGS[circuit](draw)): Move => ({
    circuit,
    args,
    answers: [draw.u(8), draw.u(8), draw.u(8), draw.u(8)],
  });
  const moves = (lo: number, hi: number, pick = (): string => pool[draw.int(pool.length)]): Move[] =>
    Array.from({ length: lo + draw.int(hi - lo + 1) }, () => move(pick()));
  const rivalsOf = (call: Move): Move[] => {
    const rivals = RIVALS[call.circuit]?.(call.args, draw);
    if (rivals === undefined) return moves(1, 3);
    return Array.from({ length: 1 + draw.int(2) }, () => {
      const [circuit, args] = rivals[draw.int(rivals.length)];
      return move(circuit, args);
    });
  };

  const contract = new contractCode.Contract();
  // the circuits run without the harness's proof checks, which hundreds of calls cannot afford
  const circuits = contract.impureCircuits as unknown as Record<
    string,
    (context: runtime.CircuitContext, ...args: unknown[]) => Promise<runtime.CircuitResults<unknown>>
  >;
  expect([...names].sort()).toEqual(Object.keys(circuits).sort());
  const deployed = await contract.initialState(runtime.createConstructorContext(COIN));
  const address = runtime.dummyContractAddress();
  const fresh: Reached = {
    world: { ledger: deployed.currentContractState.data, local: contractCode.initialLocalState() },
    landed: [],
  };

  const run = async (world: World, m: Move): Promise<Ran | string> => {
    let next = 0;
    const context = withHostInterfaces(
      runtime.createCircuitContext({
        circuitId: m.circuit,
        contractAddress: address,
        coinPublicKeyOrZswapState: COIN,
        contractState: world.ledger,
        localState: world.local,
        time: 0,
      }),
      { [DICE]: { roll: () => m.answers[next++ % m.answers.length] } },
    );
    try {
      const r = await circuits[m.circuit](context, ...m.args);
      return {
        result: r.result,
        record: r.context.callProofDataTrace.at(-1)!,
        after: {
          ledger: r.context.callContext.currentQueryContext.state,
          local: r.context.callContext.currentLocalQueryContext!.state.state,
        },
      };
    } catch (e) {
      // a fault means the call does not land; any other error is the test's own
      if (e instanceof runtime.CompactError) return e.message;
      throw e;
    }
  };
  const land = async (world: World, ms: readonly Move[]): Promise<Reached> => {
    const landed: Move[] = [];
    for (const m of ms) {
      const r = await run(world, m);
      if (typeof r !== 'string') {
        world = r.after;
        landed.push(m);
      }
    }
    return { world, landed };
  };

  const stats = Object.fromEntries(
    names.map((n) => [n, { faulted: 0, acceptedSame: 0, acceptedChanged: 0, refused: 0 }]),
  );
  const refusals = { guard: 0, observation: 0, read: 0, fault: 0 };
  const violations: string[] = [];
  let trials = 0;
  const guardOf = (sv: runtime.StateValue): string => digest(sv.asArray()![0]);

  // `prepared` is reached from `history` and is what the call ran against; `folded` is reached
  // from `history` too and is what its record is folded onto
  const check = async (fate: string, history: Reached, prepared: Reached, ran: Ran, folded: Reached, call: Move) => {
    trials++;
    const where = (): string =>
      `${fate}, seed ${SEED}, trial ${trials}\n  history: ${show(history.landed)}\n  then prepared against: ${show(prepared.landed)}` +
      `\n  then folded onto: ${show(folded.landed)}\n  call: ${show([call])}, host answers ${call.answers.join(', ')}`;
    const record = ran.record.localTranscript ?? [];
    const verdict = foldCall(folded.world.local, ran.record);
    const rerun = await run({ ledger: prepared.world.ledger, local: folded.world.local }, call);
    const tally = stats[call.circuit];
    if (verdict.tag === 'folded') {
      if (typeof rerun === 'string') {
        violations.push(`the fold accepted a call re-execution fails (${rerun}): ${where()}`);
      } else {
        const differs = (
          [
            ['local state', digest(verdict.state), digest(rerun.after.local)],
            ['local record', canon(record), canon(rerun.record.localTranscript ?? [])],
            ['public transcript', canon(ran.record.publicTranscript), canon(rerun.record.publicTranscript)],
            ['private inputs', canon(ran.record.privateTranscriptOutputs), canon(rerun.record.privateTranscriptOutputs)],
            ['host outputs', canon(ran.record.hostOutputs), canon(rerun.record.hostOutputs)],
            ['result', canon(ran.result), canon(rerun.result)],
          ] as const
        ).filter(([, a, b]) => a !== b);
        if (differs.length > 0) {
          violations.push(
            `the fold accepted, but re-execution differs in ${differs.map(([what]) => what).join(', ')}: ${where()}\n` +
              differs
                .map(([what, a, b]) => {
                  const [x, y] = around(a, b);
                  return `  ${what}, fold: ${x}\n  ${what}, re-execution: ${y}`;
                })
                .join('\n'),
          );
        }
      }
      if (digest(folded.world.local) === digest(prepared.world.local)) tally.acceptedSame++;
      else tally.acceptedChanged++;
    } else {
      if (typeof rerun !== 'string' && canon(rerun.record.localTranscript ?? []) === canon(record)) {
        violations.push(`the fold refused a record re-execution reproduces (${describeDivergence(verdict.divergence)}): ${where()}`);
      }
      tally.refused++;
      // a differing guard is the local constructor's observation; past it, the VM's wording tells
      // a read that differs from an operation that faults
      refusals[
        guardOf(prepared.world.local) !== guardOf(folded.world.local)
          ? 'guard'
          : verdict.divergence.kind === 'ObservationMismatch'
            ? 'observation'
            : /mismatch between expected/.test(verdict.divergence.message)
              ? 'read'
              : 'fault'
      ]++;
    }
  };
  const replaysOnItsOwn = (history: Reached, prepared: Reached, ran: Ran, call: Move) => {
    const own = foldCall(prepared.world.local, ran.record);
    if (own.tag === 'diverged' || digest(own.state) !== digest(ran.after.local)) {
      violations.push(
        `a record does not replay onto the capsule it was made on (${own.tag === 'diverged' ? describeDivergence(own.divergence) : 'a different state'}):` +
          ` seed ${SEED}\n  history: ${show(history.landed)}\n  then: ${show(prepared.landed)}\n  call: ${show([call])}`,
      );
    }
  };

  for (let round = 0; round < ROUNDS; round++) {
    for (const name of names) {
      const history = await land(fresh.world, moves(1, 6));
      const call = move(name);
      // prepared against the history, folded after calls landed meanwhile: any, the same
      // circuit's, or ones changing what the call observed
      const onHistory = await run(history.world, call);
      if (typeof onHistory === 'string') stats[name].faulted++;
      else {
        const prepared: Reached = { world: history.world, landed: [] };
        replaysOnItsOwn(history, prepared, onHistory, call);
        await check('landed', history, prepared, onHistory, await land(history.world, moves(1, 3)), call);
        await check('twin', history, prepared, onHistory, await land(history.world, moves(1, 2, () => name)), call);
        await check('rival', history, prepared, onHistory, await land(history.world, rivalsOf(call)), call);
        await check('rival', history, prepared, onHistory, await land(history.world, rivalsOf(call)), call);
      }
      // prepared against calls still in flight, folded after one of them failed and others
      // landed, or after none of them landed
      const inFlight = await land(history.world, moves(1, 2));
      const onInFlight = await run(inFlight.world, call);
      if (typeof onInFlight === 'string') stats[name].faulted++;
      else {
        replaysOnItsOwn(history, inFlight, onInFlight, call);
        await check('sibling', history, inFlight, onInFlight, await land(history.world, moves(1, 3)), call);
        await check('unlanded', history, inFlight, onInFlight, { world: history.world, landed: [] }, call);
      }
      // two first calls raced: prepared against the fresh capsule, folded after the other landed
      if (round === 0) {
        const onFresh = await run(fresh.world, call);
        if (typeof onFresh === 'string') stats[name].faulted++;
        else {
          replaysOnItsOwn(fresh, fresh, onFresh, call);
          await check('fresh', fresh, fresh, onFresh, await land(fresh.world, moves(1, 2)), call);
        }
      }
    }
  }

  expect(violations, `${violations.length} of ${trials} trials; the first:\n${violations.slice(0, 3).join('\n\n')}`).toEqual([]);
  // a search that never reached a circuit's two verdicts, or some kind of refusal, proved little
  const coverage =
    `a coverage shortfall, not a replay violation (seed ${SEED}, ${ROUNDS} rounds, ${trials} trials; more rounds widen it):\n` +
    names.map((n) => `  ${n}: ${JSON.stringify(stats[n])}`).join('\n') +
    `\n  refusals: ${JSON.stringify(refusals)}`;
  expect(names.filter((n) => stats[n].acceptedChanged === 0 || stats[n].refused === 0), coverage).toEqual([]);
  expect(Object.entries(refusals).filter(([, n]) => n === 0).map(([kind]) => kind), coverage).toEqual([]);
}, Math.max(180_000, ROUNDS * 60_000));
