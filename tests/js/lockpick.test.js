// Lockpick minigame logic (node --test tests/js/lockpick.test.js).

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const lp = require(path.join(__dirname, '..', '..', 'resources', '[wasteland]', 'wasteland_vehicles', 'html', 'lockpick.js'));

test('angles wrap around the lock', () => {
    assert.strictEqual(lp.norm(-30), 330);
    assert.strictEqual(lp.norm(725), 5);
    assert.strictEqual(lp.angDiff(350, 10), 20);
    assert.strictEqual(lp.angDiff(10, 190), 180);
});

test('the pick is in the zone only inside its width', () => {
    assert.strictEqual(lp.inZone(100, 100, 30), true);
    assert.strictEqual(lp.inZone(115, 100, 30), true);
    assert.strictEqual(lp.inZone(116, 100, 30), false);
    assert.strictEqual(lp.inZone(355, 5, 30), true); // across the top
});

test('a new zone is always far from the pick', () => {
    for (const r of [0, 0.25, 0.5, 0.999]) {
        const z = lp.nextZone(40, () => r);
        assert.ok(lp.angDiff(z, 40) >= 100, 'zone ' + z);
    }
});
