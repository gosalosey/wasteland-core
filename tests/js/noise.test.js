// Noise meter logic (node --test tests/js/noise.test.js).

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const nm = require(path.join(__dirname, '..', '..', 'resources', '[wasteland]', 'wasteland_zombies', 'html', 'noise.js'));

test('levels follow the zombies\' hearing ranges (crouch 6, walk 18, sprint 45 m)', () => {
    assert.strictEqual(nm.levelOf(6).key, 'quiet');
    assert.strictEqual(nm.levelOf(18).key, 'noticeable');
    assert.strictEqual(nm.levelOf(45).key, 'loud');
    assert.strictEqual(nm.levelOf(150).key, 'deafening');
});

test('bars grow with the reach and stay within the meter', () => {
    assert.strictEqual(nm.litBars(0), 1);
    assert.ok(nm.litBars(6) < nm.litBars(18));
    assert.ok(nm.litBars(18) < nm.litBars(45));
    assert.strictEqual(nm.litBars(500), nm.BARS);
});

test('the reach in feet, earshot text and flags', () => {
    const v = nm.view({ radius: 18, source: 'Walking', count: 3, firing: true, safe: false });
    assert.strictEqual(v.reach, 'heard within ~60 ft');
    assert.strictEqual(v.earshot, '3 in earshot');
    assert.strictEqual(v.danger, true);
    assert.strictEqual(v.firing, true);
    assert.strictEqual(nm.view({ radius: 6, count: 0 }).earshot, 'none in earshot');
    assert.strictEqual(nm.view({ radius: 6, count: 1 }).earshot, '1 in earshot');
});

test('layout is kept on screen', () => {
    assert.deepStrictEqual(nm.normalizeLayout({ x: 2, y: -1, scale: 9 }), { x: 1, y: 0, scale: 1.8 });
    assert.deepStrictEqual(nm.normalizeLayout({ x: 0.5 }), { x: null, y: null, scale: 1 });
});
