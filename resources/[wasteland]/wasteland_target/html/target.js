// wasteland_target :: html/target.js
// The eye in the middle of the screen while Left Alt is held, and the
// options for what the player looks at (click one with the mouse, or scroll and press E).
// Data: { active, selected, cursor, options = [{ label, icon }] }

(function () {
    'use strict';

    // Pure helper (unit-tested with Node): rows to draw.
    function rows(data) {
        const list = (data && data.options) || [];
        const sel = Math.min(Math.max(1, data && data.selected || 1), Math.max(1, list.length));
        return list.map((o, i) => ({ label: String(o.label), icon: o.icon ? String(o.icon) : '•', selected: i + 1 === sel }));
    }

    if (typeof module === 'object' && module.exports) {
        module.exports = { rows: rows };
        return;
    }

    const UI = window.WastelandUI;
    const h = UI.h;
    let root, api = null;
    let last = null;   // the data shown, for E and the wheel while the cursor is up
    // While the cursor is up the game gets no keys: letting go of Alt (or Esc)
    // closes, E uses the highlighted option, the wheel moves the highlight.
    function onKeyUp(e) { if (api && (e.key === 'Alt' || e.key === 'Escape')) api.post('close'); }
    function onKeyDown(e) {
        if (!api || !last || !last.cursor) return;
        if (e.key === 'e' || e.key === 'E') api.post('select', { index: last.selected || 1 });
        if (e.key === 'Alt') e.preventDefault();
    }
    function onWheel(e) {
        if (!api || !last || !last.cursor) return;
        const n = (last.options || []).length;
        if (n < 2) return;
        const cur = last.selected || 1;
        api.post('hover', { index: e.deltaY > 0 ? cur % n + 1 : (cur + n - 2) % n + 1 });
    }

    function render(data) {
        last = data;
        root.innerHTML = '';
        const list = rows(data);
        const eye = h('div', { class: 'wlt-eye' + (list.length ? ' has-target' : '') }, h('div', { class: 'wlt-eye__pupil' }));
        root.appendChild(eye);
        if (!list.length) return;
        const box = h('div', { class: 'wlt-options' + (data.cursor ? ' is-pointing' : '') });
        list.forEach((r, i) => box.appendChild(h('div', { class: 'wlt-option' + (r.selected ? ' is-selected' : ''),
            onclick: () => api && api.post('select', { index: i + 1 }),
            onmouseenter: () => api && !r.selected && api.post('hover', { index: i + 1 }) },
            h('span', { class: 'wlt-option__icon', text: r.icon }), h('span', { text: r.label }))));
        if (list.length > 1) box.appendChild(h('div', { class: 'wlt-hint', text: 'Click an option · or scroll and E' }));
        else box.appendChild(h('div', { class: 'wlt-hint', text: 'Click or E' }));
        root.appendChild(box);
    }

    UI.registerScreen('target', {
        mount: function (el, data, screenApi) {
            api = screenApi;
            document.addEventListener('keyup', onKeyUp);
            document.addEventListener('keydown', onKeyDown);
            document.addEventListener('wheel', onWheel);
            root = h('div', { class: 'wlt-root' });
            el.appendChild(root);
            el.appendChild(h('style', { text: CSS }));
            render(data);
        },
        update: render,
        unmount: function () {
            document.removeEventListener('keyup', onKeyUp); document.removeEventListener('keydown', onKeyDown);
            document.removeEventListener('wheel', onWheel); root = null; api = null; last = null;
        },
    });

    const CSS = [
        '.wlt-root { position: absolute; inset: 0; pointer-events: none; }',
        '.wlt-eye { position: absolute; left: 50%; top: 50%; width: 18px; height: 11px; transform: translate(-50%, -50%);',
        '  border: 2px solid rgba(230,230,220,0.85); border-radius: 50% / 60%; box-shadow: 0 0 4px rgba(0,0,0,0.8);',
        '  display: flex; align-items: center; justify-content: center; transition: border-color 0.12s, transform 0.12s; }',
        '.wlt-eye__pupil { width: 5px; height: 5px; border-radius: 50%; background: rgba(230,230,220,0.85); }',
        '.wlt-eye.has-target { border-color: #7fc75a; transform: translate(-50%, -50%) scale(1.25); }',
        '.wlt-eye.has-target .wlt-eye__pupil { background: #7fc75a; }',
        '.wlt-options { position: absolute; left: calc(50% + 22px); top: 50%; transform: translateY(-14px); display: flex;',
        '  flex-direction: column; gap: 3px; min-width: 150px; }',
        '.wlt-option { display: flex; align-items: center; gap: 8px; padding: 5px 10px; font-size: 13px; color: #e6e6dc;',
        '  background: rgba(10,14,9,0.78); border: 1px solid rgba(255,255,255,0.08); border-radius: 4px; text-shadow: 0 1px 2px #000; }',
        '.wlt-options.is-pointing { pointer-events: auto; }',
        '.wlt-options.is-pointing .wlt-option { cursor: pointer; }',
        '.wlt-option.is-selected { border-color: #7fc75a; color: #fff; background: rgba(40,60,30,0.85); }',
        '.wlt-option__icon { width: 14px; text-align: center; color: #7fc75a; }',
        '.wlt-hint { font-size: 10px; color: rgba(230,230,220,0.6); padding-left: 2px; text-shadow: 0 1px 2px #000; }',
    ].join('\n');
})();
