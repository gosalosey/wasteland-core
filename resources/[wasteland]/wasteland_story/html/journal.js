// wasteland_story :: html/journal.js
// The journal (/journal): the act, its intro, every step done so far as a
// diary entry, what to do now, and the ending once reached. Esc closes.
// Data: { title, subtitle, intro, entries = { { title, text } }, current = { title, objective }, ending = { title, text } }

(function () {
    'use strict';
    if (typeof module === 'object' && module.exports) { module.exports = {}; return; }
    const UI = window.WastelandUI;
    const h = UI.h;
    let api = null;
    function onKey(e) { if (api && (e.key === 'Escape' || e.key === 'Backspace')) api.post('close'); }

    UI.registerScreen('storyJournal', {
        mount: function (el, d, screenApi) {
            api = screenApi;
            const list = h('div', { class: 'wsj-entries' });
            let n = 0;
            (d.entries || []).forEach((e) => {
                if (e.header) { n = 0; list.appendChild(h('div', { class: 'wsj-act', text: e.header })); return; }
                n += e.ending ? 0 : 1;
                list.appendChild(h('div', { class: 'wsj-entry' + (e.ending ? ' is-ending' : '') },
                    h('div', { class: 'wsj-entry__title', text: (e.ending ? '' : n + '. ') + e.title }), h('div', { class: 'wsj-entry__text', text: e.text })));
            });
            if (!(d.entries || []).length) list.appendChild(h('div', { class: 'wsj-empty', text: 'Nothing written yet.' }));
            const now = d.ending
                ? h('div', { class: 'wsj-now is-end' }, h('div', { class: 'wsj-now__k', text: 'Ending' }),
                    h('div', { class: 'wsj-now__t', text: d.ending.title }), h('div', { class: 'wsj-entry__text', text: d.ending.text }))
                : d.current ? h('div', { class: 'wsj-now' }, h('div', { class: 'wsj-now__k', text: 'Now' }),
                    h('div', { class: 'wsj-now__t', text: d.current.title }), h('div', { class: 'wsj-entry__text', text: d.current.objective })) : null;
            el.appendChild(h('div', { class: 'wsj-shade' }));
            el.appendChild(h('div', { class: 'wsj-book' },
                h('div', { class: 'wsj-head' }, h('div', { class: 'wsj-title', text: d.title || 'Journal' }), h('div', { class: 'wsj-sub', text: d.subtitle || '' })),
                h('div', { class: 'wsj-intro', text: d.intro || '' }), now, list,
                h('button', { class: 'wsj-close', text: 'Close (Esc)', onclick: () => api.post('close') })));
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
        },
        unmount: function () { document.removeEventListener('keydown', onKey); api = null; },
    });

    const CSS = [
        '.wsj-shade { position: absolute; inset: 0; background: rgba(0,0,0,0.65); }',
        '.wsj-book { position: absolute; left: 50%; top: 50%; transform: translate(-50%,-50%); width: min(680px, 90vw); max-height: 84vh; overflow: auto;',
        '  background: linear-gradient(180deg, #1a1c16, #0e0f0c); border: 1px solid rgba(214,178,60,0.45); border-radius: 10px; padding: 22px 26px;',
        '  color: #ece8da; box-shadow: 0 20px 60px rgba(0,0,0,0.8); }',
        '.wsj-head { border-bottom: 1px solid rgba(214,178,60,0.3); padding-bottom: 10px; margin-bottom: 10px; }',
        '.wsj-title { font-size: 26px; font-weight: 700; color: #e8c25a; letter-spacing: 0.06em; text-transform: uppercase; }',
        '.wsj-sub { font-size: 13px; color: rgba(236,232,218,0.6); font-style: italic; }',
        '.wsj-intro { font-family: Georgia, serif; font-size: 14px; color: rgba(236,232,218,0.75); margin-bottom: 12px; }',
        '.wsj-now { background: rgba(214,178,60,0.1); border-left: 3px solid #e8c25a; padding: 8px 12px; margin-bottom: 14px; border-radius: 4px; }',
        '.wsj-now.is-end { background: rgba(127,199,90,0.1); border-left-color: #7fc75a; }',
        '.wsj-now__k { font-size: 10px; letter-spacing: 0.14em; text-transform: uppercase; color: rgba(236,232,218,0.55); }',
        '.wsj-now__t { font-size: 16px; font-weight: 700; margin: 2px 0 4px; }',
        '.wsj-entries { display: flex; flex-direction: column; gap: 10px; }',
        '.wsj-entry__title { font-size: 14px; font-weight: 700; color: #d8cfae; }',
        '.wsj-entry__text { font-family: Georgia, serif; font-size: 14px; line-height: 1.5; color: rgba(236,232,218,0.85); }',
        '.wsj-empty { color: rgba(236,232,218,0.5); font-style: italic; }',
        '.wsj-act { margin-top: 8px; font-size: 12px; letter-spacing: 0.16em; text-transform: uppercase; color: #e8c25a;',
        '  border-bottom: 1px solid rgba(214,178,60,0.25); padding-bottom: 3px; }',
        '.wsj-entry.is-ending .wsj-entry__title { color: #7fc75a; }',
        '.wsj-close { display: block; margin: 16px 0 0 auto; background: rgba(214,178,60,0.15); color: #ece8da; border: 1px solid rgba(214,178,60,0.5);',
        '  border-radius: 5px; padding: 6px 14px; cursor: pointer; }',
    ].join('\n');
})();
