// wasteland_story :: html/tracker.js
// Story tracker (right side): the act, the step, what to do, progress.
// Data: { title, chapter, objective, progress, done }

(function () {
    'use strict';
    if (typeof module === 'object' && module.exports) { module.exports = {}; return; }
    const UI = window.WastelandUI;
    const h = UI.h;
    let root = null;

    function render(d) {
        root.innerHTML = '';
        root.appendChild(h('div', { class: 'wst-title', text: (d.title || 'Story') + (d.done ? '  ·  complete' : '') }));
        if (d.chapter) root.appendChild(h('div', { class: 'wst-chapter', text: d.chapter }));
        if (d.objective) root.appendChild(h('div', { class: 'wst-obj', text: d.objective }));
        if (d.progress) root.appendChild(h('div', { class: 'wst-prog', text: d.progress }));
        root.appendChild(h('div', { class: 'wst-hint', text: '/journal' }));
    }

    UI.registerScreen('storyTracker', {
        mount: function (el, data) {
            root = h('div', { class: 'wst-root' });
            el.appendChild(root);
            el.appendChild(h('style', { text: CSS }));
            render(data);
        },
        update: function (d) { if (root && d) render(d); },
        unmount: function () { root = null; },
    });

    const CSS = [
        '.wst-root { position: absolute; right: 1.6vw; top: 34vh; width: 260px; pointer-events: none; color: #ece8da;',
        '  text-shadow: 0 1px 2px #000, 0 0 6px rgba(0,0,0,0.7); border-right: 3px solid rgba(214,178,60,0.8); padding-right: 10px; text-align: right; }',
        '.wst-title { font-size: 13px; font-weight: 700; letter-spacing: 0.12em; text-transform: uppercase; color: #e8c25a; }',
        '.wst-chapter { font-size: 12px; color: rgba(236,232,218,0.7); margin-top: 2px; }',
        '.wst-obj { font-size: 13px; line-height: 1.35; margin-top: 4px; }',
        '.wst-prog { font-size: 12px; font-weight: 700; color: #7fc75a; margin-top: 3px; }',
        '.wst-hint { font-size: 10px; color: rgba(236,232,218,0.35); margin-top: 3px; }',
    ].join('\n');
})();
