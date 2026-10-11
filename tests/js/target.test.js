// Target screen logic (node --test tests/js/target.test.js).

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const target = require(path.join(__dirname, '..', '..', 'resources', '[wasteland]', 'wasteland_target', 'html', 'target.js'));

test('rows: one selected, default icon, clamped selection', () => {
    const r = target.rows({ selected: 2, options: [{ label: 'Search', icon: '⌕' }, { label: 'Climb' }] });
    assert.deepStrictEqual(r, [{ label: 'Search', icon: '⌕', selected: false }, { label: 'Climb', icon: '•', selected: true }]);
    assert.strictEqual(target.rows({ selected: 9, options: [{ label: 'A' }] })[0].selected, true);
    assert.deepStrictEqual(target.rows({}), []);
});
