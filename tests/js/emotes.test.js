// Emote menu and hotbar logic (node --test tests/js/emotes.test.js).

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const R = path.join(__dirname, '..', '..', 'resources', '[wasteland]');
const emotes = require(path.join(R, 'wasteland_emotes', 'html', 'emotes.js'));
const hotbar = require(path.join(R, 'wasteland_inventory', 'html', 'hotbar.js'));

const list = [{ name: 'wave', label: 'Wave', cat: 'Gestures' }, { name: 'sit', label: 'Sit on the ground', cat: 'Sit & lie' },
    { name: 'smoke', label: 'Smoke', cat: 'Moods' }];

test('emote search and categories', () => {
    assert.strictEqual(emotes.filterEmotes(list, '', '').length, 3);
    assert.deepStrictEqual(emotes.filterEmotes(list, 'GROUND', '').map((e) => e.name), ['sit']);
    assert.deepStrictEqual(emotes.filterEmotes(list, '', 'Moods').map((e) => e.name), ['smoke']);
    assert.strictEqual(emotes.filterEmotes(list, 'wave', 'Moods').length, 0);
});

test('hotbar slot counts', () => {
    assert.strictEqual(hotbar.countText({ key: 1 }), '');
    assert.strictEqual(hotbar.countText({ label: 'Bandage', count: 3 }), 'x3');
    assert.strictEqual(hotbar.countText({ label: 'Pistol', count: 1 }), '');
    assert.strictEqual(hotbar.countText({ label: 'Cash', count: 1500, cash: true }), '$1,500');
});

const tailor = require(path.join(R, 'wasteland_tailor', 'html', 'tailor.js'));

test('tailor: arrows wrap; only changed pieces are paid for', () => {
    assert.strictEqual(tailor.step(0, -1, 5), 5);
    assert.strictEqual(tailor.step(5, 1, 5), 0);
    assert.strictEqual(tailor.step(2, 1, 0), 0);
    const pieces = [
        { slot: 'legs', parts: [{ key: 'legs', d: 3, t: 1, od: 3, ot: 0 }] },
        { slot: 'feet', parts: [{ key: 'shoes', d: 2, t: 0, od: 2, ot: 0 }] },
    ];
    assert.deepStrictEqual(tailor.changes(pieces), [{ slot: 'legs', look: { legs: [3, 1] } }]);
});

const group = require(path.join(R, 'wasteland_groups', 'html', 'group.js'));

test('group members line', () => {
    const g = { members: [{ online: true }, { online: false }, { online: true }] };
    assert.strictEqual(group.summary(g, 8), '3 of 8 members, 2 online');
});

const base = require(path.join(R, 'wasteland_bases', 'html', 'base.js'));

test('base upkeep line', () => {
    assert.strictEqual(base.upkeepText({ item: 'Scrap metal', perDay: 2, stock: 5, paidHours: 30, coveredDays: 2, decaying: false }),
        'Paid for 1 d 6 h. Upkeep: 2 x Scrap metal a day; the box holds 5 (2 more days).');
    assert.strictEqual(base.upkeepText({ item: 'Scrap metal', perDay: 2, stock: 0, paidHours: 0, decaying: true, removeHours: 40 }),
        'Upkeep unpaid! Put 2 x Scrap metal in the upkeep box or the base falls apart in 40 h.');
});


const invUi = require(path.join(R, 'wasteland_inventory', 'html', 'inventory.js'));

test('inventory cells shrink to fit big grids on the screen', () => {
    assert.strictEqual(invUi.cellSize(1920, 1080, 4, 6, false), 50);
    // 10 x 10 pockets with the 12 x 10 hiking bag under them on 1920 x 1080: both fit top to bottom
    const c = invUi.cellSize(1920, 1080, 10 + 10 + 2, 12, false);
    assert.ok(22 * c + 230 <= 1080, 'fits: ' + c);
    assert.ok(c >= 24);
});

test('inventory hover box: name, amount, money for cash, condition', () => {
    assert.deepStrictEqual(invUi.tipLines({ label: '9mm rounds' }, { name: 'ammo_9mm', count: 23 }, null, 'cash'), ['9mm rounds', 'Amount: 23']);
    assert.deepStrictEqual(invUi.tipLines({ label: 'Cash' }, { name: 'cash', count: 8220 }, null, 'cash'), ['Cash', '$8,220']);
    assert.deepStrictEqual(invUi.tipLines({ label: 'Pistol' }, { name: 'weapon_pistol', count: 1 }, { text: 'Condition 80%' }, 'cash'),
        ['Pistol', 'Amount: 1 · Condition 80%']);
});

const trade = require(path.join(R, 'wasteland_trade', 'html', 'trade.js'));

test('trade status line', () => {
    const v = (me, them) => ({ me: { ready: me }, them: { ready: them, name: 'Bert' } });
    assert.strictEqual(trade.status(v(false, false)), 'Add items, then both press Accept. Any change cancels the accepts.');
    assert.strictEqual(trade.status(v(true, false)), 'You accepted. Waiting for Bert.');
    assert.strictEqual(trade.status(v(false, true)), 'Bert accepted. Check their offer and accept.');
});


const cook = require(path.join(R, 'wasteland_hunting', 'html', 'cook.js'));

test('cooking amount stays between 1 and what you have', () => {
    assert.strictEqual(cook.clampCount(5, 3, 50), 3);
    assert.strictEqual(cook.clampCount(0, 3, 50), 1);
    assert.strictEqual(cook.clampCount('abc', 3, 50), 1);
    assert.strictEqual(cook.clampCount(80, 100, 50), 50);
});

test('cooking window: still cooking after the first pieces, until finished', () => {
    assert.strictEqual(cook.cooking({ label: 'Raw meat', done: 0, total: 5 }), true);
    assert.strictEqual(cook.cooking({ label: 'Raw meat', done: 1, total: 5 }), true);   // the bug: 1 piece ready looked "done"
    assert.strictEqual(cook.cooking({ label: 'Raw meat', done: 4, total: 5 }), true);
    assert.strictEqual(cook.cooking({ finished: true, message: 'Cooked 5 x Cooked meat.' }), false);
    assert.strictEqual(cook.cooking(null), false);
});


const bb = require(path.join(R, 'wasteland_basebuilding', 'html', 'build.js'));

test('base upkeep line per material', () => {
    assert.strictEqual(bb.upkeepLine({ daily: 0, pieces: 0 }), 'no pieces');
    assert.strictEqual(bb.upkeepLine({ daily: 3, have: 0, hours: 0 }), 'OUT OF SUPPLY: these pieces are decaying');
    assert.strictEqual(bb.upkeepLine({ daily: 3, have: 9, hours: 72 }), '3.0 days left');
    assert.strictEqual(bb.upkeepLine({ daily: 24, have: 5, hours: 5 }), 'ONLY 5.0 hours left');
});
