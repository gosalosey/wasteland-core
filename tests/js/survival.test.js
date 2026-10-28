// Survival HUD logic (node --test tests/js/survival.test.js).

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const hud = require(path.join(__dirname, '..', '..', 'resources', '[wasteland]', 'wasteland_survival', 'html', 'hud.js'));

const stats = (o) => Object.assign({ hunger: 80, thirst: 60, infection: 0, bleeding: 0, temperature: 37, dead: false }, o);

test('compact shows health, food, drink and temperature icons', () => {
    const list = hud.icons({ mode: 'compact', health: 90, stats: stats() });
    assert.deepStrictEqual(list.map((i) => i.key), ['health', 'food', 'drink', 'temp']);
    assert.deepStrictEqual(list.map((i) => i.level), ['ok', 'ok', 'ok', 'ok']);
    assert.strictEqual(list[3].fill, 67); // 37 °C on a 33-39 °C thermometer
});

test('levels: amber at 35 or below, red at 15 or below; temperature by degrees', () => {
    const list = hud.icons({ mode: 'compact', health: 35, stats: stats({ hunger: 15, thirst: 36, temperature: 35.2 }) });
    assert.deepStrictEqual(list.map((i) => i.level), ['low', 'critical', 'ok', 'low']);
    assert.strictEqual(hud.icons({ mode: 'compact', health: 90, stats: stats({ temperature: 40 }) })[3].level, 'critical');
});

test('immersive shows only what matters', () => {
    assert.deepStrictEqual(hud.icons({ mode: 'immersive', health: 90, stats: stats() }), []);
    const low = hud.icons({ mode: 'immersive', health: 30, stats: stats({ thirst: 20, temperature: 34 }) }).map((i) => i.key);
    assert.deepStrictEqual(low, ['health', 'drink', 'temp']);
});

test('off and dead show nothing; values are clamped and rounded', () => {
    assert.deepStrictEqual(hud.icons({ mode: 'off', health: 10, stats: stats() }), []);
    assert.deepStrictEqual(hud.icons({ mode: 'compact', health: 10, stats: stats({ dead: true }) }), []);
    const list = hud.icons({ mode: 'compact', health: 130.4, stats: stats({ hunger: 33.6, temperature: 20 }) });
    assert.strictEqual(list[0].fill, 100);
    assert.strictEqual(list[1].fill, 34);
    assert.strictEqual(list[3].fill, 0);
});

test('badges: bleeding level and infection', () => {
    const b = hud.badges({ mode: 'compact', stats: stats({ bleeding: 2, infection: 41.6, treatment: true }) });
    assert.deepStrictEqual(b.map((x) => x.text), ['Bleeding heavily', 'Infection (treated) 42%']);
    assert.deepStrictEqual(hud.badges({ mode: 'compact', stats: stats() }), []);
    assert.deepStrictEqual(hud.badges({ mode: 'off', stats: stats({ bleeding: 3 }) }), []);
});

test('layout: default corner, clamped fractions, known sizes only', () => {
    assert.deepStrictEqual(hud.normalizeLayout(undefined), { x: null, y: null, vertical: false, size: 'm', style: 'body' });
    assert.deepStrictEqual(hud.normalizeLayout({ x: 0.5, y: 'top', size: 'xl' }), { x: null, y: null, vertical: false, size: 'm', style: 'body' });
    assert.deepStrictEqual(hud.normalizeLayout({ x: -1, y: 7, vertical: true, size: 'l' }), { x: 0, y: 1, vertical: true, size: 'l', style: 'body' });
    assert.strictEqual(hud.toPixels({}, { w: 200, h: 50 }, { w: 1920, h: 1080 }), null);
});

test('layout: dragging maps to fractions of the free space and back', () => {
    const box = { w: 220, h: 60 };
    const view = { w: 1920, h: 1080 };
    const f = hud.toFractions(850, 510, box, view);
    assert.deepStrictEqual(f, { x: 0.5, y: 0.5 });
    assert.deepStrictEqual(hud.toPixels(f, box, view), { left: 850, top: 510 });
    // dragged past the edges: stays on screen
    assert.deepStrictEqual(hud.toFractions(-300, 5000, box, view), { x: 0, y: 1 });
    // same layout on a smaller screen keeps the HUD inside it
    assert.deepStrictEqual(hud.toPixels({ x: 1, y: 1 }, box, { w: 1280, h: 720 }), { left: 1060, top: 660 });
});

