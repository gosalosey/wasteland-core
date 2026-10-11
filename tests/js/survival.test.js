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
