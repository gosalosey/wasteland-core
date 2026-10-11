// wasteland_tailor :: html/tailor.js
// Tailor screen: the pieces you wear, each with style and colour arrows. Every
// change shows on your character at once; Pay pays for the pieces changed.
// Data: { title, price, pieces = [{ slot, label, parts = [{ key, label, d, t, od, ot, maxD, maxT }] }] }
// Posts: set { slot, key, d, t }, turn, reset, buy { changes }, close
// Updates: { part = { slot, key, d, t, maxD, maxT } }, { message }

(function () {
    'use strict';

    // Pure helpers (unit-tested)
    // Step through 0..max, wrapping around.
    function step(value, delta, max) {
        const n = Math.max(0, max) + 1;
        return ((value + delta) % n + n) % n;
    }

    // Changed pieces as the server wants them: [{ slot, look = { key: [d, t] } }].
    function changes(pieces) {
        const out = [];
        (pieces || []).forEach((p) => {
            if (!p.parts.some((x) => x.d !== x.od || x.t !== x.ot)) return;
            const look = {};
            p.parts.forEach((x) => { look[x.key] = [x.d, x.t]; });
            out.push({ slot: p.slot, look: look });
        });
        return out;
    }

    if (typeof module === 'object' && module.exports) { module.exports = { step: step, changes: changes }; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st = null;

    function render() {
        st.body.innerHTML = '';
        st.pieces.forEach((p) => {
            const rows = p.parts.map((x) => {
                const arrows = (label, field, maxField) => h('div', { class: 'wlt-arrows' },
                    h('span', { class: 'wlt-what', text: label }),
                    UI.button('‹', () => change(p, x, field, -1, maxField)),
                    h('span', { class: 'wlt-num', text: (x[field] + 1) + ' / ' + (x[maxField] + 1) }),
                    UI.button('›', () => change(p, x, field, 1, maxField)));
                const changed = x.d !== x.od || x.t !== x.ot;
                return h('div', { class: 'wlt-part' + (changed ? ' is-changed' : '') },
                    h('div', { class: 'wlt-partname', text: x.label }), arrows('Style', 'd', 'maxD'), arrows('Colour', 't', 'maxT'));
            });
            st.body.appendChild(h('div', { class: 'wlt-piece' }, h('div', { class: 'wl-section-title', text: p.label }), ...rows));
        });
        const n = changes(st.pieces).length;
        st.pay.textContent = n ? 'Pay $' + (n * st.price) + ' (' + n + ' piece' + (n === 1 ? '' : 's') + ')' : 'Nothing changed';
        st.pay.disabled = n === 0;
    }

    function change(p, x, field, delta, maxField) {
        const next = { d: x.d, t: x.t };
        next[field] = step(x[field], delta, x[maxField]);
        if (field === 'd') next.t = 0; // a new style starts at its first colour
        st.api.post('set', { slot: p.slot, key: x.key, d: next.d, t: next.t });
    }

    function onKey(e) { if (st && e.key === 'Escape') st.api.post('close'); }

    UI.registerScreen('tailor', {
        mount: function (el, data, api) {
            st = { api: api, pieces: data.pieces || [], price: data.price || 0 };
            st.body = h('div', { class: 'wlt-body' });
            st.message = h('div', { class: 'wl-message' });
            st.pay = UI.button('Pay', () => api.post('buy', { changes: changes(st.pieces) }), 'primary');
            el.appendChild(h('div', { class: 'wlt-root' },
                h('div', { class: 'wl-panel wlt-panel' },
                    h('h1', { class: 'wl-title', text: data.title || 'Tailor' }),
                    h('div', { class: 'wl-hint', text: 'Restyle what you are wearing: $' + st.price + ' for each piece you change.' }),
                    st.body, st.message,
                    h('div', { class: 'wlt-views' }, h('span', { class: 'wlt-what', text: 'Camera' }),
                        ...[['full', 'Full body'], ['face', 'Face'], ['top', 'Top'], ['legs', 'Pants'], ['feet', 'Shoes']]
                            .map(([v, label]) => UI.button(label, () => api.post('view', { view: v })))),
                    h('div', { class: 'wl-hint', text: 'Drag outside this box to look around (left/right turns, up/down moves) · scroll to zoom' }),
                    h('div', { class: 'wlt-buttons' },
                        UI.button('Turn around', () => api.post('turn')),
                        UI.button('Undo all', () => {
                            st.pieces.forEach((p) => p.parts.forEach((x) => { x.d = x.od; x.t = x.ot; }));
                            api.post('reset'); render();
                        }),
                        st.pay, UI.button('Cancel', () => api.post('close'))))));
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            // Camera: drag on the free part of the screen, wheel to zoom. Moves
            // are summed and sent at most once a frame.
            const area = el.querySelector('.wlt-root');
            const panel = el.querySelector('.wlt-panel');
            let drag = null, pending = { dx: 0, dy: 0, zoom: 0 }, queued = false;
            const flush = () => {
                queued = false;
                if (!st || (!pending.dx && !pending.dy && !pending.zoom)) return;
                st.api.post('cam', pending);
                pending = { dx: 0, dy: 0, zoom: 0 };
            };
            const queue = () => { if (!queued) { queued = true; requestAnimationFrame(flush); } };
            area.addEventListener('mousedown', (e) => {
                if (panel.contains(e.target) || e.button !== 0) return;
                drag = { x: e.clientX, y: e.clientY };
                area.classList.add('is-dragging');
            });
            st.onMove = (e) => {
                if (!drag) return;
                pending.dx += e.clientX - drag.x; pending.dy -= e.clientY - drag.y;
                drag = { x: e.clientX, y: e.clientY };
                queue();
            };
            st.onUp = () => { drag = null; area.classList.remove('is-dragging'); };
            document.addEventListener('mousemove', st.onMove);
            document.addEventListener('mouseup', st.onUp);
            area.addEventListener('wheel', (e) => {
                if (panel.contains(e.target)) return;
                e.preventDefault();
                pending.zoom += e.deltaY > 0 ? 1 : -1;
                queue();
            }, { passive: false });
            render();
        },
        update: function (data) {
            if (data.part) {
                st.pieces.forEach((p) => {
                    if (p.slot !== data.part.slot) return;
                    p.parts.forEach((x) => {
                        if (x.key !== data.part.key) return;
                        x.d = data.part.d; x.t = data.part.t; x.maxD = data.part.maxD; x.maxT = data.part.maxT;
                    });
                });
                render();
            }
            if (data.message) { st.message.textContent = data.message; st.message.className = 'wl-message is-error'; }
        },
        unmount: function () {
            document.removeEventListener('keydown', onKey);
            if (st) { document.removeEventListener('mousemove', st.onMove); document.removeEventListener('mouseup', st.onUp); }
            st = null;
        },
    });

    const CSS = [
        '.wlt-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: flex-start; padding-left: 4vw; }',
        '.wlt-panel { width: min(420px, 92vw); max-height: 86vh; display: flex; flex-direction: column; gap: 8px; }',
        '.wlt-body { overflow-y: auto; display: flex; flex-direction: column; gap: 10px; padding-right: 4px; }',
        '.wlt-piece { display: flex; flex-direction: column; gap: 4px; }',
        '.wlt-part { background: var(--wl-bg-sunken); border: 1px solid var(--wl-border); border-radius: 5px; padding: 6px 8px; }',
        '.wlt-part.is-changed { border-color: var(--wl-accent); }',
        '.wlt-partname { font-size: 12px; color: var(--wl-text-dim); margin-bottom: 3px; }',
        '.wlt-arrows { display: flex; align-items: center; gap: 6px; margin: 2px 0; }',
        '.wlt-arrows .wl-btn { padding: 2px 10px; min-width: 0; }',
        '.wlt-what { width: 52px; font-size: 12px; }',
        '.wlt-num { min-width: 70px; text-align: center; font-variant-numeric: tabular-nums; font-size: 13px; }',
        '.wlt-buttons { display: flex; flex-wrap: wrap; gap: 6px; }',
        '.wlt-root { cursor: grab; } .wlt-root.is-dragging { cursor: grabbing; } .wlt-panel { cursor: default; }',
        '.wlt-views { display: flex; flex-wrap: wrap; align-items: center; gap: 4px; }',
        '.wlt-views .wl-btn { padding: 3px 9px; font-size: 12px; min-width: 0; }',
    ].join('\n');
})();
