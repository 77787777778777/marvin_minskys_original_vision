// Node harness for the Feather/WASM build.
// Sources the game layers + cache.tcl + shims.tcl + web/game.tcl, then plays
// the full walkthrough and checks save/restore works via host commands.
import { createFeather } from './feather.js';
import fs from 'fs';

const feather = await createFeather(fs.readFileSync('./feather.wasm'));
const interp = feather.create();

let saved = null;
feather.register(interp, 'host_save', (args) => { saved = args.join(' '); });
feather.register(interp, 'host_load', () => {
  if (saved === null) throw new Error('there is no saved game to restore');
  return saved;
});

const src = (p) => fs.readFileSync(p, 'utf8');
for (const file of ['../frames.tcl', '../engine.tcl', '../cache.tcl', '../shims.tcl', '../world.tcl', 'game/game.tcl']) {
  try {
    feather.eval(interp, src(file));
  } catch (e) {
    console.error(`SOURCE FAILED: ${file}: ${e.message}`);
    process.exit(1);
  }
}
console.log('SOURCE OK');

console.log(feather.eval(interp, '::game::boot_web').split('\n')[0], '- boot ok');

// save/restore round trip
feather.eval(interp, '::game::game_cmd {take key}');
console.log('save:', feather.eval(interp, '::game::game_cmd {save}').trim());
console.log('db captured:', saved ? saved.length + ' chars' : 'NO');
feather.eval(interp, '::game::game_cmd {drop key}');
const inv = feather.eval(interp, '::game::game_cmd {inventory}').trim();
console.log('after drop:', inv.split('\n')[0]);
console.log('restore:', feather.eval(interp, '::game::game_cmd {restore}').trim().split('\n')[0]);
const inv2 = feather.eval(interp, '::game::game_cmd {inventory}').trim();
console.log('after restore:', inv2.split('\n')[0]);
const roundtrip = saved !== null && /iron key/.test(inv2);

// full walkthrough
const walk = [
  'take key', 'take lamp', 'north', 'down', 'light lamp', 'take bone',
  'unlock chest', 'open chest', 'take tome', 'read tome',
  'up', 'up', 'give bone to troll',
  'north', 'look through telescope', 'turn telescope right',
  'turn telescope right', 'turn telescope right', 'take candle',
  'south', 'down', 'east', 'ask curator about ritual',
  'ring bell', 'light candle', 'say frame',
  'east', 'take amulet', 'west', 'give amulet to curator',
];
let win = false, failedAt = '';
for (const cmd of walk) {
  try {
    const out = feather.eval(interp, `::game::game_cmd {${cmd}}`);
    if (/mastered the Framework/.test(out)) win = true;
  } catch (e) { failedAt = `${cmd}: ${e.message.slice(0,60)}`; break; }
}
if (!win && !failedAt) failedAt = 'walkthrough ended without win';
console.log(win ? 'WALKTHROUGH: WIN' : `WALKTHROUGH FAILED at ${failedAt}`);
process.exit(win && roundtrip ? 0 : 1);
