// wasteland_admin :: html/lootpick.js
// Small window opened from the admin target option on a prop: make that
// prop (every copy of its model) a loot container of a chosen category, change
// it, or remove it. The server checks the admin ACE for every request.
// Data: { hash, name, containers = [{ name, label, table }], known = { [hash]: { type, added, name } } }
// Posts: add { container, propName }, remove, close. Update: { result = { ok, message } }

(function () {
    'use strict';

    if (typeof module === 'object' && module.exports) { module.exports = {}; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st = null;

    function onKey(e) { if (st && e.key === 'Escape') st.api.post('close'); }

    UI.registerScreen('adminLootPick', {
        mount: function (el, data, api) {
            st = { api: api };
            const key = String(data.hash);
            const known = (data.known || {})[key];
            const name = (known && known.name) || data.name || '';
            st.message = h('div', { class: 'wl-message' });
            const body = [];
            body.push(h('div', { class: 'wlp2-model', text: (name || 'Prop (name unknown)') + ' · model ' + key }));
            if (known && !known.added) {
                body.push(h('div', { class: 'wl-hint', text: 'Already searchable from loot.lua. Change it there.' }));
            } else {
                const pick = h('select', { class: 'wl-input' });
                (data.containers || []).forEach((c) => {
                    const o = h('option', { text: c.label + ' (' + c.table + ' loot)', attrs: { value: c.name } });
                    if (known && known.type === c.name) o.selected = true;
                    pick.appendChild(o);
                });
                const prop = h('input', { class: 'wl-input', attrs: { placeholder: 'Name players see (optional), e.g. Old barrel', maxlength: '40' } });
                prop.value = name;
                body.push(h('label', { class: 'wlp2-field' }, h('span', { text: 'Loot category' }), pick));
                body.push(h('label', { class: 'wlp2-field' }, h('span', { text: 'Name players see' }), prop));
                body.push(h('div', { class: 'wlp2-row' },
                    UI.button(known ? 'Change' : 'Make lootable', () => api.post('add', {
                        container: pick.value, propName: prop.value.replace(/[^A-Za-z0-9 _.'()-]/g, '').replace(/\s+/g, ' ').trim().slice(0, 40) }), 'primary'),
                    known ? UI.button('Remove', () => api.post('remove', {})) : null,
                    UI.button('Close', () => api.post('close'))));
                body.push(h('div', { class: 'wl-hint', text: 'Every copy of this prop on the map becomes searchable. New categories: admin panel (F10), Loot tab.' }));
            }
            if (known && !known.added) body.push(h('div', { class: 'wlp2-row' }, UI.button('Close', () => api.post('close'))));
            el.appendChild(h('div', { class: 'wlp2-root' },
                h('div', { class: 'wl-panel wlp2-panel' }, h('h2', { class: 'wl-title', text: 'Loot container' }), ...body, st.message)));
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
        },
        update: function (data) {
            if (data.result) {
                st.message.textContent = data.result.message || '';
                st.message.className = 'wl-message is-' + (data.result.ok ? 'ok' : 'error');
            }
        },
        unmount: function () { document.removeEventListener('keydown', onKey); st = null; },
    });

    const CSS = [
        '.wlp2-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }',
        '.wlp2-panel { width: min(460px, 92vw); display: flex; flex-direction: column; gap: 10px; }',
        '.wlp2-model { font-family: Consolas, monospace; font-size: 13px; color: var(--wl-accent); }',
        '.wlp2-field { display: flex; flex-direction: column; gap: 4px; font-size: 12px; color: var(--wl-text-dim); }',
        '.wlp2-row { display: flex; gap: 8px; flex-wrap: wrap; }',
    ].join('\n');
})();
