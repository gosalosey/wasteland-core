// wasteland_trade :: html/trade.js
// The trade window: three lists side by side, each scrolling on its own so
// any number of items fits without overlapping:
//   Your items (click Offer) | Your offer (change the amount, remove) | Their offer
// Accept at the bottom; any change to an offer takes both accepts back.
// Data: { invite = { from, name } } or { view = { me = { name, items, offer, ready }, them = { name, offer, ready }, message } }
// Posts: accept, decline, offer { uid, count }, ready { ready }, cancel

(function () {
    'use strict';

    // Pure helper (unit-tested): the status line under the lists.
    function status(view) {
        if (!view) return '';
        const me = view.me.ready, them = view.them.ready;
        if (me && them) return 'Trading...';
        if (me) return 'You accepted. Waiting for ' + view.them.name + '.';
        if (them) return view.them.name + ' accepted. Check their offer and accept.';
        return 'Add items, then both press Accept. Any change cancels the accepts.';
    }

    if (typeof module === 'object' && module.exports) { module.exports = { status: status }; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st = null;

    function img(it) {
        return it.image ? h('img', { class: 'wtd-img', attrs: { src: it.image, draggable: 'false' } }) : h('span', { class: 'wtd-img wtd-img--none' });
    }

    function row(it, right) {
        return h('div', { class: 'wtd-row' }, img(it),
            h('span', { class: 'wtd-name', text: it.label }),
            right);
    }

    function list(title, items, make, empty) {
        const box = h('div', { class: 'wtd-list' });
        if (!items.length) box.appendChild(h('div', { class: 'wl-hint wtd-empty', text: empty }));
        items.forEach((it) => box.appendChild(make(it)));
        return h('div', { class: 'wtd-col' }, h('div', { class: 'wl-section-title', text: title }), box);
    }

    function amountBox(it) {
        const field = h('input', { class: 'wl-input wtd-num', attrs: { type: 'number', min: '0', max: String(it.max), value: String(it.count) } });
        field.addEventListener('change', () => st.api.post('offer', { uid: it.uid, count: Math.max(0, Math.min(it.max, Math.floor(Number(field.value) || 0))) }));
        return h('span', { class: 'wtd-right' }, field, h('span', { class: 'wl-hint', text: '/ ' + it.max }),
            UI.button('✕', () => st.api.post('offer', { uid: it.uid, count: 0 })));
    }

    function render() {
        st.body.innerHTML = '';
        if (st.invite) {
            st.title.textContent = 'Trade request';
            st.body.appendChild(h('div', { class: 'wtd-invite' },
                h('div', { class: 'wtd-invite__text', text: st.invite.name + ' wants to trade with you.' }),
                h('div', { class: 'wtd-buttons' },
                    UI.button('Trade', () => st.api.post('accept'), 'primary'),
                    UI.button('No thanks', () => st.api.post('decline')))));
            return;
        }
        const v = st.view;
        if (!v) return;
        st.title.textContent = 'Trading with ' + v.them.name;
        const mine = v.me.items.filter((it) => it.offered < it.count);
        const cols = h('div', { class: 'wtd-cols' },
            list('Your items', mine, (it) => row(it, h('span', { class: 'wtd-right' },
                h('span', { class: 'wtd-count', text: 'x' + (it.count - it.offered) }),
                UI.button('Offer', () => st.api.post('offer', { uid: it.uid, count: it.count }))
            )), 'Nothing left to offer.'),
            list('Your offer' + (v.me.ready ? ' ✔' : ''), v.me.offer, (it) => row(it, amountBox(it)), 'Click Offer on your items.'),
            list(v.them.name + ' offers' + (v.them.ready ? ' ✔' : ''), v.them.offer,
                (it) => row(it, h('span', { class: 'wtd-count', text: 'x' + it.count })), 'Nothing yet.'));
        st.body.appendChild(cols);
        st.body.appendChild(h('div', { class: 'wtd-status' + (v.them.ready ? ' is-them' : ''), text: v.message || status(v) }));
        st.body.appendChild(h('div', { class: 'wtd-buttons' },
            v.me.ready ? UI.button('Undo accept', () => st.api.post('ready', { ready: false }))
                : UI.button('Accept', () => st.api.post('ready', { ready: true }), 'primary'),
            UI.button('Cancel trade', () => st.api.post('cancel'))));
    }

    function onKey(e) { if (st && e.key === 'Escape' && e.target.tagName !== 'INPUT') st.api.post(st.invite ? 'decline' : 'cancel'); }

    UI.registerScreen('tradeScreen', {
        mount: function (el, data, api) {
            st = { api: api, invite: data.invite || null, view: data.view || null };
            st.title = h('h1', { class: 'wl-title' });
            st.body = h('div', { class: 'wtd-body' });
            el.appendChild(h('div', { class: 'wtd-root' }, h('div', { class: 'wl-panel wtd-panel' + (st.invite ? ' is-small' : '') }, st.title, st.body)));
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            render();
        },
        update: function (data) {
            if (data.view) { st.view = data.view; st.invite = null; }
            if (data.invite) st.invite = data.invite;
            const panel = document.querySelector('.wtd-panel');
            if (panel) panel.classList.toggle('is-small', !!st.invite);
            render();
        },
        unmount: function () { document.removeEventListener('keydown', onKey); st = null; },
    });

    const CSS = [
        '.wtd-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }',
        '.wtd-panel { width: min(1100px, 96vw); height: min(640px, 90vh); display: flex; flex-direction: column; gap: 10px; }',
        '.wtd-panel.is-small { width: min(420px, 92vw); height: auto; }',
        '.wtd-body { flex: 1; min-height: 0; display: flex; flex-direction: column; gap: 10px; }',
        '.wtd-cols { flex: 1; min-height: 0; display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 12px; }',
        '.wtd-col { min-height: 0; display: flex; flex-direction: column; gap: 6px; }',
        '.wtd-list { flex: 1; min-height: 0; overflow-y: auto; display: flex; flex-direction: column; gap: 4px; padding-right: 4px;',
        '  background: var(--wl-bg-sunken); border: 1px solid var(--wl-border); border-radius: 6px; padding: 6px; }',
        '.wtd-row { flex: 0 0 auto; display: flex; align-items: center; gap: 8px; min-height: 40px; padding: 4px 6px; border-radius: 4px; background: rgba(255,255,255,0.03); }',
        '.wtd-img { width: 32px; height: 32px; object-fit: contain; flex: 0 0 32px; }',
        '.wtd-img--none { display: inline-block; background: rgba(255,255,255,0.06); border-radius: 4px; }',
        '.wtd-name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 14px; }',
        '.wtd-right { flex: 0 0 auto; display: flex; align-items: center; gap: 6px; }',
        '.wtd-right .wl-btn { padding: 3px 9px; font-size: 12px; }',
        '.wtd-count { font-weight: 700; color: var(--wl-accent); min-width: 36px; text-align: right; }',
        '.wtd-num { width: 70px; padding: 3px 6px; }',
        '.wtd-empty { padding: 8px; }',
        '.wtd-status { font-size: 14px; color: var(--wl-text-dim); } .wtd-status.is-them { color: var(--wl-accent); }',
        '.wtd-buttons { display: flex; gap: 8px; justify-content: flex-end; }',
        '.wtd-invite { display: flex; flex-direction: column; gap: 14px; } .wtd-invite__text { font-size: 16px; }',
    ].join('\n');
})();
