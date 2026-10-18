// wasteland_quests :: html/board.js
// Job board at a camp trader: what the camp needs, your progress, rewards.
// Data: { place, active, maxActive, message, ok, quests = [{ id, label, description,
//         status: available|active|ready|cooldown, minutes, handInHere, objectives = [{ text, done }], rewards = [text] }] }

(function () {
    'use strict';

    // Pure helper (unit-tested with Node): the button for a quest.
    function action(q) {
        if (q.status === 'available') return { action: 'accept', label: 'Accept' };
        if (q.status === 'ready') return q.handInHere ? { action: 'handIn', label: 'Hand in' } : { label: 'Hand in at another camp', disabled: true };
        if (q.status === 'active') return { action: 'abandon', label: 'Drop job', variant: 'danger' };
        return { label: 'Again in ' + (q.minutes || 0) + ' min', disabled: true };
    }

    if (typeof module === 'object' && module.exports) {
        module.exports = { action: action };
        return;
    }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st;

    const STATUS = { available: 'New', active: 'In progress', ready: 'Ready to hand in', cooldown: 'Done' };

    function card(q) {
        const a = action(q);
        const btn = UI.button(a.label, () => { if (a.action) st.api.post(a.action, { quest: q.id }); }, a.variant || (a.action === 'abandon' ? undefined : 'primary'));
        btn.disabled = !!a.disabled;
        const objectives = h('div', { class: 'wqb-objectives' });
        q.objectives.forEach((o) => objectives.appendChild(h('div', { class: 'wqb-obj' + (o.done && q.status !== 'available' ? ' is-done' : ''),
            text: (o.done && q.status !== 'available' ? '✓ ' : '• ') + o.text })));
        return h('div', { class: 'wqb-card is-' + q.status },
            h('div', { class: 'wqb-top' }, h('div', { class: 'wqb-name', text: q.label }), h('span', { class: 'wqb-status', text: STATUS[q.status] || '' })),
            h('div', { class: 'wl-hint', text: q.description || '' }),
            objectives,
            h('div', { class: 'wqb-bottom' }, h('div', { class: 'wqb-rewards', text: 'Reward: ' + (q.rewards.join(', ') || 'nothing') }), btn));
    }

    function render() {
        const d = st.data;
        st.root.innerHTML = '';
        const list = h('div', { class: 'wqb-list' });
        (d.quests || []).forEach((q) => list.appendChild(card(q)));
        if (!(d.quests || []).length) list.appendChild(h('div', { class: 'wl-hint', text: 'No jobs here right now.' }));
        st.root.appendChild(h('div', { class: 'wqb-panel' },
            h('div', { class: 'wqb-head' },
                h('div', {}, h('div', { class: 'wl-title', text: 'Jobs' }), h('div', { class: 'wl-hint', text: (d.place || '') + ' · ' + d.active + ' of ' + d.maxActive + ' jobs taken' })),
                UI.button('Close', () => st.api.post('close'))),
            h('div', { class: 'wl-message' + (d.message ? (d.ok ? ' is-ok' : ' is-error') : ''), text: d.message || '' }),
            list,
            h('div', { class: 'wl-hint wqb-foot', text: 'Esc closes · jobs can be done again after a while' })));
    }

    function onKey(e) { if (e.key === 'Escape') st.api.post('close'); }

    UI.registerScreen('questBoard', {
        mount: function (el, data, api) {
            st = { root: h('div', { class: 'wqb-root' }), data: data, api: api };
            el.appendChild(st.root);
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            render();
        },
        update: function (data) { st.data = data; render(); },
        unmount: function () { document.removeEventListener('keydown', onKey); st = null; },
    });

    const CSS = [
        '.wqb-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }',
        '.wqb-panel { width: min(760px, 94vw); max-height: 86vh; display: flex; flex-direction: column; gap: 10px; padding: 18px 20px;',
        '  background: var(--wl-bg); border: 1px solid var(--wl-border); border-radius: var(--wl-radius); box-shadow: 0 20px 60px rgba(0,0,0,0.6); }',
        '.wqb-head { display: flex; align-items: center; } .wqb-head > div:first-child { flex: 1; }',
        '.wqb-list { overflow-y: auto; max-height: 64vh; display: flex; flex-direction: column; gap: 8px; padding-right: 4px; }',
        '.wqb-card { background: var(--wl-bg-sunken); border-radius: 4px; padding: 10px 12px; border-left: 3px solid var(--wl-border);',
        '  display: flex; flex-direction: column; gap: 5px; }',
        '.wqb-card.is-active { border-left-color: #d6b23c; } .wqb-card.is-ready { border-left-color: #7fc75a; }',
        '.wqb-card.is-cooldown { opacity: 0.6; }',
        '.wqb-top { display: flex; align-items: baseline; gap: 10px; } .wqb-name { font-size: 15px; flex: 1; }',
        '.wqb-status { font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--wl-text-dim); }',
        '.wqb-objectives { font-size: 13px; display: flex; flex-direction: column; gap: 2px; }',
        '.wqb-obj.is-done { color: #9be27a; }',
        '.wqb-bottom { display: flex; align-items: center; gap: 10px; } .wqb-rewards { flex: 1; font-size: 13px; color: #e6d39a; }',
        '.wqb-foot { text-align: right; }',
        // ---- polish ----
        '.wqb-panel { position: relative; border-radius: 12px; border-color: rgba(214,186,140,0.14); background: linear-gradient(180deg, rgba(255,240,210,0.035), rgba(255,240,210,0) 120px), var(--wl-bg); box-shadow: var(--wl-shadow), inset 0 1px 0 rgba(255,240,210,0.06); backdrop-filter: blur(8px); }',
        '.wqb-panel::before { content: ""; position: absolute; top: -1px; left: 24px; right: 24px; height: 2px; border-radius: 2px; background: linear-gradient(90deg, transparent, var(--wl-accent) 25%, var(--wl-accent-strong) 50%, var(--wl-accent) 75%, transparent); opacity: 0.75; pointer-events: none; }',
        '.wqb-card { border-radius: 8px; background: linear-gradient(90deg, rgba(255,240,210,0.04), rgba(0,0,0,0.22)), rgba(10,10,9,0.55); }',
    ].join('\n');
})();
