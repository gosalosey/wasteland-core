// wasteland_survival :: html/hud.js
// Survival HUD (runs inside wasteland_ui, no input focus): health (and
// armour) as bars on a riveted plate, and food, drink, temperature, pee and
// poop as round iron dials whose ring drains; tags for bleeding and
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

    // Glyphs in a 24 x 24 box (filled shapes and strokes).
    const GLYPHS = {
        health: { fill: 'M12 20.5s-7.2-4.4-9.4-8.8A5.1 5.1 0 0 1 12 6.4a5.1 5.1 0 0 1 9.4 5.3c-2.2 4.4-9.4 8.8-9.4 8.8z' },
        armor: { fill: 'M12 2.8l7.6 2.9v5.9c0 5-3.3 8.3-7.6 9.6-4.3-1.3-7.6-4.6-7.6-9.6V5.7z' },
        food: { stroke: 'M7 3v7.5a2 2 0 0 0 4 0V3M9 12.5V21M16.5 21V3c-2.2 1-3.5 4-3.5 7.5 0 1.6.9 2.5 2.2 2.5h1.3' },
        drink: { fill: 'M12 2.8s-6.2 7.3-6.2 11.5a6.2 6.2 0 0 0 12.4 0C18.2 10.1 12 2.8 12 2.8z' },
        temp: { stroke: 'M10 13.6V5a2 2 0 0 1 4 0v8.6a4.2 4.2 0 1 1-4 0zM12 9v7.5', dot: true },
        pee: { fill: 'M12 2.8s-6 7-6 11.2a6 6 0 0 0 12 0C18 9.8 12 2.8 12 2.8z', text: 'P' },
        poop: { fill: 'M12 3.5c2 .8 2.2 2.8 1.2 3.8 2.8 0 3.8 1.8 3 3 2.8.2 3.8 2.8 2.8 4.5 2 .9 1.4 4.7-1 4.7H6c-2.4 0-3-3.8-1-4.7-1-1.7 0-4.3 2.8-4.5-.8-1.2.2-3 3-3-1-1-.6-3 1.2-3.8z' },
    };

    function glyph(key) {
        const g = GLYPHS[key] || GLYPHS.health;
        const kids = [];
        if (g.fill) kids.push(svg('path', { d: g.fill, class: 'wlh-g-fill' }));
        if (g.stroke) kids.push(svg('path', { d: g.stroke, class: 'wlh-g-stroke' }));
        if (g.dot) kids.push(svg('circle', { cx: '12', cy: '17.2', r: '2.2', class: 'wlh-g-fill' }));
        if (g.text) {
            const t = svg('text', { x: '12', y: '17.6', 'text-anchor': 'middle', class: 'wlh-g-text' });
            t.textContent = g.text;
            kids.push(t);
        }
        return svg('svg', { viewBox: '0 0 24 24', class: 'wlh-glyph' }, kids);
    }

    // A round iron badge: a ring that drains around the glyph.
    const RING = 2 * Math.PI * 19;
    function badgeEl(icon) {
        const ring = svg('svg', { viewBox: '0 0 48 48', class: 'wlh-ring' }, [
            svg('circle', { cx: '24', cy: '24', r: '19', class: 'wlh-ring__track' }),
            svg('circle', { cx: '24', cy: '24', r: '19', class: 'wlh-ring__fill',
                'stroke-dasharray': RING.toFixed(2), 'stroke-dashoffset': (RING * (1 - icon.fill / 100)).toFixed(2) }),
        ]);
        const el = h('div', { class: 'wlh-dial wlh-dial--' + icon.key + (icon.hot ? ' is-hot' : '') + ' is-' + icon.level,
            attrs: { title: icon.label + ' ' + icon.fill + '%' } },
            ring, h('div', { class: 'wlh-dial__face' }, glyph(icon.key)));
        return el;
    }

    // The long bar on a riveted plate (health, armour under it).
    function barEl(icon, thin) {
        const fill = h('div', { class: 'wlh-bar__fill' });
        fill.style.width = icon.fill + '%';
        return h('div', { class: 'wlh-plate wlh-plate--' + icon.key + ' is-' + icon.level + (thin ? ' is-thin' : '') },
            h('div', { class: 'wlh-plate__icon' }, glyph(icon.key)),
            h('div', { class: 'wlh-bar' }, fill, h('div', { class: 'wlh-bar__grime' })),
            h('span', { class: 'wlh-plate__value', text: String(icon.fill) }));
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
        const list = icons(shown);
        const bars = list.filter((i) => i.key === 'health' || i.key === 'armor');
        const dials = list.filter((i) => i.key !== 'health' && i.key !== 'armor');
        const panel = h('div', { class: 'wlh-panel' });
        bars.forEach((i) => panel.appendChild(barEl(i, i.key === 'armor')));
        if (dials.length) {
            const row = h('div', { class: 'wlh-row' });
            dials.forEach((i) => row.appendChild(badgeEl(i)));
            panel.appendChild(row);
        }
        if (bars.length || dials.length) root.appendChild(panel);
        const b = badges(shown);
        if (b.length) {
            const tags = h('div', { class: 'wlh-badges' });
            b.forEach((x) => tags.appendChild(h('span', { class: 'wlh-badge wlh-badge--' + x.key, text: x.text })));
            root.appendChild(tags);
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
        '  --wlh-ok: #8fbf5f; --wlh-low: #d99a2b; --wlh-critical: #d2261c; --wlh-scale: 1; font-family: var(--wl-font-display); }',
        '.wlh-root.is-editing { pointer-events: auto; cursor: move; outline: 2px dashed rgba(127,199,90,0.85); outline-offset: 8px;',
        '  border-radius: 8px; background: rgba(10,14,9,0.35); }',
        // the panel: everything sized from --wlh-scale
        '.wlh-panel { display: flex; flex-direction: column; align-items: stretch; gap: calc(5px * var(--wlh-scale)); }',
        // plate with a bar (health / armour)
        '.wlh-plate { position: relative; display: flex; align-items: center; gap: calc(7px * var(--wlh-scale));',
        '  width: calc(282px * var(--wlh-scale)); height: calc(30px * var(--wlh-scale)); padding: 0 calc(10px * var(--wlh-scale)) 0 calc(4px * var(--wlh-scale));',
        '  border-radius: calc(6px * var(--wlh-scale)); border: 1px solid #4a3d2e;',
        '  background: radial-gradient(3px 3px at 6px 50%, #8a7a62 40%, transparent 60%), radial-gradient(3px 3px at calc(100% - 6px) 50%, #8a7a62 40%, transparent 60%),',
        '    linear-gradient(180deg, #2c2620, #15120f 70%, #1d1914);',
        '  box-shadow: 0 4px 12px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,230,190,0.08), inset 0 -2px 4px rgba(0,0,0,0.5); }',
        '.wlh-plate.is-thin { height: calc(26px * var(--wlh-scale)); width: calc(282px * var(--wlh-scale)); }',
        '.wlh-plate__icon { flex: none; display: grid; place-items: center; width: calc(24px * var(--wlh-scale)); height: calc(24px * var(--wlh-scale));',
        '  border-radius: calc(5px * var(--wlh-scale)); background: linear-gradient(180deg, #3a3129, #1a1612); border: 1px solid #55463a;',
        '  box-shadow: inset 0 1px 0 rgba(255,230,190,0.1); color: #d2261c; }',
        '.is-thin .wlh-plate__icon { width: calc(21px * var(--wlh-scale)); height: calc(21px * var(--wlh-scale)); }',
        '.wlh-plate--armor .wlh-plate__icon { color: #8fa8b8; }',
        '.wlh-plate__icon .wlh-glyph { width: 72%; height: 72%; filter: drop-shadow(0 0 3px currentColor); }',
        '.wlh-bar { position: relative; flex: 1; height: 58%; border-radius: 3px; overflow: hidden; background: #0a0807;',
        '  box-shadow: inset 0 2px 4px rgba(0,0,0,0.9), 0 1px 0 rgba(255,230,190,0.06); }',
        '.wlh-bar__fill { position: absolute; left: 0; top: 0; bottom: 0; transition: width 0.4s ease;',
        '  background: linear-gradient(180deg, #e2453a 0%, #a3160f 55%, #5e0805 100%); box-shadow: 0 0 10px rgba(210,38,28,0.55); }',
        '.wlh-plate--armor .wlh-bar__fill { background: linear-gradient(180deg, #b9cfdc, #6c8797 55%, #3b4e5a); box-shadow: 0 0 8px rgba(143,168,184,0.45); }',
        // scratches and dirt over the bar
        '.wlh-bar__grime { position: absolute; inset: 0; pointer-events: none;',
        '  background: repeating-linear-gradient(115deg, rgba(0,0,0,0.22) 0 2px, transparent 2px 9px),',
        '    linear-gradient(180deg, rgba(255,255,255,0.18), rgba(255,255,255,0) 45%); }',
        '.wlh-plate__value { flex: none; min-width: calc(24px * var(--wlh-scale)); text-align: right; font-size: calc(13px * var(--wlh-scale)); font-weight: 700;',
        '  color: #e9dfcc; text-shadow: 0 1px 2px #000; font-variant-numeric: tabular-nums; }',
        '.is-thin .wlh-plate__value { font-size: calc(12px * var(--wlh-scale)); }',
        '.wlh-plate.is-critical { border-color: #7a1a12; box-shadow: 0 0 14px rgba(210,38,28,0.45), 0 4px 12px rgba(0,0,0,0.6); }',
        '.wlh-plate--health.is-critical .wlh-bar__fill { animation: wlhPulse 0.9s ease-in-out infinite; }',
        // round iron dials
        '.wlh-row { display: flex; gap: calc(7px * var(--wlh-scale)); justify-content: flex-start; }',
        '.wlh-root.is-vertical .wlh-row { flex-direction: column; align-items: flex-end; }',
        '.wlh-root.is-vertical .wlh-badges { flex-direction: column; align-items: flex-end; }',
        '.wlh-dial { position: relative; width: calc(46px * var(--wlh-scale)); height: calc(46px * var(--wlh-scale)); border-radius: 50%; --c: var(--wlh-ok);',
        '  background: radial-gradient(circle at 35% 30%, #4a4036, #1d1915 62%, #0f0d0b);',
        '  border: 2px solid #4f4133; box-shadow: 0 4px 10px rgba(0,0,0,0.65), inset 0 1px 1px rgba(255,230,190,0.15), inset 0 -3px 6px rgba(0,0,0,0.6); }',
        // four rivets around the rim
        '.wlh-dial::before { content: ""; position: absolute; inset: -1px; border-radius: 50%; pointer-events: none;',
        '  background: radial-gradient(circle at 50% 4%, #a08c70 0 1.6px, transparent 2.2px), radial-gradient(circle at 50% 96%, #a08c70 0 1.6px, transparent 2.2px),',
        '    radial-gradient(circle at 4% 50%, #a08c70 0 1.6px, transparent 2.2px), radial-gradient(circle at 96% 50%, #a08c70 0 1.6px, transparent 2.2px); }',
        '.wlh-ring { position: absolute; inset: 0; width: 100%; height: 100%; transform: rotate(-90deg); }',
        '.wlh-ring__track { fill: none; stroke: rgba(0,0,0,0.55); stroke-width: 4; }',
        '.wlh-ring__fill { fill: none; stroke: var(--c); stroke-width: 4; stroke-linecap: round; filter: drop-shadow(0 0 2px var(--c));',
        '  transition: stroke-dashoffset 0.5s ease, stroke 0.3s; }',
        '.wlh-dial__face { position: absolute; inset: 22%; display: grid; place-items: center; border-radius: 50%; color: var(--c);',
        '  background: radial-gradient(circle at 40% 35%, #2a241e, #0e0c0a); box-shadow: inset 0 1px 3px rgba(0,0,0,0.8); }',
        '.wlh-glyph { width: 78%; height: 78%; overflow: visible; filter: drop-shadow(0 0 3px var(--c, currentColor)); }',
        '.wlh-g-fill { fill: currentColor; }',
        '.wlh-g-stroke { fill: none; stroke: currentColor; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }',
        '.wlh-g-text { fill: #120f0c; font-size: 8px; font-weight: 800; font-family: Arial, sans-serif; }',
        // colours per stat
        '.wlh-dial--food { --c: #e0912f; } .wlh-dial--drink { --c: #3fb5c9; } .wlh-dial--temp { --c: #cfe3ea; } .wlh-dial--temp.is-hot { --c: #ff7a3c; }',
        '.wlh-dial--pee { --c: #d8c63a; } .wlh-dial--poop { --c: #a0703e; }',
        '.wlh-dial.is-low { --c: var(--wlh-low); border-color: #6b4f22; }',
        '.wlh-dial.is-critical { --c: var(--wlh-critical); border-color: #7a1a12; animation: wlhGlow 1s ease-in-out infinite; }',
        '@keyframes wlhPulse { 50% { opacity: 0.55; } }',
        '@keyframes wlhGlow { 50% { box-shadow: 0 0 16px rgba(210,38,28,0.75), 0 4px 10px rgba(0,0,0,0.65), inset 0 -3px 6px rgba(0,0,0,0.6); } }',
        // bleeding / infection tags
        '.wlh-badges { display: flex; gap: 6px; }',
        '.wlh-badge { font-size: 11px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; padding: 3px 9px; border-radius: 4px;',
        '  background: linear-gradient(180deg, #2a231d, #120f0c); text-shadow: 0 1px 2px #000; box-shadow: 0 3px 8px rgba(0,0,0,0.5); }',
        '.wlh-badge--bleeding { color: #ff6b5e; border: 1px solid #8a1d14; }',
        '.wlh-badge--bleeding::before { content: "\\25CF  "; color: #d2261c; }',
        '.wlh-badge--infection { color: #a6e06a; border: 1px solid #4f7a2a; }',
        '.wlh-badge--infection::before { content: "\\2623  "; }',
        '.wlh-info { display: flex; gap: 10px; align-items: baseline; font-size: calc(17px * var(--wlh-scale)); color: #efe6d4; font-weight: 600;',
        '  text-shadow: 0 1px 2px #000, 0 0 6px rgba(0,0,0,0.6); white-space: nowrap; letter-spacing: 0.03em; }',
        '.wlh-info__id { color: #d99a2b; font-weight: 700; }',
        '.wlh-info__cash { color: #9be27a; font-weight: 700; font-variant-numeric: tabular-nums; }',
        '.wlh-stamina { position: absolute; left: 50%; bottom: 2.2vh; width: 200px; height: 6px; transform: translateX(-50%);',
        '  background: #0a0807; border: 1px solid #4a3d2e; border-radius: 3px; overflow: hidden; box-shadow: 0 2px 6px rgba(0,0,0,0.6);',
        '  opacity: 0; transition: opacity 0.6s ease 0.8s; pointer-events: none; }',
        '.wlh-stamina.is-visible { opacity: 1; transition: opacity 0.15s ease; }',
        '.wlh-stamina__fill { height: 100%; width: 100%; background: linear-gradient(180deg, #efe6d2, #a89c84); box-shadow: 0 0 6px rgba(239,230,210,0.4); transition: width 0.15s linear; }',
        '.wlh-stamina.is-low .wlh-stamina__fill { background: linear-gradient(180deg, #f0b44a, #b06e14); }',
        '.wlh-tb { position: absolute; top: 3vh; left: 50%; transform: translateX(-50%); display: flex; flex-wrap: wrap; justify-content: center;',
        '  gap: 10px 16px; max-width: 92vw; padding: 10px 14px; background: var(--wl-bg); border: 1px solid var(--wl-border);',
        '  border-radius: var(--wl-radius); box-shadow: 0 10px 30px rgba(0,0,0,0.5); pointer-events: auto; }',
        '.wlh-tb__title { width: 100%; text-align: center; font-size: 13px; color: var(--wl-text-dim); }',
        '.wlh-tb__group { display: flex; align-items: center; gap: 6px; }',
        '.wlh-tb__label { font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--wl-text-dim); margin-right: 2px; }',
    ].join('\n');
})();
