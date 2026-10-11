// Unit tests for the NUI JavaScript (Node's built-in runner: node --test tests/js).
// They cover the logic that does not need a browser: the shell's message
// routing and the screens' pure helpers. Rendering is checked in-game.

'use strict';

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const RES = path.join(__dirname, '..', '..', 'resources', '[wasteland]');
const { createShell } = require(path.join(RES, 'wasteland_ui', 'html', 'shell.js'));
const chars = require(path.join(RES, 'wasteland_players', 'html', 'characters.js'));
const creator = require(path.join(RES, 'wasteland_appearance', 'html', 'creator.js'));

// A shell with a fake environment. `scripts` maps url -> function that
// registers screens (called when the script "loads").
function fakeShell(scripts) {
    const log = [];
    const containers = [];
    const posts = [];
    let shell;
    const env = {
        loadScript: (url) => new Promise((resolve, reject) => {
            setImmediate(() => {
                if (!scripts[url]) return reject(new Error('404'));
                scripts[url](shell);
                resolve();
            });
        }),
        createContainer: (name) => { const el = { name, removed: false }; containers.push(el); return el; },
        removeContainer: (el) => { el.removed = true; },
        post: (endpoint, body) => { posts.push({ endpoint, body }); return Promise.resolve({ ok: true }); },
        log: (level, message) => log.push(level + ': ' + message),
    };
    shell = createShell(env);
    return { shell, log, containers, posts };
}

function recorder(calls) {
    return {
        mount: (el, data, api) => { calls.push(['mount', data]); calls.api = api; },
        update: (data) => calls.push(['update', data]),
        unmount: () => calls.push(['unmount']),
    };
}

test('shell loads a screen script once and mounts with the open data', async () => {
    const calls = [];
    let loads = 0;
    const f = fakeShell({ 'https://cfx-nui-res/a.js': (shell) => { loads++; shell.registerScreen('a', recorder(calls)); } });
    await f.shell.handle({ wl: true, type: 'open', screen: 'a', script: 'https://cfx-nui-res/a.js', data: { x: 1 } });
    assert.deepStrictEqual(calls[0], ['mount', { x: 1 }]);
    assert.ok(f.shell.isOpen('a'));
    f.shell.handle({ wl: true, type: 'close', screen: 'a' });
    await f.shell.handle({ wl: true, type: 'open', screen: 'a', script: 'https://cfx-nui-res/a.js', data: { x: 2 } });
    assert.strictEqual(loads, 1);
    assert.deepStrictEqual(calls.map((c) => c[0]), ['mount', 'unmount', 'mount']);
});

test('updates sent while the script loads are delivered after mount, in order', async () => {
    const calls = [];
    const f = fakeShell({ u: (shell) => shell.registerScreen('s', recorder(calls)) });
    const opening = f.shell.handle({ wl: true, type: 'open', screen: 's', script: 'u', data: {} });
    f.shell.handle({ wl: true, type: 'update', screen: 's', data: 1 });
    f.shell.handle({ wl: true, type: 'update', screen: 's', data: 2 });
    await opening;
    assert.deepStrictEqual(calls.map((c) => c[0] + (c[1] !== undefined && c[0] === 'update' ? c[1] : '')), ['mount', 'update1', 'update2']);
});

test('a screen closed while its script loads is never mounted', async () => {
    const calls = [];
    const f = fakeShell({ u: (shell) => shell.registerScreen('s', recorder(calls)) });
    const opening = f.shell.handle({ wl: true, type: 'open', screen: 's', script: 'u', data: {} });
    f.shell.handle({ wl: true, type: 'close', screen: 's' });
    await opening;
    assert.strictEqual(calls.length, 0);
    assert.ok(!f.shell.isOpen('s'));
});

test('reopening replaces the screen (unmount, then mount) and removes the old container', async () => {
    const calls = [];
    const f = fakeShell({ u: (shell) => shell.registerScreen('s', recorder(calls)) });
    await f.shell.handle({ wl: true, type: 'open', screen: 's', script: 'u', data: 1 });
    await f.shell.handle({ wl: true, type: 'open', screen: 's', script: 'u', data: 2 });
    assert.deepStrictEqual(calls.map((c) => c[0]), ['mount', 'unmount', 'mount']);
    assert.strictEqual(f.containers[0].removed, true);
    assert.strictEqual(f.containers[1].removed, false);
});

test('load failures and scripts that do not register are logged, not thrown', async () => {
    const f = fakeShell({ empty: () => {} });
    await f.shell.handle({ wl: true, type: 'open', screen: 'x', script: 'missing', data: {} });
    await f.shell.handle({ wl: true, type: 'open', screen: 'y', script: 'empty', data: {} });
    assert.ok(f.log.some((l) => l.includes('could not load missing')));
    assert.ok(f.log.some((l) => l.includes('did not register screen "y"')));
});

