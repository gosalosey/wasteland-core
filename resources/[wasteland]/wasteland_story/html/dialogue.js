// wasteland_story :: html/dialogue.js
// A conversation: letterbox bars, the speaker, lines typed out one at a time
// (click / Space / E to go on), then the choices (click or 1-4). The server's
// answer to a choice arrives as an update { reply, keep, done }.
// Data: { npc, role, lines = { { who, text } }, choices = { { id, text, needs } } }

(function () {
    'use strict';

    // Pure helpers (unit-tested with Node)
    function typed(text, ms, cps) { return String(text || '').slice(0, Math.max(0, Math.floor(ms / 1000 * (cps || 45)))); }
    const helpers = { typed: typed };
    if (typeof module === 'object' && module.exports) { module.exports = helpers; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st = null;

    function showLine() {
        const l = st.lines[st.i];
        st.who.textContent = l.who || st.data.npc;
        st.full = l.text || '';
        st.started = performance.now();
        st.text.textContent = '';
        st.hint.textContent = st.i < st.lines.length - 1 ? 'Click / Space: next' : 'Click / Space: answer';
        st.choices.innerHTML = '';
        tick();
    }

    function tick() {
        if (!st) return;
        const t = typed(st.full, performance.now() - st.started);
        st.text.textContent = t;
        if (t.length < st.full.length) st.raf = requestAnimationFrame(tick);
    }

    function showChoices() {
        st.phase = 'choose';
        st.hint.textContent = 'Choose: click or press 1-' + st.data.choices.length;
        st.choices.innerHTML = '';
        st.data.choices.forEach((c, i) => {
            const b = h('button', { class: 'wsd-choice', onclick: () => pick(c.id) },
                h('span', { class: 'wsd-num', text: String(i + 1) }), h('span', { text: c.text }));
            if (c.needs) b.appendChild(h('span', { class: 'wsd-needs', text: 'Needs ' + c.needs }));
            st.choices.appendChild(b);
        });
    }

    function pick(id) {
        if (!st || st.phase !== 'choose') return;
        st.phase = 'wait';
        st.api.post('choose', { id: id });
    }

    function next() {
        if (!st) return;
        if (st.phase === 'reply') { st.api.post('close'); return; }
        if (st.phase !== 'lines') return;
        if (st.text.textContent.length < st.full.length) { cancelAnimationFrame(st.raf); st.text.textContent = st.full; return; }
        if (st.i < st.lines.length - 1) { st.i += 1; showLine(); } else showChoices();
    }

    function onKey(e) {
        if (!st) return;
        if (e.key === 'Escape') { st.api.post('close'); return; }
        if (e.key === ' ' || e.key === 'e' || e.key === 'E' || e.key === 'Enter') { e.preventDefault(); next(); return; }
        const n = Number(e.key);
        if (st.phase === 'choose' && n >= 1 && n <= st.data.choices.length) pick(st.data.choices[n - 1].id);
    }

    UI.registerScreen('storyDialogue', {
        mount: function (el, data, api) {
            st = { api: api, data: data, lines: (data.lines && data.lines.length) ? data.lines : [{ who: data.npc, text: '...' }], i: 0, phase: 'lines' };
            st.who = h('div', { class: 'wsd-who' });
            st.text = h('div', { class: 'wsd-text' });
            st.hint = h('div', { class: 'wsd-hint' });
            st.choices = h('div', { class: 'wsd-choices' });
            const panel = h('div', { class: 'wsd-panel' },
                h('div', { class: 'wsd-head' }, st.who, h('div', { class: 'wsd-role', text: data.role || '' })),
                st.text, st.choices, st.hint);
            panel.addEventListener('click', (e) => { if (!e.target.closest('.wsd-choice')) next(); });
            el.appendChild(h('div', { class: 'wsd-bar wsd-bar--top' }));
            el.appendChild(h('div', { class: 'wsd-bar wsd-bar--bottom' }));
            el.appendChild(panel);
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            showLine();
        },
        update: function (d) {
            if (!st || !d) return;
            if (d.keep) {   // refused (missing items, full pockets): say why, choose again
                st.phase = 'choose';
                st.hint.textContent = d.reply || '';
                st.hint.classList.add('is-warn');
                return;
            }
            st.phase = 'reply';
            st.choices.innerHTML = '';
            st.full = d.reply || '';
            st.started = performance.now();
            st.hint.classList.remove('is-warn');
            st.hint.textContent = 'Click / Space: close';
            tick();
        },
        unmount: function () {
            document.removeEventListener('keydown', onKey);
            if (st) cancelAnimationFrame(st.raf);
            st = null;
        },
    });

    const CSS = [
        '.wsd-bar { position: absolute; left: 0; right: 0; height: 9vh; background: #000; animation: wsd-in 0.4s ease-out; }',
        '.wsd-bar--top { top: 0; } .wsd-bar--bottom { bottom: 0; }',
        '.wsd-panel { position: absolute; left: 50%; bottom: 11vh; transform: translateX(-50%); width: min(820px, 80vw);',
        '  background: linear-gradient(180deg, rgba(14,16,12,0.94), rgba(8,9,7,0.96)); border: 1px solid rgba(214,178,60,0.45);',
        '  border-radius: 10px; padding: 16px 22px 12px; color: #ece8da; box-shadow: 0 16px 50px rgba(0,0,0,0.7); user-select: none; cursor: pointer; }',
        '.wsd-head { display: flex; align-items: baseline; gap: 12px; margin-bottom: 8px; }',
        '.wsd-who { font-size: 18px; font-weight: 700; color: #e8c25a; letter-spacing: 0.04em; }',
        '.wsd-role { font-size: 12px; color: rgba(236,232,218,0.55); font-style: italic; }',
        '.wsd-text { font-size: 17px; line-height: 1.55; min-height: 54px; font-family: Georgia, "Times New Roman", serif; }',
        '.wsd-choices { display: flex; flex-direction: column; gap: 6px; margin-top: 10px; }',
        '.wsd-choice { display: flex; align-items: center; gap: 10px; text-align: left; background: rgba(214,178,60,0.08); color: #ece8da;',
        '  border: 1px solid rgba(214,178,60,0.35); border-radius: 6px; padding: 8px 12px; font-size: 15px; cursor: pointer; }',
        '.wsd-choice:hover { background: rgba(214,178,60,0.22); border-color: rgba(214,178,60,0.8); }',
        '.wsd-num { display: inline-block; min-width: 20px; height: 20px; line-height: 20px; text-align: center; border-radius: 4px;',
        '  background: rgba(214,178,60,0.85); color: #14120a; font-weight: 700; font-size: 12px; }',
        '.wsd-needs { margin-left: auto; font-size: 11px; color: #9fb092; }',
        '.wsd-hint { margin-top: 8px; font-size: 11px; color: rgba(236,232,218,0.45); text-align: right; }',
        '.wsd-hint.is-warn { color: #ff9a8a; }',
        '@keyframes wsd-in { from { height: 0; } }',
    ].join('\n');
})();
