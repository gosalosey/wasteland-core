// wasteland_crafting :: html/crafting.js
// Crafting screen: every recipe you know, what it needs and what you have.
// Data: { recipes = [{ name, label, seconds, image, result = { label, count },
//         ingredients = [{ name, label, image, need, have }] }], unknown, message, ok }

(function () {
    'use strict';

    // Pure helper (unit-tested with Node): can it be made now?
    function canCraft(recipe) {
        return !!recipe && (recipe.ingredients || []).every((i) => i.have >= i.need);
    }

    if (typeof module === 'object' && module.exports) {
        module.exports = { canCraft: canCraft };
        return;
    }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st;

    function img(src, cls) {
        const el = h('img', { class: cls, draggable: false });
        if (src) el.src = src; else el.style.visibility = 'hidden';
        el.addEventListener('error', () => { el.style.visibility = 'hidden'; });
        return el;
    }

    function render() {
        const d = st.data;
        st.root.innerHTML = '';
        const list = h('div', { class: 'wcr-list' });
        (d.recipes || []).forEach((r) => {
            const ok = canCraft(r);
            const needs = h('div', { class: 'wcr-needs' });
            r.ingredients.forEach((i) => needs.appendChild(h('div', { class: 'wcr-need' + (i.have >= i.need ? '' : ' is-missing') },
                img(i.image, 'wcr-needimg'), h('span', { text: i.need + ' x ' + i.label }), h('span', { class: 'wl-hint', text: '(' + i.have + ')' }))));
            const btn = UI.button('Craft', () => st.api.post('craft', { recipe: r.name }), 'primary');
            btn.disabled = !ok;
            list.appendChild(h('div', { class: 'wcr-row' + (ok ? '' : ' is-locked') },
                img(r.image, 'wcr-img'),
                h('div', { class: 'wcr-what' },
                    h('div', { class: 'wcr-name', text: r.label + (r.result.count > 1 ? ' (x' + r.result.count + ')' : '') }),
                    h('div', { class: 'wl-hint', text: r.seconds + ' s' })),
                needs, btn));
        });
        if (!(d.recipes || []).length) list.appendChild(h('div', { class: 'wl-hint', text: 'You know no recipes yet.' }));
        st.root.appendChild(h('div', { class: 'wcr-panel' },
            h('div', { class: 'wcr-head' }, h('div', { class: 'wl-title', text: 'Crafting' }), UI.button('Close', () => st.api.post('close'))),
            h('div', { class: 'wl-message' + (d.message ? (d.ok ? ' is-ok' : ' is-error') : ''), text: d.message || '' }),
            list,
            h('div', { class: 'wl-hint', text: d.unknown > 0
                ? d.unknown + ' more recipe' + (d.unknown === 1 ? '' : 's') + ' to learn: find blueprints while looting and use them.'
                : 'You know every recipe.' }),
            h('div', { class: 'wl-hint wcr-foot', text: 'K or Esc closes' })));
    }

    function onKey(e) { if (e.key === 'Escape' || e.key === 'k' || e.key === 'K') st.api.post('close'); }

    UI.registerScreen('crafting', {
        mount: function (el, data, api) {
            st = { root: h('div', { class: 'wcr-root' }), data: data, api: api };
            el.appendChild(st.root);
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            render();
        },
        update: function (data) { st.data = data; render(); },
        unmount: function () { document.removeEventListener('keydown', onKey); st = null; },
    });

    const CSS = [
        '.wcr-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }',
        '.wcr-panel { width: min(820px, 94vw); max-height: 86vh; display: flex; flex-direction: column; gap: 10px; padding: 18px 20px;',
        '  background: var(--wl-bg); border: 1px solid var(--wl-border); border-radius: var(--wl-radius); box-shadow: 0 20px 60px rgba(0,0,0,0.6); }',
        '.wcr-head { display: flex; align-items: center; } .wcr-head .wl-title { flex: 1; }',
        '.wcr-list { overflow-y: auto; max-height: 62vh; display: flex; flex-direction: column; gap: 6px; padding-right: 4px; }',
        '.wcr-row { display: grid; grid-template-columns: 52px 170px 1fr auto; align-items: center; gap: 12px; padding: 6px 8px;',
        '  background: var(--wl-bg-sunken); border-radius: 4px; }',
        '.wcr-row.is-locked { opacity: 0.75; }',
        '.wcr-img { width: 48px; height: 48px; object-fit: contain; }',
        '.wcr-name { font-size: 14px; }',
        '.wcr-needs { display: flex; flex-wrap: wrap; gap: 4px 12px; font-size: 12px; }',
        '.wcr-need { display: flex; align-items: center; gap: 4px; color: #b6e39a; }',
        '.wcr-need.is-missing { color: #ff8a80; }',
        '.wcr-needimg { width: 20px; height: 20px; object-fit: contain; }',
        '.wcr-foot { text-align: right; }',
    ].join('\n');
})();
