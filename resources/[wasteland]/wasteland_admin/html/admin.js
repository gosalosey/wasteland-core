// wasteland_admin :: html/admin.js
// Admin panel (runs inside wasteland_ui). Tabs: Players, Live, Coords, Bans,
// Server & world, Action log.
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

    // Items grouped by category (inventory order; unknown categories last),
    // each group sorted by label: [{ category, items }]
    const CATEGORY_ORDER = ['weapon', 'ammo', 'medical', 'food', 'drink', 'clothing', 'container', 'tool', 'material', 'misc'];
    function groupItems(items) {
        const groups = {};
        items.forEach((i) => { const c = i.category || 'misc'; (groups[c] = groups[c] || []).push(i); });
        const rank = (c) => { const r = CATEGORY_ORDER.indexOf(c); return r < 0 ? 999 : r; };
        return Object.keys(groups).sort((a, b) => rank(a) - rank(b) || a.localeCompare(b))
            .map((c) => ({ category: c, items: groups[c].slice().sort((a, b) => a.label.localeCompare(b.label)) }));
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

    // Your position as text for scripts: 'vector3' | 'vector4' | 'heading' | 'xyz'.
    function coordText(c, kind) {
        const f = (n) => (Math.round(Number(n || 0) * 100) / 100).toFixed(2);
        if (kind === 'vector3') return 'vector3(' + f(c.x) + ', ' + f(c.y) + ', ' + f(c.z) + ')';
        if (kind === 'vector4') return 'vector4(' + f(c.x) + ', ' + f(c.y) + ', ' + f(c.z) + ', ' + f(c.h) + ')';
        if (kind === 'heading') return f(c.h);
        return 'X ' + f(c.x) + '   Y ' + f(c.y) + '   Z ' + f(c.z) + '   Heading ' + f(c.h);
    }

    if (typeof module === 'object' && module.exports) {
        module.exports = { filterPlayers: filterPlayers, filterItems: filterItems, groupItems: groupItems, banStatus: banStatus,
            formatTime: formatTime, coordText: coordText, DURATIONS: DURATIONS };
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
        const picker = itemPicker(st.data.items || []);
        const count = input({ type: 'number', min: '1', max: '1000000' }, 1);
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
            ...playerTools(p),
            section('Items'),
            h('div', { class: 'wla-row wla-row--top' }, picker, count, UI.button('Give', () => {
                const name = st.itemChoice;
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

    // Cash, jobs, recipes, spectate, send to camp.
    function playerTools(p) {
        const t = { target: p.id };
        const out = [];
        if (!p.character) return out;
        const watching = st.spectating === p.id;
        out.push(section('Admin view'), row(
            UI.button(watching ? 'Stop spectating' : 'Spectate', () => {
                st.spectating = watching ? null : p.id;
                act('spectate', { target: p.id, enabled: !watching });
            }, watching ? 'primary' : undefined),
            confirmButton('Send to nearest camp', () => act('sendToCamp', t))));
        if (typeof p.cash === 'number') {
            const amount = input({ type: 'number', min: '1', max: '1000000' }, 100);
            const n = () => Math.max(1, Math.floor(Number(amount.value) || 1));
            out.push(section('Cash: $' + p.cash.toLocaleString('en-US')),
                row(amount, UI.button('Give', () => act('giveCash', { target: p.id, count: n() }), 'primary'),
                    UI.button('Take', () => act('takeCash', { target: p.id, count: n() }))));
        }
        if (p.quests) {
            const box = h('div', { class: 'wla-mini' });
            p.quests.active.forEach((q) => box.appendChild(h('div', { class: 'wla-mini__row' },
                h('div', {}, h('b', { text: q.label + (q.ready ? ' (ready to hand in)' : '') }), h('div', { class: 'wl-hint', text: q.objectives.join(' · ') })),
                confirmButton('Drop', () => act('dropQuest', { target: p.id, quest: q.id })))));
            if (!p.quests.active.length) box.appendChild(h('div', { class: 'wl-hint', text: 'No jobs taken.' }));
            const cd = p.quests.cooldowns.map((q) => q.label + ' (' + q.minutes + ' min)').join(', ');
            out.push(section('Jobs'), box, row(h('span', { class: 'wl-hint', text: cd ? 'Cooling down: ' + cd : 'No cooldowns.' }),
                cd ? UI.button('Reset cooldowns', () => act('resetCooldowns', t)) : null));
        }
        if (p.recipes) {
            const box = h('div', { class: 'wla-mini wla-mini--grid' });
            p.recipes.forEach((r) => box.appendChild(h('div', { class: 'wla-mini__row' + (r.known ? ' is-known' : '') },
                h('span', { text: (r.known ? '✓ ' : '· ') + r.label }),
                !r.blueprint ? h('span', { class: 'wl-hint', text: 'starter' })
                    : r.known ? UI.button('Forget', () => act('forgetRecipe', { target: p.id, recipe: r.name }))
                        : UI.button('Teach', () => act('teachRecipe', { target: p.id, recipe: r.name })))));
            out.push(section('Recipes'), box);
        }
        return out;
    }

    // Dropdown with every item on the server: the closed box shows the
    // chosen item; open, it lists all items by category with a search box.
    function itemPicker(all) {
        const chosen = all.find((i) => i.name === st.itemChoice);
        const pic = (it, cls) => {
            const img = h('img', { class: cls, draggable: false });
            if (it && it.image) img.src = it.image; else img.style.visibility = 'hidden';
            img.addEventListener('error', () => { img.style.visibility = 'hidden'; });
            return img;
        };
        const box = h('button', { class: 'wla-pick__box' + (st.itemOpen ? ' is-open' : '') },
            pic(chosen, 'wla-pick__img'),
            h('span', { class: 'wla-pick__label', text: chosen ? chosen.label : 'Choose an item (' + all.length + ')' }),
            chosen ? h('span', { class: 'wla-pick__name', text: chosen.name }) : null,
            h('span', { class: 'wla-pick__caret', text: st.itemOpen ? '▴' : '▾' }));
        box.addEventListener('click', () => { st.itemOpen = !st.itemOpen; render(); if (st.itemOpen) pickerFocus(); });
        const wrap = h('div', { class: 'wla-pick' }, box);
        if (!st.itemOpen) return wrap;

        const list = h('div', { class: 'wla-pick__list' });
        const fill = () => {
            list.innerHTML = '';
            const groups = groupItems(filterItems(all, st.itemSearch));
            if (!groups.length) list.appendChild(h('div', { class: 'wl-hint wla-pick__empty', text: 'No item matches.' }));
            groups.forEach((g) => {
                list.appendChild(h('div', { class: 'wla-pick__group', text: g.category + ' (' + g.items.length + ')' }));
                g.items.forEach((it) => {
                    const rowEl = h('div', { class: 'wla-pick__row' + (it.name === st.itemChoice ? ' is-chosen' : '') },
                        pic(it, 'wla-pick__rowimg'), h('span', { text: it.label }), h('span', { class: 'wla-pick__name', text: it.name }));
                    rowEl.addEventListener('click', () => { st.itemChoice = it.name; st.itemOpen = false; render(); });
                    list.appendChild(rowEl);
                });
            });
        };
        const search = input({ placeholder: 'Search ' + all.length + ' items' }, st.itemSearch || '');
        search.classList.add('wla-pick__search');
        search.addEventListener('input', () => { st.itemSearch = search.value; fill(); });
        search.addEventListener('keydown', (e) => { if (e.key === 'Escape') { e.stopPropagation(); st.itemOpen = false; render(); } });
        fill();
        wrap.appendChild(h('div', { class: 'wla-pick__panel' }, search, list));
        return wrap;
    }

    function pickerFocus() {
        const el = st.content.querySelector('.wla-pick__search');
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
        const zcount = input({ type: 'number', min: '1', max: '20' }, 5);
        parts.push(section('World tools'),
            row(h('span', { class: 'wla-label', text: 'Zombies' }), zcount,
                UI.button('Spawn around me', () => act('zombieSpawn', { count: Math.max(1, Math.min(20, Math.floor(Number(zcount.value) || 5))) })),
                confirmButton('Clear all zombies', () => act('zombieClear'))),
            row(h('span', { class: 'wla-label', text: 'Vehicles' }),
                UI.button('Spawn a wreck', () => act('vehicleWreck')), UI.button('Spawn a working car', () => act('vehicleWorking')),
                UI.button('Fix the car I am in / next to', () => act('vehicleFix')), confirmButton('Refill all gas pumps', () => act('refillPumps'))),
            row(h('span', { class: 'wla-label', text: 'Travel' }), UI.button('Teleport to my map waypoint', () => act('tpWaypoint'))));
        const ov = st.overlays || (st.overlays = {});
        const toggle = (name, label) => UI.button(label + (ov[name] ? ': on' : ': off'), () => {
            ov[name] = !ov[name];
            act('overlay', { overlay: name, enabled: ov[name] });
            render();
        }, ov[name] ? 'primary' : undefined);
        parts.push(section('Debug overlays'),
            row(toggle('zombies', 'Zombie AI'), toggle('vehicles', 'Vehicles & spawn points'), toggle('camps', 'Camp borders'),
                toggle('loot', 'Loot containers')),
            h('div', { class: 'wl-hint', text: 'Shown in the world around you (only for you) until switched off.' }));
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

    // ---------------------------------------------------------------- live

    function liveTab() {
        const d = st.data;
        const l = d.live || {};
        const card = (label, value, sub) => h('div', { class: 'wla-card' },
            h('div', { class: 'wla-card__label', text: label }), h('div', { class: 'wla-card__value', text: String(value) }),
            sub ? h('div', { class: 'wl-hint', text: sub } ) : null);
        const cards = h('div', { class: 'wla-cards' },
            card('Players online', l.players || 0),
            l.zombies ? card('Zombies alive', l.zombies.alive, l.zombies.total + ' including bodies') : null,
            l.vehicles ? card('Vehicles', l.vehicles.total, l.vehicles.out + ' out right now') : null,
            l.vehicles ? card('Gas pumps in use', l.vehicles.pumpsUsed, 'refilling') : null,
            l.loot ? card('Containers searched', l.loot.searches, l.loot.containers + ' filled since start') : null,
            card('Server up', Math.floor((l.uptimeMinutes || 0) / 60) + ' h ' + ((l.uptimeMinutes || 0) % 60) + ' min'));
        const bad = (d.modules || []).filter((m) => m.state !== 'running' || m.health === 'degraded');
        const modules = h('div', { class: 'wl-hint', text: (d.modules || []).length + ' modules, ' +
            (bad.length ? bad.length + ' with problems: ' + bad.map((m) => m.name + ' (' + m.state + ')').join(', ') : 'all running') });
        const issues = h('div', { class: 'wla-issues' });
        (d.issues || []).slice(-12).reverse().forEach((i) => issues.appendChild(h('div', { class: 'wla-issue is-' + i.level,
            text: (i.time || '') + ' ' + i.level.toUpperCase() + ' [' + i.module + '] ' + i.message })));
        if (!(d.issues || []).length) issues.appendChild(h('div', { class: 'wl-hint', text: 'No recent warnings or errors.' }));
        return h('div', {}, h('div', { class: 'wl-hint', text: 'Refreshes every 5 seconds while this tab is open.' }),
            cards, section('Modules'), modules, section('Latest warnings and errors'), issues);
    }

    // ---------------------------------------------------------------- coords

    // NUI has no clipboard permission; a selected textarea and the copy
    // command work in FiveM.
    function copyText(text) {
        const ta = h('textarea', { class: 'wla-clip' });
        ta.value = text;
        document.body.appendChild(ta);
        ta.select();
        let ok = false;
        try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
        ta.remove();
        message(ok ? 'Copied: ' + text : 'Could not copy. Select the text and press Ctrl+C.', ok ? 'ok' : 'error');
        if (ok) {
            st.copied = [text].concat((st.copied || []).filter((t) => t !== text)).slice(0, 8);
            if (st.tab === 'coords') render();
        }
    }

    function showCoords() {
        if (!st.coordsEls || !st.coords) return;
        st.coordsEls.forEach((e) => { e.el.textContent = coordText(st.coords, e.kind); });
    }

    function coordsTab() {
        const c = st.coords || { x: 0, y: 0, z: 0, h: 0 };
        st.coordsEls = [];
        const line = (label, kind) => {
            const code = h('code', { class: 'wla-coord', text: coordText(c, kind) });
            st.coordsEls.push({ el: code, kind: kind });
            return h('div', { class: 'wla-coordrow' }, h('span', { class: 'wla-label', text: label }), code,
                UI.button('Copy', () => copyText(coordText(st.coords || c, kind)), 'primary'));
        };
        const big = h('div', { class: 'wla-coordbig', text: coordText(c, 'xyz') });
        st.coordsEls.push({ el: big, kind: 'xyz' });
        const parts = [h('div', { class: 'wl-hint', text: 'Where you are standing now (updates live while this tab is open).' }), big,
            line('vector3', 'vector3'), line('vector4', 'vector4'), line('Heading', 'heading')];
        if ((st.copied || []).length) {
            parts.push(section('Copied'));
            st.copied.forEach((t) => parts.push(h('div', { class: 'wla-coordrow' }, h('code', { class: 'wla-coord', text: t }),
                UI.button('Copy again', () => copyText(t)))));
        }
        return h('div', {}, ...parts);
    }

    // ---------------------------------------------------------------- frame

    const TABS = [{ id: 'players', label: 'Players' }, { id: 'live', label: 'Live' }, { id: 'coords', label: 'Coords' },
        { id: 'bans', label: 'Bans' }, { id: 'server', label: 'Server & world' }, { id: 'log', label: 'Action log' }];
    const RENDER = { players: playersTab, live: liveTab, coords: coordsTab, bans: bansTab, server: serverTab, log: logTab };

    function render() {
        st.content.innerHTML = '';
        st.content.appendChild(RENDER[st.tab]());
    }

    function selectTab(id) {
        st.tab = id;
        clearInterval(st.liveTimer);
        clearInterval(st.coordsTimer);
        if (id === 'coords') {
            st.api.post('coords');
            st.coordsTimer = setInterval(() => st.api.post('coords'), 250);
        }
        if (id === 'live') {
            st.api.post('refresh');
            st.liveTimer = setInterval(() => st.api.post('refresh'), 5000);
        }
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
                if (st.tab === 'players' || st.tab === 'server' || st.tab === 'live') render();
            }
            if (data.list) {
                st[data.list.which] = data.list.rows || [];
                st.listNow = data.list.now;
                if (st.tab === data.list.which) render();
            }
            if (data.result) message(data.result.message, data.result.ok ? 'ok' : 'error');
            if (data.coords) { st.coords = data.coords; showCoords(); }
        },
        unmount: function () { document.removeEventListener('keydown', onKey); clearInterval(st.liveTimer); clearInterval(st.coordsTimer); st = null; },
    });

    const CSS = [
        '.wla-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }',
        '.wla-panel { position: relative; width: min(1180px, 94vw); height: 86vh; display: flex; flex-direction: column; }',
        '.wla-header { display: flex; align-items: center; gap: 10px; } .wla-header .wl-title { flex: 1; }',
        '.wla-clip { position: fixed; left: -1000px; top: -1000px; opacity: 0; }',
        '.wla-coordbig { font-family: Consolas, monospace; font-size: 22px; color: var(--wl-accent); margin: 12px 0 14px; }',
        '.wla-coordrow { display: flex; align-items: center; gap: 10px; margin: 6px 0; }',
        '.wla-coord { flex: 1; font-family: Consolas, monospace; font-size: 14px; padding: 7px 10px; background: var(--wl-bg-sunken);',
        '  border: 1px solid var(--wl-border); border-radius: 4px; user-select: text; }',
        '.wla-label { min-width: 70px; color: var(--wl-text-dim); font-size: 12px; text-transform: uppercase; letter-spacing: 0.06em; }',
        '.wla-mini { display: flex; flex-direction: column; gap: 4px; margin-bottom: 6px; }',
        '.wla-mini--grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(230px, 1fr)); gap: 4px 10px; }',
        '.wla-mini__row { display: flex; align-items: center; justify-content: space-between; gap: 10px; padding: 4px 8px;',
        '  background: var(--wl-bg-sunken); border-radius: 4px; }',
        '.wla-mini__row.is-known { color: #b6e39a; }',
        '.wla-cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 10px; margin: 10px 0; }',
        '.wla-card { background: var(--wl-bg-sunken); border: 1px solid var(--wl-border); border-radius: var(--wl-radius); padding: 12px 14px; }',
        '.wla-card__label { font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--wl-text-dim); }',
        '.wla-card__value { font-size: 28px; font-weight: 700; color: var(--wl-accent); font-variant-numeric: tabular-nums; margin: 2px 0; }',
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
        '.wla-row--top { align-items: flex-start; }',
        '.wla-pick { flex: 3; min-width: 240px; }',
        '.wla-pick__box { width: 100%; display: flex; align-items: center; gap: 8px; padding: 4px 10px 4px 4px; cursor: pointer; text-align: left;',
        '  background: var(--wl-bg-sunken); color: var(--wl-text); border: 1px solid var(--wl-border); border-radius: var(--wl-radius); font: inherit; }',
        '.wla-pick__box:hover, .wla-pick__box.is-open { border-color: var(--wl-accent); }',
        '.wla-pick__img { width: 34px; height: 34px; object-fit: contain; }',
        '.wla-pick__label { flex: 1; }',
        '.wla-pick__name { color: var(--wl-text-dim); font-size: 11px; font-family: monospace; }',
        '.wla-pick__caret { color: var(--wl-text-dim); }',
        '.wla-pick__panel { margin-top: 4px; background: var(--wl-bg);',
        '  border: 1px solid var(--wl-accent); border-radius: var(--wl-radius); box-shadow: 0 12px 30px rgba(0,0,0,0.6); padding: 6px; }',
        '.wla-pick__search { width: 100%; box-sizing: border-box; margin-bottom: 6px; }',
        '.wla-pick__list { max-height: 320px; overflow-y: auto; }',
        '.wla-pick__group { position: sticky; top: 0; background: var(--wl-bg); padding: 6px 4px 3px; font-size: 11px; text-transform: uppercase;',
        '  letter-spacing: 0.06em; color: var(--wl-accent); }',
        '.wla-pick__row { display: grid; grid-template-columns: 30px 1fr auto; align-items: center; gap: 8px; padding: 3px 6px; border-radius: 4px; cursor: pointer; }',
        '.wla-pick__row:hover { background: var(--wl-bg-sunken); }',
        '.wla-pick__row.is-chosen { background: rgba(217,130,43,0.18); }',
        '.wla-pick__rowimg { width: 28px; height: 28px; object-fit: contain; }',
        '.wla-pick__empty { padding: 8px; }',
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
