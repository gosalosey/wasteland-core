// wasteland_admin :: html/announce.js
// Announcement banner at the top of every player's screen (no input focus).

(function () {
    'use strict';

    if (typeof module === 'object' && module.exports) { module.exports = {}; return; }

    const UI = window.WastelandUI;
    const h = UI.h;

    UI.registerScreen('announce', {
        mount: function (el, data) {
            el.appendChild(h('div', { class: 'wlb-root' },
                h('div', { class: 'wlb-title', text: 'Announcement' }),
                h('div', { class: 'wlb-text', text: data.text }),
                h('div', { class: 'wl-hint', text: '– ' + data.by })));
            el.appendChild(h('style', { text: CSS }));
        },
        update: function () {},
        unmount: function () {},
    });

    const CSS = [
        '.wlb-root { position: absolute; top: 4vh; left: 50%; transform: translateX(-50%); max-width: 640px; text-align: center;',
        '  background: var(--wl-bg); border: 1px solid var(--wl-accent); border-radius: var(--wl-radius); padding: 14px 22px;',
        '  box-shadow: 0 12px 40px rgba(0,0,0,0.6); animation: wlbIn 0.4s ease; }',
        '.wlb-title { font-size: 11px; letter-spacing: 0.14em; text-transform: uppercase; color: var(--wl-accent); margin-bottom: 4px; }',
        '.wlb-text { font-size: 17px; margin-bottom: 4px; white-space: pre-wrap; }',
        '@keyframes wlbIn { from { opacity: 0; transform: translate(-50%, -10px); } to { opacity: 1; transform: translate(-50%, 0); } }',
    ].join('\n');
})();
