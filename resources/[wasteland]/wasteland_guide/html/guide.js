// wasteland_guide :: html/guide.js
// The survivor's guide: Progress (what to try next, every milestone),
// Stats, How to (pages from guide.lua).
// Data: { view = { milestones = [{ id, label, hint, value, count, done }], next = [id], stats = {}, lifeMinutes, pages = [{ title, lines }] } }
// Posts: close
(function () {
    'use strict';

    const STATS = [
        ['kills', 'Zombies killed'], ['searches', 'Places searched'], ['crafts', 'Things crafted'],
        ['harvests', 'Animals harvested'], ['cooked', 'Meat cooked'], ['treated', 'Wounds treated'],
        ['trades', 'Trades at camps'], ['playerTrades', 'Trades with players'], ['jobs', 'Jobs finished'],
        ['drops', 'Supply drops opened'], ['blueprints', 'Blueprints learned'], ['deaths', 'Deaths'],
    ];

    function minutes(m) {
        m = Math.max(0, Math.floor(m || 0));
        if (m < 60) return m + ' min';
        const h = Math.floor(m / 60);
        return h + ' h ' + (m % 60) + ' min';
    }

    // Pure helpers (unit-tested).
    function summary(view) {
        const list = (view && view.milestones) || [];
        const done = list.filter((m) => m.done).length;
        return { done: done, total: list.length, pct: list.length ? Math.round((done / list.length) * 100) : 0 };
    }
    function nextUp(view) {
        const list = (view && view.milestones) || [];
        return ((view && view.next) || []).map((id) => list.find((m) => m.id === id)).filter(Boolean);
    }
    function statRows(view) {
        const s = (view && view.stats) || {};
        const rows = [['Alive this life', minutes(view && view.lifeMinutes)], ['Longest life', minutes(s.lifeMinutes)],
            ['Best skill level', String(s.bestSkill || 1)]];
        STATS.forEach((p) => rows.push([p[1], String(Math.floor(s[p[0]] || 0))]));
        return rows;
    }

    if (typeof module === 'object' && module.exports) { module.exports = { summary: summary, nextUp: nextUp, statRows: statRows, minutes: minutes }; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st = null;

    function progressBar(value, count) {
        const bar = h('div', { class: 'wgd-bar' }, h('div', { class: 'wgd-fill' }));
        bar.firstChild.style.width = Math.round((Math.min(value, count) / count) * 100) + '%';
        return bar;
    }

    function renderProgress() {
        const v = st.view;
        const s = summary(v);
        const next = nextUp(v);
        st.body.appendChild(h('div', { class: 'wgd-overall' },
            h('div', { class: 'wgd-overall-text', text: s.done + ' of ' + s.total + ' milestones' }),
            progressBar(s.done, Math.max(1, s.total))));
        if (next.length) {
            const box = h('div', { class: 'wgd-next' }, h('div', { class: 'wgd-h', text: 'Try next' }));
            next.forEach((m) => box.appendChild(h('div', { class: 'wgd-next-item' },
                h('div', { class: 'wgd-next-label', text: m.label + (m.count > 1 ? '  (' + m.value + ' / ' + m.count + ')' : '') }),
                h('div', { class: 'wgd-hint', text: m.hint }))));
            st.body.appendChild(box);
        } else {
            st.body.appendChild(h('div', { class: 'wgd-next' }, h('div', { class: 'wgd-h', text: 'Every milestone done. A true survivor.' })));
        }
        const list = h('div', { class: 'wgd-list' });
        (v.milestones || []).forEach((m) => {
            list.appendChild(h('div', { class: 'wgd-m' + (m.done ? ' is-done' : '') },
                h('span', { class: 'wgd-check', text: m.done ? '✓' : '' }),
                h('div', { class: 'wgd-m-main' },
                    h('div', { class: 'wgd-m-label', text: m.label }),
                    m.done ? null : h('div', { class: 'wgd-hint', text: m.hint })),
                m.count > 1 && !m.done ? h('span', { class: 'wgd-count', text: m.value + ' / ' + m.count }) : null));
        });
        st.body.appendChild(list);
    }

    function renderStats() {
        const grid = h('div', { class: 'wgd-stats' });
        statRows(st.view).forEach((r) => grid.appendChild(h('div', { class: 'wgd-stat' },
            h('div', { class: 'wgd-stat-value', text: r[1] }), h('div', { class: 'wgd-stat-label', text: r[0] }))));
        st.body.appendChild(grid);
    }

    function renderPages() {
        (st.view.pages || []).forEach((p, i) => {
            const open = st.page === i;
            const head = h('button', { class: 'wgd-page-head' + (open ? ' is-open' : ''), text: (open ? '▾ ' : '▸ ') + p.title });
            head.addEventListener('click', () => { st.page = open ? -1 : i; render(); });
            const page = h('div', { class: 'wgd-page' }, head);
            if (open) {
                const body = h('div', { class: 'wgd-page-body' });
                (p.lines || []).forEach((l) => body.appendChild(h('p', { text: l })));
                page.appendChild(body);
            }
            st.body.appendChild(page);
        });
    }

    function render() {
        st.tabs.forEach((b) => b.classList.toggle('is-active', b.dataset.tab === st.tab));
        st.body.textContent = '';
        if (!st.view) { st.body.appendChild(h('div', { class: 'wgd-hint', text: 'Loading...' })); return; }
        if (st.tab === 'stats') renderStats();
        else if (st.tab === 'howto') renderPages();
        else renderProgress();
    }

    function onKey(e) { if (st && (e.key === 'Escape' || e.key === 'F2')) st.api.post('close'); }

    const CSS = [
        '.wgd-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }',
        '.wgd-panel { width: min(760px, 94vw); height: min(780px, 88vh); display: flex; flex-direction: column; gap: 10px; }',
        '.wgd-head { display: flex; align-items: center; gap: 8px; } .wgd-head .wl-title { flex: 1; }',
        '.wgd-tabs { display: flex; gap: 6px; }',
        '.wgd-tab { padding: 7px 14px; border-radius: 5px; border: 1px solid var(--wl-border); background: var(--wl-bg-sunken); color: inherit; cursor: pointer; font: inherit; }',
        '.wgd-tab.is-active { border-color: var(--wl-accent); color: var(--wl-accent); }',
        '.wgd-body { flex: 1; overflow-y: auto; display: flex; flex-direction: column; gap: 10px; padding-right: 4px; }',
        '.wgd-body::-webkit-scrollbar { width: 8px; } .wgd-body::-webkit-scrollbar-track { background: transparent; }',
        '.wgd-body::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.15); border-radius: 4px; }',
        '.wgd-bar { height: 8px; background: rgba(0,0,0,0.4); border-radius: 4px; overflow: hidden; } .wgd-fill { height: 100%; background: var(--wl-accent); }',
        '.wgd-overall-text { margin-bottom: 6px; font-weight: 700; }',
        '.wgd-next { padding: 10px 12px; border: 1px solid var(--wl-accent); border-radius: 6px; background: rgba(0,0,0,0.25); display: flex; flex-direction: column; gap: 8px; }',
        '.wgd-h { font-size: 12px; letter-spacing: 0.2em; text-transform: uppercase; color: var(--wl-accent); font-weight: 700; }',
        '.wgd-next-label { font-weight: 700; } .wgd-hint { font-size: 12.5px; color: var(--wl-text-dim, #9fa894); margin-top: 2px; }',
        '.wgd-list { display: flex; flex-direction: column; gap: 6px; }',
        '.wgd-m { display: flex; align-items: center; gap: 10px; padding: 8px 10px; background: var(--wl-bg-sunken); border: 1px solid var(--wl-border); border-radius: 5px; }',
        '.wgd-m.is-done { opacity: 0.6; } .wgd-m-main { flex: 1; }',
        '.wgd-check { width: 20px; height: 20px; border: 1px solid var(--wl-border); border-radius: 4px; display: flex; align-items: center; justify-content: center; color: var(--wl-accent); font-weight: 700; flex: none; }',
        '.wgd-m.is-done .wgd-check { border-color: var(--wl-accent); }',
        '.wgd-count { font-variant-numeric: tabular-nums; color: var(--wl-text-dim, #9fa894); white-space: nowrap; }',
        '.wgd-stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; }',
        '.wgd-stat { padding: 10px; background: var(--wl-bg-sunken); border: 1px solid var(--wl-border); border-radius: 5px; }',
        '.wgd-stat-value { font-size: 22px; font-weight: 700; color: var(--wl-accent); } .wgd-stat-label { font-size: 12px; color: var(--wl-text-dim, #9fa894); }',
        '.wgd-page { border: 1px solid var(--wl-border); border-radius: 5px; background: var(--wl-bg-sunken); }',
        '.wgd-page-head { width: 100%; text-align: left; padding: 9px 12px; background: none; border: 0; color: inherit; font: inherit; font-weight: 700; cursor: pointer; }',
        '.wgd-page-head.is-open { color: var(--wl-accent); }',
        '.wgd-page-body { padding: 0 12px 8px; } .wgd-page-body p { margin: 6px 0; line-height: 1.45; }',
    ].join('\n');

    UI.registerScreen('guideScreen', {
        mount: function (el, data, api) {
            st = { api: api, view: data.view, tab: 'progress', page: 0 };
            st.body = h('div', { class: 'wgd-body' });
            st.tabs = [['progress', 'Progress'], ['stats', 'Stats'], ['howto', 'How to']].map((t) => {
                const b = h('button', { class: 'wgd-tab', text: t[1] });
                b.dataset.tab = t[0];
                b.addEventListener('click', () => { st.tab = t[0]; render(); });
                return b;
            });
            el.appendChild(h('div', { class: 'wgd-root' },
                h('div', { class: 'wl-panel wgd-panel' },
                    h('div', { class: 'wgd-head' }, h('h1', { class: 'wl-title', text: "Survivor's guide" }), UI.button('Close', () => api.post('close'))),
                    h('div', { class: 'wgd-tabs' }, ...st.tabs),
                    st.body)));
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            render();
        },
        update: function (data) { if (data.view) { st.view = data.view; render(); } },
        unmount: function () { document.removeEventListener('keydown', onKey); st = null; },
    });
})();
