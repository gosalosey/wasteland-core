// Survival HUD logic (node --test tests/js/survival.test.js).

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const hud = require(path.join(__dirname, '..', '..', 'resources', '[wasteland]', 'wasteland_survival', 'html', 'hud.js'));

const stats = (o) => Object.assign({ hunger: 80, thirst: 60, infection: 0, bleeding: 0, temperature: 37, dead: false }, o);

test('compact shows health, food and water (stamina only while used)', () => {
    const keys = hud.bars({ mode: 'compact', health: 90, stamina: 100, stats: stats() }).map((b) => b.key);
    assert.deepStrictEqual(keys, ['health', 'hunger', 'thirst']);
    const running = hud.bars({ mode: 'compact', health: 90, stamina: 40, stats: stats() }).map((b) => b.key);
    assert.ok(running.includes('stamina'));
});

test('immersive shows only what matters', () => {
    assert.deepStrictEqual(hud.bars({ mode: 'immersive', health: 90, stamina: 100, stats: stats() }), []);
    const low = hud.bars({ mode: 'immersive', health: 30, stamina: 100, stats: stats({ thirst: 20, infection: 5 }) }).map((b) => b.key);
    assert.deepStrictEqual(low, ['health', 'thirst', 'infection']);
});

test('off and dead show nothing; values are clamped and rounded', () => {
    assert.deepStrictEqual(hud.bars({ mode: 'off', health: 10, stats: stats() }), []);
    assert.deepStrictEqual(hud.bars({ mode: 'compact', health: 10, stats: stats({ dead: true }) }), []);
    const b = hud.bars({ mode: 'compact', health: 130.4, stamina: 100, stats: stats({ hunger: 33.6 }) });
    assert.strictEqual(b[0].value, 100);
    assert.strictEqual(b[1].value, 34);
});

test('chips: bleeding level and temperature (only abnormal in immersive)', () => {
    const c = hud.chips({ mode: 'compact', stats: stats({ bleeding: 2, temperature: 34.96 }) });
    assert.deepStrictEqual(c.map((x) => x.text), ['Bleeding heavily', '35.0 °C']);
    assert.strictEqual(c[1].tone, 'cold');
    assert.deepStrictEqual(hud.chips({ mode: 'immersive', stats: stats() }), []);
    assert.strictEqual(hud.chips({ mode: 'compact', stats: stats({ temperature: 39 }) })[0].tone, 'hot');
});
