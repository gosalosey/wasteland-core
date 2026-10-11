// wasteland_emotes :: html/emotes.js
// The emote menu (F4): categories, a search box, click an emote to play it.
// Data: { emotes = [{ name, label, cat }], categories = [...], playing = name | null }
// Posts: play { name }, stop, close

(function () {
    'use strict';

    // Pure helper (unit-tested): emotes matching a search and a category ('' = all).
    function filterEmotes(list, query, cat) {
        const q = String(query || '').trim().toLowerCase();
        return list.filter((e) => (!cat || e.cat === cat) &&
            (!q || e.name.includes(q) || e.label.toLowerCase().includes(q)));
    }

    if (typeof module === 'object' && module.exports) { module.exports = { filterEmotes: filterEmotes }; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st = null;

    function renderList() {
        st.list.innerHTML = '';
        const shown = filterEmotes(st.emotes, st.query, st.cat);
        if (!shown.length) { st.list.appendChild(h('div', { class: 'wl-hint', text: 'No emote matches.' })); return; }
        shown.forEach((e) => {
            st.list.appendChild(h('button', { class: 'wlem-item' + (st.playing === e.name ? ' is-playing' : ''),
                onclick: () => st.api.post('play', { name: e.name }) },
                h('span', { class: 'wlem-label', text: e.label }), h('span', { class: 'wlem-cmd', text: '/e ' + e.name })));
        });
    }

    function renderCats() {
        st.cats.innerHTML = '';
        [''].concat(st.categories).forEach((c) => {
            st.cats.appendChild(h('button', { class: 'wlem-cat' + (st.cat === c ? ' is-active' : ''), text: c || 'All',
                onclick: () => { st.cat = c; renderCats(); renderList(); } }));
        });
    }

    function onKey(e) { if (st && (e.key === 'Escape' || e.key === 'F4')) st.api.post('close'); }

    UI.registerScreen('emoteMenu', {
        mount: function (el, data, api) {
            st = { api: api, emotes: data.emotes || [], categories: data.categories || [], playing: data.playing, query: '', cat: '' };
            const search = h('input', { class: 'wl-input wlem-search', attrs: { placeholder: 'Search emotes…', maxlength: '30' } });
            search.addEventListener('input', () => { st.query = search.value; renderList(); });
            st.cats = h('div', { class: 'wlem-cats' });
            st.list = h('div', { class: 'wlem-list' });
            el.appendChild(h('div', { class: 'wlem-root' },
                h('div', { class: 'wl-panel wlem-panel' },
                    h('div', { class: 'wlem-head' }, h('h1', { class: 'wl-title', text: 'Emotes' }),
                        UI.button('Stop emote', () => api.post('stop'), st.playing ? 'primary' : undefined),
                        UI.button('Close', () => api.post('close'))),
                    search, st.cats, st.list,
                    h('div', { class: 'wl-hint', text: 'Click to play · /e name · /e c stops · X hands up · F4 or Esc closes' }))));
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            renderCats();
            renderList();
            setTimeout(() => search.focus(), 50);
        },
        unmount: function () { document.removeEventListener('keydown', onKey); st = null; },
    });

    const CSS = [
        '.wlem-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: flex-end; padding-right: 4vw; pointer-events: none; }',
        '.wlem-panel { pointer-events: auto; width: min(430px, 92vw); max-height: 80vh; display: flex; flex-direction: column; gap: 8px; }',
        '.wlem-head { display: flex; align-items: center; gap: 8px; } .wlem-head .wl-title { flex: 1; }',
        '.wlem-search { width: 100%; box-sizing: border-box; }',
        '.wlem-cats { display: flex; flex-wrap: wrap; gap: 4px; }',
        '.wlem-cat { background: var(--wl-bg-sunken); color: var(--wl-text-dim); border: 1px solid var(--wl-border); border-radius: 12px;',
        '  padding: 3px 10px; font-size: 12px; cursor: pointer; }',
        '.wlem-cat.is-active { color: #fff; border-color: var(--wl-accent); background: rgba(127,199,90,0.18); }',
        '.wlem-list { overflow-y: auto; display: grid; grid-template-columns: 1fr 1fr; gap: 4px; padding-right: 4px; }',
        '.wlem-item { display: flex; flex-direction: column; align-items: flex-start; gap: 1px; text-align: left; cursor: pointer;',
        '  background: var(--wl-bg-sunken); border: 1px solid var(--wl-border); border-radius: 5px; padding: 6px 9px; color: var(--wl-text); }',
        '.wlem-item:hover { border-color: var(--wl-accent); }',
        '.wlem-item.is-playing { border-color: var(--wl-accent); background: rgba(127,199,90,0.15); }',
        '.wlem-label { font-size: 13px; } .wlem-cmd { font-size: 10px; color: var(--wl-text-dim); font-family: Consolas, monospace; }',
    ].join('\n');
})();
