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
