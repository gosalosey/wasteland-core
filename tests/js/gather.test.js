// Chop / mine circle minigame logic (node --test tests/js/gather.test.js).

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const g = require(path.join(__dirname, '..', '..', 'resources', '[wasteland]', 'wasteland_loot', 'html', 'gather.js'));

test('the needle is in the green only inside the arc, also across the top', () => {
    assert.strictEqual(g.inZone(100, 100, 72), true);
    assert.strictEqual(g.inZone(136, 100, 72), true);
    assert.strictEqual(g.inZone(137, 100, 72), false);
    assert.strictEqual(g.inZone(350, 10, 72), true);
});

test('the next arc is always well away from the needle', () => {
    for (const r of [0, 0.3, 0.7, 0.999]) assert.ok(g.angDiff(g.nextZone(200, () => r), 200) >= 100);
});

test('settings: easy defaults, clamped', () => {
    const s = g.settings({ hits: 3, zone: 0.2, speed: 0.45 });
    assert.strictEqual(s.hits, 3);
    assert.strictEqual(s.width, 72);
    assert.ok(Math.abs(s.speed - 162) < 1e-9);
    const d = g.settings({});
    assert.strictEqual(d.hits, 3);
    assert.strictEqual(g.settings({ hits: 99, zone: 5, speed: 99 }).hits, 12);
    assert.strictEqual(g.settings({ zone: 5 }).width, 200);
});
