// Survivor trade window logic (node --test tests/js/survivors.test.js).

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const barter = require(path.join(__dirname, '..', '..', 'resources', '[wasteland]', 'wasteland_survivors', 'html', 'barter.js'));

test('a trade can be made with enough items while they have some left', () => {
    const o = { left: 2, give: { count: 3, have: 3 }, get: { count: 1 } };
    assert.strictEqual(barter.canTrade(o), true);
    assert.strictEqual(barter.why(o), '2 left');
    assert.strictEqual(barter.canTrade({ ...o, give: { count: 3, have: 1 } }), false);
    assert.strictEqual(barter.why({ ...o, give: { count: 3, have: 1 } }), 'you have 1');
    assert.strictEqual(barter.canTrade({ ...o, left: 0 }), false);
    assert.strictEqual(barter.why({ ...o, left: 0 }), 'none left');
});
