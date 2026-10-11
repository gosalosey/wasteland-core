// wasteland_vehicles :: html/hud.js
// Vehicle HUD (bottom middle, only in a vehicle): speed, fuel gauge,
// engine and body condition, lock, and why it will not run.
// Data: { speed (m/s), metric, fuel, tank, engine, body (0-1000), locked, hasLock, warning }

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

    if (typeof module === 'object' && module.exports) {
        module.exports = { speedText: speedText, level: level, view: view };
        return;
    }

    const UI = window.WastelandUI;
    const h = UI.h;
    let root;

    function render(d) {
        const v = view(d);
        root.innerHTML = '';
        const fuelBar = h('div', { class: 'wvh-bar' }, h('div', { class: 'wvh-bar__fill is-' + v.fuel.level }));
        fuelBar.firstChild.style.width = v.fuel.fill + '%';
        root.appendChild(h('div', { class: 'wvh-speed' },
            h('span', { class: 'wvh-speed__value', text: v.speed.value }), h('span', { class: 'wvh-speed__unit', text: v.speed.unit })));
        root.appendChild(h('div', { class: 'wvh-row' },
            h('span', { class: 'wvh-label', text: 'FUEL' }), fuelBar, h('span', { class: 'wvh-val is-' + v.fuel.level, text: v.fuel.text })));
        const stats = h('div', { class: 'wvh-row wvh-stats' },
            h('span', { class: 'wvh-label', text: 'ENGINE' }), h('span', { class: 'wvh-val is-' + v.engine.level, text: v.engine.text }),
            h('span', { class: 'wvh-label', text: 'BODY' }), h('span', { class: 'wvh-val is-' + v.body.level, text: v.body.text }));
        if (v.lock) stats.appendChild(h('span', { class: 'wvh-lock', text: v.lock === 'Locked' ? '🔒 Locked' : '🔓 Unlocked' }));
        root.appendChild(stats);
        if (v.warning) root.appendChild(h('div', { class: 'wvh-warning', text: v.warning }));
    }

    UI.registerScreen('vehHud', {
        mount: function (el, data) {
            root = h('div', { class: 'wvh-root' });
            el.appendChild(root);
            el.appendChild(h('style', { text: CSS }));
            render(data);
        },
        update: render,
        unmount: function () { root = null; },
    });

    const CSS = [
        '.wvh-root { position: absolute; left: 50%; bottom: 4.5vh; transform: translateX(-50%); min-width: 230px; pointer-events: none;',
        '  display: flex; flex-direction: column; align-items: center; gap: 4px; text-shadow: 0 1px 2px #000, 0 0 6px rgba(0,0,0,0.6);',
        '  --ok: #7fc75a; --low: #d6b23c; --critical: #e0533f; }',
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
    ].join('\n');
})();
