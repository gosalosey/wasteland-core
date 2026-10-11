// wasteland_loot :: html/progress.js
// Search progress bar (bottom middle, above the stamina bar).
// Data: { label, seconds }

(function () {
    'use strict';

    if (typeof module === 'object' && module.exports) { module.exports = {}; return; }

    const UI = window.WastelandUI;
    const h = UI.h;

    UI.registerScreen('lootProgress', {
        mount: function (el, data) {
            const fill = h('div', { class: 'wlp-fill' });
            el.appendChild(h('div', { class: 'wlp-root' },
                h('div', { class: 'wlp-label', text: data.label || 'Searching' }),
                h('div', { class: 'wlp-track' }, fill),
                h('div', { class: 'wlp-hint', text: 'Move or press X to cancel' })));
            el.appendChild(h('style', { text: CSS }));
            const ms = Math.max(200, (Number(data.seconds) || 3) * 1000);
            fill.style.transition = 'width ' + ms + 'ms linear';
            requestAnimationFrame(() => requestAnimationFrame(() => { fill.style.width = '100%'; }));
        },
        unmount: function () {},
    });

    const CSS = [
        '.wlp-root { position: absolute; left: 50%; bottom: 12vh; transform: translateX(-50%); width: 260px; text-align: center; pointer-events: none; }',
        '.wlp-label { font-size: 13px; color: #e6e6dc; text-shadow: 0 1px 2px #000; margin-bottom: 5px; }',
        '.wlp-track { height: 6px; background: rgba(10,14,9,0.7); border: 1px solid rgba(127,199,90,0.4); border-radius: 3px; overflow: hidden; }',
        '.wlp-fill { height: 100%; width: 0; background: #7fc75a; box-shadow: 0 0 6px rgba(127,199,90,0.6); }',
        '.wlp-hint { font-size: 10px; color: rgba(230,230,220,0.55); margin-top: 4px; text-shadow: 0 1px 2px #000; }',
    ].join('\n');
})();
