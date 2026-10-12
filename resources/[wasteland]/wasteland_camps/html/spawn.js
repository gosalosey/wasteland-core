// wasteland_camps :: html/spawn.js
// Where to start: a new character picks one of the safe camps; a returning
// one can also go back to where they left ("last").
// Data: { camps = [{ id, label, traders?, last? }], returning }   Posts: choose { id }

(function () {
    'use strict';

    if (typeof module === 'object' && module.exports) { module.exports = {}; return; }

    const UI = window.WastelandUI;
    const h = UI.h;

    UI.registerScreen('spawnChoice', {
        mount: function (el, data, api) {
            let chosen = false;
            const list = h('div', { class: 'wsc-list' });
            (data.camps || []).forEach((c) => {
                const b = h('button', { class: 'wsc-camp', onclick: () => {
                    if (chosen) return;
                    chosen = true;
                    b.classList.add('is-chosen');
                    api.post('choose', { id: c.id });
                } },
                    h('span', { class: 'wsc-name', text: c.label }),
                    h('span', { class: 'wsc-info', text: c.last ? 'Where you logged out' : 'Safe zone · ' + c.traders + (c.traders === 1 ? ' trader' : ' traders') }));
                list.appendChild(b);
            });
            el.appendChild(h('div', { class: 'wsc-root' },
                h('div', { class: 'wl-panel wsc-panel' },
                    h('h1', { class: 'wl-title', text: data.returning ? 'Where do you wake up?' : 'Where do you start?' }),
                    h('div', { class: 'wl-hint', text: (data.returning ? 'Go back to where you left, or to a camp. ' : 'Pick a camp. ') +
                        'Camps are safe zones: no zombies, and traders who buy and sell. You cannot be hurt until you arrive.' }),
                    list)));
            el.appendChild(h('style', { text: CSS }));
        },
        unmount: function () {},
    });

    const CSS = [
        '.wsc-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; background: rgba(0,0,0,0.45); }',
        '.wsc-panel { width: min(520px, 92vw); display: flex; flex-direction: column; gap: 10px; }',
        '.wsc-list { display: flex; flex-direction: column; gap: 8px; margin-top: 6px; }',
        '.wsc-camp { display: flex; flex-direction: column; align-items: flex-start; gap: 2px; text-align: left; cursor: pointer;',
        '  background: var(--wl-bg-sunken); border: 1px solid var(--wl-border); border-radius: var(--wl-radius); padding: 12px 14px; color: var(--wl-text); }',
        '.wsc-camp:hover { border-color: var(--wl-accent); }',
        '.wsc-camp.is-chosen { border-color: var(--wl-accent); background: rgba(127,199,90,0.15); }',
        '.wsc-name { font-size: 16px; font-weight: 700; } .wsc-info { font-size: 12px; color: var(--wl-text-dim); }',
    ].join('\n');
})();
