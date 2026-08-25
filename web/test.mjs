// Node harness for the Feather/WASM build.
// Sources the game layers + cache.tcl + shims.tcl + game/game.tcl, then plays
// the full walkthrough (deeds + insights) and checks save/restore via host
// commands. Paths are resolved relative to THIS file so the harness runs
// both from a checkout and from the nix check sandbox.
import { createFeather } from './feather.js';
import fs from 'fs';
import path from 'path';
import url from 'url';

const here = path.dirname(url.fileURLToPath(import.meta.url));
// Sources resolve differently in the checkout (the core .tcl files live one
// level above test.mjs, at the repo root) versus the deployed/check layout
// (everything flat in one dir). Try both; ordering prefers `here` so the
// flat layout is checked first.
const src = (p) => {
  for (const base of [here, path.resolve(here, '..')]) {
    const cand = path.resolve(base, p);
    if (fs.existsSync(cand)) return fs.readFileSync(cand, 'utf8');
  }
  throw new Error(`cannot locate ${p}`);
};

const f = await createFeather(fs.readFileSync(path.join(here, 'feather.wasm')));
const interpId = f.create();
let saved = null;
f.register(interpId, 'host_save', (args) => { saved = args.join(' '); });
f.register(interpId, 'host_load', () => {
  if (saved === null) throw new Error('there is no saved game to restore');
  return saved;
});

for (const file of ['frames.tcl', 'engine.tcl', 'cache.tcl', 'shims.tcl', 'world.tcl', 'game/game.tcl']) {
  try {
    f.eval(interpId, src(file));
  } catch (e) {
    console.error(`SOURCE FAILED: ${file}: ${e.message}`);
    process.exit(1);
  }
}
console.log('SOURCE OK');

console.log(f.eval(interpId, '::game::boot_web').split('\n')[0], '- boot ok');

// Regression probes, fired from the Study BEFORE any movement, so they pin
// the out-of-view behaviours: the curator is omnipresent but not present.
function probe(cmd, wantRe, label, wantNot = null) {
  const out = f.eval(interpId, '::game::game_cmd ' + jsToTcl(cmd));
  if (wantNot && wantNot.test(out)) { console.log(`${label}: UNEXPECTED ${cmd}`); process.exit(1); }
  if (wantRe.test(out)) { console.log(`PROBE OK: ${label}`); return 1; }
  console.log(`PROBE FAIL: ${label} (${cmd})`); console.log(out); process.exit(1);
  return 0;
}
// ask-about must read the TOPIC, not echo the object's own name ("keeper of
// the frames" is the curator's *self* topic, so it must stay absent here).
probe('ask curator about frames', /is a remembered stereotype/, 'ask frames (topic vs object)',
      /keeper of the frames/);
// the hint verb exists and surfaces someone's topic
probe('hint', /A nudge, then:/, 'hint verb', null);
// a missed topic guides the player toward the catalogue instead of shrugging
probe('ask curator about flurb', /knows something about/, 'unknown topic nudge', null);

// save/restore round trip
f.eval(interpId, '::game::game_cmd {take key}');
console.log('save:', f.eval(interpId, '::game::game_cmd {save}').trim());
console.log('db captured:', saved ? saved.length + ' chars' : 'NO');
f.eval(interpId, '::game::game_cmd {drop key}');
const inv = f.eval(interpId, '::game::game_cmd {inventory}').trim();
console.log('after drop:', inv.split('\n')[0]);
console.log('restore:', f.eval(interpId, '::game::game_cmd {restore}').trim().split('\n')[0]);
const inv2 = f.eval(interpId, '::game::game_cmd {inventory}').trim();
console.log('after restore:', inv2.split('\n')[0]);
const roundtrip = saved !== null && /iron key/.test(inv2);

// Full walkthrough: six deeds AND six insights; win condition is 12/12.
// Commands are passed exactly as the browser passes them: one brace-quoted word.
function jsToTcl(s) {
  return '{' + s.replace(/\\/g, '\\\\').replace(/\{/g, '\\{').replace(/\}/g, '\\}') + '}';
}

const walk = [
  'north', 'east',
  'ask curator about frames', 'ask curator about minsky',
  'ask curator about ritual', 'ask curator about word',
  'ask curator about inscription', 'ask curator about stars',
  'west', 'south',
  'take key', 'take lamp', 'north', 'down', 'light lamp',
  'unlock chest', 'open chest', 'take tome', 'read tome',
  'take bone', 'up', 'up', 'give bone to troll',
  'north', 'look through telescope', 'turn telescope right',
  'turn telescope right', 'turn telescope right', 'take candle',
  'south', 'down', 'east', 'ring bell', 'light candle', 'say frame',
  'east', 'take amulet', 'west', 'give amulet to curator',
];
let win = false, failedAt = '', i = 0;
for (const cmd of walk) {
  i++;
  const t0 = Date.now();
  try {
    const out = f.eval(interpId, '::game::game_cmd ' + jsToTcl(cmd));
    if (/mastered the Framework/.test(out)) win = true;
    process.stdout.write(`[${i}/${walk.length}] ${cmd} (${Date.now()-t0}ms)\n`);
  } catch (e) {
    failedAt = `${cmd}: ${e.message.slice(0,60)}`;
    break;
  }
}
if (!win && !failedAt) failedAt = 'walkthrough ended without win';
console.log(win ? 'WALKTHROUGH: WIN' : `WALKTHROUGH FAILED at ${failedAt}`);
console.log(`ROUNDTRIP: ${roundtrip ? 'OK' : 'FAIL'}`);
process.exit(win && roundtrip ? 0 : 1);
