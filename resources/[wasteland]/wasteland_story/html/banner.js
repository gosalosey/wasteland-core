// wasteland_story :: html/banner.js
// A title card in the top middle: a new story, "Journal updated", an ending.
// Data: { kicker, title, subtitle, text, small }

(function () {
    'use strict';
    if (typeof module === 'object' && module.exports) { module.exports = {}; return; }
    const UI = window.WastelandUI;
    const h = UI.h;

    UI.registerScreen('storyBanner', {
        mount: function (el, d) {
            el.appendChild(h('div', { class: 'wsb-root' + (d.small ? ' is-small' : '') },
                h('div', { class: 'wsb-kicker', text: d.kicker || '' }), h('div', { class: 'wsb-title', text: d.title || '' }),
                d.subtitle ? h('div', { class: 'wsb-sub', text: d.subtitle }) : null,
                d.text ? h('div', { class: 'wsb-text', text: d.text }) : null));
            el.appendChild(h('style', { text: CSS }));
        },
        unmount: function () {},
    });

    const CSS = [
        '.wsb-root { position: absolute; left: 50%; top: 12vh; transform: translateX(-50%); text-align: center; pointer-events: none; width: min(760px, 86vw);',
        '  color: #ece8da; text-shadow: 0 2px 4px #000, 0 0 18px rgba(0,0,0,0.8); animation: wsb-life 6.4s ease forwards; }',
        '.wsb-kicker { font-size: 12px; letter-spacing: 0.3em; text-transform: uppercase; color: #e8c25a; }',
        '.wsb-title { font-size: 44px; font-weight: 800; letter-spacing: 0.06em; text-transform: uppercase; margin: 4px 0; }',
        '.wsb-root.is-small .wsb-title { font-size: 26px; }',
        '.wsb-sub { font-size: 15px; font-style: italic; color: rgba(236,232,218,0.8); }',
        '.wsb-text { font-family: Georgia, serif; font-size: 15px; margin-top: 10px; color: rgba(236,232,218,0.85); }',
        '@keyframes wsb-life { 0% { opacity: 0; transform: translate(-50%, -12px); } 8% { opacity: 1; transform: translate(-50%, 0); }',
        '  85% { opacity: 1; } 100% { opacity: 0; } }',
    ].join('\n');
})();
