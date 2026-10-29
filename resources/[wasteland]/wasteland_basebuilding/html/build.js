// wasteland_basebuilding :: html/build.js
// Two screens in one:
//   build    - categories on the left, the pieces of the chosen one with
//              their cost (and what you carry); Build starts the placement.
//   cupboard - the tool cupboard: upkeep per material, who has access
//              (authorize by player id, take access away), Supplies, Repair
//              all, Remove.
// Data: { mode = 'build', build = { categories = [{ key, label, pieces = [{ key, label, cost = [{ label, count, have, image }], canPay }] }] } }
//     | { mode = 'cupboard', cupboard = { id, owner, health, maxHealth, radius, auth = [{ id, name, online }],
//         upkeep = [{ material, item, pieces, daily, have, hours }], damaged, upkeepEnabled, message } }
// Posts: place { key }, authorize { cupboard, server }, revoke { cupboard, id }, supplies { cupboard },
//        repairAll { cupboard }, removeCupboard { cupboard }, close

(function () {
    'use strict';

    // Pure helper (unit-tested): how long the supplies of one material last.
    function upkeepLine(u) {
        if (u.infinite) return u.pieces > 0 ? 'infinite (admin cupboard)' : 'no pieces';
        if (!u.daily) return u.pieces > 0 ? 'no upkeep needed' : 'no pieces';
        if (u.have <= 0) return 'OUT OF SUPPLY: these pieces are decaying';
        const hours = u.hours || 0;
        if (hours >= 24) return (hours / 24).toFixed(1) + ' days left';
        return 'ONLY ' + hours.toFixed(1) + ' hours left';
    }

    if (typeof module === 'object' && module.exports) { module.exports = { upkeepLine: upkeepLine }; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st = null;

    function confirmButton(label, fn, variant) {
        let armed = false, timer = null;
        const b = UI.button(label, () => {
            if (armed) { clearTimeout(timer); fn(); return; }
            armed = true;
            b.textContent = 'Sure? Click again';
            timer = setTimeout(() => { armed = false; b.textContent = label; }, 4000);
        }, variant);
        return b;
    }

    function renderBuild() {
        const b = st.build;
        st.title.textContent = 'Build';
        if (!b || !b.categories.length) { st.body.appendChild(h('div', { class: 'wl-hint', text: 'Nothing to build.' })); return; }
        if (!st.cat || !b.categories.find((c) => c.key === st.cat)) st.cat = b.categories[0].key;
        const tabs = h('div', { class: 'wbb-tabs' });
        b.categories.forEach((c) => tabs.appendChild(UI.button(c.label, () => { st.cat = c.key; render(); }, c.key === st.cat ? 'primary' : undefined)));
        const list = h('div', { class: 'wbb-list' });
        const cat = b.categories.find((c) => c.key === st.cat);
        cat.pieces.forEach((p) => {
            const cost = h('div', { class: 'wbb-cost' });
            p.cost.forEach((c) => cost.appendChild(h('span', { class: 'wbb-c' + (c.have >= c.count ? '' : ' is-missing'), text: c.count + ' ' + c.label + ' (' + c.have + ')' })));
            const go = UI.button('Build', () => st.api.post('place', { key: p.key }), 'primary');
            if (!p.canPay) go.disabled = true;
            list.appendChild(h('div', { class: 'wbb-row' }, h('div', { class: 'wbb-name', text: p.label }), cost, go));
        });
        st.body.appendChild(tabs);
        st.body.appendChild(list);
        st.body.appendChild(h('div', { class: 'wl-hint', text: 'Placing: E place · mouse wheel turn · arrows turn freely · Shift+wheel height · Tab snapping on/off · Backspace cancel. Build a Tool Cupboard first: it claims the land.' }));
    }

    function renderCupboard() {
        const c = st.cupboard;
        st.title.textContent = 'Tool cupboard';
        if (!c) return;
        st.body.appendChild(h('div', { class: 'wl-hint', text: 'Claims ' + Math.round(c.radius) + ' m · health ' + c.health + ' / ' + c.maxHealth + (c.owner ? ' · you own it' : '') }));
        if (c.upkeepEnabled) {
            st.body.appendChild(h('div', { class: 'wl-section-title', text: 'Upkeep (from the supplies)' }));
            const up = h('div', { class: 'wbb-upkeep' });
            c.upkeep.forEach((u) => {
                const bad = u.daily > 0 && (u.have <= 0 || (u.hours || 0) < 24);
                up.appendChild(h('div', { class: 'wbb-up' + (bad ? ' is-bad' : '') },
                    h('span', { class: 'wbb-up__m', text: u.item }),
                    h('span', { class: 'wl-hint', text: u.pieces + ' pieces · ' + u.daily + ' a day · ' + u.have + ' in supplies' }),
                    h('span', { class: 'wbb-up__s', text: upkeepLine(u) })));
            });
            st.body.appendChild(up);
        }
        st.body.appendChild(h('div', { class: 'wbb-buttons' },
            UI.button('Supplies', () => st.api.post('supplies', { cupboard: c.id })),
            UI.button('Repair all' + (c.damaged ? ' (' + c.damaged + ' damaged)' : ''), () => st.api.post('repairAll', { cupboard: c.id }))));
        st.body.appendChild(h('div', { class: 'wl-section-title', text: 'Access' }));
        st.body.appendChild(h('div', { class: 'wl-hint', text: 'The owner, the players below, and the owner\'s group (/group) may build, open doors and storage here.' }));
        const list = h('div', { class: 'wbb-auth' });
        if (!c.auth.length) list.appendChild(h('div', { class: 'wl-hint', text: 'Nobody else yet.' }));
        c.auth.forEach((a) => list.appendChild(h('div', { class: 'wbb-a' },
            h('span', { class: 'wbb-dot' + (a.online ? ' is-on' : '') }), h('span', { class: 'wbb-a__n', text: a.name }),
            c.owner ? confirmButton('Remove', () => st.api.post('revoke', { cupboard: c.id, id: a.id })) : null)));
        st.body.appendChild(list);
        if (c.owner) {
            const id = h('input', { class: 'wl-input wbb-id', attrs: { type: 'number', min: '1', placeholder: 'Player id' } });
            st.body.appendChild(h('div', { class: 'wbb-buttons' }, id, UI.button('Give access', () => st.api.post('authorize', { cupboard: c.id, server: id.value }), 'primary')));
            st.body.appendChild(h('div', { class: 'wbb-buttons wbb-danger' },
                confirmButton('Remove the tool cupboard', () => st.api.post('removeCupboard', { cupboard: c.id }), 'danger'),
                h('span', { class: 'wl-hint', text: 'The land is no longer claimed (the pieces stay).' })));
        }
    }

    function render() {
        st.body.innerHTML = '';
        if (st.mode === 'cupboard') renderCupboard(); else renderBuild();
    }

    function onKey(e) { if (st && e.key === 'Escape' && e.target.tagName !== 'INPUT') st.api.post('close'); }

    UI.registerScreen('bbScreen', {
        mount: function (el, data, api) {
            st = { api: api, mode: data.mode, build: data.build, cupboard: data.cupboard, cat: null };
            st.title = h('h1', { class: 'wl-title' });
            st.body = h('div', { class: 'wbb-body' });
            st.message = h('div', { class: 'wl-message', text: (data.cupboard && data.cupboard.message) || '' });
            el.appendChild(h('div', { class: 'wbb-root' }, h('div', { class: 'wl-panel wbb-panel' },
                h('div', { class: 'wbb-head' }, st.title, UI.button('Close', () => api.post('close'))), st.body, st.message)));
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            render();
        },
        update: function (data) {
            if (data.mode) st.mode = data.mode;
            if (data.build) st.build = data.build;
            if (data.cupboard) { st.cupboard = data.cupboard; st.message.textContent = data.cupboard.message || ''; }
            if (data.message) st.message.textContent = data.message;
            render();
        },
        unmount: function () { document.removeEventListener('keydown', onKey); st = null; },
    });

    const CSS = [
        '.wbb-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }',
        '.wbb-panel { width: min(720px, 94vw); max-height: 88vh; display: flex; flex-direction: column; gap: 10px; }',
        '.wbb-head { display: flex; align-items: center; } .wbb-head .wl-title { flex: 1; }',
        '.wbb-body { overflow-y: auto; display: flex; flex-direction: column; gap: 8px; }',
        '.wbb-tabs { display: flex; flex-wrap: wrap; gap: 6px; }',
        '.wbb-list { display: flex; flex-direction: column; gap: 4px; }',
        '.wbb-row { display: flex; align-items: center; gap: 10px; padding: 7px 10px; background: var(--wl-bg-sunken); border: 1px solid var(--wl-border); border-radius: 6px; }',
        '.wbb-name { width: 180px; font-weight: 700; } .wbb-cost { flex: 1; display: flex; flex-wrap: wrap; gap: 4px 12px; font-size: 13px; }',
        '.wbb-c.is-missing { color: #e07a6a; }',
        '.wbb-upkeep { display: flex; flex-direction: column; gap: 4px; }',
        '.wbb-up { display: flex; align-items: baseline; gap: 10px; padding: 6px 10px; background: var(--wl-bg-sunken); border-left: 3px solid #7fc75a; border-radius: 4px; }',
        '.wbb-up.is-bad { border-left-color: #d65b4a; } .wbb-up__m { width: 110px; font-weight: 700; } .wbb-up__s { margin-left: auto; font-weight: 700; }',
        '.wbb-buttons { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; } .wbb-id { width: 120px; }',
        '.wbb-auth { display: flex; flex-direction: column; gap: 4px; }',
        '.wbb-a { display: flex; align-items: center; gap: 8px; padding: 5px 8px; background: var(--wl-bg-sunken); border-radius: 4px; }',
        '.wbb-a__n { flex: 1; } .wbb-dot { width: 8px; height: 8px; border-radius: 50%; background: #666; } .wbb-dot.is-on { background: #7fc75a; }',
        '.wbb-danger { margin-top: 8px; }',
    ].join('\n');
})();
