// wasteland_bases :: html/base.js
// The base screen: no base (how to claim one), or your base: upkeep, the
// pieces you can build and what they cost.
// Data: { view = { flags, claimRadius, maxPieces, base?: { id, owner, ownerName, pieces, inClaim, distance,
//         upkeep: { item, perDay, stock, paidHours, decaying, removeHours, coveredDays } },
//         catalog?: [{ kind, label, slot, family, tier, cost: [{ label, count, have }], built, max, canPay }] } }
// Posts: build {kind}, box, abandon, refresh, close

(function () {
    'use strict';

    // Pure helper (unit-tested): the upkeep line.
    function upkeepText(u) {
        if (!u) return '';
        if (u.decaying) {
            return 'Upkeep unpaid! Put ' + u.perDay + ' x ' + u.item + ' in the upkeep box or the base falls apart in ' + u.removeHours + ' h.';
        }
        const days = Math.floor(u.paidHours / 24);
        const paid = days > 0 ? days + ' d ' + (u.paidHours % 24) + ' h' : u.paidHours + ' h';
        return 'Paid for ' + paid + '. Upkeep: ' + u.perDay + ' x ' + u.item + ' a day; the box holds ' + u.stock +
            ' (' + u.coveredDays + ' more day' + (u.coveredDays === 1 ? '' : 's') + ').';
    }

    if (typeof module === 'object' && module.exports) { module.exports = { upkeepText: upkeepText }; return; }

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

    const GROUPS = { wall: 'Walls', door: 'Doors', gate: 'Gates' };

    function render() {
        const v = st.view;
        st.body.innerHTML = '';
        if (!v) { st.body.appendChild(h('div', { class: 'wl-hint', text: 'Loading...' })); return; }
        if (!v.base) {
            st.body.appendChild(h('div', { class: 'wl-section-title', text: 'No base yet' }));
            st.body.appendChild(h('div', { class: 'wl-hint', text: 'Craft a Base flag (wood planks, rags, scrap metal) and use it from your inventory ' +
                'to claim a spot. You can then build within ' + Math.floor(v.claimRadius) + ' m of the flag. ' +
                'One base per group: your group members build and use it with you. Not too close to camps or other bases.' }));
            st.body.appendChild(h('div', { class: 'wl-hint', text: v.flags > 0 ? 'You have a base flag: use it from your inventory.' : 'You have no base flag.' }));
            return;
        }
        const b = v.base;
        st.body.appendChild(h('div', { class: 'wbs-line' },
            h('span', { class: 'wbs-name', text: b.owner ? 'Your base' : 'Base of ' + b.ownerName }),
            h('span', { class: 'wl-hint', text: b.pieces + ' of ' + v.maxPieces + ' pieces' + (b.distance != null ? ' · flag ' + b.distance + ' m away' : '') })));
        st.body.appendChild(h('div', { class: 'wbs-upkeep' + (b.upkeep.decaying ? ' is-bad' : '') }, h('span', { text: upkeepText(b.upkeep) }),
            UI.button('Upkeep box', () => st.api.post('box'))));
        if (!b.inClaim) st.body.appendChild(h('div', { class: 'wl-hint wbs-warn', text: 'Go to your base to build (within ' + Math.floor(v.claimRadius) + ' m of the flag).' }));
        st.body.appendChild(h('div', { class: 'wl-hint', text: 'Pick a piece, then: E / Q turn, left click place (again for more), right click stop. ' +
            'Walls and doors snap to a grid; build a better wall on an old one to upgrade it. Hold Left Alt on a piece to use or demolish it.' }));
        let lastGroup = null;
        const list = h('div', { class: 'wbs-list' });
        (v.catalog || []).forEach((p) => {
            const group = p.slot === 'edge' ? (GROUPS[p.family] || 'Walls') : 'Other';
            if (group !== lastGroup) { list.appendChild(h('div', { class: 'wl-section-title', text: group })); lastGroup = group; }
            const full = p.max && p.built >= p.max;
            const cost = h('div', { class: 'wbs-cost' });
            p.cost.forEach((c) => cost.appendChild(h('span', { class: 'wbs-c' + (c.have >= c.count ? '' : ' is-missing'), text: c.count + ' ' + c.label + ' (' + c.have + ')' })));
            const btn = UI.button('Build', () => st.api.post('build', { kind: p.kind }), 'primary');
            if (!p.canPay || full || !b.inClaim) btn.disabled = true;
            list.appendChild(h('div', { class: 'wbs-row' },
                h('div', { class: 'wbs-what' }, h('div', { class: 'wbs-label', text: p.label }),
                    h('div', { class: 'wl-hint', text: p.max ? p.built + ' of ' + p.max + ' built' : (p.built ? p.built + ' built' : '') })),
                cost, btn));
        });
        st.body.appendChild(list);
        if (b.owner) {
            st.body.appendChild(h('div', { class: 'wgr-row wbs-danger' },
                confirmButton('Remove the whole base', () => st.api.post('abandon'), 'danger'),
                h('span', { class: 'wl-hint', text: 'Everything is removed, storage included. No refund.' })));
        }
    }

    function onKey(e) { if (st && (e.key === 'Escape' || e.key === 'F7') && e.target.tagName !== 'INPUT') st.api.post('close'); }

    UI.registerScreen('baseScreen', {
        mount: function (el, data, api) {
            st = { api: api, view: data.view };
            st.body = h('div', { class: 'wbs-body' });
            st.message = h('div', { class: 'wl-message' });
            el.appendChild(h('div', { class: 'wbs-root' },
                h('div', { class: 'wl-panel wbs-panel' },
                    h('div', { class: 'wbs-head' }, h('h1', { class: 'wl-title', text: 'Base' }), UI.button('Close', () => api.post('close'))),
                    st.body, st.message)));
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            render();
        },
        update: function (data) {
            if (data.view !== undefined) { st.view = data.view; render(); }
            if (data.message) st.message.textContent = data.message;
        },
        unmount: function () { document.removeEventListener('keydown', onKey); st = null; },
    });

    const CSS = [
        '.wbs-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }',
        '.wbs-panel { width: min(680px, 94vw); max-height: 88vh; display: flex; flex-direction: column; gap: 8px; }',
        '.wbs-head { display: flex; align-items: center; } .wbs-head .wl-title { flex: 1; }',
        '.wbs-body { overflow-y: auto; display: flex; flex-direction: column; gap: 8px; }',
        '.wbs-line { display: flex; align-items: baseline; gap: 10px; flex-wrap: wrap; }',
        '.wbs-name { font-size: 20px; font-weight: 700; color: var(--wl-accent); }',
        '.wbs-upkeep { display: flex; align-items: center; gap: 8px; padding: 8px 10px; border: 1px solid var(--wl-border); border-radius: 5px; background: var(--wl-bg-sunken); }',
        '.wbs-upkeep span { flex: 1; } .wbs-upkeep.is-bad { border-color: #d65b4a; color: #f0a093; }',
        '.wbs-warn { color: #e8c25a; }',
        '.wbs-list { display: flex; flex-direction: column; gap: 4px; }',
        '.wbs-row { display: flex; align-items: center; gap: 10px; padding: 6px 8px; background: var(--wl-bg-sunken); border: 1px solid var(--wl-border); border-radius: 5px; }',
        '.wbs-what { width: 150px; } .wbs-label { font-weight: 600; }',
        '.wbs-cost { flex: 1; display: flex; flex-wrap: wrap; gap: 4px 10px; font-size: 12px; }',
        '.wbs-c.is-missing { color: #e07a6a; }',
        '.wbs-danger { display: flex; gap: 8px; align-items: center; margin-top: 6px; }',
    ].join('\n');
})();
