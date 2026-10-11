// wasteland_inventory :: html/inventory.js
// Inventory screen (runs inside wasteland_ui): pockets, worn backpack,
// worn items, hotbar, and the ground/stash being searched. Drag items
// between grids (R rotates while dragging), right-click for actions,
// double-click or shift-click to quick-move. The server decides every change; the screen
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

    // Quick move (double-click or shift-click): from a searched / opened
    // inventory into yours (pockets, then backpack), or from yours into the
    // opened one. Tops up a matching stack first, then uses free space.
    // Returns { action, payload } or { error } or null (nothing to move to).
    function quickTarget(stack, fromId, snap, defs) {
        const def = defs[stack.name];
        if (!def) return null;
        const mine = [snap.pockets, snap.backpack].filter(Boolean);
        const others = snap.secondary || [];
        const targets = mine.indexOf(fromId) >= 0 ? others : mine;
        if (!targets.length) return null;
        const byId = (id) => snap.inventories.find((i) => i.id === id);
        // Room for `n` more units by weight (the server checks again).
        const light = (inv, n) => typeof inv.maxWeight !== 'number' || (inv.weight || 0) + (def.weight || 0) * n <= inv.maxWeight + 1e-9;
        let heavy = false;
        if (def.stack > 1) {
            for (const id of targets) {
                const inv = byId(id);
                if (inv && !light(inv, 1)) { heavy = true; continue; }
                const under = inv && inv.items.find((s) => s.uid !== stack.uid && s.name === stack.name
                    && s.count < def.stack && sameMeta(s.metadata, stack.metadata));
                if (under) {
                    let count = Math.min(stack.count, def.stack - under.count);
                    while (count > 1 && !light(inv, count)) count--;
                    return { action: 'merge', payload: { uid: stack.uid, from: fromId, target: under.uid, to: id, count: count } };
                }
            }
        }
        for (const id of targets) {
            const inv = byId(id);
            if (inv && !light(inv, stack.count)) { heavy = true; continue; }
            const spot = inv && findSpot(inv, defs, def);
            if (spot) return { action: 'move', payload: { uid: stack.uid, from: fromId, to: id, x: spot.x, y: spot.y, rotated: spot.rotated } };
        }
        return { error: heavy ? 'Too heavy to carry.' : 'No room for that.' };
    }

    // Body temperature in Fahrenheit, and how it feels.
    function toF(c) { return Math.round((c * 9 / 5 + 32) * 10) / 10; }
    function feels(c, lim) {
        if (typeof c !== 'number') return null;
        const l = lim || {};
        if (c <= (l.hypothermia || 35)) return 'Freezing';
        if (c <= 35.5) return 'Cold';
        if (c >= (l.hyperthermia || 39.5)) return 'Overheating';
        if (c >= 38.5) return 'Hot';
        return 'Comfortable';
    }

    // Health panel: what is wrong and how to fix it.
    // v = { health, armor, hunger, thirst, temperature, bleeding, infection, treatment, dead, cures, limits }
    // -> [{ key, level: 'low' | 'critical', title, fix }]
    function conditions(v) {
        if (!v || v.dead) return [];
        const c = v.cures || {};
        const lim = v.limits || {};
        const list = (names, verb, fallback) => (names && names.length ? verb + ' ' + names.join(', ') + '.' : fallback);
        const out = [];
        const r = (x) => Math.round(Number(x) || 0);
        if (v.bleeding > 0) {
            const lvl = Math.min(3, v.bleeding);
            out.push({ key: 'bleeding', level: lvl >= 2 ? 'critical' : 'low',
                title: ['', 'Bleeding', 'Bleeding heavily', 'Bleeding severely'][lvl],
                fix: list(c.bleeding, 'Stop it with:', 'Find something to stop the bleeding.') + ' Light bleeding may stop by itself; heavy bleeding will not.' });
        }
        if (v.infection > 0) {
            const hurts = r(v.infection) >= (lim.infectionDamage || 60);
            out.push({ key: 'infection', level: hurts ? 'critical' : 'low',
                title: 'Infected ' + r(v.infection) + '%' + (v.treatment ? ' (treated)' : ''),
                fix: v.treatment ? 'The medicine is working; it cannot get worse for now.'
                    : list(c.infection, 'Treat it with:', 'Find antibiotics.') + (hurts ? ' It is hurting you now.' : ' It grows over time and hurts you at ' + (lim.infectionDamage || 60) + '%.') });
        }
        if (typeof v.health === 'number' && v.health < 60) {
            out.push({ key: 'health', level: v.health <= 25 ? 'critical' : 'low', title: 'Hurt (health ' + r(v.health) + '%)',
                fix: list(c.health, 'Heal with:', 'Find medical supplies.') });
        }
        if (typeof v.hunger === 'number' && v.hunger <= 35) {
            out.push({ key: 'hunger', level: v.hunger <= 15 ? 'critical' : 'low', title: v.hunger <= 0 ? 'Starving' : 'Hungry (' + r(v.hunger) + '%)',
                fix: list(c.hunger, 'Eat:', 'Find food.') });
        }
        if (typeof v.thirst === 'number' && v.thirst <= 35) {
            out.push({ key: 'thirst', level: v.thirst <= 15 ? 'critical' : 'low', title: v.thirst <= 0 ? 'Dehydrated' : 'Thirsty (' + r(v.thirst) + '%)',
                fix: list(c.thirst, 'Drink:', 'Find water.') });
        }
        if (typeof v.temperature === 'number') {
            const t = Math.round(v.temperature * 10) / 10;
            if (t <= 35.5) {
                out.push({ key: 'cold', level: t <= (lim.hypothermia || 35) ? 'critical' : 'low',
                    title: (t <= (lim.hypothermia || 35) ? 'Hypothermia' : 'Cold') + ' (' + toF(t).toFixed(1) + ' °F)',
                    fix: 'Wear warm clothes (mend worn ones), get out of the rain, stay out of the cold at night.' + list(c.cold, ' Warm up with:', '') });
            } else if (t >= 38.5) {
                out.push({ key: 'hot', level: t >= (lim.hyperthermia || 39.5) ? 'critical' : 'low',
                    title: (t >= (lim.hyperthermia || 39.5) ? 'Overheating' : 'Hot') + ' (' + toF(t).toFixed(1) + ' °F)',
                    fix: 'Take off warm clothes, find shade, drink.' });
            }
        }
        if (typeof v.armor === 'number' && v.armor <= 25) {
            out.push({ key: 'armor', level: v.armor <= 0 ? 'critical' : 'low', title: v.armor <= 0 ? 'Armor plate broken' : 'Armor plate ' + r(v.armor) + '%',
                fix: 'Repair it with an armor repair kit (right-click the plate).' });
        }
        return out;
    }

    // Condition of an item with durability: { share 0-1, text, ruined } or null.
    // Items made before durability existed count as new.
    function condition(def, stack) {
        if (!def || !(def.durability > 0)) return null;
        const cur = stack && stack.metadata && typeof stack.metadata.durability === 'number' ? stack.metadata.durability : def.durability;
        const share = Math.max(0, Math.min(1, cur / def.durability));
        if (share <= 0) return { share: 0, text: 'Ruined', ruined: true };
        return { share: share, text: 'Condition ' + Math.round(share * 100) + '%', ruined: false };
    }

    function formatKg(v) { return (Math.round(v * 10) / 10).toFixed(1); }

    // Short label for a tile: whole label when it fits, else initials.
    function shortLabel(label, cellsWide) {
        if (label.length <= cellsWide * 7) return label;
        return label.split(/\s+/).map((w) => w[0]).join('').toUpperCase().slice(0, 4);
    }

    if (typeof module === 'object' && module.exports) {
        module.exports = { footprint: footprint, fits: fits, findSpot: findSpot, stackAt: stackAt, decideDrop: decideDrop, quickTarget: quickTarget,
            formatKg: formatKg, shortLabel: shortLabel, condition: condition, conditions: conditions, toF: toF, feels: feels };
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
        clothing: '#5a4d6e', armor: '#4a5866', container: '#4e5f45', weapon: '#5d5d5d', ammo: '#7d6b2e', misc: '#555048',
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
        const cond = condition(def, stack);
        const el = h('div', { class: 'wli-item' + (cond && cond.ruined ? ' is-ruined' : ''),
            title: def.label + (cond ? ' (' + cond.text + ')' : '') + (def.description ? ' – ' + def.description : '') });
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
        if (stack.name === st.defs.cashItem) {
            el.appendChild(h('span', { class: 'wli-item__count', text: '$' + stack.count.toLocaleString('en-US') }));
        } else if (stack.count > 1) {
            el.appendChild(h('span', { class: 'wli-item__count', text: 'x' + stack.count }));
        }
        if (cond) {
            const bar = h('span', { class: 'wli-item__dur' + (cond.share <= 0.25 ? ' is-low' : '') });
            bar.style.width = Math.round(cond.share * 100) + '%';
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

    // ---------------------------------------------------------------- health panel

    const SVGNS = 'http://www.w3.org/2000/svg';
    function svgEl(tag, attrs) {
        const e = document.createElementNS(SVGNS, tag);
        Object.keys(attrs).forEach((k) => e.setAttribute(k, attrs[k]));
        return e;
    }
    // A simple human outline (front), 60 x 120.
    const BODY = 'M30 4 a9 9 0 1 1 0 18 a9 9 0 1 1 0 -18 Z ' +
        'M19 25 H41 Q48 25 50 32 L56 60 Q57 64 53 65 Q50 65 49 61 L44 40 V64 L46 112 Q46 117 41 117 Q37 117 36 112 L31 72 H29 L24 112 ' +
        'Q23 117 19 117 Q14 117 14 112 L16 64 V40 L11 61 Q10 65 7 65 Q3 64 4 60 L10 32 Q12 25 19 25 Z';

    function healthColor(p) {
        if (p <= 25) return '#e0533f';
        if (p <= 60) return '#d6b23c';
        return '#7fc75a';
    }

    function bodyFigure(v) {
        const svg = svgEl('svg', { viewBox: '0 0 60 120', class: 'wli-body' });
        const hp = typeof v.health === 'number' ? v.health : 100;
        svg.appendChild(svgEl('path', { d: BODY, fill: healthColor(hp), 'fill-opacity': String(0.25 + 0.55 * hp / 100), stroke: '#cfe8c0', 'stroke-width': '1.2' }));
        if (v.infection > 0) {
            svg.appendChild(svgEl('path', { d: BODY, fill: '#6fbf3a', 'fill-opacity': String(Math.min(0.7, v.infection / 100)), class: 'wli-body__infect' }));
        }
        const t = v.temperature;
        if (typeof t === 'number' && (t <= 35.5 || t >= 38.5)) {
            svg.appendChild(svgEl('path', { d: BODY, fill: 'none', stroke: t <= 35.5 ? '#6db7ff' : '#ff9a3c', 'stroke-width': '2.4', 'stroke-opacity': '0.9' }));
        }
        if (typeof v.armor === 'number') {
            svg.appendChild(svgEl('rect', { x: '19', y: '29', width: '22', height: '24', rx: '3', fill: v.armor > 0 ? '#8a9aa8' : '#5a5a5a',
                'fill-opacity': v.armor > 0 ? '0.75' : '0.45', stroke: '#1d242b', 'stroke-width': '1' }));
        }
        for (let i = 0; i < Math.min(3, v.bleeding || 0); i++) {
            svg.appendChild(svgEl('path', { d: 'M' + (24 + i * 6) + ' 44 q-2.5 4 0 6 q2.5 -2 0 -6 Z', fill: '#d1202a', class: 'wli-body__drop' }));
        }
        return svg;
    }

    function bar(label, value, text) {
        const fill = h('div', { class: 'wli-vbar__fill' });
        fill.style.width = Math.max(0, Math.min(100, value)) + '%';
        fill.style.background = healthColor(value);
        return h('div', { class: 'wli-vbar' }, h('span', { class: 'wli-vbar__label', text: label }),
            h('div', { class: 'wli-vbar__track' }, fill), h('span', { class: 'wli-vbar__val', text: text }));
    }

    function renderVitals() {
        if (!st || !st.vitalsEl) return;
        const v = st.vitals;
        st.vitalsEl.innerHTML = '';
        if (!v) { st.vitalsEl.hidden = true; return; }
        st.vitalsEl.hidden = false;
        const r = (x) => Math.round(Number(x) || 0);
        const bars = h('div', { class: 'wli-vbars' },
            bar('Health', r(v.health), r(v.health) + '%'),
            bar('Food', r(v.hunger), r(v.hunger) + '%'),
            bar('Water', r(v.thirst), r(v.thirst) + '%'),
            typeof v.armor === 'number' ? bar('Armor', r(v.armor), r(v.armor) + '%') : null,
            h('div', { class: 'wli-vtemp is-' + String(feels(v.temperature, v.limits) || '').toLowerCase(),
                text: 'Body temperature ' + (typeof v.temperature === 'number' ? toF(v.temperature).toFixed(1) + ' °F · ' + feels(v.temperature, v.limits) : '?') }));
        const list = h('div', { class: 'wli-conds' });
        const conds = conditions(v);
        if (!conds.length) list.appendChild(h('div', { class: 'wli-cond is-ok' }, h('b', { text: 'You are in good shape.' })));
        conds.forEach((c) => list.appendChild(h('div', { class: 'wli-cond is-' + c.level },
            h('b', { text: c.title }), h('div', { class: 'wli-cond__fix', text: c.fix }))));
        st.vitalsEl.appendChild(h('div', { class: 'wli-section__head' }, h('span', { class: 'wl-section-title', text: 'Health' })));
        st.vitalsEl.appendChild(h('div', { class: 'wli-vitals' }, bodyFigure(v), bars));
        st.vitalsEl.appendChild(list);
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
        // Health under what is being looted (that comes first).
        (st.snap.secondary || []).forEach((id) => { const inv = invById(id); if (inv) st.right.appendChild(gridPanel(inv)); });
        st.right.appendChild(st.vitalsEl);
        renderVitals();
        const ground = h('div', { class: 'wli-ground', text: 'Drop here to put items on the ground' });
        ground.dataset.ground = '1';
        st.right.appendChild(ground);
    }

    // ---------------------------------------------------------------- drag

    function startDrag(e, stack, fromId, el) {
        if (e.button !== 0) return;
        e.preventDefault();
        closeMenu();
        if (e.shiftKey) { quickMove(stack, fromId, true); return; }
        // Double-click (second press on the same item within 300 ms): quick move.
        const now = Date.now();
        if (st.lastPress && st.lastPress.uid === stack.uid && now - st.lastPress.t < 300) {
            st.lastPress = null;
            quickMove(stack, fromId, false);
            return;
        }
        st.lastPress = { uid: stack.uid, t: now };
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

    // Double-click / shift-click: move between your inventories and the
    // searched one. `explain`: say so when nothing is open.
    function quickMove(stack, fromId, explain) {
        if (fromId === st.snap.equip) return; // worn items: drag them off
        const r = quickTarget(stack, fromId, st.snap, st.defs.items);
        if (!r) { if (explain) setMessage('Nothing is open to move it to.', 'error'); return; }
        if (r.error) { setMessage(r.error, 'error'); return; }
        st.api.post(r.action, r.payload);
    }

    // ---------------------------------------------------------------- menu

    function openMenu(e, stack, fromId) {
        closeMenu();
        const def = st.defs.items[stack.name];
        const worn = fromId === st.snap.equip;
        const items = [];
        if (def.usable) items.push(['Use', () => st.api.post('use', { uid: stack.uid, from: fromId })]);
        // Damaged: offer every carried item that repairs this category.
        const cond = condition(def, stack);
        if (cond && cond.share < 1) {
            const seen = {};
            [st.snap.pockets, st.snap.backpack].forEach((id) => {
                const inv = id && invById(id);
                (inv ? inv.items : []).forEach((k) => {
                    const kd = st.defs.items[k.name];
                    if (kd && kd.usable && kd.repairs === def.category && !seen[k.name]) {
                        seen[k.name] = true;
                        items.push(['Repair with ' + kd.label, () => st.api.post('use', { uid: k.uid, from: inv.id, target: stack.uid })]);
                    }
                });
            });
        }
        if (def.equip && !worn) items.push(['Wear', () => st.api.post('equip', { uid: stack.uid, from: fromId, slot: def.equip })]);
        if (worn) items.push(['Take off', () => st.api.post('unequip', { slot: stack.slot, to: st.snap.pockets })]);
        if (!worn && stack.count > 1) items.push(['Split…', () => openSplit(e, stack, fromId)]);
        for (let i = 1; i <= 5; i++) {
            if (!worn) items.push(['Hotbar ' + i, () => st.api.post('setHotbar', { index: i, uid: stack.uid })]);
        }
        items.push(['Drop', () => st.api.post('drop', { uid: stack.uid, from: fromId, count: stack.count })]);
        const menu = h('div', { class: 'wli-menu' },
            h('div', { class: 'wli-menu__title', text: def.label + (stack.count > 1 ? ' x' + stack.count : '') + (cond ? ' · ' + cond.text : '') }));
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
            st = { api: api, defs: data.defs, snap: data.snapshot, drag: null, menu: null, preview: null, vitals: data.vitals || null };
            st.vitalsEl = h('div', { class: 'wli-section wli-health' });
            st.left = h('div', { class: 'wli-col' });
            st.middle = h('div', { class: 'wli-col wli-col--main' });
            st.right = h('div', { class: 'wli-col' });
            st.message = h('div', { class: 'wl-message' });
            st.root = h('div', { class: 'wli-root' },
                h('div', { class: 'wl-backdrop' }),
                h('div', { class: 'wli-layout' },
                    h('div', { class: 'wli-header' },
                        h('h1', { class: 'wl-title', text: 'Inventory' }),
                        h('span', { class: 'wl-hint wli-header__hint', text: 'Drag to move · Double-click to take / put back · R rotates while dragging · Right-click for actions · TAB or Esc closes' }),
                        UI.button('Crafting (K)', () => st.api.post('crafting', {}))),
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
            if (data.vitals !== undefined) { st.vitals = data.vitals; renderVitals(); }
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
        '.wli-header__hint { flex: 1; }',
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
        '.wli-item__dur.is-low { background: #e0533f; }',
        '.wli-item.is-ruined { filter: grayscale(0.85) brightness(0.75); }',
        '.wli-item.is-ruined::after { content: "RUINED"; position: absolute; right: 3px; bottom: 5px; font-size: 9px; font-weight: 700; color: #ff9c90; letter-spacing: 0.05em; }',
        '.wli-ghost { position: fixed; pointer-events: none; z-index: 50; opacity: 0.9; }',
        '.wli-preview { position: absolute; pointer-events: none; background: rgba(127,174,90,0.25); border: 1px solid var(--wl-ok); }',
        '.wli-preview.is-bad { background: rgba(196,69,58,0.25); border-color: var(--wl-danger); }',
        '.wli-health { margin-bottom: 4px; min-width: 300px; max-width: 440px; }',
        '.wli-vitals { display: grid; grid-template-columns: 80px 1fr; gap: 12px; align-items: center; }',
        '.wli-body { width: 80px; height: 160px; }',
        '.wli-body__drop { animation: wli-drip 1.4s ease-in infinite; }',
        '@keyframes wli-drip { 0% { transform: translateY(0); opacity: 1; } 100% { transform: translateY(10px); opacity: 0; } }',
        '.wli-vbars { display: flex; flex-direction: column; gap: 5px; }',
        '.wli-vbar { display: grid; grid-template-columns: 48px 1fr 38px; gap: 6px; align-items: center; font-size: 11px; }',
        '.wli-vbar__label { color: var(--wl-text-dim); }',
        '.wli-vbar__track { height: 6px; background: var(--wl-bg-sunken); border-radius: 3px; overflow: hidden; }',
        '.wli-vbar__fill { height: 100%; }',
        '.wli-vbar__val { text-align: right; font-variant-numeric: tabular-nums; }',
        '.wli-vtemp { font-size: 12px; color: var(--wl-text-dim); margin-top: 2px; }',
        '.wli-vtemp.is-comfortable { color: #7fc75a; } .wli-vtemp.is-cold { color: #6db7ff; } .wli-vtemp.is-freezing { color: #4d8dff; font-weight: 700; }',
        '.wli-vtemp.is-hot { color: #ff9a3c; } .wli-vtemp.is-overheating { color: #ff5a3c; font-weight: 700; }',
        '.wli-conds { display: flex; flex-direction: column; gap: 5px; margin-top: 8px; max-width: 420px; }',
        '.wli-cond { font-size: 12px; padding: 5px 8px; border-radius: 4px; background: var(--wl-bg-sunken); border-left: 3px solid #d6b23c; }',
        '.wli-cond.is-critical { border-left-color: #e0533f; } .wli-cond.is-critical b { color: #ff9c90; }',
        '.wli-cond.is-ok { border-left-color: #7fc75a; }',
        '.wli-cond__fix { color: var(--wl-text-dim); margin-top: 2px; line-height: 1.3; }',
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
