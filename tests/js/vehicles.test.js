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

test('layout: size limits, default position, screen fractions', () => {
    assert.strictEqual(hud.clampScale(3), 1.8);
    assert.strictEqual(hud.clampScale(0.1), 0.6);
    assert.strictEqual(hud.clampScale('x'), 1);
    assert.strictEqual(hud.clampScale(1.234), 1.23);
    assert.deepStrictEqual(hud.normalizeLayout(null), { x: null, y: null, scale: 1 });
    assert.deepStrictEqual(hud.normalizeLayout({ x: 0.5 }), { x: null, y: null, scale: 1 });
    assert.deepStrictEqual(hud.normalizeLayout({ x: 2, y: -1, scale: 1.5 }), { x: 1, y: 0, scale: 1.5 });
    const box = { w: 200, h: 100 }, scr = { w: 1200, h: 700 };
    assert.strictEqual(hud.toPixels({}, box, scr), null);
    assert.deepStrictEqual(hud.toPixels({ x: 0.5, y: 1 }, box, scr), { left: 500, top: 600 });
    assert.deepStrictEqual(hud.toFractions(500, 600, box, scr), { x: 0.5, y: 1 });
    assert.deepStrictEqual(hud.toFractions(-50, 9999, box, scr), { x: 0, y: 1 });
});
