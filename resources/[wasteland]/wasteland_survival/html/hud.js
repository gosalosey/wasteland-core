// wasteland_survival :: html/hud.js
// Survival HUD (runs inside wasteland_ui, no input focus). Two styles:
//   body     - (default) a body silhouette (red while bleeding, green tint
//              while infected, red flush at low health) with rings in an arc: health (red), stamina (dark
//              blue), food (brown), drink (deep blue); small rings top left
//              for armour (outer ring the vest, inner ring the plates) and
//              noise (how far zombies hear you, lit green while talking); small
//              rings for temperature, pee and poop; bleeding / infection tags
//   classic  - health (and armour) as bars on a riveted plate, food, drink,
//              temperature, pee and poop as round iron dials
// Modes:
//   compact    - every icon, always
//   immersive  - an icon only while it matters (low, cold, hot)
//   off        - nothing
// /hud opens edit mode: drag the HUD anywhere, pick mode, row/column and
// size, then Save (client/main.lua stores it on the player's PC).
// Also: a line with the player's server id, character name and cash (moves
// with the HUD), and a stamina bar at the bottom middle of the screen that
// only shows while stamina is being used.
// Data: { mode, health, armor (vest %, only while one is worn), plates (%), stamina, voice = { talking, level, levels, on },
//         noise = { radius (m), source, count, safe } (wasteland_zombies; nil = unknown),
//         editing, layout = { x, y, vertical, size, style },
//         info = { id, name, cash },
//         stats = { hunger, thirst, infection, bleeding, temperature, treatment, dead } }

