#!/usr/bin/env node
// killion watch — watch a Puffer Party room: live question + best
// game-verified answers, minus what players have already said.
// Zero footprint: does NOT join the room (the room stream is not gated on
// membership), so no player appears in the game UI. Read-only.
// Usage: node watch.mjs <ROOMCODE>
import { spawnSync } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { existsSync, readFileSync, writeFileSync, renameSync } from 'fs';

const HERE = dirname(fileURLToPath(import.meta.url));
const DATA = join(HERE, 'full_dives.json');
const PARTY_FILE = join(HERE, 'party_answers.json');
const TIERS_FILE = join(HERE, 'tiers.json');
const RENDER_FILE = join(HERE, 'render.jq');
const code = (process.argv[2] ?? '').trim().toUpperCase();
if (!/^[A-Z]{4}$/.test(code)) {
  console.error('usage: killion watch <ROOMCODE>   (4-letter room code)');
  process.exit(2);
}

// j never rejects: a network hiccup yields {} so a token refresh degrades
// to a retry instead of crashing the watcher
const j = (url) => fetch(url).then(r => r.json()).catch(() => ({}));
let token = (await j('https://krillion.io/api/party/token')).token;
if (!token) {
  console.error('error: no guest token from krillion.io (network down?)');
  process.exit(1);
}
const randKey = () =>
  [...crypto.getRandomValues(new Uint8Array(16))].map(b => b.toString(16).padStart(2, '0')).join('');

// look up game-verified answers for an exact question: the same render.jq
// the CLI uses, in exact mode — a fuzzy match on a server-supplied question
// could silently show another question's answers
function lookup(question) {
  const r = spawnSync('jq', ['-r', '-f', RENDER_FILE, '--arg', 'q', question,
    '--arg', 'm', 'exact',
    '--slurpfile', 'p', existsSync(PARTY_FILE) ? PARTY_FILE : '/dev/null',
    '--slurpfile', 'T', TIERS_FILE, DATA], { encoding: 'utf8' });
  try {
    const o = JSON.parse((r.stdout || '').trim());
    return o && o.answers ? o : null;
  } catch { return null; }
}

// tier table, shared with render.jq + download_full.py (tiers.json)
const TIERS = JSON.parse(readFileSync(TIERS_FILE, 'utf8'));
const TIER_ORDER = TIERS.order;
const pick = (f) => Object.fromEntries(Object.entries(TIERS.tiers).map(([k, v]) => [k, v[f]]));
const TIER_NAME = pick('name');
const TIER_ICON = pick('icon');
const SHOW_CAP = pick('cap');

process.on('SIGINT', () => { flush(); process.exit(0); });
process.on('SIGTERM', () => { flush(); process.exit(0); });

// room state we care about
let roomCode = code, phase = null, players = [], cat = null;
let lookupResult = null, lookupFor = null;
let said = new Map();            // answer.toLowerCase() -> {a, tier}
let lastSeenSig = '';

// Round provenance for the state channel: the server can deliver a players
// array whose lastAnswer still holds the previous round's value (an early
// new-round patch, or a reconnect snap), so a lastAnswer present at round
// start is NOT an answer to the current question. We baseline each player's
// lastAnswer text at round start (snap + newRound patch) and the state
// channel only records/shows values that CHANGE after the round started.
// A player who re-answers their own baseline text is captured by their pass
// event, not the state channel. Accepted tradeoff: joining mid-round, a
// pre-join answer absent from the snap's event log is dropped from the
// record (the said display still shows it when the log has it). Correctness
// over completeness — a wrong suggestion mid-round is worse than a missing
// entry. (Players without an id can't be baselined; for them the state
// channel keeps its record-as-seen behavior.)
let baseline = new Map();        // player id -> lastAnswer text (lowercase) at round start
const laText = (p) => {
  const la = p.lastAnswer;
  return typeof la === 'string' ? la : (la?.text ?? null);
};
function setBaseline(ps) {
  baseline = new Map();
  for (const p of ps) {
    const t = laText(p);
    if (p.id != null && t) baseline.set(p.id, t.toLowerCase());
  }
}

