// kw_harness.mjs — offline driver for watch.mjs (no network, no live room).
// Normal entry point is tests/run.sh; standalone for A/B runs:
//   node kw_harness.mjs <repo-copy-dir> <out-file>
// Stubs fetch + WebSocket, feeds a scripted snap/patch sequence, captures
// everything written to stdout, then fires a non-fatal close: the watcher
// must reconnect on its own, after which the harness SIGTERMs itself
// (watch.mjs flushes the party file on the signal and exits 0).
// KSTUB_NETFAIL=1 makes fetch reject, to exercise the token-failure path.
// KSTUB_CLOSE=<code> fires that close code instead of the reconnect dance:
// for a fatal code (4404 room-gone; 4403 refused shares the path) watch.mjs
// must flush the party file and exit itself. The harness appends a late
// pass event after the last new-round boundary, so that entry's presence
// in the party file proves the onclose flush.
import { writeFileSync } from 'fs';
import { join } from 'path';

const [repo, outFile] = [process.argv[2], process.argv[3]];
process.argv = [process.argv[0], join(repo, 'watch.mjs'), 'TEST'];

const netFail = !!process.env.KSTUB_NETFAIL;   // fetch rejects -> token failure path
const closeCode = process.env.KSTUB_CLOSE ? Number(process.env.KSTUB_CLOSE) : null;

// a live connection holds a ref'd event-loop handle; emulate it so the
// harness mirrors reality (a dead socket — after onclose — must hold none,
// or the reconnect bug below gets masked)
globalThis.fetch = netFail
  ? async () => { throw new Error('fetch failed: ENOTFOUND'); }
  : async () => ({ json: async () => ({ token: 'FAKE' }) });
let builds = 0;
const socks = [];
globalThis.WebSocket = class {
  constructor(url) {
    this.url = url; builds++;
    this._keep = setInterval(() => {}, 1000);
    socks.push(this);
  }
  close() {}
};
const last = () => socks[socks.length - 1];

// scripted sequence: covers event replay (incl. duplicate + tierless pass
// events, non-pass event), non-JSON and non-object frames (dropped, the
// watcher keeps running), string/object lastAnswer, unchanged patch (no
// redraw), player update, and three new-round patches (flush + reset).
// Round-provenance cases (the cross-round contamination fix):
//  - p4 Dave's snap lastAnswer has no pass event: a round-start value is
//    neither recorded nor shown as said;
//  - the round-2 patch carries the players array BEFORE the server cleared
//    lastAnswer: every carried value is baselined, none is recorded under
//    the new question, while the 'Go' pass event (== p1's baseline) proves
//    events are recorded unconditionally;
//  - p4's round-2 lastAnswer change is a post-round-start transition and
//    must still be recorded via the state channel.
// Round 2 is a party-only question (lookup from the pre-seeded party file),
// round 3 is a case-variant of the daily question — exact mode must NOT
// match it (a fuzzy fallback would leak the daily list into the draw).
const msgs = [
  { t: 'snap', room: {
      code: 'TEST', phase: 'answer',
      players: [
        { id: 'p1', name: 'Alice', alive: true,  lastAnswer: { text: 'Go', tier: 'rare' } },
        { id: 'p2', name: 'Bob',   alive: true,  lastAnswer: 'Rithmomachia' },
        { id: 'p3', name: 'Cara',  alive: false, lastAnswer: null },
        { id: 'p4', name: 'Dave',  alive: true,  lastAnswer: { text: 'Stale snap', tier: 'schooler' } },
      ],
      category: { index: 1, text: 'Name a strategy board game' },
      events: [
        { kind: 'pass', answer: 'Go', tier: 'rare' },
        { kind: 'pass', answer: 'Go', tier: 'rare' },   // dup event: must count twice
        { kind: 'pass', answer: 'Rithmomachia' },        // no tier -> null
        { kind: 'roll', dice: 3 },                       // non-pass: ignored
      ],
  } },
  { t: 'patch', patch: { events: [{ kind: 'pass', answer: 'Gomoku', tier: 'schooler' }] } },
  { t: 'ping' },                                    // unknown type -> ignored, no redraw
  '{ not json',                                     // non-JSON frame -> dropped, keeps running
  'null',                                           // JSON, not an object -> dropped, keeps running
  { t: 'patch' },                                   // no patch field -> no crash
  { t: 'patch', patch: { set: { phase: 'answer' } } },   // no change -> no redraw
  { t: 'patch', patch: { set: { players: [
      { id: 'p1', name: 'Alice', alive: true,  lastAnswer: { text: 'Go', tier: 'rare' } },
      { id: 'p2', name: 'Bob',   alive: false, lastAnswer: 'Rithmomachia' },
      { id: 'p3', name: 'Cara',  alive: true,  lastAnswer: { text: 'No tier answer' } },
      { id: 'p4', name: 'Dave',  alive: true,  lastAnswer: { text: 'Stale snap', tier: 'schooler' } },
  ] } } },
  { t: 'patch', patch: {
      set: { phase: 'answer',
             category: { index: 2, text: 'A party-only question nobody asked daily' },
             players: [   // stale: round 1's array carried with the new category
      { id: 'p1', name: 'Alice', alive: true,  lastAnswer: { text: 'Go', tier: 'rare' } },
      { id: 'p2', name: 'Bob',   alive: false, lastAnswer: 'Rithmomachia' },
      { id: 'p3', name: 'Cara',  alive: true,  lastAnswer: { text: 'No tier answer' } },
      { id: 'p4', name: 'Dave',  alive: true,  lastAnswer: { text: 'Stale snap', tier: 'schooler' } },
  ] },
      events: [
        { kind: 'pass', answer: 'Fresh answer', tier: 'plankton' },
        { kind: 'pass', answer: 'Go', tier: 'rare' },   // == p1's baseline: events are unconditional
      ],
  } },
  { t: 'patch', patch: { set: { players: [   // Dave answers in round 2: a transition
      { id: 'p1', name: 'Alice', alive: true,  lastAnswer: { text: 'Go', tier: 'rare' } },
      { id: 'p2', name: 'Bob',   alive: false, lastAnswer: 'Rithmomachia' },
      { id: 'p3', name: 'Cara',  alive: true,  lastAnswer: { text: 'No tier answer' } },
      { id: 'p4', name: 'Dave',  alive: true,  lastAnswer: { text: 'Trick answer', tier: 'rare' } },
  ] } } },
  { t: 'patch', patch: { set: { phase: 'answer', category: { index: 3, text: 'name a strategy board game' } } } },
];

