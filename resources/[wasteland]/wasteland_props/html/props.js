// wasteland_props :: html/props.js
// Prop placer panel (admins): type any prop model or pick a preset, then
// place it in the world; nearby placed props can be moved, deleted or
// visited. Esc closes.
// Data: { presets = [{ group, label, model }], nearby = [{ id, model, dist }], total }

(function () {
    'use strict';

    // Pure helper (unit-tested): presets by group, filtered by a search.
    function grouped(presets, query) {
        const q = String(query || '').trim().toLowerCase();
        const out = [];
        const byName = {};
        (presets || []).forEach((p) => {
            if (q && p.label.toLowerCase().indexOf(q) < 0 && p.model.toLowerCase().indexOf(q) < 0 && p.group.toLowerCase().indexOf(q) < 0) return;
            if (!byName[p.group]) { byName[p.group] = { group: p.group, items: [] }; out.push(byName[p.group]); }
            byName[p.group].items.push(p);
        });
        return out;
    }

    if (typeof module === 'object' && module.exports) { module.exports = { grouped: grouped }; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let api = null, data = null, root = null, query = '', input = null;

    function place(model) { if (model) api.post('place', { model: model }); }

    function render() {
        const body = root.querySelector('.wpp-body');
        body.innerHTML = '';
        // presets
        const groups = grouped(data.presets, query);
        const presetBox = h('div', { class: 'wpp-presets' });
        if (!groups.length) presetBox.appendChild(h('div', { class: 'wl-hint', text: query ? 'No preset matches. Press Place to try "' + query + '" as a model name.' : 'No presets (props.lua presets).' }));
        groups.forEach((g) => {
            presetBox.appendChild(h('div', { class: 'wl-section-title', text: g.group }));
            const grid = h('div', { class: 'wpp-grid' });
            g.items.forEach((p) => grid.appendChild(h('button', { class: 'wpp-chip', attrs: { title: p.model }, onclick: () => place(p.model) },
                h('span', { class: 'wpp-chip__label', text: p.label }), h('span', { class: 'wpp-chip__model', text: p.model }))));
            presetBox.appendChild(grid);
        });
        // nearby
        const near = h('div', { class: 'wpp-near' },
            h('div', { class: 'wl-section-title', text: 'Placed nearby (' + (data.nearby || []).length + ' of ' + (data.total || 0) + ')' }));
        if (!(data.nearby || []).length) near.appendChild(h('div', { class: 'wl-hint', text: 'Nothing placed within 150 m.' }));
        (data.nearby || []).forEach((p) => {
            near.appendChild(h('div', { class: 'wpp-row' },
                h('span', { class: 'wpp-row__id', text: '#' + p.id }),
                h('span', { class: 'wpp-row__model', text: p.model }),
                h('span', { class: 'wpp-row__dist', text: p.dist + ' m' }),
                UI.button('Move', () => api.post('edit', { id: p.id })),
                UI.button('Go', () => api.post('goto', { id: p.id })),
                UI.button('Delete', () => api.post('delete', { id: p.id }), 'danger')));
        });
        body.appendChild(presetBox);
        body.appendChild(near);
    }

    function onKey(e) { if (e.key === 'Escape') api.post('close', {}); }

    UI.registerScreen('propPlacer', {
        mount: function (el, d, screenApi) {
            api = screenApi; data = d || {};
            input = h('input', { class: 'wl-input', attrs: { placeholder: 'Search presets or type any prop model, e.g. prop_barrel_02a', spellcheck: 'false' } });
            input.addEventListener('input', () => { query = input.value; render(); });
            input.addEventListener('keydown', (e) => { if (e.key === 'Enter') place(input.value.trim()); });
            root = h('div', { class: 'wl-panel wpp-panel' },
                h('div', { class: 'wpp-head' },
                    h('div', {}, h('h1', { class: 'wl-title', text: 'Prop Placer' }),
                        h('p', { class: 'wl-subtitle', text: 'Place props anywhere. Everything is saved and stays after restarts.' })),
                    UI.button('✕', () => api.post('close', {}), 'icon')),
                h('div', { class: 'wpp-search' }, input, UI.button('Place', () => place(input.value.trim()), 'primary')),
                h('div', { class: 'wpp-body' }));
            el.appendChild(root);
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            render();
            setTimeout(() => input && input.focus(), 50);
        },
        update: function (d) { data = d || {}; render(); },
        unmount: function () { document.removeEventListener('keydown', onKey); api = null; root = null; input = null; },
    });

    const CSS = [
        '.wpp-panel { position: absolute; right: 2.5vw; top: 50%; transform: translateY(-50%); width: 560px; max-height: 86vh; display: flex; flex-direction: column; }',
        '.wpp-head { display: flex; justify-content: space-between; align-items: flex-start; gap: 12px; }',
        '.wpp-head .wl-subtitle { margin-bottom: 12px; font-size: 13px; }',
        '.wpp-search { display: flex; gap: 8px; margin-bottom: 6px; }',
        '.wpp-body { overflow-y: auto; padding-right: 4px; }',
        '.wpp-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; }',
        '.wpp-chip { font: inherit; text-align: left; display: flex; flex-direction: column; gap: 1px; padding: 7px 9px; cursor: pointer; color: var(--wl-text);',
        '  border-radius: 8px; border: 1px solid rgba(214,186,140,0.12); background: linear-gradient(180deg, rgba(255,240,210,0.035), rgba(0,0,0,0.18)), rgba(10,10,9,0.55);',
        '  transition: border-color 0.14s, background 0.14s; }',
        '.wpp-chip:hover { border-color: var(--wl-accent); background: linear-gradient(180deg, rgba(217,130,43,0.18), rgba(0,0,0,0.2)), rgba(10,10,9,0.55); }',
        '.wpp-chip__label { font-size: 13px; font-weight: 600; }',
        '.wpp-chip__model { font-size: 10px; color: var(--wl-text-dim); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }',
        '.wpp-row { display: grid; grid-template-columns: 48px 1fr 52px auto auto auto; gap: 6px; align-items: center; padding: 5px 8px; margin-bottom: 5px;',
        '  border-radius: 8px; border: 1px solid rgba(214,186,140,0.10); background: rgba(10,10,9,0.5); font-size: 13px; }',
        '.wpp-row .wl-btn { padding: 4px 10px; font-size: 12px; }',
        '.wpp-row__id { color: var(--wl-accent-strong); font-weight: 700; }',
        '.wpp-row__model { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }',
        '.wpp-row__dist { color: var(--wl-text-dim); text-align: right; font-variant-numeric: tabular-nums; }',
    ].join('\n');
})();
