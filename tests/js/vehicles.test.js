// Vehicle HUD logic (node --test tests/js/vehicles.test.js).

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const hud = require(path.join(__dirname, '..', '..', 'resources', '[wasteland]', 'wasteland_vehicles', 'html', 'hud.js'));

test('speed in km/h or mph', () => {
    assert.deepStrictEqual(hud.speedText(25, true), { value: '90', unit: 'km/h' });
    assert.deepStrictEqual(hud.speedText(25, false), { value: '56', unit: 'mph' });
    assert.strictEqual(hud.speedText(-3, true).value, '0');
});

test('fuel, engine and body levels; lock and warning', () => {
    const v = hud.view({ speed: 0, fuel: 6, tank: 50, engine: 300, body: 900, hasLock: true, locked: true, warning: 'There is no battery.' });
    assert.strictEqual(v.fuel.text, '6 / 50 L');
    assert.strictEqual(v.fuel.level, 'critical');
    assert.strictEqual(v.engine.level, 'low');
    assert.strictEqual(v.body.text, '90%');
    assert.strictEqual(v.lock, 'Locked');
    assert.strictEqual(v.warning, 'There is no battery.');
    assert.strictEqual(hud.view({ fuel: 60, tank: 50 }).fuel.fill, 100);
});
