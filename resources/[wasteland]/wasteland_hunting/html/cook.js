// wasteland_hunting :: html/cook.js
// Cooking at a campfire: pick how many to cook (up to what you carry),
// then watch the progress ("Cooking 2 of 5"); Stop at any time.
// Data: { view = { fire, items = [{ item, label, result, have, image }], seconds, max, message, cooking? },
//         progress = { label, done, total, seconds } | { finished = true, message } }
// Posts: cook { item, count }, stop, close

(function () {
    'use strict';

    // Pure helper (unit-tested): is something cooking right now? (`done` is
    // how many pieces are ready; `finished` marks the end.)
    function cooking(p) { return !!p && !p.finished && typeof p.total === 'number' && p.done < p.total; }

    // Pure helper (unit-tested): the amount typed, kept between 1 and what can be cooked.
    function clampCount(value, have, max) {
        const n = Math.floor(Number(value) || 1);
        return Math.max(1, Math.min(n, have, max || 50));
    }

    if (typeof module === 'object' && module.exports) { module.exports = { clampCount: clampCount, cooking: cooking }; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st = null;

    function render() {
        const v = st.view;
        st.body.innerHTML = '';
        if (!v) return;
        const p = st.progress;
        if (cooking(p)) {
            const fill = h('div', { class: 'wck-fill' });
            st.body.appendChild(h('div', { class: 'wck-busy' },
                h('div', { class: 'wck-busy__label', text: 'Cooking ' + p.label.toLowerCase() + ': ' + (p.done + 1) + ' of ' + p.total }),
                h('div', { class: 'wck-track' }, fill),
                UI.button('Stop', () => st.api.post('stop'))));
            const ms = Math.max(200, (Number(p.seconds) || 5) * 1000);
            fill.style.transition = 'none';
            fill.style.width = '0%';
            requestAnimationFrame(() => requestAnimationFrame(() => { fill.style.transition = 'width ' + ms + 'ms linear'; fill.style.width = '100%'; }));
            return;
        }
        v.items.forEach((it) => {
            const field = h('input', { class: 'wl-input wck-num', attrs: { type: 'number', min: '1', max: String(Math.max(1, it.have)), value: String(Math.max(1, Math.min(it.have, st.counts[it.item] || it.have))) } });
            const cook = UI.button('Cook', () => {
                const n = clampCount(field.value, it.have, v.max);
                st.counts[it.item] = n;
                st.api.post('cook', { item: it.item, count: n });
            }, 'primary');
            const row = h('div', { class: 'wck-row' + (it.have > 0 ? '' : ' is-empty') },
                it.image ? h('img', { class: 'wck-img', attrs: { src: it.image } }) : null,
                h('div', { class: 'wck-what' },
                    h('div', { class: 'wck-name', text: it.label + ' → ' + it.result }),
                    h('div', { class: 'wl-hint', text: 'You have ' + it.have + ' · ' + v.seconds + ' s each' })),
                h('span', { class: 'wck-amount' }, UI.button('−', () => { field.value = String(clampCount(Number(field.value) - 1, it.have, v.max)); }),
                    field, UI.button('+', () => { field.value = String(clampCount(Number(field.value) + 1, it.have, v.max)); }),
                    UI.button('All', () => { field.value = String(Math.max(1, Math.min(it.have, v.max))); })),
                cook);
            if (it.have <= 0) [...row.querySelectorAll('button, input')].forEach((b) => { b.disabled = true; });
            st.body.appendChild(row);
        });
    }

    function onKey(e) { if (st && e.key === 'Escape' && e.target.tagName !== 'INPUT') st.api.post('close'); }

    UI.registerScreen('cookScreen', {
        mount: function (el, data, api) {
            st = { api: api, view: data.view || null, progress: null, counts: {} };
            st.body = h('div', { class: 'wck-body' });
            st.message = h('div', { class: 'wl-message', text: (data.view && data.view.message) || '' });
            el.appendChild(h('div', { class: 'wck-root' }, h('div', { class: 'wl-panel wck-panel' },
                h('div', { class: 'wck-head' }, h('h1', { class: 'wl-title', text: 'Campfire' }), UI.button('Close', () => api.post('close'))),
                st.body, st.message)));
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            render();
        },
        update: function (data) {
            if (data.view) {
                st.view = data.view;
                st.message.textContent = data.view.message || '';
                st.progress = data.view.cooking ? { label: data.view.cooking.label, done: data.view.cooking.done, total: data.view.cooking.total,
                    seconds: data.view.seconds } : null;
            }
            if (data.progress) {
                st.progress = data.progress.finished ? null : data.progress;
                if (data.progress.message) st.message.textContent = data.progress.message;
            }
            if (data.message) st.message.textContent = data.message;
            render();
        },
        unmount: function () { document.removeEventListener('keydown', onKey); st = null; },
    });

    const CSS = [
        '.wck-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }',
        '.wck-panel { width: min(560px, 94vw); display: flex; flex-direction: column; gap: 10px; }',
        '.wck-head { display: flex; align-items: center; } .wck-head .wl-title { flex: 1; }',
        '.wck-body { display: flex; flex-direction: column; gap: 8px; }',
        '.wck-row { display: flex; align-items: center; gap: 10px; padding: 8px 10px; background: var(--wl-bg-sunken); border: 1px solid var(--wl-border); border-radius: 6px; }',
        '.wck-row.is-empty { opacity: 0.55; }',
        '.wck-img { width: 40px; height: 40px; object-fit: contain; }',
        '.wck-what { flex: 1; min-width: 0; } .wck-name { font-weight: 700; font-size: 15px; }',
        '.wck-amount { display: flex; align-items: center; gap: 4px; } .wck-amount .wl-btn { padding: 3px 9px; }',
        '.wck-num { width: 60px; padding: 3px 6px; text-align: center; }',
        '.wck-busy { display: flex; flex-direction: column; gap: 10px; padding: 8px 0; }',
        '.wck-busy__label { font-size: 16px; font-weight: 700; }',
        '.wck-track { height: 10px; background: var(--wl-bg-sunken); border: 1px solid var(--wl-border); border-radius: 5px; overflow: hidden; }',
        '.wck-fill { height: 100%; width: 0; background: #e8a24a; }',
    ].join('\n');
})();