test('errors inside a screen are logged and do not break the shell', async () => {
    const f = fakeShell({ u: (shell) => shell.registerScreen('s', { mount: () => { throw new Error('boom'); } }) });
    await f.shell.handle({ wl: true, type: 'open', screen: 's', script: 'u', data: {} });
    assert.ok(f.log.some((l) => l.includes('s mount failed: boom')));
});

test('ignores messages that are not for the shell', () => {
    const f = fakeShell({});
    assert.strictEqual(f.shell.handle({ type: 'open', screen: 's' }), undefined);
    assert.strictEqual(f.shell.handle(null), undefined);
});

test('screen actions are posted with the screen name', async () => {
    const calls = [];
    const f = fakeShell({ u: (shell) => shell.registerScreen('s', recorder(calls)) });
    await f.shell.handle({ wl: true, type: 'open', screen: 's', script: 'u', data: {} });
    calls.api.post('save', { a: 1 });
    assert.deepStrictEqual(f.posts[0], { endpoint: 'action', body: { screen: 's', action: 'save', payload: { a: 1 } } });
});

test('registerScreen rejects definitions without mount', () => {
    const f = fakeShell({});
    assert.throws(() => f.shell.registerScreen('x', {}));
});

// ---------------------------------------------------------------- characters

test('slotsView lists every slot with its character or null', () => {
    const view = chars.slotsView({ maxCharacters: 3, characters: [{ slot: 2, firstName: 'A' }] });
    assert.deepStrictEqual(view.map((v) => [v.slot, v.character && v.character.firstName]), [[1, null], [2, 'A'], [3, null]]);
    assert.deepStrictEqual(chars.slotsView(null), []);
});

test('formatPlayTime shows hours and zero-padded minutes', () => {
    assert.strictEqual(chars.formatPlayTime(0), '0h 00m');
    assert.strictEqual(chars.formatPlayTime(3725), '1h 02m');
    assert.strictEqual(chars.formatPlayTime(-5), '0h 00m');
});

// ---------------------------------------------------------------- creator

function sample() {
    return {
        v: 1, model: 'mp_m_freemode_01',
        heritage: { mother: 3, father: 4, shapeMix: 0.3, skinMix: 0.6 },
        features: new Array(20).fill(0.1),
        hair: { style: 50, color: 1, highlight: 2 },
        eyeColor: 3,
        overlays: new Array(13).fill(0).map(() => ({ style: 255, opacity: 1, color: 0 })),
        components: [{ id: 11, drawable: 400, texture: 9 }],
        props: [{ id: 0, drawable: -1, texture: 0 }],
    };
}

test('setPart updates or adds a clothing entry and resets the texture on a new drawable', () => {
    const a = sample();
    creator.setPart(a, 'components', 11, 'drawable', 5);
    assert.deepStrictEqual(creator.findById(a.components, 11), { id: 11, drawable: 5, texture: 0 });
    creator.setPart(a, 'components', 4, 'texture', 2);
    assert.deepStrictEqual(creator.findById(a.components, 4), { id: 4, drawable: 0, texture: 2 });
    creator.setPart(a, 'props', 1, 'drawable', 3);
    assert.deepStrictEqual(creator.findById(a.props, 1), { id: 1, drawable: 3, texture: 0 });
});

test('switchModel keeps the face and takes clothing and hair from the other defaults', () => {
    const a = sample();
    const female = Object.assign(sample(), { model: 'mp_f_freemode_01', hair: { style: 4, color: 0, highlight: 0 }, components: [] });
    const out = creator.switchModel(a, { male: sample(), female: female }, 'mp_f_freemode_01');
    assert.strictEqual(out.model, 'mp_f_freemode_01');
    assert.deepStrictEqual(out.heritage, a.heritage);
    assert.deepStrictEqual(out.features, a.features);
    assert.strictEqual(out.hair.style, 4);
    assert.deepStrictEqual(out.components, []);
    out.heritage.mother = 40;
    assert.strictEqual(a.heritage.mother, 3); // copies, not shared
});

test('clampToRanges keeps values inside what the game reports', () => {
    const a = sample();
    a.overlays[1] = { style: 90, opacity: 1, color: 0 };
    const out = creator.clampToRanges(a, {
        hair: 36,
        overlays: new Array(13).fill(28),
        components: { 11: { drawables: 200, textures: 3 } },
        props: { 0: { drawables: 150, textures: 0 } },
    });
    assert.strictEqual(out.hair.style, 36);
    assert.strictEqual(out.overlays[1].style, 28);
    assert.strictEqual(out.overlays[0].style, 255); // "none" stays none
    assert.deepStrictEqual(out.components[0], { id: 11, drawable: 200, texture: 3 });
    assert.strictEqual(out.props[0].drawable, -1);
    assert.strictEqual(a.hair.style, 50); // input untouched
});
