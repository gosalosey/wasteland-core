// Admin panel logic (node --test tests/js/admin.test.js).

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const admin = require(path.join(__dirname, '..', '..', 'resources', '[wasteland]', 'wasteland_admin', 'html', 'admin.js'));

const players = [
    { id: 1, name: 'Boss', character: { firstName: 'Ann', lastName: 'Lee' } },
    { id: 12, name: 'Guy', character: null },
];

test('players are found by id, name or character name', () => {
    assert.deepStrictEqual(admin.filterPlayers(players, '').map((p) => p.id), [1, 12]);
    assert.deepStrictEqual(admin.filterPlayers(players, '12').map((p) => p.id), [12]);
    assert.deepStrictEqual(admin.filterPlayers(players, 'boss').map((p) => p.id), [1]);
    assert.deepStrictEqual(admin.filterPlayers(players, 'ann lee').map((p) => p.id), [1]);
    assert.deepStrictEqual(admin.filterPlayers(players, 'nobody'), []);
});

test('items are found by name, label or category', () => {
    const items = [{ name: 'water_bottle', label: 'Water bottle', category: 'drink' }, { name: 'bandage', label: 'Bandage', category: 'medical' }];
    assert.strictEqual(admin.filterItems(items, 'water').length, 1);
    assert.strictEqual(admin.filterItems(items, 'medical')[0].name, 'bandage');
    assert.strictEqual(admin.filterItems(items, '').length, 2);
});

test('ban status: active, expired, lifted', () => {
    const now = 1000;
    assert.strictEqual(admin.banStatus({ expires_unix: null }, now).text, 'Permanent');
    assert.strictEqual(admin.banStatus({ expires_unix: 2000 }, now).state, 'active');
    assert.strictEqual(admin.banStatus({ expires_unix: 999 }, now).state, 'expired');
    assert.strictEqual(admin.banStatus({ expires_unix: 2000, revoked_unix: 1500, revoked_by: 'Boss' }, now).text, 'Lifted by Boss');
});

test('ban durations include permanent', () => {
    assert.ok(admin.DURATIONS.some((d) => d.minutes === 0 && d.label === 'Permanent'));
});

test('groupItems: items by category in inventory order, sorted by label', () => {
    const items = [
        { name: 'zz', label: 'Zeta', category: 'misc' }, { name: 'p', label: 'Pistol', category: 'weapon' },
        { name: 'b', label: 'Bandage', category: 'medical' }, { name: 'a', label: 'Axe', category: 'weapon' },
        { name: 'x', label: 'Thing', category: 'odd' },
    ];
    const g = admin.groupItems(items);
    assert.deepStrictEqual(g.map((x) => x.category), ['weapon', 'medical', 'misc', 'odd']);
    assert.deepStrictEqual(g[0].items.map((i) => i.label), ['Axe', 'Pistol']);
});

test('coordinates as text for scripts', () => {
    const c = { x: 123.456, y: -45.6, z: 30, h: 271.239 };
    assert.strictEqual(admin.coordText(c, 'vector3'), 'vector3(123.46, -45.60, 30.00)');
    assert.strictEqual(admin.coordText(c, 'vector4'), 'vector4(123.46, -45.60, 30.00, 271.24)');
    assert.strictEqual(admin.coordText(c, 'heading'), '271.24');
    assert.strictEqual(admin.coordText(c, 'xyz'), 'X 123.46   Y -45.60   Z 30.00   Heading 271.24');
});
