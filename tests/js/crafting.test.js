// Crafting screen logic (node --test tests/js/crafting.test.js).

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const crafting = require(path.join(__dirname, '..', '..', 'resources', '[wasteland]', 'wasteland_crafting', 'html', 'crafting.js'));

test('canCraft: every ingredient in hand', () => {
    assert.strictEqual(crafting.canCraft({ ingredients: [{ need: 2, have: 2 }, { need: 1, have: 3 }] }), true);
    assert.strictEqual(crafting.canCraft({ ingredients: [{ need: 2, have: 1 }] }), false);
    assert.strictEqual(crafting.canCraft(null), false);
});

test('how many can be made', () => {
    assert.strictEqual(crafting.maxCraft({ ingredients: [{ need: 2, have: 7 }, { need: 1, have: 5 }] }), 3);
    assert.strictEqual(crafting.maxCraft({ ingredients: [{ need: 2, have: 1 }] }), 0);
    assert.strictEqual(crafting.maxCraft({ ingredients: [{ need: 1, have: 999 }] }), 50);
});