(function () {
    'use strict';

    // ------------------------------------------------------------------
    // Pure helpers (unit-tested with Node)
    // ------------------------------------------------------------------

    const LOW = 35;       // amber at or below; immersive shows the icon
    const CRITICAL = 15;  // red and pulsing at or below
    const TEMP_MIN = 33;  // thermometer empty
    const TEMP_MAX = 39;  // thermometer full

    const clamp = (v) => Math.max(0, Math.min(100, Math.round(v)));

    function levelOf(value) {
        if (value <= CRITICAL) return 'critical';
        if (value <= LOW) return 'low';
        return 'ok';
    }

    function tempLevel(t) {
        if (t <= 34.5 || t >= 39.5) return 'critical';
        if (t <= 35.5 || t >= 38.5) return 'low';
        return 'ok';
    }

    // Icons to show: [{ key, label, fill 0..100, level ok|low|critical }]
    function icons(data) {
        const s = data.stats || {};
        if (data.mode === 'off' || s.dead) return [];
        const all = [];
        if (typeof data.health === 'number') all.push({ key: 'health', label: 'Health', fill: clamp(data.health) });
        // plates (in the vest) above the vest's own bar
        if (typeof data.plates === 'number') all.push({ key: 'plates', label: 'Plates', fill: clamp(data.plates) });
        if (typeof data.armor === 'number') all.push({ key: 'armor', label: 'Armor', fill: clamp(data.armor) });
        if (typeof s.hunger === 'number') all.push({ key: 'food', label: 'Food', fill: clamp(s.hunger) });
        if (typeof s.thirst === 'number') all.push({ key: 'drink', label: 'Drink', fill: clamp(s.thirst) });
        all.forEach((i) => { i.level = levelOf(i.fill); });
        if (typeof s.temperature === 'number') {
            const t = s.temperature;
            all.push({ key: 'temp', label: 'Temp.', fill: clamp((t - TEMP_MIN) / (TEMP_MAX - TEMP_MIN) * 100), level: tempLevel(t),
                hot: t >= 38.5 });
        }
        // toilet: these fill up (full = you have to go)
        const need = (v) => (v >= 85 ? 'critical' : v >= 65 ? 'low' : 'ok');
        if (typeof s.bladder === 'number') all.push({ key: 'pee', label: 'Pee', fill: clamp(s.bladder), level: need(s.bladder) });
        if (typeof s.bowel === 'number') all.push({ key: 'poop', label: 'Poop', fill: clamp(s.bowel), level: need(s.bowel) });
        if (data.mode === 'immersive') return all.filter((i) => i.level !== 'ok');
        return all;
    }

    // Badges: bleeding (1-3) and infection (percent, treated or not).
    function badges(data) {
        const s = data.stats || {};
        if (data.mode === 'off' || s.dead) return [];
        const out = [];
        if (s.bleeding > 0) {
            const lvl = Math.min(3, s.bleeding);
            out.push({ key: 'bleeding', level: lvl, text: ['', 'Bleeding', 'Bleeding heavily', 'Bleeding severely'][lvl] });
        }
        if (s.infection > 0) {
            out.push({ key: 'infection', text: (s.treatment ? 'Infection (treated) ' : 'Infection ') + clamp(s.infection) + '%' });
        }
        return out;
    }

    // Id, name and cash line (null when the HUD is off). Cash null = unknown
    // (inventory not running).
    function infoLine(data) {
        const s = data.stats || {};
        if (data.mode === 'off' || s.dead || !data.info) return null;
        const i = data.info;
        const cash = typeof i.cash === 'number' ? '$' + Math.max(0, Math.floor(i.cash)).toLocaleString('en-US') : null;
        return { id: typeof i.id === 'number' ? '#' + i.id : null, name: i.name ? String(i.name) : null, cash: cash };
    }

    // Stamina bar: shown only while stamina is not full (and the HUD is on).
    function staminaBar(data) {
        const s = data.stats || {};
        if (data.mode === 'off' || s.dead || typeof data.stamina !== 'number') return { visible: false, fill: 100 };
        const fill = clamp(data.stamina);
        return { visible: fill < 100, fill: fill, low: fill <= 20 };
    }

    // How loud (the zombies' hearing range, metres): the same bands as the noise panel.
    function noiseLevel(r) {
        if (r <= 6) return { key: 'quiet', word: 'QUIET' };
        if (r <= 12) return { key: 'low', word: 'LOW' };
        if (r <= 25) return { key: 'noticeable', word: 'NOTICEABLE' };
        if (r <= 50) return { key: 'loud', word: 'LOUD' };
        return { key: 'deafening', word: 'DEAFENING' };
    }

    // The body style: rings in the arc, the small rings, the armour and voice
    // rings, and how the body figure looks. Rings: [{ key, fill, level, text }].
    function bodyView(data) {
        const s = data.stats || {};
        if (data.mode === 'off' || s.dead) return null;
        const ring = (key, v) => ({ key: key, fill: clamp(v), level: levelOf(clamp(v)), text: clamp(v) + '%' });
        let big = [];
        if (typeof data.health === 'number') big.push(ring('health', data.health));
        if (typeof data.stamina === 'number') big.push(ring('stamina', data.stamina));
        if (typeof s.hunger === 'number') big.push(ring('food', s.hunger));
        if (typeof s.thirst === 'number') big.push(ring('drink', s.thirst));
        const small = icons(Object.assign({}, data, { mode: 'compact', health: null, armor: null, plates: null, stats: Object.assign({}, s, { hunger: null, thirst: null }) }))
            .filter((i) => i.key === 'temp' || i.key === 'pee' || i.key === 'poop');
        const armor = typeof data.armor === 'number'
            ? { worn: true, fill: clamp(data.armor), plates: typeof data.plates === 'number' ? clamp(data.plates) : 0, level: levelOf(clamp(data.armor)) }
            : { worn: false, fill: 0, plates: 0, level: 'ok' };
        const v = data.voice || {};
        const levels = v.levels || 3;
        const voice = { on: v.on !== false, talking: v.talking === true,
            fill: typeof v.level === 'number' ? clamp(v.level / levels * 100) : (v.on === false ? 0 : 66) };
        const n = data.noise;
        const noise = n && typeof n.radius === 'number'
            ? Object.assign(noiseLevel(n.radius), { known: true, talking: false,
                fill: Math.max(4, Math.round(Math.min(1, Math.sqrt(Math.max(0, n.radius) / 120)) * 100)),
                feet: Math.round(n.radius * 3.28084 / 5) * 5, count: n.count || 0 })
            : { known: false, key: 'quiet', word: '', talking: false, fill: 0, feet: 0, count: 0 };
        const immersive = data.mode === 'immersive';
        if (immersive) {
            big = big.filter((i) => i.level !== 'ok');
        }
        // the speaker in the small row: voice range, lit while talking ("when it matters": only while talking)
        if (voice.on && (!immersive || voice.talking)) {
            small.push({ key: 'voice', label: 'Voice', fill: voice.fill, level: 'ok', talking: voice.talking });
        }
        return {
            big: big,
            small: immersive ? small.filter((i) => i.level !== 'ok' || i.key === 'voice') : small,
            armor: armor, voice: voice, noise: noise,
            body: { bleeding: Math.min(3, s.bleeding || 0), infected: (s.infection || 0) > 0,
                hurt: typeof data.health === 'number' && data.health <= LOW },
        };
    }

    // Layout: x/y are the share of the free space left of / above the HUD
    // (0 = left/top edge, 1 = right/bottom edge), so the HUD stays on screen
    // at any resolution or size. x/y null = default corner (bottom right).
    const SIZES = { s: 0.8, m: 1, l: 1.3 };
    const unit = (v) => (typeof v === 'number' && isFinite(v) ? Math.max(0, Math.min(1, v)) : null);

    function normalizeLayout(l) {
        l = l || {};
        let x = unit(l.x);
        let y = unit(l.y);
        if (x === null || y === null) { x = null; y = null; }
        return { x: x, y: y, vertical: l.vertical === true, size: SIZES[l.size] ? l.size : 'm', style: l.style === 'classic' ? 'classic' : 'body' };
    }

    // Pixel position of the HUD's top-left corner (null = default corner).
    function toPixels(layout, box, view) {
        const l = normalizeLayout(layout);
        if (l.x === null) return null;
        return {
            left: Math.round(l.x * Math.max(0, view.w - box.w)),
            top: Math.round(l.y * Math.max(0, view.h - box.h)),
        };
    }

    // Layout x/y for a HUD dragged to left/top (clamped to the screen).
    function toFractions(left, top, box, view) {
        const fw = view.w - box.w;
        const fh = view.h - box.h;
        const r = (v) => Math.round(Math.max(0, Math.min(1, v)) * 10000) / 10000;
        return { x: fw > 0 ? r(left / fw) : 0, y: fh > 0 ? r(top / fh) : 0 };
    }

    if (typeof module === 'object' && module.exports) {
        module.exports = { noiseLevel: noiseLevel, bodyView: bodyView, icons: icons, badges: badges, infoLine: infoLine, staminaBar: staminaBar, normalizeLayout: normalizeLayout, toPixels: toPixels, toFractions: toFractions };
        return;
    }

    // ------------------------------------------------------------------
    // Screen
    // ------------------------------------------------------------------

    const UI = window.WastelandUI;
    const h = UI.h;
    const NS = 'http://www.w3.org/2000/svg';
    let root;
    let uid = 0;

    function svg(tag, attrs, children) {
        const el = document.createElementNS(NS, tag);
        Object.keys(attrs || {}).forEach((k) => el.setAttribute(k, attrs[k]));
        (children || []).forEach((c) => el.appendChild(c));
        return el;
    }

    // Glyphs in a 24 x 24 box (filled shapes and strokes).
    const GLYPHS = {
        health: { fill: 'M12 20.5s-7.2-4.4-9.4-8.8A5.1 5.1 0 0 1 12 6.4a5.1 5.1 0 0 1 9.4 5.3c-2.2 4.4-9.4 8.8-9.4 8.8z' },
        armor: { fill: 'M12 2.8l7.6 2.9v5.9c0 5-3.3 8.3-7.6 9.6-4.3-1.3-7.6-4.6-7.6-9.6V5.7z' },
        plates: { fill: 'M7 3h10l2 3v13l-2 2H7l-2-2V6zM8.5 11h7v2h-7z' },
        food: { stroke: 'M7 3v7.5a2 2 0 0 0 4 0V3M9 12.5V21M16.5 21V3c-2.2 1-3.5 4-3.5 7.5 0 1.6.9 2.5 2.2 2.5h1.3' },
        drink: { fill: 'M12 2.8s-6.2 7.3-6.2 11.5a6.2 6.2 0 0 0 12.4 0C18.2 10.1 12 2.8 12 2.8z' },
        temp: { stroke: 'M10 13.6V5a2 2 0 0 1 4 0v8.6a4.2 4.2 0 1 1-4 0zM12 9v7.5', dot: true },
        pee: { fill: 'M12 2.8s-6 7-6 11.2a6 6 0 0 0 12 0C18 9.8 12 2.8 12 2.8z', text: 'P' },
        stamina: { stroke: 'M13 8l-3 4.5 3 3-1.5 6M10 12.5l-4.5 1M13.2 9.5l4 2 2.3-2.2M13 15.5l4.5 1 1 4.5', circle: [14.5, 4.6, 2.3] },
        bread: { fill: 'M3.5 11.2C3.5 7.2 7.4 5 12 5s8.5 2.2 8.5 6.2c0 1.3-.8 2.1-2 2.2V19H5.5v-5.6c-1.2-.1-2-.9-2-2.2z' },
        glass: { stroke: 'M7 3h10c0 5.2-2.2 8.2-5 8.2S7 8.2 7 3zM12 11.2V19M8 21h8' },
        voice: { fill: 'M3.5 9h4l5.2-4.2v14.4L7.5 15h-4z', stroke: 'M16 8.6a4.8 4.8 0 0 1 0 6.8M18.6 6a8.4 8.4 0 0 1 0 12' },
        speaker: { fill: 'M3.5 9h4l5.2-4.2v14.4L7.5 15h-4z', stroke: 'M16 8.6a4.8 4.8 0 0 1 0 6.8M18.6 6a8.4 8.4 0 0 1 0 12' },
        poop: { fill: 'M12 3.5c2 .8 2.2 2.8 1.2 3.8 2.8 0 3.8 1.8 3 3 2.8.2 3.8 2.8 2.8 4.5 2 .9 1.4 4.7-1 4.7H6c-2.4 0-3-3.8-1-4.7-1-1.7 0-4.3 2.8-4.5-.8-1.2.2-3 3-3-1-1-.6-3 1.2-3.8z' },
    };

    function glyph(key) {
        const g = GLYPHS[key] || GLYPHS.health;
        const kids = [];
        if (g.fill) kids.push(svg('path', { d: g.fill, class: 'wlh-g-fill' }));
        if (g.stroke) kids.push(svg('path', { d: g.stroke, class: 'wlh-g-stroke' }));
        if (g.dot) kids.push(svg('circle', { cx: '12', cy: '17.2', r: '2.2', class: 'wlh-g-fill' }));
        if (g.circle) kids.push(svg('circle', { cx: String(g.circle[0]), cy: String(g.circle[1]), r: String(g.circle[2]), class: 'wlh-g-fill' }));
        if (g.text) {
            const t = svg('text', { x: '12', y: '17.6', 'text-anchor': 'middle', class: 'wlh-g-text' });
            t.textContent = g.text;
            kids.push(t);
        }
        return svg('svg', { viewBox: '0 0 24 24', class: 'wlh-glyph' }, kids);
    }

    // A round iron badge: a ring that drains around the glyph.
    const RING = 2 * Math.PI * 19;
    function badgeEl(icon) {
        const ring = svg('svg', { viewBox: '0 0 48 48', class: 'wlh-ring' }, [
            svg('circle', { cx: '24', cy: '24', r: '19', class: 'wlh-ring__track' }),
            svg('circle', { cx: '24', cy: '24', r: '19', class: 'wlh-ring__fill',
                'stroke-dasharray': RING.toFixed(2), 'stroke-dashoffset': (RING * (1 - icon.fill / 100)).toFixed(2) }),
        ]);
        const el = h('div', { class: 'wlh-dial wlh-dial--' + icon.key + (icon.hot ? ' is-hot' : '') + (icon.talking ? ' is-talking' : '') + ' is-' + icon.level,
            attrs: { title: icon.label + ' ' + icon.fill + '%' } },
            ring, h('div', { class: 'wlh-dial__face' }, glyph(icon.key)));
        return el;
    }

    // The long bar on a riveted plate (health, armour under it).
    function barEl(icon, thin) {
        const fill = h('div', { class: 'wlh-bar__fill' });
        fill.style.width = icon.fill + '%';
        return h('div', { class: 'wlh-plate wlh-plate--' + icon.key + ' is-' + icon.level + (thin ? ' is-thin' : '') },
            h('div', { class: 'wlh-plate__icon' }, glyph(icon.key)),
            h('div', { class: 'wlh-bar' }, fill, h('div', { class: 'wlh-bar__grime' })),
            h('span', { class: 'wlh-plate__value', text: String(icon.fill) }));
    }

    // ------------------------------------------------------------------
    // Body style
    // ------------------------------------------------------------------

    // The body: a grey silhouette (PNG, kept inside this file so the red and
    // green tints can use it as their mask).
    const SILHOUETTE = 'data:image/png;base64,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';

    function bodySilhouette(b) {
        const img = h('img', { class: 'wlh-portrait__img', draggable: false });
        img.src = SILHOUETTE;
        const tint = (cls) => { const d = h('div', { class: 'wlh-portrait__tint ' + cls }); d.style.webkitMaskImage = d.style.maskImage = 'url(' + SILHOUETTE + ')'; return d; };
        return h('div', { class: 'wlh-portrait' + (b.bleeding ? ' is-bleeding is-bleeding-' + b.bleeding : '') + (b.infected ? ' is-infected' : '')
            + (b.hurt ? ' is-hurt' : '') }, img, tint('wlh-portrait__infection'), tint('wlh-portrait__blood'));
    }

    // An arc ring (open on the left, like a gauge) with a glyph and a value.
    const ARC = 0.8;   // share of the circle the gauge covers
    function arcRing(r, sw, fill, cls) {
        const c = 2 * Math.PI * r;
        const track = svg('circle', { cx: '30', cy: '30', r: String(r), class: 'wlh-arc__track ' + (cls || ''),
            'stroke-width': String(sw), 'stroke-dasharray': (c * ARC).toFixed(2) + ' ' + c.toFixed(2), transform: 'rotate(216 30 30)' });
        const bar = svg('circle', { cx: '30', cy: '30', r: String(r), class: 'wlh-arc__fill ' + (cls || ''),
            'stroke-width': String(sw), 'stroke-dasharray': (c * ARC * fill / 100).toFixed(2) + ' ' + c.toFixed(2), transform: 'rotate(216 30 30)' });
        return [track, bar];
    }

    function bigRing(r) {
        const glyphKey = { health: 'health', stamina: 'stamina', food: 'bread', drink: 'glass' }[r.key];
        return h('div', { class: 'wlh-gauge wlh-gauge--' + r.key + ' is-' + r.level, attrs: { title: r.key + ' ' + r.text } },
            svg('svg', { viewBox: '0 0 60 60', class: 'wlh-gauge__ring' }, arcRing(26, 4.2, r.fill)),
            h('div', { class: 'wlh-gauge__face' }, glyph(glyphKey), h('span', { class: 'wlh-gauge__val', text: r.text })));
    }

    function armorRing(a) {
        return h('div', { class: 'wlh-mini wlh-mini--armor' + (a.worn ? '' : ' is-none') + ' is-' + a.level,
            attrs: { title: a.worn ? 'Armour ' + a.fill + '%, plates ' + a.plates + '%' : 'No armour' } },
            svg('svg', { viewBox: '0 0 60 60', class: 'wlh-gauge__ring' }, arcRing(26, 4.5, a.fill).concat(arcRing(19.5, 3.2, a.plates, 'is-plates'))),
            h('div', { class: 'wlh-mini__face' }, glyph('armor')));
    }

    function noiseRing(n) {
        const title = n.known ? 'Noise: ' + n.word.toLowerCase() + ', heard within ~' + n.feet + ' ft'
            + (n.count ? ' (' + n.count + ' in earshot)' : '') : 'Noise';
        return h('div', { class: 'wlh-noise' },
            h('div', { class: 'wlh-mini wlh-mini--noise is-' + n.key + (n.talking ? ' is-talking' : '') + (n.known ? '' : ' is-none'),
                attrs: { title: title } },
                svg('svg', { viewBox: '0 0 60 60', class: 'wlh-gauge__ring' }, arcRing(26, 4.5, n.fill)),
                h('div', { class: 'wlh-mini__face' }, glyph('speaker'))),
            n.known ? h('div', { class: 'wlh-noise__word is-' + n.key, text: n.word }) : null);
    }

    function renderBody(shown) {
        const v = bodyView(shown);
        if (!v) return;
        const wrap = h('div', { class: 'wlh-bodyhud' });
        const left = h('div', { class: 'wlh-bodyhud__left' },
            h('div', { class: 'wlh-bodyhud__minis' }, armorRing(v.armor), noiseRing(v.noise)),
            bodySilhouette(v.body));
        const right = h('div', { class: 'wlh-bodyhud__arc' });
        v.big.forEach((r, i) => {
            const g = bigRing(r);
            g.style.marginLeft = 'calc(' + [0, 16, 16, 0][i % 4] + 'px * var(--wlh-scale))';
            right.appendChild(g);
        });
        wrap.appendChild(left);
        wrap.appendChild(right);
        root.appendChild(wrap);
        if (v.small.length) {
            const row = h('div', { class: 'wlh-row wlh-bodyhud__small' });
            v.small.forEach((i) => row.appendChild(badgeEl(i)));
            root.appendChild(row);
        }
    }

    // ------------------------------------------------------------------
    // Edit mode (/hud)
    // ------------------------------------------------------------------

    let host;           // the screen element
    let stamina = null; // bottom-middle stamina bar (kept, so it can fade)
    let post;           // api.post(action, payload)
    let toolbar = null;
    let draft = null;   // while editing: { mode, x, y, vertical, size }
    let drag = null;    // { dx, dy } while the mouse holds the HUD
    let last = null;    // last data from the game

    const MODES = [['compact', 'Always'], ['immersive', 'When it matters'], ['off', 'Off']];
    const DEMO = { hunger: 80, thirst: 60, temperature: 37, infection: 0, bleeding: 0, bladder: 40, bowel: 20 };

    function view() { return { w: window.innerWidth, h: window.innerHeight }; }
    function box() { const r = root.getBoundingClientRect(); return { w: r.width, h: r.height }; }

    function place(layout) {
        root.style.setProperty('--wlh-scale', String(SIZES[layout.size] || 1));
        root.classList.toggle('is-vertical', layout.vertical === true);
        const px = toPixels(layout, box(), view());
        if (px) {
            root.style.left = px.left + 'px';
            root.style.top = px.top + 'px';
            root.style.right = 'auto';
            root.style.bottom = 'auto';
        } else {
            root.style.left = '';
            root.style.top = '';
            root.style.right = '';
            root.style.bottom = '';
        }
    }

    function finish(save) {
        if (save && draft) {
            post('saveLayout', { mode: draft.mode, x: draft.x, y: draft.y, vertical: draft.vertical, size: draft.size, style: draft.style });
        } else {
            post('cancelLayout', {});
        }
    }

    function buildToolbar() {
        const group = (label, options, current, pick) => {
            const g = h('div', { class: 'wlh-tb__group' }, h('span', { class: 'wlh-tb__label', text: label }));
            options.forEach((o) => {
                g.appendChild(UI.button(o[1], () => { pick(o[0]); render(last); }, o[0] === current ? 'primary' : undefined));
            });
            return g;
        };
        return h('div', { class: 'wlh-tb' },
            h('div', { class: 'wlh-tb__title', text: 'Drag the HUD anywhere on the screen, then Save' }),
            group('Show', MODES, draft.mode, (v) => { draft.mode = v; }),
            group('Style', [['body', 'Body'], ['classic', 'Classic']], draft.style, (v) => { draft.style = v; }),
            draft.style === 'classic' ? group('Layout', [[false, 'Row'], [true, 'Column']], draft.vertical, (v) => { draft.vertical = v; }) : null,
            group('Size', [['s', 'S'], ['m', 'M'], ['l', 'L']], draft.size, (v) => { draft.size = v; }),
            h('div', { class: 'wlh-tb__group' },
                UI.button('Reset', () => { draft.x = null; draft.y = null; draft.vertical = false; draft.size = 'm'; draft.style = 'body'; render(last); }),
                UI.button('Cancel', () => finish(false)),
                UI.button('Save', () => finish(true), 'primary')));
    }

    function render(data) {
        last = data;
        const editing = data.editing === true;
        if (editing && !draft) draft = Object.assign({ mode: data.mode || 'compact' }, normalizeLayout(data.layout));
        if (!editing) { draft = null; drag = null; }

        root.innerHTML = '';
        root.classList.toggle('is-editing', editing);
        const line = infoLine(editing ? Object.assign({}, data, { mode: 'compact', stats: {} }) : data);
        if (line) {
            const info = h('div', { class: 'wlh-info' });
            if (line.id) info.appendChild(h('span', { class: 'wlh-info__id', text: line.id }));
            if (line.name) info.appendChild(h('span', { class: 'wlh-info__name', text: line.name }));
            if (line.cash) info.appendChild(h('span', { class: 'wlh-info__cash', text: line.cash }));
            root.appendChild(info);
        }
        // While editing every icon shows, so there is always something to move.
        const shown = editing
            ? Object.assign({}, data, {
                mode: 'compact',
                health: typeof data.health === 'number' ? data.health : 100,
                stats: Object.assign({}, DEMO, data.stats || {}, { dead: false }),
            })
            : data;
        const style = (editing ? draft : normalizeLayout(data.layout)).style;
        root.classList.toggle('is-body', style === 'body');
        if (style === 'body') renderBody(editing ? Object.assign({}, shown, { stamina: typeof data.stamina === 'number' ? data.stamina : 100 }) : shown);
        const list = style === 'body' ? [] : icons(shown);
        const BAR = { health: true, armor: true, plates: true };
        const bars = list.filter((i) => BAR[i.key]);
        const dials = list.filter((i) => !BAR[i.key]);
        const panel = h('div', { class: 'wlh-panel' });
        bars.forEach((i) => panel.appendChild(barEl(i, i.key !== 'health')));
        if (dials.length) {
            const row = h('div', { class: 'wlh-row' });
            dials.forEach((i) => row.appendChild(badgeEl(i)));
            panel.appendChild(row);
        }
        if (bars.length || dials.length) root.appendChild(panel);
        const b = badges(shown);
        if (b.length) {
            const tags = h('div', { class: 'wlh-badges' });
            b.forEach((x) => tags.appendChild(h('span', { class: 'wlh-badge wlh-badge--' + x.key, text: x.text })));
            root.appendChild(tags);
        }
        place(editing ? draft : normalizeLayout(data.layout));

        if (toolbar) { toolbar.remove(); toolbar = null; }
        if (editing) { toolbar = buildToolbar(); host.appendChild(toolbar); }

        const bar = style === 'body' ? { visible: false, fill: 100 } : staminaBar(data);
        stamina.classList.toggle('is-visible', bar.visible);
        stamina.classList.toggle('is-low', bar.low === true);
        stamina.firstChild.style.width = bar.fill + '%';
    }

    function onDown(e) {
        if (!draft || e.button !== 0) return;
        const r = root.getBoundingClientRect();
        drag = { dx: e.clientX - r.left, dy: e.clientY - r.top };
        e.preventDefault();
    }
    function onMove(e) {
        if (!drag || !draft) return;
        const f = toFractions(e.clientX - drag.dx, e.clientY - drag.dy, box(), view());
        draft.x = f.x;
        draft.y = f.y;
        place(draft);
    }
    function onUp() { drag = null; }
    function onKey(e) { if (draft && e.key === 'Escape') finish(false); }

    UI.registerScreen('hud', {
        mount: function (el, data, api) {
            host = el;
            post = api.post;
            root = h('div', { class: 'wlh-root' });
            el.appendChild(root);
            stamina = h('div', { class: 'wlh-stamina' }, h('div', { class: 'wlh-stamina__fill' }));
            el.appendChild(stamina);
            el.appendChild(h('style', { text: CSS }));
            root.addEventListener('mousedown', onDown);
            document.addEventListener('mousemove', onMove);
            document.addEventListener('mouseup', onUp);
            document.addEventListener('keydown', onKey);
            render(data);
        },
        update: render,
        unmount: function () {
            document.removeEventListener('mousemove', onMove);
            document.removeEventListener('mouseup', onUp);
            document.removeEventListener('keydown', onKey);
            root = null; host = null; toolbar = null; draft = null; drag = null; stamina = null;
        },
    });

    const CSS = [
        '.wlh-root { position: absolute; right: 1.6vw; bottom: 3vh; display: flex; flex-direction: column; align-items: flex-end; gap: 6px; pointer-events: none;',
        '  --wlh-ok: #8fbf5f; --wlh-low: #d99a2b; --wlh-critical: #d2261c; --wlh-scale: 1; font-family: var(--wl-font-display); }',
        '.wlh-root.is-editing { pointer-events: auto; cursor: move; outline: 2px dashed rgba(127,199,90,0.85); outline-offset: 8px;',
        '  border-radius: 8px; background: rgba(10,14,9,0.35); }',
        // the panel: everything sized from --wlh-scale
        '.wlh-panel { display: flex; flex-direction: column; align-items: stretch; gap: calc(5px * var(--wlh-scale)); }',
        // plate with a bar (health / armour)
        '.wlh-plate { position: relative; display: flex; align-items: center; gap: calc(7px * var(--wlh-scale));',
        '  width: calc(282px * var(--wlh-scale)); height: calc(30px * var(--wlh-scale)); padding: 0 calc(10px * var(--wlh-scale)) 0 calc(4px * var(--wlh-scale));',
        '  border-radius: calc(6px * var(--wlh-scale)); border: 1px solid #4a3d2e;',
        '  background: radial-gradient(3px 3px at 6px 50%, #8a7a62 40%, transparent 60%), radial-gradient(3px 3px at calc(100% - 6px) 50%, #8a7a62 40%, transparent 60%),',
        '    linear-gradient(180deg, #2c2620, #15120f 70%, #1d1914);',
        '  box-shadow: 0 4px 12px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,230,190,0.08), inset 0 -2px 4px rgba(0,0,0,0.5); }',
        '.wlh-plate.is-thin { height: calc(26px * var(--wlh-scale)); width: calc(282px * var(--wlh-scale)); }',
        '.wlh-plate__icon { flex: none; display: grid; place-items: center; width: calc(24px * var(--wlh-scale)); height: calc(24px * var(--wlh-scale));',
        '  border-radius: calc(5px * var(--wlh-scale)); background: linear-gradient(180deg, #3a3129, #1a1612); border: 1px solid #55463a;',
        '  box-shadow: inset 0 1px 0 rgba(255,230,190,0.1); color: #d2261c; }',
        '.is-thin .wlh-plate__icon { width: calc(21px * var(--wlh-scale)); height: calc(21px * var(--wlh-scale)); }',
        '.wlh-plate--armor .wlh-plate__icon { color: #8fa8b8; }',
        '.wlh-plate--plates .wlh-plate__icon { color: #c9a24a; }',
        '.wlh-plate--plates .wlh-bar__fill { background: linear-gradient(180deg, #ecd28c, #b88a2c 55%, #6b4f16); box-shadow: 0 0 8px rgba(201,162,74,0.45); }',
        '.wlh-plate__icon .wlh-glyph { width: 72%; height: 72%; filter: drop-shadow(0 0 3px currentColor); }',
        '.wlh-bar { position: relative; flex: 1; height: 58%; border-radius: 3px; overflow: hidden; background: #0a0807;',
        '  box-shadow: inset 0 2px 4px rgba(0,0,0,0.9), 0 1px 0 rgba(255,230,190,0.06); }',
        '.wlh-bar__fill { position: absolute; left: 0; top: 0; bottom: 0; transition: width 0.4s ease;',
        '  background: linear-gradient(180deg, #e2453a 0%, #a3160f 55%, #5e0805 100%); box-shadow: 0 0 10px rgba(210,38,28,0.55); }',
        '.wlh-plate--armor .wlh-bar__fill { background: linear-gradient(180deg, #b9cfdc, #6c8797 55%, #3b4e5a); box-shadow: 0 0 8px rgba(143,168,184,0.45); }',
        // scratches and dirt over the bar
        '.wlh-bar__grime { position: absolute; inset: 0; pointer-events: none;',
        '  background: repeating-linear-gradient(115deg, rgba(0,0,0,0.22) 0 2px, transparent 2px 9px),',
        '    linear-gradient(180deg, rgba(255,255,255,0.18), rgba(255,255,255,0) 45%); }',
        '.wlh-plate__value { flex: none; min-width: calc(24px * var(--wlh-scale)); text-align: right; font-size: calc(13px * var(--wlh-scale)); font-weight: 700;',
        '  color: #e9dfcc; text-shadow: 0 1px 2px #000; font-variant-numeric: tabular-nums; }',
        '.is-thin .wlh-plate__value { font-size: calc(12px * var(--wlh-scale)); }',
        '.wlh-plate.is-critical { border-color: #7a1a12; box-shadow: 0 0 14px rgba(210,38,28,0.45), 0 4px 12px rgba(0,0,0,0.6); }',
        '.wlh-plate--health.is-critical .wlh-bar__fill { animation: wlhPulse 0.9s ease-in-out infinite; }',
        // round iron dials
        '.wlh-row { display: flex; gap: calc(7px * var(--wlh-scale)); justify-content: flex-start; }',
        '.wlh-root.is-vertical .wlh-row { flex-direction: column; align-items: flex-end; }',
        '.wlh-root.is-vertical .wlh-badges { flex-direction: column; align-items: flex-end; }',
        '.wlh-dial { position: relative; width: calc(46px * var(--wlh-scale)); height: calc(46px * var(--wlh-scale)); border-radius: 50%; --c: var(--wlh-ok);',
        '  background: radial-gradient(circle at 35% 30%, #4a4036, #1d1915 62%, #0f0d0b);',
        '  border: 2px solid #4f4133; box-shadow: 0 4px 10px rgba(0,0,0,0.65), inset 0 1px 1px rgba(255,230,190,0.15), inset 0 -3px 6px rgba(0,0,0,0.6); }',
        // four rivets around the rim
        '.wlh-dial::before { content: ""; position: absolute; inset: -1px; border-radius: 50%; pointer-events: none;',
        '  background: radial-gradient(circle at 50% 4%, #a08c70 0 1.6px, transparent 2.2px), radial-gradient(circle at 50% 96%, #a08c70 0 1.6px, transparent 2.2px),',
        '    radial-gradient(circle at 4% 50%, #a08c70 0 1.6px, transparent 2.2px), radial-gradient(circle at 96% 50%, #a08c70 0 1.6px, transparent 2.2px); }',
        '.wlh-ring { position: absolute; inset: 0; width: 100%; height: 100%; transform: rotate(-90deg); }',
        '.wlh-ring__track { fill: none; stroke: rgba(0,0,0,0.55); stroke-width: 4; }',
        '.wlh-ring__fill { fill: none; stroke: var(--c); stroke-width: 4; stroke-linecap: round; filter: drop-shadow(0 0 2px var(--c));',
        '  transition: stroke-dashoffset 0.5s ease, stroke 0.3s; }',
        '.wlh-dial__face { position: absolute; inset: 22%; display: grid; place-items: center; border-radius: 50%; color: var(--c);',
        '  background: radial-gradient(circle at 40% 35%, #2a241e, #0e0c0a); box-shadow: inset 0 1px 3px rgba(0,0,0,0.8); }',
        '.wlh-glyph { width: 78%; height: 78%; overflow: visible; filter: drop-shadow(0 0 3px var(--c, currentColor)); }',
        '.wlh-g-fill { fill: currentColor; }',
        '.wlh-g-stroke { fill: none; stroke: currentColor; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }',
        '.wlh-g-text { fill: #120f0c; font-size: 8px; font-weight: 800; font-family: Arial, sans-serif; }',
        // colours per stat
        '.wlh-dial--food { --c: #e0912f; } .wlh-dial--drink { --c: #3fb5c9; } .wlh-dial--temp { --c: #cfe3ea; } .wlh-dial--temp.is-hot { --c: #ff7a3c; }',
        '.wlh-dial--pee { --c: #d8c63a; } .wlh-dial--poop { --c: #a0703e; }',
        '.wlh-dial.is-low { --c: var(--wlh-low); border-color: #6b4f22; }',
        '.wlh-dial.is-critical { --c: var(--wlh-critical); border-color: #7a1a12; animation: wlhGlow 1s ease-in-out infinite; }',
        '@keyframes wlhPulse { 50% { opacity: 0.55; } }',
        '@keyframes wlhGlow { 50% { box-shadow: 0 0 16px rgba(210,38,28,0.75), 0 4px 10px rgba(0,0,0,0.65), inset 0 -3px 6px rgba(0,0,0,0.6); } }',
        // bleeding / infection tags
        '.wlh-badges { display: flex; gap: 6px; }',
        '.wlh-badge { font-size: 11px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; padding: 3px 9px; border-radius: 4px;',
        '  background: linear-gradient(180deg, #2a231d, #120f0c); text-shadow: 0 1px 2px #000; box-shadow: 0 3px 8px rgba(0,0,0,0.5); }',
        '.wlh-badge--bleeding { color: #ff6b5e; border: 1px solid #8a1d14; }',
        '.wlh-badge--bleeding::before { content: "\\25CF  "; color: #d2261c; }',
        '.wlh-badge--infection { color: #a6e06a; border: 1px solid #4f7a2a; }',
        '.wlh-badge--infection::before { content: "\\2623  "; }',
        '.wlh-info { display: flex; gap: 10px; align-items: baseline; font-size: calc(17px * var(--wlh-scale)); color: #efe6d4; font-weight: 600;',
        '  text-shadow: 0 1px 2px #000, 0 0 6px rgba(0,0,0,0.6); white-space: nowrap; letter-spacing: 0.03em; }',
        '.wlh-info__id { color: #d99a2b; font-weight: 700; }',
        '.wlh-info__cash { color: #9be27a; font-weight: 700; font-variant-numeric: tabular-nums; }',
        '.wlh-stamina { position: absolute; left: 50%; bottom: 2.2vh; width: 200px; height: 6px; transform: translateX(-50%);',
        '  background: #0a0807; border: 1px solid #4a3d2e; border-radius: 3px; overflow: hidden; box-shadow: 0 2px 6px rgba(0,0,0,0.6);',
        '  opacity: 0; transition: opacity 0.6s ease 0.8s; pointer-events: none; }',
        '.wlh-stamina.is-visible { opacity: 1; transition: opacity 0.15s ease; }',
        '.wlh-stamina__fill { height: 100%; width: 100%; background: linear-gradient(180deg, #efe6d2, #a89c84); box-shadow: 0 0 6px rgba(239,230,210,0.4); transition: width 0.15s linear; }',
        '.wlh-stamina.is-low .wlh-stamina__fill { background: linear-gradient(180deg, #f0b44a, #b06e14); }',
        // ---- body style
        '.wlh-bodyhud { display: flex; align-items: center; gap: calc(4px * var(--wlh-scale)); }',
        '.wlh-bodyhud__left { position: relative; width: calc(132px * var(--wlh-scale)); height: calc(274px * var(--wlh-scale)); }',
        '.wlh-bodyhud__minis { position: absolute; left: 0; top: 0; display: flex; gap: calc(5px * var(--wlh-scale)); z-index: 1; }',
        '.wlh-portrait { position: absolute; left: calc(14px * var(--wlh-scale)); top: calc(46px * var(--wlh-scale)); width: calc(104px * var(--wlh-scale));',
        '  height: calc(226px * var(--wlh-scale)); }',
        '.wlh-portrait__img, .wlh-portrait__tint { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: contain; object-position: center bottom; }',
        '.wlh-portrait__img { filter: drop-shadow(0 3px 6px rgba(0,0,0,0.85)); }',
        '.wlh-portrait__tint { opacity: 0; transition: opacity 0.4s; -webkit-mask-size: contain; mask-size: contain;',
        '  -webkit-mask-repeat: no-repeat; mask-repeat: no-repeat; -webkit-mask-position: center bottom; mask-position: center bottom; }',
        '.wlh-portrait__blood { background: #c8150c; mix-blend-mode: multiply; } .wlh-portrait__infection { background: #6fbf2c; mix-blend-mode: multiply; }',
        '.wlh-portrait.is-hurt .wlh-portrait__blood { opacity: 0.35; }',
        '.wlh-portrait.is-bleeding .wlh-portrait__blood { animation: wlhBleed2 1.4s ease-in-out infinite; }',
        '.wlh-portrait.is-bleeding-3 .wlh-portrait__blood { animation-duration: 0.7s; }',
        '.wlh-portrait.is-infected .wlh-portrait__infection { opacity: 0.4; }',
        '@keyframes wlhBleed2 { 0%, 100% { opacity: 0.25; } 50% { opacity: 0.8; } }',
        '.wlh-bodyhud__arc { display: flex; flex-direction: column; gap: calc(6px * var(--wlh-scale)); }',
        '.wlh-gauge, .wlh-mini { position: relative; display: grid; place-items: center; --c1: #8fe3ff; --c2: #2c7be5; }',
        '.wlh-gauge { width: calc(58px * var(--wlh-scale)); height: calc(58px * var(--wlh-scale)); }',
        '.wlh-mini { width: calc(40px * var(--wlh-scale)); height: calc(40px * var(--wlh-scale)); }',
        '.wlh-gauge__ring { position: absolute; inset: 0; width: 100%; height: 100%; overflow: visible; }',
        '.wlh-arc__track { fill: none; stroke: rgba(0,0,0,0.55); stroke-linecap: round; }',
        '.wlh-arc__fill { fill: none; stroke: var(--c2); stroke-linecap: round; filter: drop-shadow(0 0 2px var(--c1)); transition: stroke-dasharray 0.5s ease; }',
        '.wlh-gauge .wlh-arc__fill, .wlh-mini .wlh-arc__fill { stroke: var(--c1); }',
        '.wlh-gauge::before, .wlh-mini::before { content: ""; position: absolute; inset: 14%; border-radius: 50%;',
        '  background: radial-gradient(circle at 40% 35%, rgba(40,40,38,0.85), rgba(8,8,8,0.9)); box-shadow: inset 0 1px 3px rgba(0,0,0,0.8); }',
        '.wlh-gauge__face, .wlh-mini__face { position: relative; display: flex; flex-direction: column; align-items: center; justify-content: center;',
        '  color: #f3f3ee; line-height: 1; }',
        '.wlh-gauge__face .wlh-glyph { width: calc(20px * var(--wlh-scale)); height: calc(20px * var(--wlh-scale)); filter: drop-shadow(0 1px 2px #000); }',
        '.wlh-mini__face .wlh-glyph { width: calc(17px * var(--wlh-scale)); height: calc(17px * var(--wlh-scale)); filter: drop-shadow(0 1px 2px #000); }',
        '.wlh-gauge__val { margin-top: calc(1px * var(--wlh-scale)); font-size: calc(11px * var(--wlh-scale)); font-weight: 700; color: #f3f3ee;',
        '  text-shadow: 0 1px 2px #000; font-family: Arial, sans-serif; }',
        // each stat its own colour; low turns amber, critical red
        '.wlh-gauge--health { --c1: #e0352b; } .wlh-gauge--stamina { --c1: #2448b8; } .wlh-gauge--food { --c1: #8a5a2b; } .wlh-gauge--drink { --c1: #1d3f9e; }',
        '.wlh-gauge.is-low { --c1: #f2b24a; } .wlh-gauge.is-critical { --c1: #ff4a3d; animation: wlhPulse 0.9s ease-in-out infinite; }',
        '.wlh-gauge--health.is-critical { --c1: #ff2a1a; }',
        '.wlh-mini--armor { --c1: #a9c7da; } .wlh-mini--armor .wlh-arc__fill.is-plates { stroke: #e0b84f; filter: drop-shadow(0 0 2px #e0b84f); }',
        '.wlh-mini--armor .wlh-mini__face { color: #a9c7da; }',
        '.wlh-mini.is-none { opacity: 0.45; }',
        '.wlh-noise { display: flex; flex-direction: column; align-items: center; gap: 1px; }',
        '.wlh-mini--noise { --c1: #e8e8e2; } .wlh-mini--noise.is-low { --c1: #cfe3a0; } .wlh-mini--noise.is-noticeable { --c1: #f0d24a; }',
        '.wlh-mini--noise.is-loud { --c1: #f08a2c; } .wlh-mini--noise.is-deafening { --c1: #ff3b2e; }',
        '.wlh-mini--noise.is-talking .wlh-mini__face { color: #7fe36a; } .wlh-mini--noise.is-talking::before { box-shadow: 0 0 10px rgba(127,227,106,0.6), inset 0 1px 3px rgba(0,0,0,0.8); }',
        '.wlh-noise__word { font-size: calc(8px * var(--wlh-scale)); font-weight: 800; letter-spacing: 0.08em; color: #e8e8e2; text-shadow: 0 1px 2px #000; font-family: Arial, sans-serif; }',
        '.wlh-noise__word.is-noticeable { color: #f0d24a; } .wlh-noise__word.is-loud { color: #f08a2c; } .wlh-noise__word.is-deafening { color: #ff3b2e; }',
        '.wlh-bodyhud__small { justify-content: flex-end; }',
        '.wlh-dial--voice { --c: #e8e8e2; } .wlh-dial--voice.is-talking { --c: #7fe36a; box-shadow: 0 0 12px rgba(127,227,106,0.7), 0 4px 10px rgba(0,0,0,0.65); }',
        '.wlh-bodyhud__small .wlh-dial { width: calc(36px * var(--wlh-scale)); height: calc(36px * var(--wlh-scale)); }',
        '.wlh-tb { position: absolute; top: 3vh; left: 50%; transform: translateX(-50%); display: flex; flex-wrap: wrap; justify-content: center;',
        '  gap: 10px 16px; max-width: 92vw; padding: 10px 14px; background: var(--wl-bg); border: 1px solid var(--wl-border);',
        '  border-radius: var(--wl-radius); box-shadow: 0 10px 30px rgba(0,0,0,0.5); pointer-events: auto; }',
        '.wlh-tb__title { width: 100%; text-align: center; font-size: 13px; color: var(--wl-text-dim); }',
        '.wlh-tb__group { display: flex; align-items: center; gap: 6px; }',
        '.wlh-tb__label { font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--wl-text-dim); margin-right: 2px; }',
    ].join('\n');
})();
