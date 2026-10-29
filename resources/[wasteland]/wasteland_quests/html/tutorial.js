// wasteland_quests :: html/tutorial.js
// The new player tutorial: the offer (Start / No thanks) and, at the end,
// "Tutorial done" with the rewards.
// Data: { mode: 'offer' | 'done', label, description, steps = [text], rewards = [text], command, text }

(function () {
    'use strict';

    // Pure helper (unit-tested with Node): the buttons for a mode.
    function buttons(mode) {
        if (mode === 'done') return [{ action: 'close', label: 'Got it', variant: 'primary' }];
        return [{ action: 'start', label: 'Start the tutorial', variant: 'primary' }, { action: 'skip', label: 'No thanks' }];
    }

    if (typeof module === 'object' && module.exports) {
        module.exports = { buttons: buttons };
        return;
    }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st;

    function render() {
        const d = st.data;
        st.root.innerHTML = '';
        const done = d.mode === 'done';
        const body = h('div', { class: 'wqtu-body' });
        if (done) {
            body.appendChild(h('div', { class: 'wqtu-text', text: d.text || 'You have the tools, you know where the wood and stone are, and you know how to turn them into money. Good luck out there.' }));
        } else {
            body.appendChild(h('div', { class: 'wqtu-text', text: d.description || '' }));
            const list = h('ol', { class: 'wqtu-steps' });
            (d.steps || []).forEach((s) => list.appendChild(h('li', { text: s })));
            body.appendChild(list);
        }
        if ((d.rewards || []).length) body.appendChild(h('div', { class: 'wqtu-rewards', text: (done ? 'You got: ' : 'Reward: ') + d.rewards.join(', ') }));
        if (!done) body.appendChild(h('div', { class: 'wl-hint', text: 'You can skip it and play on your own. Type /' + (d.command || 'tutorial') + ' any time to start it later.' }));
        const row = h('div', { class: 'wqtu-buttons' });
        buttons(d.mode).forEach((b) => row.appendChild(UI.button(b.label, () => st.api.post(b.action), b.variant)));
        st.root.appendChild(h('div', { class: 'wqtu-panel' },
            h('div', { class: 'wl-title', text: done ? 'Tutorial done' : (d.label || 'Tutorial') }),
            body, row));
    }

    function onKey(e) { if (e.key === 'Escape') st.api.post(st.data.mode === 'done' ? 'close' : 'later'); }

    UI.registerScreen('questTutorial', {
        mount: function (el, data, api) {
            st = { root: h('div', { class: 'wqtu-root' }), data: data, api: api };
            el.appendChild(st.root);
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            render();
        },
        update: function (data) { st.data = data; render(); },
        unmount: function () { document.removeEventListener('keydown', onKey); st = null; },
    });

    const CSS = [
        '.wqtu-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; background: rgba(0,0,0,0.35); }',
        '.wqtu-panel { position: relative; width: min(560px, 94vw); display: flex; flex-direction: column; gap: 12px; padding: 20px 22px;',
        '  background: linear-gradient(180deg, rgba(255,240,210,0.035), rgba(255,240,210,0) 120px), var(--wl-bg); border: 1px solid rgba(214,186,140,0.14);',
        '  border-radius: 12px; box-shadow: var(--wl-shadow), inset 0 1px 0 rgba(255,240,210,0.06); }',
        '.wqtu-panel::before { content: ""; position: absolute; top: -1px; left: 24px; right: 24px; height: 2px; border-radius: 2px; background: linear-gradient(90deg, transparent, var(--wl-accent) 25%, var(--wl-accent-strong) 50%, var(--wl-accent) 75%, transparent); opacity: 0.75; }',
        '.wqtu-body { display: flex; flex-direction: column; gap: 10px; }',
        '.wqtu-text { font-size: 14px; line-height: 1.45; }',
        '.wqtu-steps { margin: 0; padding-left: 22px; font-size: 13px; display: flex; flex-direction: column; gap: 3px; }',
        '.wqtu-rewards { font-size: 13px; color: #e6d39a; }',
        '.wqtu-buttons { display: flex; gap: 10px; justify-content: flex-end; }',
    ].join('\n');
})();
