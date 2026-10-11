// Inventory screen logic (node --test tests/js/inventory.test.js).
// The placement rules must match shared/grid.lua exactly; the server is the
// authority, but a wrong preview would confuse players.

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const inv = require(path.join(__dirname, '..', '..', 'resources', '[wasteland]', 'wasteland_inventory', 'html', 'inventory.js'));

const DEFS = {
    can: { width: 1, height: 1, stack: 5 },
    bottle: { width: 1, height: 2, stack: 1 },
    plank: { width: 3, height: 1, stack: 1 },
    crate: { width: 2, height: 2, stack: 1 },
    top: { width: 2, height: 2, stack: 1, equip: 'torso' },
};

function grid(w, h, items) { return { id: 'player:1', width: w, height: h, items: items || [] }; }

test('fits: bounds, rotation, overlap and ignoring the moved stack', () => {
    const g = grid(4, 3, [{ uid: 'c', name: 'crate', count: 1, x: 1, y: 1 }]);
    assert.strictEqual(inv.fits(g, DEFS, DEFS.plank, 1, 0, false), true);
    assert.strictEqual(inv.fits(g, DEFS, DEFS.plank, 2, 0, false), false);
    assert.strictEqual(inv.fits(g, DEFS, DEFS.plank, 0, 0, true), true);
    assert.strictEqual(inv.fits(g, DEFS, DEFS.bottle, 2, 0, false), false);
    assert.strictEqual(inv.fits(g, DEFS, DEFS.crate, 2, 1, false, 'c'), true);
    assert.strictEqual(inv.fits(g, DEFS, DEFS.can, 0.5, 0, false), false);
});

test('findSpot matches the server: row by row, unrotated first', () => {
    const g = grid(3, 3, [{ uid: 'a', name: 'crate', count: 1, x: 0, y: 0 }]);
    assert.deepStrictEqual(inv.findSpot(g, DEFS, DEFS.bottle), { x: 2, y: 0, rotated: false });
    assert.deepStrictEqual(inv.findSpot(g, DEFS, DEFS.plank), { x: 0, y: 2, rotated: false });
    assert.deepStrictEqual(inv.findSpot(grid(1, 3), DEFS, DEFS.plank), { x: 0, y: 0, rotated: true });
    assert.strictEqual(inv.findSpot(grid(2, 2, [{ uid: 'a', name: 'crate', count: 1, x: 0, y: 0 }]), DEFS, DEFS.can), null);
});

test('decideDrop: move to a free cell, nothing when blocked', () => {
    const g = grid(4, 4, [{ uid: 'b', name: 'bottle', count: 1, x: 0, y: 0 }, { uid: 'c', name: 'crate', count: 1, x: 2, y: 0 }]);
    const drag = { stack: g.items[0], from: 'player:1', rotated: false };
    const move = inv.decideDrop(drag, { kind: 'grid', inv: g, x: 0, y: 2, cellX: 0, cellY: 2 }, DEFS, 'equip:1');
    assert.deepStrictEqual(move, { action: 'move', payload: { uid: 'b', from: 'player:1', to: 'player:1', x: 0, y: 2, rotated: false } });
    assert.strictEqual(inv.decideDrop(drag, { kind: 'grid', inv: g, x: 2, y: 0, cellX: 2, cellY: 0 }, DEFS, 'equip:1'), null);
});

test('decideDrop: dropping onto the same stackable item merges', () => {
    const g = grid(4, 4, [{ uid: 'a', name: 'can', count: 2, x: 0, y: 0 }, { uid: 'b', name: 'can', count: 1, x: 3, y: 3 }]);
    const drag = { stack: g.items[1], from: 'player:1', rotated: false };
    const d = inv.decideDrop(drag, { kind: 'grid', inv: g, x: 0, y: 0, cellX: 0, cellY: 0 }, DEFS, 'equip:1');
    assert.strictEqual(d.action, 'merge');
    assert.strictEqual(d.payload.target, 'a');
    // different metadata does not merge
    g.items[1].metadata = { spoiled: true };
    assert.strictEqual(inv.decideDrop(drag, { kind: 'grid', inv: g, x: 0, y: 0, cellX: 0, cellY: 0 }, DEFS, 'equip:1'), null);
});

test('decideDrop: equipment slots, taking off, hotbar and ground', () => {
    const top = { uid: 't', name: 'top', count: 1, x: 0, y: 0 };
    const g = grid(4, 4, [top]);
    const drag = { stack: top, from: 'player:1', rotated: false };
    assert.deepStrictEqual(inv.decideDrop(drag, { kind: 'slot', slot: 'torso' }, DEFS, 'equip:1'),
        { action: 'equip', payload: { uid: 't', from: 'player:1', slot: 'torso' } });
    assert.strictEqual(inv.decideDrop(drag, { kind: 'slot', slot: 'legs' }, DEFS, 'equip:1'), null);
    const worn = { uid: 't', name: 'top', count: 1, slot: 'torso' };
    const off = inv.decideDrop({ stack: worn, from: 'equip:1', rotated: false }, { kind: 'grid', inv: grid(4, 4), x: 1, y: 1, cellX: 1, cellY: 1 }, DEFS, 'equip:1');
    assert.deepStrictEqual(off, { action: 'unequip', payload: { slot: 'torso', to: 'player:1', x: 1, y: 1, rotated: false } });
    assert.deepStrictEqual(inv.decideDrop(drag, { kind: 'hotbar', index: 3 }, DEFS, 'equip:1'), { action: 'setHotbar', payload: { index: 3, uid: 't' } });
    assert.deepStrictEqual(inv.decideDrop(drag, { kind: 'ground' }, DEFS, 'equip:1'), { action: 'drop', payload: { uid: 't', from: 'player:1', count: 1 } });
    assert.strictEqual(inv.decideDrop(drag, null, DEFS, 'equip:1'), null);
    void g;
});

test('labels and weights are formatted for the tiles', () => {
    assert.strictEqual(inv.shortLabel('Can', 1), 'Can');
    assert.strictEqual(inv.shortLabel('Hiking backpack', 1), 'HB');
    assert.strictEqual(inv.shortLabel('Hiking backpack', 4), 'Hiking backpack');
    assert.strictEqual(inv.formatKg(1.25), '1.3');
    assert.strictEqual(inv.formatKg(12), '12.0');
});
