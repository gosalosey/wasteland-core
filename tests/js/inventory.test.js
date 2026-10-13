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

test('quickTarget: takes into pockets, tops up a stack first, falls back to the bag, refuses when heavy or full', () => {
    const defs = {
        ammo: { width: 1, height: 1, stack: 100, weight: 0.01 },
        rifle: { width: 5, height: 2, stack: 1, weight: 3 },
        rock: { width: 1, height: 1, stack: 1, weight: 20 },
    };
    const pockets = { id: 'player:1', width: 6, height: 4, weight: 1, maxWeight: 35, items: [
        { uid: 'p1', name: 'ammo', count: 95, x: 0, y: 0, metadata: {} },
        { uid: 'p2', name: 'rifle', count: 1, x: 0, y: 1 },
        { uid: 'p3', name: 'rifle', count: 1, x: 0, y: 3 - 0 },
    ] };
    const bag = { id: 'item:b', width: 7, height: 6, weight: 0, maxWeight: 60, items: [] };
    const loot = { id: 'stash:loot_x', width: 6, height: 5, weight: 0, maxWeight: 200, items: [
        { uid: 'l1', name: 'ammo', count: 20, x: 0, y: 0, metadata: {} },
        { uid: 'l2', name: 'rifle', count: 1, x: 0, y: 1 },
        { uid: 'l3', name: 'rock', count: 1, x: 0, y: 3 },
    ] };
    const snap = { pockets: 'player:1', backpack: 'item:b', secondary: ['stash:loot_x'], inventories: [pockets, bag, loot] };
    const merge = inv.quickTarget(loot.items[0], 'stash:loot_x', snap, defs);
    assert.strictEqual(merge.action, 'merge');
    assert.strictEqual(merge.payload.target, 'p1');
    assert.strictEqual(merge.payload.count, 5); // tops the pocket stack up to 100
    const rifle = inv.quickTarget(loot.items[1], 'stash:loot_x', snap, defs);
    assert.strictEqual(rifle.action, 'move');
    assert.strictEqual(rifle.payload.to, 'item:b'); // pockets have no 5x2 room left
    pockets.weight = 34; bag.weight = 59;
    assert.strictEqual(inv.quickTarget(loot.items[2], 'stash:loot_x', snap, defs).error, 'Too heavy to carry.');
    // from your pockets back into the open container
    assert.strictEqual(inv.quickTarget(pockets.items[1], 'player:1', snap, defs).payload.to, 'stash:loot_x');
    // no loot open, backpack open: pockets <-> backpack
    pockets.weight = 1; bag.weight = 1;
    const toBag = inv.quickTarget(pockets.items[1], 'player:1', Object.assign({}, snap, { secondary: [] }), defs);
    assert.strictEqual(toBag.payload.to, 'item:b');
    // backpack closed (the screen leaves it out) and nothing open: nothing to do
    assert.strictEqual(inv.quickTarget(pockets.items[1], 'player:1', Object.assign({}, snap, { secondary: [], backpack: null }), defs), null);
});

test('condition of items with durability', () => {
    const def = { durability: 100 };
    assert.strictEqual(inv.condition({ durability: 0 }, {}), null);
    assert.deepStrictEqual(inv.condition(def, { metadata: {} }), { share: 1, text: 'Condition 100%', ruined: false });
    assert.deepStrictEqual(inv.condition(def, { metadata: { durability: 37 } }), { share: 0.37, text: 'Condition 37%', ruined: false });
    assert.deepStrictEqual(inv.condition(def, { metadata: { durability: 0 } }), { share: 0, text: 'Ruined', ruined: true });
});

test('health panel: what is wrong and how to fix it', () => {
    const cures = { bleeding: ['Bandage', 'Rag'], infection: ['Antibiotics'], hunger: ['Canned beans'], thirst: ['Water bottle'], health: ['Painkillers'], cold: [] };
    assert.deepStrictEqual(inv.conditions({ health: 100, hunger: 80, thirst: 80, temperature: 37, bleeding: 0, infection: 0, cures }), []);
    assert.deepStrictEqual(inv.conditions({ dead: true, bleeding: 3 }), []);
    const c = inv.conditions({ health: 20, hunger: 10, thirst: 50, temperature: 34.8, bleeding: 2, infection: 70, treatment: false, armor: 0,
        cures, limits: { hypothermia: 35, hyperthermia: 39.5, infectionDamage: 60 } });
    const byKey = {};
    c.forEach((x) => { byKey[x.key] = x; });
    assert.strictEqual(byKey.bleeding.title, 'Bleeding heavily');
    assert.ok(byKey.bleeding.fix.startsWith('Stop it with: Bandage, Rag.'));
    assert.strictEqual(byKey.infection.level, 'critical');
    assert.ok(byKey.infection.fix.includes('Antibiotics') && byKey.infection.fix.includes('hurting you now'));
    assert.strictEqual(byKey.health.title, 'Hurt (health 20%)');
    assert.strictEqual(byKey.hunger.level, 'critical');
    assert.strictEqual(byKey.thirst, undefined);
    assert.strictEqual(byKey.cold.title, 'Hypothermia (94.6 °F)');
    assert.strictEqual(byKey.armor.title, 'Armor plate broken');
    const treated = inv.conditions({ infection: 30, treatment: true, cures });
    assert.strictEqual(treated[0].title, 'Infected 30% (treated)');
});

test('body temperature in Fahrenheit and how it feels', () => {
    assert.strictEqual(inv.toF(37), 98.6);
    assert.strictEqual(inv.feels(37), 'Comfortable');
    assert.strictEqual(inv.feels(35.3), 'Cold');
    assert.strictEqual(inv.feels(34.9, { hypothermia: 35 }), 'Freezing');
    assert.strictEqual(inv.feels(38.7), 'Hot');
    assert.strictEqual(inv.feels(39.6, { hyperthermia: 39.5 }), 'Overheating');
});

test('a repair kit lists the damaged pieces of its category, most worn first', () => {
    const defs = { items: { clothing_top: { label: 'Top', category: 'clothing', durability: 100 },
        clothing_pants: { label: 'Pants', category: 'clothing', durability: 100 },
        armor_plate: { label: 'Armor plate', category: 'armor', durability: 100 } } };
    const snap = { equip: 'equip:1', pockets: 'player:1', inventories: [
        { id: 'equip:1', items: [{ uid: 'a', name: 'clothing_top', metadata: { durability: 60 } }, { uid: 'p', name: 'armor_plate', metadata: { durability: 10 } }] },
        { id: 'player:1', items: [{ uid: 'b', name: 'clothing_pants', metadata: { durability: 20 } }, { uid: 'c', name: 'clothing_pants', metadata: {} }] },
        { id: 'stash:x', items: [{ uid: 'd', name: 'clothing_top', metadata: { durability: 1 } }] },
    ] };
    assert.deepStrictEqual(inv.repairChoices(snap, defs, 'clothing'), [
        { uid: 'b', label: 'Pants', share: 0.2, worn: false },
        { uid: 'a', label: 'Top', share: 0.6, worn: true },
    ]);
    assert.strictEqual(inv.repairChoices(snap, defs, 'armor')[0].uid, 'p');
});

