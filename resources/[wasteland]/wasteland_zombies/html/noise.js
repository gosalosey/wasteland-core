// wasteland_zombies :: html/noise.js
// Noise meter: how far zombies can hear you right now (client/noise.lua
// measures it with the zombies' own rule). A row of bars like a sound
// level, a word for how loud, the reach in feet and what makes the noise,
// and how many zombies are inside that reach. /hud edit mode: drag it and
// resize it (mouse wheel or - / +); every change is posted ('layout').
// Data: { radius (m), source, firing, count, safe, layout = { x, y, scale }, editing }

(function () {
    'use strict';

    // Pure helpers (unit-tested with Node)
    const BARS = 14;
    const FULL = 120; // metres at which every bar is lit

    function levelOf(r) {
        if (r <= 6) return { key: 'quiet', word: 'QUIET' };
        if (r <= 12) return { key: 'low', word: 'LOW' };
        if (r <= 25) return { key: 'noticeable', word: 'NOTICEABLE' };
        if (r <= 50) return { key: 'loud', word: 'LOUD' };
        return { key: 'deafening', word: 'DEAFENING' };
    }

    // Lit bars: square-root scale so the quiet end still moves visibly.
    function litBars(r) {
        const f = Math.max(0, Math.min(1, Math.sqrt(Math.max(0, Number(r) || 0) / FULL)));
        return Math.max(1, Math.round(f * BARS));
    }

    function feet(r) { return Math.round((Number(r) || 0) * 3.28084 / 5) * 5; }

    function view(d) {
        const r = Math.max(0, Number(d.radius) || 0);
        const lvl = levelOf(r);
        const count = Math.max(0, Math.floor(Number(d.count) || 0));
        return {
            level: lvl.key, word: lvl.word, lit: litBars(r),
            reach: 'heard within ~' + feet(r) + ' ft',
            source: d.source || '',
            earshot: count === 0 ? 'none in earshot' : count === 1 ? '1 in earshot' : count + ' in earshot',
            danger: count > 0, firing: d.firing === true, safe: d.safe === true,
        };
    }

    const MIN_SCALE = 0.6, MAX_SCALE = 1.8;
    function clampScale(s) {
        const n = Number(s);
        if (!isFinite(n)) return 1;
        return Math.round(Math.max(MIN_SCALE, Math.min(MAX_SCALE, n)) * 100) / 100;
    }
    function unit(v) { return typeof v === 'number' && isFinite(v) ? Math.max(0, Math.min(1, v)) : null; }
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
        module.exports = { levelOf: levelOf, litBars: litBars, feet: feet, view: view, BARS: BARS,
            clampScale: clampScale, normalizeLayout: normalizeLayout, toPixels: toPixels, toFractions: toFractions };
        return;
    }

    const UI = window.WastelandUI;
    const h = UI.h;
    let frame = null, toolbar = null, api = null, els = null;
    let draft = null, drag = null, editing = false;

    function screenSize() { return { w: window.innerWidth, h: window.innerHeight }; }
    function box() { const r = frame.getBoundingClientRect(); return { w: r.width, h: r.height }; }

    function place(layout) {
        const l = normalizeLayout(layout);
        frame.style.setProperty('--wnm-scale', String(l.scale));
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
            toolbar.querySelector('.wnm-size').textContent = Math.round(l.scale * 100) + '%';
        }
    }

    function changed() {
        place(draft);
        if (api) api.post('layout', { x: draft.x, y: draft.y, scale: draft.scale });
    }

    function resize(delta) {
        if (!draft) return;
        const b = frame.getBoundingClientRect();
        draft.scale = clampScale(draft.scale + delta);
        if (draft.x !== null) {
            frame.style.setProperty('--wnm-scale', String(draft.scale));
            const a = box();
            const f = toFractions(b.left + b.width / 2 - a.w / 2, b.top + b.height / 2 - a.h / 2, a, screenSize());
            draft.x = f.x; draft.y = f.y;
        }
        changed();
    }

    function buildToolbar() {
        const btn = (text, fn, title) => h('button', { class: 'wnm-btn', text: text, attrs: { title: title || '' }, onclick: fn });
        return h('div', { class: 'wnm-toolbar' },
            h('span', { class: 'wnm-tool-label', text: 'Noise meter' }),
            btn('−', () => resize(-0.1), 'Smaller'), h('span', { class: 'wnm-size', text: '100%' }), btn('+', () => resize(0.1), 'Bigger'),
            btn('Reset', () => { draft = { x: null, y: null, scale: 1 }; changed(); }, 'Back to its normal spot and size'));
    }

    function build() {
        const bars = [];
        const meter = h('div', { class: 'wnm-bars' });
        for (let i = 0; i < BARS; i++) {
            const b = h('span', { class: 'wnm-bar' });
            b.style.height = (34 + i * (66 / (BARS - 1))) + '%';
            b.style.setProperty('--i', String(i));
            meter.appendChild(b);
            bars.push(b);
        }
        els = {
            bars: bars,
            word: h('span', { class: 'wnm-word' }),
            safe: h('span', { class: 'wnm-safe', text: 'SAFE ZONE' }),
            reach: h('span', { class: 'wnm-reach' }),
            source: h('span', { class: 'wnm-source' }),
            earshot: h('span', { class: 'wnm-earshot' }),
        };
        const icon = h('span', { class: 'wnm-icon', innerHTML:
            '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round">' +
            '<path d="M4 9v6h4l5 4V5L8 9z" fill="currentColor" stroke="none"/><path d="M16 9a4 4 0 0 1 0 6"/><path d="M19 6a8 8 0 0 1 0 12"/></svg>' });
        return h('div', { class: 'wnm-plate' },
            h('div', { class: 'wnm-head' }, icon, h('span', { class: 'wnm-title', text: 'NOISE' }), els.safe, els.word),
            meter,
            h('div', { class: 'wnm-foot' }, els.reach, h('span', { class: 'wnm-dot', text: '·' }), els.source),
            els.earshot);
    }

    function render(d) {
        const v = view(d);
        frame.className = frame.className.replace(/\bis-(quiet|low|noticeable|loud|deafening)\b/g, '').trim();
        frame.classList.add('is-' + v.level);
        frame.classList.toggle('is-firing', v.firing);
        frame.classList.toggle('is-safe', v.safe);
        els.bars.forEach((b, i) => b.classList.toggle('is-on', i < v.lit));
        els.word.textContent = v.word;
        els.reach.textContent = v.reach;
        els.source.textContent = v.source;
        els.earshot.textContent = v.earshot;
        els.earshot.classList.toggle('is-danger', v.danger);

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

    UI.registerScreen('noiseMeter', {
        mount: function (el, data, screenApi) {
            api = screenApi;
            frame = h('div', { class: 'wnm-root is-default' }, build());
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
            frame = null; toolbar = null; els = null; draft = null; drag = null; editing = false; api = null;
        },
    });

    // Colours: bone-green when quiet, through rust to blood red.
    const CSS = [
        '.wnm-root { position: absolute; pointer-events: none; --wnm-scale: 1; transform-origin: top left; transform: scale(var(--wnm-scale));',
        '  --c: #9fb98a; --glow: rgba(159,185,138,0.45); font-family: var(--wl-font-display); }',
        '.wnm-root.is-default { left: 1.2vw; bottom: 27vh; transform-origin: bottom left; }',
        '.wnm-root.is-low { --c: #c7c27a; --glow: rgba(199,194,122,0.45); }',
        '.wnm-root.is-noticeable { --c: #d9932b; --glow: rgba(217,147,43,0.5); }',
        '.wnm-root.is-loud { --c: #d4552a; --glow: rgba(212,85,42,0.55); }',
        '.wnm-root.is-deafening { --c: #c4231b; --glow: rgba(196,35,27,0.7); }',
        '.wnm-root.is-editing { pointer-events: auto; cursor: move; outline: 2px dashed rgba(127,199,90,0.85); outline-offset: 6px; border-radius: 10px; }',
        '.wnm-plate { position: relative; width: 210px; padding: 9px 12px 9px; border-radius: 10px; overflow: hidden;',
        '  background: radial-gradient(120% 90% at 0% 0%, rgba(60,48,34,0.55), rgba(0,0,0,0) 60%),',
        '    linear-gradient(180deg, rgba(22,20,17,0.86), rgba(9,9,8,0.9));',
        '  border: 1px solid rgba(214,186,140,0.16); box-shadow: 0 8px 22px rgba(0,0,0,0.55), inset 0 1px 0 rgba(255,240,210,0.06);',
        '  transition: border-color 0.25s, box-shadow 0.25s; }',
        // grime: faint scratches over the plate
        '.wnm-plate::after { content: ""; position: absolute; inset: 0; pointer-events: none; opacity: 0.5;',
        '  background: repeating-linear-gradient(115deg, rgba(255,255,255,0.018) 0 1px, transparent 1px 7px),',
        '    repeating-linear-gradient(25deg, rgba(0,0,0,0.12) 0 1px, transparent 1px 11px); }',
        '.wnm-plate::before { content: ""; position: absolute; left: 0; top: 0; bottom: 0; width: 3px; background: var(--c);',
        '  box-shadow: 0 0 10px var(--glow); transition: background 0.25s; }',
        '.is-loud .wnm-plate, .is-deafening .wnm-plate { border-color: rgba(196,35,27,0.45); box-shadow: 0 8px 22px rgba(0,0,0,0.55), 0 0 18px rgba(196,35,27,0.25); }',
        '.wnm-head { position: relative; display: flex; align-items: center; gap: 6px; margin-bottom: 7px; }',
        '.wnm-icon { display: inline-flex; color: var(--c); filter: drop-shadow(0 0 4px var(--glow)); transition: color 0.25s; }',
        '.wnm-title { font-size: 11px; font-weight: 700; letter-spacing: 0.24em; color: #a59c8b; }',
        '.wnm-word { margin-left: auto; font-size: 13px; font-weight: 700; letter-spacing: 0.12em; color: var(--c);',
        '  text-shadow: 0 0 10px var(--glow), 0 1px 2px #000; transition: color 0.25s; }',
        '.wnm-safe { display: none; font-size: 9px; font-weight: 700; letter-spacing: 0.14em; color: #7fc75a; border: 1px solid rgba(127,199,90,0.55);',
        '  border-radius: 4px; padding: 1px 5px; background: rgba(127,199,90,0.1); white-space: nowrap; }',
        '.is-safe .wnm-safe { display: inline-block; }',
        '.wnm-bars { position: relative; display: flex; align-items: flex-end; gap: 3px; height: 30px; padding: 0 1px; }',
        '.wnm-bar { flex: 1; border-radius: 2px; background: rgba(214,186,140,0.09); box-shadow: inset 0 1px 2px rgba(0,0,0,0.6);',
        '  transition: background 0.18s, box-shadow 0.18s; }',
        '.wnm-bar.is-on { background: linear-gradient(180deg, var(--c), rgba(0,0,0,0.25) 160%); box-shadow: 0 0 7px var(--glow); }',
        '.wnm-foot { position: relative; display: flex; align-items: baseline; gap: 5px; margin-top: 7px; font-family: var(--wl-font);',
        '  font-size: 11px; color: #cfc6b4; white-space: nowrap; }',
        '.wnm-dot { color: #6d665a; } .wnm-source { color: #a59c8b; overflow: hidden; text-overflow: ellipsis; }',
        '.wnm-earshot { position: relative; display: block; margin-top: 3px; font-family: var(--wl-font); font-size: 11px; color: #7d766a; }',
        '.wnm-earshot.is-danger { color: #e0533f; font-weight: 600; text-shadow: 0 0 8px rgba(224,83,63,0.45); }',
        '.wnm-earshot.is-danger::before { content: "☣ "; }',
        // a gunshot: the plate jolts and flashes red
        '@keyframes wnm-jolt { 0% { transform: translate(0,0); } 20% { transform: translate(-2px,1px); } 40% { transform: translate(2px,-1px); }',
        '  60% { transform: translate(-1px,0); } 100% { transform: translate(0,0); } }',
        '@keyframes wnm-flash { 0% { box-shadow: 0 0 0 1px rgba(196,35,27,0.9), 0 0 28px rgba(196,35,27,0.7); } 100% { box-shadow: 0 8px 22px rgba(0,0,0,0.55), 0 0 18px rgba(196,35,27,0.25); } }',
        '.is-firing .wnm-plate { animation: wnm-jolt 0.25s ease-out, wnm-flash 1.2s ease-out; }',
        '@keyframes wnm-pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.55; } }',
        '.is-deafening .wnm-word { animation: wnm-pulse 0.9s ease-in-out infinite; }',
        '.wnm-toolbar { position: absolute; transform: translateX(-50%); display: flex; align-items: center; gap: 6px; pointer-events: auto;',
        '  background: rgba(10,14,9,0.88); border: 1px solid rgba(127,199,90,0.45); border-radius: 6px; padding: 4px 8px; white-space: nowrap;',
        '  font-size: 12px; color: #e6e6dc; }',
        '.wnm-tool-label { color: #7fc75a; letter-spacing: 0.08em; text-transform: uppercase; font-size: 11px; margin-right: 4px; }',
        '.wnm-size { min-width: 38px; text-align: center; font-variant-numeric: tabular-nums; }',
        '.wnm-btn { background: rgba(127,199,90,0.15); color: #e6e6dc; border: 1px solid rgba(127,199,90,0.5); border-radius: 4px;',
        '  padding: 2px 9px; font-size: 13px; cursor: pointer; } .wnm-btn:hover { background: rgba(127,199,90,0.35); }',
    ].join('\n');
})();
