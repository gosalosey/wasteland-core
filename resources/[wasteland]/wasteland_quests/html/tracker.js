// wasteland_quests :: html/tracker.js
// Quest tracker on the right side of the screen (no input focus).
// Data: { quests = [{ label, ready, objectives = [{ text, done }] }] }

(function () {
    'use strict';

    if (typeof module === 'object' && module.exports) { module.exports = {}; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let root;

    function render(data) {
        root.innerHTML = '';
        (data.quests || []).forEach((q) => {
            const box = h('div', { class: 'wqt-quest' + (q.ready ? ' is-ready' : '') },
                h('div', { class: 'wqt-name', text: q.label + (q.ready ? ' - hand in at camp' : '') }));
            (q.objectives || []).forEach((o) => box.appendChild(h('div', { class: 'wqt-obj' + (o.done ? ' is-done' : ''),
                text: (o.done ? '✓ ' : '• ') + o.text })));
            root.appendChild(box);
        });
    }

    UI.registerScreen('questTracker', {
        mount: function (el, data) {
            root = h('div', { class: 'wqt-root' });
            el.appendChild(root);
            el.appendChild(h('style', { text: CSS }));
            render(data);
        },
        update: render,
        unmount: function () { root = null; },
    });

    const CSS = [
        '.wqt-root { position: absolute; right: 1.6vw; top: 30vh; width: 260px; display: flex; flex-direction: column; gap: 8px; pointer-events: none; }',
        '.wqt-quest { background: rgba(10,14,9,0.55); border-left: 2px solid #d6b23c; border-radius: 3px; padding: 6px 9px; }',
        '.wqt-quest.is-ready { border-left-color: #7fc75a; }',
        '.wqt-name { font-size: 13px; font-weight: 600; color: #f0e6c8; text-shadow: 0 1px 2px #000; margin-bottom: 2px; }',
        '.wqt-obj { font-size: 12px; color: #d8d8cc; text-shadow: 0 1px 2px #000; }',
        '.wqt-obj.is-done { color: #9be27a; }',
    ].join('\n');
})();
