// wasteland_inventory :: html/hotbar.js
// The hotbar on screen (bottom middle, /hotbar shows or hides it): five
// slots with the item picture, its count and condition, and the key.
// Data: { slots = [{ key, label, image, count, cond (0-1 or null), color }] }

(function () {
    'use strict';

    // Pure helper (unit-tested): a slot's small text ("x12", "$40", "").
    function countText(slot) {
        if (!slot || !slot.label) return '';
        if (slot.cash) return '$' + Number(slot.count || 0).toLocaleString('en-US');
        return slot.count > 1 ? 'x' + slot.count : '';
    }

    if (typeof module === 'object' && module.exports) { module.exports = { countText: countText }; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let root = null;

    function render(data) {
        root.innerHTML = '';
        (data.slots || []).forEach((s) => {
            const cell = h('div', { class: 'wlhb-slot' + (s.label ? '' : ' is-empty') });
            if (s.color && s.label) cell.style.background = s.color;
            if (s.image) {
                const img = h('img', { class: 'wlhb-img', src: s.image, draggable: false });
                img.addEventListener('error', () => img.remove());
                cell.appendChild(img);
            } else if (s.label) {
                cell.appendChild(h('span', { class: 'wlhb-name', text: s.label }));
            }
            cell.appendChild(h('span', { class: 'wlhb-key', text: String(s.key) }));
            const t = countText(s);
            if (t) cell.appendChild(h('span', { class: 'wlhb-count', text: t }));
            if (typeof s.cond === 'number') {
                const bar = h('span', { class: 'wlhb-cond' + (s.cond <= 0.25 ? ' is-low' : '') });
                bar.style.width = Math.round(s.cond * 100) + '%';
                cell.appendChild(bar);
            }
            root.appendChild(cell);
        });
    }

    UI.registerScreen('hotbarHud', {
        mount: function (el, data) {
            root = h('div', { class: 'wlhb-root' });
            el.appendChild(root);
            el.appendChild(h('style', { text: CSS }));
            render(data);
        },
        update: render,
        unmount: function () { root = null; },
    });

    const CSS = [
        '.wlhb-root { position: absolute; left: 50%; bottom: 3.6vh; transform: translateX(-50%); display: flex; gap: 6px; pointer-events: none; }',
        '.wlhb-slot { position: relative; width: 54px; height: 54px; border-radius: 6px; background: rgba(10,14,9,0.6);',
        '  border: 1px solid rgba(127,199,90,0.35); box-shadow: 0 2px 6px rgba(0,0,0,0.5); overflow: hidden; }',
        '.wlhb-slot.is-empty { background: rgba(10,14,9,0.35); border-style: dashed; }',
        '.wlhb-img { position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); max-width: 44px; max-height: 44px; }',
        '.wlhb-name { position: absolute; inset: 4px; font-size: 9px; line-height: 1.1; color: #e6e6dc; text-shadow: 0 1px 2px #000; }',
        '.wlhb-key { position: absolute; left: 4px; top: 2px; font-size: 11px; font-weight: 700; color: #cfe8c0; text-shadow: 0 1px 2px #000; }',
        '.wlhb-count { position: absolute; right: 4px; bottom: 4px; font-size: 10px; color: #fff; text-shadow: 0 1px 2px #000; }',
        '.wlhb-cond { position: absolute; left: 0; bottom: 0; height: 3px; background: #7fc75a; }',
        '.wlhb-cond.is-low { background: #e0533f; }',
    ].join('\n');
})();
