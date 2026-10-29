// wasteland_survivors :: html/barter.js
// Trading with a survivor: their swaps (your items for theirs). The server
// decides every trade.
// Data: { title, message, ok, offers = [{ index, left, give = { name, count, label, image, have }, get = { name, count, label, image } }] }

(function () {
    'use strict';

    // Pure helpers (unit-tested with Node)
    function canTrade(o) { return !!o && o.left > 0 && (o.give.have || 0) >= o.give.count; }
    function why(o) {
        if (o.left <= 0) return 'none left';
        if ((o.give.have || 0) < o.give.count) return 'you have ' + (o.give.have || 0);
        return o.left + ' left';
    }

    if (typeof module === 'object' && module.exports) {
        module.exports = { canTrade: canTrade, why: why };
        return;
    }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st;

    function stack(s) {
        const img = h('img', { class: 'wsv-img', draggable: false });
        if (s.image) img.src = s.image; else img.style.visibility = 'hidden';
        img.addEventListener('error', () => { img.style.visibility = 'hidden'; });
        return h('div', { class: 'wsv-stack' }, img, h('div', { class: 'wsv-label', text: s.count + ' x ' + s.label }));
    }

    function row(o) {
        const go = UI.button('Trade', () => st.api.post('trade', { index: o.index }), 'primary');
        if (!canTrade(o)) go.disabled = true;
        return h('div', { class: 'wsv-row' + (canTrade(o) ? '' : ' is-off') },
            stack(o.give), h('div', { class: 'wsv-arrow', text: '→' }), stack(o.get),
            h('div', { class: 'wl-hint wsv-why', text: why(o) }), go);
    }

    function render() {
        const d = st.data;
        st.root.innerHTML = '';
        const list = h('div', { class: 'wsv-list' });
        (d.offers || []).forEach((o) => list.appendChild(row(o)));
        if (!(d.offers || []).length) list.appendChild(h('div', { class: 'wl-hint', text: 'They have nothing to trade.' }));
        st.root.appendChild(h('div', { class: 'wsv-panel' },
            h('div', { class: 'wsv-head' },
                h('div', {}, h('div', { class: 'wl-title', text: d.title || 'Survivor' }), h('div', { class: 'wl-hint', text: 'Survivor - trades item for item' })),
                UI.button('Close', () => st.api.post('close'))),
            h('div', { class: 'wl-message' + (d.message ? (d.ok ? ' is-ok' : ' is-error') : ''), text: d.message || '' }),
            h('div', { class: 'wsv-cols wl-hint' }, h('div', { text: 'You give' }), h('div'), h('div', { text: 'You get' })),
            list,
            h('div', { class: 'wl-hint wsv-foot', text: 'Esc closes' })));
    }

    function onKey(e) { if (e.key === 'Escape') st.api.post('close'); }

    UI.registerScreen('survivorTrade', {
        mount: function (el, data, api) {
            st = { root: h('div', { class: 'wsv-root' }), data: data || {}, api: api };
            el.appendChild(st.root);
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            render();
        },
        // a full view (offers) replaces everything; a notice only sets the message
        update: function (data) { st.data = data && data.offers ? data : Object.assign({}, st.data, data); render(); },
        unmount: function () { document.removeEventListener('keydown', onKey); st = null; },
    });

    const CSS = [
        '.wsv-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }',
        '.wsv-panel { position: relative; width: min(680px, 94vw); max-height: 86vh; display: flex; flex-direction: column; gap: 10px; padding: 18px 20px;',
        '  border: 1px solid rgba(214,186,140,0.14); border-radius: 12px; box-shadow: var(--wl-shadow), inset 0 1px 0 rgba(255,240,210,0.06);',
        '  background: linear-gradient(180deg, rgba(255,240,210,0.035), rgba(255,240,210,0) 120px), var(--wl-bg); }',
        '.wsv-panel::before { content: ""; position: absolute; top: -1px; left: 24px; right: 24px; height: 2px; border-radius: 2px; background: linear-gradient(90deg, transparent, var(--wl-accent) 25%, var(--wl-accent-strong) 50%, var(--wl-accent) 75%, transparent); opacity: 0.75; pointer-events: none; }',
        '.wsv-head { display: flex; align-items: center; gap: 16px; } .wsv-head > div:first-child { flex: 1; }',
        '.wsv-cols { display: grid; grid-template-columns: 1fr 24px 1fr 90px 72px; gap: 8px; padding: 0 8px; text-transform: uppercase; letter-spacing: 0.1em; font-size: 11px; }',
        '.wsv-list { overflow-y: auto; max-height: 60vh; display: flex; flex-direction: column; gap: 5px; }',
        '.wsv-row { display: grid; grid-template-columns: 1fr 24px 1fr 90px 72px; align-items: center; gap: 8px; padding: 5px 8px; border-radius: 8px;',
        '  background: linear-gradient(180deg, rgba(255,240,210,0.035), rgba(0,0,0,0.18)), rgba(10,10,9,0.55); border: 1px solid rgba(214,186,140,0.10); }',
        '.wsv-row:hover { border-color: rgba(217,130,43,0.35); } .wsv-row.is-off { opacity: 0.6; }',
        '.wsv-stack { display: flex; align-items: center; gap: 8px; min-width: 0; } .wsv-img { width: 36px; height: 36px; object-fit: contain; flex: none; }',
        '.wsv-label { font-size: 13px; line-height: 1.2; } .wsv-arrow { text-align: center; color: var(--wl-accent); font-size: 18px; }',
        '.wsv-why { text-align: right; } .wsv-foot { text-align: right; }',
    ].join('\n');
})();
