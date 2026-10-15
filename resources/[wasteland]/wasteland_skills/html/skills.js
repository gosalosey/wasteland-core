// wasteland_skills :: html/skills.js
// The skills screen: every skill with its level, an XP bar and what the
// level gives you now.
(function () {
    'use strict';
    const DESCRIBE = {
        searchTime: (v) => pct(v) + ' faster searching',
        extraLoot: (v) => pct(v) + ' chance of an extra find',
        craftTime: (v) => pct(v) + ' faster crafting',
        saveChance: (v) => pct(v) + ' chance to save a material',
        heal: (v) => pct(v) + ' more healing',
        extraMeat: (v) => pct(v) + ' more meat',
        stamina: (v) => pct(v) + ' more stamina',
        meleeDamage: (v) => pct(v) + ' melee damage',
        weaponWear: (v) => pct(v) + ' slower weapon wear',
    };
    function pct(v) { return '+' + Math.round(v * 100) + '%'; }

    function describe(bonus) {
        const parts = Object.keys(bonus || {}).filter((k) => bonus[k] > 0).map((k) => (DESCRIBE[k] ? DESCRIBE[k](bonus[k]) : k));
        return parts.length ? parts.join(' · ') : 'No bonus yet - level up to get one';
    }

    // Rows to show (exported for tests).
    function rows(view) {
        return ((view && view.skills) || []).map((s) => {
            const top = s.needed === 0;
            return {
                label: s.label, level: s.level, top: top,
                fill: top ? 100 : Math.max(0, Math.min(100, Math.round((s.into / s.needed) * 100))),
                progress: top ? 'Max level' : Math.floor(s.into) + ' / ' + s.needed + ' XP',
                text: describe(s.bonus),
            };
        });
    }

    if (typeof module === 'object' && module.exports) { module.exports = { rows: rows, describe: describe }; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st = null;

    function render() {
        st.body.textContent = '';
        const list = rows(st.view);
        if (!list.length) { st.body.appendChild(h('div', { class: 'wsk-empty', text: 'Loading...' })); return; }
        list.forEach((r) => {
            const bar = h('div', { class: 'wsk-bar' }, h('div', { class: 'wsk-fill' + (r.top ? ' is-top' : '') }));
            bar.firstChild.style.width = r.fill + '%';
            st.body.appendChild(h('div', { class: 'wsk-row' },
                h('div', { class: 'wsk-top' },
                    h('span', { class: 'wsk-name', text: r.label }),
                    h('span', { class: 'wsk-level', text: 'Level ' + r.level })),
                bar,
                h('div', { class: 'wsk-sub' },
                    h('span', { class: 'wsk-bonus', text: r.text }),
                    h('span', { class: 'wsk-xp', text: r.progress }))));
        });
    }

    function onKey(e) { if (st && (e.key === 'Escape' || e.key === 'F9')) st.api.post('close'); }

    const CSS = [
        '.wsk-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }',
        '.wsk-panel { width: min(560px, 94vw); max-height: 86vh; display: flex; flex-direction: column; gap: 10px; }',
        '.wsk-head { display: flex; align-items: center; } .wsk-head .wl-title { flex: 1; }',
        '.wsk-body { overflow-y: auto; display: flex; flex-direction: column; gap: 10px; }',
        '.wsk-row { padding: 10px 12px; background: var(--wl-bg-sunken); border: 1px solid var(--wl-border); border-radius: 6px; }',
        '.wsk-top { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 6px; }',
        '.wsk-name { font-size: 17px; font-weight: 700; } .wsk-level { color: var(--wl-accent); font-weight: 700; }',
        '.wsk-bar { height: 8px; background: rgba(0,0,0,0.4); border-radius: 4px; overflow: hidden; }',
        '.wsk-fill { height: 100%; background: var(--wl-accent); transition: width 0.4s; } .wsk-fill.is-top { background: #e0b24f; }',
        '.wsk-sub { display: flex; justify-content: space-between; gap: 10px; margin-top: 6px; font-size: 12.5px; color: var(--wl-text-dim, #9fa894); }',
        '.wsk-xp { white-space: nowrap; font-variant-numeric: tabular-nums; }',
        '.wsk-hint { font-size: 12px; color: var(--wl-text-dim, #9fa894); }',
    ].join('\n');

    UI.registerScreen('skillsScreen', {
        mount: function (el, data, api) {
            st = { api: api, view: data.view };
            st.body = h('div', { class: 'wsk-body' });
            el.appendChild(h('div', { class: 'wsk-root' },
                h('div', { class: 'wl-panel wsk-panel' },
                    h('div', { class: 'wsk-head' }, h('h1', { class: 'wl-title', text: 'Skills' }), UI.button('Close', () => api.post('close'))),
                    st.body,
                    h('div', { class: 'wsk-hint', text: 'Skills grow by doing: search, craft, treat wounds, hunt, sprint and fight. Dying costs a little progress.' }))));
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            render();
        },
        update: function (data) { if (data.view) { st.view = data.view; render(); } },
        unmount: function () { document.removeEventListener('keydown', onKey); st = null; },
    });

})();
