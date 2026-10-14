// wasteland_survival :: html/hud.js
// Survival HUD (runs inside wasteland_ui, no input focus): four outlined
// icons that drain like a liquid level - health (drop), food (tray), drink
// (bottle), temperature (thermometer) - plus small badges for bleeding and
// infection. Modes:
//   compact    - every icon, always
//   immersive  - an icon only while it matters (low, cold, hot)
//   off        - nothing
// /hud opens edit mode: drag the HUD anywhere, pick mode, row/column and
// size, then Save (client/main.lua stores it on the player's PC).
// Also: a line with the player's server id, character name and cash (moves
// with the HUD), and a stamina bar at the bottom middle of the screen that
// only shows while stamina is being used.
// Data: { mode, health, armor (plate %, only while one is worn), stamina, editing, layout = { x, y, vertical, size },
//         info = { id, name, cash },
//         stats = { hunger, thirst, infection, bleeding, temperature, treatment, dead } }

(function () {
    'use strict';

    // ------------------------------------------------------------------
    // Pure helpers (unit-tested with Node)
    // ------------------------------------------------------------------

    const LOW = 35;       // amber at or below; immersive shows the icon
    const CRITICAL = 15;  // red and pulsing at or below
    const TEMP_MIN = 33;  // thermometer empty
    const TEMP_MAX = 39;  // thermometer full

    const clamp = (v) => Math.max(0, Math.min(100, Math.round(v)));

    function levelOf(value) {
        if (value <= CRITICAL) return 'critical';
        if (value <= LOW) return 'low';
        return 'ok';
    }

    function tempLevel(t) {
        if (t <= 34.5 || t >= 39.5) return 'critical';
        if (t <= 35.5 || t >= 38.5) return 'low';
        return 'ok';
    }

    // Icons to show: [{ key, label, fill 0..100, level ok|low|critical }]
    function icons(data) {
        const s = data.stats || {};
        if (data.mode === 'off' || s.dead) return [];
        const all = [];
        if (typeof data.health === 'number') all.push({ key: 'health', label: 'Health', fill: clamp(data.health) });
        if (typeof data.armor === 'number') all.push({ key: 'armor', label: 'Armor', fill: clamp(data.armor) });
        if (typeof s.hunger === 'number') all.push({ key: 'food', label: 'Food', fill: clamp(s.hunger) });
        if (typeof s.thirst === 'number') all.push({ key: 'drink', label: 'Drink', fill: clamp(s.thirst) });
        all.forEach((i) => { i.level = levelOf(i.fill); });
        if (typeof s.temperature === 'number') {
            const t = s.temperature;
            all.push({ key: 'temp', label: 'Temp.', fill: clamp((t - TEMP_MIN) / (TEMP_MAX - TEMP_MIN) * 100), level: tempLevel(t),
                hot: t >= 38.5 });
        }
        // toilet: these fill up (full = you have to go)
        const need = (v) => (v >= 85 ? 'critical' : v >= 65 ? 'low' : 'ok');
        if (typeof s.bladder === 'number') all.push({ key: 'pee', label: 'Pee', fill: clamp(s.bladder), level: need(s.bladder) });
        if (typeof s.bowel === 'number') all.push({ key: 'poop', label: 'Poop', fill: clamp(s.bowel), level: need(s.bowel) });
        if (data.mode === 'immersive') return all.filter((i) => i.level !== 'ok');
        return all;
    }

    // Badges: bleeding (1-3) and infection (percent, treated or not).
    function badges(data) {
        const s = data.stats || {};
        if (data.mode === 'off' || s.dead) return [];
        const out = [];
        if (s.bleeding > 0) {
            const lvl = Math.min(3, s.bleeding);
            out.push({ key: 'bleeding', level: lvl, text: ['', 'Bleeding', 'Bleeding heavily', 'Bleeding severely'][lvl] });
        }
        if (s.infection > 0) {
            out.push({ key: 'infection', text: (s.treatment ? 'Infection (treated) ' : 'Infection ') + clamp(s.infection) + '%' });
        }
        return out;
    }

    // Id, name and cash line (null when the HUD is off). Cash null = unknown
    // (inventory not running).
    function infoLine(data) {
        const s = data.stats || {};
        if (data.mode === 'off' || s.dead || !data.info) return null;
        const i = data.info;
        const cash = typeof i.cash === 'number' ? '$' + Math.max(0, Math.floor(i.cash)).toLocaleString('en-US') : null;
        return { id: typeof i.id === 'number' ? '#' + i.id : null, name: i.name ? String(i.name) : null, cash: cash };
    }

    // Stamina bar: shown only while stamina is not full (and the HUD is on).
    function staminaBar(data) {
        const s = data.stats || {};
        if (data.mode === 'off' || s.dead || typeof data.stamina !== 'number') return { visible: false, fill: 100 };
        const fill = clamp(data.stamina);
        return { visible: fill < 100, fill: fill, low: fill <= 20 };
    }

    // Layout: x/y are the share of the free space left of / above the HUD
    // (0 = left/top edge, 1 = right/bottom edge), so the HUD stays on screen
    // at any resolution or size. x/y null = default corner (bottom right).
    const SIZES = { s: 0.8, m: 1, l: 1.3 };
    const unit = (v) => (typeof v === 'number' && isFinite(v) ? Math.max(0, Math.min(1, v)) : null);

    function normalizeLayout(l) {
        l = l || {};
        let x = unit(l.x);
        let y = unit(l.y);
        if (x === null || y === null) { x = null; y = null; }
        return { x: x, y: y, vertical: l.vertical === true, size: SIZES[l.size] ? l.size : 'm' };
    }

    // Pixel position of the HUD's top-left corner (null = default corner).
    function toPixels(layout, box, view) {
        const l = normalizeLayout(layout);
        if (l.x === null) return null;
        return {
            left: Math.round(l.x * Math.max(0, view.w - box.w)),
            top: Math.round(l.y * Math.max(0, view.h - box.h)),
        };
    }

    // Layout x/y for a HUD dragged to left/top (clamped to the screen).
    function toFractions(left, top, box, view) {
        const fw = view.w - box.w;
        const fh = view.h - box.h;
        const r = (v) => Math.round(Math.max(0, Math.min(1, v)) * 10000) / 10000;
        return { x: fw > 0 ? r(left / fw) : 0, y: fh > 0 ? r(top / fh) : 0 };
    }

    if (typeof module === 'object' && module.exports) {
        module.exports = { icons: icons, badges: badges, infoLine: infoLine, staminaBar: staminaBar, normalizeLayout: normalizeLayout, toPixels: toPixels, toFractions: toFractions };
        return;
    }

    // ------------------------------------------------------------------
    // Screen
    // ------------------------------------------------------------------

    const UI = window.WastelandUI;
    const h = UI.h;
    const NS = 'http://www.w3.org/2000/svg';
    let root;
    let uid = 0;

    function svg(tag, attrs, children) {
        const el = document.createElementNS(NS, tag);
        Object.keys(attrs || {}).forEach((k) => el.setAttribute(k, attrs[k]));
        (children || []).forEach((c) => el.appendChild(c));
        return el;
    }

    // Shapes in a 40 x 48 box: outline, the liquid shape inside it, and
    // details drawn over the liquid (cut-outs in the background colour).
    const SHAPES = {
        health: {
            outline: 'M20 3 C20 3 5 21 5 31 A15 15 0 0 0 35 31 C35 21 20 3 20 3 Z',
            inner: 'M20 9 C20 9 9 23 9 31 A11 11 0 0 0 31 31 C31 23 20 9 20 9 Z',
        },
        food: {
            outline: 'M11 3 H29 A6 6 0 0 1 35 9 V39 A6 6 0 0 1 29 45 H11 A6 6 0 0 1 5 39 V9 A6 6 0 0 1 11 3 Z',
            inner: 'M12 7 H28 A3 3 0 0 1 31 10 V38 A3 3 0 0 1 28 41 H12 A3 3 0 0 1 9 38 V10 A3 3 0 0 1 12 7 Z',
            // fork (left) and knife (right)
            detail: 'M13 11 V19 M15.5 11 V19 M18 11 V19 M13 19 Q15.5 23 18 19 M15.5 21 V37 M24 11 Q28 15 26 24 H24 Z M25 24 V37',
        },
        drink: {
            outline: 'M15 3 H25 V9 C25 12 34 15 34 24 V39 A6 6 0 0 1 28 45 H12 A6 6 0 0 1 6 39 V24 C6 15 15 12 15 9 Z',
            inner: 'M17.5 7 H22.5 V10 C22.5 14 30 17 30 24 V38 A3 3 0 0 1 27 41 H13 A3 3 0 0 1 10 38 V24 C10 17 17.5 14 17.5 10 Z',
        },
        armor: {
            outline: 'M20 3 L35 9 V22 C35 33 28 41 20 45 C12 41 5 33 5 22 V9 Z',
            inner: 'M20 7 L31 11.5 V22 C31 30.5 26 37 20 40.5 C14 37 9 30.5 9 22 V11.5 Z',
        },
        // a droplet with a "P"
        pee: {
            outline: 'M20 3 C20 3 6 20 6 30 A14 14 0 0 0 34 30 C34 20 20 3 20 3 Z',
            inner: 'M20 9 C20 9 10 22 10 30 A10 10 0 0 0 30 30 C30 22 20 9 20 9 Z',
            detail: 'M16.5 38 V24 H21.5 A3.5 3.5 0 0 1 21.5 31 H16.5',
        },
        // a swirl pile
        poop: {
            outline: 'M20 4 C25 6 25 11 22 13 C29 13 31 18 28 21 C35 22 37 28 34 32 C39 34 39 44 32 45 H8 C1 44 1 34 6 32 C3 28 5 22 12 21 C9 18 11 13 18 13 C15 10 16 6 20 4 Z',
            inner: 'M20 8 C22 10 21 13 18 16 C25 16 28 18 26 22 C32 23 34 28 31 32 C36 34 36 41 31 42 H9 C4 41 4 34 9 32 C6 28 8 23 14 22 C12 18 14 16 18 16 Z',
        },
        temp: {
            outline: 'M15 8 A5 5 0 0 1 25 8 V28 A10 10 0 1 1 15 28 Z',
            inner: 'M18 9 A2 2 0 0 1 22 9 V30.5 A6.5 6.5 0 1 1 18 30.5 Z',
        },
    };

    function iconSvg(icon) {
        const shape = SHAPES[icon.key];
        const id = 'wlh-clip-' + (++uid);
        // Liquid from the bottom of the inner shapes (y 44) up to the level (y 7 = full).
        const top = 44 - (37 * icon.fill / 100);
        const clip = svg('clipPath', { id: id }, [svg('rect', { x: '0', y: String(top), width: '40', height: String(48 - top) })]);
        const kids = [
            svg('defs', {}, [clip]),
            svg('path', { d: shape.outline, class: 'wlh-outline' }),
            svg('path', { d: shape.inner, class: 'wlh-liquid', 'clip-path': 'url(#' + id + ')' }),
        ];
        if (shape.detail) kids.push(svg('path', { d: shape.detail, class: 'wlh-detail', 'clip-path': 'url(#' + id + ')' }));
        return svg('svg', { viewBox: '0 0 40 48', class: 'wlh-svg' }, kids);
    }

    // ------------------------------------------------------------------
    // Edit mode (/hud)
    // ------------------------------------------------------------------

    let host;           // the screen element
    let stamina = null; // bottom-middle stamina bar (kept, so it can fade)
    let post;           // api.post(action, payload)
    let toolbar = null;
    let draft = null;   // while editing: { mode, x, y, vertical, size }
    let drag = null;    // { dx, dy } while the mouse holds the HUD
    let last = null;    // last data from the game

    const MODES = [['compact', 'Always'], ['immersive', 'When it matters'], ['off', 'Off']];
    const DEMO = { hunger: 80, thirst: 60, temperature: 37, infection: 0, bleeding: 0, bladder: 40, bowel: 20 };

    function view() { return { w: window.innerWidth, h: window.innerHeight }; }
    function box() { const r = root.getBoundingClientRect(); return { w: r.width, h: r.height }; }

    function place(layout) {
        root.style.setProperty('--wlh-scale', String(SIZES[layout.size] || 1));
        root.classList.toggle('is-vertical', layout.vertical === true);
        const px = toPixels(layout, box(), view());
        if (px) {
            root.style.left = px.left + 'px';
            root.style.top = px.top + 'px';
            root.style.right = 'auto';
            root.style.bottom = 'auto';
        } else {
            root.style.left = '';
            root.style.top = '';
            root.style.right = '';
            root.style.bottom = '';
        }
    }

    function finish(save) {
        if (save && draft) {
            post('saveLayout', { mode: draft.mode, x: draft.x, y: draft.y, vertical: draft.vertical, size: draft.size });
        } else {
            post('cancelLayout', {});
        }
    }

    function buildToolbar() {
        const group = (label, options, current, pick) => {
            const g = h('div', { class: 'wlh-tb__group' }, h('span', { class: 'wlh-tb__label', text: label }));
            options.forEach((o) => {
                g.appendChild(UI.button(o[1], () => { pick(o[0]); render(last); }, o[0] === current ? 'primary' : undefined));
            });
            return g;
        };
        return h('div', { class: 'wlh-tb' },
            h('div', { class: 'wlh-tb__title', text: 'Drag the HUD anywhere on the screen, then Save' }),
            group('Show', MODES, draft.mode, (v) => { draft.mode = v; }),
            group('Layout', [[false, 'Row'], [true, 'Column']], draft.vertical, (v) => { draft.vertical = v; }),
            group('Size', [['s', 'S'], ['m', 'M'], ['l', 'L']], draft.size, (v) => { draft.size = v; }),
            h('div', { class: 'wlh-tb__group' },
                UI.button('Reset', () => { draft.x = null; draft.y = null; draft.vertical = false; draft.size = 'm'; render(last); }),
                UI.button('Cancel', () => finish(false)),
                UI.button('Save', () => finish(true), 'primary')));
    }

    function render(data) {
        last = data;
        const editing = data.editing === true;
        if (editing && !draft) draft = Object.assign({ mode: data.mode || 'compact' }, normalizeLayout(data.layout));
        if (!editing) { draft = null; drag = null; }

        root.innerHTML = '';
        root.classList.toggle('is-editing', editing);
        const line = infoLine(editing ? Object.assign({}, data, { mode: 'compact', stats: {} }) : data);
        if (line) {
            const info = h('div', { class: 'wlh-info' });
            if (line.id) info.appendChild(h('span', { class: 'wlh-info__id', text: line.id }));
            if (line.name) info.appendChild(h('span', { class: 'wlh-info__name', text: line.name }));
            if (line.cash) info.appendChild(h('span', { class: 'wlh-info__cash', text: line.cash }));
            root.appendChild(info);
        }
        // While editing every icon shows, so there is always something to move.
        const shown = editing
            ? Object.assign({}, data, {
                mode: 'compact',
                health: typeof data.health === 'number' ? data.health : 100,
                stats: Object.assign({}, DEMO, data.stats || {}, { dead: false }),
            })
            : data;
        const row = h('div', { class: 'wlh-row' });
        icons(shown).forEach((i) => {
            const el = h('div', { class: 'wlh-icon is-' + i.level });
            el.appendChild(iconSvg(i));
            row.appendChild(el);
        });
        root.appendChild(row);
        const b = badges(shown);
        if (b.length) {
            const list = h('div', { class: 'wlh-badges' });
            b.forEach((x) => list.appendChild(h('span', { class: 'wlh-badge wlh-badge--' + x.key, text: x.text })));
            root.appendChild(list);
        }
        place(editing ? draft : normalizeLayout(data.layout));

        if (toolbar) { toolbar.remove(); toolbar = null; }
        if (editing) { toolbar = buildToolbar(); host.appendChild(toolbar); }

        const bar = staminaBar(data);
        stamina.classList.toggle('is-visible', bar.visible);
        stamina.classList.toggle('is-low', bar.low === true);
        stamina.firstChild.style.width = bar.fill + '%';
    }

    function onDown(e) {
        if (!draft || e.button !== 0) return;
        const r = root.getBoundingClientRect();
        drag = { dx: e.clientX - r.left, dy: e.clientY - r.top };
        e.preventDefault();
    }
    function onMove(e) {
        if (!drag || !draft) return;
        const f = toFractions(e.clientX - drag.dx, e.clientY - drag.dy, box(), view());
        draft.x = f.x;
        draft.y = f.y;
        place(draft);
    }
    function onUp() { drag = null; }
    function onKey(e) { if (draft && e.key === 'Escape') finish(false); }

    UI.registerScreen('hud', {
        mount: function (el, data, api) {
            host = el;
            post = api.post;
            root = h('div', { class: 'wlh-root' });
            el.appendChild(root);
            stamina = h('div', { class: 'wlh-stamina' }, h('div', { class: 'wlh-stamina__fill' }));
            el.appendChild(stamina);
            el.appendChild(h('style', { text: CSS }));
            root.addEventListener('mousedown', onDown);
            document.addEventListener('mousemove', onMove);
            document.addEventListener('mouseup', onUp);
            document.addEventListener('keydown', onKey);
            render(data);
        },
        update: render,
        unmount: function () {
            document.removeEventListener('mousemove', onMove);
            document.removeEventListener('mouseup', onUp);
            document.removeEventListener('keydown', onKey);
            root = null; host = null; toolbar = null; draft = null; drag = null; stamina = null;
        },
    });

    const CSS = [
        '.wlh-root { position: absolute; right: 1.6vw; bottom: 3vh; display: flex; flex-direction: column; align-items: flex-end; gap: 6px; pointer-events: none;',
        '  --wlh-ok: #7fc75a; --wlh-low: #d6b23c; --wlh-critical: #e0533f; --wlh-cut: #0b0f0a; --wlh-scale: 1; }',
        '.wlh-root.is-editing { pointer-events: auto; cursor: move; outline: 2px dashed rgba(127,199,90,0.85); outline-offset: 8px;',
        '  border-radius: 6px; background: rgba(10,14,9,0.35); }',
        '.wlh-row { display: flex; gap: calc(14px * var(--wlh-scale)); }',
        '.wlh-root.is-vertical .wlh-row { flex-direction: column; }',
        '.wlh-root.is-vertical .wlh-badges { flex-direction: column; align-items: flex-end; }',
        '.wlh-icon { width: calc(36px * var(--wlh-scale)); height: calc(43px * var(--wlh-scale)); color: var(--wlh-ok);',
        '  filter: drop-shadow(0 0 4px rgba(127,199,90,0.55)) drop-shadow(0 1px 1px #000); }',
        '.wlh-icon.is-low { color: var(--wlh-low); filter: drop-shadow(0 0 4px rgba(214,178,60,0.55)) drop-shadow(0 1px 1px #000); }',
        '.wlh-icon.is-critical { color: var(--wlh-critical); filter: drop-shadow(0 0 5px rgba(224,83,63,0.7)) drop-shadow(0 1px 1px #000);',
        '  animation: wlhPulse 1.1s ease-in-out infinite; }',
        '.wlh-svg { width: 100%; height: 100%; overflow: visible; }',
        '.wlh-outline { fill: rgba(10,14,9,0.6); stroke: currentColor; stroke-width: 2.6; stroke-linejoin: round; }',
        '.wlh-liquid { fill: currentColor; opacity: 0.85; }',
        '.wlh-detail { fill: var(--wlh-cut); stroke: var(--wlh-cut); stroke-width: 1.8; stroke-linecap: round; stroke-linejoin: round; }',
        '@keyframes wlhPulse { 50% { opacity: 0.45; } }',
        '.wlh-badges { display: flex; gap: 6px; }',
        '.wlh-badge { font-size: 11px; padding: 2px 8px; border-radius: 10px; background: rgba(10,14,9,0.7); text-shadow: 0 1px 2px #000; }',
        '.wlh-badge--bleeding { color: #ff8a80; border: 1px solid var(--wlh-critical); }',
        '.wlh-badge--infection { color: #b6e39a; border: 1px solid var(--wlh-ok); }',
        '.wlh-info { display: flex; gap: 10px; align-items: baseline; font-size: calc(12px * var(--wlh-scale)); color: #cfe8c0;',
        '  text-shadow: 0 1px 2px #000, 0 0 6px rgba(0,0,0,0.6); white-space: nowrap; }',
        '.wlh-info__id { color: var(--wlh-ok); font-weight: 600; }',
        '.wlh-info__cash { color: #9be27a; font-weight: 600; font-variant-numeric: tabular-nums; }',
        '.wlh-stamina { position: absolute; left: 50%; bottom: 2.2vh; width: 180px; height: 5px; transform: translateX(-50%);',
        '  background: rgba(10,14,9,0.6); border: 1px solid rgba(127,199,90,0.35); border-radius: 3px; overflow: hidden;',
        '  opacity: 0; transition: opacity 0.6s ease 0.8s; pointer-events: none; }',
        '.wlh-stamina.is-visible { opacity: 1; transition: opacity 0.15s ease; }',
        '.wlh-stamina__fill { height: 100%; width: 100%; background: #d8e6c8; box-shadow: 0 0 6px rgba(216,230,200,0.6); transition: width 0.15s linear; }',
        '.wlh-stamina.is-low .wlh-stamina__fill { background: #d6b23c; }',
        '.wlh-tb { position: absolute; top: 3vh; left: 50%; transform: translateX(-50%); display: flex; flex-wrap: wrap; justify-content: center;',
        '  gap: 10px 16px; max-width: 92vw; padding: 10px 14px; background: var(--wl-bg); border: 1px solid var(--wl-border);',
        '  border-radius: var(--wl-radius); box-shadow: 0 10px 30px rgba(0,0,0,0.5); pointer-events: auto; }',
        '.wlh-tb__title { width: 100%; text-align: center; font-size: 13px; color: var(--wl-text-dim); }',
        '.wlh-tb__group { display: flex; align-items: center; gap: 6px; }',
        '.wlh-tb__label { font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--wl-text-dim); margin-right: 2px; }',
    ].join('\n');
})();
