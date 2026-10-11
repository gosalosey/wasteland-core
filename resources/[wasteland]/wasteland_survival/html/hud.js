// wasteland_survival :: html/hud.js
// Survival HUD (runs inside wasteland_ui, no input focus): four outlined
// icons that drain like a liquid level - health (drop), food (tray), drink
// (bottle), temperature (thermometer) - plus small badges for bleeding and
// infection. Modes:
//   compact    - every icon, always
//   immersive  - an icon only while it matters (low, cold, hot)
//   off        - nothing
// Data: { mode, health, stats = { hunger, thirst, infection, bleeding, temperature, treatment, dead } }

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
        if (typeof s.hunger === 'number') all.push({ key: 'food', label: 'Food', fill: clamp(s.hunger) });
        if (typeof s.thirst === 'number') all.push({ key: 'drink', label: 'Drink', fill: clamp(s.thirst) });
        all.forEach((i) => { i.level = levelOf(i.fill); });
        if (typeof s.temperature === 'number') {
            const t = s.temperature;
            all.push({ key: 'temp', label: 'Temp.', fill: clamp((t - TEMP_MIN) / (TEMP_MAX - TEMP_MIN) * 100), level: tempLevel(t),
                hot: t >= 38.5 });
        }
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

    if (typeof module === 'object' && module.exports) {
        module.exports = { icons: icons, badges: badges };
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

    function render(data) {
        root.innerHTML = '';
        const row = h('div', { class: 'wlh-row' });
        icons(data).forEach((i) => {
            const el = h('div', { class: 'wlh-icon is-' + i.level });
            el.appendChild(iconSvg(i));
            row.appendChild(el);
        });
        root.appendChild(row);
        const b = badges(data);
        if (b.length) {
            const list = h('div', { class: 'wlh-badges' });
            b.forEach((x) => list.appendChild(h('span', { class: 'wlh-badge wlh-badge--' + x.key, text: x.text })));
            root.appendChild(list);
        }
    }

    UI.registerScreen('hud', {
        mount: function (el, data) {
            root = h('div', { class: 'wlh-root' });
            el.appendChild(root);
            el.appendChild(h('style', { text: CSS }));
            render(data);
        },
        update: render,
        unmount: function () { root = null; },
    });

    const CSS = [
        '.wlh-root { position: absolute; right: 1.6vw; bottom: 3vh; display: flex; flex-direction: column; align-items: flex-end; gap: 6px; pointer-events: none;',
        '  --wlh-ok: #7fc75a; --wlh-low: #d6b23c; --wlh-critical: #e0533f; --wlh-cut: #0b0f0a; }',
        '.wlh-row { display: flex; gap: 14px; }',
        '.wlh-icon { width: 36px; height: 43px; color: var(--wlh-ok); filter: drop-shadow(0 0 4px rgba(127,199,90,0.55)) drop-shadow(0 1px 1px #000); }',
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
    ].join('\n');
})();
