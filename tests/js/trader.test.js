// Trade screen logic (node --test tests/js/trader.test.js).

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const trader = require(path.join(__dirname, '..', '..', 'resources', '[wasteland]', 'wasteland_camps', 'html', 'trader.js'));

test('buy list: what the trader sells; sell list: what it buys that you carry', () => {
    const items = [
        { name: 'a', buy: 5, sell: 1, have: 0 }, { name: 'b', sell: 3, have: 2 }, { name: 'c', sell: 3, have: 0 }, { name: 'd', buy: 9 },
    ];
    assert.deepStrictEqual(trader.buyList(items).map((i) => i.name), ['a', 'd']);
    assert.deepStrictEqual(trader.sellList(items).map((i) => i.name), ['b']);
    assert.strictEqual(trader.money(12500.7), '$12,500');
});
