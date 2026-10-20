// wasteland_moonshine :: html/still.js
// The moonshine still: pick a flavour (what it needs, what you have), the
// run in progress (time left), jars ready to collect. Esc closes.
// Data: { id, flavours = [{ key, label, image, needs = [{ label, count, have }], canBrew, most }], jars, seconds, times = { [runs] = seconds },
//         brewing = { label, left } | nil, ready = { label, count, image } | nil, canPickUp }

(function () {
    'use strict';

    function timeLeft(s) {
        const n = Math.max(0, Math.ceil(Number(s) || 0));
        return n >= 60 ? Math.floor(n / 60) + ' min ' + (n % 60) + ' s' : n + ' s';
    }

    if (typeof module === 'object' && module.exports) { module.exports = { timeLeft: timeLeft }; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st = null;
    const picked = {}; // flavour -> how many runs

    function post(action, extra) { st.api.post(action, Object.assign({ id: st.v.id }, extra || {})); }

    function render() {
        const v = st.v;
        st.body.innerHTML = '';
        if (v.ready) {
            st.body.appendChild(h('div', { class: 'wms-ready' },
                v.ready.image ? h('img', { src: v.ready.image, draggable: false }) : null,
                h('div', { class: 'wms-ready__text', text: v.ready.count + ' × ' + v.ready.label + ' ready' }),
                UI.button('Collect', () => post('collect'), 'primary')));
        } else if (v.brewing) {
            st.left = v.brewing.left;
            const txt = h('div', { class: 'wms-busy__text', text: 'Brewing ' + ((v.brewing.runs || 1) * v.jars) + '× ' + v.brewing.label + ': ' + timeLeft(st.left) + ' left' });
            st.busyText = txt;
            st.body.appendChild(h('div', { class: 'wms-busy' }, h('div', { class: 'wms-flame' }), txt));
        } else {
            st.body.appendChild(h('div', { class: 'wl-hint', text: 'Each run gives ' + v.jars + ' jars. Pick how many runs to brew at once (- / +); each extra run adds a little time.' }));
            const list = h('div', { class: 'wms-list' });
            v.flavours.forEach((f) => {
                const needs = h('div', { class: 'wms-needs' });
                const most = Math.max(1, f.most || 0);
                const runs = Math.max(1, Math.min(most, picked[f.key] || 1));
                f.needs.forEach((n) => needs.appendChild(h('span', { class: 'wms-need' + (n.have >= n.count * runs ? '' : ' is-short'),
                    text: (n.count * runs) + '× ' + n.label + ' (' + n.have + ')' })));
                const step = (d) => { picked[f.key] = Math.max(1, Math.min(most, runs + d)); render(); };
                const minus = UI.button('−', () => step(-1)); minus.disabled = runs <= 1;
                const plus = UI.button('+', () => step(1)); plus.disabled = runs >= most;
                const secs = (v.times && v.times[runs - 1]) || v.seconds * runs;
                const btn = UI.button('Brew ' + (runs * v.jars) + ' jars', () => post('brew', { flavour: f.key, runs: runs }), 'primary');
                btn.disabled = !f.canBrew;
                const qty = h('div', { class: 'wms-qty' }, minus, h('span', { class: 'wms-runs', text: runs + (runs === 1 ? ' run' : ' runs') }), plus);
                list.appendChild(h('div', { class: 'wms-row' + (f.canBrew ? '' : ' is-off') },
                    f.image ? h('img', { class: 'wms-img', src: f.image, draggable: false }) : h('span'),
                    h('div', {}, h('div', { class: 'wms-name', text: f.label }), needs,
                        h('div', { class: 'wms-time', text: timeLeft(secs) + (f.canBrew ? '' : ' · not enough to brew') })),
                    h('div', { class: 'wms-actions' }, qty, btn)));
            });
            st.body.appendChild(list);
        }
        st.pickup.style.display = v.canPickUp && !v.brewing && !v.ready ? '' : 'none';
    }

    function onKey(e) { if (e.key === 'Escape') st.api.post('close', {}); }

    UI.registerScreen('moonshineStill', {
        mount: function (el, data, api) {
            st = { api: api, v: data };
            st.body = h('div', { class: 'wms-body' });
            st.pickup = UI.button('Pick up still', () => post('pickup'));
            el.appendChild(h('div', { class: 'wl-panel wms-panel' },
                h('div', { class: 'wms-head' }, h('h1', { class: 'wl-title', text: 'Moonshine still' }), UI.button('✕', () => api.post('close', {}), 'icon')),
                st.body, h('div', { class: 'wms-foot' }, st.pickup)));
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            st.timer = setInterval(() => {
                if (st && st.v.brewing && st.busyText) {
                    st.left = Math.max(0, st.left - 1);
                    st.busyText.textContent = 'Brewing ' + ((st.v.brewing.runs || 1) * st.v.jars) + '× ' + st.v.brewing.label + ': ' + timeLeft(st.left) + ' left';
                    if (st.left <= 0) post('refresh');
                }
            }, 1000);
            render();
        },
        update: function (data) { st.v = data; render(); },
        unmount: function () { document.removeEventListener('keydown', onKey); if (st) clearInterval(st.timer); st = null; },
    });

    const CSS = [
        '.wms-panel { position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); width: min(620px, 94vw); max-height: 88vh; overflow-y: auto; }',
        '.wms-head { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }',
        '.wms-list { display: flex; flex-direction: column; gap: 8px; margin-top: 10px; }',
        '.wms-row { display: grid; grid-template-columns: 48px 1fr auto; gap: 12px; align-items: center; padding: 8px 10px; border-radius: 10px;',
        '  border: 1px solid rgba(214,186,140,0.12); background: linear-gradient(180deg, rgba(255,240,210,0.035), rgba(0,0,0,0.18)), rgba(10,10,9,0.55); }',
        '.wms-row.is-off { opacity: 0.6; }',
        '.wms-img { width: 44px; height: 44px; object-fit: contain; filter: drop-shadow(0 2px 3px rgba(0,0,0,0.6)); }',
        '.wms-name { font-weight: 700; margin-bottom: 4px; }',
        '.wms-needs { display: flex; flex-wrap: wrap; gap: 6px; }',
        '.wms-need { font-size: 11px; padding: 2px 7px; border-radius: 10px; background: rgba(127,174,90,0.15); color: #b9dd9a; }',
        '.wms-need.is-short { background: rgba(196,69,58,0.18); color: #ff9c90; }',
        '.wms-busy { display: flex; align-items: center; gap: 14px; padding: 18px; border-radius: 10px; background: rgba(10,10,9,0.55); }',
        '.wms-busy__text { font-size: 15px; }',
        '@keyframes wmsFlame { 0%, 100% { transform: scaleY(1); opacity: 0.9; } 50% { transform: scaleY(1.25); opacity: 1; } }',
        '.wms-flame { width: 22px; height: 30px; border-radius: 50% 50% 40% 40%; background: radial-gradient(circle at 50% 70%, #ffd36a, #e8732c 60%, #8a2a10);',
        '  box-shadow: 0 0 14px rgba(232,115,44,0.7); animation: wmsFlame 0.6s ease-in-out infinite; transform-origin: bottom; }',
        '.wms-ready { display: flex; align-items: center; gap: 14px; padding: 14px; border-radius: 10px; background: rgba(10,10,9,0.55);',
        '  border: 1px solid rgba(127,199,90,0.45); }',
        '.wms-ready img { width: 52px; height: 52px; object-fit: contain; }',
        '.wms-ready__text { flex: 1; font-weight: 700; }',
        '.wms-actions { display: flex; flex-direction: column; align-items: flex-end; gap: 6px; }',
        '.wms-qty { display: flex; align-items: center; gap: 6px; }',
        '.wms-qty button { min-width: 30px; padding: 2px 8px; }',
        '.wms-runs { min-width: 52px; text-align: center; font-weight: 700; }',
        '.wms-time { font-size: 11px; color: #9d958a; margin-top: 4px; }',
        '.wms-foot { display: flex; justify-content: flex-end; margin-top: 12px; }',
    ].join('\n');
})();
