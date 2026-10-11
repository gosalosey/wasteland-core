// wasteland_admin :: html/admin.js
// Admin panel (runs inside wasteland_ui). Tabs: Players, Bans, Server, Log.
// The server checks the admin permission for every action; this screen
// only shows data and sends requests.

(function () {
    'use strict';

    // ------------------------------------------------------------------
    // Pure helpers (unit-tested with Node)
    // ------------------------------------------------------------------

    function filterPlayers(players, query) {
        const q = String(query || '').trim().toLowerCase();
        if (!q) return players.slice();
        return players.filter((p) => {
            const c = p.character ? (p.character.firstName + ' ' + p.character.lastName) : '';
            return String(p.id) === q || (p.name || '').toLowerCase().includes(q) || c.toLowerCase().includes(q);
        });
    }

    function filterItems(items, query) {
        const q = String(query || '').trim().toLowerCase();
        if (!q) return items.slice();
        return items.filter((i) => i.name.includes(q) || i.label.toLowerCase().includes(q) || (i.category || '').includes(q));
    }

    const DURATIONS = [
        { label: '1 hour', minutes: 60 }, { label: '1 day', minutes: 1440 }, { label: '3 days', minutes: 4320 },
        { label: '1 week', minutes: 10080 }, { label: '30 days', minutes: 43200 }, { label: 'Permanent', minutes: 0 },
    ];

    function formatTime(unix) {
        if (!unix) return '';
        const d = new Date(unix * 1000);
        const pad = (n) => String(n).padStart(2, '0');
        return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
    }

    // 'active' | 'expired' | 'lifted' and a readable text.
    function banStatus(ban, now) {
        if (ban.revoked_unix) return { state: 'lifted', text: 'Lifted by ' + (ban.revoked_by || '?') };
        if (ban.expires_unix && ban.expires_unix <= now) return { state: 'expired', text: 'Expired' };
        return { state: 'active', text: ban.expires_unix ? 'Until ' + formatTime(ban.expires_unix) : 'Permanent' };
    }

    if (typeof module === 'object' && module.exports) {
        module.exports = { filterPlayers: filterPlayers, filterItems: filterItems, banStatus: banStatus, formatTime: formatTime, DURATIONS: DURATIONS };
        return;
    }

    // ------------------------------------------------------------------
    // Screen
    // ------------------------------------------------------------------

    const UI = window.WastelandUI;
    const h = UI.h;
    let st;

    const act = (action, args) => st.api.post('act', { action: action, args: args || {} });

    function message(text, kind) {
        st.message.textContent = text || '';
        st.message.className = 'wl-message' + (kind ? ' is-' + kind : '');
    }

    // A button that needs a second click within 4 seconds.
    function confirmButton(label, onConfirm) {
        let armed = false;
        let timer = null;
        const b = UI.button(label, () => {
            if (!armed) {
                armed = true;
                b.textContent = 'Click again to confirm';
                timer = setTimeout(() => { armed = false; b.textContent = label; }, 4000);
                return;
            }
            clearTimeout(timer);
            armed = false;
            b.textContent = label;
            onConfirm();
        }, 'danger');
        return b;
    }

    function input(attrs, value) {
        const el = h('input', { class: 'wl-input', attrs: attrs || {} });
        if (value !== undefined) el.value = value;
        return el;
    }

    function select(options, value) {
        const el = h('select', { class: 'wl-input' });
        options.forEach((o) => {
            const opt = h('option', { text: o.label, attrs: { value: String(o.value) } });
            if (String(o.value) === String(value)) opt.selected = true;
            el.appendChild(opt);
        });
        return el;
    }

    function row() { return h('div', { class: 'wla-row' }, ...arguments); }
    function section(title) { return h('div', { class: 'wl-section-title', text: title }); }

    // ---------------------------------------------------------------- players

    function playerList() {
        const box = h('div', { class: 'wla-list' });
        filterPlayers(st.data.players, st.search).forEach((p) => {
            const c = p.character ? p.character.firstName + ' ' + p.character.lastName : 'no character';
            const item = h('button', { class: 'wla-list__item' + (p.id === st.selected ? ' is-active' : ''),
                onclick: () => { st.selected = p.id; render(); } },
                h('span', { class: 'wla-id', text: '#' + p.id }),
                h('span', { class: 'wla-name', text: p.name }),
                h('span', { class: 'wl-hint', text: c + (p.stats && p.stats.dead ? ' – dead' : '') }));
            box.appendChild(item);
        });
        if (!box.children.length) box.appendChild(h('div', { class: 'wl-hint', text: 'No players.' }));
        return box;
    }

    function statEditor(p) {
        const s = p.stats;
        if (!s) return h('div', { class: 'wl-hint', text: 'No survival stats (no character loaded).' });
        const box = h('div', { class: 'wla-stats' });
        [['hunger', 'Food', 0, 100], ['thirst', 'Water', 0, 100], ['infection', 'Infection', 0, 100],
            ['bleeding', 'Bleeding', 0, 3], ['temperature', 'Temperature', 30, 42]].forEach(([key, label, min, max]) => {
            const field = input({ type: 'number', min: String(min), max: String(max), step: key === 'temperature' ? '0.1' : '1' },
                Math.round((s[key] || 0) * 10) / 10);
            box.appendChild(h('div', { class: 'wla-stat' }, h('span', { class: 'wl-field__label', text: label }), field,
                UI.button('Set', () => act('setStat', { target: p.id, stat: key, value: Number(field.value) }))));
        });
        return box;
    }

    function playerDetail() {
        const p = st.data.players.find((x) => x.id === st.selected);
        if (!p) return h('div', { class: 'wl-hint', text: 'Select a player.' });
        const t = { target: p.id };
        const c = p.character ? p.character.firstName + ' ' + p.character.lastName + ' (character ' + p.character.id + ')' : 'no character loaded';
        const items = filterItems(st.data.items || [], st.itemSearch);
        const itemSelect = select(items.map((i) => ({ label: i.label + ' (' + i.name + ')', value: i.name })), st.itemChoice);
        itemSelect.addEventListener('change', () => { st.itemChoice = itemSelect.value; });
        const itemSearch = input({ placeholder: 'Search items' }, st.itemSearch || '');
        itemSearch.addEventListener('input', () => { st.itemSearch = itemSearch.value; render(); itemFocus(); });
        const count = input({ type: 'number', min: '1', max: '10000' }, 1);
        const kickReason = input({ placeholder: 'Reason', maxlength: '200' });
        const banReason = input({ placeholder: 'Reason (required)', maxlength: '200' });
        const banTime = select(DURATIONS.map((d) => ({ label: d.label, value: d.minutes })), 1440);
        return h('div', { class: 'wla-detail' },
            h('div', { class: 'wla-detail__head' },
                h('div', { class: 'wla-big', text: '#' + p.id + ' ' + p.name }),
                h('div', { class: 'wl-hint', text: c + ' · ping ' + p.ping + ' ms' + (p.frozen ? ' · FROZEN' : '') })),
            section('Actions'),
            row(UI.button('Teleport to', () => act('teleportTo', t)), UI.button('Bring', () => act('bring', t)),
                UI.button('Heal', () => act('heal', t)), UI.button('Revive', () => act('revive', t)),
                UI.button(p.frozen ? 'Unfreeze' : 'Freeze', () => act('freeze', { target: p.id, enabled: !p.frozen }))),
            section('Survival'),
            statEditor(p),
            section('Items'),
            row(itemSearch),
            row(itemSelect, count, UI.button('Give', () => {
                const name = itemSelect.value;
                if (name) act('give', { target: p.id, item: name, count: Math.max(1, Math.floor(Number(count.value) || 1)) });
            }, 'primary')),
            row(UI.button('Open inventory', () => act('inventory', t)),
                confirmButton('Clear inventory', () => act('clearInventory', t))),
            section('Kick'),
            row(kickReason, confirmButton('Kick', () => act('kick', { target: p.id, reason: kickReason.value }))),
            section('Ban'),
            row(banReason, banTime, confirmButton('Ban', () => act('ban', {
                target: p.id, reason: banReason.value, minutes: Number(banTime.value),
            }))));
    }

    function itemFocus() {
        const el = st.content.querySelector('.wla-detail input[placeholder="Search items"]');
        if (el) { el.focus(); el.setSelectionRange(el.value.length, el.value.length); }
    }

    function playersTab() {
        const search = input({ placeholder: 'Search by id, name or character' }, st.search || '');
        search.addEventListener('input', () => {
            st.search = search.value;
            const list = st.content.querySelector('.wla-list');
            if (list) list.replaceWith(playerList());
        });
        return h('div', { class: 'wla-split' },
            h('div', { class: 'wla-left' }, search, playerList()),
            h('div', { class: 'wla-right' }, playerDetail()));
    }

    // ---------------------------------------------------------------- bans & log

    function bansTab() {
        const license = input({ placeholder: 'license:...', maxlength: '64' });
        const name = input({ placeholder: 'Name (optional)', maxlength: '64' });
        const reason = input({ placeholder: 'Reason (required)', maxlength: '200' });
        const time = select(DURATIONS.map((d) => ({ label: d.label, value: d.minutes })), 1440);
        const table = h('table', { class: 'wla-table' },
            h('tr', {}, ...['#', 'Name', 'License', 'Reason', 'By', 'When', 'Status', ''].map((t) => h('th', { text: t }))));
        (st.bans || []).forEach((b) => {
            const s = banStatus(b, st.listNow || 0);
            table.appendChild(h('tr', { class: 'is-' + s.state },
                h('td', { text: String(b.id) }), h('td', { text: b.name || '' }), h('td', { class: 'wla-mono', text: b.license }),
                h('td', { text: b.reason }), h('td', { text: b.banned_by }), h('td', { text: formatTime(b.created_unix) }),
                h('td', { text: s.text }),
                h('td', {}, s.state === 'active' ? confirmButton('Lift', () => act('unban', { banId: Number(b.id) })) : null)));
        });
        return h('div', {},
            section('Ban by license (also for players who are offline)'),
            row(license, name), row(reason, time, confirmButton('Ban', () => act('banLicense', {
                license: license.value.trim(), name: name.value.trim(), reason: reason.value, minutes: Number(time.value),
            }))),
            section('Recent bans'),
            row(UI.button('Refresh', () => st.api.post('list', { which: 'bans' }))),
            h('div', { class: 'wla-scroll' }, table));
    }

    function logTab() {
        const table = h('table', { class: 'wla-table' },
            h('tr', {}, ...['When', 'Admin', 'Action', 'Target', 'Details'].map((t) => h('th', { text: t }))));
        (st.log || []).forEach((r) => table.appendChild(h('tr', {},
            h('td', { text: formatTime(r.created_unix) }), h('td', { text: r.admin }), h('td', { text: r.action }),
            h('td', { text: r.target || '' }), h('td', { text: r.details || '' }))));
        return h('div', {}, row(UI.button('Refresh', () => st.api.post('list', { which: 'log' }))),
            h('div', { class: 'wla-scroll' }, table));
    }

    // ---------------------------------------------------------------- server

    function serverTab() {
        const d = st.data;
        const self = d.self || {};
        const parts = [section('You'),
            row(UI.button(self.noclip ? 'Noclip: on' : 'Noclip: off', () => { self.noclip = !self.noclip; act('noclip', { enabled: self.noclip }); }),
                UI.button(self.invisible ? 'Invisible: on' : 'Invisible: off', () => { self.invisible = !self.invisible; act('invisible', { enabled: self.invisible }); }),
                h('span', { class: 'wl-hint', text: 'Noclip: W A S D, Space up, Ctrl down, Shift faster' }))];
        if (d.world) {
            const hour = input({ type: 'number', min: '0', max: '23' }, d.world.hour);
            const minute = input({ type: 'number', min: '0', max: '59' }, d.world.minute);
            const weather = select((d.world.weathers || []).map((w) => ({ label: w, value: w })), d.world.weather);
            parts.push(section('Time and weather'),
                row(h('span', { class: 'wl-hint', text: 'Now ' + String(d.world.hour).padStart(2, '0') + ':' + String(d.world.minute).padStart(2, '0') + ', ' + d.world.weather }),
                    hour, minute, UI.button('Set time', () => act('setTime', { hour: Number(hour.value), minute: Number(minute.value) })),
                    UI.button(d.world.frozen ? 'Time: frozen' : 'Time: running', () => act('freezeTime', { enabled: !d.world.frozen }))),
                row(weather, UI.button('Set weather', () => act('setWeather', { weather: weather.value })),
                    UI.button(d.world.dynamic ? 'Weather: changes' : 'Weather: fixed', () => act('weatherDynamic', { enabled: !d.world.dynamic }))));
        }
        const text = h('textarea', { class: 'wl-input wla-textarea', attrs: { maxlength: '300', placeholder: 'Message to every player' } });
        parts.push(section('Announcement'), text, row(UI.button('Send to everyone', () => act('announce', { text: text.value }), 'primary')));
        const modules = h('table', { class: 'wla-table' }, h('tr', {}, ...['Module', 'Version', 'State', 'Details'].map((t) => h('th', { text: t }))));
        (d.modules || []).forEach((m) => modules.appendChild(h('tr', { class: m.state !== 'running' || m.health === 'degraded' ? 'is-bad' : '' },
            h('td', { text: m.name }), h('td', { text: m.version }), h('td', { text: m.state + (m.health === 'degraded' ? ' (degraded)' : '') }),
            h('td', { text: m.detail || '' }))));
        parts.push(section('Modules'), modules);
        const issues = h('div', { class: 'wla-issues' });
        (d.issues || []).slice().reverse().forEach((i) => issues.appendChild(h('div', { class: 'wla-issue is-' + i.level,
            text: (i.time || '') + ' ' + i.level.toUpperCase() + ' [' + i.module + '] ' + i.message })));
        if (!(d.issues || []).length) issues.appendChild(h('div', { class: 'wl-hint', text: 'No recent warnings or errors.' }));
        parts.push(section('Recent warnings and errors'), issues);
        return h('div', {}, ...parts);
    }

    // ---------------------------------------------------------------- frame

    const TABS = [{ id: 'players', label: 'Players' }, { id: 'bans', label: 'Bans' }, { id: 'server', label: 'Server & world' }, { id: 'log', label: 'Action log' }];
    const RENDER = { players: playersTab, bans: bansTab, server: serverTab, log: logTab };

    function render() {
        st.content.innerHTML = '';
        st.content.appendChild(RENDER[st.tab]());
    }

    function selectTab(id) {
        st.tab = id;
        if (id === 'bans') st.api.post('list', { which: 'bans' });
        if (id === 'log') st.api.post('list', { which: 'log' });
        render();
    }

    function onKey(e) {
        if (e.key === 'Escape' || (e.key === 'F10' && !(e.target && e.target.tagName === 'INPUT'))) st.api.post('close');
    }

    UI.registerScreen('adminPanel', {
        mount: function (el, data, api) {
            st = { api: api, data: data.data, tab: 'players', selected: null, search: '', itemSearch: '', bans: [], log: [] };
            if (st.data.players.length) st.selected = st.data.players[0].id;
            st.content = h('div', { class: 'wla-content' });
            st.message = h('div', { class: 'wl-message' });
            const tabs = UI.tabs(TABS, selectTab);
            el.appendChild(h('div', { class: 'wla-root' }, h('div', { class: 'wl-backdrop' }),
                h('div', { class: 'wl-panel wla-panel' },
                    h('div', { class: 'wla-header' }, h('h1', { class: 'wl-title', text: 'Admin' }),
                        UI.button('Refresh', () => api.post('refresh')), UI.button('Close', () => api.post('close'))),
                    tabs, st.content, st.message)));
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            tabs.select('players');
        },
        update: function (data) {
            if (data.data) {
                const self = st.data.self;
                st.data = data.data;
                if (self && st.data.self) { st.data.self.noclip = self.noclip; st.data.self.invisible = self.invisible; }
                if (!st.data.players.find((p) => p.id === st.selected) && st.data.players.length) st.selected = st.data.players[0].id;
                if (st.tab === 'players' || st.tab === 'server') render();
            }
            if (data.list) {
                st[data.list.which] = data.list.rows || [];
                st.listNow = data.list.now;
                if (st.tab === data.list.which) render();
            }
            if (data.result) message(data.result.message, data.result.ok ? 'ok' : 'error');
        },
        unmount: function () { document.removeEventListener('keydown', onKey); st = null; },
    });

    const CSS = [
        '.wla-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }',
        '.wla-panel { position: relative; width: min(1180px, 94vw); height: 86vh; display: flex; flex-direction: column; }',
        '.wla-header { display: flex; align-items: center; gap: 10px; } .wla-header .wl-title { flex: 1; }',
        '.wla-content { flex: 1; overflow: auto; padding-right: 6px; }',
        '.wla-split { display: grid; grid-template-columns: 300px 1fr; gap: 16px; height: 100%; }',
        '.wla-left { display: flex; flex-direction: column; gap: 8px; min-height: 0; }',
        '.wla-list { display: flex; flex-direction: column; gap: 4px; overflow: auto; }',
        '.wla-list__item { font: inherit; text-align: left; color: var(--wl-text); background: var(--wl-bg-raised); border: 1px solid var(--wl-border);',
        '  border-radius: var(--wl-radius); padding: 8px 10px; cursor: pointer; display: grid; grid-template-columns: 44px 1fr; gap: 0 6px; }',
        '.wla-list__item .wl-hint { grid-column: 2; }',
        '.wla-list__item.is-active { border-color: var(--wl-accent); }',
        '.wla-id { color: var(--wl-accent); font-variant-numeric: tabular-nums; }',
        '.wla-big { font-family: var(--wl-font-display); font-size: 22px; }',
        '.wla-row { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-bottom: 8px; }',
        '.wla-row .wl-input { flex: 1; min-width: 120px; }',
        '.wla-row select.wl-input { flex: 2; }',
        '.wla-stats { display: grid; grid-template-columns: repeat(auto-fill, minmax(230px, 1fr)); gap: 8px; }',
        '.wla-stat { display: grid; grid-template-columns: 90px 1fr auto; gap: 6px; align-items: center; }',
        '.wla-table { width: 100%; border-collapse: collapse; font-size: 13px; }',
        '.wla-table th { text-align: left; color: var(--wl-text-dim); font-weight: 600; padding: 6px; border-bottom: 1px solid var(--wl-border); }',
        '.wla-table td { padding: 6px; border-bottom: 1px solid rgba(255,255,255,0.04); vertical-align: top; }',
        '.wla-table tr.is-lifted td, .wla-table tr.is-expired td { color: var(--wl-text-dim); }',
        '.wla-table tr.is-bad td { color: #ffb37a; }',
        '.wla-mono { font-family: Consolas, monospace; font-size: 11px; word-break: break-all; }',
        '.wla-scroll { max-height: 52vh; overflow: auto; }',
        '.wla-textarea { min-height: 70px; resize: vertical; margin-bottom: 8px; }',
        '.wla-issues { font-family: Consolas, monospace; font-size: 12px; display: flex; flex-direction: column; gap: 3px; }',
        '.wla-issue.is-error { color: #ff9c90; } .wla-issue.is-warn { color: #ffd38a; }',
        'select.wl-input option { background: #1b1915; }',
    ].join('\n');
})();
