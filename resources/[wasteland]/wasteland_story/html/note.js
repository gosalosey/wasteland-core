// wasteland_story :: html/note.js
// A note, log or recording found in the world, on old paper. Esc / click Close.
// Data: { title, text }

(function () {
    'use strict';
    if (typeof module === 'object' && module.exports) { module.exports = {}; return; }
    const UI = window.WastelandUI;
    const h = UI.h;
    let api = null;
    function onKey(e) { if (api && (e.key === 'Escape' || e.key === 'Backspace')) api.post('close'); }

    UI.registerScreen('storyNote', {
        mount: function (el, data, screenApi) {
            api = screenApi;
            const body = h('div', { class: 'wsn-text' });
            String(data.text || '').split('\n').forEach((p) => body.appendChild(h('p', { text: p })));
            el.appendChild(h('div', { class: 'wsn-shade' }));
            el.appendChild(h('div', { class: 'wsn-paper' },
                h('div', { class: 'wsn-title', text: data.title || '' }), body,
                h('button', { class: 'wsn-close', text: 'Close (Esc)', onclick: () => api.post('close') })));
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
        },
        unmount: function () { document.removeEventListener('keydown', onKey); api = null; },
    });

    const CSS = [
        '.wsn-shade { position: absolute; inset: 0; background: rgba(0,0,0,0.6); }',
        '.wsn-paper { position: absolute; left: 50%; top: 50%; transform: translate(-50%,-50%) rotate(-0.6deg); width: min(560px, 86vw);',
        '  max-height: 78vh; overflow: auto; padding: 30px 34px 20px; color: #2a2318; border-radius: 3px;',
        '  background: radial-gradient(circle at 30% 20%, #efe3c4, #d9c79d 70%, #c8b283); box-shadow: 0 20px 60px rgba(0,0,0,0.8);',
        '  font-family: "Courier New", Courier, monospace; animation: wsn-in 0.3s ease-out; }',
        '.wsn-title { font-weight: 700; font-size: 16px; border-bottom: 1px solid rgba(42,35,24,0.35); padding-bottom: 8px; margin-bottom: 12px; }',
        '.wsn-text p { margin: 0 0 10px; font-size: 14px; line-height: 1.5; min-height: 4px; }',
        '.wsn-close { display: block; margin: 14px 0 0 auto; background: #2a2318; color: #efe3c4; border: 0; border-radius: 3px; padding: 6px 14px; cursor: pointer; }',
        '@keyframes wsn-in { from { opacity: 0; transform: translate(-50%,-46%) rotate(-2deg); } }',
    ].join('\n');
})();
