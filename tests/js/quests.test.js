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

const tracker = require(path.join(__dirname, '..', '..', 'resources', '[wasteland]', 'wasteland_quests', 'html', 'tracker.js'));
const log = require(path.join(__dirname, '..', '..', 'resources', '[wasteland]', 'wasteland_quests', 'html', 'log.js'));

test('tracker distances read naturally', () => {
    assert.strictEqual(tracker.distance(340.4), '340 m');
    assert.strictEqual(tracker.distance(1234), '1.2 km');
    assert.strictEqual(tracker.distance(null), '');
});

test('/quest: the story step in one line', () => {
    assert.strictEqual(log.storyLine({ step: { type: 'kill', count: 8, progress: 3, objective: 'Clear the clinic', where: 'Paleto' } }),
        'Clear the clinic (3/8) · Paleto');
    assert.strictEqual(log.storyLine({ step: { type: 'talk', title: 'Hollis', where: 'Hollis' } }), 'Hollis · Hollis');
    assert.strictEqual(log.storyLine(null), '');
});
