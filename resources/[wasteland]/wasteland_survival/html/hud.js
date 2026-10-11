// wasteland_survival :: html/hud.js
// Survival HUD (runs inside wasteland_ui, no input focus). Modes:
//   compact    - every bar, always
//   immersive  - a bar only while it matters (low, bleeding, infected, cold...)
//   off        - nothing
// Data: { mode, health, stamina, stats = { hunger, thirst, infection, bleeding, temperature, treatment, dead } }

(function () {
    'use strict';

    // ------------------------------------------------------------------
    // Pure helpers (unit-tested with Node)
    // ------------------------------------------------------------------

    const LOW = 35; // immersive mode shows a bar at or below this

    // Bars to show: [{ key, label, value 0..100, tone }]
    function bars(data) {
        const s = data.stats || {};
        if (data.mode === 'off' || s.dead) return [];
        const all = [
            { key: 'health', label: 'Health', value: data.health, tone: 'health' },
            { key: 'stamina', label: 'Stamina', value: data.stamina, tone: 'stamina' },
            { key: 'hunger', label: 'Food', value: s.hunger, tone: 'hunger' },
            { key: 'thirst', label: 'Water', value: s.thirst, tone: 'thirst' },
        ];
        if (s.infection > 0) all.push({ key: 'infection', label: s.treatment ? 'Infection (treated)' : 'Infection', value: s.infection, tone: 'infection', inverse: true });
        return all.filter((b) => typeof b.value === 'number').filter((b) => {
            if (data.mode !== 'immersive') return b.key !== 'stamina' || b.value < 100;
            return b.inverse ? b.value > 0 : b.value <= LOW;
        }).map((b) => Object.assign({}, b, { value: Math.max(0, Math.min(100, Math.round(b.value))) }));
    }

    // Status chips: bleeding level and body temperature when it matters.
    function chips(data) {
        const s = data.stats || {};
        if (data.mode === 'off' || s.dead) return [];
        const out = [];
        if (s.bleeding > 0) out.push({ key: 'bleeding', text: ['', 'Bleeding', 'Bleeding heavily', 'Bleeding severely'][s.bleeding], tone: 'danger' });
        if (typeof s.temperature === 'number') {
            const t = Math.round(s.temperature * 10) / 10;
            const tone = t <= 35.5 ? 'cold' : t >= 38.5 ? 'hot' : 'normal';
            if (data.mode !== 'immersive' || tone !== 'normal') out.push({ key: 'temperature', text: t.toFixed(1) + ' °C', tone: tone });
        }
        return out;
    }

    if (typeof module === 'object' && module.exports) {
        module.exports = { bars: bars, chips: chips };
        return;
    }

    // ------------------------------------------------------------------
    // Screen
    // ------------------------------------------------------------------

    const UI = window.WastelandUI;
    const h = UI.h;
    let root;

    function render(data) {
        root.innerHTML = '';
        bars(data).forEach((b) => {
            const fill = h('div', { class: 'wlh-fill wlh-' + b.tone });
            fill.style.width = b.value + '%';
            root.appendChild(h('div', { class: 'wlh-bar' + (!b.inverse && b.value <= 20 ? ' is-low' : '') },
                h('span', { class: 'wlh-label', text: b.label }), h('div', { class: 'wlh-track' }, fill)));
        });
        const c = chips(data);
        if (c.length) {
            const row = h('div', { class: 'wlh-chips' });
            c.forEach((x) => row.appendChild(h('span', { class: 'wlh-chip wlh-chip--' + x.tone, text: x.text })));
            root.appendChild(row);
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
        '.wlh-root { position: absolute; left: 1.6vw; bottom: 26vh; width: 210px; display: flex; flex-direction: column; gap: 5px; pointer-events: none; }',
        '.wlh-bar { display: grid; grid-template-columns: 64px 1fr; align-items: center; gap: 6px; }',
        '.wlh-label { font-size: 11px; color: var(--wl-text-dim); text-shadow: 0 1px 2px #000; text-transform: uppercase; letter-spacing: 0.06em; }',
        '.wlh-track { height: 7px; background: rgba(0,0,0,0.55); border: 1px solid rgba(255,255,255,0.08); border-radius: 4px; overflow: hidden; }',
        '.wlh-fill { height: 100%; transition: width 0.4s ease; }',
        '.wlh-health { background: #c4453a; } .wlh-stamina { background: #c9c1a8; } .wlh-hunger { background: #d9822b; }',
        '.wlh-thirst { background: #4f9ac4; } .wlh-infection { background: #7fae5a; }',
        '.wlh-bar.is-low .wlh-track { animation: wlhPulse 1s ease-in-out infinite; }',
        '@keyframes wlhPulse { 50% { border-color: #ff6b5e; } }',
        '.wlh-chips { display: flex; gap: 6px; margin-top: 2px; }',
        '.wlh-chip { font-size: 11px; padding: 2px 7px; border-radius: 10px; background: rgba(0,0,0,0.6); text-shadow: 0 1px 2px #000; }',
        '.wlh-chip--danger { color: #ff8a80; border: 1px solid #c4453a; } .wlh-chip--cold { color: #9ad3ff; border: 1px solid #4f9ac4; }',
        '.wlh-chip--hot { color: #ffc27a; border: 1px solid #d9822b; } .wlh-chip--normal { color: var(--wl-text-dim); }',
    ].join('\n');
})();