test('info line: id, character name and cash; hidden when the HUD is off', () => {
    const line = hud.infoLine({ mode: 'immersive', info: { id: 7, name: 'John Doe', cash: 1250.9 }, stats: stats() });
    assert.deepStrictEqual(line, { id: '#7', name: 'John Doe', cash: '$1,250' });
    assert.strictEqual(hud.infoLine({ mode: 'compact', info: { id: 7, name: 'A B' }, stats: stats() }).cash, null);
    assert.strictEqual(hud.infoLine({ mode: 'off', info: { id: 7 }, stats: stats() }), null);
    assert.strictEqual(hud.infoLine({ mode: 'compact', info: { id: 7 }, stats: stats({ dead: true }) }), null);
});

test('stamina bar: only while stamina is used', () => {
    assert.strictEqual(hud.staminaBar({ mode: 'compact', stamina: 100, stats: stats() }).visible, false);
    const used = hud.staminaBar({ mode: 'immersive', stamina: 63.4, stats: stats() });
    assert.deepStrictEqual(used, { visible: true, fill: 63, low: false });
    assert.strictEqual(hud.staminaBar({ mode: 'compact', stamina: 12, stats: stats() }).low, true);
    assert.strictEqual(hud.staminaBar({ mode: 'off', stamina: 10, stats: stats() }).visible, false);
});

test('armor plate icon only while a plate is worn', () => {
    const base = { mode: 'compact', health: 80, stats: { hunger: 50, thirst: 50 } };
    assert.ok(!hud.icons(base).some((i) => i.key === 'armor'));
    const a = hud.icons(Object.assign({ armor: 30 }, base)).find((i) => i.key === 'armor');
    assert.deepStrictEqual([a.fill, a.level], [30, 'low']);
});

test('pee and poop icons fill up and warn when nearly full', () => {
    const list = hud.icons({ mode: 'compact', health: 90, stats: stats({ bladder: 90, bowel: 30 }) });
    const pee = list.find((i) => i.key === 'pee'), poop = list.find((i) => i.key === 'poop');
    assert.strictEqual(pee.fill, 90); assert.strictEqual(pee.level, 'critical');
    assert.strictEqual(poop.level, 'ok');
    assert.deepStrictEqual(hud.icons({ mode: 'immersive', health: 90, stats: stats({ bladder: 70, bowel: 10 }) }).map((i) => i.key), ['pee']);
});

test('body style: the arc of rings, armour with plates, voice and the body state', () => {
    const v = hud.bodyView({ mode: 'compact', health: 80, stamina: 100, armor: 60, plates: 40,
        voice: { talking: true, level: 2, levels: 3, on: true },
        stats: { hunger: 60, thirst: 5, temperature: 37, bladder: 20, bowel: 10, bleeding: 2, infection: 10 } });
    assert.deepStrictEqual(v.big.map((r) => r.key), ['health', 'stamina', 'food', 'drink']);
    assert.strictEqual(v.big[3].level, 'critical');
    assert.strictEqual(v.big[0].text, '80%');
    assert.deepStrictEqual(v.armor, { worn: true, fill: 60, plates: 40, level: 'ok' });
    assert.strictEqual(v.voice.talking, true); assert.strictEqual(v.voice.fill, 67);
    assert.deepStrictEqual(v.small.map((i) => i.key), ['temp', 'pee', 'poop', 'voice']);
    assert.strictEqual(v.small[3].talking, true);
    assert.deepStrictEqual(v.body, { bleeding: 2, infected: true, hurt: false });
});

test('body style: no vest, no voice resource, "when it matters" and off', () => {
    const v = hud.bodyView({ mode: 'compact', health: 100, voice: { on: false }, stats: {} });
    assert.strictEqual(v.armor.worn, false); assert.strictEqual(v.voice.on, false); assert.strictEqual(v.voice.fill, 0);
    const im = hud.bodyView({ mode: 'immersive', health: 90, stamina: 30, stats: { hunger: 80, thirst: 90 } });
    assert.deepStrictEqual(im.big.map((r) => r.key), ['stamina']);
    assert.strictEqual(hud.bodyView({ mode: 'off', stats: {} }), null);
    assert.strictEqual(hud.normalizeLayout({}).style, 'body');
    assert.strictEqual(hud.normalizeLayout({ style: 'classic' }).style, 'classic');
});

