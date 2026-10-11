// wasteland_survival :: html/death.js
// "You died" screen with a countdown and the Respawn button. The server
// enforces the delay; the countdown only shows it.

(function () {
    'use strict';

    if (typeof module === 'object' && module.exports) { module.exports = {}; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let timer = null;

    UI.registerScreen('death', {
        mount: function (el, data, api) {
            let left = Math.max(0, Math.floor(data.respawnSeconds || 0));
            const button = UI.button('Respawn', () => { button.disabled = true; api.post('respawn'); }, 'primary');
            const count = h('div', { class: 'wld-count' });
            const tickDown = () => {
                if (left > 0) {
                    count.textContent = 'You can respawn in ' + left + ' s';
                    button.disabled = true;
                    left -= 1;
                } else {
                    count.textContent = '';
                    button.disabled = false;
                }
            };
            tickDown();
            timer = setInterval(tickDown, 1000);
            el.appendChild(h('div', { class: 'wld-root' },
                h('div', { class: 'wld-title', text: 'You died' }),
                h('p', { class: 'wld-text', text: 'Everything you carried is in a body bag where you fell. It is marked on your map; items on your hotbar stay with you.' }),
                count, button));
            el.appendChild(h('style', { text: CSS }));
        },
        update: function () {},
        unmount: function () { clearInterval(timer); timer = null; },
    });

    const CSS = [
        '.wld-root { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 16px;',
        '  background: radial-gradient(ellipse at center, rgba(40,0,0,0.35) 0%, rgba(0,0,0,0.85) 100%); }',
        '.wld-title { font-family: var(--wl-font-display); font-size: 64px; letter-spacing: 0.2em; text-transform: uppercase; color: #c4453a; text-shadow: 0 4px 24px #000; }',
        '.wld-text { max-width: 520px; text-align: center; color: var(--wl-text-dim); margin: 0; }',
        '.wld-count { min-height: 20px; color: var(--wl-text); font-variant-numeric: tabular-nums; }',
    ].join('\n');
})();
