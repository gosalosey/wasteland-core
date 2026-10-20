// wasteland_farming :: html/farm.js
// A farm plot: its spots in a grid (what grows, how far along, time until
// harvest), the plot's water, and actions: plant (pick a seed), water,
// harvest, pull up, pick the plot up. Esc closes.
// Data: { id, label, size, slots = [{ crop, label, stage, minutesLeft, progress, image } | false],
//         seeds = [{ crop, label, count, minutes, image }], water, maxWater, waterPerBottle,
//         bottles, waterLabel, outdoors, raining, canPickUp }
// Posts: plant { id, slot, crop }, water { id }, harvest { id, slot }, pull { id, slot }, pickup { id }, close

(function () {
    'use strict';

    // Pure helpers (unit-tested)
    function timeText(minutes) {
        const m = Math.max(0, Math.ceil(Number(minutes) || 0));
        if (m <= 0) return 'Ready to harvest';
        if (m < 60) return m + ' min of watered growing left';
        const h = Math.floor(m / 60), r = m % 60;
        return h + ' h ' + (r ? r + ' min ' : '') + 'of watered growing left';
    }
    function waterText(v) {
        if (v.outdoors && v.raining) return 'Raining: the soil waters itself';
        const w = Math.max(0, Math.round(v.water || 0));
        if (w <= 0) return 'Dry: plants do not grow';
        return w < 60 ? w + ' min of water' : Math.floor(w / 60) + ' h ' + (w % 60) + ' min of water';
    }
    const STAGES = { sprout: 'Sprout', young: 'Young plant', grown: 'Grown', ripe: 'Ripe' };

    if (typeof module === 'object' && module.exports) { module.exports = { timeText: timeText, waterText: waterText }; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st = null;

    function post(action, extra) { st.api.post(action, Object.assign({ id: st.v.id }, extra || {})); }

    function spotCard(i, s) {
        if (!s) {
            const card = h('div', { class: 'wfm-spot is-empty' + (st.pick === i ? ' is-picking' : '') },
                h('div', { class: 'wfm-spot__title', text: 'Empty spot' }));
            if (st.pick === i) {
                if (!st.v.seeds.length) card.appendChild(h('div', { class: 'wl-hint', text: 'You have no seeds. Find them while looting or buy them from traders.' }));
                const list = h('div', { class: 'wfm-seeds' });
                st.v.seeds.forEach((sd) => {
                    const b = h('button', { class: 'wfm-seed', attrs: { title: sd.minutes + ' min to grow' },
                        onclick: () => { st.pick = null; post('plant', { slot: i, crop: sd.crop }); } });
                    if (sd.image) b.appendChild(h('img', { src: sd.image, draggable: false }));
                    b.appendChild(h('span', { text: sd.label + ' ×' + sd.count }));
                    list.appendChild(b);
                });
                card.appendChild(list);
                card.appendChild(UI.button('Cancel', () => { st.pick = null; render(); }));
            } else {
                card.appendChild(UI.button('Plant', () => { st.pick = i; render(); }, 'primary'));
            }
            return card;
        }
        const ripe = s.stage === 'ripe';
        const bar = h('div', { class: 'wfm-bar' }, h('div', { class: 'wfm-bar__fill' + (ripe ? ' is-ripe' : '') }));
        bar.firstChild.style.width = Math.min(100, s.progress) + '%';
        const card = h('div', { class: 'wfm-spot' + (ripe ? ' is-ripe' : '') },
            h('div', { class: 'wfm-spot__head' },
                s.image ? h('img', { class: 'wfm-spot__img', src: s.image, draggable: false }) : null,
                h('div', {}, h('div', { class: 'wfm-spot__title', text: s.label }), h('div', { class: 'wfm-spot__stage', text: STAGES[s.stage] || s.stage }))),
            bar,
            h('div', { class: 'wfm-spot__time' + (ripe ? ' is-ripe' : ''), text: timeText(s.minutesLeft) }));
        const row = h('div', { class: 'wfm-spot__row' });
        if (ripe) row.appendChild(UI.button('Harvest', () => post('harvest', { slot: i }), 'primary'));
        row.appendChild(UI.button('Pull up', () => post('pull', { slot: i }), 'danger'));
        card.appendChild(row);
        return card;
    }

    function render() {
        const v = st.v;
        st.title.textContent = v.label;
        st.water.textContent = waterText(v);
        st.waterFill.style.width = Math.min(100, (v.water / v.maxWater) * 100) + '%';
        st.waterFill.classList.toggle('is-rain', !!(v.outdoors && v.raining));
        st.place.textContent = v.outdoors ? 'Outdoors: rain waters it' : 'Under a roof: water it by hand';
        st.waterBtn.disabled = v.bottles < 1;
        st.waterBtn.textContent = 'Water (' + v.bottles + ' × ' + v.waterLabel + ', +' + v.waterPerBottle + ' min)';
        st.grid.innerHTML = '';
        st.grid.style.gridTemplateColumns = 'repeat(' + Math.min(v.size, 3) + ', 1fr)';
        for (let i = 1; i <= v.size * v.size; i++) st.grid.appendChild(spotCard(i, v.slots[i - 1]));
        st.pickupBtn.style.display = v.canPickUp ? '' : 'none';
    }

    function onKey(e) { if (e.key === 'Escape') st.api.post('close', {}); }

    UI.registerScreen('farmPlot', {
        mount: function (el, data, api) {
            st = { api: api, v: data, pick: null };
            st.title = h('h1', { class: 'wl-title' });
            st.water = h('span', { class: 'wfm-water__text' });
            st.waterFill = h('div', { class: 'wfm-water__fill' });
            st.place = h('span', { class: 'wfm-place' });
            st.waterBtn = UI.button('Water', () => post('water'));
            st.grid = h('div', { class: 'wfm-grid' });
            st.pickupBtn = UI.button('Pick up plot', () => post('pickup'));
            el.appendChild(h('div', { class: 'wl-panel wfm-panel' },
                h('div', { class: 'wfm-head' }, st.title, UI.button('✕', () => api.post('close', {}), 'icon')),
                h('div', { class: 'wfm-water' },
                    h('div', { class: 'wfm-water__row' }, h('span', { class: 'wfm-water__label', text: 'WATER' }), st.water, st.place),
                    h('div', { class: 'wfm-water__track' }, st.waterFill),
                    h('div', { class: 'wfm-water__row' }, st.waterBtn)),
                st.grid,
                h('div', { class: 'wfm-foot' }, h('span', { class: 'wl-hint', text: 'Plants only grow while the soil is wet.' }), st.pickupBtn)));
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            render();
        },
        update: function (data) { st.v = data; render(); },
        unmount: function () { document.removeEventListener('keydown', onKey); st = null; },
    });

    const CSS = [
        '.wfm-panel { position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); width: min(760px, 94vw); max-height: 90vh; overflow-y: auto; }',
        '.wfm-head { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; }',
        '.wfm-water { padding: 10px 12px; border-radius: 10px; border: 1px solid rgba(214,186,140,0.12); background: rgba(10,10,9,0.5); margin-bottom: 12px; }',
        '.wfm-water__row { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }',
        '.wfm-water__label { font-size: 11px; font-weight: 700; letter-spacing: 0.14em; color: #5fb4d6; }',
        '.wfm-water__text { font-size: 13px; }',
        '.wfm-place { margin-left: auto; font-size: 12px; color: var(--wl-text-dim); }',
        '.wfm-water__track { height: 8px; border-radius: 5px; background: rgba(0,0,0,0.5); margin: 8px 0; overflow: hidden; box-shadow: inset 0 1px 3px rgba(0,0,0,0.6); }',
        '.wfm-water__fill { height: 100%; background: linear-gradient(90deg, #2f7fa6, #5fb4d6); box-shadow: 0 0 8px rgba(95,180,214,0.5); transition: width 0.3s; }',
        '.wfm-water__fill.is-rain { background: repeating-linear-gradient(115deg, #5fb4d6 0 6px, #3d93ba 6px 12px); }',
        '.wfm-grid { display: grid; gap: 10px; }',
        '.wfm-spot { padding: 10px; border-radius: 10px; border: 1px solid rgba(214,186,140,0.12);',
        '  background: linear-gradient(180deg, rgba(255,240,210,0.035), rgba(0,0,0,0.18)), rgba(10,10,9,0.55); display: flex; flex-direction: column; gap: 8px; }',
        '.wfm-spot.is-ripe { border-color: rgba(127,199,90,0.55); box-shadow: 0 0 14px rgba(127,199,90,0.15); }',
        '.wfm-spot.is-empty { border-style: dashed; align-items: flex-start; }',
        '.wfm-spot__head { display: flex; gap: 10px; align-items: center; }',
        '.wfm-spot__img { width: 40px; height: 40px; object-fit: contain; filter: drop-shadow(0 2px 3px rgba(0,0,0,0.6)); }',
        '.wfm-spot__title { font-weight: 700; font-size: 14px; }',
        '.wfm-spot__stage { font-size: 12px; color: var(--wl-text-dim); }',
        '.wfm-spot__time { font-size: 12px; color: var(--wl-text-dim); }',
        '.wfm-spot__time.is-ripe { color: #8fd36a; font-weight: 700; }',
        '.wfm-spot__row { display: flex; gap: 6px; }',
        '.wfm-spot__row .wl-btn { padding: 5px 12px; font-size: 12px; }',
        '.wfm-bar { height: 7px; border-radius: 4px; background: rgba(0,0,0,0.5); overflow: hidden; }',
        '.wfm-bar__fill { height: 100%; background: linear-gradient(90deg, #6f9a3a, #9bcf5a); transition: width 0.3s; }',
        '.wfm-bar__fill.is-ripe { background: linear-gradient(90deg, #8fd36a, #c6f08a); box-shadow: 0 0 8px rgba(143,211,106,0.6); }',
        '.wfm-seeds { display: flex; flex-wrap: wrap; gap: 6px; }',
        '.wfm-seed { font: inherit; font-size: 12px; color: var(--wl-text); display: flex; align-items: center; gap: 6px; padding: 4px 8px; cursor: pointer;',
        '  border-radius: 8px; border: 1px solid rgba(214,186,140,0.18); background: rgba(10,10,9,0.6); }',
        '.wfm-seed:hover { border-color: var(--wl-accent); }',
        '.wfm-seed img { width: 24px; height: 24px; object-fit: contain; }',
        '.wfm-foot { display: flex; justify-content: space-between; align-items: center; margin-top: 12px; }',
    ].join('\n');
})();