const drawn = [];
const realWrite = process.stdout.write.bind(process.stdout);
process.stdout.write = (c, ...r) => { drawn.push(String(c)); return true; };

// fatal-close variant: the late answer lands after the last new-round
// boundary, so at close time it is still only in memory
if (closeCode !== null)
  msgs.push({ t: 'patch', patch: { events: [{ kind: 'pass', answer: 'Late answer', tier: 'rare' }] } });

await import(join(repo, 'watch.mjs'));
const first = last();
if (!first) { realWrite('harness: ERROR — WebSocket never constructed\n'); process.exit(1); }
// string entries are raw frames (non-JSON or non-object JSON); objects
// are JSON-stringified
for (const m of msgs) first.onmessage({ data: typeof m === 'string' ? m : JSON.stringify(m) });

writeFileSync(outFile, drawn.join(''));
// normalize the random player key so this line is byte-stable across runs
const url = first.url.replace(/key=[0-9a-f]{32}/, 'key=<key32>');
realWrite('harness: ws url = ' + url + '\n');

if (closeCode !== null) {
  // fatal close: watch.mjs must flush the party file and exit(closeCode)
  // on its own — no reconnect, no SIGTERM dance. Restore the real stdout
  // first: the drawn output is already saved, and the exit message must
  // reach the harness's own stdout (the patched write would swallow it
  // into the never-flushed drawn buffer).
  process.stdout.write = realWrite;
  socks.forEach(s => clearInterval(s._keep));
  first.onclose({ code: closeCode });
  realWrite('harness: ERROR — fatal close did not exit\n');
  process.exit(1);
}

// disconnect: the dead socket holds no handle, so from this moment the
// watcher must stay alive via its own (ref'd) retry timer — an unref'd one
// lets the process exit silently before it reconnects (the bug this pins).
// The watchdog is unref'd so it cannot mask that either.
socks.forEach(s => clearInterval(s._keep));
first.onclose({ code: 1006 });
setTimeout(() => {
  realWrite(`harness: ws builds after close = ${builds}\n`);
  if (builds < 2) realWrite('harness: ERROR — no reconnect after close\n');
  process.kill(process.pid, 'SIGTERM');   // watch.mjs: flush() + exit(0)
}, 2500).unref?.();
