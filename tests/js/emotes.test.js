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
