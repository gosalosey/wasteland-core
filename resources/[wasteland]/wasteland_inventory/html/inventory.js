// wasteland_inventory :: html/inventory.js
// Inventory screen (runs inside wasteland_ui): pockets, worn backpack,
// worn items, hotbar, and the ground/stash being searched. Drag items
// between grids (R rotates while dragging), right-click for actions,
// shift-click to quick-move. The server decides every change; the screen
// only previews placement (same rules as shared/grid.lua) and waits for the
// server's snapshot.

(function () {
    'use strict';

    // ------------------------------------------------------------------
    // Pure helpers (unit-tested with Node; mirror shared/grid.lua)
    // ------------------------------------------------------------------

    function footprint(def, rotated) {
        return rotated ? { w: def.height, h: def.width } : { w: def.width, h: def.height };
    }

    function overlaps(a, b) {
        return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h;
    }

    // Can `def` sit at (x, y) in `inv` (ignoring stack `ignoreUid`)?
    function fits(inv, defs, def, x, y, rotated, ignoreUid) {
        const f = footprint(def, rotated);
        if (!Number.isInteger(x) || !Number.isInteger(y)) return false;
        if (x < 0 || y < 0 || x + f.w > inv.width || y + f.h > inv.height) return false;
        const rect = { x: x, y: y, w: f.w, h: f.h };
        return inv.items.every((s) => {
            if (s.uid === ignoreUid || s.x === undefined || s.x === null) return true;
            const sf = footprint(defs[s.name] || { width: 1, height: 1 }, s.rotated);
            return !overlaps(rect, { x: s.x, y: s.y, w: sf.w, h: sf.h });
        });
    }

    function findSpot(inv, defs, def, ignoreUid) {
        for (const rotated of [false, true]) {
            if (rotated && def.width === def.height) continue;
            const f = footprint(def, rotated);
            for (let y = 0; y <= inv.height - f.h; y++) {
                for (let x = 0; x <= inv.width - f.w; x++) {
                    if (fits(inv, defs, def, x, y, rotated, ignoreUid)) return { x: x, y: y, rotated: rotated };
                }
            }
        }
        return null;
    }

    function stackAt(inv, defs, x, y) {
        for (const s of inv.items) {
            if (s.x === undefined || s.x === null) continue;
            const f = footprint(defs[s.name] || { width: 1, height: 1 }, s.rotated);
            if (x >= s.x && x < s.x + f.w && y >= s.y && y < s.y + f.h) return s;
        }
        return null;
    }

    function sameMeta(a, b) { return JSON.stringify(a || {}) === JSON.stringify(b || {}); }

    // What releasing a dragged stack over a target means.
    // drag = { stack, from, rotated }, target = { kind: 'grid', inv, x, y } | { kind: 'slot', slot }
    //   | { kind: 'hotbar', index } | { kind: 'ground' }
    // Returns { action, payload } or null.
    function decideDrop(drag, target, defs, equipId) {
        const s = drag.stack;
        const def = defs[s.name];
        if (!def || !target) return null;
        if (target.kind === 'hotbar') return { action: 'setHotbar', payload: { index: target.index, uid: s.uid } };
        if (target.kind === 'ground') return { action: 'drop', payload: { uid: s.uid, from: drag.from, count: s.count } };
        if (target.kind === 'slot') {
            if (def.equip !== target.slot || drag.from === equipId) return null;
            return { action: 'equip', payload: { uid: s.uid, from: drag.from, slot: target.slot } };
        }
        if (target.kind !== 'grid') return null;
        const under = stackAt(target.inv, defs, target.cellX, target.cellY);
        if (under && under.uid !== s.uid && under.name === s.name && def.stack > 1 && sameMeta(under.metadata, s.metadata)) {
            return { action: 'merge', payload: { uid: s.uid, from: drag.from, target: under.uid, to: target.inv.id, count: s.count } };
        }
        const ignore = drag.from === target.inv.id ? s.uid : null;
        if (!fits(target.inv, defs, def, target.x, target.y, drag.rotated, ignore)) return null;
        if (drag.from === equipId) {
            return { action: 'unequip', payload: { slot: s.slot, to: target.inv.id, x: target.x, y: target.y, rotated: drag.rotated } };
        }
        return { action: 'move', payload: { uid: s.uid, from: drag.from, to: target.inv.id, x: target.x, y: target.y, rotated: drag.rotated } };
    }

    function formatKg(v) { return (Math.round(v * 10) / 10).toFixed(1); }

    // Short label for a tile: whole label when it fits, else initials.
    function shortLabel(label, cellsWide) {
        if (label.length <= cellsWide * 7) return label;
        return label.split(/\s+/).map((w) => w[0]).join('').toUpperCase().slice(0, 4);
    }

    if (typeof module === 'object' && module.exports) {
        module.exports = { footprint: footprint, fits: fits, findSpot: findSpot, stackAt: stackAt, decideDrop: decideDrop,
            formatKg: formatKg, shortLabel: shortLabel };
        return;
    }

    // ------------------------------------------------------------------
    // Screen
    // ------------------------------------------------------------------

    const UI = window.WastelandUI;
    const h = UI.h;
    const CELL = 50;
    const CATEGORY_COLORS = {
        food: '#6d7f3a', drink: '#3d6f8a', medical: '#8a3d3d', material: '#6b5f50', tool: '#7a6a3a',
        clothing: '#5a4d6e', container: '#4e5f45', weapon: '#5d5d5d', ammo: '#7d6b2e', misc: '#555048',
    };
    let st; // screen state

    function invById(id) { return st.snap.inventories.find((i) => i.id === id); }

    function setMessage(text, kind) {
        st.message.textContent = text || '';
        st.message.className = 'wl-message' + (kind ? ' is-' + kind : '');
        clearTimeout(st.messageTimer);
        if (text) st.messageTimer = setTimeout(() => setMessage(''), 5000);
    }

    function closeMenu() { if (st.menu) { st.menu.remove(); st.menu = null; } }

    function tile(stack, inv, opts) {
        const def = st.defs.items[stack.name] || { label: stack.name, width: 1, height: 1, category: 'misc' };
        const f = opts && opts.fixed ? { w: opts.fixed, h: opts.fixed } : footprint(def, stack.rotated);
        const el = h('div', { class: 'wli-item', title: def.label + (def.description ? ' – ' + def.description : '') });
        el.style.width = (f.w * CELL - 4) + 'px';
        el.style.height = (f.h * CELL - 4) + 'px';
        el.style.background = def.color || CATEGORY_COLORS[def.category] || CATEGORY_COLORS.misc;
        if (!(opts && opts.fixed)) {
            el.style.left = (stack.x * CELL + 2) + 'px';
            el.style.top = (stack.y * CELL + 2) + 'px';
        }
        if (def.image) {
            // The picture keeps its own orientation box and turns with the item.
            el.classList.add('has-image');
            const img = h('img', { class: 'wli-item__img', src: def.image, draggable: false });
            const turned = !!stack.rotated && !(opts && opts.fixed);
            img.style.width = ((turned ? f.h : f.w) * CELL - 10) + 'px';
            img.style.height = ((turned ? f.w : f.h) * CELL - 10) + 'px';
            if (turned) img.style.transform = 'translate(-50%, -50%) rotate(90deg)';
            img.addEventListener('error', () => { img.remove(); el.classList.remove('has-image'); });
            el.appendChild(img);
        }
        el.appendChild(h('span', { class: 'wli-item__label', text: shortLabel(def.label, f.w) }));
        if (stack.count > 1) el.appendChild(h('span', { class: 'wli-item__count', text: 'x' + stack.count }));
        if (def.durability > 0 && stack.metadata && typeof stack.metadata.durability === 'number') {
            const bar = h('span', { class: 'wli-item__dur' });
            bar.style.width = Math.max(0, Math.min(100, stack.metadata.durability / def.durability * 100)) + '%';
            el.appendChild(bar);
        }
        const hot = st.snap.hotbar ? st.snap.hotbar.indexOf(stack.uid) : -1;
        if (hot >= 0) el.appendChild(h('span', { class: 'wli-item__hot', text: String(hot + 1) }));
        el.addEventListener('mousedown', (e) => startDrag(e, stack, inv.id, el));
        el.addEventListener('contextmenu', (e) => { e.preventDefault(); openMenu(e, stack, inv.id); });
        return el;
    }

    function gridPanel(inv, title) {
        const grid = h('div', { class: 'wli-grid' });
        grid.style.width = (inv.width * CELL) + 'px';
        grid.style.height = (inv.height * CELL) + 'px';
        grid.dataset.inv = inv.id;
        inv.items.forEach((s) => { if (s.x !== undefined && s.x !== null) grid.appendChild(tile(s, inv)); });
        const heavy = inv.weight > inv.maxWeight * 0.9;
        return h('div', { class: 'wli-section' },
            h('div', { class: 'wli-section__head' },
                h('span', { class: 'wl-section-title', text: title || inv.label }),
                inv.maxWeight < 100000 ? h('span', { class: 'wli-weight' + (heavy ? ' is-heavy' : ''),
                    text: formatKg(inv.weight) + ' / ' + formatKg(inv.maxWeight) + ' kg' }) : null),
            grid);
    }

    function equipmentPanel() {
        const equip = invById(st.snap.equip);
        const bySlot = {};
        (equip ? equip.items : []).forEach((s) => { bySlot[s.slot] = s; });
        const box = h('div', { class: 'wli-slots' });
        st.defs.slots.forEach((slot) => {
            const cell = h('div', { class: 'wli-slot' }, h('span', { class: 'wli-slot__label', text: st.defs.slotLabels[slot] || slot }));
            cell.dataset.slot = slot;
            if (bySlot[slot]) cell.appendChild(tile(bySlot[slot], equip, { fixed: 2 }));
            box.appendChild(cell);
        });
        return h('div', { class: 'wli-section' }, h('div', { class: 'wli-section__head' }, h('span', { class: 'wl-section-title', text: 'Worn' })), box);
    }

    function findStack(uid) {
        for (const inv of st.snap.inventories) {
            const s = inv.items.find((x) => x.uid === uid);
            if (s) return { stack: s, inv: inv };
        }
        return null;
    }

    function hotbarPanel() {
        const row = h('div', { class: 'wli-hotbar' });
        for (let i = 0; i < 5; i++) {
            const uid = st.snap.hotbar && st.snap.hotbar[i];
            const found = uid ? findStack(uid) : null;
            const cell = h('div', { class: 'wli-hot' }, h('span', { class: 'wli-hot__key', text: String(i + 1) }));
            cell.dataset.hotbar = String(i + 1);
            if (found) {
                const def = st.defs.items[found.stack.name];
                cell.appendChild(h('span', { class: 'wli-hot__name', text: def ? def.label : found.stack.name }));
            }
            cell.addEventListener('contextmenu', (e) => { e.preventDefault(); st.api.post('setHotbar', { index: i + 1 }); });
            row.appendChild(cell);
        }
        return h('div', { class: 'wli-section' },
            h('div', { class: 'wli-section__head' }, h('span', { class: 'wl-section-title', text: 'Hotbar (keys 1-5, right-click to clear)' })), row);
    }

    function render() {
        closeMenu();
        st.left.innerHTML = '';
        st.middle.innerHTML = '';
        st.right.innerHTML = '';
        st.left.appendChild(equipmentPanel());
        st.left.appendChild(hotbarPanel());
        const pockets = invById(st.snap.pockets);
        if (pockets) st.middle.appendChild(gridPanel(pockets, 'Pockets'));
        if (st.snap.backpack && invById(st.snap.backpack)) st.middle.appendChild(gridPanel(invById(st.snap.backpack)));
        (st.snap.secondary || []).forEach((id) => { const inv = invById(id); if (inv) st.right.appendChild(gridPanel(inv)); });
        const ground = h('div', { class: 'wli-ground', text: 'Drop here to put items on the ground' });
        ground.dataset.ground = '1';
        st.right.appendChild(ground);
    }

    // ---------------------------------------------------------------- drag

    function startDrag(e, stack, fromId, el) {
        if (e.button !== 0) return;
        e.preventDefault();
        closeMenu();
        if (e.shiftKey) { quickMove(stack, fromId); return; }
        const rect = el.getBoundingClientRect();
        const ghost = el.cloneNode(true);
        ghost.classList.add('wli-ghost');
        ghost.style.left = rect.left + 'px';
        ghost.style.top = rect.top + 'px';
        st.root.appendChild(ghost);
        el.classList.add('is-dragging');
        st.drag = {
            stack: stack, from: fromId, rotated: !!stack.rotated, el: el, ghost: ghost,
            grabX: Math.min(Math.floor((e.clientX - rect.left) / CELL), 9),
            grabY: Math.min(Math.floor((e.clientY - rect.top) / CELL), 9),
            offX: e.clientX - rect.left, offY: e.clientY - rect.top,
        };
        moveGhost(e);
    }

    // `drag` is passed in: on release st.drag is already cleared.
    function targetAt(clientX, clientY, drag) {
        const under = document.elementsFromPoint(clientX, clientY);
        for (const el of under) {
            if (el.dataset && el.dataset.inv) {
                const rect = el.getBoundingClientRect();
                const inv = invById(el.dataset.inv);
                const cellX = Math.floor((clientX - rect.left) / CELL);
                const cellY = Math.floor((clientY - rect.top) / CELL);
                return { kind: 'grid', inv: inv, el: el, cellX: cellX, cellY: cellY,
                    x: cellX - drag.grabX, y: cellY - drag.grabY };
            }
            if (el.dataset && el.dataset.slot) return { kind: 'slot', slot: el.dataset.slot, el: el };
            if (el.dataset && el.dataset.hotbar) return { kind: 'hotbar', index: Number(el.dataset.hotbar), el: el };
            if (el.dataset && el.dataset.ground) return { kind: 'ground', el: el };
        }
        return null;
    }

    function clearPreview() {
        if (st.preview) { st.preview.remove(); st.preview = null; }
        st.root.querySelectorAll('.is-target').forEach((x) => x.classList.remove('is-target'));
    }

    function moveGhost(e) {
        const d = st.drag;
        const def = st.defs.items[d.stack.name];
        const f = footprint(def, d.rotated);
        d.ghost.style.width = (f.w * CELL - 4) + 'px';
        d.ghost.style.height = (f.h * CELL - 4) + 'px';
        d.ghost.style.left = (e.clientX - d.grabX * CELL - CELL / 2) + 'px';
        d.ghost.style.top = (e.clientY - d.grabY * CELL - CELL / 2) + 'px';
        clearPreview();
        const target = targetAt(e.clientX, e.clientY, d);
        const decision = decideDrop(d, target, st.defs.items, st.snap.equip);
        if (target && target.kind === 'grid' && target.inv) {
            const p = h('div', { class: 'wli-preview' + (decision ? '' : ' is-bad') });
            p.style.left = (Math.max(0, target.x) * CELL) + 'px';
            p.style.top = (Math.max(0, target.y) * CELL) + 'px';
            p.style.width = (f.w * CELL) + 'px';
            p.style.height = (f.h * CELL) + 'px';
            target.el.appendChild(p);
            st.preview = p;
        } else if (target && decision) {
            target.el.classList.add('is-target');
        }
        d.lastEvent = { clientX: e.clientX, clientY: e.clientY };
    }

    function endDrag(e) {
        const d = st.drag;
        st.drag = null;
        clearPreview();
        d.ghost.remove();
        d.el.classList.remove('is-dragging');
        const target = targetAt(e.clientX, e.clientY, d);
        const decision = decideDrop(d, target, st.defs.items, st.snap.equip);
        if (decision) st.api.post(decision.action, decision.payload);
        else if (target) setMessage('That does not fit there.', 'error');
    }

    // Shift-click: move between your inventories and the searched one.
    function quickMove(stack, fromId) {
        const def = st.defs.items[stack.name];
        const mine = [st.snap.pockets, st.snap.backpack].filter(Boolean);
        const others = st.snap.secondary || [];
        const targets = mine.indexOf(fromId) >= 0 ? others : mine;
        for (const id of targets) {
            const inv = invById(id);
            const spot = inv && findSpot(inv, st.defs.items, def);
            if (spot) {
                st.api.post('move', { uid: stack.uid, from: fromId, to: id, x: spot.x, y: spot.y, rotated: spot.rotated });
                return;
            }
        }
        setMessage(targets.length ? 'No room for that.' : 'Nothing is open to move it to.', 'error');
    }

    // ---------------------------------------------------------------- menu

    function openMenu(e, stack, fromId) {
        closeMenu();
        const def = st.defs.items[stack.name];
        const worn = fromId === st.snap.equip;
        const items = [];
        if (def.usable) items.push(['Use', () => st.api.post('use', { uid: stack.uid, from: fromId })]);
        if (def.equip && !worn) items.push(['Wear', () => st.api.post('equip', { uid: stack.uid, from: fromId, slot: def.equip })]);
        if (worn) items.push(['Take off', () => st.api.post('unequip', { slot: stack.slot, to: st.snap.pockets })]);
        if (!worn && stack.count > 1) items.push(['Split…', () => openSplit(e, stack, fromId)]);
        for (let i = 1; i <= 5; i++) {
            if (!worn) items.push(['Hotbar ' + i, () => st.api.post('setHotbar', { index: i, uid: stack.uid })]);
        }
        items.push(['Drop', () => st.api.post('drop', { uid: stack.uid, from: fromId, count: stack.count })]);
        const menu = h('div', { class: 'wli-menu' },
            h('div', { class: 'wli-menu__title', text: def.label + (stack.count > 1 ? ' x' + stack.count : '') }));
        items.forEach(([label, fn]) => menu.appendChild(h('button', { class: 'wli-menu__item', text: label,
            onclick: () => { closeMenu(); fn(); } })));
        menu.style.left = Math.min(e.clientX, window.innerWidth - 190) + 'px';
        menu.style.top = Math.min(e.clientY, window.innerHeight - 40 - items.length * 30) + 'px';
        st.root.appendChild(menu);
        st.menu = menu;
    }

    function openSplit(e, stack, fromId) {
        closeMenu();
        const input = h('input', { class: 'wl-input', attrs: { type: 'number', min: '1', max: String(stack.count - 1) } });
        input.value = Math.floor(stack.count / 2);
        const go = () => {
            const n = Math.floor(Number(input.value));
            closeMenu();
            if (n >= 1 && n < stack.count) st.api.post('split', { uid: stack.uid, from: fromId, count: n });
            else setMessage('Choose 1 to ' + (stack.count - 1) + '.', 'error');
        };
        input.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') go(); });
        const menu = h('div', { class: 'wli-menu' }, h('div', { class: 'wli-menu__title', text: 'Split how many?' }), input,
            h('button', { class: 'wli-menu__item', text: 'Split', onclick: go }));
        menu.style.left = Math.min(e.clientX, window.innerWidth - 190) + 'px';
        menu.style.top = Math.min(e.clientY, window.innerHeight - 140) + 'px';
        st.root.appendChild(menu);
        st.menu = menu;
        setTimeout(() => input.focus(), 0);
    }

    // ---------------------------------------------------------------- lifecycle

    function onMouseMove(e) { if (st && st.drag) moveGhost(e); }
    function onMouseUp(e) { if (st && st.drag) endDrag(e); }
    function onKey(e) {
        if (!st) return;
        if (st.drag && (e.key === 'r' || e.key === 'R')) {
            st.drag.rotated = !st.drag.rotated;
            const g = st.drag.grabX; st.drag.grabX = st.drag.grabY; st.drag.grabY = g;
            if (st.drag.lastEvent) moveGhost(st.drag.lastEvent);
            return;
        }
        if (e.key === 'Escape' || e.key === 'i' || e.key === 'I' || e.key === 'Tab') {
            if (st.menu) { closeMenu(); return; }
            if (e.target && e.target.tagName === 'INPUT') return;
            e.preventDefault();
            st.api.post('close');
        }
    }
    function onClick(e) { if (st && st.menu && !st.menu.contains(e.target)) closeMenu(); }

    UI.registerScreen('inventory', {
        mount: function (el, data, api) {
            st = { api: api, defs: data.defs, snap: data.snapshot, drag: null, menu: null, preview: null };
            st.left = h('div', { class: 'wli-col' });
            st.middle = h('div', { class: 'wli-col wli-col--main' });
            st.right = h('div', { class: 'wli-col' });
            st.message = h('div', { class: 'wl-message' });
            st.root = h('div', { class: 'wli-root' },
                h('div', { class: 'wl-backdrop' }),
                h('div', { class: 'wli-layout' },
                    h('div', { class: 'wli-header' },
                        h('h1', { class: 'wl-title', text: 'Inventory' }),
                        h('span', { class: 'wl-hint', text: 'Drag to move · R rotates while dragging · Right-click for actions · Shift-click to quick-move · TAB or Esc closes' })),
                    h('div', { class: 'wli-columns' }, st.left, st.middle, st.right),
                    st.message));
            el.appendChild(st.root);
            el.appendChild(h('style', { text: CSS }));
            document.addEventListener('mousemove', onMouseMove);
            document.addEventListener('mouseup', onMouseUp);
            document.addEventListener('keydown', onKey);
            document.addEventListener('click', onClick);
            render();
        },
        update: function (data) {
            if (data.defs) st.defs = data.defs;
            if (data.snapshot) {
                st.snap = data.snapshot;
                if (st.drag) { st.drag.ghost.remove(); st.drag = null; clearPreview(); }
                render();
            }
            if (data.error) setMessage(data.error, 'error');
            if (data.notice) setMessage(data.notice, 'ok');
        },
        unmount: function () {
            document.removeEventListener('mousemove', onMouseMove);
            document.removeEventListener('mouseup', onMouseUp);
            document.removeEventListener('keydown', onKey);
            document.removeEventListener('click', onClick);
            clearTimeout(st.messageTimer);
            st = null;
        },
    });

    const CSS = [
        '.wli-root { position: absolute; inset: 0; }',
        '.wli-layout { position: absolute; inset: 4vh 3vw; display: flex; flex-direction: column; gap: 10px; }',
        '.wli-header { display: flex; align-items: baseline; gap: 18px; }',
        '.wli-columns { flex: 1; display: flex; gap: 22px; align-items: flex-start; overflow: auto; }',
        '.wli-col { display: flex; flex-direction: column; gap: 16px; }',
        '.wli-col--main { flex: 0 0 auto; }',
        '.wli-section { background: var(--wl-bg); border: 1px solid var(--wl-border); border-radius: var(--wl-radius); padding: 10px 12px 12px; }',
        '.wli-section__head { display: flex; justify-content: space-between; align-items: baseline; gap: 12px; margin-bottom: 6px; }',
        '.wli-section__head .wl-section-title { margin: 0; }',
        '.wli-weight { font-size: 12px; color: var(--wl-text-dim); font-variant-numeric: tabular-nums; }',
        '.wli-weight.is-heavy { color: #ffb37a; }',
        '.wli-grid { position: relative; background-color: var(--wl-bg-sunken);',
        '  background-image: linear-gradient(to right, rgba(255,255,255,0.06) 1px, transparent 1px), linear-gradient(to bottom, rgba(255,255,255,0.06) 1px, transparent 1px);',
        '  background-size: ' + CELL + 'px ' + CELL + 'px; border: 1px solid var(--wl-border); }',
        '.wli-item { position: absolute; border-radius: 4px; border: 1px solid rgba(0,0,0,0.5); box-shadow: inset 0 0 0 1px rgba(255,255,255,0.08);',
        '  cursor: grab; overflow: hidden; display: flex; align-items: center; justify-content: center; text-align: center; }',
        '.wli-item:hover { box-shadow: inset 0 0 0 1px var(--wl-accent); }',
        '.wli-item.is-dragging { opacity: 0.35; }',
        '.wli-item__label { position: relative; font-size: 11px; line-height: 1.15; padding: 2px 4px; text-shadow: 0 1px 2px #000; }',
        '.wli-item.has-image { background-color: rgba(30,30,28,0.92) !important; }',
        '.wli-item.has-image .wli-item__label { font-size: 10px; opacity: 0.85; }',
        '.wli-item__img { position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); object-fit: contain; pointer-events: none; }',
        '.wli-item__count { position: absolute; right: 3px; bottom: 1px; font-size: 11px; font-weight: 600; text-shadow: 0 1px 2px #000; }',
        '.wli-item__hot { position: absolute; left: 3px; top: 1px; font-size: 10px; color: var(--wl-accent-strong); font-weight: 700; }',
        '.wli-item__dur { position: absolute; left: 0; bottom: 0; height: 3px; background: var(--wl-ok); }',
        '.wli-ghost { position: fixed; pointer-events: none; z-index: 50; opacity: 0.9; }',
        '.wli-preview { position: absolute; pointer-events: none; background: rgba(127,174,90,0.25); border: 1px solid var(--wl-ok); }',
        '.wli-preview.is-bad { background: rgba(196,69,58,0.25); border-color: var(--wl-danger); }',
        '.wli-slots { display: grid; grid-template-columns: repeat(2, ' + (2 * CELL + 8) + 'px); gap: 8px; }',
        '.wli-slot { position: relative; width: ' + (2 * CELL + 8) + 'px; height: ' + (2 * CELL + 22) + 'px; background: var(--wl-bg-sunken);',
        '  border: 1px dashed var(--wl-border); border-radius: var(--wl-radius); display: flex; flex-direction: column; align-items: center; padding-top: 2px; }',
        '.wli-slot .wli-item { position: relative; }',
        '.wli-slot__label { font-size: 11px; color: var(--wl-text-dim); }',
        '.wli-slot.is-target, .wli-hot.is-target, .wli-ground.is-target { border-color: var(--wl-ok); border-style: solid; }',
        '.wli-hotbar { display: flex; gap: 6px; }',
        '.wli-hot { position: relative; width: 52px; height: 52px; background: var(--wl-bg-sunken); border: 1px solid var(--wl-border);',
        '  border-radius: 4px; display: flex; align-items: center; justify-content: center; text-align: center; }',
        '.wli-hot__key { position: absolute; left: 4px; top: 2px; font-size: 10px; color: var(--wl-accent); }',
        '.wli-hot__name { font-size: 10px; padding: 0 2px; }',
        '.wli-ground { min-width: 220px; padding: 22px 14px; text-align: center; color: var(--wl-text-dim); font-size: 13px;',
        '  border: 1px dashed var(--wl-border); border-radius: var(--wl-radius); background: var(--wl-bg); }',
        '.wli-menu { position: fixed; z-index: 60; min-width: 170px; background: var(--wl-bg-raised); border: 1px solid var(--wl-border);',
        '  border-radius: var(--wl-radius); box-shadow: 0 8px 24px rgba(0,0,0,0.6); padding: 6px; display: flex; flex-direction: column; gap: 2px; }',
        '.wli-menu__title { font-size: 12px; color: var(--wl-accent); padding: 4px 8px 6px; }',
        '.wli-menu__item { font: inherit; font-size: 13px; text-align: left; color: var(--wl-text); background: transparent; border: 0;',
        '  border-radius: 4px; padding: 6px 8px; cursor: pointer; }',
        '.wli-menu__item:hover { background: rgba(217,130,43,0.2); }',
    ].join('\n');
})();
