// wasteland_quests :: html/tracker.js
// Quest tracker on the right side of the screen (no input focus): each job,
// how long ago it was taken, its objectives, how to do the next one, and
// once done, the camp to hand it in at and how far that is.
// Data: { quests = [{ label, ready, ago, handIn = { label, metres }, objectives = [{ text, done, how }] }] }

(function () {
    'use strict';

    // Pure helper (unit-tested with Node): "340 m" / "1.2 km".
    function distance(m) {
        if (m == null) return '';
        return m < 1000 ? Math.round(m) + ' m' : (m / 1000).toFixed(1) + ' km';
    }

    if (typeof module === 'object' && module.exports) { module.exports = { distance: distance }; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let root;

    function render(data) {
        root.innerHTML = '';
        (data.quests || []).forEach((q) => {
            const box = h('div', { class: 'wqt-quest' + (q.ready ? ' is-ready' : '') },
                h('div', { class: 'wqt-head' }, h('span', { class: 'wqt-name', text: q.label }),
                    q.ago ? h('span', { class: 'wqt-ago', text: q.ago === 'just now' ? 'just taken' : q.ago + ' ago' }) : null));
            const objs = q.objectives || [];
            const next = objs.findIndex((o) => !o.done);
            objs.forEach((o, i) => {
                box.appendChild(h('div', { class: 'wqt-obj' + (o.done ? ' is-done' : ''), text: (o.done ? '✓ ' : '• ') + o.text }));
                if (i === next && o.how) box.appendChild(h('div', { class: 'wqt-how', text: o.how }));
            });
            if (q.ready) {
                box.appendChild(h('div', { class: 'wqt-hand', text: q.handIn
                    ? 'Hand in at ' + q.handIn.label + ' · ' + distance(q.handIn.metres)
                    : 'Hand in at a camp' }));
            }
            root.appendChild(box);
        });
        if ((data.quests || []).length) root.appendChild(h('div', { class: 'wqt-foot', text: 'J or /quest for details' }));
    }

    // The story tracker sits on the same side: when it is shown, go below it
    // (it changes height with its text, so look again every half second).
    let timer = null;
    function place() {
        if (!root) return;
        const story = document.querySelector('.wst-root');
        const r = story && story.offsetParent !== null ? story.getBoundingClientRect() : null;
        root.style.top = r && r.height > 0 ? Math.max(r.bottom + 14, window.innerHeight * 0.3) + 'px' : '';
    }

    UI.registerScreen('questTracker', {
        mount: function (el, data) {
            root = h('div', { class: 'wqt-root' });
            el.appendChild(root);
            el.appendChild(h('style', { text: CSS }));
            render(data);
            place();
            timer = setInterval(place, 500);
        },
        update: function (data) { render(data); place(); },
        unmount: function () { if (timer) clearInterval(timer); timer = null; root = null; },
    });

    const CSS = [
        '.wqt-root { position: absolute; right: 1.6vw; top: 30vh; width: 270px; max-height: 68vh; overflow: hidden; display: flex; flex-direction: column; gap: 8px; pointer-events: none; }',
        '.wqt-quest { background: rgba(10,14,9,0.6); border-left: 2px solid #d6b23c; border-radius: 3px; padding: 6px 9px; }',
        '.wqt-quest.is-ready { border-left-color: #7fc75a; }',
        '.wqt-head { display: flex; justify-content: space-between; align-items: baseline; gap: 6px; margin-bottom: 2px; }',
        '.wqt-name { font-size: 13px; font-weight: 600; color: #f0e6c8; text-shadow: 0 1px 2px #000; }',
        '.wqt-ago { font-size: 10px; color: rgba(216,216,204,0.6); white-space: nowrap; }',
        '.wqt-obj { font-size: 12px; color: #d8d8cc; text-shadow: 0 1px 2px #000; }',
        '.wqt-obj.is-done { color: #9be27a; }',
        '.wqt-how { font-size: 11px; color: rgba(216,216,204,0.7); font-style: italic; margin: 1px 0 2px 10px; text-shadow: 0 1px 2px #000; }',
        '.wqt-hand { font-size: 12px; color: #9be27a; font-weight: 600; margin-top: 3px; text-shadow: 0 1px 2px #000; }',
        '.wqt-foot { font-size: 10px; color: rgba(216,216,204,0.5); text-align: right; text-shadow: 0 1px 2px #000; }',
    ].join('\n');
})();
