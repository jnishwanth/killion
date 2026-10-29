#!/usr/bin/env node
// killion watch — watch a Puffer Party room: live question + best
// game-verified answers, minus what players have already said.
// Zero footprint: does NOT join the room (the room stream is not gated on
// membership), so no player appears in the game UI. Read-only.
// Usage: node watch.mjs <ROOMCODE>
import { spawnSync } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { readFileSync, writeFileSync, renameSync } from 'fs';

const HERE = dirname(fileURLToPath(import.meta.url));
const DATA = join(HERE, 'full_dives.json');
const PARTY_FILE = join(HERE, 'party_answers.json');
const code = (process.argv[2] ?? '').trim().toUpperCase();
if (!/^[A-Z]{4}$/.test(code)) {
  console.error('usage: killion watch <ROOMCODE>   (4-letter room code)');
  process.exit(2);
}

const j = (url) => fetch(url).then(r => r.json().catch(() => ({})));
let token = (await j('https://krillion.io/api/party/token')).token;
const randKey = () =>
  [...crypto.getRandomValues(new Uint8Array(16))].map(b => b.toString(16).padStart(2, '0')).join('');

// look up game-verified answers for an exact question (daily data + party record)
function lookup(question) {
  const r = spawnSync('jq', ['-c', '--arg', 'q', question,
    '[.[] as $d | $d.prompts[] | select(.q == $q) | {dive: $d.n, date: $d.date, answers: .answers}] | .[0] // empty',
    DATA], { encoding: 'utf8' });
  let daily = null;
  try { daily = JSON.parse(r.stdout || 'null'); } catch {}
  let party = [];
  try { party = JSON.parse(readFileSync(PARTY_FILE, 'utf8'))[question] ?? []; } catch {}
  if (!daily && !party.length) return null;
  const inDaily = new Set((daily?.answers ?? []).map(a => a.a.toLowerCase()));
  const extras = party.filter(a => !inDaily.has(a.a.toLowerCase()));
  return {
    source: daily ? (extras.length ? 'daily+party' : 'daily') : 'party',
    dive: daily?.dive ?? null,
    date: daily?.date ?? null,
    answers: [...(daily?.answers ?? []), ...extras],
  };
}

const TIER_NAME = { krillion: 'One in a Krillion', deepcut: 'Deep Cut', rare: 'Rare',
                    schooler: 'Schooler', tooclever: 'Too Clever', plankton: 'Plankton' };
const TIER_ICON = { krillion: '◆', deepcut: '◆', rare: '●', schooler: '●',
                    tooclever: '○', plankton: '○' };
const TIER_ORDER = ['krillion', 'deepcut', 'rare', 'schooler', 'tooclever', 'plankton'];
const SHOW_CAP = { krillion: 5, deepcut: 12, rare: 6, schooler: 4, tooclever: 3, plankton: 3 };

let leaving = false;
process.on('SIGINT', () => { flush(); process.exit(0); });
process.on('SIGTERM', () => { flush(); process.exit(0); });

// room state we care about
let roomCode = code, phase = null, players = [], cat = null;
let lookupResult = null, lookupFor = null;
let said = new Map();            // answer.toLowerCase() -> {a, tier}
let dirty = true, lastSeenSig = '';

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
        if (left.length > SHOW_CAP[t]) L.push(`    … +${left.length - SHOW_CAP[t]} more — ./killion "${cat.text}"`);
      }
      const unscored = lookupResult.answers.filter(a => !TIER_ORDER.includes(a.tier));
      if (unscored.length) {
        L.push(`  · unscored (${unscored.length})`);
        for (const a of unscored.slice(0, SHOW_CAP.plankton)) L.push(`    • ${a.a}`);
      }
    } else if (lookupResult === null && lookupFor === cat.text) {
      L.push('  no game-verified answers yet (party-only category)');
    } else {
      L.push('  looking up verified answers…');
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
  const la = p.lastAnswer;
  const text = typeof la === 'string' ? la : (la?.text ?? null);
  const tier = (la && typeof la === 'object' && la.tier) || null;
  if (text && !said.has(text.toLowerCase())) {
    said.set(text.toLowerCase(), { a: text, tier });
    record(text, tier);
  }
}

let ws = null;
function connect() {
  if (leaving) return;
  ws = new WebSocket(
    `wss://party.krillion.io/rooms/${code}/ws?key=${randKey()}&token=${encodeURIComponent(token)}`);
  ws.onmessage = (e) => {
    const m = JSON.parse(String(e.data));
    if (m.t === 'snap') {
      const r = m.room;
      phase = r.phase; players = r.players; cat = r.category;
      // known answers from the current round's event log
      said = new Map();
      for (const ev of r.events ?? [])
        if (ev.kind === 'pass' && ev.answer) {
          if (!said.has(ev.answer.toLowerCase()))
            said.set(ev.answer.toLowerCase(), { a: ev.answer, tier: ev.tier ?? null });
          record(ev.answer, ev.tier ?? null);
        }
      for (const p of r.players) addSaidFromPlayer(p);
      dirty = true;
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
          process.stdout.write('\x07');
        }
      }
      for (const ev of m.patch?.events ?? [])
        if (ev.kind === 'pass' && ev.answer) {
          if (!said.has(ev.answer.toLowerCase()))
            said.set(ev.answer.toLowerCase(), { a: ev.answer, tier: ev.tier ?? null });
          record(ev.answer, ev.tier ?? null);
        }
      if (Array.isArray(s.players))
        for (const p of s.players) addSaidFromPlayer(p);
      dirty = true;
    }
    if (dirty) { dirty = false; draw(); }
  };
  ws.onclose = async (e) => {
    if (leaving) return;
    if (e.code === 4404) { console.log('\nroom is gone.'); process.exit(1); }
    if (e.code === 4403) { console.log('\nrefused.'); process.exit(1); }
    if (e.code === 4401) token = (await j('https://krillion.io/api/party/token')).token;
    console.log('connection lost, retrying…');
    setTimeout(connect, 1500).unref?.();
  };
  ws.onerror = () => {};
}
connect();
