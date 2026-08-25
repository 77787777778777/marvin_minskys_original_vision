import { createFeather } from '/home/wrath/framework-game/web/feather.js';
import fs from 'fs';
const f = await createFeather(fs.readFileSync('/home/wrath/framework-game/web/feather.wasm'));
const interpId = f.create();
let saved = null;
f.register(interpId, 'host_save', (a) => { saved = a.join(' '); });
f.register(interpId, 'host_load', () => { if(saved===null) throw new Error('no'); return saved; });
const src = (p) => fs.readFileSync(p,'utf8');
for (const file of ['../frames.tcl','../engine.tcl','../cache.tcl','../shims.tcl','../world.tcl','game/game.tcl']) f.eval(interpId, src(file));
f.eval(interpId,'::game::boot_web');

// Full walkthrough with progress output so we can see it working even if
// the total runtime exceeds a shell timeout. Run in background and poll.
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
let win = false, failedAt = '', roundtrip = false;

f.eval(interpId, '::game::game_cmd {take key}');
console.log('save:', f.eval(interpId, '::game::game_cmd {save}').trim());
console.log('db captured:', saved ? saved.length + ' chars' : 'NO');
f.eval(interpId, '::game::game_cmd {drop key}');
f.eval(interpId, '::game::game_cmd {restore}');
const inv2 = f.eval(interpId, '::game::game_cmd {inventory}').trim();
roundtrip = /iron key/.test(inv2);
console.log('restore roundtrip:', roundtrip ? 'OK' : 'FAIL');

let i = 0;
for (const cmd of walk) {
  i++;
  const t0 = Date.now();
  try {
    const out = f.eval(interpId, `::game::game_cmd {${cmd}}`);
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