function sig() {
  return [phase, cat?.index, cat?.text, players.filter(p => p.alive).length,
    [...said.values()].map(v => v.a).sort().join('|')].join('§');
}

function lookupIfNeeded() {
  if (!cat?.text || cat.text === lookupFor) return;
  lookupFor = cat.text;
  lookupResult = lookup(cat.text);
}

function draw() {
  const s = sig();
  if (s === lastSeenSig) return;
  lastSeenSig = s;

  lookupIfNeeded();
  const inGame = players.filter(p => p.alive).length;
  const L = [];
  L.push(`krillion watch · room ${roomCode} · ${phase ?? '?'} · ${inGame}/${players.length} in game · ctrl-c to quit`);
  L.push('');
  L.push('QUESTION');
  L.push(`  ${cat?.text ?? '(waiting for a round to start…)'}`);
  if (cat?.text) {
    if (lookupResult) {
      const n = lookupResult.answers.length;
      if (lookupResult.source === 'party')
        L.push(`  party-verified · ${n} answer${n === 1 ? '' : 's'} recorded from your games`);
      else
        L.push(`  verified in daily dive #${lookupResult.dive} (${lookupResult.date}) · ${n} accepted answers` +
          (lookupResult.source === 'daily+party' ? '  (+ party-verified)' : ''));
      L.push('');
      for (const t of TIER_ORDER) {
        const all = lookupResult.answers.filter(a => a.tier === t);
        if (!all.length) continue;
        const saidIn = all.filter(a => said.has(a.a.toLowerCase()));
        const left = all.filter(a => !said.has(a.a.toLowerCase()));
        const head = `  ${TIER_ICON[t]} ${TIER_NAME[t]} (${all.length})` +
          (saidIn.length ? `  — ${saidIn.length} already said` : '');
        L.push(head);
        if (!left.length) { L.push('    (every answer in this tier has been said)'); continue; }
        for (const a of left.slice(0, SHOW_CAP[t]))
          L.push(`    • ${a.a}${a.seen > 1 ? `  (×${a.seen})` : ''}`);
        if (left.length > SHOW_CAP[t]) L.push(`    … +${left.length - SHOW_CAP[t]} more — ./killion "${cat.text}" --all`);
      }
      const unscored = lookupResult.answers.filter(a => !TIER_ORDER.includes(a.tier));
      if (unscored.length) {
        L.push(`  · unscored (${unscored.length})`);
        for (const a of unscored.slice(0, SHOW_CAP.plankton)) L.push(`    • ${a.a}`);
      }
    } else {
      // lookupIfNeeded() ran synchronously above (spawnSync): null
      // means no verified answers exist for this question
      L.push('  no game-verified answers yet (party-only category)');
    }
    if (said.size) {
      L.push('');
      L.push(`  said this round: ${[...said.values()].map(v => `"${v.a}"${v.tier ? ` (${TIER_NAME[v.tier] ?? v.tier})` : ''}`).join('  ')}`);
    }
  }
  process.stdout.write('\x1b[2J\x1b[H' + L.join('\n') + '\n');
}

// every accepted answer seen in a room is game-verified (the server
// assigns its tier) — record it so party categories build up data.
const recorded = new Map();   // questionLower -> Map(answerLower -> entry)
const qText = new Map();      // questionLower -> original question text
const today = () => new Date().toISOString().slice(0, 10);

function record(text, tier) {
  const q = cat?.text;
  if (!q || !text) return;
  const qL = q.toLowerCase();
  qText.set(qL, q);
  const qm = recorded.get(qL) ?? new Map();
  recorded.set(qL, qm);
  const k = text.toLowerCase();
  const date = today();
  const e = qm.get(k) ?? { a: text, tier: tier ?? null, seen: 0, firstSeen: date, lastSeen: date };
  e.seen += 1;
  e.lastSeen = date;
  if (!e.tier && tier) e.tier = tier;
  qm.set(k, e);
}

