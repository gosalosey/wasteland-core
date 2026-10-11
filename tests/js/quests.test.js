// Job board logic (node --test tests/js/quests.test.js).

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const board = require(path.join(__dirname, '..', '..', 'resources', '[wasteland]', 'wasteland_quests', 'html', 'board.js'));

test('board button per status', () => {
    assert.strictEqual(board.action({ status: 'available' }).action, 'accept');
    assert.strictEqual(board.action({ status: 'active' }).action, 'abandon');
    assert.strictEqual(board.action({ status: 'ready', handInHere: true }).action, 'handIn');
    assert.strictEqual(board.action({ status: 'ready', handInHere: false }).disabled, true);
    assert.strictEqual(board.action({ status: 'cooldown', minutes: 12 }).label, 'Again in 12 min');
});
