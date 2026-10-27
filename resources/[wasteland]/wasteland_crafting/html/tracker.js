// wasteland_crafting :: html/tracker.js
// The crafting tracker in the top-right corner: each tracked recipe, the
// items it needs and how many you have (green once you have enough).
// Data: { recipes = [{ label, ready, ingredients = [{ label, need, have }] }] }

(function () {
    'use strict';
    if (typeof module === 'object' && module.exports) { module.exports = {}; return; }
    const UI = window.WastelandUI;
    const h = UI.h;
    let root;

    function render(d) {
        root.innerHTML = '';
        (d && d.recipes || []).forEach((r) => {
            const box = h('div', { class: 'wct-recipe' + (r.ready ? ' is-ready' : '') },
                h('div', { class: 'wct-title', text: r.label + (r.ready ? '  ✓ ready' : '') }));
            (r.ingredients || []).forEach((i) => box.appendChild(h('div', { class: 'wct-item' + (i.have >= i.need ? ' is-ok' : '') },
                h('span', { text: i.label }), h('span', { class: 'wct-count', text: Math.min(i.have, 9999) + ' / ' + i.need }))));
            root.appendChild(box);
        });
    }

    UI.registerScreen('craftTracker', {
        mount: function (el, data) {
            root = h('div', { class: 'wct-root' });
            el.appendChild(root);
            el.appendChild(h('style', { text: CSS }));
            render(data);
        },
        update: function (data) { render(data); },
        unmount: function () { root = null; },
    });

    const CSS = [
        '.wct-root { position: absolute; top: 22%; right: 18px; width: 230px; display: flex; flex-direction: column; gap: 8px; pointer-events: none; }',
        '.wct-recipe { background: rgba(10,12,9,0.72); border: 1px solid rgba(214,186,140,0.18); border-left: 3px solid #d9822b;',
        '  border-radius: 6px; padding: 6px 9px; color: #e6e1d2; font-size: 12px; text-shadow: 0 1px 2px #000; }',
        '.wct-recipe.is-ready { border-left-color: #7fc75a; }',
        '.wct-title { font-weight: 700; font-size: 13px; margin-bottom: 3px; color: #f0d9a8; }',
        '.wct-recipe.is-ready .wct-title { color: #b6e39a; }',
        '.wct-item { display: flex; justify-content: space-between; gap: 8px; color: #ff9d8f; }',
        '.wct-item.is-ok { color: #b6e39a; }',
        '.wct-count { font-variant-numeric: tabular-nums; }',
    ].join('
');
})();
