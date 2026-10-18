// wasteland_camps :: html/trader.js
// Trade screen: Buy (the trader's stock) and Sell (what the trader takes
// that you carry). Prices in cash; the server decides every trade.
// Data: { title, place, cash, message, ok, items = [{ name, label, image, buy, sell, stock, have }] }

(function () {
    'use strict';

    // Pure helpers (unit-tested with Node)
    function buyList(items) { return (items || []).filter((i) => typeof i.buy === 'number'); }
    function sellList(items) { return (items || []).filter((i) => typeof i.sell === 'number' && i.have > 0); }
    function money(n) { return '$' + Math.max(0, Math.floor(n || 0)).toLocaleString('en-US'); }

    if (typeof module === 'object' && module.exports) {
        module.exports = { buyList: buyList, sellList: sellList, money: money };
        return;
    }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st;

    function row(it, mode) {
        const img = h('img', { class: 'wtr-img', draggable: false });
        if (it.image) img.src = it.image; else img.style.visibility = 'hidden';
        img.addEventListener('error', () => { img.style.visibility = 'hidden'; });
        const max = mode === 'buy' ? (typeof it.stock === 'number' ? it.stock : 999) : it.have;
        const qty = h('input', { class: 'wl-input wtr-qty', attrs: { type: 'number', min: '1', max: String(Math.max(1, max)) } });
        qty.value = '1';
        const price = mode === 'buy' ? it.buy : it.sell;
        const info = mode === 'buy'
            ? (typeof it.stock === 'number' ? (it.stock > 0 ? it.stock + ' in stock' : 'sold out') : '')
            : 'you have ' + it.have;
        const go = UI.button(mode === 'buy' ? 'Buy' : 'Sell', () => {
            const count = Math.max(1, Math.floor(Number(qty.value) || 1));
            st.api.post(mode, { item: it.name, count: count });
        }, mode === 'buy' ? 'primary' : undefined);
        if (mode === 'buy' && typeof it.stock === 'number' && it.stock <= 0) go.disabled = true;
        const all = mode === 'sell' ? UI.button('All', () => st.api.post('sell', { item: it.name, count: it.have })) : null;
        return h('div', { class: 'wtr-row' }, img,
            h('div', { class: 'wtr-name' }, h('div', { text: it.label }), h('div', { class: 'wl-hint', text: info })),
            h('div', { class: 'wtr-price', text: money(price) }), qty, go, all);
    }

    function render() {
        const d = st.data;
        st.root.innerHTML = '';
        const buys = buyList(d.items);
        const sells = sellList(d.items);
        const buyCol = h('div', { class: 'wtr-col' }, h('div', { class: 'wl-section-title', text: 'Buy' }));
        buys.forEach((it) => buyCol.appendChild(row(it, 'buy')));
        if (!buys.length) buyCol.appendChild(h('div', { class: 'wl-hint', text: 'Nothing for sale.' }));
        const sellCol = h('div', { class: 'wtr-col' }, h('div', { class: 'wl-section-title', text: 'Sell' }));
        sells.forEach((it) => sellCol.appendChild(row(it, 'sell')));
        if (!sells.length) sellCol.appendChild(h('div', { class: 'wl-hint', text: 'You carry nothing this trader buys.' }));
        st.root.appendChild(h('div', { class: 'wtr-panel' },
            h('div', { class: 'wtr-head' },
                h('div', {}, h('div', { class: 'wl-title', text: d.title || 'Trader' }), h('div', { class: 'wl-hint', text: d.place || '' })),
                h('div', { class: 'wtr-cash', text: 'Cash: ' + money(d.cash) }),
                UI.button('Close', () => st.api.post('close'))),
            h('div', { class: 'wl-message' + (d.message ? (d.ok ? ' is-ok' : ' is-error') : ''), text: d.message || '' }),
            h('div', { class: 'wtr-cols' }, buyCol, sellCol),
            h('div', { class: 'wl-hint wtr-foot', text: 'Esc closes' })));
    }

    function onKey(e) { if (e.key === 'Escape') st.api.post('close'); }

    UI.registerScreen('trader', {
        mount: function (el, data, api) {
            st = { root: h('div', { class: 'wtr-root' }), data: data, api: api };
            el.appendChild(st.root);
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            render();
        },
        update: function (data) { st.data = data; render(); },
        unmount: function () { document.removeEventListener('keydown', onKey); st = null; },
    });

    const CSS = [
        '.wtr-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }',
        '.wtr-panel { width: min(1000px, 94vw); max-height: 86vh; display: flex; flex-direction: column; gap: 10px; padding: 18px 20px;',
        '  background: var(--wl-bg); border: 1px solid var(--wl-border); border-radius: var(--wl-radius); box-shadow: 0 20px 60px rgba(0,0,0,0.6); }',
        '.wtr-head { display: flex; align-items: center; gap: 16px; } .wtr-head > div:first-child { flex: 1; }',
        '.wtr-cash { font-size: 16px; font-weight: 600; color: #9be27a; font-variant-numeric: tabular-nums; }',
        '.wtr-cols { display: grid; grid-template-columns: 1fr 1fr; gap: 18px; overflow: hidden; min-height: 0; }',
        '.wtr-col { overflow-y: auto; max-height: 64vh; padding-right: 4px; display: flex; flex-direction: column; gap: 4px; }',
        '.wtr-row { display: grid; grid-template-columns: 40px 1fr 70px 64px auto auto; align-items: center; gap: 8px; padding: 4px 6px;',
        '  background: var(--wl-bg-sunken); border-radius: 4px; }',
        '.wtr-img { width: 38px; height: 38px; object-fit: contain; }',
        '.wtr-name { font-size: 13px; line-height: 1.2; }',
        '.wtr-price { text-align: right; font-variant-numeric: tabular-nums; color: #e6d39a; }',
        '.wtr-qty { width: 60px; }',
        '.wtr-foot { text-align: right; }',
        // ---- polish ----
        '.wtr-panel { position: relative; border-radius: 12px; border-color: rgba(214,186,140,0.14); background: linear-gradient(180deg, rgba(255,240,210,0.035), rgba(255,240,210,0) 120px), var(--wl-bg); box-shadow: var(--wl-shadow), inset 0 1px 0 rgba(255,240,210,0.06); }',
        '.wtr-panel::before { content: ""; position: absolute; top: -1px; left: 24px; right: 24px; height: 2px; border-radius: 2px; background: linear-gradient(90deg, transparent, var(--wl-accent) 25%, var(--wl-accent-strong) 50%, var(--wl-accent) 75%, transparent); opacity: 0.75; pointer-events: none; }',
        '.wtr-row { border-radius: 8px; background: linear-gradient(180deg, rgba(255,240,210,0.035), rgba(0,0,0,0.18)), rgba(10,10,9,0.55); border: 1px solid rgba(214,186,140,0.10); transition: border-color 0.14s; }',
        '.wtr-row:hover { border-color: rgba(217,130,43,0.35); }',
    ].join('\n');
})();
