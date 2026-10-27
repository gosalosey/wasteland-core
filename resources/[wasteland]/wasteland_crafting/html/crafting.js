// wasteland_crafting :: html/crafting.js
// Crafting screen: every recipe you know, what it needs and what you have.
// Data: { maxTracked, recipes = [{ name, tracked, label, seconds, image, result = { label, count },
//         ingredients = [{ name, label, image, need, have }], station? = { label, here } }], unknown, message, ok }

(function () {
    'use strict';

    // Pure helper (unit-tested with Node): can it be made now?
    function canCraft(recipe) {
        if (!recipe || (recipe.station && !recipe.station.here)) return false;
        return (recipe.ingredients || []).every((i) => i.have >= i.need);
    }

    // How many can be made with what is carried (at most 50 in one go).
    function maxCraft(recipe) {
        if (!recipe || !(recipe.ingredients || []).length || (recipe.station && !recipe.station.here)) return 0;
        let n = 50;
        recipe.ingredients.forEach((i) => { n = Math.min(n, Math.floor(i.have / Math.max(1, i.need))); });
        return Math.max(0, n);
    }

    if (typeof module === 'object' && module.exports) {
        module.exports = { canCraft: canCraft, maxCraft: maxCraft };
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
            // How many: - / number / + / Max (kept per recipe while the screen is open).
            const max = maxCraft(r);
            st.qty = st.qty || {};
            const qty = Math.max(1, Math.min(Math.max(1, max), st.qty[r.name] || 1));
            st.qty[r.name] = qty;
            const btn = UI.button(qty > 1 ? 'Craft x' + qty : 'Craft', () => st.api.post('craft', { recipe: r.name, count: st.qty[r.name] || 1 }), 'primary');
            btn.disabled = !ok;
            const field = h('input', { class: 'wl-input wcr-qty', attrs: { type: 'number', min: '1', max: String(Math.max(1, max)) } });
            field.value = String(qty);
            const set = (n) => { st.qty[r.name] = Math.max(1, Math.min(Math.max(1, max), Math.floor(Number(n) || 1))); render(); };
            field.addEventListener('change', () => set(field.value));
            const amount = h('div', { class: 'wcr-amount' },
                UI.button('−', () => set(qty - 1)), field, UI.button('+', () => set(qty + 1)), UI.button('Max', () => set(max)),
                h('span', { class: 'wl-hint', text: max > 0 ? 'can make ' + max : '' }));
            if (!ok) [...amount.querySelectorAll('button, input')].forEach((b) => { b.disabled = true; });
            list.appendChild(h('div', { class: 'wcr-row' + (ok ? '' : ' is-locked') },
                img(r.image, 'wcr-img'),
                h('div', { class: 'wcr-what' },
                    h('div', { class: 'wcr-name', text: r.label + (r.result.count > 1 ? ' (x' + r.result.count + ')' : '') }),
                    h('div', { class: 'wl-hint', text: r.seconds + ' s' + (r.station ? ' · at a ' + r.station.label + (r.station.here ? '' : ' (not here)') : '') })),
                needs, h('div', { class: 'wcr-do' }, amount, h('div', { class: 'wcr-btns' },
                    h('button', { class: 'wl-btn wcr-track' + (r.tracked ? ' is-on' : ''), text: r.tracked ? '★ Tracked' : '☆ Track',
                        attrs: { title: 'Show what this needs on screen (up to ' + (d.maxTracked || 3) + ')' },
                        onclick: () => st.api.post('track', { recipe: r.name }) }), btn))));
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
        '.wcr-do { display: flex; flex-direction: column; align-items: flex-end; gap: 6px; }',
        '.wcr-amount { display: flex; align-items: center; gap: 4px; }',
        '.wcr-amount .wl-btn { padding: 3px 9px; min-width: 0; }',
        '.wcr-qty { width: 52px; text-align: center; padding: 4px; }',
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
        '.wcr-btns { display: flex; gap: 6px; }',
        '.wcr-track.is-on { color: #e8c25a; border-color: rgba(232,194,90,0.6); }',
        // ---- polish ----
        '.wcr-panel { position: relative; border-radius: 12px; border-color: rgba(214,186,140,0.14); background: linear-gradient(180deg, rgba(255,240,210,0.035), rgba(255,240,210,0) 120px), var(--wl-bg); box-shadow: var(--wl-shadow), inset 0 1px 0 rgba(255,240,210,0.06); }',
        '.wcr-panel::before { content: ""; position: absolute; top: -1px; left: 24px; right: 24px; height: 2px; border-radius: 2px; background: linear-gradient(90deg, transparent, var(--wl-accent) 25%, var(--wl-accent-strong) 50%, var(--wl-accent) 75%, transparent); opacity: 0.75; pointer-events: none; }',
        '.wcr-row { border-radius: 8px; background: linear-gradient(180deg, rgba(255,240,210,0.035), rgba(0,0,0,0.18)), rgba(10,10,9,0.55); border: 1px solid rgba(214,186,140,0.10); transition: border-color 0.14s; }',
        '.wcr-row:hover { border-color: rgba(217,130,43,0.35); }',
    ].join('\n');
})();
