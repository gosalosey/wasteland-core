// wasteland_vehicles :: html/hud.js
// Vehicle HUD (only in a vehicle): speed, fuel gauge, engine and body
// condition, lock, and why it will not run. Bottom middle unless the player
// moved it: /hud (edit mode of the main HUD) also lets you drag this one and
// resize it (mouse wheel or the - / + buttons). Every change is posted
// ('layout'); the client keeps it when the main HUD is saved.
// Data: { speed (m/s), metric, fuel, tank, engine, body (0-1000), locked, hasLock, warning,
//         layout = { x, y, scale }, editing }

(function () {
    'use strict';

    // Pure helpers (unit-tested with Node)
    function speedText(mps, metric) {
        const v = Math.max(0, Number(mps) || 0) * (metric ? 3.6 : 2.236936);
        return { value: String(Math.round(v)), unit: metric ? 'km/h' : 'mph' };
    }

    function level(fraction) {
        if (fraction <= 0.15) return 'critical';
        if (fraction <= 0.35) return 'low';
        return 'ok';
    }

    function view(d) {
        const tank = d.tank || 50;
        const fuel = Math.max(0, Math.min(tank, d.fuel || 0));
        const engine = Math.max(0, Math.min(1000, d.engine || 0)) / 1000;
        const body = Math.max(0, Math.min(1000, d.body || 0)) / 1000;
        return {
            speed: speedText(d.speed, d.metric !== false),
            fuel: { fill: Math.round(fuel / tank * 100), text: Math.round(fuel) + ' / ' + tank + ' L', level: level(fuel / tank) },
            engine: { text: Math.round(engine * 100) + '%', level: level(engine) },
            body: { text: Math.round(body * 100) + '%', level: level(body) },
            lock: d.hasLock ? (d.locked ? 'Locked' : 'Unlocked') : null,
            warning: d.warning || null,
        };
    }

    const MIN_SCALE = 0.6, MAX_SCALE = 1.8;
    function clampScale(s) {
        const n = Number(s);
        if (!isFinite(n)) return 1;
        return Math.round(Math.max(MIN_SCALE, Math.min(MAX_SCALE, n)) * 100) / 100;
    }

    function unit(v) { return typeof v === 'number' && isFinite(v) ? Math.max(0, Math.min(1, v)) : null; }

    // { x, y } share of the free screen space (null = default bottom middle), scale.
    function normalizeLayout(l) {
        l = l || {};
        let x = unit(l.x), y = unit(l.y);
        if (x === null || y === null) { x = null; y = null; }
        return { x: x, y: y, scale: clampScale(l.scale === undefined || l.scale === null ? 1 : l.scale) };
    }

    function toPixels(layout, box, scr) {
        const l = normalizeLayout(layout);
        if (l.x === null) return null;
        return { left: Math.round(l.x * Math.max(0, scr.w - box.w)), top: Math.round(l.y * Math.max(0, scr.h - box.h)) };
    }

    function toFractions(left, top, box, scr) {
        const fw = scr.w - box.w, fh = scr.h - box.h;
        const r = (v) => Math.round(Math.max(0, Math.min(1, v)) * 10000) / 10000;
        return { x: fw > 0 ? r(left / fw) : 0, y: fh > 0 ? r(top / fh) : 0 };
    }

    if (typeof module === 'object' && module.exports) {
        module.exports = { speedText: speedText, level: level, view: view, clampScale: clampScale, normalizeLayout: normalizeLayout,
            toPixels: toPixels, toFractions: toFractions };
        return;
    }

    const UI = window.WastelandUI;
    const h = UI.h;
    let frame = null, content = null, toolbar = null, api = null;
    let draft = null, drag = null, editing = false;

    function screenSize() { return { w: window.innerWidth, h: window.innerHeight }; }
    function box() { const r = frame.getBoundingClientRect(); return { w: r.width, h: r.height }; }

    function place(layout) {
        const l = normalizeLayout(layout);
        frame.style.setProperty('--wvh-scale', String(l.scale));
        if (l.x === null) {
            frame.classList.add('is-default');
            frame.style.left = ''; frame.style.top = '';
        } else {
            frame.classList.remove('is-default');
            const px = toPixels(l, box(), screenSize());
            frame.style.left = px.left + 'px';
            frame.style.top = px.top + 'px';
        }
        if (toolbar) {
            const r = frame.getBoundingClientRect();
            toolbar.style.left = Math.round(r.left + r.width / 2) + 'px';
            toolbar.style.top = Math.round(r.top > 50 ? r.top - 42 : r.bottom + 10) + 'px';
            toolbar.querySelector('.wvh-size').textContent = Math.round(l.scale * 100) + '%';
        }
    }

    function changed() {
        place(draft);
        if (api) api.post('layout', { x: draft.x, y: draft.y, scale: draft.scale });
    }

    function resize(delta) {
        if (!draft) return;
        // Keep the centre where it is while growing or shrinking.
        const before = frame.getBoundingClientRect();
        draft.scale = clampScale(draft.scale + delta);
        if (draft.x !== null) {
            frame.style.setProperty('--wvh-scale', String(draft.scale));
            const after = box();
            const f = toFractions(before.left + before.width / 2 - after.w / 2, before.top + before.height / 2 - after.h / 2, after, screenSize());
            draft.x = f.x; draft.y = f.y;
        }
        changed();
    }

    function buildToolbar() {
        const btn = (text, fn, title) => h('button', { class: 'wvh-btn', text: text, attrs: { title: title || '' }, onclick: fn });
        return h('div', { class: 'wvh-toolbar' },
            h('span', { class: 'wvh-tool-label', text: 'Vehicle HUD' }),
            btn('−', () => resize(-0.1), 'Smaller'), h('span', { class: 'wvh-size', text: '100%' }), btn('+', () => resize(0.1), 'Bigger'),
            btn('Reset', () => { draft = { x: null, y: null, scale: 1 }; changed(); }, 'Back to the bottom middle, normal size'));
    }

    function render(d) {
        const v = view(d);
        content.innerHTML = '';
        const fuelBar = h('div', { class: 'wvh-bar' }, h('div', { class: 'wvh-bar__fill is-' + v.fuel.level }));
        fuelBar.firstChild.style.width = v.fuel.fill + '%';
        content.appendChild(h('div', { class: 'wvh-speed' },
            h('span', { class: 'wvh-speed__value', text: v.speed.value }), h('span', { class: 'wvh-speed__unit', text: v.speed.unit })));
        content.appendChild(h('div', { class: 'wvh-row' },
            h('span', { class: 'wvh-label', text: 'FUEL' }), fuelBar, h('span', { class: 'wvh-val is-' + v.fuel.level, text: v.fuel.text })));
        const stats = h('div', { class: 'wvh-row wvh-stats' },
            h('span', { class: 'wvh-label', text: 'ENGINE' }), h('span', { class: 'wvh-val is-' + v.engine.level, text: v.engine.text }),
            h('span', { class: 'wvh-label', text: 'BODY' }), h('span', { class: 'wvh-val is-' + v.body.level, text: v.body.text }));
        if (v.lock) stats.appendChild(h('span', { class: 'wvh-lock', text: v.lock === 'Locked' ? '🔒 Locked' : '🔓 Unlocked' }));
        content.appendChild(stats);
        if (v.warning) content.appendChild(h('div', { class: 'wvh-warning', text: v.warning }));

        const nowEditing = d.editing === true;
        if (nowEditing && !editing) {
            draft = normalizeLayout(d.layout);
            toolbar = buildToolbar();
            frame.parentNode.appendChild(toolbar);
        } else if (!nowEditing && editing) {
            draft = null; drag = null;
            if (toolbar) toolbar.remove();
            toolbar = null;
        }
        editing = nowEditing;
        frame.classList.toggle('is-editing', editing);
        if (!drag) place(editing ? draft : d.layout);
    }

    function onDown(e) {
        if (!editing || e.button !== 0) return;
        const r = frame.getBoundingClientRect();
        if (draft.x === null) {
            // Leave the bottom-middle default: keep it where it is on screen.
            const f = toFractions(r.left, r.top, box(), screenSize());
            draft.x = f.x; draft.y = f.y;
            place(draft);
        }
        drag = { dx: e.clientX - r.left, dy: e.clientY - r.top };
        e.preventDefault();
    }
    function onMove(e) {
        if (!drag || !draft) return;
        const f = toFractions(e.clientX - drag.dx, e.clientY - drag.dy, box(), screenSize());
        draft.x = f.x; draft.y = f.y;
        place(draft);
    }
    function onUp() { if (drag) { drag = null; changed(); } }
    function onWheel(e) { if (editing) { e.preventDefault(); resize(e.deltaY < 0 ? 0.05 : -0.05); } }

    UI.registerScreen('vehHud', {
        mount: function (el, data, screenApi) {
            api = screenApi;
            content = h('div', { class: 'wvh-content' });
            frame = h('div', { class: 'wvh-root is-default' }, content);
            frame.addEventListener('mousedown', onDown);
            frame.addEventListener('wheel', onWheel, { passive: false });
            document.addEventListener('mousemove', onMove);
            document.addEventListener('mouseup', onUp);
            el.appendChild(frame);
            el.appendChild(h('style', { text: CSS }));
            render(data);
        },
        update: render,
        unmount: function () {
            document.removeEventListener('mousemove', onMove);
            document.removeEventListener('mouseup', onUp);
            if (toolbar) toolbar.remove();
            frame = null; content = null; toolbar = null; draft = null; drag = null; editing = false; api = null;
        },
    });

    const CSS = [
        '.wvh-root { position: absolute; pointer-events: none; --wvh-scale: 1; transform-origin: top left;',
        '  transform: scale(var(--wvh-scale)); text-shadow: 0 1px 2px #000, 0 0 6px rgba(0,0,0,0.6);',
        '  --ok: #7fc75a; --low: #d6b23c; --critical: #e0533f; }',
        '.wvh-root.is-default { left: 50%; bottom: 4.5vh; transform-origin: bottom center; transform: translateX(-50%) scale(var(--wvh-scale)); }',
        '.wvh-root.is-editing { pointer-events: auto; cursor: move; outline: 2px dashed rgba(127,199,90,0.85); outline-offset: 6px;',
        '  background: rgba(10,14,9,0.35); border-radius: 6px; }',
        '.wvh-content { min-width: 230px; display: flex; flex-direction: column; align-items: center; gap: 4px; padding: 2px 4px; }',
        '.wvh-speed { display: flex; align-items: baseline; gap: 5px; }',
        '.wvh-speed__value { font-size: 34px; font-weight: 700; color: #e8f2de; font-variant-numeric: tabular-nums; line-height: 1; }',
        '.wvh-speed__unit { font-size: 12px; color: #b9c8ad; letter-spacing: 0.06em; }',
        '.wvh-row { display: flex; align-items: center; gap: 8px; font-size: 11px; }',
        '.wvh-label { color: #9fb092; letter-spacing: 0.08em; }',
        '.wvh-bar { width: 120px; height: 6px; background: rgba(10,14,9,0.65); border: 1px solid rgba(127,199,90,0.35); border-radius: 3px; overflow: hidden; }',
        '.wvh-bar__fill { height: 100%; background: var(--ok); box-shadow: 0 0 6px rgba(127,199,90,0.6); transition: width 0.3s linear; }',
        '.wvh-bar__fill.is-low { background: var(--low); } .wvh-bar__fill.is-critical { background: var(--critical); }',
        '.wvh-val { font-variant-numeric: tabular-nums; color: var(--ok); font-weight: 600; }',
        '.wvh-val.is-low { color: var(--low); } .wvh-val.is-critical { color: var(--critical); }',
        '.wvh-stats .wvh-label:not(:first-child) { margin-left: 6px; }',
        '.wvh-lock { margin-left: 8px; color: #d8d8cc; }',
        '.wvh-warning { margin-top: 2px; font-size: 12px; color: #ff9a8a; background: rgba(10,14,9,0.6); padding: 2px 8px; border-radius: 10px;',
        '  border: 1px solid rgba(224,83,63,0.6); }',
        '.wvh-toolbar { position: absolute; transform: translateX(-50%); display: flex; align-items: center; gap: 6px; pointer-events: auto;',
        '  background: rgba(10,14,9,0.88); border: 1px solid rgba(127,199,90,0.45); border-radius: 6px; padding: 4px 8px; white-space: nowrap;',
        '  font-size: 12px; color: #e6e6dc; }',
        '.wvh-tool-label { color: #7fc75a; letter-spacing: 0.08em; text-transform: uppercase; font-size: 11px; margin-right: 4px; }',
        '.wvh-size { min-width: 38px; text-align: center; font-variant-numeric: tabular-nums; }',
        '.wvh-btn { background: rgba(127,199,90,0.15); color: #e6e6dc; border: 1px solid rgba(127,199,90,0.5); border-radius: 4px;',
        '  padding: 2px 9px; font-size: 13px; cursor: pointer; } .wvh-btn:hover { background: rgba(127,199,90,0.35); }',
    ].join('\n');
})();
