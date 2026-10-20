// wasteland_moonshine :: html/meter.js
// The Zombie Blind meter (no input): how much moonshine masks your smell,
// and whether zombies can smell you. Full = safe until it drains below the line.
// Data: { blind (0 - 100), masked, unmaskBelow, drunk }

(function () {
    'use strict';

    function status(d) {
        if (d.masked) return { key: 'safe', text: "SAFE: zombies can't smell you" };
        return { key: 'danger', text: 'NOT SAFE: zombies can smell you' };
    }

    if (typeof module === 'object' && module.exports) { module.exports = { status: status }; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let els = null;

    function render(d) {
        const s = status(d);
        els.root.className = 'wmb-root is-' + s.key;
        els.fill.style.width = Math.max(0, Math.min(100, d.blind)) + '%';
        els.line.style.left = (d.unmaskBelow || 40) + '%';
        els.line.style.display = d.masked ? '' : 'none';
        els.status.textContent = s.text;
        els.pct.textContent = Math.round(d.blind) + '%';
        els.hint.textContent = d.masked ? 'Until the meter drops below the line' : (d.blind > 0 ? 'Fill the meter to hide from them' : '');
    }

    UI.registerScreen('moonshineMeter', {
        mount: function (el, data) {
            els = {};
            els.fill = h('div', { class: 'wmb-fill' });
            els.line = h('div', { class: 'wmb-line' });
            els.status = h('div', { class: 'wmb-status' });
            els.pct = h('span', { class: 'wmb-pct' });
            els.hint = h('div', { class: 'wmb-hint' });
            els.root = h('div', { class: 'wmb-root' },
                h('div', { class: 'wmb-head' }, h('span', { class: 'wmb-title', text: '☣ ZOMBIE BLIND' }), els.pct),
                h('div', { class: 'wmb-track' }, els.fill, els.line),
                els.status, els.hint);
            el.appendChild(els.root);
            el.appendChild(h('style', { text: CSS }));
            render(data);
        },
        update: render,
        unmount: function () { els = null; },
    });

    const CSS = [
        '.wmb-root { position: absolute; left: 50%; top: 2.5vh; transform: translateX(-50%); width: 300px; padding: 10px 14px; border-radius: 10px; pointer-events: none;',
        '  background: linear-gradient(180deg, rgba(22,20,17,0.88), rgba(9,9,8,0.9)); border: 1px solid rgba(214,186,140,0.16);',
        '  box-shadow: 0 8px 22px rgba(0,0,0,0.55); font-family: var(--wl-font-display); --c: #d2261c; }',
        '.wmb-root.is-safe { --c: #6fcf5a; border-color: rgba(111,207,90,0.45); box-shadow: 0 0 18px rgba(111,207,90,0.2), 0 8px 22px rgba(0,0,0,0.55); }',
        '.wmb-head { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 6px; }',
        '.wmb-title { font-size: 12px; font-weight: 700; letter-spacing: 0.18em; color: #c9bfa9; }',
        '.wmb-pct { font-size: 13px; font-weight: 700; color: var(--c); }',
        '.wmb-track { position: relative; height: 10px; border-radius: 5px; background: #0a0807; overflow: hidden; box-shadow: inset 0 1px 3px rgba(0,0,0,0.8); }',
        '.wmb-fill { height: 100%; background: linear-gradient(90deg, #8a6d2b, var(--c)); box-shadow: 0 0 10px var(--c); transition: width 0.6s linear; }',
        '.wmb-line { position: absolute; top: -2px; bottom: -2px; width: 2px; background: #f0e6d0; opacity: 0.8; }',
        '.wmb-status { margin-top: 7px; font-size: 13px; font-weight: 700; letter-spacing: 0.05em; color: var(--c); text-shadow: 0 0 8px rgba(0,0,0,0.8); }',
        '@keyframes wmbPulse { 50% { opacity: 0.55; } }',
        '.wmb-root.is-danger .wmb-status { animation: wmbPulse 1.2s ease-in-out infinite; }',
        '.wmb-hint { font-size: 11px; color: #9d958a; margin-top: 2px; font-family: var(--wl-font); }',
    ].join('\n');
})();
