// wasteland_players :: html/characters.js
// Character select screen (runs inside wasteland_ui). Shows the account's
// slots; lets the player play, create or delete characters. All rules
// (names, slot limit, confirmation) are enforced by the server; this screen
// only displays its answers.

(function () {
    'use strict';

    // ------------------------------------------------------------------
    // Pure helpers (unit-tested with Node)
    // ------------------------------------------------------------------

    // [{ slot, character | null }] for slots 1..maxCharacters.
    function slotsView(list) {
        const max = (list && list.maxCharacters) || 0;
        const bySlot = {};
        ((list && list.characters) || []).forEach((c) => { if (c && c.slot) bySlot[c.slot] = c; });
        const out = [];
        for (let slot = 1; slot <= max; slot++) out.push({ slot: slot, character: bySlot[slot] || null });
        return out;
    }

    function formatPlayTime(seconds) {
        const s = Math.max(0, Math.floor(seconds || 0));
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        return h + 'h ' + String(m).padStart(2, '0') + 'm';
    }

    function trimName(v) { return String(v || '').trim(); }

    if (typeof module === 'object' && module.exports) {
        module.exports = { slotsView: slotsView, formatPlayTime: formatPlayTime, trimName: trimName };
        return;
    }

    // ------------------------------------------------------------------
    // Screen
    // ------------------------------------------------------------------

    const UI = window.WastelandUI;
    const h = UI.h;
    let state;

    function setMessage(text, kind) {
        state.message.textContent = text || '';
        state.message.className = 'wl-message' + (kind ? ' is-' + kind : '');
    }

    function setBusy(busy) {
        state.busy = busy;
        state.root.querySelectorAll('button, input').forEach((el) => { el.disabled = busy; });
    }

    function characterCard(entry) {
        const c = entry.character;
        const card = h('div', { class: 'wlc-card' },
            h('div', { class: 'wlc-slot', text: 'Slot ' + entry.slot }),
            h('div', { class: 'wlc-name', text: c.firstName + ' ' + c.lastName }),
            h('div', { class: 'wl-hint', text: 'Played ' + formatPlayTime(c.playSeconds) }));
        const actions = h('div', { class: 'wlc-actions' });
        if (state.deleting === entry.slot) {
            const input = h('input', { class: 'wl-input', attrs: { placeholder: 'Type "' + c.firstName + '" to confirm', maxlength: '32' } });
            actions.appendChild(input);
            actions.appendChild(UI.button('Delete forever', () => {
                setBusy(true);
                setMessage('Deleting...');
                state.api.post('delete', { slot: entry.slot, confirm: trimName(input.value) });
            }, 'danger'));
            actions.appendChild(UI.button('Cancel', () => { state.deleting = null; render(); }));
            setTimeout(() => input.focus(), 0);
        } else {
            actions.appendChild(UI.button('Play', () => {
                setBusy(true);
                setMessage('Loading ' + c.firstName + '...');
                state.api.post('select', { slot: entry.slot });
            }, 'primary'));
            if (state.allowDelete) {
                actions.appendChild(UI.button('Delete', () => { state.deleting = entry.slot; render(); }, 'danger'));
            }
        }
        card.appendChild(actions);
        return card;
    }

    function emptyCard(entry) {
        if (state.creating !== entry.slot) {
            return h('div', { class: 'wlc-card wlc-card--empty' },
                h('div', { class: 'wlc-slot', text: 'Slot ' + entry.slot }),
                h('div', { class: 'wl-hint', text: 'Empty' }),
                UI.button('Create character', () => { state.creating = entry.slot; render(); }));
        }
        const first = h('input', { class: 'wl-input', attrs: { placeholder: 'First name', maxlength: '32' } });
        const last = h('input', { class: 'wl-input', attrs: { placeholder: 'Last name', maxlength: '32' } });
        const submit = () => {
            setBusy(true);
            setMessage('Creating...');
            state.api.post('create', { firstName: trimName(first.value), lastName: trimName(last.value) });
        };
        last.addEventListener('keydown', (e) => { if (e.key === 'Enter') submit(); });
        setTimeout(() => first.focus(), 0);
        return h('div', { class: 'wlc-card' },
            h('div', { class: 'wlc-slot', text: 'Slot ' + entry.slot }),
            first, last,
            h('div', { class: 'wlc-actions' },
                UI.button('Create', submit, 'primary'),
                UI.button('Cancel', () => { state.creating = null; render(); })));
    }

    function render() {
        state.cards.innerHTML = '';
        slotsView(state.list).forEach((entry) => {
            state.cards.appendChild(entry.character ? characterCard(entry) : emptyCard(entry));
        });
        setBusy(state.busy);
    }

    UI.registerScreen('characterSelect', {
        mount: function (el, data, api) {
            state = { api: api, list: data.list || {}, busy: false, creating: null, deleting: null, allowDelete: true };
            state.cards = h('div', { class: 'wlc-cards' });
            state.message = h('div', { class: 'wl-message' });
            state.root = h('div', { class: 'wlc-root' },
                h('div', { class: 'wl-backdrop' }),
                h('div', { class: 'wl-panel wlc-panel' },
                    h('h1', { class: 'wl-title', text: 'Survivors' }),
                    h('p', { class: 'wl-subtitle', text: 'Choose who you play, or start someone new.' }),
                    state.cards,
                    state.message));
            el.appendChild(state.root);
            el.appendChild(h('style', { text: CSS }));
            render();
        },
        update: function (data) {
            if (data.list) {
                state.list = data.list;
                state.creating = null;
                state.deleting = null;
                state.busy = false;
                render();
            }
            if (data.result) {
                const r = data.result;
                if (!r.ok) state.busy = false;
                setBusy(state.busy);
                setMessage(r.message, r.ok ? 'ok' : 'error');
            }
        },
        unmount: function () { state = null; },
    });

    const CSS = [
        '.wlc-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }',
        '.wlc-panel { position: relative; width: min(920px, 92vw); }',
        '.wlc-cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: var(--wl-gap); }',
        '.wlc-card { background: var(--wl-bg-raised); border: 1px solid var(--wl-border); border-radius: var(--wl-radius); padding: 14px; display: flex; flex-direction: column; gap: 8px; min-height: 150px; }',
        '.wlc-card--empty { border-style: dashed; justify-content: space-between; }',
        '.wlc-slot { font-size: 11px; letter-spacing: 0.12em; text-transform: uppercase; color: var(--wl-accent); }',
        '.wlc-name { font-family: var(--wl-font-display); font-size: 20px; }',
        '.wlc-actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: auto; }',
    ].join('\n');
})();