test('character picture: only the pixels that differ between the two shots are kept', () => {
    const w = 10, h = 10;
    const a = new Uint8ClampedArray(w * h * 4).fill(100), b = new Uint8ClampedArray(w * h * 4).fill(100);
    for (let y = 2; y < 8; y++) for (let x = 3; x < 6; x++) { const i = (y * w + x) * 4; a[i] = 250; a[i + 2] = 20; }
    a[(9 * w + 9) * 4] = 160;   // one stray pixel: not part of the box
    const r = hud.cutout(a, b, w, h);
    assert.deepStrictEqual(r.box, { x: 3, y: 2, w: 3, h: 6 });
    assert.strictEqual(r.data[3], 0);                          // background: clear
    assert.strictEqual(r.data[(2 * w + 3) * 4 + 3], 255);     // character: solid
    assert.strictEqual(r.data[(2 * w + 3) * 4], 250);         // with its own colour
    assert.strictEqual(hud.cutout(b, b, w, h).box, null);    // nothing differs: no picture
});

test('noise ring: the zombies\' hearing range as a word, a fill and feet', () => {
    const v = hud.bodyView({ mode: 'compact', health: 90, noise: { radius: 30, source: 'running', count: 2 }, voice: { talking: true }, stats: {} });
    assert.strictEqual(v.noise.key, 'loud'); assert.strictEqual(v.noise.word, 'LOUD');
    assert.strictEqual(v.noise.feet, 100); assert.strictEqual(v.noise.count, 2);
    assert.ok(v.noise.fill > 40 && v.noise.fill < 60);
    assert.strictEqual(hud.noiseLevel(4).key, 'quiet'); assert.strictEqual(hud.noiseLevel(80).key, 'deafening');
    const none = hud.bodyView({ mode: 'compact', health: 90, stats: {} });
    assert.strictEqual(none.noise.known, false);
});

test('voice speaker in the small row: only with voice chat; "when it matters" only while talking', () => {
    const quiet = hud.bodyView({ mode: 'immersive', health: 90, voice: { on: true, talking: false, level: 1, levels: 3 }, stats: {} });
    assert.strictEqual(quiet.small.some((i) => i.key === 'voice'), false);
    const talking = hud.bodyView({ mode: 'immersive', health: 90, voice: { on: true, talking: true, level: 3, levels: 3 }, stats: {} });
    assert.strictEqual(talking.small.find((i) => i.key === 'voice').fill, 100);
    const off = hud.bodyView({ mode: 'compact', health: 90, voice: { on: false }, stats: {} });
    assert.strictEqual(off.small.some((i) => i.key === 'voice'), false);
});

test('character picture: specks elsewhere in the shot (clouds) do not widen the crop', () => {
    const w = 200, h = 100;
    const a = new Uint8ClampedArray(w * h * 4).fill(120), b = new Uint8ClampedArray(w * h * 4).fill(120);
    const set = (x, y) => { a[(y * w + x) * 4] = 255; };
    for (let y = 20; y < 96; y++) for (let x = 90; x < 111; x++) set(x, y);   // the character
    for (let x = 60; x < 66; x++) for (let y = 30; y < 50; y++) set(x, y);    // ... an arm held out (small gap allowed? no: far)
    let seed = 7; const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
    for (let i = 0; i < 400; i++) set(Math.floor(rnd() * w), Math.floor(rnd() * 12));   // clouds across the top rows
    const r = hud.cutout(a, b, w, h);
    assert.ok(r.box.x >= 85 && r.box.x + r.box.w <= 115, 'columns: ' + JSON.stringify(r.box));
    assert.ok(r.box.y >= 15 && r.box.y + r.box.h >= 94, 'rows: ' + JSON.stringify(r.box));
    assert.strictEqual(r.data[(5 * w + 10) * 4 + 3], 0);   // a cloud speck outside the box is cleared
});
