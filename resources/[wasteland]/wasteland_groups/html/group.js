// wasteland_groups :: html/group.js
// The group screen: an invitation, making a group, or your group (members,
// online or not, invite, and for the leader: kick, make leader, rename,
// disband).
// Data: { view = { me, maxMembers, nameMin, nameMax, group?, invite? }, nearby = [{ server, name, distance }] }
// Posts: create {name}, invite {server}, accept/decline {group}, leave, kick/promote {id}, disband, rename {name}, close

(function () {
    'use strict';

    // Pure helper (unit-tested): the members line, e.g. "3 of 8 members, 2 online".
    function summary(group, max) {
        const n = group.members.length;
        const on = group.members.filter((m) => m.online).length;
        return n + ' of ' + max + ' members, ' + on + ' online';
    }

    if (typeof module === 'object' && module.exports) { module.exports = { summary: summary }; return; }

    const UI = window.WastelandUI;
    const h = UI.h;
    let st = null;

    // A button that needs a second click within 4 s (for leave, kick, disband).
    function confirmButton(label, fn, variant) {
        let armed = false, timer = null;
        const b = UI.button(label, () => {
            if (armed) { clearTimeout(timer); fn(); return; }
            armed = true;
            b.textContent = 'Sure? Click again';
            timer = setTimeout(() => { armed = false; b.textContent = label; }, 4000);
        }, variant);
        return b;
    }

    function input(placeholder, max) {
        return h('input', { class: 'wl-input', attrs: { placeholder: placeholder, maxlength: String(max || 32) } });
    }

    function render() {
        const v = st.view;
        st.body.innerHTML = '';
        if (!v) { st.body.appendChild(h('div', { class: 'wl-hint', text: 'Loading...' })); return; }
        if (v.invite) {
            st.body.appendChild(h('div', { class: 'wgr-invite' },
                h('div', { text: v.invite.by + ' invites you to the group' }),
                h('div', { class: 'wgr-invite__name', text: v.invite.name }),
                h('div', { class: 'wgr-row' },
                    UI.button('Join', () => st.api.post('accept', { group: v.invite.group }), 'primary'),
                    UI.button('No thanks', () => st.api.post('decline', { group: v.invite.group })))));
        }
        if (!v.group) {
            const name = input('Group name', v.nameMax);
            st.body.appendChild(h('div', { class: 'wl-section-title', text: 'Make a group' }));
            st.body.appendChild(h('div', { class: 'wl-hint', text: 'Name it (' + v.nameMin + '-' + v.nameMax + ' characters), then invite players. Members see each other on the map. The group stays until its leader disbands it.' }));
            st.body.appendChild(h('div', { class: 'wgr-row' }, name, UI.button('Create', () => st.api.post('create', { name: name.value }), 'primary')));
            return;
        }
        const g = v.group;
        st.body.appendChild(h('div', { class: 'wgr-name', text: g.name }));
        st.body.appendChild(h('div', { class: 'wl-hint', text: summary(g, v.maxMembers) + (g.leader ? ' · you lead it' : '') }));
        const list = h('div', { class: 'wgr-members' });
        g.members.forEach((m) => {
            const row = h('div', { class: 'wgr-member' + (m.online ? '' : ' is-offline') },
                h('span', { class: 'wgr-dot' + (m.online ? ' is-on' : '') }),
                h('span', { class: 'wgr-mname', text: m.name + (m.id === v.me ? ' (you)' : '') }),
                m.leader ? h('span', { class: 'wgr-tag', text: 'LEADER' }) : null,
                h('span', { class: 'wl-hint', text: m.online ? '#' + m.server : 'offline' }));
            if (g.leader && m.id !== v.me) {
                row.appendChild(h('span', { class: 'wgr-actions' },
                    confirmButton('Make leader', () => st.api.post('promote', { id: m.id })),
                    confirmButton('Remove', () => st.api.post('kick', { id: m.id }))));
            }
            list.appendChild(row);
        });
        st.body.appendChild(list);
        if (g.leader) {
            st.body.appendChild(h('div', { class: 'wl-section-title', text: 'Invite' }));
            const id = h('input', { class: 'wl-input wgr-id', attrs: { placeholder: 'Player id', type: 'number', min: '1' } });
            st.body.appendChild(h('div', { class: 'wgr-row' }, id, UI.button('Invite', () => st.api.post('invite', { server: id.value }), 'primary')));
            if (st.nearby.length) {
                const near = h('div', { class: 'wgr-near' });
                st.nearby.forEach((p) => near.appendChild(UI.button('#' + p.server + ' ' + p.name + ' (' + p.distance + ' m)', () => st.api.post('invite', { server: p.server }))));
                st.body.appendChild(h('div', { class: 'wl-hint', text: 'Near you:' }));
                st.body.appendChild(near);
            }
            const name = input('New name', v.nameMax);
            st.body.appendChild(h('div', { class: 'wl-section-title', text: 'Leader' }));
            st.body.appendChild(h('div', { class: 'wgr-row' }, name, UI.button('Rename', () => st.api.post('rename', { name: name.value })),
                confirmButton('Disband the group', () => st.api.post('disband'), 'danger')));
        } else {
            st.body.appendChild(h('div', { class: 'wgr-row' }, confirmButton('Leave the group', () => st.api.post('leave'))));
        }
    }

    function onKey(e) { if (st && (e.key === 'Escape' || e.key === 'F6') && e.target.tagName !== 'INPUT') st.api.post('close'); }

    UI.registerScreen('groupScreen', {
        mount: function (el, data, api) {
            st = { api: api, view: data.view, nearby: data.nearby || [] };
            st.body = h('div', { class: 'wgr-body' });
            st.message = h('div', { class: 'wl-message' });
            el.appendChild(h('div', { class: 'wgr-root' },
                h('div', { class: 'wl-panel wgr-panel' },
                    h('div', { class: 'wgr-head' }, h('h1', { class: 'wl-title', text: 'Group' }), UI.button('Close', () => api.post('close'))),
                    st.body, st.message)));
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('keydown', onKey);
            render();
        },
        update: function (data) {
            if (data.view !== undefined) { st.view = data.view; if (data.nearby) st.nearby = data.nearby; render(); }
            if (data.message) st.message.textContent = data.message;
        },
        unmount: function () { document.removeEventListener('keydown', onKey); st = null; },
    });

    const CSS = [
        '.wgr-root { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; }',
        '.wgr-panel { width: min(560px, 94vw); max-height: 86vh; display: flex; flex-direction: column; gap: 8px; }',
        '.wgr-head { display: flex; align-items: center; } .wgr-head .wl-title { flex: 1; }',
        '.wgr-body { overflow-y: auto; display: flex; flex-direction: column; gap: 8px; }',
        '.wgr-row { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; } .wgr-row .wl-input { flex: 1; min-width: 140px; }',
        '.wgr-id { max-width: 120px; }',
        '.wgr-name { font-size: 22px; font-weight: 700; color: var(--wl-accent); }',
        '.wgr-members { display: flex; flex-direction: column; gap: 4px; }',
        '.wgr-member { display: flex; align-items: center; gap: 8px; padding: 6px 8px; background: var(--wl-bg-sunken); border: 1px solid var(--wl-border); border-radius: 5px; }',
        '.wgr-member.is-offline { opacity: 0.6; }',
        '.wgr-dot { width: 8px; height: 8px; border-radius: 50%; background: #666; } .wgr-dot.is-on { background: #7fc75a; }',
        '.wgr-mname { flex: 1; }',
        '.wgr-tag { font-size: 10px; font-weight: 700; color: #e8c25a; letter-spacing: 0.08em; }',
        '.wgr-actions { display: flex; gap: 4px; } .wgr-actions .wl-btn { padding: 2px 8px; font-size: 12px; }',
        '.wgr-near { display: flex; flex-wrap: wrap; gap: 4px; } .wgr-near .wl-btn { font-size: 12px; padding: 3px 8px; }',
        '.wgr-invite { border: 1px solid var(--wl-accent); border-radius: var(--wl-radius); padding: 10px 12px; display: flex; flex-direction: column; gap: 6px; background: rgba(127,199,90,0.08); }',
        '.wgr-invite__name { font-size: 18px; font-weight: 700; }',
    ].join('\n');
})();
