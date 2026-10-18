// wasteland_camps :: html/stuck.js
// /stuck: go to the nearest safe camp after standing still for a few seconds.
// Data: { info = { camp, distance, wait, cooldown } }   Updates: { counting = seconds | false, message }
// Posts: start, cancel, close
(function () {
    'use strict';

    // Pure helper (unit-tested): "1.4 km" / "350 m"
    function distanceText(m) {
        m = Math.max(0, Math.round(m || 0));
        return m >= 1000 ? (m / 1000).toFixed(1) + ' km' : m + ' m';
    }
    function cooldownText(s) {
        s = Math.max(0, Math.ceil(s || 0));
        const min = Math.floor(s / 60);
        return min > 0 ? min + ' min ' + (s % 60) + ' s' : s + ' s';
    }

    if (typeof module === 'object' && module.exports) { module.exports = { distanceText: distanceText, cooldownText: cooldownText }; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st = null;

    function render() {
        const i = st.info || {};
        st.body.textContent = '';
        if (!i.camp) {
            st.body.appendChild(h('div', { class: 'wl-hint', text: 'There is no safe camp to go to.' }));
            st.body.appendChild(h('div', { class: 'wsk2-row' }, UI.button('Close', () => st.api.post('close'))));
            return;
        }
        st.body.appendChild(h('div', { class: 'wsk2-camp', text: i.camp }));
        st.body.appendChild(h('div', { class: 'wl-hint', text: distanceText(i.distance) + ' away. The nearest safe zone.' }));
        if (i.cooldown > 0) {
            st.body.appendChild(h('div', { class: 'wsk2-warn', text: 'You can use this again in ' + cooldownText(i.cooldown) + '.' }));
            st.body.appendChild(h('div', { class: 'wsk2-row' }, UI.button('Close', () => st.api.post('close'))));
            return;
        }
        if (st.counting !== false && st.counting !== undefined) {
            st.body.appendChild(h('div', { class: 'wsk2-count', text: String(st.counting) }));
            st.body.appendChild(h('div', { class: 'wl-hint', text: 'Stand still. Moving, getting hurt or getting into a vehicle cancels it.' }));
            st.body.appendChild(h('div', { class: 'wsk2-row' }, UI.button('Cancel', () => st.api.post('cancel'))));
            return;
        }
        st.body.appendChild(h('div', { class: 'wl-hint', text: 'Stand still for ' + i.wait + ' seconds and you are taken there. ' +
            'You can do this once every ' + Math.round((i.every || 0) / 60) + ' minutes.' }));
        st.body.appendChild(h('div', { class: 'wsk2-row' },
            UI.button('Teleport', () => st.api.post('start'), 'primary'),
            UI.button('Close', () => st.api.post('close'))));
    }

    function onKey(e) { if (st && e.key === 'Escape') st.api.post(st.counting ? 'cancel' : 'close'); }

    const CSS = [
        '.wsk2-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }',
        '.wsk2-panel { width: min(420px, 92vw); display: flex; flex-direction: column; gap: 10px; }',
        '.wsk2-camp { font-size: 22px; font-weight: 700; color: var(--wl-accent); }',
        '.wsk2-count { font-size: 56px; font-weight: 800; text-align: center; color: var(--wl-accent); }',
        '.wsk2-warn { color: #e0b24f; }',
        '.wsk2-row { display: flex; gap: 8px; justify-content: flex-end; }',
        '.wsk2-msg { min-height: 1em; font-size: 13px; color: #e0533f; }',
    ].join('\n');

    UI.registerScreen('stuckScreen', {
        mount: function (el, data, api) {
            st = { api: api, info: data.info, counting: false };
            st.body = h('div', { class: 'wsk2-body' });
            st.msg = h('div', { class: 'wsk2-msg' });
            el.appendChild(h('div', { class: 'wsk2-root' },
                h('div', { class: 'wl-panel wsk2-panel' },
                    h('h1', { class: 'wl-title', text: 'Stuck?' }), st.body, st.msg)));
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            render();
        },
        update: function (data) {
            if (data.info) st.info = data.info;
            if (data.counting !== undefined) st.counting = data.counting;
            if (data.message !== undefined) st.msg.textContent = data.message;
            render();
        },
        unmount: function () { document.removeEventListener('keydown', onKey); st = null; },
    });
})();