function flush() {
  if (!recorded.size) return;
  let existing = {};
  try { existing = JSON.parse(readFileSync(PARTY_FILE, 'utf8')); } catch {}
  const date = today();
  for (const [qL, qm] of recorded) {
    const q = qText.get(qL);
    const arr = new Map((existing[q] ?? []).map(e => [e.a.toLowerCase(), e]));
    for (const [k, e] of qm) {
      const old = arr.get(k);
      arr.set(k, old
        ? { ...old, seen: old.seen + e.seen, lastSeen: date, tier: old.tier || e.tier }
        : { ...e, lastSeen: date });
    }
    existing[q] = [...arr.values()];
  }
  const tmp = PARTY_FILE + '.tmp';
  writeFileSync(tmp, JSON.stringify(existing, null, 1));
  renameSync(tmp, PARTY_FILE);
  recorded.clear();
}

function addSaidFromPlayer(p) {
  const text = laText(p);
  if (!text) return;
  const k = text.toLowerCase();
  if (baseline.get(p.id) === k) return;   // round-start value: stale — neither said nor recorded
  const tier = (p.lastAnswer && typeof p.lastAnswer === 'object' && p.lastAnswer.tier) || null;
  if (!said.has(k)) {
    said.set(k, { a: text, tier });
    record(text, tier);
  }
}

// a 'pass' event is an accepted answer the server scored: mark it as said
// and record every sighting (duplicates count) for the party dataset
function applyEvents(events) {
  for (const ev of events ?? [])
    if (ev.kind === 'pass' && ev.answer) {
      if (!said.has(ev.answer.toLowerCase()))
        said.set(ev.answer.toLowerCase(), { a: ev.answer, tier: ev.tier ?? null });
      record(ev.answer, ev.tier ?? null);
    }
}

function connect() {
  const ws = new WebSocket(
    `wss://party.krillion.io/rooms/${code}/ws?key=${randKey()}&token=${encodeURIComponent(token)}`);
  ws.onmessage = (e) => {
    // a frame that is not a JSON object (proxy garbage, a bare null)
    // must not kill the watcher: drop it and keep running. Dropped
    // silently, like unknown frame types below — a garbage frame stays
    // invisible in the output (the golden pins exactly that).
    let m;
    try { m = JSON.parse(String(e.data)); } catch { return; }
    if (!m || typeof m !== 'object' || Array.isArray(m)) return;
    if (m.t === 'snap') {
      const r = m.room;
      phase = r.phase; players = r.players; cat = r.category;
      setBaseline(players);     // lastAnswers now are provenance, not current-round answers
      // known answers from the current round's event log
      said = new Map();
      applyEvents(r.events);
      for (const p of r.players) addSaidFromPlayer(p);
    } else if (m.t === 'patch') {
      const s = m.patch?.set ?? {};
      if (s.phase) phase = s.phase;
      if (Array.isArray(s.players)) players = s.players;
      if (s.category) {
        const newRound = !cat || s.category.index !== cat.index;
        cat = s.category;
        if (newRound) {
          flush();                    // persist previous rounds' answers
          said = new Map();           // fresh round: nothing said yet
          setBaseline(players);       // carried (or later stale) lastAnswers are pre-round values
          process.stdout.write('\x07');
        }
      }
      applyEvents(m.patch?.events);
      if (Array.isArray(s.players))
        for (const p of s.players) addSaidFromPlayer(p);
    } else return;
    draw();
  };
  ws.onclose = async (e) => {
    // natural death (4404 room-gone, 4403 refused — same path): flush
    // first, so answers recorded since the last round boundary — still in
    // memory — are not lost with the process
    if (e.code === 4404) { flush(); console.log('\nroom is gone.'); process.exit(1); }
    if (e.code === 4403) { flush(); console.log('\nrefused.'); process.exit(1); }
    if (e.code === 4401) {
      const t = (await j('https://krillion.io/api/party/token')).token;
      if (t) token = t;                    // refresh failed: retry with the old one
    }
    console.log('connection lost, retrying…');
    // ref'd on purpose: once the socket is gone this timer is the only handle
    // left, and an unref'd one lets the process exit silently before the retry
    setTimeout(connect, 1500);
  };
  ws.onerror = () => {};
}
connect();
